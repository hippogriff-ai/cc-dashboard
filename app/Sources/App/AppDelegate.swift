import SwiftUI
import AppKit
import UserNotifications
import Combine
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var iconController: StatusIconController?
    private var popover: PopoverController?
    private var stateObserverTask: Task<Void, Never>?
    private var popoverOpenObserver: AnyCancellable?
    private var quietModeObserver: AnyCancellable?
    /// Buffered error to surface once the popover exists. The
    /// `requestAuthorization` callback can fire before the backend reaches
    /// `.ready` (the path that constructs `popover`); we stash the message
    /// here and flush it on the `.ready` transition. Loop 34.
    private var pendingError: (message: String, kind: PopoverError.Kind)?
    let backend = BackendController()
    let store = PollingStore()
    let settings = SettingsStore()
    let quietMode = QuietModeStore()
    // FlashController receives a quiet-mode predicate so it can suppress the
    // flash while the user has the menu-bar muted. Captured weakly to avoid
    // a retain cycle (AppDelegate owns both — the cycle would only ever be
    // closed at process exit, but no reason not to be tidy).
    //
    // `onFlashStart` posts a UNNotification on the strict-increase transition
    // (Task 33). The hook fires INSIDE `FlashController.startFlashing()` which
    // is already gated by quiet-mode + strict-increase + not-already-flashing,
    // so the notification inherits all three guards. Sound is opt-in via
    // `settings.notificationSound`. Authorization is requested below in
    // `applicationDidFinishLaunching`; if denied, `add(req)` is a no-op.
    lazy var flash: FlashController = FlashController(
        isQuiet: { [weak self] in self?.quietMode.isQuiet ?? false },
        isEnabled: { [weak self] in self?.settings.flashEnabled ?? true },
        onFlashStart: { [weak self] in self?.postAttentionNotification() }
    )

    // Global hotkey ownership (Task 32). The popover-local KeyboardMonitor
    // handles in-popover navigation only; AppDelegate owns the two global
    // hotkeys via the vendored `KeyboardShortcuts` module. Subscriptions are
    // set up once in `applicationDidFinishLaunching` — the closures captured
    // by `KeyboardShortcuts.onKeyDown(for:)` live for the app lifetime and
    // are not unregistered here (process exit is the only termination path
    // and the system reclaims the Carbon hot-key registration on app quit).

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("did finish launching")

        // Request notification permission on first run (Task 33). The closure
        // is invoked off the main thread on a UNUserNotificationCenter-owned
        // queue. We log the outcome rather than discarding it (per the
        // project's "never silently swallow" convention) — `granted == false`
        // with a nil error is the user-denied case, an Error is the OS-level
        // failure case (rare; transient daemon issues etc.).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error {
                logger.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if granted {
                logger.info("notification authorization granted")
            } else {
                logger.info("notification authorization denied by user")
                // First-run-denied UX (Loop 34): surface a one-time banner
                // so the user understands why "Play sound on attention" is
                // silent. Persisted ack flag prevents re-firing on every
                // launch. Hop to main actor — the auth callback runs on a
                // UNUserNotificationCenter-owned queue.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.settings.notificationDenialAcknowledged { return }
                    self.settings.notificationDenialAcknowledged = true
                    self.surfaceError(
                        "Notifications denied — enable in System Settings",
                        kind: .warning
                    )
                }
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if item.button == nil {
            // Preserve Loop 1 / Loop 14 defensive guard. The icon will populate
            // via `StatusIconController.init` once the backend is `.ready`, so
            // we no longer set a fallback `title` here.
            logger.error("status item button was nil; menu bar entry will be missing")
        }
        statusItem = item
        backend.start()

        // Wire global hotkeys (Task 32). Done once, before backend `.ready`
        // fires — the popover may not exist yet when the user fires the
        // navigate hotkey, but the closure tolerates a nil `popover` (logs
        // and returns) so an early hotkey press is a recoverable no-op.
        wireGlobalShortcuts()

        // Stop the menu-bar flash whenever the popover transitions closed →
        // open. Opening the popover counts as the user acknowledging current
        // alerts (matches FlashController's "user-initiated dismissal"
        // semantic). `dropFirst` skips the published initial value (false) so
        // the very first emission can't satisfy the `false → true` rule on
        // its own; `removeDuplicates` collapses no-op republishes.
        popoverOpenObserver = store.$isPopoverOpen
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isOpen in
                guard let self else { return }
                if isOpen {
                    logger.debug("popover opened; stopping flash")
                    self.flash.stopFlashing()
                }
            }

        // FlashController consults the quiet predicate at `update()` entry, but
        // a mid-flash quiet toggle wouldn't otherwise trigger an `update()` call
        // — so the in-flight flash would keep blinking until the count changes
        // or the cap settles. Subscribe to `quietMode.$quietUntil` directly and
        // call `flash.stopFlashing()` whenever quiet activates.
        quietModeObserver = quietMode.$quietUntil
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.quietMode.isQuiet {
                    logger.debug("quiet mode activated; stopping in-flight flash")
                    self.flash.stopFlashing()
                }
            }

        // Watch backend state. Backend may transition `.starting → .ready`
        // multiple times across respawns (Loop 14 caps at 2 attempts). Each
        // `.ready` may carry a different port, so we always rebuild the
        // APIClient and re-attach it to the store (idempotent: detaches the
        // old client first). The StatusIconController is created once and
        // reuses the same store reference — recreating it on every respawn
        // would leak prior controllers and their refresh timers.
        stateObserverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await s in self.backend.$state.values {
                if Task.isCancelled { return }
                switch s {
                case .ready(let port):
                    let hadController = self.iconController != nil
                    logger.info("backend .ready on port \(port, privacy: .public); rewiring client (controller exists=\(hadController, privacy: .public))")
                    let client = APIClient(port: port)
                    self.store.attach(client: client)
                    if !hadController {
                        self.iconController = StatusIconController(
                            item: item,
                            flash: self.flash,
                            store: self.store
                        )
                        // The popover takes over `statusItem.button`'s
                        // target/action. Created once alongside the icon
                        // controller so subsequent `.ready` transitions
                        // (post-respawn) don't re-bind the button or leak
                        // popover instances.
                        self.popover = PopoverController(
                            statusItem: item,
                            store: self.store,
                            settings: self.settings,
                            quietMode: self.quietMode
                        )
                        // Drain any error buffered before the popover existed
                        // (e.g. the notification-denied warning surfaced from
                        // `requestAuthorization` during early launch). Loop 34.
                        if let pending = self.pendingError {
                            self.pendingError = nil
                            // Persistent (after: 0) — the popover is closed
                            // at this point so an auto-dismiss timer would
                            // tick down before the user could read it.
                            self.popover?.showError(pending.message, kind: pending.kind, after: 0)
                        }
                    }
                case .starting:
                    // Don't detach the store on `.starting` — that's the
                    // transition right before `.ready` and detaching would
                    // briefly clear the UI mid-respawn.
                    logger.debug("backend .starting; leaving store attached during transition")
                case .failed(let reason):
                    logger.error("backend .failed: \(reason, privacy: .public); detaching store from old client")
                    self.store.detach()
                    // If a banner is buffered (e.g. notification-denied from
                    // launch-time requestAuthorization) and the backend never
                    // reached `.ready`, the popover was never built and the
                    // buffer would otherwise leak forever. Surface the message
                    // at `.error` level so it's at least visible in Console.app.
                    if let pending = self.pendingError {
                        logger.error("backend .failed; surfacing buffered banner via log only: \(pending.message, privacy: .public)")
                        self.pendingError = nil
                    }
                case .idle:
                    logger.debug("backend .idle; detaching store")
                    self.store.detach()
                }
            }
        }
    }

    /// Subscribe to the two named global hotkeys declared in
    /// `GlobalShortcuts.swift`. Called once from `applicationDidFinishLaunching`.
    /// `KeyboardShortcuts.onKeyDown(for:)` is safe to call before the user
    /// has assigned a shortcut; subscriptions stay dormant until then. For
    /// `.toggleQuiet` the default of ⌃⌥M is registered on first construction
    /// of the `Name`, so the binding is hot from launch one. For
    /// `.navigateMode` no default ships, so this subscription is dormant
    /// until the user assigns a shortcut (Recorder UI in SettingsView is
    /// deferred to a future loop — for now, programmatic assignment via
    /// `KeyboardShortcuts.setShortcut(_:for:)` is the only path).
    private func wireGlobalShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .navigateMode) { [weak self] in
            guard let self else {
                logger.error("navigateMode hotkey fired after AppDelegate deallocation")
                return
            }
            guard let popover = self.popover else {
                // Promoted `.info` → `.error` for parity with `toggle()`'s
                // no-button log: a hotkey press that does nothing is a
                // user-visible failure, not informational.
                logger.error("navigateMode hotkey fired before popover construction; ignoring")
                return
            }
            popover.openAndEnterNavigateMode()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleQuiet) { [weak self] in
            guard let self else {
                logger.error("toggleQuiet hotkey fired after AppDelegate deallocation")
                return
            }
            self.quietMode.toggle()
        }
    }

    /// Routes a transient error to the popover's toast banner. If the
    /// popover hasn't been constructed yet (early in launch, before backend
    /// `.ready`), the message is buffered in `pendingError` and flushed on
    /// the popover-construction path above. Loop 34.
    ///
    /// `after: 0` means persistent (no auto-dismiss) — used for the
    /// notification-denied warning since the popover is typically closed
    /// when that fires; we want the banner to still be visible the next
    /// time the user opens the popover.
    private func surfaceError(_ message: String, kind: PopoverError.Kind) {
        if let popover {
            popover.showError(message, kind: kind, after: 0)
        } else {
            pendingError = (message, kind)
        }
    }

    /// Composes and posts the "session needs your attention" UNNotification
    /// (Task 33). Called from `FlashController.startFlashing` via the injected
    /// `onFlashStart` hook — so quiet-mode, strict-increase, and "not already
    /// flashing" are all enforced upstream. Sound is opt-in via
    /// `settings.notificationSound`. Errors from the async `add(_:)` call are
    /// logged (not swallowed) — typical failure modes are denied authorization
    /// (logged at request time above) and rare daemon hiccups.
    private func postAttentionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "cc-dashboard"
        content.body = "A session needs your attention."
        if settings.notificationSound { content.sound = .default }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                logger.error("failed to post attention notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cancel the state-observer Task before stopping the backend so its
        // synthetic shutdown state transitions don't drive a final iteration.
        stateObserverTask?.cancel()
        stateObserverTask = nil
        popoverOpenObserver?.cancel()
        popoverOpenObserver = nil
        quietModeObserver?.cancel()
        quietModeObserver = nil
        backend.stop()
    }
}
