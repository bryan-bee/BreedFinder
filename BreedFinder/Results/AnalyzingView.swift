import SwiftUI

struct AnalyzingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Studying your dog…")
                .font(.headline)
            Text("Checking \(DogAnalyzer.framesPerClip) frames from the video")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
