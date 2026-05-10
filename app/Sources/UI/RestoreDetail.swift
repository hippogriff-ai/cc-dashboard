// Right-hand detail pane for the Restore tab. Ports
// docs/ux-design/screens.jsx::RestoreTab's `restore-detail` block
// (lines 86–121).
//
// Sections (each conditionally rendered):
//   * Recent prompts (first 4 from `panel.recentPrompts`)
//   * Last assistant message (panel.lastAssistant or repo.lastAssistant fallback)
//   * Open tool at end (when `repo.openTool != nil`)
//   * Uncommitted (panel.diffSummary string verbatim — v1 doesn't parse +/− splits)
//   * Action button row: Resume / Fork / Open in IDE
//
// Loading: a small ProgressView in place of the body sections while the panel
// fetch is in flight.
//
// Action callbacks bubble up to the parent (RestoreTab) so the toast overlay
// lives on the parent and can outlive a row-selection change without flicker.
import SwiftUI
import AppKit

struct RestoreDetail: View {
    let repo: RecentRepo
    let panel: Panel?
    let loading: Bool
    /// When non-nil, the prior panel fetch failed and the detail pane shows a
    /// dismissible error block with a Retry button. This is a separate signal
    /// from `loading == false && panel == nil` (which means "haven't fetched
    /// yet" or "fetched and got empty") so users can distinguish "transient
    /// error, retry me" from "no data".
    let panelError: String?
    let actionsEnabled: Bool
    var onResume: () -> Void
    var onFork: () -> Void
    var onOpenIDE: () -> Void
    var onRetryPanel: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let err = panelError {
                    errorBanner(err)
                } else if loading && panel == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…")
                            .font(.system(size: 11))
                            .foregroundColor(theme.fgTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    promptsSection
                    assistantSection
                    openToolSection
                    diffSection
                }
                buttonRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Icon(name: .warning, size: 11).foregroundColor(theme.uFailed)
                Text("Couldn't load details").fontWeight(.semibold).font(.system(size: 11.5))
            }
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.fgSecondary)
                .lineLimit(3)
                .truncationMode(.tail)
            Button(action: onRetryPanel) {
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
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgRowUrgent)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder
    private var promptsSection: some View {
        if let prompts = panel?.recentPrompts, !prompts.isEmpty {
            let visible = Array(prompts.prefix(4))
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Recent prompts", trailing: "\(prompts.count)")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(">")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.accent)
                            Text(p.display)
                                .font(.system(size: 11.5))
                                .foregroundColor(theme.fgSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assistantSection: some View {
        let text = panel?.lastAssistant.isEmpty == false
            ? (panel?.lastAssistant ?? "")
            : repo.lastAssistant
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Last assistant message", trailing: nil)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundColor(theme.fg)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ZStack(alignment: .leading) {
                            theme.bgElev
                            Rectangle().fill(theme.accent).frame(width: 2)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var openToolSection: some View {
        // Prefer the panel's openTool when the panel has loaded; otherwise
        // fall back to the row's openTool so the section still renders during
        // the brief loading window for repos that have one.
        let tool = panel?.openTool ?? repo.openTool
        if let tool {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Open tool at end", trailing: nil)
                Text(tool.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(theme.accent)
            }
        }
    }

    @ViewBuilder
    private var diffSection: some View {
        if let summary = panel?.diffSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Uncommitted", trailing: nil)
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.fgSecondary)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 6) {
            ActionButton(
                label: "Resume",
                icon: .copy,
                primary: true,
                enabled: actionsEnabled,
                action: onResume
            )
            ActionButton(
                label: "Fork",
                icon: .copy,
                primary: false,
                enabled: actionsEnabled,
                action: onFork
            )
            ActionButton(
                label: "Open in IDE",
                icon: .ide,
                primary: false,
                enabled: actionsEnabled,
                action: onOpenIDE
            )
        }
        .padding(.top, 4)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.fgTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundColor(theme.fgTertiary)
            }
        }
    }
}

/// Small button styled to match `.btn` / `.btn.primary` from styles.css.
/// Renders the icon at 11pt + label, with a primary (accent fill) variant.
private struct ActionButton: View {
    let label: String
    let icon: IconName
    let primary: Bool
    let enabled: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Icon(name: icon, size: 11)
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(primary ? theme.accent : theme.bgElev)
            .foregroundColor(primary ? .white : theme.fg)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(theme.separator, lineWidth: primary ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.5)
    }
}
