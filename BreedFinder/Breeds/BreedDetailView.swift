import SwiftUI

/// One breed's page in the Breeds tab: its photo, the user's scans of it, and its profile.
/// Shown inside BreedPager, which sets the title as you swipe from breed to breed.
struct BreedDetailView: View {
    let profile: BreedProfile
    @EnvironmentObject private var collection: BreedCollection

    var body: some View {
        let records = collection.records(for: profile.name)
        ScrollView {
            VStack(spacing: 20) {
                let photo = BreedLibrary.shared.photo(for: profile.name)
                Group {
                    if let photo {
                        WholePhoto(image: Image(uiImage: photo))
                    } else {
                        PhotoPlaceholder()
                    }
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Photo of \(withArticle(profile.name))")
                .accessibilityAddTraits(.isImage)
                .accessibilityHidden(photo == nil)

                HStack {
                    Text(dexLabel(for: profile.name))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if records.isEmpty {
                        Label("Not collected", systemImage: "seal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Collected", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                YourScans(breed: profile.name, records: records)
                BreedProfileView(profile: profile, showsTitle: false)
            }
            .padding()
        }
    }
}

private struct YourScans: View {
    let breed: String
    let records: [ScanRecord]
    @EnvironmentObject private var collection: BreedCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your scans")
                .font(.headline)
            if let first = records.last {
                Text("Scanned \(records.count) \(records.count == 1 ? "time" : "times") · first on \(first.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    // Lazy, so a breed scanned many times only loads the photos in view.
                    LazyHStack(spacing: 10) {
                        ForEach(records) { record in
                            ScanThumbnail(record: record)
                                .contextMenu {
                                    Button("Remove from Breeds", systemImage: "trash", role: .destructive) {
                                        withAnimation { collection.remove(record.id) }
                                    }
                                }
                                // The same for VoiceOver, in its Actions rotor.
                                .accessibilityAction(named: "Remove from Breeds") {
                                    withAnimation { collection.remove(record.id) }
                                }
                        }
                    }
                }
                Text("Touch and hold a photo to remove a scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("You haven't scanned \(withArticle(breed)) yet. Scan one to add it to your collection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ScanThumbnail: View {
    let record: ScanRecord
    @EnvironmentObject private var collection: BreedCollection

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let photo = collection.photo(for: record) {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(record.date.formatted(date: .numeric, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your scan from \(record.date.formatted(date: .long, time: .omitted))")
        .accessibilityAddTraits(.isImage)
    }
}
