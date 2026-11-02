import UIKit

struct BreedPhotoCredit: Decodable {
    let file: String
    /// The Commons file name, e.g. "Akita Inu (male)".
    let title: String?
    let author: String
    /// Where the author asks credits to link (CC BY 2.0 lets them name one), e.g. their website.
    let authorURL: String?
    let license: String
    let licenseURL: String?
    let sourceURL: String?

    /// The credit the photo's license asks for: its title (linked to its Commons page),
    /// author, license (linked to the license text) and source, and a note that the app
    /// changed it, since CC licenses ask you to say so.
    var attribution: AttributedString {
        var text = AttributedString("“")
        var title = AttributedString(self.title ?? "Photo")
        title.link = sourceURL.flatMap(URL.init(string:))
        text += title
        text += AttributedString("”")
        if !author.isEmpty, author != "Unknown" {
            var name = AttributedString(author)
            name.link = authorURL.flatMap(URL.init(string:))
            text += AttributedString(" by ") + name
        }
        text += AttributedString(", ")
        var license = AttributedString(self.license)
        license.link = licenseURL.flatMap(URL.init(string:))
        text += license
        text += AttributedString(", via Wikimedia Commons. Resized and cropped for display.")
        return text
    }
}

/// Everything the app shows about a breed. Loaded from breeds.json, which
/// tools/build_breed_content.py generates from content/breeds/*.json.
struct BreedProfile: Decodable, Identifiable, Hashable {
    let name: String
    let summary: String
    let origin: String
    let lifespan: String
    let weight: String
    let group: String
    let temperament: [String]
    let funFacts: [String]
    let photo: BreedPhotoCredit?
    /// Countries for grouping, e.g. "Scotland and England" → ["Scotland", "England"].
    let originCountries: [String]
    /// The AKC group, "Designer crossbreed" or "Other".
    let groupKey: String

    var id: String { name }

    static func == (lhs: BreedProfile, rhs: BreedProfile) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// "a Beagle", "an Akita". Every breed name that starts with a vowel letter also starts
/// with a vowel sound (no "Eurasier"-style exceptions in the list), so the letter decides.
func withArticle(_ breed: String) -> String {
    let startsWithVowel = breed.first.map { "AEIOU".contains($0) } ?? false
    return (startsWithVowel ? "an " : "a ") + breed
}

final class BreedLibrary {
    static let shared = BreedLibrary()

    /// Every breed, A–Z.
    let allProfiles: [BreedProfile]
    private let profiles: [String: BreedProfile]
    private let dexNumbers: [String: Int]
    private let thumbnails = NSCache<NSString, UIImage>()

    init(bundle: Bundle = .main) {
        var loaded: [String: BreedProfile] = [:]
        do {
            guard let url = bundle.url(forResource: "breeds", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            loaded = try JSONDecoder().decode([String: BreedProfile].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Couldn't load breeds.json: \(error)")
        }
        profiles = loaded
        allProfiles = loaded.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        dexNumbers = Dictionary(uniqueKeysWithValues: allProfiles.enumerated().map { ($1.name, $0 + 1) })
    }

    func profile(for breed: String) -> BreedProfile? {
        profiles[breed]
    }

    /// The breed's number in the Breeds list ("No. 042"), by alphabetical position.
    func dexNumber(for breed: String) -> Int? {
        dexNumbers[breed]
    }

    /// The bundled reference photo for a breed, from Resources/BreedPhotos.
    func photo(for breed: String) -> UIImage? {
        guard
            let file = profiles[breed]?.photo?.file,
            let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                                      withExtension: (file as NSString).pathExtension,
                                      subdirectory: "BreedPhotos")
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// A small, cached version of the reference photo for list rows.
    func thumbnail(for breed: String) -> UIImage? {
        if let cached = thumbnails.object(forKey: breed as NSString) { return cached }
        guard let photo = photo(for: breed), photo.size.width > 0, photo.size.height > 0 else { return nil }
        // Short side 160 px, same proportions as the photo.
        let scale = 160 / min(photo.size.width, photo.size.height)
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        guard let thumbnail = photo.preparingThumbnail(of: size) else { return nil }
        thumbnails.setObject(thumbnail, forKey: breed as NSString)
        return thumbnail
    }
}
