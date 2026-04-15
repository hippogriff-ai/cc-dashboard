#!/usr/bin/env python3
"""
cc-dashboard — local web dashboard for managing many Claude Code terminal windows.

Two views on the same data pipeline:
  - Live: ranked inbox of live sessions (Agents-as-Inbox)
  - Restore: recent sessions per repo with a "where I left off" panel

Zero-install: stdlib only. Run with `python3 server.py` and open http://localhost:7777
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
SESSIONS_DIR = CLAUDE_DIR / "sessions"
PROJECTS_DIR = CLAUDE_DIR / "projects"
HISTORY_FILE = CLAUDE_DIR / "history.jsonl"
TODOS_DIR = CLAUDE_DIR / "todos"
PORT = 7777
SCRIPT_DIR = Path(__file__).resolve().parent


# ─────────────────────────── helpers ───────────────────────────
def cwd_to_encoded(cwd: str) -> str:
    """Encode cwd to projects subdir name. Replaces / and . with -."""
    return re.sub(r"[/.]", "-", cwd)


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def read_jsonl_tail(path: Path, n: int = 200):
    """Read last n lines of a jsonl file."""
    if not path.exists():
        return []
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            chunk = min(size, 256 * 1024)
            f.seek(size - chunk)
            data = f.read().decode("utf-8", errors="replace")
    except Exception:
        return []
    lines = [l for l in data.splitlines() if l.strip()]
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except Exception:
            pass
    return out


def is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False
    except Exception:
        return False


def git_info(cwd: str) -> dict:
    info = {"branch": None, "dirty": 0, "last_commit": None}
    if not Path(cwd).is_dir():
        return info
    try:
        branch = subprocess.run(
            ["git", "-C", cwd, "branch", "--show-current"],
            capture_output=True, text=True, timeout=1.5,
        )
        if branch.returncode == 0:
            info["branch"] = branch.stdout.strip() or None
        status = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain"],
            capture_output=True, text=True, timeout=1.5,
        )
        if status.returncode == 0:
            info["dirty"] = len([l for l in status.stdout.splitlines() if l.strip()])
        log = subprocess.run(
            ["git", "-C", cwd, "log", "-1", "--pretty=%h %s"],
            capture_output=True, text=True, timeout=1.5,
        )
        if log.returncode == 0:
            info["last_commit"] = log.stdout.strip() or None
    except Exception:
        pass
    return info


# ─────────────────── transcript → structured event ───────────────────
def find_transcript(cwd: str, sid: str) -> Path | None:
    enc = cwd_to_encoded(cwd)
    p = PROJECTS_DIR / enc / f"{sid}.jsonl"
    if p.exists():
        return p
    # fallback: search by sid anywhere
    candidates = list(PROJECTS_DIR.glob(f"*/{sid}.jsonl"))
    return candidates[0] if candidates else None


def last_turns(transcript: list[dict], k: int = 12) -> list[dict]:
    """Filter to main-thread user/assistant turns, return last k."""
    turns = [
        t for t in transcript
        if t.get("type") in ("user", "assistant")
        and not t.get("isSidechain", False)
        and isinstance(t.get("message"), dict)
    ]
    return turns[-k:]


def extract_text(msg_content) -> str:
    """Extract plain text from message.content (string or list of blocks)."""
    if isinstance(msg_content, str):
        return msg_content
    if isinstance(msg_content, list):
        parts = []
        for block in msg_content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                parts.append(block.get("text", ""))
            elif block.get("type") == "tool_use":
                name = block.get("name", "?")
                parts.append(f"[tool: {name}]")
        return "\n".join(parts)
    return ""


def classify(transcript: list[dict], alive: bool) -> dict:
    """Return {event, priority, reason, last_user, last_assistant, open_tool}.

    Classification rule: the event reflects the state of the LAST turn only,
    not cumulative history. A tool error from 20 turns ago that Claude has
    since responded to is not 'failing' — it's resolved. Only classify as
    TOOL_FAILED if the very last turn is an unresolved error with no
    assistant response after it.
    """
    turns = last_turns(transcript, k=20)
    last_user_text = None
    last_assistant_text = None
    open_tool = None

    # First pass: capture the most recent user/assistant text for the side
    # panel display. These are historical context, not classification inputs.
    for t in turns:
        m = t.get("message", {})
        role = m.get("role")
        content = m.get("content")
        if role == "user":
            if isinstance(content, str):
                last_user_text = content
            elif isinstance(content, list):
                txts = [b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text"]
                if txts:
                    last_user_text = "\n".join(txts)
        elif role == "assistant":
            text = extract_text(content)
            if text:
                last_assistant_text = text

    # Default: nothing pending
    event = "CLEAR"
    reason = ""
    priority = 99
    if not turns:
        return {
            "event": event, "reason": reason, "priority": priority,
            "last_user": "", "last_assistant": "", "open_tool": None,
        }

    # Classify based on the LAST turn only.
    last = turns[-1]
    m = last.get("message", {}) if isinstance(last.get("message"), dict) else {}
    role = m.get("role")
    content = m.get("content")

    if role == "assistant":
        # Walk the last assistant content for open tool_use + text
        has_open_tool = False
        text_parts: list[str] = []
        if isinstance(content, list):
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    has_open_tool = True
                    open_tool = {"name": b.get("name"), "id": b.get("id")}
                elif b.get("type") == "text":
                    text_parts.append(b.get("text", ""))
        elif isinstance(content, str):
            text_parts.append(content)
        text = "\n".join(text_parts).strip()

        if has_open_tool and alive:
            event = "WORKING"
            reason = f"running {open_tool['name'] if open_tool else 'tool'}"
            priority = 90
        elif text and text.rstrip().endswith("?"):
            event = "ASK"
            reason = text.strip().split("\n")[-1][:180]
            priority = 20
        else:
            # Last turn is an assistant message — even if a historical
            # tool error exists in earlier turns, the assistant has
            # moved past it. This session is idle waiting for the user.
            event = "IDLE_AFTER_COMPLETE"
            reason = "ready for next instruction"
            priority = 40

    elif role == "user":
        # Last turn is a user turn. Two sub-cases:
        # (a) it's a real user prompt → claude is processing
        # (b) it's a tool_result with is_error and claude hasn't responded
        is_error_result = False
        error_detail = ""
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
                    is_error_result = True
                    res = b.get("content", "")
                    if isinstance(res, list):
                        res = " ".join(x.get("text", "") for x in res if isinstance(x, dict))
                    error_detail = str(res)[:200]
                    break
        if is_error_result:
            event = "TOOL_FAILED"
            reason = f"tool error: {error_detail[:100]}"
            priority = 10
        else:
            event = "WORKING" if alive else "CLEAR"
            reason = "processing..."
            priority = 85

    return {
        "event": event,
        "reason": reason,
        "priority": priority,
        "last_user": (last_user_text or "")[:400],
        "last_assistant": (last_assistant_text or "")[:800],
        "open_tool": open_tool,
    }


# ─────────────────────────── build views ───────────────────────────
def load_live_sessions() -> list[dict]:
    """Scan ~/.claude/sessions/*.json → enrich with transcript classification."""
    out = []
    if not SESSIONS_DIR.exists():
        return out
    for sf in SESSIONS_DIR.glob("*.json"):
        data = read_json(sf)
        if not data or data.get("kind") != "interactive":
            continue
        pid = data.get("pid")
        sid = data.get("sessionId")
        cwd = data.get("cwd", "")
        started = data.get("startedAt", 0)
        alive = is_pid_alive(pid) if pid else False
        if not alive:
            continue
        tp = find_transcript(cwd, sid)
        transcript = read_jsonl_tail(tp, 300) if tp else []
        meta = classify(transcript, alive=True)
        gi = git_info(cwd)
        tp_mtime = tp.stat().st_mtime if tp else (started / 1000)
        # Staleness decay: events lose urgency over time. A TOOL_FAILED
        # from 9 hours ago should not rank above a fresh IDLE. After 30
        # minutes of no activity we add a decay penalty to priority (higher
        # number = less urgent). Fresh sessions (< 5 min) are untouched.
        age_sec = max(0.0, time.time() - tp_mtime)
        decay = 0
        if age_sec > 300:  # 5 min grace period
            # Linear decay: +10 priority per hour after the grace period,
            # capped at 60 so stale urgent events still rank above CLEAR.
            decay = min(60, int((age_sec - 300) / 360))  # 360s = 10pt/hr
        out.append({
            "pid": pid,
            "sessionId": sid,
            "cwd": cwd,
            "repo": Path(cwd).name,
            "branch": gi["branch"],
            "dirty": gi["dirty"],
            "started_at": started,
            "last_activity": tp_mtime * 1000,
            "age_sec": int(age_sec),
            "stale_decay": decay,
            "transcript_found": tp is not None,
            **meta,
            "priority": meta["priority"] + decay,
        })
    # Sort by (priority asc, last_activity desc). Lower priority number = more urgent.
    out.sort(key=lambda s: (s["priority"], -s["last_activity"]))
    return out


def load_recent_by_repo(days: int = 14) -> list[dict]:
    """Scan all transcripts, group by cwd, return most recent per repo."""
    cutoff = time.time() - days * 86400
    by_cwd: dict[str, dict] = {}
    if not PROJECTS_DIR.exists():
        return []
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        name = project_dir.name
        # Skip temp/test repos
        if "-private-var-folders-" in name or "test-repo" in name:
            continue
        for jf in project_dir.glob("*.jsonl"):
            try:
                mt = jf.stat().st_mtime
            except Exception:
                continue
            if mt < cutoff:
                continue
            # Try to derive cwd from first turn's cwd field; fall back to decoding name
            first_cwd = None
            try:
                with open(jf, "r") as f:
                    for line in f:
                        try:
                            obj = json.loads(line)
                        except Exception:
                            continue
                        if isinstance(obj, dict) and obj.get("cwd"):
                            first_cwd = obj["cwd"]
                            break
            except Exception:
                pass
            cwd = first_cwd or ("/" + name.lstrip("-").replace("-", "/"))
            sid = jf.stem
            entry = by_cwd.get(cwd)
            if entry is None or mt > entry["mtime"]:
                by_cwd[cwd] = {
                    "mtime": mt,
                    "sessionId": sid,
                    "transcript": str(jf),
                }
    rows = []
    for cwd, info in by_cwd.items():
        if not Path(cwd).is_dir():
            # cwd no longer exists on disk — skip to reduce noise
            continue
        transcript = read_jsonl_tail(Path(info["transcript"]), 300)
        meta = classify(transcript, alive=False)
        gi = git_info(cwd)
        rows.append({
            "cwd": cwd,
            "repo": Path(cwd).name,
            "branch": gi["branch"],
            "dirty": gi["dirty"],
            "last_commit": gi["last_commit"],
            "sessionId": info["sessionId"],
            "last_activity": info["mtime"] * 1000,
            **meta,
        })
    rows.sort(key=lambda r: -r["last_activity"])
    return rows


def recent_prompts_for_cwd(cwd: str, limit: int = 5) -> list[dict]:
    """Last N user prompts for this cwd from history.jsonl."""
    out = []
    if not HISTORY_FILE.exists():
        return out
    try:
        with open(HISTORY_FILE, "r") as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("project") == cwd:
                    out.append({
                        "display": (obj.get("display") or "")[:400],
                        "timestamp": obj.get("timestamp"),
                    })
    except Exception:
        return out
    return out[-limit:][::-1]


def build_panel(cwd: str, sid: str | None) -> dict:
    """Build the 'where I left off' panel for a given session."""
    tp = None
    if sid:
        tp = find_transcript(cwd, sid)
    transcript = read_jsonl_tail(tp, 400) if tp else []
    meta = classify(transcript, alive=False)
    gi = git_info(cwd)
    prompts = recent_prompts_for_cwd(cwd, 5)

    # Uncommitted diff summary
    diff_summary = None
    try:
        r = subprocess.run(
            ["git", "-C", cwd, "diff", "--stat"],
            capture_output=True, text=True, timeout=2,
        )
        if r.returncode == 0 and r.stdout.strip():
            diff_summary = r.stdout.strip()[:2000]
    except Exception:
        pass

    return {
        "cwd": cwd,
        "repo": Path(cwd).name,
        "sessionId": sid,
        "transcript_found": tp is not None,
        "git": gi,
        "diff_summary": diff_summary,
        "recent_prompts": prompts,
        "last_user": meta["last_user"],
        "last_assistant": meta["last_assistant"],
        "event": meta["event"],
        "reason": meta["reason"],
        "open_tool": meta["open_tool"],
    }


# ─────────────────────────── focus / resume actions ───────────────────────────
import unicodedata

_STOPWORDS = {
    "the","a","an","is","are","was","were","to","of","for","in","on","at","by",
    "and","or","i","me","my","you","we","it","this","that","from","with","can",
    "how","what","do","does","be","been","has","have","had","will","would","should",
    "but","not","if","so","as","about","into","out","up","down","over","under",
    "just","please","want","need","here","there","now","then","some","any","all",
    "new","like","get","got","let","make","made","use","used","using","way","one",
}


def _tokenize(text: str) -> set[str]:
    """Normalize text and return a set of content words for scoring."""
    if not text:
        return set()
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    # Strip URL percent-encoding first (%20 → space) so we don't end up with
    # junk tokens like "20agent" when a markdown link contains encoded spaces.
    text = re.sub(r"%[0-9a-fA-F]{2}", " ", text)
    text = re.sub(r"[^a-zA-Z0-9\s]", " ", text.lower())
    # Require at least 3 chars, not purely numeric, not a stopword
    return {
        w for w in text.split()
        if len(w) >= 3 and not w.isdigit() and w not in _STOPWORDS
    }


def _list_ghostty_windows() -> dict:
    """Ask System Events for every Ghostty window and its title.
    Requires Ghostty to be activated first so AX sees all current-space windows.
    Returns {windows: [{index, title}], error: str | None}.
    Distinguishes genuine "no windows" from AX permission/timeout errors.
    """
    script = r'''
tell application "System Events"
  tell process "Ghostty"
    set out to ""
    set n to count of windows
    repeat with i from 1 to n
      try
        set t to name of window i
      on error
        set t to ""
      end try
      set out to out & i & "\t" & t & linefeed
    end repeat
    return out
  end tell
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=3,
        )
    except subprocess.TimeoutExpired:
        return {"windows": [], "error": "osascript_timeout"}
    except Exception as e:
        return {"windows": [], "error": f"osascript_failed: {e}"}
    if r.returncode != 0:
        # Most common cause: macOS Accessibility permission not granted
        err = r.stderr.strip() or f"exit {r.returncode}"
        reason = "ax_permission_denied" if "1002" in err or "not allowed" in err.lower() else "list_failed"
        return {"windows": [], "error": f"{reason}: {err[:200]}"}
    windows = []
    for line in r.stdout.splitlines():
        if "\t" not in line:
            continue
        idx_s, title = line.split("\t", 1)
        try:
            windows.append({"index": int(idx_s.strip()), "title": title.strip()})
        except ValueError:
            pass
    return {"windows": windows, "error": None}


def _raise_ghostty_window(index: int) -> bool:
    script = f'''
tell application "System Events"
  tell process "Ghostty"
    try
      perform action "AXRaise" of window {index}
      set frontmost to true
      return "ok"
    on error
      return "err"
    end try
  end tell
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=2,
        )
        return "ok" in r.stdout
    except Exception:
        return False


def _session_prompts(cwd: str, sid: str | None) -> tuple[list[str], list[str]]:
    """Extract user prompts from a session, split into (early, recent).
    Ghostty window titles are set VERY early in a session (first real prompt)
    and stay sticky, so the first few prompts are worth ~3x more for matching
    than later prompts. Returns (first_5_prompts, last_3_prompts).
    """
    if not sid:
        return [], []
    tp = find_transcript(cwd, sid)
    if not tp or not tp.exists():
        return [], []
    all_prompts: list[str] = []
    try:
        with open(tp, "r") as f:
            for line in f:
                if '"type":"user"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("isSidechain"):
                    continue
                msg = obj.get("message", {})
                if not isinstance(msg, dict) or msg.get("role") != "user":
                    continue
                content = msg.get("content")
                text = None
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "text":
                            text = b.get("text", "")
                            break
                if not text:
                    continue
                # Skip Claude Code's automated IDE selection turns and tool_result wrappers
                if text.startswith("<ide_selection>") or text.startswith("<system-reminder>"):
                    continue
                text = text.strip()
                if text:
                    all_prompts.append(text[:500])
    except Exception:
        pass
    if not all_prompts:
        return [], []
    early = all_prompts[:5]
    recent = all_prompts[-3:] if len(all_prompts) > 5 else []
    return early, recent


def _score_window(window_tokens: set[str], early_tokens: set[str],
                  recent_tokens: set[str], cwd_tokens: set[str]) -> dict:
    """Weighted token overlap. Early prompts dominate, cwd name is a tiebreaker.
    Weights: early=3, recent=1, cwd=2. Total score is sum of weighted overlaps.
    """
    early_hit = window_tokens & early_tokens
    recent_hit = window_tokens & recent_tokens
    cwd_hit = window_tokens & cwd_tokens
    # Avoid double-counting tokens that appear in multiple buckets
    counted = set()
    score = 0
    for tok in early_hit:
        if tok not in counted:
            score += 3
            counted.add(tok)
    for tok in cwd_hit:
        if tok not in counted:
            score += 2
            counted.add(tok)
    for tok in recent_hit:
        if tok not in counted:
            score += 1
            counted.add(tok)
    return {
        "score": score,
        "hits": sorted(counted),
        "early_hits": sorted(early_hit),
        "recent_hits": sorted(recent_hit - early_hit),
        "cwd_hits": sorted(cwd_hit - early_hit),
    }


def focus_ghostty(cwd: str, sid: str | None = None) -> dict:
    """Find and raise the Ghostty window that owns this Claude Code session.

    Strategy: activate Ghostty so all current-space windows become AX-visible,
    list every window title via System Events, then pick the window whose
    title overlaps most strongly (weighted by word-position in the session)
    with the target session's early user prompts. Ghostty titles are sticky
    to early topics so early prompts dominate. We require score >= 5 and a
    gap of >= 3 over the runner-up to declare a confident match.
    """
    early_prompts, recent_prompts = _session_prompts(cwd, sid)
    early_tokens = _tokenize(" ".join(early_prompts))
    recent_tokens = _tokenize(" ".join(recent_prompts))
    cwd_tokens = _tokenize(Path(cwd).name.replace("-", " ").replace("_", " "))

    # Activate Ghostty. If activation fails (Ghostty not installed, not
    # running and failing to launch, osascript timeout), return a distinct
    # reason so the frontend can surface it rather than pretending no window
    # matched.
    try:
        act = subprocess.run(
            ["osascript", "-e", 'tell application "Ghostty" to activate'],
            capture_output=True, text=True, timeout=2,
        )
        if act.returncode != 0:
            return {
                "ok": False,
                "matched": False,
                "reason": "ghostty_activate_failed",
                "detail": (act.stderr or "").strip()[:200],
            }
    except subprocess.TimeoutExpired:
        return {"ok": False, "matched": False, "reason": "ghostty_activate_timeout"}
    except Exception as e:
        return {"ok": False, "matched": False, "reason": "ghostty_activate_failed", "detail": str(e)}

    time.sleep(0.25)  # let AX catch up after activation
    win_result = _list_ghostty_windows()
    if win_result.get("error"):
        return {
            "ok": False,
            "matched": False,
            "reason": win_result["error"].split(":", 1)[0],
            "detail": win_result["error"],
        }
    windows = win_result["windows"]

    # Score each window's title
    scored = []
    for w in windows:
        title_tokens = _tokenize(w["title"])
        s = _score_window(title_tokens, early_tokens, recent_tokens, cwd_tokens)
        scored.append({**w, "title_tokens": sorted(title_tokens), **s})
    scored.sort(key=lambda x: -x["score"])

    best = scored[0] if scored else None
    second = scored[1] if len(scored) > 1 else None
    second_score = second["score"] if second else 0

    # Confidence rule: absolute score >= 5 AND margin over runner-up >= 3
    MIN_SCORE = 5
    MIN_MARGIN = 3
    confident = (
        best is not None
        and best["score"] >= MIN_SCORE
        and (best["score"] - second_score) >= MIN_MARGIN
    )

    if confident:
        raised = _raise_ghostty_window(best["index"])
        return {
            "ok": True,
            "matched": raised,
            "window_index": best["index"],
            "matched_title": best["title"],
            "score": best["score"],
            "margin": best["score"] - second_score,
            "hits": best["hits"],
            "all_windows": scored,
        }

    return {
        "ok": True,
        "matched": False,
        "reason": "no_confident_match",
        "best_score": best["score"] if best else 0,
        "second_score": second_score,
        "best_candidate": best,
        "early_tokens": sorted(early_tokens),
        "all_windows": scored,
    }


def resume_command(cwd: str, sid: str | None) -> dict:
    """Build a resume command and copy it to clipboard."""
    parts = [f"cd {shlex.quote(cwd)}"]
    if sid:
        parts.append(f"claude --resume {sid}")
    else:
        parts.append("claude --continue")
    cmd = " && ".join(parts)
    try:
        subprocess.run(["pbcopy"], input=cmd.encode(), timeout=2)
        copied = True
    except Exception:
        copied = False
    return {"command": cmd, "copied_to_clipboard": copied}


_IDE_PRIORITY = [
    # (app-bundle name in /Applications, display name)
    ("Cursor", "Cursor"),
    ("Visual Studio Code", "VS Code"),
    ("Zed", "Zed"),
    ("Windsurf", "Windsurf"),
    ("Sublime Text", "Sublime Text"),
    ("WebStorm", "WebStorm"),
    ("PyCharm", "PyCharm"),
    ("GoLand", "GoLand"),
    ("Rider", "Rider"),
    ("CLion", "CLion"),
    ("Xcode", "Xcode"),
]


def _detect_ide() -> tuple[str, str]:
    """Return (app_bundle_name, display_name) of the preferred IDE.
    Honors CC_DASH_IDE env var for override, otherwise walks _IDE_PRIORITY
    checking /Applications for each. Falls back to ("", "Finder") which
    means `open` with no -a argument (opens the folder in Finder).
    """
    override = os.environ.get("CC_DASH_IDE", "").strip()
    if override:
        return (override, override)
    apps_dir = Path("/Applications")
    for bundle, display in _IDE_PRIORITY:
        if (apps_dir / f"{bundle}.app").exists():
            return (bundle, display)
    return ("", "Finder")


def open_in_ide(cwd: str) -> dict:
    """Launch the detected IDE pointed at cwd."""
    if not cwd or not Path(cwd).is_dir():
        return {"ok": False, "error": "cwd_not_a_directory", "cwd": cwd}
    bundle, display = _detect_ide()
    cmd = ["open"]
    if bundle:
        cmd += ["-a", bundle]
    cmd += [cwd]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "open_timeout", "ide": display}
    except Exception as e:
        return {"ok": False, "error": str(e), "ide": display}
    if r.returncode != 0:
        return {
            "ok": False,
            "error": "open_failed",
            "ide": display,
            "detail": (r.stderr or "").strip()[:200],
        }
    return {"ok": True, "ide": display, "cwd": cwd}


def fork_summary(cwd: str, sid: str | None) -> dict:
    """Build a markdown summary to paste into a fresh claude session."""
    panel = build_panel(cwd, sid)
    lines = [
        f"# Resuming work in `{panel['repo']}`",
        f"**Branch**: {panel['git']['branch'] or 'n/a'}  ",
        f"**Uncommitted files**: {panel['git']['dirty']}  ",
        f"**Last commit**: {panel['git']['last_commit'] or 'n/a'}",
        "",
        "## What I was working on (recent prompts)",
    ]
    for p in panel["recent_prompts"]:
        lines.append(f"- {p['display']}")
    if panel["last_assistant"]:
        lines += ["", "## Claude's last message", "```", panel["last_assistant"][:1500], "```"]
    if panel["open_tool"]:
        lines += ["", f"## Open tool at session end", f"- {panel['open_tool'].get('name')}"]
    if panel["diff_summary"]:
        lines += ["", "## Git diff stat", "```", panel["diff_summary"], "```"]
    lines += ["", "Pick up from here — please continue where we left off."]
    summary = "\n".join(lines)
    try:
        subprocess.run(["pbcopy"], input=summary.encode(), timeout=2)
        copied = True
    except Exception:
        copied = False
    return {"summary": summary, "copied_to_clipboard": copied}


# ─────────────────────────── HTTP server ───────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # quiet

    def _json(self, status: int, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _file(self, path: Path, ctype: str):
        if not path.exists():
            self._json(404, {"error": "not found"})
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            qs = urllib.parse.parse_qs(parsed.query)
            if path == "/" or path == "/index.html":
                self._file(SCRIPT_DIR / "index.html", "text/html; charset=utf-8")
            elif path == "/api/live":
                _, ide_name = _detect_ide()
                self._json(200, {
                    "sessions": load_live_sessions(),
                    "ide": ide_name,
                    "ts": time.time(),
                })
            elif path == "/api/recent":
                days = int(qs.get("days", ["14"])[0])
                _, ide_name = _detect_ide()
                self._json(200, {
                    "repos": load_recent_by_repo(days),
                    "ide": ide_name,
                    "ts": time.time(),
                })
            elif path == "/api/panel":
                cwd = qs.get("cwd", [""])[0]
                sid = qs.get("sid", [""])[0] or None
                if not cwd:
                    self._json(400, {"error": "cwd required"}); return
                self._json(200, build_panel(cwd, sid))
            else:
                self._json(404, {"error": "not found"})
        except Exception as e:
            tb = traceback.format_exc()
            sys.stderr.write(f"[do_GET {self.path}] {tb}\n")
            try:
                self._json(500, {"error": str(e), "trace": tb})
            except Exception:
                pass  # connection already dead; nothing to do

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length)) if length else {}
            except Exception:
                body = {}
            path = urllib.parse.urlparse(self.path).path
            if path == "/api/focus":
                cwd = body.get("cwd", "")
                sid = body.get("sid") or None
                if not cwd:
                    self._json(400, {"error": "cwd required"}); return
                self._json(200, focus_ghostty(cwd, sid))
            elif path == "/api/resume":
                self._json(200, resume_command(body.get("cwd", ""), body.get("sid")))
            elif path == "/api/fork":
                self._json(200, fork_summary(body.get("cwd", ""), body.get("sid")))
            elif path == "/api/open-ide":
                cwd = body.get("cwd", "")
                if not cwd:
                    self._json(400, {"error": "cwd required"}); return
                self._json(200, open_in_ide(cwd))
            else:
                self._json(404, {"error": "not found"})
        except Exception as e:
            tb = traceback.format_exc()
            sys.stderr.write(f"[do_POST {self.path}] {tb}\n")
            try:
                self._json(500, {"error": str(e), "trace": tb})
            except Exception:
                pass


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    n_sessions = len(list(SESSIONS_DIR.glob("*.json"))) if SESSIONS_DIR.exists() else 0
    n_projects = len([p for p in PROJECTS_DIR.iterdir() if p.is_dir()]) if PROJECTS_DIR.exists() else 0
    print(f"cc-dashboard :{PORT} — {n_sessions} session files, {n_projects} project dirs on disk")
    print(f"Open in browser: open http://localhost:{PORT}")
    try:
        subprocess.Popen(["open", f"http://localhost:{PORT}"])
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")


if __name__ == "__main__":
    main()
