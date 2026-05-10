// Pure resolver mapping a `LiveSession` to a concrete focus action. Mirrors
// cctop's strategy enum: today every cc-dashboard session is a Claude Code
// transcript whose terminal we locate via the Ghostty matcher in the sidecar
// (`POST /api/focus`), but the polyglot extension hooks (opencode / pi /
// codex, plus arbitrary GUI app handoffs) live in the `.openWithApp` and
// `.openInFinder` cases so the call site doesn't need to change shape when
// they land.
//
// The resolver is deliberately a free function with no side effects — that
// keeps the test surface trivial (construct a `LiveSession`, assert the
// returned enum case) and avoids the need for a mock `APIClient` or
// `NSWorkspace` to exercise the dispatch logic. The actual I/O happens at
// the call site (see `PopoverController.activateLiveSession`).
import Foundation

/// Concrete focus strategy for a session. v1 only constructs `.ghostty`; the
/// other two cases are placeholders for future polyglot sources (opencode /
/// pi / codex) and for GUI-app handoffs (e.g. "open this transcript with
/// Cursor"). Equatable so tests can assert returned cases directly.
enum FocusStrategy: Equatable {
    case ghostty(cwd: String, sid: String?)
    case openWithApp(bundleID: String, target: String)
    case openInFinder(path: String)
}

/// Map a `LiveSession` to the strategy that should fire when the user
/// activates the row (Enter / nav-mode digit / row tap, depending on call
/// site). Pure: no I/O, no logging, no mocking required to test.
///
/// For v1, every cc-dashboard session is a Claude Code transcript whose
/// terminal we locate via the sidecar's Ghostty matcher. The other enum
/// cases exist so the call site already speaks the future polyglot dialect
/// — when opencode / pi / codex sessions show up in `LiveSession`, this
/// switch grows a branch and the dispatcher in `PopoverController` keeps
/// the same shape.
func resolveFocusStrategy(session: LiveSession) -> FocusStrategy {
    // The `sid` parameter on `.ghostty` is `String?` because the broader
    // contract (cctop's matcher, `APIClient.focus(cwd:sid:)`, the Ghostty
    // window-title heuristic) treats sid as optional even though
    // `LiveSession.sessionId` is currently a non-optional `String` after
    // backend decoding. Keeping the strategy's sid optional means we can
    // accept sid-less inputs (e.g. RecentRepo handoffs in a future loop)
    // without re-shaping the enum.
    .ghostty(cwd: session.cwd, sid: session.sessionId)
}
