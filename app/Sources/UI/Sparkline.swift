// Single-pass sparkline view. Ports docs/ux-design/components.jsx::Sparkline
// (lines 154–176).
//
// Renders an area path (linear gradient: color@0.4 at top → color@0 at
// bottom) plus a stroked line on top (1.5pt, round caps). Width is taken
// from `GeometryReader` so the chart stretches to fill its container; height
// defaults to 40pt to match the JSX reference.
//
// Returns `EmptyView` when `data` is empty rather than emitting a 0-height
// invisible Path — keeps the layout free of phantom space when a session has
// no load samples yet.
import SwiftUI

struct Sparkline: View {
    let data: [Int]
    var color: Color
    var height: CGFloat = 40

    var body: some View {
        if data.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                let w = geo.size.width
                let h = height
                // `max(1, ...)` keeps the divisor non-zero when every sample
                // is zero — otherwise `(v / max) * h` would NaN.
                let maxV = max(1, data.max() ?? 0)
                // `data.count - 1` step. Single-sample data renders as one
                // point at x=0; guard against `data.count == 1` divide-by-zero
                // by collapsing step to 0 and emitting a single Move.
                let step: CGFloat = data.count > 1 ? w / CGFloat(data.count - 1) : 0
                let points: [CGPoint] = data.enumerated().map { (i, v) in
                    CGPoint(
                        x: CGFloat(i) * step,
                        y: h - (CGFloat(v) / CGFloat(maxV)) * (h - 4) - 2
                    )
                }
                ZStack {
                    areaPath(points: points, w: w, h: h)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    color.opacity(0.4),
                                    color.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    linePath(points: points)
                        .stroke(
                            color,
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }
            .frame(height: height)
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        var p = Path()
        for (i, pt) in points.enumerated() {
            if i == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        return p
    }

    private func areaPath(points: [CGPoint], w: CGFloat, h: CGFloat) -> Path {
        var p = linePath(points: points)
        // Close the area along the right edge → bottom-right → bottom-left.
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
