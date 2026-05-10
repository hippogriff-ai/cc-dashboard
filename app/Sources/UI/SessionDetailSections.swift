// Section views for `SessionDetailView`. Ports the body sections of
// docs/ux-design/screens.jsx::SessionDetail (lines 275–407).
//
// Each section is a self-contained struct that takes the relevant slice of
// `SessionDetail` plus a theme from the environment. Keeping them as separate
// views (rather than `@ViewBuilder` helpers on `SessionDetailView`) makes the
// component tree shallower at the call site and lets each section's
// conditional-render logic live next to its own data.
//
// `fmtTokens` is a pure helper used by `TokenUsageSection` for the three stat
// cells and the meta line under the bar; living here keeps the formatter
// close to its single consumer.
import SwiftUI

// MARK: - Branch timeline

struct BranchTimelineSection: View {
    let history: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Branch timeline", trailing: nil, theme: theme)
            HStack(spacing: 4) {
                ForEach(Array(history.enumerated()), id: \.offset) { idx, b in
                    if idx > 0 {
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundColor(theme.fgQuaternary)
                    }
                    Text(b)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(idx == history.count - 1 ? theme.accent : theme.fgSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.bgElev)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Files changed

struct FilesChangedSection: View {
    let files: [FileTouch]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Files changed", trailing: "\(files.count)", theme: theme)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(files) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        fileNameView(f.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(f.edits) edit\(f.edits == 1 ? "" : "s")")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(theme.fgTertiary)
                        // `lastTouch` is seconds-epoch on the wire; `RelTime`
                        // expects ms-epoch — multiply.
                        Text(RelTime.format(f.lastTouch * 1000))
                            .font(.system(size: 10.5))
                            .foregroundColor(theme.fgTertiary)
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fileNameView(_ path: String) -> some View {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let name = parts.last ?? path
        let dir = parts.dropLast().joined(separator: "/")
        if dir.isEmpty {
            Text(name)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(theme.fg)
        } else {
            (
                Text("\(dir)/")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(theme.fgTertiary)
                + Text(name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(theme.fg)
            )
        }
    }
}

// MARK: - Token usage

struct TokenUsageSection: View {
    let tokens: Tokens
    @Environment(\.theme) private var theme

    private var totalContext: Int {
        max(0, tokens.input + tokens.cachedRead + tokens.cachedCreate + tokens.output)
    }

    private var ctxPct: Double {
        guard tokens.contextLimit > 0 else { return 0 }
        return min(100, Double(totalContext) / Double(tokens.contextLimit) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOKEN USAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.fgTertiary)
                Spacer()
                if ctxPct > 80 {
                    Text("\(Int(ctxPct.rounded()))% — consider /compact")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.uPermission)
                }
            }
            HStack(spacing: 8) {
                tokenStat(label: "Input", value: tokens.input)
                tokenStat(label: "Cached", value: tokens.cachedRead + tokens.cachedCreate)
                tokenStat(label: "Output", value: tokens.output)
            }
            tokenBar
            HStack {
                if tokens.contextLimit > 0 {
                    Text("\(fmtTokens(totalContext)) / \(fmtTokens(tokens.contextLimit))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(theme.fgTertiary)
                    Spacer()
                    Text(String(format: "%.1f%%", ctxPct))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(theme.fgTertiary)
                } else {
                    // Don't show "12.3k / 0" with "0.0%" — that's a meaningless
                    // misleading display. Surface the schema oddity explicitly.
                    Text("\(fmtTokens(totalContext)) used · context limit unavailable")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(theme.uFailed)
                    Spacer()
                }
            }
        }
    }

    private func tokenStat(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.fgTertiary)
            Text(fmtTokens(value))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.fg)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var tokenBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.bgElev)
                Rectangle()
                    .fill(ctxPct > 80 ? theme.uPermission : theme.accent)
                    .frame(width: geo.size.width * CGFloat(ctxPct / 100))
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

// MARK: - Load history

struct LoadHistorySection: View {
    let history: [Int]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOAD OVER TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.fgTertiary)
                Spacer()
                Text("tool_use / min")
                    .font(.system(size: 10))
                    .foregroundColor(theme.fgTertiary)
            }
            Sparkline(data: history, color: theme.uWorking)
        }
    }
}

// MARK: - Last assistant

struct LastAssistantSection: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Last assistant message", trailing: nil, theme: theme)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(theme.fg)
                .lineLimit(6)
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

// MARK: - Open tool

struct OpenToolSection: View {
    let tool: OpenTool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Open tool", trailing: nil, theme: theme)
            Text(tool.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.accent)
        }
    }
}

// MARK: - Decisions

struct DecisionsSection: View {
    let pairs: [DecisionPair]
    @Environment(\.theme) private var theme

    var body: some View {
        if pairs.isEmpty {
            // Skip section entirely when empty (per task spec). Returning
            // EmptyView keeps the parent VStack rhythm correct.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Decisions for this repo", trailing: "\(pairs.count)", theme: theme)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pairs) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(">")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.fgTertiary)
                                Text(d.q)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(theme.fgSecondary)
                                    .lineLimit(2)
                            }
                            Text(d.a)
                                .font(.system(size: 11.5))
                                .foregroundColor(theme.fg)
                                .lineLimit(3)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Action row

/// Four-button action strip mirroring `RestoreDetail`'s `ActionButton` style.
/// Focus terminal is reserved for Task 30 (Phase 5 keyboard nav); rendered
/// disabled here so the visual layout matches the spec without exposing a
/// silently-broken click target.
struct ActionRow: View {
    var onResume: () -> Void
    var onFork: () -> Void
    var onOpenIDE: () -> Void
    var onFocus: () -> Void
    var enabled: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            DetailActionButton(
                label: "Focus",
                icon: .terminal,
                primary: true,
                enabled: false,
                action: onFocus
            )
            DetailActionButton(
                label: "Resume",
                icon: .copy,
                primary: false,
                enabled: enabled,
                action: onResume
            )
            DetailActionButton(
                label: "Fork",
                icon: .copy,
                primary: false,
                enabled: enabled,
                action: onFork
            )
            DetailActionButton(
                label: "Open in IDE",
                icon: .ide,
                primary: false,
                enabled: enabled,
                action: onOpenIDE
            )
        }
    }
}

/// Mirrors `RestoreDetail.swift`'s `ActionButton` (private there). Duplicated
/// here rather than promoted to a shared file to keep this loop's blast
/// radius narrow; can be unified in a polish pass.
private struct DetailActionButton: View {
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

// MARK: - Shared section header

@ViewBuilder
private func sectionHeader(_ title: String, trailing: String?, theme: ThemePalette) -> some View {
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

// MARK: - fmtTokens

/// Compact token formatter:
///   * negative → clamped to 0 ("0")
///   * < 1000   → "234"
///   * < 10_000 → "1.2k" (one decimal)
///   * < 1M     → "12k"  (rounded)
///   * >= 1M    → "1.2M"
///
/// Negative clamp guards against backend bugs that emit negative cumulative
/// counters; rendering "-1.2k" in a token cell would mislead users about
/// context budget. Very-large clamp (>= 1M) lets future pricing tiers with
/// 10M+ context windows render without overflowing the cell.
func fmtTokens(_ raw: Int) -> String {
    let n = max(0, raw)
    if n < 1000 { return "\(n)" }
    if n < 10_000 {
        let v = Double(n) / 1000.0
        return String(format: "%.1fk", v)
    }
    if n < 1_000_000 {
        return "\(n / 1000)k"
    }
    let v = Double(n) / 1_000_000.0
    return String(format: "%.1fM", v)
}
