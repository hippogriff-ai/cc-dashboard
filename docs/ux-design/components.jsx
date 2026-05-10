// SessionRow + StatusIcon (menu bar) + small primitives

const { useState, useEffect, useRef, useMemo } = React;

const SessionRow = ({ session, focused, navIndex, onClick, onHover, stale }) => {
  const u = window.URGENCY[session.state] || window.URGENCY["clear"];
  const isUrgent = session.state === "permission-pending" || session.state === "tool-failed";

  const styleVars = {
    "--tick-color": u.color,
    "--icon-color": u.color,
    "--status-color": u.color,
  };

  return (
    <div
      className={
        "session-row" +
        (focused ? " focused" : "") +
        (isUrgent ? " urgent" : "") +
        (stale ? " stale" : "")
      }
      style={styleVars}
      onClick={onClick}
      onMouseEnter={onHover}
    >
      <div className="urgency-tick" />
      <div className="session-row-main">
        <div className="session-row-line1">
          <span className="session-row-icon">
            {session.state === "working" ? (
              <span className="working-pulse" style={{ background: u.color }} />
            ) : (
              <Icon name={u.icon} size={13} />
            )}
          </span>
          <span className="session-row-repo">{session.repo}</span>
          <span className="session-row-branch">{session.branch}</span>
        </div>
        <div className="session-row-line2">
          <span className="session-row-status">{session.reason}</span>
        </div>
      </div>
      <div className="session-row-time">{fmtRel(session.lastActivity)}</div>
      {navIndex != null && <div className="nav-badge">{navIndex}</div>}
    </div>
  );
};

// ---------- Status icon (menu bar) ----------
const StatusIcon = ({ state, count = 0, active = false }) => {
  // state: "idle" | "working" | "needs-1" | "needs-n" | "flashing" | "quiet" | "error" | "loading"
  const showActivity = state === "working";
  const showBadge = state === "needs-1" || state === "needs-n" || state === "flashing";
  const isFlashing = state === "flashing";
  const isQuiet = state === "quiet";
  const isErr = state === "error";
  const isLoading = state === "loading";

  return (
    <div
      className={
        "menubar-icon" +
        (active ? " active" : "") +
        (isFlashing ? " flashing" : "") +
        (isErr ? " error" : "") +
        (isLoading ? " loading" : "")
      }
    >
      <Icon name="stack-filled" size={16} />
      {showActivity && <span className="activity-dot" />}
      {showBadge && (
        <span className={"badge" + (state === "needs-n" && count > 1 ? "" : "")}>
          {state === "needs-n" ? count : ""}
        </span>
      )}
      {isQuiet && (
        <span className="moon-overlay">
          <Icon name="moon" size={8} />
        </span>
      )}
    </div>
  );
};

// ---------- Quiet pill ----------
const QuietPill = ({ quiet, onClick }) => (
  <button className={"quiet-pill" + (quiet ? " quiet" : "")} onClick={onClick}>
    <span className="dot" />
    {quiet ? (
      <>
        <Icon name="moon" size={11} />
        <span>Quiet</span>
      </>
    ) : (
      <>
        <Icon name="bolt" size={11} />
        <span>Active</span>
      </>
    )}
  </button>
);

// ---------- Tab bar ----------
const TabBar = ({ tabs, active, onChange }) => (
  <div className="tab-bar">
    {tabs.map((t) => (
      <button
        key={t}
        className={"tab" + (active === t ? " active" : "")}
        onClick={() => onChange(t)}
      >
        {t}
      </button>
    ))}
  </div>
);

// ---------- Popover header ----------
const PopHeader = ({ count, quiet, onQuietToggle, attentionCount }) => (
  <div className="pop-header">
    <div className="pop-header-left">
      <Icon name="stack-filled" size={14} style={{ color: "var(--accent)" }} />
      <span className="pop-header-title">cc-dash</span>
      <span className="pop-header-count">
        {count} live · {attentionCount} need attention
      </span>
    </div>
    <QuietPill quiet={quiet} onClick={onQuietToggle} />
  </div>
);

// ---------- Footer ----------
const PopFooter = ({ onSettings, onRefresh, lastRefresh, hint }) => (
  <div className="pop-footer">
    <div style={{ display: "flex", gap: 2 }}>
      <button className="icon-btn" title="Settings" onClick={onSettings}>
        <Icon name="gear" />
      </button>
      <button className="icon-btn" title="Refresh" onClick={onRefresh}>
        <Icon name="refresh" />
      </button>
    </div>
    <div className="kbd-hint">
      {hint || (
        <>
          <span className="key">↑↓</span> nav <span className="key">⏎</span> open <span className="key">⇥</span> tab
        </>
      )}
    </div>
  </div>
);

// ---------- Sparkline ----------
const Sparkline = ({ data, color = "var(--u-working)", height = 40 }) => {
  if (!data || data.length === 0) return null;
  const w = 320;
  const h = height;
  const max = Math.max(1, ...data);
  const step = w / (data.length - 1);
  const points = data.map((v, i) => [i * step, h - (v / max) * (h - 4) - 2]);
  const path = points.map((p, i) => (i === 0 ? "M" : "L") + p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
  const area = path + ` L${w},${h} L0,${h} Z`;
  return (
    <svg className="sparkline" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none">
      <defs>
        <linearGradient id="sparkfill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.4" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#sparkfill)" />
      <path d={path} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
};

Object.assign(window, { SessionRow, StatusIcon, QuietPill, TabBar, PopHeader, PopFooter, Sparkline });
