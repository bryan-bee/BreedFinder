import SwiftUI

/// The breed page to open, and the list it was opened from: the Breeds list in the order
/// it was shown, or only the search results while a search is on. The page then swipes
/// through that list.
struct BreedPage: Hashable {
    let breeds: [String]
    let index: Int

    /// A page for every row of the list, shaped like `sections`. Each knows the whole list
    /// in the order shown and its own place in it, so a breed listed twice (under two
    /// origin countries) swipes on from the row that was tapped.
    static func pages(for sections: [BreedSection]) -> [[BreedPage]] {
        let order = sections.flatMap { $0.breeds.map(\.name) }
        var index = 0
        return sections.map { section in
            section.breeds.map { _ in
                defer { index += 1 }
                return BreedPage(breeds: order, index: index)
            }
        }
    }
}

/// Breed pages side by side: swipe left for the next breed in the list, right for the one
/// before. The list stays as it was when the page opened, so it doesn't reshuffle while
/// you swipe (in the Collected grouping, say, after removing a scan).
struct BreedPager: View {
    private let profiles: [BreedProfile]
    @State private var current: Int

    init(page: BreedPage) {
        profiles = page.breeds.compactMap { BreedLibrary.shared.profile(for: $0) }
        _current = State(initialValue: min(max(page.index, 0), max(profiles.count - 1, 0)))
    }

    var body: some View {
        TabView(selection: $current) {
            ForEach(profiles.indices, id: \.self) { index in
                BreedDetailView(profile: profiles[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The breed, and where it is in the list, such as "3 of 12" in search results.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.headline)
                    if profiles.count > 1 {
                        Text("\(current + 1) of \(profiles.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var title: String {
        profiles.indices.contains(current) ? profiles[current].name : ""
    }
}
