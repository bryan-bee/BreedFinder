import SwiftUI

@main
struct BreedFinderApp: App {
    @StateObject private var collection: BreedCollection
    @StateObject private var recentScans: RecentScansStore
    @StateObject private var scanModel: ScanModel

    init() {
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
    }
}
