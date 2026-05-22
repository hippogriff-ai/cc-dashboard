// In-process port of the Ghostty focus pipeline that previously lived in
// `backend/src/ghostty/{focus,applescript,tokenize,score}.ts` and was reached
// via `POST /api/focus`. Moved into the Swift app process because the
// Accessibility (UI scripting) grant macOS hands out is per-binary, not per
// app bundle: the bundled bun sidecar that called osascript was a separately-
// attributable child not covered by the user's `cc-dashboard.app` toggle in
// System Settings → Privacy → Accessibility. With the AppleScript invocation
// living in the .app process, the toggle now actually applies to the caller.
//
// Behavioural contract is preserved exactly so `PopoverController.focusViaGhostty`
// — and any reason-string switch in callers — keeps working unchanged:
//   - `activate Ghostty → 250 ms settle → list windows → score against
//      session prompt tokens → raise the best window if confident`
//   - identical `MIN_SCORE = 5`, `MIN_MARGIN = 3` thresholds
//   - identical `ax_permission_denied` / `ghostty_not_running` /
//     `no_confident_match` / `list_failed` reason codes
//
// All AppleScript runs through `NSAppleScript.executeAndReturnError` rather
// than shelling to `osascript`. NSAppleScript is synchronous and can block
// for 5–20 s on cross-Space window raises (Loop 39 observation), so the
// public entry point dispatches on a detached priority-`.userInitiated`
// task to keep the popover responsive.
import Foundation
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "GhosttyFocus")

/// Tracks whether we've already nudged macOS to show the Accessibility prompt
/// this app-launch. AXIsProcessTrustedWithOptions(prompt:true) is the only
/// API that makes macOS register the app in System Settings → Privacy &
/// Security → Accessibility and show the standard "Open System Settings"
/// dialog. NSAppleScript's silent -1743 failure path doesn't trigger it. We
/// fire the prompt at most once per launch so repeat clicks don't spam.
private actor AXPromptOnce {
    private var fired = false
    func tryFire() -> Bool {
        if fired { return false }
        fired = true
        return true
    }
}
private let axPromptOnce = AXPromptOnce()

// MARK: - Public entry point

enum GhosttyFocus {
    /// Mirrors `MIN_SCORE` in the prior `backend/src/ghostty/focus.ts`.
    /// A best-window score below this is treated as "no confident match" —
    /// activating Ghostty without a target raise is preferable to landing on
    /// a wrong window when the matcher's signal is weak.
    private static let minScore = 5
    /// Mirrors `MIN_MARGIN`. Even a high-scoring window is rejected if the
    /// runner-up's score is within `MIN_MARGIN`, because the matcher can't
    /// reliably distinguish two similar candidates from window titles alone.
    private static let minMargin = 3

    /// Find and raise the Ghostty window hosting the session at `cwd`/`sid`.
    /// Returns the same `FocusResult` shape `APIClient.focus(...)` previously
    /// returned, so call-site error handling remains unchanged. Async because
    /// AppleScript I/O happens off the main thread.
    static func focus(cwd: String, sid: String?) async -> FocusResult {
        await Task.detached(priority: .userInitiated) {
            await runFocus(cwd: cwd, sid: sid)
        }.value
    }

