// SwiftUI port of docs/ux-design/icons.jsx. Each glyph is drawn into a 16×16
// canvas to match the source SVG `viewBox`, then scaled to the requested
// `size`. Stroke-based glyphs use a 1.4pt round-cap/round-join line to mirror
// the React component's defaults; filled glyphs (e.g. `stackFilled`, `bolt`)
// fill the path explicitly.
//
// Missing/unimplemented glyphs fall through to a visible filled-square
// fallback so they're easy to spot during development. The fallback is logged
// once per glyph via `os.Logger` to avoid log spam.
import SwiftUI

enum IconName: String, CaseIterable {
    case permission, failed, ask, working, idle, clear
    case branch
    case chevronRight = "chevron-right"
    case chevronLeft = "chevron-left"
    case gear, refresh, moon, bolt, search, copy, external
    case terminal, warning, info, x
    case arrowBack = "arrow-back"
    case file, ide
    case stack
    case stackFilled = "stack-filled"
}

struct Icon: View {
    let name: IconName
    var size: CGFloat = 14
    var tint: Color? = nil

    var body: some View {
        // Source SVGs are authored in a 16×16 viewBox; render into that space
        // then scale uniformly to `size`. Using a fixed inner canvas keeps the
        // 1.4pt strokes consistent regardless of the requested display size.
        let inner: CGFloat = 16
        let scale = size / inner
        return ZStack {
            content
                .frame(width: inner, height: inner)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale, anchor: .center)
        .frame(width: size, height: size)
        .foregroundColor(tint ?? .primary)
    }

