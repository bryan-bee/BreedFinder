import SwiftUI

/// The Breeds tab: every breed the app knows, Pokédex-style, with how many times the
/// user has scanned each one.
struct BreedsView: View {
    @EnvironmentObject private var collection: BreedCollection
    @AppStorage("breedGrouping") private var grouping: BreedGrouping = .alphabetical
    @State private var search = ""

    private let library = BreedLibrary.shared

    private var sections: [BreedSection] {
        let profiles = search.isEmpty
            ? library.allProfiles
            : library.allProfiles.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return grouping.sections(of: profiles, collected: collection.collectedBreeds)
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        CollectionProgress(collected: collection.collectedBreeds.count,
                                           total: library.allProfiles.count)
                    }
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.breeds) { profile in
                            NavigationLink(value: profile.name) {
                                BreedRow(profile: profile)
                            }
                        }
                    } header: {
                        if let title = section.title {
                            let caught = section.breeds.filter { collection.collectedBreeds.contains($0.name) }.count
                            Text("\(title) · \(caught)/\(section.breeds.count)")
                        }
                    }
                }
            }
            .navigationTitle("Breeds")
            .searchable(text: $search, prompt: "Search breeds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Group by", selection: $grouping) {
                            ForEach(BreedGrouping.allCases) { option in
                                Label(option.rawValue, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Label("Group by", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: String.self) { name in
                if let profile = library.profile(for: name) {
                    BreedDetailView(profile: profile)
                }
            }
        }
    }
}

private struct CollectionProgress: View {
    let collected: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(collected)")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text("of \(total) breeds collected")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(collected), total: Double(max(total, 1)))
                .tint(Color.accentColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collected) of \(total) breeds collected")
    }
}

private struct BreedRow: View {
    let profile: BreedProfile
    @EnvironmentObject private var collection: BreedCollection

    var body: some View {
        let count = collection.count(for: profile.name)
        HStack(spacing: 14) {
            Group {
                if count > 0, let photo = collection.latestPhoto(for: profile.name) {
                    // Collected: the user's own dog.
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Not yet collected: a faded reference photo.
                    BreedThumbnail(breed: profile.name)
                        .grayscale(count > 0 ? 0 : 1)
                        .opacity(count > 0 ? 1 : 0.45)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                Text("\(dexLabel(for: profile.name)) · \(profile.origin)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if count > 0 {
                Text("×\(count)")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        // One element: "Beagle, number 25, England", then "Scanned 2 times" as its value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile.name), \(dexAccessibilityLabel(for: profile.name)), \(profile.origin)")
        .accessibilityValue(count > 0 ? "Scanned \(count) \(count == 1 ? "time" : "times")" : "Not collected yet")
    }
}

/// "No. 042"
func dexLabel(for breed: String) -> String {
    guard let number = BreedLibrary.shared.dexNumber(for: breed) else { return "No. —" }
    return "No. " + String(format: "%03d", number)
}

/// "number 42": "No. 042" spoken the way it's meant, for VoiceOver.
func dexAccessibilityLabel(for breed: String) -> String {
    BreedLibrary.shared.dexNumber(for: breed).map { "number \($0)" } ?? ""
}
