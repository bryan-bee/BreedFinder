import UIKit

struct BreedPhotoCredit: Decodable {
    let file: String
    let author: String
    let license: String
    let licenseURL: String?
    let sourceURL: String?
}

/// Everything the result screen shows about a breed. Loaded from breeds.json, which
/// tools/build_breed_content.py generates from content/breeds/*.json.
struct BreedProfile: Decodable, Identifiable {
    let name: String
    let summary: String
    let origin: String
    let lifespan: String
    let weight: String
    let group: String
    let temperament: [String]
    let funFacts: [String]
    let photo: BreedPhotoCredit?

    var id: String { name }
}

final class BreedLibrary {
    static let shared = BreedLibrary()

    private let profiles: [String: BreedProfile]

    init(bundle: Bundle = .main) {
        do {
            guard let url = bundle.url(forResource: "breeds", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            profiles = try JSONDecoder().decode([String: BreedProfile].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Couldn't load breeds.json: \(error)")
            profiles = [:]
        }
    }

    func profile(for breed: String) -> BreedProfile? {
        profiles[breed]
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
}
