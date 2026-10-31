import SwiftUI

struct ResultView: View {
    let result: ScanResult
    let onScanAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                FrameStrip(frames: result.frames)

                if result.guesses.isEmpty {
                    ContentUnavailableView(
                        "No dog found",
                        systemImage: "pawprint",
                        description: Text("Try again in good light, with the dog filling more of the frame.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Best guesses")
                            .font(.title2.bold())
                        ForEach(Array(result.guesses.enumerated()), id: \.element.id) { index, guess in
                            GuessRow(rank: index + 1, guess: guess)
                        }
                    }
                    Text("Mixed-breed dogs often show their parent breeds here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onScanAgain) {
                Label("Scan another dog", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }
}

/// The five frames pulled from the video. Frames without a dog are dimmed.
private struct FrameStrip: View {
    let frames: [FrameAnalysis]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frames checked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    Color.clear
                        .aspectRatio(0.75, contentMode: .fit)  // portrait 3:4 tiles
                        .overlay {
                            Image(decorative: frame.image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(frame.prediction.containsDog ? 1 : 0.35)
                        .overlay(alignment: .bottomTrailing) {
                            if frame.prediction.containsDog {
                                Image(systemName: "pawprint.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.accentColor)
                                    .padding(4)
                            }
                        }
                }
            }
        }
    }
}

private struct GuessRow: View {
    let rank: Int
    let guess: BreedGuess

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank). \(guess.breed)")
                    .font(rank == 1 ? Font.title3.bold() : Font.body.weight(.medium))
                Spacer()
                Text(guess.confidence, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: guess.confidence)
                .tint(rank == 1 ? Color.accentColor : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
