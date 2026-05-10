import Foundation
import Combine
import os

/// Observable session-state store: polls the sidecar's live/recent endpoints
/// and exposes a sorted `sessions` array plus an `attentionCount` derived from
/// the ranker's event field. Owned by the menu-bar UI; `@MainActor` so all
/// `@Published` mutations happen on the main thread.
@MainActor
final class PollingStore: ObservableObject {
    @Published private(set) var sessions: [LiveSession] = []
    @Published private(set) var recent: [RecentRepo] = []
    @Published private(set) var ide: String = "Finder"
    @Published var isPopoverOpen: Bool = false

    /// Most recent failure reason from either poll, or nil when the last poll
    /// of the corresponding endpoint succeeded. UI layers (Task 26+) can render
    /// a "disconnected" pip when this is non-nil for >3× the poll interval.
    @Published private(set) var lastError: String?
    /// Wall-clock timestamp of the last successful `refreshLive`. Combined with
    /// `lastError`, lets UI surface "stale data" without coupling to error type.
    @Published private(set) var lastSuccessfulPoll: Date?
    /// Derived UI-friendly view of `lastError` + `lastSuccessfulPoll`. Recomputed
    /// after every refresh AND on a 2s heartbeat — the heartbeat matters because
    /// `.connected → .stale` is a duration-elapsed transition that no refresh
    /// will trigger (a backend that's gone silent never calls back). Loop 37.
    @Published private(set) var connectionStatus: ConnectionStatus = .connecting
    private var connectionTimer: Timer?

    /// Read-only public access for action callers (RestoreDetail's resume/fork/
    /// open-IDE etc.). Published so that views observing the store re-render
    /// when the client is detached during a backend respawn — actions that
    /// depend on it can disable themselves rather than appear-tappable-but-no-op.
    @Published private(set) var apiClient: APIClient?
    private var liveTimer: Timer?
    private var recentTimer: Timer?
    private let pollLive: TimeInterval = 2.0
    private let pollRecent: TimeInterval = 4.0

