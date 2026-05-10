// Main app — assembles all screens into design-canvas artboards

const { useState, useEffect, useRef } = React;

// A single live "interactive" popover — used in the main artboard
const LivePopover = ({ initialTab = "Live", initialDetail = null, navMode = false, quietInit = false, sessions, restoreSessions }) => {
  const [tab, setTab] = useState(initialTab);
  const [focusedId, setFocusedId] = useState(sessions[0]?.id);
  const [openSession, setOpenSession] = useState(initialDetail);
  const [restoreSel, setRestoreSel] = useState(restoreSessions[0]?.id);
  const [quiet, setQuiet] = useState(quietInit);

  if (openSession) {
    return (
      <div className="popover popover-detail">
        <SessionDetail
          session={sessions.find((s) => s.id === openSession.id) || openSession}
          onBack={() => setOpenSession(null)}
        />
      </div>
    );
  }

  const attentionCount = sessions.filter(
    (s) => s.state === "permission-pending" || s.state === "tool-failed" || s.state === "ask"
  ).length;

  return (
    <div className="popover popover-tall" style={{ position: "relative" }}>
      <PopHeader
        count={sessions.length}
        attentionCount={attentionCount}
        quiet={quiet}
        onQuietToggle={() => setQuiet(!quiet)}
      />
      <TabBar tabs={["Live", "Restore", "Settings"]} active={tab} onChange={setTab} />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", minHeight: 0, overflow: "hidden" }}>
        {tab === "Live" && (
          <LiveTab
            sessions={sessions}
            focusedId={focusedId}
            onFocusChange={setFocusedId}
            onOpenDetail={setOpenSession}
            navMode={navMode}
            quiet={quiet}
          />
        )}
        {tab === "Restore" && (
          <RestoreTab
            sessions={restoreSessions}
            selectedId={restoreSel}
            onSelect={setRestoreSel}
          />
        )}
        {tab === "Settings" && <SettingsTab />}
      </div>
      {tab === "Live" && (
        <PopFooter
          onSettings={() => setTab("Settings")}
          onRefresh={() => {}}
          hint={
            navMode ? (
              <span style={{ color: "var(--accent)" }}>Press 1–9 to focus that session · esc to cancel</span>
            ) : null
          }
        />
      )}
      {tab !== "Live" && (
        <div className="pop-footer">
          <span style={{ color: "var(--fg-tertiary)" }}>
            {tab === "Restore" ? "Last 14 days · " + restoreSessions.length + " repos" : "cc-dash 0.4.0"}
          </span>
          <span className="kbd-hint">
            <span className="key">⇥</span> tab <span className="key">esc</span> close
          </span>
        </div>
      )}
      {navMode && tab === "Live" && (
        <div className="navigate-hint">
          <Icon name="bolt" size={11} style={{ color: "var(--accent)" }} />
          Press a number to focus that terminal
        </div>
      )}
    </div>
  );
};

// =========== Status icon row variants ===========
const MenuBarSample = ({ iconState, iconCount = 0, label }) => (
  <div style={{ width: "100%", padding: "16px 16px 12px" }}>
    <div className="menubar-strip">
      <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 11, fontFamily: "var(--font-mono)" }}>3:24</span>
      <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 11 }}>100%</span>
      <StatusIcon state={iconState} count={iconCount} active={iconState === "needs-n" || iconState === "flashing"} />
    </div>
    <div style={{ marginTop: 14, fontSize: 12, color: "var(--fg-secondary)", fontFamily: "var(--font-mono)", textAlign: "center" }}>
      {label}
    </div>
  </div>
);

