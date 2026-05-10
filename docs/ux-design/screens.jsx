// Screen-level components: Live tab, Restore tab, Settings tab, Session Detail

const { useState: _us, useEffect: _ue, useRef: _ur } = React;

// ============ LIVE TAB ============
const LiveTab = ({ sessions, focusedId, onFocusChange, onOpenDetail, navMode, quiet }) => {
  const sorted = [...sessions].sort((a, b) => {
    const ra = urgencyRank(a.state);
    const rb = urgencyRank(b.state);
    if (ra !== rb) return ra - rb;
    return b.lastActivity - a.lastActivity;
  });

  if (sorted.length === 0) {
    return (
      <div className="empty">
        <div className="empty-icon"><Icon name="stack" size={22} /></div>
        <div className="empty-title">No live sessions</div>
        <div className="empty-body">Start one with <span className="empty-code">claude</span> in any terminal.</div>
      </div>
    );
  }

  return (
    <div className="session-list" tabIndex={0}>
      {sorted.map((s, i) => {
        const stale = Date.now() - s.lastActivity > 1000 * 60 * 30;
        return (
          <SessionRow
            key={s.id}
            session={s}
            focused={focusedId === s.id}
            navIndex={navMode && i < 9 ? i + 1 : null}
            stale={stale}
            onClick={() => onOpenDetail(s)}
            onHover={() => onFocusChange(s.id)}
          />
        );
      })}
    </div>
  );
};

// ============ RESTORE TAB ============
const RestoreTab = ({ sessions, selectedId, onSelect }) => {
  const sel = sessions.find((s) => s.id === selectedId);

  if (sessions.length === 0) {
    return (
      <div className="empty">
        <div className="empty-icon"><Icon name="search" size={22} /></div>
        <div className="empty-title">Nothing here yet</div>
        <div className="empty-body">No sessions in the last 14 days. Sessions show up here once you've used Claude Code.</div>
      </div>
    );
  }

  return (
    <div className="restore-layout">
      <div className="restore-list">
        {sessions.map((s) => {
          const u = window.URGENCY[s.lastEvent] || window.URGENCY["clear"];
          return (
            <div
              key={s.id}
              className={"restore-row" + (selectedId === s.id ? " selected" : "") + (!s.cwdExists ? " dim" : "")}
              onClick={() => onSelect(s.id)}
            >
              <div>
                <div className="restore-line1">
                  <Icon name={u.icon} size={11} style={{ color: u.color }} />
                  {s.repo}
                </div>
                <div className="restore-line2">
                  <span>{s.branch}</span>
                  {s.dirty > 0 && <span style={{ color: "var(--u-permission)" }}>+{s.dirty}</span>}
                  {!s.cwdExists && <span style={{ color: "var(--fg-tertiary)" }}>· cwd missing</span>}
                </div>
              </div>
              <div className="restore-time">{fmtRel(s.lastActivity)}</div>
            </div>
          );
        })}
      </div>
      {sel ? (
        <div className="restore-detail">
          <div className="section-h" style={{ marginBottom: 6 }}>
            <span>Recent prompts</span>
            <span style={{ textTransform: "none", letterSpacing: 0 }}>{sel.prompts.length}</span>
          </div>
          <div className="prompt-list" style={{ marginBottom: 12 }}>
            {sel.prompts.slice(0, 4).map((p, i) => (
              <div key={i} className="prompt-item">{p}</div>
            ))}
          </div>
          <div className="section-h" style={{ marginBottom: 6 }}>Last assistant message</div>
          <div className="assistant-msg" style={{ marginBottom: 12, maxHeight: 60 }}>{sel.lastAssistant}</div>
          {sel.openTool && (
            <>
              <div className="section-h" style={{ marginBottom: 6 }}>Open tool at end</div>
              <div style={{ marginBottom: 12, fontFamily: "var(--font-mono)", fontSize: 11.5 }}>
                <span style={{ color: "var(--accent)" }}>{sel.openTool.name}</span>{" "}
                <span style={{ color: "var(--fg-secondary)" }}>{sel.openTool.args}</span>
              </div>
            </>
          )}
          {(sel.diff.add > 0 || sel.diff.del > 0) && (
            <>
              <div className="section-h" style={{ marginBottom: 6 }}>Uncommitted</div>
              <div className="diffstat" style={{ marginBottom: 12 }}>
                <span className="add">+{sel.diff.add}</span>
                <span className="del">−{sel.diff.del}</span>
              </div>
            </>
          )}
          <div className="btn-row">
            <button className="btn primary"><Icon name="copy" size={11} />Copy resume</button>
            <button className="btn"><Icon name="copy" size={11} />Fork summary</button>
            <button className="btn"><Icon name="ide" size={11} />Open in IDE</button>
          </div>
        </div>
      ) : (
        <div className="restore-detail-empty">Select a repo to see where you left off.</div>
      )}
    </div>
  );
};

