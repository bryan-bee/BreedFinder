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

            Text("Breed Finder")
                .font(.largeTitle.bold())

            Spacer()

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
