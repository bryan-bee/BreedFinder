import SwiftUI

struct SupportView: View {
    @State private var showingReport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "pawprint.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Breed Finder")
                                .font(.headline)
                            Text("Version \(SupportInfo.appVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button { showingReport = true } label: {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                    }
                } footer: {
                    Text("Tell us about a wrong breed, a crash, a bug or an idea. You can attach one of your recent scans, and you'll see the whole email before it's sent. If Share With App Developers is on (Settings → Privacy & Security → Analytics & Improvements), crash logs also reach us automatically.")
                }

                Section("How Breed Finder works") {
                    InfoRow(icon: "lock.iphone", title: "Everything stays on your iPhone",
                            text: "Videos and photos are analyzed on the device and never uploaded. Your Breeds collection, your dog photos and the frames from your last \(RecentScansStore.limit) scans are stored only on this iPhone. They leave it only if you attach them to a problem report.")
                    InfoRow(icon: "brain", title: "The breed model",
                            text: "A neural network trained on about 96,000 dog photos recognizes 176 breeds. It's a best guess, not a DNA test: mixed-breed dogs often show their parent breeds in the top 3.")
                }

                Section("Breed photos") {
                    Text("Each breed's reference photo comes from Wikimedia Commons and is used under its license (public domain, CC0, CC BY or CC BY-SA). The photographer is credited on every breed's page.")
                        .font(.subheadline)
                    NavigationLink("Photo credits") { PhotoCreditsView() }
                }

                Section("Training data") {
                    Text("The breed model was trained with Stanford Dogs, Tsinghua Dogs, the Oxford-IIIT Pet Dataset, Udacity's dog breed dataset, the Kaggle 70 Dog Breeds dataset, COCO, and Creative Commons photos from Wikimedia Commons and Flickr (via Openverse).")
                        .font(.subheadline)
                }

                Section {
                    Text("© \(Date.now.formatted(.dateTime.year())) \(SupportInfo.copyrightHolder). All rights reserved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Support: \(SupportInfo.reportEmail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Support")
            .sheet(isPresented: $showingReport) {
                ReportProblemView()
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Every breed photo's author and license, as their Creative Commons licenses require.
private struct PhotoCreditsView: View {
    var body: some View {
        List(BreedLibrary.shared.allProfiles) { profile in
            if let credit = profile.photo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                    Text("\(credit.author) · \(credit.license)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let source = credit.sourceURL.flatMap(URL.init(string:)) {
                        Link("View on Wikimedia Commons", destination: source)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Photo credits")
    }
}
