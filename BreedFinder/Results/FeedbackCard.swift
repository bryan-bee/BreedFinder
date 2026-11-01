import SwiftUI

/// The user's answer to "Is it a …?" on a result. It keeps their Breeds collection right,
/// and the usage stats turn the answers into Breed Finder's accuracy on real dogs.
enum ScanFeedback: Equatable {
    /// "Yes": the top guess is right.
    case correct
    /// It's another breed: one of the other top guesses (`rank` 2 or 3), or one picked
    /// from the full list (`rank` nil).
    case otherBreed(String, rank: Int?)
    /// "No", without saying which breed it is.
    case notTopGuess
    /// "Not sure", e.g. a mixed-breed dog or a friend's dog.
    case unsure

    /// The answer when the user picks `breed` from a list.
    init(breed: String, guesses: [BreedGuess]) {
        switch guesses.firstIndex(where: { $0.breed == breed }) {
        case 0?: self = .correct
        case let index?: self = .otherBreed(breed, rank: index + 1)
        case nil: self = .otherBreed(breed, rank: nil)
        }
    }

    /// How the answer is recorded in the usage stats (see "Usage stats" in the README for
    /// turning these into top-1 and top-3 accuracy).
    var statsAnswer: String {
        switch self {
        case .correct: return "top1"
        case .otherBreed(_, let rank?): return "top\(rank)"
        case .otherBreed(_, nil): return "notInTop3"
        case .notTopGuess: return "notTop1"
        case .unsure: return "unsure"
        }
    }
}

/// Under the cards on a result: whether the scan is saved to the user's Breeds, and
/// "Is it a …?". "No" offers the other two guesses first, so the answer also says whether
/// the right breed was in the top 3.
struct FeedbackCard: View {
    let guesses: [BreedGuess]
    let feedback: ScanFeedback?
    /// The breed the scan counts as in the collection; nil if the user took it out.
    let countedAs: String?
    /// How many scans of `countedAs` the collection has, this one included.
    let timesCounted: Int
    let onAnswer: (ScanFeedback) -> Void
    /// Opens the full breed list, which also has "Don't count this scan".
    let onPickBreed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// After "No": the other guesses are showing, to pick from.
    @State private var choosingBreed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            status
            if let top = guesses.first {
                Divider()
                switch feedback {
                case nil:
                    question(about: top.breed)
                case .notTopGuess? where choosingBreed:
                    otherGuesses
                case let answer?:
                    Text(thanks(for: answer))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .animation(reduceMotion ? nil : .snappy, value: feedback)
        .animation(reduceMotion ? nil : .snappy, value: choosingBreed)
    }

    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: countedAs == nil ? "seal" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(countedAs == nil ? Color.secondary : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(countedAs == nil ? "Not counted in your Breeds" : "Saved to your Breeds")
                    .font(.subheadline.weight(.semibold))
                if let countedAs {
                    Text("as \(countedAs) · ×\(timesCounted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription)
            Spacer()
            // Until the question is answered, "No" is the way to fix a wrong breed.
            if feedback != nil || countedAs == nil {
                Button(countedAs == nil ? "Choose breed" : "Change", action: onPickBreed)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
    }

    private var statusDescription: String {
        guard let countedAs else { return "Not counted in your Breeds" }
        return "Saved to your Breeds as \(countedAs), \(timesCounted) \(timesCounted == 1 ? "scan" : "scans") of this breed"
    }

    private func question(about breed: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Is it \(withArticle(breed))?")
                .font(.headline)
            // Three identical buttons, so nothing nudges people toward "Yes" (which would
            // make the accuracy stats look better than they are).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { answerButtons }
                VStack(spacing: 8) { answerButtons }
            }
            Text("Your answer keeps your Breeds right and helps measure how accurate Breed Finder is.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var answerButtons: some View {
        choice("Yes") { onAnswer(.correct) }
        choice("No") {
            choosingBreed = true
            onAnswer(.notTopGuess)
        }
        choice("Not sure") { onAnswer(.unsure) }
    }

    private var otherGuesses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which breed is it?")
                .font(.headline)
            ForEach(Array(guesses.enumerated()).dropFirst(), id: \.element.id) { index, guess in
                choice("\(index + 1). \(guess.breed)", alignment: .leading) {
                    onAnswer(.otherBreed(guess.breed, rank: index + 1))
                }
            }
            choice("Another breed…", alignment: .leading, action: onPickBreed)
            choice("I don't know", alignment: .leading) { choosingBreed = false }
        }
    }

    /// A full-width button in the text color on gray, which keeps the contrast high in
    /// light and dark mode.
    private func choice(_ title: String, alignment: Alignment = .center,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.bordered)
        .tint(Color.primary)
    }

    private func thanks(for answer: ScanFeedback) -> String {
        switch answer {
        case .correct:
            return "Thanks for confirming!"
        case .otherBreed:
            return "Thanks for the correction!"
        case .notTopGuess, .unsure:
            return "Thanks! If you find out the breed, tap \(countedAs == nil ? "Choose breed" : "Change")."
        }
    }
}
