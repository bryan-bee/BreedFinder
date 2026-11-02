import SwiftUI

/// A breed's summary, facts, temperament, fun facts and photo credit. Used on the
/// result screen and on each breed's page in the Breeds tab.
struct BreedProfileView: View {
    let profile: BreedProfile
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsTitle {
                Text("About the \(profile.name)")
                    .font(.title3.bold())
            }
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
                            .accessibilityHidden(true)
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

struct FactTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)
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

/// Attribution required by the photo's Creative Commons license. The title and license
/// are links (to the photo's Commons page and the license text), and so is the author's
/// name when they ask for a link. Full-contrast text: the gray secondary style is under
/// the 4.5:1 that small text needs, and this credit is legally required.
struct PhotoCreditView: View {
    let credit: BreedPhotoCredit

    var body: some View {
        (Text("Breed photo: ") + Text(credit.attribution))
            .font(.caption)
            .foregroundStyle(.primary)
            .tint(Color.accentColor)
    }
}

/// Shows the entire photo, with a blurred copy filling the leftover space. Reference
/// photos are mostly wide side views; cropping them to a tall frame would cut off the
/// dog's head or tail.
struct WholePhoto: View {
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

struct PhotoPlaceholder: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.15)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.opacity(0.6))
        }
    }
}