    private static func runFocus(cwd: String, sid: String?) async -> FocusResult {
        // If the app isn't AX-trusted, NSAppleScript will silently fail with
        // -1743 and we'd return ax_permission_denied without macOS ever
        // showing the user the standard "Open System Settings" dialog. Fire
        // AXIsProcessTrustedWithOptions(prompt:true) once per launch to (a)
        // register the app in the Accessibility list and (b) surface the
        // system dialog that takes the user there. Returns immediately —
        // the dialog is non-blocking. After this, the focus attempt below
        // still proceeds and still returns ax_permission_denied, but the
        // user now has a one-click path to grant rather than digging
        // through System Settings manually.
        if !AXIsProcessTrusted(), await axPromptOnce.tryFire() {
            let options: NSDictionary = [
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            logger.info("AX not trusted; system prompt requested")
        }

        let prompts = sessionPrompts(cwd: cwd, sid: sid)
        let earlyTokens = tokenize(prompts.early.joined(separator: " "))
        let recentTokens = tokenize(prompts.recent.joined(separator: " "))
        // assistant_last: the most recent assistant text turn. Reflects what
        // the user is *currently* seeing in the terminal — Claude's most
        // recent response, which often includes recap/topic summary after a
        // /compact or /resume. Catches drifted sessions where `early` is
        // stale (a slash-command 26 days ago) and `recent` is empty
        // (transcript has only a couple of human-typed prompts). Weight 2
        // matches cwd: enough to push a window over MIN_SCORE=5 when
        // combined with a single early/cwd hit, but not enough to dominate
        // if early prompts strongly point at a different window.
        let assistantTokens = tokenize(prompts.lastAssistant ?? "")
        // Mirror TS: tokenize the cwd basename with `-`/`_` rewritten to spaces.
        // Without the rewrite, `tokenize` would treat "agent-portal" as a single
        // token and miss the cross-bucket overlap with the prompt tokens.
        let cwdBase = URL(fileURLWithPath: cwd).lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let cwdTokens = tokenize(cwdBase)

        let activate = activateGhostty()
        if !activate.ok {
            return FocusResult(ok: false, matched: false, reason: activate.reason,
                               detail: activate.detail, windowIndex: nil,
                               matchedTitle: nil, score: nil, margin: nil)
        }

        // Allow AX tree to settle after activation. Mirrors the prior 250 ms
        // sleep in `focus.ts`. Could be replaced with an
        // `NSWorkspace.didActivateApplicationNotification` await once we have
        // confidence the notification fires reliably across spaces; keep the
        // fixed sleep for now since it matched prior behaviour exactly.
        try? await Task.sleep(nanoseconds: 250_000_000)

        let windows: [(index: Int, title: String)]
        switch listGhosttyWindows() {
        case .failure(let reason, let detail):
            return FocusResult(ok: false, matched: false, reason: reason, detail: detail,
                               windowIndex: nil, matchedTitle: nil, score: nil, margin: nil)
        case .success(let xs):
            windows = xs
        }

        let scored = windows.map { w -> (index: Int, title: String, result: ScoreResult) in
            let tt = tokenize(w.title)
            let r = scoreWindow(window: tt, early: earlyTokens, recent: recentTokens,
                                cwd: cwdTokens, assistant: assistantTokens)
            return (w.index, w.title, r)
        }.sorted { $0.result.score > $1.result.score }

        guard let best = scored.first else {
            return FocusResult(ok: true, matched: false, reason: "no_confident_match",
                               detail: nil, windowIndex: nil, matchedTitle: nil,
                               score: nil, margin: nil)
        }
        let secondScore = scored.count > 1 ? scored[1].result.score : 0
        let margin = best.result.score - secondScore
        let confident = best.result.score >= minScore && margin >= minMargin

        if confident {
            let raised = raiseGhosttyWindow(index: best.index)
            return FocusResult(
                ok: true,
                matched: raised,
                reason: nil,
                detail: nil,
                windowIndex: best.index,
                matchedTitle: best.title,
                score: best.result.score,
                margin: margin
            )
        }
        return FocusResult(ok: true, matched: false, reason: "no_confident_match",
                           detail: nil, windowIndex: nil, matchedTitle: nil,
                           score: nil, margin: nil)
    }
}

// MARK: - Tokenization (port of backend/src/ghostty/tokenize.ts)

let ghosttyStopwords: Set<String> = [
    "the","a","an","is","are","was","were","to","of","for","in","on","at","by",
    "and","or","i","me","my","you","we","it","this","that","from","with","can",
    "how","what","do","does","be","been","has","have","had","will","would","should",
    "but","not","if","so","as","about","into","out","up","down","over","under",
    "just","please","want","need","here","there","now","then","some","any","all",
    "new","like","get","got","let","make","made","use","used","using","way","one"
]

private let percentEncodingPattern = try! NSRegularExpression(pattern: "%[0-9a-fA-F]{2}")
private let nonAlnumSpacePattern = try! NSRegularExpression(pattern: "[^a-z0-9\\s]")

/// Mirrors `backend/src/ghostty/tokenize.ts` exactly. Internal access so
/// XCTest can exercise it without going through the public focus pipeline.
func tokenize(_ text: String) -> Set<String> {
    if text.isEmpty { return [] }
    // NFKD then drop non-ASCII. Mirrors TS:
    //   `text.normalize("NFKD").replace(/[^\u0000-\u007f]/g, "")`
    // Combining diacritics decompose into separate scalars (non-ASCII) and
    // get filtered, so "café" → "cafe", "résumé" → "resume". Foundation has
    // four normalization variants — use `decomposedStringWithCompatibilityMapping`
    // (NFKD); `precomposed…CompatibilityMapping` is NFKC and would leave
    // "café" composed as a single scalar.
    let nfkd = text.decomposedStringWithCompatibilityMapping
    let asciiOnly = String(nfkd.unicodeScalars.filter { $0.isASCII })

    // Strip URL %-encoding to whitespace BEFORE lowercasing so "%2F" doesn't
    // survive into the token set. Mirrors TS pattern literally.
    let stripped = percentEncodingPattern.stringByReplacingMatches(
        in: asciiOnly,
        range: NSRange(location: 0, length: (asciiOnly as NSString).length),
        withTemplate: " "
    )
    let lower = stripped.lowercased()
    let cleaned = nonAlnumSpacePattern.stringByReplacingMatches(
        in: lower,
        range: NSRange(location: 0, length: (lower as NSString).length),
        withTemplate: " "
    )

    var out: Set<String> = []
    for w in cleaned.split(whereSeparator: { $0.isWhitespace }) {
        let s = String(w)
        guard s.count >= 3 else { continue }
        // After ASCII-only + lowercase + non-alnum-strip, every char is in
        // [a-z0-9]. `\.isNumber` is true for ASCII digits. Pure-numeric tokens
        // are excluded (matches TS `/^\d+$/.test(w)`).
        guard !s.allSatisfy({ $0.isNumber }) else { continue }
        guard !ghosttyStopwords.contains(s) else { continue }
        out.insert(s)
    }
    return out
}

// MARK: - Scoring (port of backend/src/ghostty/score.ts)

struct ScoreResult: Equatable {
    var score: Int
    var hits: [String]
    var earlyHits: [String]
    var recentHits: [String]
    var cwdHits: [String]
    var assistantHits: [String]
}

/// Weights: early = 3, assistant_last = 2, cwd = 2, recent = 1.
/// A token in multiple buckets is counted once at the highest weight; ties
/// are broken by iteration order (early > assistant > cwd > recent), which
/// puts the token in the most-meaningful bucket for the `*Hits` breakdown.
///
/// The `assistant` argument is optional with a default of `[]` so the
/// signature stays callable by tests that only care about the three
/// original buckets. Pass the last assistant turn's tokens to catch
/// "drifted session" cases — see `runFocus` for rationale.
func scoreWindow(window: Set<String>,
                 early: Set<String>,
                 recent: Set<String>,
                 cwd: Set<String>,
                 assistant: Set<String> = []) -> ScoreResult {
    let earlyHit = window.intersection(early)
    let assistantHit = window.intersection(assistant)
    let recentHit = window.intersection(recent)
    let cwdHit = window.intersection(cwd)

    var counted: Set<String> = []
    var score = 0
    for t in earlyHit where !counted.contains(t) { score += 3; counted.insert(t) }
    for t in assistantHit where !counted.contains(t) { score += 2; counted.insert(t) }
    for t in cwdHit where !counted.contains(t) { score += 2; counted.insert(t) }
    for t in recentHit where !counted.contains(t) { score += 1; counted.insert(t) }

    return ScoreResult(
        score: score,
        hits: counted.sorted(),
        earlyHits: earlyHit.sorted(),
        recentHits: recentHit.subtracting(earlyHit).subtracting(assistantHit).sorted(),
        cwdHits: cwdHit.subtracting(earlyHit).subtracting(assistantHit).sorted(),
        assistantHits: assistantHit.subtracting(earlyHit).sorted()
    )
}

// MARK: - Transcript path resolution + prompt extraction
// Port of the relevant slice of `backend/src/claude/{paths,transcript}.ts`.
// Only the early/recent prompt extraction `focus.ts` needed is ported —
// other transcript helpers stay in the backend (they have many TS callers).

/// Mirrors TS `cwdToEncoded`: replace each `/` and `.` with `-`. The TS impl
/// throws on relative paths; Swift returns `nil` from the surrounding
/// `findTranscript` instead, which is the only caller.
/// Detects user-turn prefixes that mark machine-generated content (slash
/// commands, IDE injections, house-keeping reminders) — see `sessionPrompts`
/// for the full rationale + symptom history.
///
/// `internal` (default) access so XCTest can pin the contract directly.
func isMachineGeneratedUserTurn(_ text: String) -> Bool {
    return text.hasPrefix("<ide_selection>")
        || text.hasPrefix("<system-reminder>")
        || text.hasPrefix("<command-")
        || text.hasPrefix("<local-command-")
}

private func cwdToEncoded(_ cwd: String) -> String? {
    guard cwd.hasPrefix("/") else { return nil }
    var result = ""
    result.reserveCapacity(cwd.count)
    for c in cwd {
        result.append(c == "/" || c == "." ? "-" : c)
    }
    return result
}

private func claudeHomeURL() -> URL {
    if let env = ProcessInfo.processInfo.environment["CLAUDE_HOME"] {
        return URL(fileURLWithPath: env)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
}

func findTranscript(cwd: String, sid: String) -> URL? {
    guard let encoded = cwdToEncoded(cwd) else { return nil }
    let url = claudeHomeURL()
        .appendingPathComponent("projects")
        .appendingPathComponent(encoded)
        .appendingPathComponent("\(sid).jsonl")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

/// Read the JSONL transcript for `cwd`/`sid` and return:
///   - `early`: first 5 substantive user prompts
///   - `recent`: last 3 (when there are >5 total)
///   - `lastAssistant`: text content of the latest assistant turn, or nil
///
/// Empty arrays + nil when the transcript is missing or has no prompts.
/// Filters out machine-generated user-turn artifacts on the user side:
///   - `<ide_selection>` — VS Code injects the current editor selection
///   - `<system-reminder>` — Claude Code injects house-keeping reminders
///   - `<command-name>` / `<command-message>` / `<command-args>` /
///     `<command-stdout>` — slash-command wrappers
///   - `<local-command-caveat>` / `<local-command-output>` — local
///     slash-command boilerplate
///
/// All of these tokenize to high-frequency, low-signal words like "command",
/// "name", "message", "clear" that would otherwise dominate the early-prompts
/// token bucket at weight 3 and drown out real topic signal. Observed in the
/// wild: a 26-prompt gbrain session whose top 5 user turns were all
/// slash-command shells; the matcher scored "laser caveat command name" as
/// the session's "topic" and missed every window with the actual project's
/// vocabulary in the title.
///
/// For assistant turns, only `text` blocks are concatenated (thinking and
/// tool_use blocks are skipped — those aren't visible-to-user content and
/// would pollute tokens with tool names).
func sessionPrompts(cwd: String, sid: String?) -> (early: [String], recent: [String], lastAssistant: String?) {
    guard let sid, !sid.isEmpty,
          let tp = findTranscript(cwd: cwd, sid: sid),
          let raw = try? String(contentsOf: tp, encoding: .utf8)
    else {
        return ([], [], nil)
    }
    var prompts: [String] = []
    var lastAssistant: String? = nil
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
        // Cheap pre-filter: a line that doesn't say "user" or "assistant"
        // can't be one of the records we care about. Avoids JSON.parse cost
        // on tool_result lines and similar.
        let isUserLine = line.contains("\"type\":\"user\"")
        let isAssistantLine = line.contains("\"type\":\"assistant\"")
        guard isUserLine || isAssistantLine else { continue }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        if let isSidechain = obj["isSidechain"] as? Bool, isSidechain { continue }
        guard let m = obj["message"] as? [String: Any],
              let role = m["role"] as? String
        else { continue }

        if isUserLine, role == "user" {
            var text = ""
            if let s = m["content"] as? String {
                text = s
            } else if let blocks = m["content"] as? [[String: Any]] {
                for b in blocks {
                    if let t = b["type"] as? String, t == "text",
                       let bt = b["text"] as? String {
                        text = bt
                        break
                    }
                }
            }
            guard !text.isEmpty,
                  !isMachineGeneratedUserTurn(text) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                prompts.append(String(trimmed.prefix(500)))
            }
        } else if isAssistantLine, role == "assistant" {
            // Concatenate all `text` blocks (skip thinking/tool_use). For a
            // single-string content, take it as-is. Overwrite `lastAssistant`
            // each iteration so we end up with the latest in file order.
            var text = ""
            if let s = m["content"] as? String {
                text = s
            } else if let blocks = m["content"] as? [[String: Any]] {
                var parts: [String] = []
                for b in blocks {
                    if let t = b["type"] as? String, t == "text",
                       let bt = b["text"] as? String {
                        parts.append(bt)
                    }
                }
                text = parts.joined(separator: "\n")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Cap at 2 KB — enough signal for tokenization, bounded so a
                // single long assistant response can't dominate the token set.
                lastAssistant = String(trimmed.prefix(2000))
            }
        }
    }
    let early = Array(prompts.prefix(5))
    let recent = prompts.count > 5 ? Array(prompts.suffix(3)) : []
    return (early, recent, lastAssistant)
}

// MARK: - AppleScript bridge (port of backend/src/ghostty/applescript.ts)

private struct ActivateOutcome {
    let ok: Bool
    let reason: String?
    let detail: String?
}

private enum WindowList {
    case success([(index: Int, title: String)])
    case failure(reason: String, detail: String)
}

private struct ScriptOutcome {
    let output: String?
    let errorNumber: Int?
    let errorMessage: String?
}

private func runAppleScript(_ source: String) -> ScriptOutcome {
    guard let scr = NSAppleScript(source: source) else {
        return ScriptOutcome(output: nil, errorNumber: nil,
                             errorMessage: "NSAppleScript init failed")
    }
    var errInfo: NSDictionary?
    let descriptor = scr.executeAndReturnError(&errInfo)
    if let err = errInfo {
        return ScriptOutcome(
            output: nil,
            errorNumber: err[NSAppleScript.errorNumber] as? Int,
            errorMessage: err[NSAppleScript.errorMessage] as? String
        )
    }
    return ScriptOutcome(output: descriptor.stringValue,
                         errorNumber: nil, errorMessage: nil)
}

private func activateGhostty() -> ActivateOutcome {
    let r = runAppleScript(#"tell application "Ghostty" to activate"#)
    if r.errorNumber == nil {
        return ActivateOutcome(ok: true, reason: nil, detail: nil)
    }
    let detail = r.errorMessage ?? "errorNumber=\(r.errorNumber ?? 0)"
    // Apple Events return -600 (procNotFound), -1728 (errAENoSuchObject), or
    // -10810 (errLSAppNotInstalled) when Ghostty isn't installed/running.
    // Anything else is treated as a generic activate failure.
    if let n = r.errorNumber, [-600, -1728, -10810].contains(n) {
        return ActivateOutcome(ok: false, reason: "ghostty_not_running", detail: detail)
    }
    return ActivateOutcome(ok: false, reason: "ghostty_activate_failed", detail: detail)
}

private let listScript = """
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
      set out to out & i & "\\t" & t & linefeed
    end repeat
    return out
  end tell
end tell
"""

private func listGhosttyWindows() -> WindowList {
    let r = runAppleScript(listScript)
    if let n = r.errorNumber {
        // Accessibility (UI scripting) denial surfaces as -1743 in the
        // NSAppleScript error dictionary. Older macOS versions and certain
        // codepaths use 1002 or surface a "not allowed" / "assistive" string
        // instead. Match all three so the reason-mapping in PopoverController
        // continues to fire the "Grant Accessibility…" branch.
        let msg = (r.errorMessage ?? "").lowercased()
        let isAxDenial = n == -1743 || n == 1002
            || msg.contains("not allowed") || msg.contains("assistive access")
        let reason = isAxDenial ? "ax_permission_denied" : "list_failed"
        return .failure(reason: reason,
                        detail: "errorNumber=\(n) message=\(r.errorMessage ?? "")")
    }
    var windows: [(Int, String)] = []
    for line in (r.output ?? "").split(separator: "\n", omittingEmptySubsequences: true) {
        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let idx = Int(parts[0].trimmingCharacters(in: .whitespaces))
        else { continue }
        windows.append((idx, String(parts[1]).trimmingCharacters(in: .whitespaces)))
    }
    return .success(windows)
}

private func raiseGhosttyWindow(index: Int) -> Bool {
    // Two-step `AXRaise` then `set frontmost to true` mirrors the prior
    // applescript.ts `raiseGhosttyWindow`. Returns false on any error so the
    // caller surfaces "matched: false" in the FocusResult.
    let script = """
    tell application "System Events"
      tell process "Ghostty"
        try
          perform action "AXRaise" of window \(index)
          set frontmost to true
          return "ok"
        on error
          return "err"
        end try
      end tell
    end tell
    """
    let r = runAppleScript(script)
    if r.errorNumber != nil {
        logger.error("raiseGhosttyWindow failed index=\(index, privacy: .public) err=\(r.errorMessage ?? "", privacy: .public)")
        return false
    }
    return (r.output ?? "").contains("ok")
}
