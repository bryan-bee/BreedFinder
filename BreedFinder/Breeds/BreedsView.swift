import SwiftUI

/// The Breeds tab: every breed the app knows, Pokédex-style, with how many times the
/// user has scanned each one.
struct BreedsView: View {
    @EnvironmentObject private var collection: BreedCollection
    @AppStorage("breedGrouping") private var grouping: BreedGrouping = .alphabetical
    /// Whether the search bar is open: the magnifying glass opens it, Cancel closes it.
    @State private var isSearching = false
    @State private var search = ""
    @FocusState private var searchFieldFocused: Bool

    private let library = BreedLibrary.shared

    private var isFiltering: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var sections: [BreedSection] {
        let profiles = library.allProfiles.filter { BreedSearch.matches($0.name, query: search) }
        return grouping.sections(of: profiles, collected: collection.collectedBreeds)
    }

    var body: some View {
        let sections = self.sections
        let pages = BreedPage.pages(for: sections)
        NavigationStack {
            List {
                if !isFiltering {
                    Section {
                        CollectionProgress(collected: collection.collectedBreeds.count,
                                           total: library.allProfiles.count)
                    }
                }
                ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                    Section {
                        ForEach(Array(section.breeds.enumerated()), id: \.element.id) { row, profile in
                            NavigationLink(value: pages[sectionIndex][row]) {
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
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if isFiltering, sections.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isSearching {
                    BreedSearchBar(text: $search, isFocused: $searchFieldFocused, onCancel: closeSearch)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("Breeds")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isSearching {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { isSearching = true }
                        } label: {
                            Label("Search breeds", systemImage: "magnifyingglass")
                        }
                    }
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
            .navigationDestination(for: BreedPage.self) { page in
                BreedPager(page: page)
            }
        }
    }

    private func closeSearch() {
        searchFieldFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isSearching = false
            search = ""
        }
    }
}

/// The search field that opens under the title when the magnifying glass is tapped. The
/// list filters as you type; Cancel closes the field and shows every breed again.
private struct BreedSearchBar: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search breeds", text: $text)
                    .focused(isFocused)
                    // Typed text matches anywhere in a name, in any case, so don't capitalize it.
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isFocused.wrappedValue = false }
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            Button("Cancel", action: onCancel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            // Open the keyboard right away. The field has to be on screen before it can take focus.
            DispatchQueue.main.async { isFocused.wrappedValue = true }
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
