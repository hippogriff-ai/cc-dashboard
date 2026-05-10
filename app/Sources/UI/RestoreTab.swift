// Restore tab body for the popover. Ports
// docs/ux-design/screens.jsx::RestoreTab (lines 45–127).
//
// Two states:
//   * Empty (when `store.recent` is empty) — search icon + "Nothing here yet"
//     + body copy matching the JSX verbatim.
//   * Populated — two-pane HStack: list (~165pt) on the left, detail
//     (remaining ~215pt) on the right. PopoverShell pins the width to 380pt.
//
// Selection model: `selectedId` is the cwd of the chosen `RecentRepo` (since
// `RecentRepo.id == cwd`). On selection change, kick a `Task` to fetch the
// `Panel` lazily via `store.apiClient?.panel(...)`. The panel stays cached
// until the next selection change.
//
// Toast overlay: action results (Resume/Fork copy success, Open-IDE outcome,
// or any error) surface via a 2.5s overlay that auto-dismisses. The overlay
// lives on the tab (not on RestoreDetail) so it survives row-selection
// changes that re-render the detail pane.
import SwiftUI
import AppKit
import os

struct RestoreTab: View {
    @ObservedObject var store: PollingStore
    @State private var selectedId: String? = nil
    @State private var panel: Panel? = nil
    @State private var panelError: String? = nil
    @State private var loadingPanel: Bool = false
    @State private var toast: Toast? = nil
    @State private var toastToken: UUID = UUID()
    @State private var toastDismissTask: Task<Void, Never>? = nil
    /// Monotonic counter used to discard stale panel-fetch responses when the
    /// user re-clicks the same row before the prior fetch completes.
    @State private var panelFetchToken: Int = 0
    /// Set of cwds whose directories don't exist on disk. Refreshed off the
    /// main thread when `store.recent` changes; rows query via Set membership
    /// rather than running `FileManager.fileExists` per render (which would
    /// stat() every cwd on the main thread on every body re-evaluation).
    @State private var missingCwds: Set<String> = []
    @Environment(\.theme) private var theme

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "RestoreTab")

    var body: some View {
        Group {
            if store.recent.isEmpty {
                emptyState
            } else {
                splitView
            }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                ToastView(toast: t)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toast?.message)
        .onChange(of: store.recent.map(\.cwd)) { newCwds in
            // Drop selection if the previously-selected repo aged out of the
            // 14-day window (otherwise the detail pane silently shows
            // "Select a repo…" while panel state lingers).
            if let id = selectedId, !newCwds.contains(id) {
                selectedId = nil
                panel = nil
                panelError = nil
            }
            // Recompute the missing-cwd set off the main thread so the per-row
            // existence check stays out of `body`.
            Task.detached {
                let missing = Set(newCwds.filter { !FileManager.default.fileExists(atPath: $0) })
                await MainActor.run { missingCwds = missing }
            }
        }
        .onAppear {
            // Initial population on first render so rows don't flash as
            // "exists" before the .onChange fires.
            let cwds = store.recent.map(\.cwd)
            Task.detached {
                let missing = Set(cwds.filter { !FileManager.default.fileExists(atPath: $0) })
                await MainActor.run { missingCwds = missing }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(name: .search, size: 22).foregroundColor(theme.fgTertiary)
            Text("Nothing here yet").fontWeight(.semibold)
            Text("No sessions in the last 14 days. Sessions show up here once you've used Claude Code.")
                .font(.system(size: 12))
                .foregroundColor(theme.fgSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 165)
            Rectangle()
                .fill(theme.separator)
                .frame(width: 1)
            detailPane
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.recent) { repo in
                    RestoreRow(
                        repo: repo,
                        isSelected: selectedId == repo.id,
                        cwdMissing: missingCwds.contains(repo.cwd),
                        onTap: { select(repo) }
                    )
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedId, let repo = store.recent.first(where: { $0.id == id }) {
            RestoreDetail(
                repo: repo,
                panel: panel,
                loading: loadingPanel,
                panelError: panelError,
                actionsEnabled: store.apiClient != nil,
                onResume: { performResume(repo: repo) },
                onFork: { performFork(repo: repo) },
                onOpenIDE: { performOpenIDE(repo: repo) },
                onRetryPanel: { select(repo, force: true) }
            )
        } else {
            VStack {
                Spacer()
                Text("Select a repo to see where you left off.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.fgTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Selection / panel fetch

    private func select(_ repo: RecentRepo, force: Bool = false) {
        if !force && selectedId == repo.id { return }
        selectedId = repo.id
        panel = nil
        panelError = nil
        loadingPanel = true
        panelFetchToken &+= 1
        let token = panelFetchToken
        let cwd = repo.cwd
        let sid = repo.sessionId
        Task { @MainActor in
            guard let client = store.apiClient else {
                if token == panelFetchToken {
                    loadingPanel = false
                    panelError = "Backend not connected"
                }
                Self.logger.error("panel fetch skipped: no apiClient attached")
                return
            }
            do {
                let p = try await client.panel(cwd: cwd, sid: sid)
                // Drop the result if the user moved on, retried, or the
                // backend respawned mid-flight (apiClient identity changed).
                guard token == panelFetchToken else { return }
                guard store.apiClient === client else {
                    Self.logger.info("dropping stale panel result: apiClient changed mid-fetch")
                    return
                }
                panel = p
                panelError = nil
            } catch {
                Self.logger.error("panel fetch failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if token == panelFetchToken {
                    panelError = "Couldn't load panel: \(error.localizedDescription)"
                }
            }
            if token == panelFetchToken {
                loadingPanel = false
            }
        }
    }

    // MARK: - Actions

    /// Identity-checks `store.apiClient` against the captured client after the
    /// await — if the backend respawned mid-action, the result is from a now-
    /// stale connection and shouldn't be presented to the user as authoritative.
    private func isClientStillCurrent(_ client: APIClient) -> Bool {
        store.apiClient === client
    }

    private func performResume(repo: RecentRepo) {
        guard let client = store.apiClient else {
            showToast("Backend not connected", kind: .error)
            return
        }
        let cwd = repo.cwd
        let sid = repo.sessionId
        Task { @MainActor in
            do {
                let r = try await client.resume(cwd: cwd, sid: sid)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale resume result: apiClient changed mid-action")
                    return
                }
                if copyToClipboard(r.command) {
                    showToast("Copied resume command", kind: .success)
                } else {
                    Self.logger.error("pasteboard write failed for resume command")
                    showToast("Couldn't copy to clipboard", kind: .error)
                }
            } catch {
                Self.logger.error("resume failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showToast("Resume failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func performFork(repo: RecentRepo) {
        guard let client = store.apiClient else {
            showToast("Backend not connected", kind: .error)
            return
        }
        let cwd = repo.cwd
        let sid = repo.sessionId
        Task { @MainActor in
            do {
                let r = try await client.fork(cwd: cwd, sid: sid)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale fork result: apiClient changed mid-action")
                    return
                }
                if copyToClipboard(r.summary) {
                    showToast("Copied fork summary", kind: .success)
                } else {
                    Self.logger.error("pasteboard write failed for fork summary")
                    showToast("Couldn't copy to clipboard", kind: .error)
                }
            } catch {
                Self.logger.error("fork failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showToast("Fork failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func performOpenIDE(repo: RecentRepo) {
        guard let client = store.apiClient else {
            showToast("Backend not connected", kind: .error)
            return
        }
        let cwd = repo.cwd
        Task { @MainActor in
            do {
                let r = try await client.openIde(cwd: cwd)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale openIde result: apiClient changed mid-action")
                    return
                }
                if r.ok {
                    let label = r.ide ?? "IDE"
                    showToast("Opened in \(label)", kind: .success)
                } else {
                    let detail = r.error ?? r.detail ?? "unknown error"
                    Self.logger.error("openIde returned ok=false cwd=\(cwd, privacy: .public) detail=\(detail, privacy: .public)")
                    showToast("Open in IDE failed: \(detail)", kind: .error)
                }
            } catch {
                Self.logger.error("openIde failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showToast("Open in IDE failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    /// Returns true on successful pasteboard write. `setString(_:forType:)` can
    /// return false if another app holds the pasteboard or sandboxing rules
    /// reject the write — the toast must reflect actual outcome, not assume.
    private func copyToClipboard(_ s: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(s, forType: .string)
    }

    // MARK: - Toast

    private func showToast(_ message: String, kind: Toast.Kind) {
        toastDismissTask?.cancel()
        toast = Toast(message: message, kind: kind)
        let myToken = UUID()
        toastToken = myToken
        toastDismissTask = Task { @MainActor in
            // 2.5s feels long enough to read a multi-word toast without blocking
            // a follow-up action from a fast user.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            // Only clear if THIS task's toast is still the current one. A new
            // toast (with its own token) may have replaced ours; cancellation
            // is racy under SwiftUI's main-runloop scheduling, but token
            // identity is deterministic.
            if myToken == toastToken {
                toast = nil
            }
        }
    }
}

/// Small payload struct for the toast overlay. `Equatable` so SwiftUI's
/// `animation(value:)` can detect message changes without identity tricks.
struct Toast: Equatable {
    let message: String
    let kind: Kind

    enum Kind: Equatable {
        case success
        case error
    }
}

private struct ToastView: View {
    let toast: Toast
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Icon(name: toast.kind == .success ? .idle : .warning, size: 11)
                .foregroundColor(toast.kind == .success ? theme.uIdle : theme.uFailed)
            Text(toast.message)
                .font(.system(size: 11.5))
                .foregroundColor(theme.fg)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 12)
    }
}
