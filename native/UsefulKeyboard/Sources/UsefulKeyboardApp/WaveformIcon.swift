import SwiftUI
import UsefulKeyboardCore

/// Center-aligned waveform bars with an asymmetric envelope
/// that naturally suggests the letter "K". The left side rises steeply
/// to a peak, while the right side has a secondary kick — like the
/// upper and lower strokes of a K branching from a strong vertical.
struct WaveformIcon: View {
    var barCount: Int = 9
    var spacing: CGFloat = 1.5

    // K-envelope: strong left peak with a secondary bump on the right.
    private static let presets: [Int: [CGFloat]] = [
        5:  [1.0, 0.70, 0.35, 0.70, 0.90],
        7:  [0.50, 1.0, 0.70, 0.30, 0.55, 0.85, 0.50],
        9:  [0.35, 0.70, 1.0, 0.75, 0.30, 0.50, 0.80, 0.60, 0.30],
        11: [0.25, 0.50, 0.85, 1.0, 0.70, 0.30, 0.45, 0.75, 0.60, 0.40, 0.20],
        13: [0.20, 0.40, 0.65, 0.90, 1.0, 0.70, 0.30, 0.40, 0.65, 0.80, 0.55, 0.35, 0.20],
    ]

    private var multipliers: [CGFloat] {
        Self.presets[barCount] ?? Self.presets[9]!
    }

    var body: some View {
        GeometryReader { geo in
            let mults = multipliers
            let count = mults.count
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(count)
            let cornerRadius = barWidth / 2

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let barHeight = max(geo.size.height * mults[i], barWidth)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: barWidth, height: barHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}
