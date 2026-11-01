import UIKit

enum SupportInfo {
    /// Where problem reports go.
    static let reportEmail = "breedfinder123@gmail.com"

    static let copyrightHolder = "Bryan Bee"

    /// docs/privacy.html in the repo, published by GitHub Pages. App Review requires a
    /// privacy policy link inside the app as well as in the App Store listing.
    static let privacyPolicyURL = URL(string: "https://bryan-bee.github.io/BreedFinder/privacy.html")!

    /// docs/support.html: contact details and answers to common questions. Also the
    /// Support URL in the App Store listing.
    static let helpURL = URL(string: "https://bryan-bee.github.io/BreedFinder/support.html")!

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    /// The hardware model, e.g. "iPhone16,1".
    static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Opens whatever mail app is the default. Can't carry attachments.
    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: body)]
        return components.url
    }
}
