// Owns the `NSPopover` and toggles it on status-item click. The status item's
// button target/action is rewired here, replacing the no-op default. The
// popover content is a `PopoverShell` hosting `PopoverPlaceholder`, which
// switches between LiveTab / RestoreTab / SettingsView based on the
// `PopoverViewModel`'s active tab.
//
// Theme is injected by `PopoverPlaceholder` reading `settings.palette` and
// passing it into `PopoverShell` (which re-emits it via
// `.environment(\.theme, ...)` on its content). Because `SettingsStore` is an
// `ObservableObject`, mutating `settings.themeId` / `themeMode` triggers a
// re-evaluation of `PopoverPlaceholder`, which rebuilds the palette injection
// — so the theme picker is live without a relaunch.
import SwiftUI
import AppKit
import Combine
import os

@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var statusItem: NSStatusItem?
    private let store: PollingStore
    private let settings: SettingsStore
    private let quietMode: QuietModeStore

    /// SwiftUI @State persists across view-tree rebuilds only when the host is
    /// retained. Hosting the controller once in `init` (rather than every
    /// `toggle()`) preserves the user's tab/quiet selection across opens.
    private let hostingController: NSHostingController<AnyView>
    private let popoverViewModel = PopoverViewModel()
    /// Keyboard monitor for the popover. Installed on `popoverDidShow`,
    /// removed on `popoverDidClose` so we don't intercept system keyDowns
    /// while the popover is hidden. Action handler is wired up in `init`.
    private let keyboardMonitor = KeyboardMonitor()
    /// Mirrors `popoverViewModel.navMode` into `keyboardMonitor.navMode` so
    /// the resolver sees the live nav-mode flag without the monitor having
    /// to retain the view model. Cancelled on `deinit`.
    private var navModeObserver: AnyCancellable?

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "PopoverController")

    /// Computed palette — reads through to `settings.palette` so external
    /// callers (and any future hot-reload paths) always see the live theme.
    var currentPalette: ThemePalette { settings.palette }

    init(statusItem: NSStatusItem,
         store: PollingStore,
         settings: SettingsStore,
         quietMode: QuietModeStore) {
        self.statusItem = statusItem
        self.store = store
        self.settings = settings
        self.quietMode = quietMode

        // Build the host once. The rootView is an AnyView so we can hold the
        // hosting controller behind a stable type even though the inner tree
        // depends on `settings`/`quietMode` ObservableObjects (and hence has
        // a generic shape). The actual theme injection happens inside
        // `PopoverPlaceholder` so that store mutations trigger re-render.
        let vm = self.popoverViewModel
        self.hostingController = NSHostingController(
            rootView: AnyView(
                PopoverPlaceholder(
                    viewModel: vm,
                    store: store,
                    settings: settings,
                    quietMode: quietMode
                )
            )
        )

        super.init()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController

        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(toggle)
        } else {
            Self.logger.error("status item has no button; popover toggle will not be wired")
        }

        // Wire keyboard actions. The closure captures `self` weakly to
        // avoid a cycle (controller → monitor → closure → controller).
        keyboardMonitor.onAction = { [weak self] action in
            self?.handleKeyAction(action)
        }
        // Bridge SwiftUI row tap → controller's focus dispatcher (Loop 39).
        // PopoverPlaceholder's `LiveTab.onActivate` calls
        // `viewModel.onActivateLiveSession?(session)` from inside the view
        // tree; the controller (which owns the FocusStrategy resolver) does
        // the actual dispatch. Weak capture mirrors the keyboardMonitor wire.
        popoverViewModel.onActivateLiveSession = { [weak self] session in
            self?.focus(session: session)
        }
        // Mirror `viewModel.navMode` into `keyboardMonitor.navMode`. The
        // resolver is pure and reads the snapshot on every event; without
        // this bridge a SwiftUI binding flip would never reach it.
        navModeObserver = popoverViewModel.$navMode
            .removeDuplicates()
            .sink { [weak self] navMode in
                self?.keyboardMonitor.navMode = navMode
            }
        // Task 32 deleted the in-popover stub for the global navigate
        // hotkey. Global hotkey ownership now lives in `AppDelegate`, which
        // subscribes via `KeyboardShortcuts.onKeyDown(for: .navigateMode)`
        // and calls `openAndEnterNavigateMode()` on this controller.
    }

    deinit {
        // Clear the button's target/action so AppKit doesn't keep dispatching
        // to a deallocating selector path. `target` is a weak ref on NSControl
        // so AppKit handles it, but `action` is a Selector value that remains
        // bound until cleared. Best-effort: invoked on the actor that owns
        // `statusItem` since this whole class is `@MainActor`.
        statusItem?.button?.target = nil
        statusItem?.button?.action = nil
        navModeObserver?.cancel()
    }

    @objc private func toggle() {
        guard let btn = statusItem?.button else {
            // Promoted to `.error` (not `.warning`) — a click reaching this
            // branch means the menu-bar UI is silently broken from the user's
            // perspective. The earlier `.error` in `init` already flagged the
            // construction-time variant; this is the click-time variant.
            Self.logger.error("toggle invoked without a status item button; menu-bar click did nothing")
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        // `popover.show` can no-op if the button has no window (transient
        // screen-config change between guard and call). Surface that case so
        // the user-visible "click did nothing" failure isn't silent.
        if !popover.isShown {
            Self.logger.error("popover.show was a no-op; btn.window=\(btn.window != nil, privacy: .public)")
        }
        // NOTE: do NOT write `store.isPopoverOpen` here. NSPopover's `.transient`
        // behavior auto-closes on outside clicks WITHOUT calling toggle(), which
        // means a manual write here goes stale within seconds. The
        // NSPopoverDelegate callbacks below are the single source of truth.
    }

    /// Public entry point for the global `navigateMode` hotkey (Task 32).
    /// Opens the popover if it's currently hidden AND sets nav-mode = true on
    /// the view model so the overlay + 1–9 jumps activate immediately. If the
    /// popover is already open, this only flips nav-mode (so the user doesn't
    /// see the popover dismissed by a "toggle" interpretation of the hotkey).
    /// Called by AppDelegate's `KeyboardShortcuts.onKeyDown(for: .navigateMode)`
    /// subscription — the Carbon hot-key handler runs on the main thread, so
    /// no actor-hop is required here (this method is `@MainActor`-isolated by
    /// virtue of `PopoverController` being `@MainActor`).
    func openAndEnterNavigateMode() {
        guard let btn = statusItem?.button else {
            Self.logger.error("openAndEnterNavigateMode: status item has no button; ignoring hotkey")
            return
        }
        if !popover.isShown {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            if !popover.isShown {
                Self.logger.error("openAndEnterNavigateMode: popover.show was a no-op; btn.window=\(btn.window != nil, privacy: .public)")
                // Even if popover failed to show, flipping navMode is a no-op
                // for the user — fall through and leave the model untouched.
                return
            }
        }
        popoverViewModel.navMode = true
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidShow(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.store.isPopoverOpen = true
            // Install the local NSEvent monitor only while the popover is
            // visible — we don't want to intercept user keystrokes (digits!)
            // when the menu-bar UI is hidden.
            self.keyboardMonitor.start()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.store.isPopoverOpen = false
            self.keyboardMonitor.stop()
            // Reset nav-mode on close so reopening the popover lands in
            // the default state. Without this, dismissing the popover
            // mid-nav would silently keep the overlay armed for the next
            // open.
            self.popoverViewModel.navMode = false
        }
    }

    // MARK: - Keyboard actions

    /// Translate a resolved `KeyAction` into concrete state mutations on
    /// `popoverViewModel` / `store`. Intentionally short and exhaustive —
    /// the switch is the documented contract between the resolver and the
    /// rest of the app.
    private func handleKeyAction(_ action: KeyAction) {
        let vm = popoverViewModel
        switch action {
        case .up:
            moveFocus(by: -1)
        case .down:
            moveFocus(by: +1)
        case .activate:
            activateFocused()
        case .jumpToTop:
            if let first = focusableSessions().first {
                vm.focusedId = first.sessionId
            }
        case .switchTab:
            // Cycle through all available tabs. UX brief calls for "Live /
            // Restore" but the popover has three tabs; cycling all three
            // matches the visible affordance.
            let all = PopoverTab.allCases
            if let i = all.firstIndex(of: vm.tab) {
                vm.tab = all[(i + 1) % all.count]
            }
        case .refresh:
            // Force a poll regardless of timer cadence. We kick both
            // refreshers so the user sees both lists update.
            Task { @MainActor [store] in
                await store.refreshLive()
                await store.refreshRecentIfNeeded()
            }
        case .toggleNavMode:
            vm.navMode.toggle()
        case .exit:
            if vm.navMode {
                vm.navMode = false
            } else {
                popover.performClose(nil)
            }
        case .jumpTo(let n):
            jumpToIndex(n)
        }
    }

    /// Sessions visible to keyboard navigation. Today this is the Live
    /// list (sorted as `store.sessions`); when nav lands on Restore (Task
    /// 31+) this becomes a switch on `popoverViewModel.tab`.
    private func focusableSessions() -> [LiveSession] {
        store.sessions
    }

    private func moveFocus(by delta: Int) {
        let xs = focusableSessions()
        guard !xs.isEmpty else { return }
        let cur = popoverViewModel.focusedId
        let curIdx = xs.firstIndex(where: { $0.sessionId == cur })
        let nextIdx: Int
        if let curIdx {
            nextIdx = max(0, min(xs.count - 1, curIdx + delta))
        } else {
            // No prior selection — pressing up lands on the bottom row,
            // pressing down lands on the top. Matches macOS list-nav idiom.
            nextIdx = delta < 0 ? xs.count - 1 : 0
        }
        popoverViewModel.focusedId = xs[nextIdx].sessionId
    }

    private func activateFocused() {
        let xs = focusableSessions()
        guard let id = popoverViewModel.focusedId,
              let session = xs.first(where: { $0.sessionId == id }) else {
            // Nothing focused yet — Enter on a virgin list jumps to top
            // rather than no-op'ing silently.
            if let first = xs.first { popoverViewModel.focusedId = first.sessionId }
            return
        }
        focus(session: session)
    }

    private func jumpToIndex(_ oneBased: Int) {
        let xs = focusableSessions()
        let idx = oneBased - 1
        // Always exit nav-mode on a digit press — leaving the overlay armed
        // when the index is out of range strands the user with no feedback.
        popoverViewModel.navMode = false
        guard idx >= 0, idx < xs.count, idx < 9 else {
            Self.logger.info("jumpTo(\(oneBased, privacy: .public)) out of range; live count=\(xs.count, privacy: .public)")
            return
        }
        let session = xs[idx]
        popoverViewModel.focusedId = session.sessionId
        // Per task spec: 1–9 jumps focus the row AND trigger its primary
        // action.
        focus(session: session)
    }

    /// Invoke the focus terminal action for a session. Routes through the
    /// pure `resolveFocusStrategy(session:)` resolver so the dispatch shape
    /// matches the future polyglot world (opencode / pi / codex sessions
    /// that may want `.openWithApp` or `.openInFinder` instead of the
    /// Ghostty matcher). For v1 every session resolves to `.ghostty`, which
    /// reuses `APIClient.focus(cwd:sid:)` (the same call site that
    /// `SessionDetailView`'s Focus button will wire up). Errors are logged
    /// — toast surface lands in a polish loop.
    private func focus(session: LiveSession) {
        let strategy = resolveFocusStrategy(session: session)
        switch strategy {
        case .ghostty(let cwd, let sid):
            focusViaGhostty(cwd: cwd, sid: sid)
        case .openWithApp(let bundleID, let target):
            openWithApp(bundleID: bundleID, target: target)
        case .openInFinder(let path):
            openInFinder(path: path)
        }
    }

    private func focusViaGhostty(cwd: String, sid: String?) {
        // In-flight indicator. Persistent (`after: 0`) so it doesn't auto-
        // dismiss mid-AppleScript. Loop 39 found real-world Ghostty raises can
        // take 5–20s when the target window is on another macOS space. The
        // success branch dismisses this banner once the window is up; the
        // error / no-match branches replace it via `showError`.
        popoverViewModel.showError("Focusing terminal…", kind: .info, after: 0)
        // Snapshot the banner's id AFTER showError assigns it — that's how we
        // detect "the focus banner is still the one on screen" vs "the user
        // (or another action) showed something else in the meantime; don't
        // clobber their banner."
        let pendingId = popoverViewModel.lastError?.id
        Task { @MainActor in
            // GhosttyFocus runs the AppleScript in-process so the user's
            // Accessibility grant on cc-dashboard.app actually applies — see
            // GhosttyFocus.swift for the rationale. Non-throwing: failures
            // come back as a `FocusResult` with `matched: false` and a
            // structured reason, never as a Swift error.
            let result = await GhosttyFocus.focus(cwd: cwd, sid: sid)
            if result.matched {
                if popoverViewModel.lastError?.id == pendingId {
                    popoverViewModel.dismissError()
                }
            } else {
                let reason = result.reason ?? "none"
                Self.logger.error("focus matcher returned no window cwd=\(cwd, privacy: .public) sid=\(sid ?? "nil", privacy: .public) reason=\(reason, privacy: .public)")
                // Translate the matcher's machine-readable `reason` codes
                // into actionable user messages. The most important one
                // to disambiguate is `ax_permission_denied` — a generic
                // "no match" toast is wrong (it implies the matcher ran
                // and failed; in fact, AX never let us enumerate windows
                // at all). User needs to grant Accessibility access in
                // System Settings; the `no_confident_match` case is the
                // matcher genuinely not finding the window.
                let message: String
                let kind: PopoverError.Kind
                switch reason {
                case "ax_permission_denied":
                    message = "Grant Accessibility to cc-dashboard in System Settings → Privacy"
                    kind = .error
                case "ghostty_not_running":
                    message = "Ghostty is not running"
                    kind = .warning
                case "ghostty_activate_failed":
                    message = "Couldn't activate Ghostty"
                    kind = .error
                case "list_failed":
                    message = "Couldn't list Ghostty windows"
                    kind = .error
                case "no_confident_match", "none":
                    message = "No terminal window matched (window may be on another Space)"
                    kind = .warning
                default:
                    message = "Focus failed: \(reason)"
                    kind = .warning
                }
                popoverViewModel.showError(message, kind: kind, after: 8)
            }
        }
    }

    /// `.openWithApp` is reserved for future polyglot sources (opencode /
    /// pi / codex) that hand off to a GUI app rather than a terminal. Call
    /// site lifted from cctop's strategy dispatcher: locate the app by
    /// bundle id, fall back to logging if it's missing or the open fails.
    private func openWithApp(bundleID: String, target: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Self.logger.error("openWithApp: no app found for bundleID=\(bundleID, privacy: .public)")
            popoverViewModel.showError("App not installed: \(bundleID)", kind: .error)
            return
        }
        let targetURL = URL(fileURLWithPath: target)
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: cfg) { [weak self] _, error in
            if let error {
                Self.logger.error("openWithApp failed bundleID=\(bundleID, privacy: .public) target=\(target, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                Task { @MainActor in
                    self?.popoverViewModel.showError("Couldn't open \(bundleID)", kind: .error)
                }
            }
        }
    }

    /// `.openInFinder` is the "I just want to see the directory" fallback
    /// for sources we don't know how to focus. `NSWorkspace.open(_:)`
    /// returns a Bool — we log on false rather than silently swallowing.
    private func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        let ok = NSWorkspace.shared.open(url)
        if !ok {
            Self.logger.error("openInFinder failed path=\(path, privacy: .public)")
            popoverViewModel.showError("Couldn't open Finder", kind: .error)
        }
    }

    /// Public passthrough so non-popover-owned call sites (AppDelegate's
    /// notification-authorization path) can surface a banner without
    /// reaching into the view model directly. Loop 34.
    func showError(_ message: String, kind: PopoverError.Kind = .error, after: TimeInterval = 4) {
        popoverViewModel.showError(message, kind: kind, after: after)
    }
}

