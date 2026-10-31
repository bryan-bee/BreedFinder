import SwiftUI

struct ResultView: View {
    let result: ScanResult
    let onScanAgain: () -> Void
    let onHome: () -> Void

    /// The guess whose card and profile are showing; nil means the top guess.
    @State private var selected: BreedGuess?
    @State private var cardsDealt = false

    private var shown: BreedGuess? { selected ?? result.guesses.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let shown {
                    header(for: shown)
                    CardFan(dogPhoto: result.dogPhoto, breed: shown, dealt: cardsDealt)
                    guessList
                    if let profile = BreedLibrary.shared.profile(for: shown.breed) {
                        BreedProfileView(profile: profile)
                    }
                } else {
                    ContentUnavailableView(
                        "No dog found",
                        systemImage: "pawprint",
                        description: Text("Check the frames below. Try again in good light, with the dog filling more of the screen.")
                    )
                }
                FrameStrip(frames: result.frames)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { actions }
        .sensoryFeedback(.success, trigger: cardsDealt)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) {
                cardsDealt = true
            }
        }
    }

    private func header(for guess: BreedGuess) -> some View {
        VStack(spacing: 4) {
            Text(guess == result.guesses.first ? "Best match" : "Showing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .textCase(.uppercase)
            Text(guess.breed)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("\(guess.confidence, format: .percent.precision(.fractionLength(0))) match")
                .font(.headline)
                .foregroundStyle(.secondary)
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
                    withAnimation(.snappy) { selected = guess }
                } label: {
                    GuessRow(rank: index + 1, guess: guess, isShown: guess == shown)
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
        .padding()
        .background(.bar)
    }
}

// MARK: - Cards

/// Two photo cards fanned out like a hand of playing cards: the user's dog on the
/// left, a reference photo of the guessed breed on the right.
private struct CardFan: View {
    let dogPhoto: CGImage?
    let breed: BreedGuess
    let dealt: Bool

    var body: some View {
        ZStack {
            PhotoCard(caption: "Your dog") {
                if let dogPhoto {
                    Image(decorative: dogPhoto, scale: 1).resizable().scaledToFill()
                } else {
                    CardPlaceholder()
                }
            }
            .rotationEffect(.degrees(dealt ? -9 : 0), anchor: .bottom)
            .offset(x: dealt ? -64 : 0, y: dealt ? 10 : 0)

            PhotoCard(caption: breed.breed) {
                if let photo = BreedLibrary.shared.photo(for: breed.breed) {
                    WholePhoto(image: Image(uiImage: photo))
                } else {
                    CardPlaceholder()
                }
            }
            .overlay(alignment: .topTrailing) {
                Text(breed.confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .padding(14)
            }
            .rotationEffect(.degrees(dealt ? 9 : 0), anchor: .bottom)
            .offset(x: dealt ? 64 : 0)
            .id(breed.breed)  // a fresh card (and fade) when a different guess is picked
            .transition(.opacity)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your dog next to a photo of a \(breed.breed)")
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

/// Shows the entire photo inside the card, with a blurred copy filling the leftover
/// space. Reference photos are mostly wide side views; cropping them to a tall card
/// would cut off the dog's head or tail.
private struct WholePhoto: View {
    let image: Image

    var body: some View {
        ZStack {
            image
                .resizable()
                .scaledToFill()
                .blur(radius: 14)
                .opacity(0.6)
            image
                .resizable()
                .scaledToFit()
        }
    }
}

private struct CardPlaceholder: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.15)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.opacity(0.6))
        }
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

// MARK: - Breed profile

private struct BreedProfileView: View {
    let profile: BreedProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("About the \(profile.name)")
                .font(.title3.bold())
            Text(profile.summary)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 16) {
                FactTile(icon: "globe", title: "Origin", value: profile.origin)
                FactTile(icon: "heart.fill", title: "Average lifespan", value: profile.lifespan)
                FactTile(icon: "scalemass.fill", title: "Weight", value: profile.weight)
                FactTile(icon: "rosette", title: "Group", value: profile.group)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Temperament")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.temperament.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Fun facts")
                    .font(.headline)
                ForEach(profile.funFacts, id: \.self) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                        Text(fact)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let credit = profile.photo {
                PhotoCreditView(credit: credit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct FactTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Attribution required by the photo's Creative Commons license.
private struct PhotoCreditView: View {
    let credit: BreedPhotoCredit

    var body: some View {
        let text = Text("Breed photo: \(credit.author) · \(credit.license) · Wikimedia Commons")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let source = credit.sourceURL.flatMap(URL.init(string:)) {
            Link(destination: source) { text }
        } else {
            text
        }
    }
}

// MARK: - Frames

/// The frames pulled from the video. Frames without a dog are dimmed.
private struct FrameStrip: View {
    let frames: [FrameAnalysis]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frames analyzed")
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
        }
    }
}
