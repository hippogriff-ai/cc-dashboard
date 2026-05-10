// cc-dash icons & glyphs (single source of truth)
// All icons are 14×14 strokes unless noted. Inline SVG only.

const Icon = ({ name, size = 14, className = "", style = {} }) => {
  const stroke = "currentColor";
  const sw = 1.4;
  const props = {
    width: size,
    height: size,
    viewBox: "0 0 16 16",
    fill: "none",
    stroke,
    strokeWidth: sw,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    className: "icn " + className,
    style,
  };
  switch (name) {
    case "permission":
      // hand / palm — Claude is asking permission to use a tool
      return (
        <svg {...props}>
          <path d="M5 9V4.5a1 1 0 0 1 2 0V8" />
          <path d="M7 8V3.5a1 1 0 0 1 2 0V8" />
          <path d="M9 8V4.5a1 1 0 0 1 2 0V9" />
          <path d="M11 9V6.5a1 1 0 0 1 2 0V11a3 3 0 0 1-3 3H7a3 3 0 0 1-2.5-1.3L3 10.5" />
        </svg>
      );
    case "failed":
      // x in circle
      return (
        <svg {...props}>
          <circle cx="8" cy="8" r="5.5" />
          <path d="M6 6l4 4M10 6l-4 4" />
        </svg>
      );
    case "ask":
      // question mark
      return (
        <svg {...props}>
          <circle cx="8" cy="8" r="5.5" />
          <path d="M6.5 6.5a1.5 1.5 0 0 1 3 0c0 1-1.5 1.3-1.5 2.3" />
          <circle cx="8" cy="11.2" r="0.4" fill={stroke} stroke="none" />
        </svg>
      );
    case "working":
      // spinning gear-ish — concentric arcs
      return (
        <svg {...props}>
          <path d="M3 8a5 5 0 0 1 5-5" />
          <path d="M13 8a5 5 0 0 1-5 5" />
          <circle cx="8" cy="8" r="1.4" fill={stroke} stroke="none" />
        </svg>
      );
    case "idle":
      // check
      return (
        <svg {...props}>
          <path d="M3.5 8.5L6.5 11.5L12.5 5" />
        </svg>
      );
    case "clear":
      return (
        <svg {...props}>
          <circle cx="8" cy="8" r="2.5" />
        </svg>
      );
    case "branch":
      return (
        <svg {...props}>
          <circle cx="4" cy="3.5" r="1.4" />
          <circle cx="4" cy="12.5" r="1.4" />
          <circle cx="12" cy="6" r="1.4" />
          <path d="M4 4.9V11.1" />
          <path d="M4 8a4 4 0 0 0 4-4V4a3 3 0 0 1 3 3v.5" />
        </svg>
      );
    case "chevron-right":
      return (
        <svg {...props}>
          <path d="M6 4l4 4-4 4" />
        </svg>
      );
    case "chevron-left":
      return (
        <svg {...props}>
          <path d="M10 4l-4 4 4 4" />
        </svg>
      );
    case "gear":
      return (
        <svg {...props}>
          <circle cx="8" cy="8" r="2" />
          <path d="M8 1.5v1.8M8 12.7v1.8M14.5 8h-1.8M3.3 8H1.5M12.6 3.4l-1.3 1.3M4.7 11.3l-1.3 1.3M12.6 12.6l-1.3-1.3M4.7 4.7L3.4 3.4" />
        </svg>
      );
    case "refresh":
      return (
        <svg {...props}>
          <path d="M2.5 8a5.5 5.5 0 0 1 9.4-3.9" />
          <path d="M12 2.5V5h-2.5" />
          <path d="M13.5 8a5.5 5.5 0 0 1-9.4 3.9" />
          <path d="M4 13.5V11h2.5" />
        </svg>
      );
    case "moon":
      return (
        <svg {...props}>
          <path d="M13 9.5A5.5 5.5 0 1 1 6.5 3a4.5 4.5 0 0 0 6.5 6.5z" />
        </svg>
      );
    case "bolt":
      return (
        <svg {...props}>
          <path d="M9 1.5L3 9h4l-1 5.5L13 7H8.5z" fill={stroke} stroke="none" />
        </svg>
      );
    case "search":
      return (
        <svg {...props}>
          <circle cx="7" cy="7" r="4" />
          <path d="M10 10l3.5 3.5" />
        </svg>
      );
    case "copy":
      return (
        <svg {...props}>
          <rect x="5" y="5" width="8" height="9" rx="1.5" />
          <path d="M3 11V3.5A1.5 1.5 0 0 1 4.5 2H10" />
        </svg>
      );
    case "external":
      return (
        <svg {...props}>
          <path d="M9 2.5h4.5V7" />
          <path d="M13.5 2.5L7.5 8.5" />
          <path d="M11 9.5v3a1 1 0 0 1-1 1H3.5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h3" />
        </svg>
      );
    case "terminal":
      return (
        <svg {...props}>
          <rect x="2" y="3" width="12" height="10" rx="1.5" />
          <path d="M5 7l2 1.5L5 10" />
          <path d="M8.5 10.5h3" />
        </svg>
      );
    case "warning":
      return (
        <svg {...props}>
          <path d="M8 2.5L14 13H2z" />
          <path d="M8 6.5v3.5" />
          <circle cx="8" cy="11.5" r="0.4" fill={stroke} stroke="none" />
        </svg>
      );
    case "info":
      return (
        <svg {...props}>
          <circle cx="8" cy="8" r="5.5" />
          <path d="M8 7.5v3.5" />
          <circle cx="8" cy="5.2" r="0.4" fill={stroke} stroke="none" />
        </svg>
      );
    case "x":
      return (
        <svg {...props}>
          <path d="M3.5 3.5l9 9M12.5 3.5l-9 9" />
        </svg>
      );
    case "arrow-back":
      return (
        <svg {...props}>
          <path d="M7 3l-4 5 4 5" />
          <path d="M3 8h10" />
        </svg>
      );
    case "file":
      return (
        <svg {...props}>
          <path d="M4 1.5h5l3 3V14a0.5 0.5 0 0 1-0.5 0.5h-7.5A0.5 0.5 0 0 1 3.5 14V2A0.5 0.5 0 0 1 4 1.5z" />
          <path d="M9 1.5V4.5h3" />
        </svg>
      );
    case "ide":
      return (
        <svg {...props}>
          <rect x="2" y="3" width="12" height="10" rx="1" />
          <path d="M2 6h12" />
          <circle cx="4" cy="4.5" r="0.3" fill={stroke} />
          <circle cx="5.5" cy="4.5" r="0.3" fill={stroke} />
        </svg>
      );
    case "stack":
      // The cc-dash glyph: stacked layers/cards
      return (
        <svg {...props}>
          <path d="M2.5 5L8 2L13.5 5L8 8L2.5 5Z" />
          <path d="M2.5 8L8 11L13.5 8" />
          <path d="M2.5 11L8 14L13.5 11" />
        </svg>
      );
    case "stack-filled":
      return (
        <svg width={size} height={size} viewBox="0 0 16 16" className={"icn " + className} style={style}>
          <path d="M2.5 5L8 2L13.5 5L8 8L2.5 5Z" fill="currentColor" opacity="1" />
          <path d="M2.5 8L8 11L13.5 8L11.5 7L8 9L4.5 7L2.5 8Z" fill="currentColor" opacity="0.7" />
          <path d="M2.5 11L8 14L13.5 11L11.5 10L8 12L4.5 10L2.5 11Z" fill="currentColor" opacity="0.45" />
        </svg>
      );
    default:
      return null;
  }
};

// Urgency state metadata (used by SessionRow + StatusBadge)
const URGENCY = {
  "permission-pending": {
    label: "Permission",
    icon: "permission",
    color: "var(--u-permission)",
    rank: 0,
  },
  "tool-failed": {
    label: "Failed",
    icon: "failed",
    color: "var(--u-failed)",
    rank: 1,
  },
  "ask": {
    label: "Asked",
    icon: "ask",
    color: "var(--u-ask)",
    rank: 2,
  },
  "working": {
    label: "Working",
    icon: "working",
    color: "var(--u-working)",
    rank: 3,
  },
  "idle-after-complete": {
    label: "Idle",
    icon: "idle",
    color: "var(--u-idle)",
    rank: 4,
  },
  "clear": {
    label: "Clear",
    icon: "clear",
    color: "var(--u-clear)",
    rank: 5,
  },
};

window.Icon = Icon;
window.URGENCY = URGENCY;