/// Transient error surfaced via the popover's top-of-stack toast banner
/// (Loop 34). `kind` drives the banner's background tint; `id` lets the
/// auto-dismiss task disambiguate "is the error I scheduled still the
/// active one?" from "did a newer error replace me?".
struct PopoverError: Equatable {
    let id: UUID
    let message: String
    let kind: Kind
    enum Kind: Equatable { case info, warning, error }
}

/// Persists the popover's UI selections across view-tree rebuilds — `@State`
/// inside the host's rootView would survive too (since the host is built
/// once), but routing through an explicit observable makes the lifetime
/// guarantee testable and lets future loops (Task 26+) drive the active tab
/// programmatically (e.g. flash → click → jump to Restore tab).
@MainActor
final class PopoverViewModel: ObservableObject {
    @Published var quiet: Bool = false
    @Published var tab: PopoverTab = .live
    /// When non-nil, the popover replaces its tabbed chrome with a
    /// `SessionDetailView` for the held session (push navigation, no modal).
    /// `LiveTab` sets this via `onOpenDetail`; `SessionDetailView`'s back
    /// button clears it.
    @Published var selectedDetail: LiveSession? = nil
    /// Sessionid of the keyboard-focused row in the active list (Live or
    /// Restore). Lifted out of PopoverPlaceholder's @State so the
    /// `KeyboardMonitor` can drive it without going through SwiftUI.
    @Published var focusedId: String? = nil
    /// Whether nav-mode (overlay + 1–9 jumps) is active. Lifted out of
    /// PopoverPlaceholder's @State for the same reason as `focusedId`.
    @Published var navMode: Bool = false
    /// Bridge from the SwiftUI row tap (`LiveTab.onActivate`) into
    /// `PopoverController.focus(session:)`. Set by the controller after
    /// `super.init()` so the closure can capture `self` weakly. The view
    /// can't reach the controller directly because the host is a struct.
    var onActivateLiveSession: ((LiveSession) -> Void)?
    /// Transient error toast displayed at the top of the popover content
    /// stack (Loop 34). `nil` = no banner. Mutated only via `showError` /
    /// `dismissError` so the auto-dismiss timer stays consistent with the
    /// published value.
    @Published var lastError: PopoverError? = nil

