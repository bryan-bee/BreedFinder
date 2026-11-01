import SwiftUI

@main
struct BreedFinderApp: App {
    @StateObject private var collection: BreedCollection
    @StateObject private var recentScans: RecentScansStore
    @StateObject private var scanModel: ScanModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // First, as TelemetryDeck asks, so its session signal covers this launch.
        Analytics.start()
        // Created together: each scan result is saved to the collection and kept as a recent scan.
        let collection = BreedCollection()
        let recentScans = RecentScansStore()
        _collection = StateObject(wrappedValue: collection)
        _recentScans = StateObject(wrappedValue: recentScans)
        _scanModel = StateObject(wrappedValue: ScanModel(collection: collection, recentScans: recentScans))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(collection)
                .environmentObject(recentScans)
                .environmentObject(scanModel)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS may close the app while it's in the background, so send the answer to
            // "Is it a …?" for the result on screen now.
            if phase == .background {
                scanModel.sendFeedback()
            }
        }
    }
}