// =========== Empty / error states ===========
const EmptyArtboard = ({ kind }) => {
  const sessions = [];
  let body;
  if (kind === "no-claude") {
    body = (
      <div className="empty">
        <div className="empty-icon"><Icon name="warning" size={22} style={{ color: "var(--u-permission)" }} /></div>
        <div className="empty-title">Looks like Claude Code isn't installed</div>
        <div className="empty-body">cc-dash watches <span style={{ fontFamily: "var(--font-mono)" }}>~/.claude/</span> for sessions. Once you install Claude Code and run it once, sessions will show up here.</div>
        <button className="btn primary" style={{ marginTop: 8 }}><Icon name="external" size={11} />Install instructions</button>
      </div>
    );
  } else if (kind === "backend-down") {
    body = (
      <>
        <div className="banner error">
          <span className="banner-icon"><Icon name="warning" size={14} /></span>
          <div className="banner-body">
            <div className="banner-title">Backend isn't responding</div>
            <div style={{ color: "var(--fg-secondary)" }}>The cc-dash sidecar stopped 12s ago. <span className="banner-link">Retry</span> · <span className="banner-link">View log</span></div>
          </div>
        </div>
        <div className="empty">
          <div className="empty-icon"><Icon name="x" size={22} style={{ color: "var(--u-failed)" }} /></div>
          <div className="empty-title">Can't reach the sidecar</div>
          <div className="empty-body">Last data is from 12 seconds ago. Polling will resume automatically once the sidecar comes back.</div>
        </div>
      </>
    );
  } else if (kind === "permission") {
    body = (
      <>
        <div className="banner">
          <span className="banner-icon"><Icon name="warning" size={14} /></span>
          <div className="banner-body">
            <div className="banner-title">Accessibility permission needed</div>
            <div style={{ color: "var(--fg-secondary)" }}>Without it, cc-dash can't focus your terminal when you press <span className="kbd-hint"><span className="key">↵</span></span>. <span className="banner-link">Open System Settings →</span></div>
          </div>
        </div>
        <div style={{ flex: 1 }}>
          {/* show a regular list behind */}
          <SessionRow session={makeSession("working")} />
          <SessionRow session={makeSession("idle-after-complete")} />
        </div>
      </>
    );
  } else {
    body = (
      <div className="empty">
        <div className="empty-icon"><Icon name="stack" size={22} /></div>
        <div className="empty-title">No live sessions</div>
        <div className="empty-body">Start one with <span className="empty-code">claude</span> in any terminal.</div>
      </div>
    );
  }

  return (
    <div className="popover" style={{ height: 380 }}>
      <PopHeader count={0} attentionCount={0} quiet={false} onQuietToggle={() => {}} />
      <TabBar tabs={["Live", "Restore", "Settings"]} active="Live" onChange={() => {}} />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", minHeight: 0, overflow: "hidden" }}>{body}</div>
      <PopFooter />
    </div>
  );
};

// =========== Context menu ===========
const ContextMenu = () => (
  <div className="ns-menu">
    <div className="ns-menu-item">Mute for 30 min</div>
    <div className="ns-menu-item">Mute for 1 hour</div>
    <div className="ns-menu-item">Mute for 4 hours</div>
    <div className="ns-menu-item">Mute until tomorrow 9 AM</div>
    <div className="ns-menu-item">Mute until I unmute</div>
    <div className="ns-menu-divider" />
    <div className="ns-menu-item">About cc-dashboard</div>
    <div className="ns-menu-item">Quit<span style={{ color: "var(--fg-tertiary)", fontFamily: "var(--font-mono)", fontSize: 11 }}>⌘Q</span></div>
  </div>
);

