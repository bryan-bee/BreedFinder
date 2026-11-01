import SwiftUI

/// Lets the user say which breed a scan really was, so their Breeds collection stays
/// right when the model gets it wrong.
struct BreedPickerSheet: View {
    /// The model's top guesses, shown first.
    let suggestions: [BreedGuess]
    /// The breed currently chosen, if any (shown with a checkmark).
    let current: String?
    let onPick: (String) -> Void
    /// When set, offers "Don't count this scan" (used from the result screen).
    var onUncount: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [BreedProfile] {
        let all = BreedLibrary.shared.allProfiles
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty, !suggestions.isEmpty {
                    Section("Top guesses") {
                        ForEach(suggestions) { guess in
                            row(guess.breed, detail: guess.confidence.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
                Section(search.isEmpty ? "All breeds" : "Matching breeds") {
                    ForEach(matches) { profile in
                        row(profile.name, detail: nil)
                    }
                }
                if current != nil, let onUncount {
                    Section {
                        Button("Don't count this scan", role: .destructive) {
                            onUncount()
                            dismiss()
                        }
                    } footer: {
                        Text("Removes this scan from your Breeds collection, e.g. if it wasn't a real dog.")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search breeds")
            .navigationTitle("Which breed is it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ breed: String, detail: String?) -> some View {
        Button {
            onPick(breed)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                BreedThumbnail(breed: breed, size: 40)
                Text(breed)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail {
                    Text(detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if breed == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// A breed's reference photo as a small rounded square. Hidden from VoiceOver: it's
/// always shown next to the breed's name.
struct BreedThumbnail: View {
    let breed: String
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let thumbnail = BreedLibrary.shared.thumbnail(for: breed) {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                PhotoPlaceholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}
