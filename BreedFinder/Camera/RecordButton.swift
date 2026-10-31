import SwiftUI

/// A camera-style shutter button. While recording, a ring fills over `duration`
/// seconds so the user knows how long to keep the dog in frame.
struct RecordButton: View {
    let isRecording: Bool
    let duration: TimeInterval
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: isRecording ? 8 : 34)
                    .fill(Color.red)
                    .frame(width: isRecording ? 30 : 68, height: isRecording ? 30 : 68)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, recording in
            progress = 0
            if recording {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            }
        }
        .accessibilityLabel(isRecording ? "Recording" : "Record a 5-second clip")
    }
}