    @ViewBuilder
    private var content: some View {
        switch name {
        case .permission:
            // Hand / palm — four parallel finger arcs into a curling thumb.
            ZStack {
                Path { p in
                    p.move(to: .init(x: 5, y: 9))
                    p.addLine(to: .init(x: 5, y: 4.5))
                    p.addQuadCurve(to: .init(x: 7, y: 4.5), control: .init(x: 6, y: 3.5))
                    p.addLine(to: .init(x: 7, y: 8))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 7, y: 8))
                    p.addLine(to: .init(x: 7, y: 3.5))
                    p.addQuadCurve(to: .init(x: 9, y: 3.5), control: .init(x: 8, y: 2.5))
                    p.addLine(to: .init(x: 9, y: 8))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 9, y: 8))
                    p.addLine(to: .init(x: 9, y: 4.5))
                    p.addQuadCurve(to: .init(x: 11, y: 4.5), control: .init(x: 10, y: 3.5))
                    p.addLine(to: .init(x: 11, y: 9))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 11, y: 9))
                    p.addLine(to: .init(x: 11, y: 6.5))
                    p.addQuadCurve(to: .init(x: 13, y: 6.5), control: .init(x: 12, y: 5.5))
                    p.addLine(to: .init(x: 13, y: 11))
                    p.addCurve(to: .init(x: 10, y: 14),
                               control1: .init(x: 13, y: 12.5),
                               control2: .init(x: 11.5, y: 14))
                    p.addLine(to: .init(x: 7, y: 14))
                    p.addCurve(to: .init(x: 4.5, y: 12.7),
                               control1: .init(x: 5.5, y: 14),
                               control2: .init(x: 4.8, y: 13.3))
                    p.addLine(to: .init(x: 3, y: 10.5))
                }.stroke(.primary, style: lineStyle())
            }
        case .failed:
            // Circle + diagonal X.
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 6, y: 6))
                    p.addLine(to: .init(x: 10, y: 10))
                    p.move(to: .init(x: 10, y: 6))
                    p.addLine(to: .init(x: 6, y: 10))
                }.stroke(.primary, style: lineStyle())
            }
        case .ask:
            // Question mark inside circle.
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 6.5, y: 6.5))
                    p.addQuadCurve(to: .init(x: 9.5, y: 6.5), control: .init(x: 8, y: 5))
                    p.addQuadCurve(to: .init(x: 8, y: 8.8), control: .init(x: 9.5, y: 7.5))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addEllipse(in: CGRect(x: 7.6, y: 10.8, width: 0.8, height: 0.8))
                }.fill(.primary)
            }
        case .working:
            // Two arcs around a filled center dot — "in motion".
            ZStack {
                Path { p in
                    // 5-radius arc from 180° to 270° (top-left quadrant).
                    p.addArc(center: .init(x: 8, y: 8), radius: 5,
                             startAngle: .degrees(180), endAngle: .degrees(270),
                             clockwise: false)
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addArc(center: .init(x: 8, y: 8), radius: 5,
                             startAngle: .degrees(0), endAngle: .degrees(90),
                             clockwise: false)
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addEllipse(in: CGRect(x: 6.6, y: 6.6, width: 2.8, height: 2.8))
                }.fill(.primary)
            }
        case .idle:
            // Checkmark.
            Path { p in
                p.move(to: .init(x: 3.5, y: 8.5))
                p.addLine(to: .init(x: 6.5, y: 11.5))
                p.addLine(to: .init(x: 12.5, y: 5))
            }.stroke(.primary, style: lineStyle())
        case .clear:
            // Small dot.
            Path { p in
                p.addEllipse(in: CGRect(x: 5.5, y: 5.5, width: 5, height: 5))
            }.stroke(.primary, style: lineStyle())
        case .branch:
            // Git branch glyph: two left dots + one right dot, connected.
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 2.6, y: 2.1, width: 2.8, height: 2.8))
                    p.addEllipse(in: CGRect(x: 2.6, y: 11.1, width: 2.8, height: 2.8))
                    p.addEllipse(in: CGRect(x: 10.6, y: 4.6, width: 2.8, height: 2.8))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 4, y: 4.9))
                    p.addLine(to: .init(x: 4, y: 11.1))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 4, y: 8))
                    p.addCurve(to: .init(x: 8, y: 4),
                               control1: .init(x: 6.5, y: 8),
                               control2: .init(x: 8, y: 6.5))
                    p.addLine(to: .init(x: 8, y: 4))
                    p.addCurve(to: .init(x: 11, y: 7),
                               control1: .init(x: 9.5, y: 4),
                               control2: .init(x: 11, y: 5.5))
                    p.addLine(to: .init(x: 11, y: 7.5))
                }.stroke(.primary, style: lineStyle())
            }
        case .chevronRight:
            Path { p in
                p.move(to: .init(x: 6, y: 4))
                p.addLine(to: .init(x: 10, y: 8))
                p.addLine(to: .init(x: 6, y: 12))
            }.stroke(.primary, style: lineStyle())
        case .chevronLeft:
            Path { p in
                p.move(to: .init(x: 10, y: 4))
                p.addLine(to: .init(x: 6, y: 8))
                p.addLine(to: .init(x: 10, y: 12))
            }.stroke(.primary, style: lineStyle())
        case .gear:
            // Center circle + 8 spokes.
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 6, y: 6, width: 4, height: 4))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 8, y: 1.5));  p.addLine(to: .init(x: 8, y: 3.3))
                    p.move(to: .init(x: 8, y: 12.7)); p.addLine(to: .init(x: 8, y: 14.5))
                    p.move(to: .init(x: 14.5, y: 8)); p.addLine(to: .init(x: 12.7, y: 8))
                    p.move(to: .init(x: 3.3, y: 8));  p.addLine(to: .init(x: 1.5, y: 8))
                    p.move(to: .init(x: 12.6, y: 3.4)); p.addLine(to: .init(x: 11.3, y: 4.7))
                    p.move(to: .init(x: 4.7, y: 11.3)); p.addLine(to: .init(x: 3.4, y: 12.6))
                    p.move(to: .init(x: 12.6, y: 12.6)); p.addLine(to: .init(x: 11.3, y: 11.3))
                    p.move(to: .init(x: 4.7, y: 4.7)); p.addLine(to: .init(x: 3.4, y: 3.4))
                }.stroke(.primary, style: lineStyle())
            }
        case .refresh:
            // Two opposing arcs with arrowheads.
            ZStack {
                Path { p in
                    p.addArc(center: .init(x: 8, y: 8), radius: 5.5,
                             startAngle: .degrees(180), endAngle: .degrees(300),
                             clockwise: false)
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 12, y: 2.5))
                    p.addLine(to: .init(x: 12, y: 5))
                    p.addLine(to: .init(x: 9.5, y: 5))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addArc(center: .init(x: 8, y: 8), radius: 5.5,
                             startAngle: .degrees(0), endAngle: .degrees(120),
                             clockwise: false)
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 4, y: 13.5))
                    p.addLine(to: .init(x: 4, y: 11))
                    p.addLine(to: .init(x: 6.5, y: 11))
                }.stroke(.primary, style: lineStyle())
            }
        case .moon:
            // Crescent — outer arc + inner arc.
            Path { p in
                p.move(to: .init(x: 13, y: 9.5))
                p.addArc(center: .init(x: 7.5, y: 8.5), radius: 5.5,
                         startAngle: .degrees(-15), endAngle: .degrees(345),
                         clockwise: true)
                p.addArc(center: .init(x: 9, y: 7.5), radius: 4.5,
                         startAngle: .degrees(135), endAngle: .degrees(45),
                         clockwise: false)
                p.closeSubpath()
            }.stroke(.primary, style: lineStyle())
        case .bolt:
            // Filled lightning-bolt zigzag.
            Path { p in
                p.move(to: .init(x: 9, y: 1.5))
                p.addLine(to: .init(x: 3, y: 9))
                p.addLine(to: .init(x: 7, y: 9))
                p.addLine(to: .init(x: 6, y: 14.5))
                p.addLine(to: .init(x: 13, y: 7))
                p.addLine(to: .init(x: 8.5, y: 7))
                p.closeSubpath()
            }.fill(.primary)
        case .search:
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 3, y: 3, width: 8, height: 8))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 10, y: 10))
                    p.addLine(to: .init(x: 13.5, y: 13.5))
                }.stroke(.primary, style: lineStyle())
            }
        case .copy:
            ZStack {
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 5, y: 5, width: 8, height: 9),
                                     cornerSize: CGSize(width: 1.5, height: 1.5))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 3, y: 11))
                    p.addLine(to: .init(x: 3, y: 3.5))
                    p.addQuadCurve(to: .init(x: 4.5, y: 2), control: .init(x: 3, y: 2))
                    p.addLine(to: .init(x: 10, y: 2))
                }.stroke(.primary, style: lineStyle())
            }
        case .external:
            ZStack {
                Path { p in
                    p.move(to: .init(x: 9, y: 2.5))
                    p.addLine(to: .init(x: 13.5, y: 2.5))
                    p.addLine(to: .init(x: 13.5, y: 7))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 13.5, y: 2.5))
                    p.addLine(to: .init(x: 7.5, y: 8.5))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 11, y: 9.5))
                    p.addLine(to: .init(x: 11, y: 12.5))
                    p.addQuadCurve(to: .init(x: 10, y: 13.5), control: .init(x: 11, y: 13.5))
                    p.addLine(to: .init(x: 3.5, y: 13.5))
                    p.addQuadCurve(to: .init(x: 2.5, y: 12.5), control: .init(x: 2.5, y: 13.5))
                    p.addLine(to: .init(x: 2.5, y: 6))
                    p.addQuadCurve(to: .init(x: 3.5, y: 5), control: .init(x: 2.5, y: 5))
                    p.addLine(to: .init(x: 6.5, y: 5))
                }.stroke(.primary, style: lineStyle())
            }
        case .terminal:
            ZStack {
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 2, y: 3, width: 12, height: 10),
                                     cornerSize: CGSize(width: 1.5, height: 1.5))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 5, y: 7))
                    p.addLine(to: .init(x: 7, y: 8.5))
                    p.addLine(to: .init(x: 5, y: 10))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 8.5, y: 10.5))
                    p.addLine(to: .init(x: 11.5, y: 10.5))
                }.stroke(.primary, style: lineStyle())
            }
        case .warning:
            ZStack {
                Path { p in
                    p.move(to: .init(x: 8, y: 2.5))
                    p.addLine(to: .init(x: 14, y: 13))
                    p.addLine(to: .init(x: 2, y: 13))
                    p.closeSubpath()
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 8, y: 6.5))
                    p.addLine(to: .init(x: 8, y: 10))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addEllipse(in: CGRect(x: 7.6, y: 11.1, width: 0.8, height: 0.8))
                }.fill(.primary)
            }
        case .info:
            ZStack {
                Path { p in
                    p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 8, y: 7.5))
                    p.addLine(to: .init(x: 8, y: 11))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addEllipse(in: CGRect(x: 7.6, y: 4.8, width: 0.8, height: 0.8))
                }.fill(.primary)
            }
        case .x:
            Path { p in
                p.move(to: .init(x: 3.5, y: 3.5))
                p.addLine(to: .init(x: 12.5, y: 12.5))
                p.move(to: .init(x: 12.5, y: 3.5))
                p.addLine(to: .init(x: 3.5, y: 12.5))
            }.stroke(.primary, style: lineStyle())
        case .arrowBack:
            ZStack {
                Path { p in
                    p.move(to: .init(x: 7, y: 3))
                    p.addLine(to: .init(x: 3, y: 8))
                    p.addLine(to: .init(x: 7, y: 13))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 3, y: 8))
                    p.addLine(to: .init(x: 13, y: 8))
                }.stroke(.primary, style: lineStyle())
            }
        case .file:
            ZStack {
                Path { p in
                    p.move(to: .init(x: 4, y: 1.5))
                    p.addLine(to: .init(x: 9, y: 1.5))
                    p.addLine(to: .init(x: 12, y: 4.5))
                    p.addLine(to: .init(x: 12, y: 14))
                    p.addLine(to: .init(x: 4, y: 14))
                    p.closeSubpath()
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 9, y: 1.5))
                    p.addLine(to: .init(x: 9, y: 4.5))
                    p.addLine(to: .init(x: 12, y: 4.5))
                }.stroke(.primary, style: lineStyle())
            }
        case .ide:
            ZStack {
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 2, y: 3, width: 12, height: 10),
                                     cornerSize: CGSize(width: 1, height: 1))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.move(to: .init(x: 2, y: 6))
                    p.addLine(to: .init(x: 14, y: 6))
                }.stroke(.primary, style: lineStyle())
                Path { p in
                    p.addEllipse(in: CGRect(x: 3.7, y: 4.2, width: 0.6, height: 0.6))
                    p.addEllipse(in: CGRect(x: 5.2, y: 4.2, width: 0.6, height: 0.6))
                }.fill(.primary)
            }
        case .stack:
            // Three-layer stacked diamonds, outline only.
            Path { p in
                p.move(to: .init(x: 2.5, y: 5))
                p.addLine(to: .init(x: 8, y: 2))
                p.addLine(to: .init(x: 13.5, y: 5))
                p.addLine(to: .init(x: 8, y: 8))
                p.closeSubpath()
                p.move(to: .init(x: 2.5, y: 8))
                p.addLine(to: .init(x: 8, y: 11))
                p.addLine(to: .init(x: 13.5, y: 8))
                p.move(to: .init(x: 2.5, y: 11))
                p.addLine(to: .init(x: 8, y: 14))
                p.addLine(to: .init(x: 13.5, y: 11))
            }.stroke(.primary, style: lineStyle())
        case .stackFilled:
            // Three filled diamonds, fading opacity (top to bottom).
            ZStack {
                Path { p in
                    p.move(to: .init(x: 2.5, y: 5))
                    p.addLine(to: .init(x: 8, y: 2))
                    p.addLine(to: .init(x: 13.5, y: 5))
                    p.addLine(to: .init(x: 8, y: 8))
                    p.closeSubpath()
                }.fill(.primary)
                Path { p in
                    p.move(to: .init(x: 2.5, y: 8))
                    p.addLine(to: .init(x: 8, y: 11))
                    p.addLine(to: .init(x: 13.5, y: 8))
                    p.addLine(to: .init(x: 11.5, y: 7))
                    p.addLine(to: .init(x: 8, y: 9))
                    p.addLine(to: .init(x: 4.5, y: 7))
                    p.closeSubpath()
                }.fill(.primary.opacity(0.7))
                Path { p in
                    p.move(to: .init(x: 2.5, y: 11))
                    p.addLine(to: .init(x: 8, y: 14))
                    p.addLine(to: .init(x: 13.5, y: 11))
                    p.addLine(to: .init(x: 11.5, y: 10))
                    p.addLine(to: .init(x: 8, y: 12))
                    p.addLine(to: .init(x: 4.5, y: 10))
                    p.closeSubpath()
                }.fill(.primary.opacity(0.45))
            }
        }
    }

    private func lineStyle() -> StrokeStyle {
        StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
    }
}

