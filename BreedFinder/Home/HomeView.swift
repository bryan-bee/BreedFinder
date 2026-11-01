import PhotosUI
import SwiftUI

struct HomeView: View {
    let onScan: () -> Void
    let onPhotos: ([PhotosPickerItem]) -> Void

    @State private var pickedPhotos: [PhotosPickerItem] = []

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
            .accessibilityHidden(true)  // decoration; the title says what the app is

            Text("Breed Finder")
                .font(.largeTitle.bold())

            Spacer()

            VStack(spacing: 12) {
                Button(action: onScan) {
                    Label("Scan a Dog", systemImage: "camera.viewfinder")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: PhotoLoader.maxPhotos,
                             selectionBehavior: .ordered, matching: .images) {
                    Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline.bold())  // orange on light orange is under 4.5:1, fine for bold text
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
        .padding(24)
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            onPhotos(items)
            pickedPhotos = []  // so picking the same photos again still triggers a scan
        }
    }
}