    /// Outstanding auto-dismiss task. Cancelled when a new error replaces
    /// the current one (so the new error's timer starts fresh) or when the
    /// user dismisses manually. The task self-checks `lastError?.id` before
    /// clearing to avoid clobbering an error that was set after the timer
    /// armed but before it fired.
    private var dismissTask: Task<Void, Never>?

    /// Show a transient error banner. `after <= 0` means "do not auto-dismiss"
    /// (the user must hit ✕ or tap the banner). The dismiss timer is reset on
    /// every `showError` call, so a chain of errors all stay visible for at
    /// least their own `after` interval.
    func showError(_ message: String, kind: PopoverError.Kind = .error, after: TimeInterval = 4) {
        dismissTask?.cancel()
        let err = PopoverError(id: UUID(), message: message, kind: kind)
        lastError = err
        guard after > 0 else { return }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            // Id check prevents a stale timer from clobbering a fresher
            // error that was set after this task armed.
            if self.lastError?.id == err.id { self.lastError = nil }
        }
    }

    /// User-initiated dismissal. Cancels any pending auto-dismiss timer so
    /// it can't reset `lastError` to nil twice (harmless, but also can't
    /// clobber a new error set immediately after).
    func dismissError() {
        dismissTask?.cancel()
        dismissTask = nil
        lastError = nil
    }
}