// ============ SETTINGS TAB ============
const SettingsTab = () => {
  const [theme, setTheme] = _us("claude");
  const [dark, setDark] = _us(true);
  const [pollInterval, setPollInterval] = _us(2);
  const [flash, setFlash] = _us(true);
  const [flashCap, setFlashCap] = _us(30);
  const [sound, setSound] = _us(false);
  const [ide, setIde] = _us("zed");
  const [a11yGranted] = _us(true);

  const themes = [
    { id: "claude", name: "Claude", colors: ["#1c1b19", "#d97757", "#f5efe6"] },
    { id: "tokyo", name: "Tokyo Night", colors: ["#1a1b26", "#bb9af7", "#7dcfff"] },
    { id: "gruvbox", name: "Gruvbox", colors: ["#282828", "#fabd2f", "#d79921"] },
    { id: "nord", name: "Nord", colors: ["#2e3440", "#88c0d0", "#5e81ac"] },
  ];

  return (
    <div className="settings-body">
      <div className="section-h" style={{ padding: "12px 14px 6px" }}>Appearance</div>
      <div className="theme-grid">
        {themes.map((t) => (
          <div
            key={t.id}
            className={"theme-swatch" + (theme === t.id ? " selected" : "")}
            onClick={() => setTheme(t.id)}
            style={{
              background: `linear-gradient(135deg, ${t.colors[0]} 0%, ${t.colors[0]} 50%, ${t.colors[1]} 50%, ${t.colors[1]} 75%, ${t.colors[2]} 75%)`,
            }}
          >
            <span className="theme-swatch-name">{t.name}</span>
          </div>
        ))}
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Dark mode</div>
        </div>
        <div className={"toggle" + (dark ? " on" : "")} onClick={() => setDark(!dark)} />
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Poll interval</div>
          <div className="setting-sub">How often to refresh while popover is open</div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <input type="range" min="1" max="10" value={pollInterval} onChange={(e) => setPollInterval(+e.target.value)} className="slider-input" />
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-secondary)", width: 22 }}>{pollInterval}s</span>
        </div>
      </div>

      <div className="section-h" style={{ padding: "12px 14px 6px" }}>Hotkeys</div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Navigate mode</div>
          <div className="setting-sub">Show 1–9 badges on rows</div>
        </div>
        <div className="kbd-bind unset">click to bind</div>
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Quiet mode</div>
        </div>
        <div className="kbd-bind">⌃ ⌥ M</div>
      </div>

      <div className="section-h" style={{ padding: "12px 14px 6px" }}>Notifications</div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Flash on attention</div>
          <div className="setting-sub">Status icon blinks when a session needs you</div>
        </div>
        <div className={"toggle" + (flash ? " on" : "")} onClick={() => setFlash(!flash)} />
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Flash duration cap</div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <input type="range" min="5" max="60" value={flashCap} onChange={(e) => setFlashCap(+e.target.value)} className="slider-input" />
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-secondary)", width: 26 }}>{flashCap}s</span>
        </div>
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Notification sound</div>
        </div>
        <div className={"toggle" + (sound ? " on" : "")} onClick={() => setSound(!sound)} />
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Custom mute durations</div>
          <div className="setting-sub">Show in right-click menu</div>
        </div>
      </div>
      <div className="mute-list">
        {["30 minutes", "1 hour", "4 hours", "Until tomorrow 9 AM"].map((m) => (
          <div key={m} className="mute-item">
            <span>{m}</span>
            <span className="x"><Icon name="x" size={10} /></span>
          </div>
        ))}
      </div>

      <div className="section-h" style={{ padding: "12px 14px 6px" }}>Tools</div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Open in IDE</div>
        </div>
        <select value={ide} onChange={(e) => setIde(e.target.value)} className="select">
          <option value="zed">Zed</option>
          <option value="cursor">Cursor</option>
          <option value="vscode">VS Code</option>
          <option value="nvim">nvim</option>
        </select>
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Accessibility permission</div>
          <div className="setting-sub">Required to focus terminal windows</div>
        </div>
        <span style={{ fontSize: 11.5, color: a11yGranted ? "#84b87b" : "var(--u-failed)" }}>
          {a11yGranted ? "Granted" : "Not granted"}
        </span>
      </div>

      <div className="section-h" style={{ padding: "12px 14px 6px" }}>About</div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Version</div>
          <div className="setting-sub">cc-dash 0.4.0 · sidecar healthy 2s ago</div>
        </div>
      </div>
      <div className="setting-row">
        <div>
          <div className="setting-label">Log file</div>
          <div className="setting-sub" style={{ fontFamily: "var(--font-mono)" }}>~/Library/Logs/cc-dash/main.log</div>
        </div>
        <button className="btn"><Icon name="external" size={11} /></button>
      </div>
    </div>
  );
};

