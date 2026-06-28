import SwiftUI

struct AudioWaveformView: View {
    let amplitude: Float

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 16
    private let barShape: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .frame(width: barWidth, height: maxBarHeight * barRatio(for: index))
            }
        }
        .frame(height: maxBarHeight)
    }

    private func barRatio(for index: Int) -> CGFloat {
        let clamped = max(0, min(1, CGFloat(amplitude)))
        let scaled = sqrt(clamped) * 2.5
        return max(0.02, min(1, barShape[index] * scaled))
    }
}

struct AudioWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            AudioWaveformView(amplitude: 0.0)
            AudioWaveformView(amplitude: 0.3)
            AudioWaveformView(amplitude: 0.7)
            AudioWaveformView(amplitude: 1.0)
        }
    }
}