// =========== APP — design canvas ===========
const App = () => {
  // Live ticking sessions used by main artboards (shared)
  const [sessions, setSessions] = useState(() => makeInitialSessions(9));
  const [tick, setTick] = useState(0);
  const restoreSessions = useRef(makeRestoreSessions()).current;

  // Tweaks
  const tweaks = useTweaks(/*EDITMODE-BEGIN*/{
    "quiet": false
  }/*EDITMODE-END*/);
  const { values, setTweak } = tweaks;

  // Tick — advance "lastActivity" minutes occasionally; mutate one session every ~3s
  useEffect(() => {
    const t = setInterval(() => {
      setTick((x) => x + 1);
      setSessions((curr) => {
        // randomly mutate one session's state to feel "live"
        const idx = Math.floor(Math.random() * curr.length);
        const next = [...curr];
        const s = { ...next[idx] };
        const transitions = {
          "working": ["working", "working", "idle-after-complete", "ask", "permission-pending"],
          "permission-pending": ["permission-pending", "permission-pending", "working"],
          "tool-failed": ["tool-failed", "working", "ask"],
          "ask": ["ask", "working"],
          "idle-after-complete": ["idle-after-complete", "working"],
        };
        const choices = transitions[s.state] || ["working"];
        s.state = choices[Math.floor(Math.random() * choices.length)];
        const reasons = window.STATUS_REASONS[s.state] || ["…"];
        s.reason = reasons[Math.floor(Math.random() * reasons.length)];
        s.lastActivity = Date.now();
        // bump sparkline
        s.sparkline = [...s.sparkline.slice(1), s.state === "working" ? Math.floor(Math.random() * 8) + 2 : Math.floor(Math.random() * 3)];
        next[idx] = s;
        return next;
      });
    }, 3000);
    // tick every second for relative time labels
    const t2 = setInterval(() => setTick((x) => x + 1), 1000);
    return () => { clearInterval(t); clearInterval(t2); };
  }, []);

  // attention count for status icon
  const attentionCount = sessions.filter(
    (s) => s.state === "permission-pending" || s.state === "tool-failed" || s.state === "ask"
  ).length;

  // detail session for the detail artboards — pick a permission-pending one
  const detailSession = sessions.find((s) => s.state === "permission-pending") || sessions[0];

  return (
    <>
      <DesignCanvas projectName="cc-dash" defaultBg="#1a1816">
        {/* SECTION 1 — STATUS ICON */}
        <DCSection id="status-icon" title="01 · Status icon">
          <DCArtboard id="icon-idle" label="Idle / all clear" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="idle" label="baseline glyph · stacked layers" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-working" label="Working" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="working" label="activity dot · no badge" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-1" label="Needs attention (1)" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="needs-1" label="amber badge" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-n" label="Needs attention (n)" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="needs-n" iconCount={4} label="count badge · 4 sessions" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-flash" label="Flashing (new attention)" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="flashing" iconCount={2} label="2-image swap @ 1Hz · 30s cap" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-quiet" label="Quiet mode" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="quiet" label="moon overlay · flashing suppressed" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-error" label="Backend down" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="error" label="red variant · tooltip explains" />
            </div>
          </DCArtboard>
          <DCArtboard id="icon-loading" label="Loading (cold start)" width={280} height={130}>
            <div className="canvas-bg-desktop" style={{ height: "100%" }}>
              <MenuBarSample iconState="loading" label="grey · until health check passes" />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 2 — POPOVER · Live tab */}
        <DCSection id="popover-live" title="02 · Popover — Live tab (the triage view)">
          <DCArtboard id="live-main" label="Live · populated · ticking" width={428} height={620}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} quietInit={values.quiet} />
            </div>
          </DCArtboard>
          <DCArtboard id="live-navigate" label="Navigate mode active" width={428} height={620}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} navMode={true} />
            </div>
          </DCArtboard>
          <DCArtboard id="live-quiet" label="Quiet mode on" width={428} height={620}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} quietInit={true} />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 3 — POPOVER · Restore + Settings */}
        <DCSection id="popover-other" title="03 · Popover — Restore & Settings">
          <DCArtboard id="restore" label="Restore tab · row selected" width={428} height={620}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} initialTab="Restore" />
            </div>
          </DCArtboard>
          <DCArtboard id="settings" label="Settings tab" width={428} height={620}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} initialTab="Settings" />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 4 — SESSION DETAIL */}
        <DCSection id="detail" title="04 · Session detail (push from a Live row)">
          <DCArtboard id="detail-main" label="Detail · permission-pending session" width={428} height={680}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <LivePopover sessions={sessions} restoreSessions={restoreSessions} initialDetail={detailSession} />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 5 — EMPTY & ERROR STATES */}
        <DCSection id="empty" title="05 · Empty & error states">
          <DCArtboard id="empty-live" label="Live · no sessions" width={428} height={420}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <EmptyArtboard kind="empty" />
            </div>
          </DCArtboard>
          <DCArtboard id="empty-claude" label="Claude Code not installed" width={428} height={420}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <EmptyArtboard kind="no-claude" />
            </div>
          </DCArtboard>
          <DCArtboard id="empty-backend" label="Backend down" width={428} height={420}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <EmptyArtboard kind="backend-down" />
            </div>
          </DCArtboard>
          <DCArtboard id="empty-perm" label="Accessibility permission" width={428} height={420}>
            <div className="canvas-bg-popover" style={{ height: "100%" }}>
              <EmptyArtboard kind="permission" />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 6 — CONTEXT MENU */}
        <DCSection id="context-menu" title="06 · Right-click context menu (NSMenu)">
          <DCArtboard id="ctx" label="Mute presets + About / Quit" width={260} height={260}>
            <div style={{ height: "100%", padding: 16, background: "linear-gradient(135deg, #2a2825, #14110f)", display: "flex", justifyContent: "center", alignItems: "flex-start" }}>
              <ContextMenu />
            </div>
          </DCArtboard>
        </DCSection>

        {/* SECTION 7 — URGENCY TAXONOMY */}
        <DCSection id="taxonomy" title="07 · Urgency taxonomy">
          <DCArtboard id="urgency-key" label="Color + icon + edge tick" width={520} height={360}>
            <div style={{ height: "100%", padding: 18, background: "var(--bg-window-solid)" }}>
              <div style={{ fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em", color: "var(--fg-tertiary)", marginBottom: 10 }}>Five urgency states · color-blind safe</div>
              {[
                { state: "permission-pending", reason: "wants to run Bash: rm -rf node_modules" },
                { state: "tool-failed", reason: "tool failed: pytest (3 errors)" },
                { state: "ask", reason: "asked: idempotency keys or DB constraints?" },
                { state: "working", reason: "running Bash: pnpm test" },
                { state: "idle-after-complete", reason: "completed 3 edits" },
              ].map((d) => (
                <SessionRow
                  key={d.state}
                  session={{
                    id: d.state,
                    repo: "myorg/example",
                    branch: "feat/example",
                    state: d.state,
                    reason: d.reason,
                    lastActivity: Date.now() - 1000 * 60 * 2,
                  }}
                />
              ))}
              <div style={{ fontSize: 11, color: "var(--fg-tertiary)", marginTop: 8, lineHeight: 1.5 }}>
                Sessions in any state for &gt; 30 min dim and deprioritize in sort.
              </div>
            </div>
          </DCArtboard>
        </DCSection>
      </DesignCanvas>

      <TweaksPanel title="Tweaks">
        <TweakSection title="State">
          <TweakToggle
            label="Quiet mode"
            sublabel="Affects all popovers"
            value={values.quiet}
            onChange={(v) => setTweak("quiet", v)}
          />
        </TweakSection>
      </TweaksPanel>
    </>
  );
};

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
