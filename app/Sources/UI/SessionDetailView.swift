// Push-navigation detail view for a single live session. Ports
// docs/ux-design/screens.jsx::SessionDetail (lines 275–407).
//
// Header: back-arrow + repo title + meta line (branch icon + branch + age +
// source) + urgency chip (color + icon mirroring `SessionRow`). Body: a
// scrollable column of section views from `SessionDetailSections.swift`.
//
// The view fetches `SessionDetail` lazily on `.task` via
// `APIClient.sessionDetail(sid:)`, and uses the same fetch-token + apiClient
// identity guards as `RestoreTab.select(_:)` so a backend respawn or rapid
// retry can't flash stale data.
//
// Action callbacks (Resume / Fork / Open IDE) log on error; toast surface
// will land in a polish loop. Focus is rendered disabled — Task 30 territory.
import SwiftUI
import AppKit
import os

struct SessionDetailView: View {
    @ObservedObject var store: PollingStore
    let session: LiveSession
    var onBack: () -> Void
    @State private var detail: SessionDetail? = nil
    @State private var loading: Bool = true
    @State private var fetchError: String? = nil
    @State private var fetchToken: Int = 0
    /// Single shared in-flight flag for the action row — Resume / Fork /
    /// Open IDE all share it. The intent is "no concurrent actions" since
    /// they target the same session and most users wouldn't expect them to
    /// race. Per-action flags would be a small UX win but extra plumbing.
    @State private var actionInFlight: Bool = false
    /// User-visible feedback for the most recent Resume/Fork/Open-IDE call.
    /// Auto-dismisses after 2.5s. Without this, success and failure are
    /// visually identical (the spinner just disappears) — the silent-failure
    /// pattern this codebase forbids.
    @State private var actionStatus: ActionStatus? = nil
    @State private var actionStatusToken: UUID = UUID()
    @State private var actionDismissTask: Task<Void, Never>? = nil
    @Environment(\.theme) private var theme

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "SessionDetailView")

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: fetchToken) { await fetch() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onBack) {
                Icon(name: .arrowBack, size: 14)
                    .foregroundColor(theme.fgSecondary)
                    .padding(6)
                    .background(theme.bgElev)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.repo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.fg)
                    .lineLimit(1)
                metaLine
            }

            Spacer()

            urgencyChip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if let branch = session.branch, !branch.isEmpty {
                Icon(name: .branch, size: 11)
                    .foregroundColor(theme.fgTertiary)
                Text(branch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.fgSecondary)
                Text("·").foregroundColor(theme.fgQuaternary)
            }
            // Sub-minute age renders as "<1m" rather than "0m" — "0m" reads
            // as missing data; "<1m" is unambiguous "just started".
            Text(formattedAge(session.ageSec))
                .font(.system(size: 11))
                .foregroundColor(theme.fgSecondary)
            Text("·").foregroundColor(theme.fgQuaternary)
            Text(detail?.source ?? "cc")
                .font(.system(size: 11))
                .foregroundColor(theme.fgSecondary)
        }
    }

    private var urgencyChip: some View {
        HStack(spacing: 4) {
            Icon(name: urgencyIcon, size: 12)
                .foregroundColor(urgencyColor)
            Text(urgencyLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(urgencyColor)
        }
    }

    private var urgencyColor: Color {
        switch session.event {
        case .permissionPending: return theme.uPermission
        case .toolFailed: return theme.uFailed
        case .ask: return theme.uAsk
        case .working: return theme.uWorking
        case .idleAfterComplete: return theme.uIdle
        case .clear: return theme.uClear
        }
    }

    private var urgencyIcon: IconName {
        switch session.event {
        case .permissionPending: return .permission
        case .toolFailed: return .failed
        case .ask: return .ask
        case .working: return .working
        case .idleAfterComplete: return .idle
        case .clear: return .clear
        }
    }

    private var urgencyLabel: String {
        switch session.event {
        case .permissionPending: return "Permission"
        case .toolFailed: return "Failed"
        case .ask: return "Asking"
        case .working: return "Working"
        case .idleAfterComplete: return "Idle"
        case .clear: return "Clear"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let err = fetchError {
            errorState(err)
        } else if loading && detail == nil {
            loadingState
        } else if let d = detail {
            sectionsList(d)
        } else {
            // No error, no data, not loading — defensive empty state.
            VStack {
                Spacer()
                Text("No detail available.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.fgTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading session detail…")
                .font(.system(size: 11))
                .foregroundColor(theme.fgTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(name: .warning, size: 12).foregroundColor(theme.uFailed)
                Text("Couldn't load session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.fg)
            }
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.fgSecondary)
                .lineLimit(4)
                .truncationMode(.tail)
            Button(action: { fetchToken &+= 1 }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.bgElev)
                    .foregroundColor(theme.fg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(theme.separator, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func sectionsList(_ d: SessionDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !d.branchHistory.isEmpty {
                    BranchTimelineSection(history: d.branchHistory)
                }
                if !d.filesChanged.isEmpty {
                    FilesChangedSection(files: d.filesChanged)
                }
                TokenUsageSection(tokens: d.tokens)
                if !d.loadHistory.isEmpty {
                    LoadHistorySection(history: d.loadHistory)
                }
                if !d.lastAssistant.isEmpty {
                    LastAssistantSection(text: d.lastAssistant)
                }
                if let tool = d.openTool {
                    OpenToolSection(tool: tool)
                }
                DecisionsSection(pairs: d.decisions)
                ActionRow(
                    onResume: { performResume() },
                    onFork: { performFork() },
                    onOpenIDE: { performOpenIDE() },
                    onFocus: { /* Task 30 territory; button is disabled. */ },
                    enabled: store.apiClient != nil && !actionInFlight
                )
                .padding(.top, 4)
                if let status = actionStatus {
                    actionStatusPill(status)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.15), value: actionStatus?.message)
        }
    }

    private func actionStatusPill(_ status: ActionStatus) -> some View {
        HStack(spacing: 6) {
            Icon(name: status.kind == .success ? .idle : .warning, size: 11)
                .foregroundColor(status.kind == .success ? theme.uIdle : theme.uFailed)
            Text(status.message)
                .font(.system(size: 11.5))
                .foregroundColor(theme.fg)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func showActionStatus(_ message: String, kind: ActionStatus.Kind) {
        actionDismissTask?.cancel()
        actionStatus = ActionStatus(message: message, kind: kind)
        let myToken = UUID()
        actionStatusToken = myToken
        actionDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if myToken == actionStatusToken {
                actionStatus = nil
            }
        }
    }

    private func formattedAge(_ ageSec: Int) -> String {
        let s = max(0, ageSec)
        if s < 60 { return "<1m" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }

    // MARK: - Fetch

    private func fetch() async {
        let token = fetchToken
        loading = true
        fetchError = nil
        // Clear stale data on retry. Without this, a Retry click after a
        // successful fetch leaves the prior `detail` visible while the new
        // fetch runs (loading branch only fires when `detail == nil`), so the
        // user sees no progress feedback during retries.
        if token > 0 { detail = nil }
        guard let client = store.apiClient else {
            // Stay loud — surfacing "Backend not connected" lets the user
            // distinguish this from a transient HTTP error.
            if token == fetchToken {
                loading = false
                fetchError = "Backend not connected"
            }
            Self.logger.error("session-detail fetch skipped: no apiClient attached")
            return
        }
        let sid = session.sessionId
        do {
            let d = try await client.sessionDetail(sid: sid)
            // Drop the result if the user retried, navigated away, or the
            // backend respawned mid-flight (apiClient identity changed).
            guard token == fetchToken else { return }
            guard store.apiClient === client else {
                Self.logger.info("dropping stale session-detail result: apiClient changed mid-fetch")
                return
            }
            detail = d
            fetchError = nil
            loading = false
        } catch {
            Self.logger.error("session-detail fetch failed sid=\(sid, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
            if token == fetchToken {
                fetchError = "Couldn't load session detail: \(error.localizedDescription)"
                loading = false
            }
        }
    }

    // MARK: - Actions

    private func isClientStillCurrent(_ client: APIClient) -> Bool {
        store.apiClient === client
    }

    private func performResume() {
        guard let client = store.apiClient else {
            Self.logger.error("resume skipped: no apiClient attached")
            showActionStatus("Backend not connected", kind: .error)
            return
        }
        let cwd = session.cwd
        let sid = session.sessionId
        actionInFlight = true
        Task { @MainActor in
            defer { actionInFlight = false }
            do {
                let r = try await client.resume(cwd: cwd, sid: sid)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale resume result: apiClient changed mid-action")
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                if pb.setString(r.command, forType: .string) {
                    showActionStatus("Copied resume command", kind: .success)
                } else {
                    Self.logger.error("pasteboard write failed for resume command")
                    showActionStatus("Couldn't copy to clipboard", kind: .error)
                }
            } catch {
                Self.logger.error("resume failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showActionStatus("Resume failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func performFork() {
        guard let client = store.apiClient else {
            Self.logger.error("fork skipped: no apiClient attached")
            showActionStatus("Backend not connected", kind: .error)
            return
        }
        let cwd = session.cwd
        let sid = session.sessionId
        actionInFlight = true
        Task { @MainActor in
            defer { actionInFlight = false }
            do {
                let r = try await client.fork(cwd: cwd, sid: sid)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale fork result: apiClient changed mid-action")
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                if pb.setString(r.summary, forType: .string) {
                    showActionStatus("Copied fork summary", kind: .success)
                } else {
                    Self.logger.error("pasteboard write failed for fork summary")
                    showActionStatus("Couldn't copy to clipboard", kind: .error)
                }
            } catch {
                Self.logger.error("fork failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showActionStatus("Fork failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func performOpenIDE() {
        guard let client = store.apiClient else {
            Self.logger.error("openIde skipped: no apiClient attached")
            showActionStatus("Backend not connected", kind: .error)
            return
        }
        let cwd = session.cwd
        actionInFlight = true
        Task { @MainActor in
            defer { actionInFlight = false }
            do {
                let r = try await client.openIde(cwd: cwd)
                guard isClientStillCurrent(client) else {
                    Self.logger.info("dropping stale openIde result: apiClient changed mid-action")
                    return
                }
                if r.ok {
                    let label = r.ide ?? "IDE"
                    showActionStatus("Opened in \(label)", kind: .success)
                } else {
                    let detailMsg = r.error ?? r.detail ?? "unknown error"
                    Self.logger.error("openIde returned ok=false cwd=\(cwd, privacy: .public) detail=\(detailMsg, privacy: .public)")
                    showActionStatus("Open in IDE failed: \(detailMsg)", kind: .error)
                }
            } catch {
                Self.logger.error("openIde failed cwd=\(cwd, privacy: .public) error=\(String(reflecting: error), privacy: .public)")
                if isClientStillCurrent(client) {
                    showActionStatus("Open in IDE failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }
}

/// Inline pill shown beneath the ActionRow with the result of the most recent
/// Resume/Fork/Open-IDE call. Auto-dismisses after 2.5s.
struct ActionStatus: Equatable {
    let message: String
    let kind: Kind
    enum Kind: Equatable { case success, error }
}