/// Popover root content. Owns the header / tab bar / current-tab body /
/// footer stack and switches the body view based on `viewModel.tab`. Theme
/// injection happens here (not in PopoverController) so SettingsStore
/// mutations trigger SwiftUI to rebuild the environment binding live.
private struct PopoverPlaceholder: View {
    @ObservedObject var viewModel: PopoverViewModel
    @ObservedObject var store: PollingStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var quietMode: QuietModeStore

    // Phase 5 (Task 30) lifted `focusedId` / `navMode` into the view model
    // so the popover-wide `KeyboardMonitor` can drive them without
    // SwiftUI plumbing. `LiveTab` still takes them as Bindings; we project
    // those bindings off the ObservedObject below.

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "PopoverPlaceholder")

    var body: some View {
        // Recompute palette on every body evaluation. Cheap (table lookup) and
        // guaranteed live: any settings setter calls `objectWillChange.send()`
        // which forces this body to re-evaluate.
        let palette = settings.palette
        return PopoverShell(palette: palette) {
            innerContent
        }
    }

    @ViewBuilder
    private var innerContent: some View {
        // ErrorBanner sits at the very top of the content stack — above
        // both the tabbed chrome and the detail-mode sub-view — so a toast
        // raised mid-detail-navigation is still visible. The banner pushes
        // the rest of the content down (rather than overlaying) so it never
        // occludes a row the user is reaching for; the auto-dismiss timer
        // means the layout shift is brief.
        VStack(spacing: 0) {
            ErrorBanner(
                error: viewModel.lastError,
                dismiss: { viewModel.dismissError() }
            )
            Group {
                if let s = viewModel.selectedDetail {
                    // Detail mode: push-navigation replaces the entire chrome.
                    // PopoverShell stays a pure outer-chrome wrapper; this branch
                    // owns its own frame so NSPopover resizes to 620pt.
                    SessionDetailView(
                        store: store,
                        session: s,
                        onBack: { viewModel.selectedDetail = nil }
                    )
                } else {
                    VStack(spacing: 0) {
                        // Quiet binding projects through the QuietModeStore so
                        // tapping the QuietPill toggles persisted mute state +
                        // FlashController suppression. Setter routes through the
                        // store's `toggle()` (1-hour default mute).
                        PopHeader(
                            liveCount: store.sessions.count,
                            attentionCount: store.attentionCount,
                            connection: store.connectionStatus,
                            quiet: Binding(
                                get: { quietMode.isQuiet },
                                set: { _ in quietMode.toggle() }
                            )
                        )
                        TabBar(tabs: PopoverTab.allCases, active: $viewModel.tab)
                        tabContent
                        PopFooter()
                    }
                    // Translucent dim + hint bar while nav-mode is on; the
                    // numbered badges themselves are drawn by SessionRow via
                    // its `navIndex` parameter, which LiveTab populates from
                    // the same `viewModel.navMode`.
                    .navigateOverlay(active: viewModel.navMode)
                }
            }
        }
        .frame(width: 380, height: viewModel.selectedDetail != nil ? 620 : 560)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.tab {
        case .live:
            // Primary row tap = focus the Ghostty terminal (uses the same
            // FocusStrategy resolver path as the keyboard `.activate` action).
            // Trailing info-chevron tap = push SessionDetailView via
            // `viewModel.selectedDetail` (Task 28). The two gestures are
            // intentionally separated so clicking the row doesn't open detail.
            LiveTab(
                store: store,
                navMode: $viewModel.navMode,
                focusedId: $viewModel.focusedId,
                onActivate: { session in viewModel.onActivateLiveSession?(session) },
                onOpenDetail: { session in viewModel.selectedDetail = session }
            )
        case .restore:
            RestoreTab(store: store)
        case .settings:
            SettingsView(settings: settings, quietMode: quietMode)
        }
    }
}