// ============ SESSION DETAIL ============
const SessionDetail = ({ session, onBack }) => {
  const u = window.URGENCY[session.state] || window.URGENCY["clear"];
  const totalContext = session.inputTokens + session.cachedTokens + session.outputTokens;
  const ctxPct = Math.min(100, (totalContext / session.contextLimit) * 100);
  const sessionAgeMin = Math.floor((Date.now() - session.started) / 60000);

  return (
    <>
      <div className="detail-header">
        <button className="detail-back" onClick={onBack}><Icon name="arrow-back" size={14} /></button>
        <div className="detail-title">
          <div className="detail-repo">{session.repo}</div>
          <div className="detail-meta">
            <Icon name="branch" size={11} />
            <span>{session.branch}</span>
            <span style={{ color: "var(--fg-quaternary)" }}>·</span>
            <span>{sessionAgeMin}m</span>
            <span style={{ color: "var(--fg-quaternary)" }}>·</span>
            <span>{session.source}</span>
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 4, color: u.color, fontSize: 11.5, fontWeight: 500 }}>
          <Icon name={u.icon} size={12} />
          <span>{u.label}</span>
        </div>
      </div>

      <div className="detail-body">
        <div className="section">
          <div className="section-h"><span>Branch timeline</span></div>
          <div className="branch-timeline">
            {session.branchHistory.map((b, i) => (
              <React.Fragment key={i}>
                {i > 0 && <span className="branch-arrow">→</span>}
                <span className={"branch-seg" + (i === session.branchHistory.length - 1 ? " current" : "")}>{b}</span>
              </React.Fragment>
            ))}
          </div>
        </div>

        <div className="section">
          <div className="section-h"><span>Files changed · {session.files.length}</span></div>
          <div className="file-list">
            {session.files.map((f, i) => {
              const parts = f.path.split("/");
              const name = parts.pop();
              const dir = parts.join("/");
              return (
                <div key={i} className="file-row">
                  <div className="file-name">
                    {dir && <span className="dim">{dir}/</span>}
                    {name}
                  </div>
                  <div className="file-edits">{f.edits} edit{f.edits === 1 ? "" : "s"}</div>
                  <div className="file-time">{fmtRel(f.lastTouch)}</div>
                </div>
              );
            })}
          </div>
        </div>

        <div className="section">
          <div className="section-h">
            <span>Token usage</span>
            {ctxPct > 80 && <span className="token-warning">{ctxPct.toFixed(0)}% — consider /compact</span>}
          </div>
          <div className="token-grid">
            <div className="token-stat">
              <div className="token-label">Input</div>
              <div className="token-val">{fmtTokens(session.inputTokens)}</div>
            </div>
            <div className="token-stat">
              <div className="token-label">Cached</div>
              <div className="token-val">{fmtTokens(session.cachedTokens)}</div>
            </div>
            <div className="token-stat">
              <div className="token-label">Output</div>
              <div className="token-val">{fmtTokens(session.outputTokens)}</div>
            </div>
          </div>
          <div className="token-bar">
            <div className="token-bar-fill" style={{ width: ctxPct + "%" }} />
          </div>
          <div className="token-bar-meta">
            <span>{fmtTokens(totalContext)} / 200k</span>
            <span>{ctxPct.toFixed(1)}%</span>
          </div>
        </div>

        <div className="section">
          <div className="section-h"><span>Load over time</span><span style={{ textTransform: "none", letterSpacing: 0 }}>tool_use / min</span></div>
          <Sparkline data={session.sparkline} color="var(--u-working)" />
        </div>

        <div className="section">
          <div className="section-h"><span>Last assistant message</span></div>
          <div className="assistant-msg">{session.lastAssistant}</div>
        </div>

        {session.state === "working" && (
          <div className="section">
            <div className="section-h"><span>Open tool</span></div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 12 }}>
              <span style={{ color: "var(--accent)" }}>Bash</span>{" "}
              <span style={{ color: "var(--fg-secondary)" }}>{session.reason.replace(/^running [^:]+: ?/, "")}</span>
            </div>
          </div>
        )}

        <div className="section">
          <div className="section-h"><span>Decisions for this repo</span><span style={{ textTransform: "none", letterSpacing: 0 }}>{session.decisions.length}</span></div>
          {session.decisions.map((d, i) => (
            <div key={i} className="decision">
              <div className="q"><span className="label">Q</span>{d.q}</div>
              <div className="a"><span className="label">A</span>{d.a}</div>
            </div>
          ))}
        </div>

        <div className="section">
          <div className="btn-row">
            <button className="btn primary"><Icon name="terminal" size={11} />Focus terminal</button>
            <button className="btn"><Icon name="copy" size={11} />Copy resume</button>
            <button className="btn"><Icon name="copy" size={11} />Copy fork</button>
            <button className="btn"><Icon name="ide" size={11} />Open in IDE</button>
          </div>
        </div>
      </div>
    </>
  );
};

Object.assign(window, { LiveTab, RestoreTab, SettingsTab, SessionDetail });
