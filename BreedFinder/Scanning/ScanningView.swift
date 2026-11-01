import SwiftUI

/// Shows the frames pulled from the video while the model works, with a scanner
/// line sweeping over each one, so people can see exactly which photos are used
/// (and notice if the video was blurry or the dog was out of frame).
struct ScanningView: View {
    let frames: [CGImage]
    let source: ScanSource

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Scanning your dog")
                    .font(.title2.bold())
                Text(frames.count == 1
                     ? "This is the \(source.itemName) we're checking."
                     : "These are the \(frames.count) \(source.itemName)s we're checking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            frameGrid

            HStack(spacing: 10) {
                ProgressView()
                Text("Identifying the breed…")
                    .font(.headline)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Three frames on top, the rest centered underneath.
    private var frameGrid: some View {
        let indexed = Array(frames.enumerated())
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(indexed.prefix(3), id: \.offset) { item in
                    ScanningFrame(image: item.element, delay: Double(item.offset) * 0.3)
                }
            }
            HStack(spacing: 12) {
                ForEach(indexed.dropFirst(3), id: \.offset) { item in
                    ScanningFrame(image: item.element, delay: Double(item.offset) * 0.3)
                }
            }
        }
    }
}

private struct ScanningFrame: View {
    let image: CGImage
    let delay: Double

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: 100, height: 133)
            .overlay { ScannerSweep(delay: delay) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

/// A glowing line that sweeps top to bottom on a loop, with a fading trail behind it.
/// With Reduce Motion on, a steady tint instead (the spinner below still shows progress).
private struct ScannerSweep: View {
    let delay: Double
    private let period = 1.8
    private let trail: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Color.accentColor.opacity(0.15)
                .allowsHitTesting(false)
        } else {
            sweep
        }
    }

    private var sweep: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate + delay
            let progress = elapsed.truncatingRemainder(dividingBy: period) / period
            GeometryReader { geometry in
                let y = geometry.size.height * progress
                LinearGradient(colors: [Color.accentColor.opacity(0), Color.accentColor.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: trail)
                    .offset(y: y - trail)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2.5)
                    .shadow(color: Color.accentColor.opacity(0.9), radius: 4)
                    .offset(y: y - 1)
            }
        }
        .allowsHitTesting(false)
    }
}