    private var isRefreshingLive = false
    private var isRefreshingRecent = false

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "PollingStore")

    func attach(client: APIClient) {
        self.apiClient = client
        startPolling()
    }

    func detach() {
        liveTimer?.invalidate()
        liveTimer = nil
        recentTimer?.invalidate()
        recentTimer = nil
        connectionTimer?.invalidate()
        connectionTimer = nil
        apiClient = nil
        // Detaching means the backend is gone; reset to .connecting so the UI
        // doesn't briefly flash a stale "stale" pip from the previous attach.
        connectionStatus = .connecting
    }

    deinit {
        // `Timer.invalidate()` is thread-safe and the only main-actor cleanup
        // strictly necessary; `client` will dealloc with us. This prevents the
        // run loop from holding a strong reference past the store's lifetime.
        liveTimer?.invalidate()
        recentTimer?.invalidate()
        connectionTimer?.invalidate()
    }

    private func startPolling() {
        // Idempotent: callers that re-`attach()` should not leak the previous timers.
        // `detach()` invalidates timers AND nils the client, so we re-set the client
        // immediately below to preserve attach()'s post-condition.
        let savedClient = self.apiClient
        detach()
        self.apiClient = savedClient

        // Schedule on the main run loop in `.common` modes so polls keep firing
        // during menu / popover tracking — the exact UI scenario this store
        // exists for. `Timer.scheduledTimer` would only register in `.default`.
        let live = Timer(timeInterval: pollLive, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLive() }
        }
        RunLoop.main.add(live, forMode: .common)
        liveTimer = live

        let recent = Timer(timeInterval: pollRecent, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshRecentIfNeeded() }
        }
        RunLoop.main.add(recent, forMode: .common)
        recentTimer = recent

        // Heartbeat for connectionStatus. Without this, a backend that goes
        // silent (no thrown error from refreshLive — e.g. process killed
        // mid-flight, the poll just never returns) leaves us indefinitely on
        // `.connected` because no `catch` block fires to re-evaluate. The
        // heartbeat re-checks `now - lastSuccessfulPoll` every 2s.
        let heartbeat = Timer(timeInterval: pollLive, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeConnectionStatus() }
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        connectionTimer = heartbeat

        // Immediate kick on both endpoints so the popover is populated before
        // the first timer interval elapses.
        Task { @MainActor in await refreshLive() }
        Task { @MainActor in await refreshRecentIfNeeded() }
    }

    func refreshLive() async {
        guard !isRefreshingLive else {
            Self.logger.debug("refreshLive skipped: already in flight")
            return
        }
        guard let c = apiClient else {
            Self.logger.debug("refreshLive skipped: no client attached")
            return
        }
        isRefreshingLive = true
        defer { isRefreshingLive = false }
        do {
            let r = try await c.live()
            self.sessions = Self.sort(r.sessions)
            self.ide = r.ide
            self.lastError = nil
            self.lastSuccessfulPoll = Date()
            self.recomputeConnectionStatus()
        } catch {
            let detail = "endpoint=/api/live error=\(String(reflecting: error))"
            Self.logger.error("refreshLive failed: \(detail, privacy: .public)")
            self.lastError = detail
            self.recomputeConnectionStatus()
        }
    }

    func refreshRecentIfNeeded() async {
        guard !isRefreshingRecent else {
            Self.logger.debug("refreshRecentIfNeeded skipped: already in flight")
            return
        }
        guard let c = apiClient else {
            Self.logger.debug("refreshRecentIfNeeded skipped: no client attached")
            return
        }
        isRefreshingRecent = true
        defer { isRefreshingRecent = false }
        do {
            let r = try await c.recent()
            self.recent = r.repos
            // NOTE: do NOT also write self.ide here. `refreshLive` is the single
            // source of truth for the IDE field; this refresher polls at half
            // the cadence and writing both would race the UI to flicker between
            // values whenever the two endpoints disagree mid-IDE-switch.
        } catch {
            let detail = "endpoint=/api/recent error=\(String(reflecting: error))"
            Self.logger.error("refreshRecentIfNeeded failed: \(detail, privacy: .public)")
            self.lastError = detail
            self.recomputeConnectionStatus()
        }
    }

    /// Recompute `connectionStatus` from the current `lastError` /
    /// `lastSuccessfulPoll` snapshot. Called from every refresh outcome AND
    /// from the 2s heartbeat. Wraps the pure logic (`computeStatus`) so the
    /// state machine is testable without spinning up timers.
    private func recomputeConnectionStatus() {
        let next = Self.computeStatus(
            lastError: lastError,
            lastSuccessfulPoll: lastSuccessfulPoll,
            now: Date(),
            staleAfter: pollLive * 3
        )
        if next != connectionStatus { connectionStatus = next }
    }

    /// Pure status-derivation logic. Exposed `static nonisolated` so tests can
    /// drive it directly with synthetic `Date`s without an actor hop. Rules:
    /// - No successful poll yet → `.connecting` (initial state).
    /// - Latest poll succeeded (`lastError == nil`) → `.connected`.
    /// - Latest poll failed but the last success is recent (≤ staleAfter) →
    ///   `.connected` (transient hiccup; don't flash a pip the user can't act on).
    /// - Latest poll failed AND no success in `staleAfter` seconds → `.stale(elapsed)`.
    nonisolated static func computeStatus(
        lastError: String?,
        lastSuccessfulPoll: Date?,
        now: Date,
        staleAfter: TimeInterval
    ) -> ConnectionStatus {
        guard let last = lastSuccessfulPoll else { return .connecting }
        let elapsed = now.timeIntervalSince(last)
        if lastError == nil { return .connected }
        if elapsed <= staleAfter { return .connected }
        return .stale(secondsSinceSuccess: Int(elapsed))
    }

    /// Ranker-aware ordering: sort by `priority` ascending (the backend ranker
    /// emits 0–99 with 0 = most urgent, so lower wins), then by `lastActivity`
    /// descending so newer activity bubbles up within the same priority bucket.
    /// `nonisolated` because it is a pure function over its argument and must
    /// be callable from XCTest synchronous contexts.
    nonisolated static func sort(_ xs: [LiveSession]) -> [LiveSession] {
        xs.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.lastActivity > $1.lastActivity
        }
    }

    /// Attention-event count for a given session list. Extracted as a static
    /// helper so tests can exercise the rule without needing to mutate the
    /// `private(set) var sessions` on a live `PollingStore` instance.
    /// `nonisolated` for the same reason as `sort(_:)`.
    nonisolated static func attentionCount(of xs: [LiveSession]) -> Int {
        xs.filter { $0.event == .permissionPending || $0.event == .toolFailed || $0.event == .ask }.count
    }

    var attentionCount: Int { Self.attentionCount(of: sessions) }
}

/// Three-state view of the sidecar connection. UI renders a small pip in
/// PopHeader only when `.stale` — `.connecting` and `.connected` are both
/// "things are fine, don't bother the user". The associated `Int` on
/// `.stale` is whole seconds since the last success, for display.
enum ConnectionStatus: Equatable {
    case connecting
    case connected
    case stale(secondsSinceSuccess: Int)
}
