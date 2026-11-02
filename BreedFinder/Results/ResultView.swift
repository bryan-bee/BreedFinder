import SwiftUI

struct ResultView: View {
    let result: ScanResult
    let onScanAgain: () -> Void
    let onHome: () -> Void

    @EnvironmentObject private var model: ScanModel
    @EnvironmentObject private var collection: BreedCollection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The breed picked for comparison (tapping a guess); nil shows the counted breed.
    @State private var comparing: String?
    @State private var cardsDealt = false
    @State private var showingPicker = false

    private var record: ScanRecord? { model.currentRecordID.flatMap { collection.record(id: $0) } }
    private var topGuess: BreedGuess? { result.guesses.first }
    private var shownBreed: String? { comparing ?? record?.breed ?? topGuess?.breed }

    private func confidence(of breed: String) -> Double? {
        result.guesses.first { $0.breed == breed }?.confidence
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let shownBreed {
                    header(for: shownBreed)
                    CardFan(dogPhoto: result.dogPhoto, breed: shownBreed,
                            confidence: confidence(of: shownBreed), dealt: cardsDealt)
                    FeedbackCard(guesses: result.guesses, feedback: model.feedback,
                                 countedAs: record?.breed,
                                 timesCounted: record.map { collection.count(for: $0.breed) } ?? 0,
                                 onAnswer: { submit($0) },
                                 onPickBreed: { showingPicker = true })
                    guessList
                    if let profile = BreedLibrary.shared.profile(for: shownBreed) {
                        BreedProfileView(profile: profile)
                    }
                } else {
                    ContentUnavailableView(
                        "No dog found",
                        systemImage: "pawprint",
                        description: Text("Check the \(result.source.itemName)s below. Try again in good light, with the dog filling more of the picture.")
                    )
                }
                FrameStrip(frames: result.frames, title: "\(result.source.itemName.capitalized)s analyzed")
                ReportScanButton(result: result, record: record, scanID: model.currentScanID)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { actions }
        .sensoryFeedback(.success, trigger: cardsDealt)
        .sheet(isPresented: $showingPicker) {
            BreedPickerSheet(suggestions: result.guesses, current: record?.breed,
                             onPick: { submit(ScanFeedback(breed: $0, guesses: result.guesses)) },
                             onUncount: { model.uncountCurrentScan() })
        }
        .onAppear {
            if reduceMotion {
                cardsDealt = true  // the cards appear already fanned out
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) {
                    cardsDealt = true
                }
            }
        }
    }

    /// An answer that names the breed brings the cards back to the breed it now counts as.
    private func submit(_ answer: ScanFeedback) {
        model.answer(answer)
        switch answer {
        case .correct, .otherBreed:
            withAnimation(.snappy) { comparing = nil }
        case .notTopGuess, .unsure:
            break  // they may be comparing guesses to work out the breed
        }
    }

    private func header(for breed: String) -> some View {
        let label: String
        if breed == record?.breed, record?.wasCorrected == true {
            label = "Your pick"
        } else if breed == topGuess?.breed {
            label = "Best match"
        } else {
            label = "Comparing"
        }
        return VStack(spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .textCase(.uppercase)
            Text(breed)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if let confidence = confidence(of: breed) {
                Text("\(confidence, format: .percent.precision(.fractionLength(0))) match")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var guessList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top guesses")
                .font(.title3.bold())
            ForEach(Array(result.guesses.enumerated()), id: \.element.id) { index, guess in
                Button {
                    withAnimation(.snappy) { comparing = guess.breed }
                } label: {
                    GuessRow(rank: index + 1, guess: guess, isShown: guess.breed == shownBreed)
                }
                .buttonStyle(.plain)
            }
            Text("Tap a breed to compare. Mixed-breed dogs often show their parent breeds here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onHome) {
                Label("Home", systemImage: "house.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onScanAgain) {
                Label("Scan another", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .bold()  // white on orange is 3.6:1 in dark mode, enough only for bold text
        .padding()
        .background(.bar)
    }
}

/// Opens the problem report with this scan attached. After a correction, it asks the
/// user to send it, since a corrected photo is exactly what improves the model.
private struct ReportScanButton: View {
    let result: ScanResult
    let record: ScanRecord?
    let scanID: UUID?
    @State private var showingReport = false

    var body: some View {
        let corrected = record?.wasCorrected == true
        Button { showingReport = true } label: {
            Label(corrected ? "Send this correction to help improve Breed Finder" : "Report a problem with this scan",
                  systemImage: corrected ? "paperplane" : "exclamationmark.bubble")
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(scanID == nil)
        .sheet(isPresented: $showingReport) {
            ReportProblemView(kind: result.guesses.isEmpty ? .bug : .wrongBreed,
                              scanID: scanID,
                              actualBreed: corrected ? record?.breed : nil)
        }
    }
}

// MARK: - Cards

/// Two photo cards fanned out like a hand of playing cards: the user's dog on the
/// left, a reference photo of the breed on the right.
private struct CardFan: View {
    let dogPhoto: CGImage?
    let breed: String
    let confidence: Double?
    let dealt: Bool

    var body: some View {
        ZStack {
            PhotoCard(caption: "Your dog") {
                if let dogPhoto {
                    Image(decorative: dogPhoto, scale: 1).resizable().scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .rotationEffect(.degrees(dealt ? -9 : 0), anchor: .bottom)
            .offset(x: dealt ? -64 : 0, y: dealt ? 10 : 0)

            PhotoCard(caption: breed) {
                if let photo = BreedLibrary.shared.photo(for: breed) {
                    FramedPhoto(photo: photo, focus: BreedLibrary.shared.photoFocus(for: breed))
                } else {
                    PhotoPlaceholder()
                }
            }
            .overlay(alignment: .topTrailing) {
                if let confidence {
                    Text(confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                        .padding(14)
                }
            }
            .rotationEffect(.degrees(dealt ? 9 : 0), anchor: .bottom)
            .offset(x: dealt ? 64 : 0)
            .id(breed)  // a fresh card (and fade) when a different breed is shown
            .transition(.opacity)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your dog next to a photo of \(withArticle(breed))")
    }
}

/// A white photo-print style card with a caption under the picture.
private struct PhotoCard<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: 156, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 10)
                .frame(width: 156)
        }
        .padding(8)
        .padding(.bottom, 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }
}

// MARK: - Guesses

private struct GuessRow: View {
    let rank: Int
    let guess: BreedGuess
    let isShown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank). \(guess.breed)")
                    .font(rank == 1 ? Font.headline : Font.body.weight(.medium))
                Spacer()
                Text(guess.confidence, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: guess.confidence)
                .tint(rank == 1 ? Color.accentColor : Color.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: isShown ? 2 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}

// MARK: - Frames

/// The frames or photos that were analyzed. Ones without a dog are dimmed.
private struct FrameStrip: View {
    let frames: [FrameAnalysis]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    Color.clear
                        .aspectRatio(0.75, contentMode: .fit)  // portrait 3:4 tiles
                        .overlay {
                            Image(decorative: frame.image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(frame.prediction.containsDog ? 1 : 0.35)
                        .overlay(alignment: .bottomTrailing) {
                            if frame.prediction.containsDog {
                                Image(systemName: "pawprint.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.accentColor)
                                    .padding(4)
                            }
                        }
                }
            }
            .frame(maxWidth: CGFloat(frames.count) * 72, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(frames.count). A dog was found in \(frames.filter(\.prediction.containsDog).count).")
    }
}
