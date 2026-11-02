import Foundation

/// Ways to organize the Breeds list. Adding one means adding a case and its sections.
enum BreedGrouping: String, CaseIterable, Identifiable {
    case alphabetical = "A–Z"
    case origin = "Origin"
    case group = "Breed group"
    case collected = "Collected"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .origin: return "globe"
        case .group: return "rosette"
        case .collected: return "checkmark.seal"
        }
    }

    /// Groups already-sorted profiles into sections; breeds stay in their given order.
    func sections(of profiles: [BreedProfile], collected: Set<String>) -> [BreedSection] {
        switch self {
        case .alphabetical:
            return [BreedSection(title: nil, breeds: profiles)]

        case .origin:
            // A breed from "Scotland and England" appears under both.
            var byCountry: [String: [BreedProfile]] = [:]
            for profile in profiles {
                for country in profile.originCountries {
                    byCountry[country, default: []].append(profile)
                }
            }
            return byCountry.keys.sorted().map { BreedSection(title: $0, breeds: byCountry[$0] ?? []) }

        case .group:
            let order = ["Sporting", "Hound", "Working", "Terrier", "Toy", "Non-Sporting", "Herding",
                         "Designer crossbreed", "Other"]
            let byGroup = Dictionary(grouping: profiles, by: \.groupKey)
            return order.compactMap { key in
                byGroup[key].map { BreedSection(title: key == "Other" ? "Other breeds" : key, breeds: $0) }
            }

        case .collected:
            let sections = [
                BreedSection(title: "Collected", breeds: profiles.filter { collected.contains($0.name) }),
                BreedSection(title: "Not yet", breeds: profiles.filter { !collected.contains($0.name) }),
            ]
            return sections.filter { !$0.breeds.isEmpty }
        }
    }
}

struct BreedSection: Identifiable {
    /// Nil for an ungrouped list.
    let title: String?
    let breeds: [BreedProfile]

    var id: String { title ?? "all" }
}

/// The Breeds tab's search.
enum BreedSearch {
    /// Whether `name` matches what was typed. The text can be anywhere in the name, ignoring
    /// case and accents: "c" finds every breed with a C in it, and "chi" finds Chihuahua,
    /// Chinese Crested, Japanese Chin and Schipperke. A typed "*" stands for any number of
    /// characters, so "g*doodle" finds Goldendoodle. Blank text matches every breed.
    static func matches(_ name: String, query: String) -> Bool {
        let pieces = query.trimmingCharacters(in: .whitespaces).split(separator: "*")
        var searchFrom = name.startIndex
        for piece in pieces {
            guard let found = name.range(of: piece, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchFrom..<name.endIndex) else { return false }
            searchFrom = found.upperBound
        }
        return true
    }
}
