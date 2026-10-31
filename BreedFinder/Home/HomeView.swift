import SwiftUI

struct HomeView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 190, height: 190)
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 136, height: 136)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 10) {
                Text("Breed Finder")
                    .font(.largeTitle.bold())
                Text("Film your dog for 5 seconds and find out what breed it is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Step(icon: "video.fill", text: "Record your dog for 5 seconds")
                Step(icon: "photo.stack", text: "We check 5 frames from the video")
                Step(icon: "list.number", text: "See the top 3 breeds and fun facts")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

            Button(action: onScan) {
                Label("Scan a Dog", systemImage: "camera.viewfinder")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(24)
    }
}

private struct Step: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }
}
