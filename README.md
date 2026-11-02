# Breed Finder

An iPhone app that guesses a dog's breed from a 5-second video. Point the camera at a dog, tap record, and the app shows its top 3 guesses. The breed model runs on the phone: no server, no account, and the video never leaves the device. The only thing the app sends is anonymous usage stats, which users can turn off.

## How it works

Three tabs:

- **Scan:** tap *Scan a Dog* and record 5 seconds (pinch or tap 0.5× / 1× / 2× / 5× to zoom; optional flash), or *Choose Photos* to pick up to 5. Watch the frames or photos get scanned, then get the result: your dog and the best-matching breed as fanned cards, the top 3 guesses (tap one to compare) and the breed's profile. Every scan is saved to your collection.
- **"Is it a …?"** under the cards: *Yes* / *No* / *Not sure*. *No* lists the other two guesses, then *Another breed…* (the full list) and *I don't know*. Naming a breed recounts the scan as that breed. *Change* fixes it later or takes the scan out of the collection. The answers are how the [usage stats](#usage-stats) measure real-world accuracy.
- **Breeds:** a Pokédex of all 188 breeds with how many times you've scanned each, your own dog photos for the ones you've collected, search, and grouping A–Z / by origin / by breed group / collected.
- **Support:** report a problem, help & FAQ, privacy policy, the usage-stats switch, how the app works, photo credits, training-data credits.

The collection (scan records and dog photos) is stored only on the device, in Application Support.

### Problem reports

*Report a Problem* (Support tab, or *Report a problem with this scan* on a result) opens a form:

| Field | Notes |
|---|---|
| Problem type | Wrong breed · App crashed · Something didn't work · Suggestion |
| Scan | One of the last 10 scans (thumbnail + what the app said); preselected for wrong-breed reports |
| What breed is it really? | Wrong-breed reports: pick a breed and/or describe it ("Lab × Poodle mix") |
| Details | Free text; required for bugs and suggestions |
| Attach photos | The scan's frames/photos, previewed in the form |
| Included automatically | App version, breed-model version, iOS version, iPhone model, plus the scan's top 3 guesses, frames with a dog, and what it counts as in the collection |

It becomes an email to breedfinder123@gmail.com that the user reviews before sending. Without the Mail app set up, it falls back to the share sheet (photos attached, address copied) or the default mail app (text only). The last 10 scans' frames live in the Caches folder ([Analysis/RecentScans.swift](BreedFinder/Analysis/RecentScans.swift)): they survive crashes and restarts, and the oldest is deleted as each new scan arrives.

Crash logs from users who allow sharing with developers appear in Xcode under **Window → Organizer → Crashes**.

```
record 5 s video ──► pull 5 frames ──► for each frame:                       ──► combine ──► top 3
(AVFoundation,        (0.5 s, 1.5 s,     1. find the dog (Vision's built-in        frames
 no audio)             … 4.5 s)             animal detector)
                                         2. crop a square around it
                                         3. classify the breed (our Core ML model)
```

- **The breed model** is a ConvNeXt-Tiny fine-tuned on ~107k photos covering 188 breeds plus "Not a dog" (see [The breed model](#the-breed-model)).
- **Combining frames:** a frame counts only when the classifier is at least 80% sure it shows a dog (real dogs score above 99%; empty rooms don't). Counting frames add their breed probabilities to a running total, rescaled to 100%, so unsure frames count for less. A video needs at least 2 counting frames and uploaded photos at least 1; otherwise the app says it found no dog instead of guessing.

| File | What it does |
|---|---|
| [ContentView.swift](BreedFinder/ContentView.swift) | The three tabs; the Scan tab's screens |
| [Home/HomeView.swift](BreedFinder/Home/HomeView.swift) | Start screen: *Scan a Dog* and *Choose Photos* |
| [Camera/CameraController.swift](BreedFinder/Camera/CameraController.swift) | Capture session, zoom and flash; records exactly 5 s of portrait video |
| [Camera/ZoomScale.swift](BreedFinder/Camera/ZoomScale.swift) | Turns the Camera app's zoom numbers (0.5×, 1×, 2×, 5×) into the camera's own zoom factors |
| [Scanning/ScanningView.swift](BreedFinder/Scanning/ScanningView.swift) | The frames/photos with a scanner sweep while the model runs |
| [Results/ResultView.swift](BreedFinder/Results/ResultView.swift) | Card fan, top 3, breed profile |
| [Results/FeedbackCard.swift](BreedFinder/Results/FeedbackCard.swift) | "Is it a …?" and whether the scan is saved to your Breeds |
| [Results/BreedPickerSheet.swift](BreedFinder/Results/BreedPickerSheet.swift) | The full breed list behind *Another breed…* and *Change* |
| [Analysis/FrameExtractor.swift](BreedFinder/Analysis/FrameExtractor.swift) | Pulls 5 evenly spaced frames out of the clip |
| [Analysis/PhotoLoader.swift](BreedFinder/Analysis/PhotoLoader.swift) | Loads picked photos the right way up |
| [Analysis/DogAnalyzer.swift](BreedFinder/Analysis/DogAnalyzer.swift) | Per frame: find the dog, crop, classify |
| [Analysis/BreedAggregator.swift](BreedFinder/Analysis/BreedAggregator.swift) | Combines the frames into the top 3 |
| [Breeds/BreedLibrary.swift](BreedFinder/Breeds/BreedLibrary.swift) | Loads breed profiles and reference photos |
| [Breeds/BreedCollection.swift](BreedFinder/Breeds/BreedCollection.swift) | The user's saved scans (on-device JSON + photos) |
| [Breeds/BreedsView.swift](BreedFinder/Breeds/BreedsView.swift), [BreedGrouping.swift](BreedFinder/Breeds/BreedGrouping.swift) | The Breeds tab, its groupings and search (the text matches anywhere in a name; `*` stands for any characters) |
| [Breeds/BreedPager.swift](BreedFinder/Breeds/BreedPager.swift) | Breed pages you swipe through, in the order the list showed them |
| [Breeds/PhotoFocus.swift](BreedFinder/Breeds/PhotoFocus.swift) | Cuts list thumbnails around the dog instead of the middle of the photo |
| [Support/SupportView.swift](BreedFinder/Support/SupportView.swift) | Support tab, problem reports, credits |
| [Support/Analytics.swift](BreedFinder/Support/Analytics.swift) | Anonymous usage stats: the TelemetryDeck App ID and every signal the app sends |
| [ScanModel.swift](BreedFinder/ScanModel.swift) | Scan tab state: home → camera → scanning → result, and the answer to "Is it a …?" |
| [PrivacyInfo.xcprivacy](BreedFinder/PrivacyInfo.xcprivacy) | Privacy manifest (see [Privacy manifest](#privacy-manifest)) |
| `MLModels/DogBreedClassifier.mlpackage` | The Core ML breed model. Not in this public repository (see [The breed model](#the-breed-model)) |

## Breed profiles and photos

- **Profiles** are written in [content/breeds/](content/breeds/) (one JSON object per breed: summary, origin, lifespan, weight, group, temperament, fun facts). [tools/build_breed_content.py](tools/build_breed_content.py) merges them into `Resources/breeds.json` and fails if any breed the model knows has no profile; `--check-wikidata` flags origins that disagree with Wikidata.
- **Reference photos** come from each breed's Wikipedia article (hosted on Wikimedia Commons), fetched by [tools/fetch_breed_photos.py](tools/fetch_breed_photos.py). Only licenses that allow redistribution with credit are used (public domain, CC0, CC BY, CC BY-SA); the app shows author and license under each breed's profile, as those licenses require. Where a photo's Commons page names the photographer only in its description (or its Author field is a bot's guess or a bare link), the credit is corrected by hand in `CREDIT_OVERRIDES` in [tools/build_breed_content.py](tools/build_breed_content.py). That's also where an author's requested link goes (`authorURL`; Pets Adviser asks for petsadviser.com). [Resources/BreedPhotos/README.md](Resources/BreedPhotos/README.md) explains the photos' terms for anyone browsing the repository, and [tools/audit_breed_photos.py](tools/audit_breed_photos.py) checks them all (see *Before release*).

- **Where the dog is** in each photo, found with Apple's Vision by [tools/find_dogs_in_photos.swift](tools/find_dogs_in_photos.swift) and saved to `Resources/BreedPhotos/focus.json`, so list thumbnails are cut around the dog, head included, instead of from the middle. Run it on a Mac after adding or replacing photos; a unit test fails until you do.

```sh
python tools/fetch_breed_photos.py --labels ~/breedfinder-data/v2/labels.json
python tools/build_breed_content.py --labels ~/breedfinder-data/v2/labels.json --check-wikidata
swift tools/find_dogs_in_photos.swift
```

## Run it on your iPhone

This public repository doesn't include the breed model (`MLModels/DogBreedClassifier.mlpackage`), so it won't build as-is. See [The breed model](#the-breed-model).

You need a Mac with Xcode and an iPhone running iOS 17 or later. The Simulator has no camera, so use a real phone.

1. Install [Homebrew](https://brew.sh) if you don't have it, then XcodeGen, which generates the Xcode project from `project.yml`:
   ```sh
   brew install xcodegen
   ```
2. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID (developer.apple.com/account → Membership details). If `com.bryanbee.breedfinder` is already taken, change `PRODUCT_BUNDLE_IDENTIFIER` too.
3. Generate and open the project:
   ```sh
   cd BreedFinder
   xcodegen
   open BreedFinder.xcodeproj
   ```
4. Plug in your iPhone and turn on **Settings → Privacy & Security → Developer Mode** (iOS asks for this the first time). Pick the phone as the run destination and press **⌘R**.
5. **⌘U** runs the unit tests.

Change settings in `project.yml`, then run `xcodegen` again. Settings changed in Xcode's UI are lost the next time the project is generated. Run it again too after pulling changes that add files or packages. The first time you open the project, Xcode downloads the TelemetryDeck package (*Resolving Package Graph*), which needs an internet connection.

**If `xcodegen` gives you trouble**, make the project by hand instead:
1. In Xcode, choose File → New → Project → iOS App. Name it `BreedFinder`, choose SwiftUI, and save it somewhere else.
2. Delete the template's `ContentView.swift`, `BreedFinderApp.swift` and `Assets.xcassets`.
3. Drag this repo's `BreedFinder/` contents and `MLModels/DogBreedClassifier.mlpackage` into the project navigator.
4. In the target settings, set Minimum Deployments to iOS 17 and Supported Destinations to iPhone only. Under the Info tab, add **Privacy - Camera Usage Description** with the text from `project.yml`.

## The breed model

The trained model and its training code are kept in a private repository. In short: a ConvNeXt-Tiny image classifier, fine-tuned on about 107,000 dog photos (deduplicated across sources, with noisy labels filtered out), then calibrated so its confidence percentages are honest, and converted to Core ML to run on the iPhone.

Training data:

| Source | Photos | Why it's here |
|---|---|---|
| [Stanford Dogs](https://huggingface.co/datasets/maurice-fp/stanford-dogs) | 20.6k | The 120 ImageNet breeds |
| [Tsinghua Dogs](https://huggingface.co/datasets/giacomov/tsinghua_dogs) | 70.4k | Real pet photos; Shiba, Aussie, Husky, Bichon, Cane Corso… |
| [133-breed AKC set](https://s3-us-west-1.amazonaws.com/udacity-aind/dog-project/dogImages.zip) | 8.4k | Dachshund, Bulldog, Akita, Havanese, many rarer breeds |
| [Oxford-IIIT Pets](https://huggingface.co/datasets/timm/oxford-iiit-pet) (CC BY-SA 4.0) | 7.4k | Pit Bull, American Bulldog; its cats become "Not a dog" |
| [Kaggle 70 Dog Breeds](https://www.kaggle.com/datasets/gpiosenka/70-dog-breedsimage-data-set) | 9.3k | Labradoodle, Cockapoo, American Hairless Terrier |
| [Dog CEO](https://github.com/jigsawpieces/dog-api-images) photos (a Kaggle copy) | 17.5k, ~660 new | 94% are Stanford Dogs copies, which the dedupe removes. The rest add a little to thin breeds: Jack Russell, Australian Cattle Dog, Dachshund, Shiba Inu. Used from v3. |
| [Wikimedia Commons](https://commons.wikimedia.org) | varies | Thin popular breeds (Dachshund, English Bulldog…); license and author per photo in each `meta.jsonl` |
| Openverse (one-time, see below) | 1.8k | Doodle mixes: Goldendoodle, Labradoodle, Bernedoodle, Cockapoo, Cavapoo, Maltipoo, Pomsky |
| "Pet classifier image directory" (Kaggle) | 13.8k, ~11.5k new | About 100 image-search results for each of 142 breeds (A–P, plus Siberian Husky). Brings most thin breeds to 100+ photos and adds 12 breeds: Azawakh, Cesky Terrier, Chinook, Coton de Tulear, Dutch Shepherd, Finnish Lapphund, Harrier, Miniature Bull Terrier, Mudi, Polish Lowland Sheepdog, Puli, Pumi. Labels are noisy, so photos without a dog, or that the previous model was sure show a different breed, were dropped, and its Cocker Spaniel, Pointer and Mastiff folders are skipped (each name covers more than one of our breeds). |
| [COCO val2017](https://cocodataset.org) photos without dogs | 4.8k | Everyday scenes and people for "Not a dog" |

Every dataset's labels are mapped onto one breed list. Ambiguous labels (Kaggle's "Corgi", ImageNet's husky-like "Eskimo dog", "coonhound") are dropped rather than guessed. Stanford Dogs and Tsinghua Dogs are licensed for non-commercial research, which fits a free app with no ads; revisit the data sources before ever charging for the app. The Dog CEO photos count as the same: the Kaggle copy carries an MIT license whose copyright lines (Mark Otto 2013, Andrew Fong 2017) match the Hyde/Hydeout website theme, so it covers code, not photos its uploader didn't take, and the image repository credits Stanford Dogs for its originals and accepts community submissions with no stated license for the photos. The pet classifier set is image-search results, which belong to their photographers whatever a dataset page says, so the same applies.

**About the doodle photos:** they're Creative Commons photos (mostly from Flickr) found through the [Openverse](https://openverse.org) API on 2026-10-31, with license and author recorded in `raw/openverse/<breed>/meta.jsonl`. Openverse's [terms](https://docs.openverse.org/terms_of_service.html) prohibit scraping its catalog, which bulk collection amounts to, so the collector was removed and no more photos will be gathered that way. More doodle photos should come from Wikimedia Commons, or from Openverse only with [expanded access granted by request](https://github.com/WordPress/openverse#keep-in-touch).


## Accuracy and limitations

The app ships the v3 model: 188 breeds plus "Not a dog", trained on 106,685 photos (after filtering and dedupe). Measured on 10,635 held-out test photos:

| | Top-1 | Top-3 |
|---|---|---|
| All test photos | 91.8% | 98.1% |
| Excluding Stanford Dogs (its photos come from ImageNet, which the backbone saw in pretraining) | 92.7% | 98.2% |
| The 116 breeds the original ImageNet-only model knew, excluding Stanford: **original model** | 85.1% | — |
| Same breeds and photos: **this model** | 93.4% | — |

**v3 vs. v2**, the previous model (176 breeds), scored on the same test photos, for the 176 breeds both know:

| | v2 top-1 | v2 top-3 | v3 top-1 | v3 top-3 |
|---|---|---|---|---|
| v2's own test photos (9,615) | 92.2% | 98.3% | 92.1% | 98.3% |
| New test photos (911) | 82.8% | 93.3% | 89.4% | 96.4% |
| Breeds that had under 100 training photos (415) | 78.6% | 92.0% | 87.7% | 94.9% |

- v3 is as accurate as v2 on the old photos, even though it chooses among 12 more breeds. It's clearly better on web-style photos like the new sources and on breeds that had few photos. The new test photos went through the filter that drops photos v2 was sure were mislabeled, which flatters v2, so the real gap there is, if anything, larger.
- **New breeds** (top-1 on 8–13 test photos each, so rough): Finnish Lapphund and Mudi 100%, Cesky Terrier and Miniature Bull Terrier 90%, Dutch Shepherd 88%, Polish Lowland Sheepdog 80%, Azawakh and Chinook 78%, Coton de Tulear and Pumi 75%, Puli 50% (of only 2), Harrier 33%.
- **"Not a dog"** works: 0.13% of dog photos are rejected, and 0.88% of non-dog photos (people, cats, rooms) are given a breed (v2: 1.13%).
- **Confidence is calibrated** (temperature scaling, T = 0.727, calibration error 0.021): when the app says 90%, it's right about 90% of the time.
- **Hardest breeds:** look-alikes. Poodle vs. Bichon Frise (teddy-bear-clipped poodles), Pomeranian vs. Japanese Spitz, Husky vs. Malamute, Shih Tzu vs. Lhasa Apso, the doodle mixes (65–75% top-1, though usually in the top 3), and the hounds around the new Harrier: Harrier 33% and American Foxhound 30% (of 10), mostly confused with the English Foxhound and Beagle. Mixed-breed dogs get their closest breeds, which is often useful but never a DNA test.
- **Not covered:** breeds with too few freely available photos, including Miniature American Shepherd, Rat Terrier, American Bully, Catahoula, Lagotto Romagnolo and smaller designer mixes (Aussiedoodle, Sheepadoodle, Yorkipoo, Morkie…). The app will name the closest breed it knows.

The Swift code doesn't depend on where the model comes from: any Core ML image classifier named `DogBreedClassifier` whose labels are breed names plus `Not a dog` works, as long as `Resources/breeds.json` has a profile for each breed (a unit test checks this).

## Usage stats

The app sends anonymous signals to [TelemetryDeck](https://telemetrydeck.com) ([Support/Analytics.swift](BreedFinder/Support/Analytics.swift)) to show how Breed Finder does in real use. Users can turn them off under *Support → Share anonymous usage stats*. They contain no photos, nothing users type and nothing that identifies them. The [privacy policy](docs/privacy.html) lists exactly what's sent; update it whenever a signal changes.

**Set it up.** Until `Analytics.appID` is set, the SDK never starts, nothing is sent, and the Support tab hides the switch.
1. Create a free account at [telemetrydeck.com](https://telemetrydeck.com) and add an app called Breed Finder. The free plan covers 50,000 signals a month. A scan sends about 3 signals, plus 1 per app session.
2. Paste the app's ID into `Analytics.appID`. It isn't a secret, because it ships inside the app anyway.
3. Run the app from Xcode and scan something. Debug builds send *test* signals, so turn on *Test Mode* in the dashboard to see them. Only release builds (TestFlight and the App Store) count as real users.

**What's sent:**

| Signal | When | Parameters | Value (averageable) |
|---|---|---|---|
| `Scan.completed` | A scan found a dog | `source` (video/photos), `frames`, `dogFrames`, `topBreed`, `confidence` (10-point range, e.g. `70-80%`), `collectedBreeds`, `modelVersion` | analysis time, ms |
| `Scan.noDogFound` | A scan found no dog | `source`, `frames`, `dogFrames`, `modelVersion` | analysis time, ms |
| `Scan.failed` | Recording, frame extraction, photo loading or analysis failed | `step`, `error` (domain and code) | |
| `Scan.feedback` | The user leaves a result they answered "Is it a …?" on (once, with their final answer) | `answer`, `topBreed`, `actualBreed`, `confidence`, `source`, `modelVersion` | top guess's confidence, 0–1 |
| `Camera.recordingStarted` | Record tapped | `zoom` (ultra-wide / 1x / zoomed in), `flash` | |
| `Report.sent` | A problem report was sent or handed to another app | `kind`, `photosAttached`, `trainingUseAllowed`, `via` | |

TelemetryDeck adds sessions, device model, iOS and app version, locale and similar details to every signal, and counts users by a hashed ID.

**Turning answers into accuracy.** `answer` is one of these values:
- `top1`: the user tapped Yes.
- `top2` or `top3`: No, then picked the 2nd or 3rd guess.
- `notInTop3`: picked another breed from the full list.
- `notTop1`: No, then *I don't know*.
- `unsure`: Not sure.

From those:
- **Top-1 accuracy on real dogs** = `top1` ÷ (`top1` + `top2` + `top3` + `notInTop3` + `notTop1`)
- **Top-3 accuracy on real dogs** = (`top1` + `top2` + `top3`) ÷ (`top1` + `top2` + `top3` + `notInTop3`)
- **Answer rate** = `Scan.feedback` ÷ `Scan.completed`
- **Calibration on real scans:** top-1 accuracy for each `confidence` range. For a calibrated model, scans in the `80-90%` range are right 80–90% of the time.
- **Most-confused breeds:** wrong answers grouped by `topBreed` → `actualBreed`. This tells you which breeds need more photos in the next training run, and `modelVersion` shows whether a new model fixed them.
- **On-device speed:** the median `Scan.completed` value, by device model.
- **Dog-detection rate:** `Scan.completed` ÷ (`Scan.completed` + `Scan.noDogFound`).

Only people who answer are counted, and people don't always know their dog's breed, so present these as *user-reported* accuracy next to the test-set numbers above, not instead of them.

**Without any code:**
- **App Store Connect → Analytics:** impressions, product page views, downloads, conversion rate, sessions, active devices, retention and deletions. Sessions, retention and deletions only cover users who share data with developers.
- **Xcode → Window → Organizer:** crash rate, hangs, launch time and battery use, from the same users.

## Accessibility

- **VoiceOver:**
  - Photos have labels, or are hidden when the text next to them says the same thing.
  - A Breeds row reads as one element ("Beagle, number 25, England", value "Scanned 2 times").
  - The analyzed frames read as a summary ("Frames analyzed: 5. A dog was found in 4.").
  - Scans on a breed's page can be removed from VoiceOver's Actions rotor.
- **Reduce Motion:** the scanner line becomes a steady tint, and the result cards appear already fanned out.
- **Contrast:**
  - The accent orange is #C2410C in light mode (5.2:1 on white, 4.6:1 on gray cards) and #EA580C in dark mode (5.9:1 on black, 4.8:1 on dark cards). Orange text meets WCAG's 4.5:1 in both.
  - White text on orange is 5.2:1 in light mode but 3.6:1 in dark mode, so labels on orange are bold, where Apple's guidance accepts 3:1.
  - No single orange reaches 4.5:1 both as text on a dark background and as a background for white text.
- **No nudging:** "Is it a …?" shows Yes, No and Not sure as identical buttons, so the accuracy numbers aren't pushed up.

## Privacy manifest

[BreedFinder/PrivacyInfo.xcprivacy](BreedFinder/PrivacyInfo.xcprivacy) declares two things:
- **Collected data.** Product interaction, device ID, performance data and other diagnostic data, all for the usage stats. None of it is linked to the user or used for tracking. Problem reports aren't listed, because they're emails the user writes and sends from their own mail app.
- **Required-reason APIs.** UserDefaults (`@AppStorage`, for the Breeds grouping and the usage-stats switch), read and written only by this app (reason CA92.1).

Xcode merges it with TelemetryDeck's own manifest. To see the combined report, choose Product → Archive, then Control-click the archive in the Organizer and choose *Generate Privacy Report*.

## Before release

- [x] Support email (`SupportInfo.reportEmail`): breedfinder123@gmail.com.
- [x] `DEVELOPMENT_TEAM` in `project.yml`: 35ADT9U8CX.
- [ ] Replace the placeholder app icon.
- [x] TelemetryDeck App ID in `Analytics.appID` (see [Usage stats](#usage-stats)). If you ship without it, nothing is collected, and the App Privacy answer becomes **Data Not Collected**. Then remove the usage-stats section from the privacy policy and the collected data types from the privacy manifest.
- [x] Privacy policy: [docs/privacy.html](docs/privacy.html), published at https://bryan-bee.github.io/BreedFinder/privacy.html and linked in the Support tab. Update it whenever the app starts handling data differently.
- [x] Support page: [docs/support.html](docs/support.html), published at https://bryan-bee.github.io/BreedFinder/support.html and linked in the Support tab (*Help & FAQ*).
- [x] Breed photo licenses audited (November 2026). Run `python tools/audit_breed_photos.py` (in the training venv) before every release and after changing any photo. It checks each photo against its Commons page: still there and not flagged, same license, the uploader actually had the right to license it, any credit the photographer requires, and that the file we ship is the credited photo. 14 photos were replaced because nothing showed their uploader had that right (e.g. someone else's photo uploaded with "permission: yes", or a crop of a deleted file).

## Ship it to the App Store

1. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com) go to Apps → + → New App, choose iOS, and select the bundle ID. The name must be unique on the store. If the bundle ID isn't listed yet, run the app on your phone from Xcode once, or register it under Certificates, Identifiers & Profiles.
2. **Upload a build.** In Xcode, set the run destination to *Any iOS Device*, then Product → Archive → Distribute App → App Store Connect. Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each new upload.
3. **Test with TestFlight.** The build appears in TestFlight after processing. Install it and try it on as many different dogs as you can.
4. **Fill in the listing:**
   - Screenshots for the iPhone size App Store Connect asks for (currently 6.9-inch). Take them on your phone.
   - **Privacy policy URL:** https://bryan-bee.github.io/BreedFinder/privacy.html
   - **Support URL:** https://bryan-bee.github.io/BreedFinder/support.html
   - **App Privacy questionnaire:** with the TelemetryDeck App ID set, the answer is **Data Not Linked to You**.
     - Data types: Identifiers → Device ID; Usage Data → Product Interaction; Diagnostics → Performance Data and Other Diagnostic Data.
     - For each one: purpose *Analytics*, not linked to the user's identity, not used for tracking.
     - This matches the privacy manifest. TelemetryDeck's [guide](https://telemetrydeck.com/docs/articles/apple-app-privacy/) covers Device ID and Product Interaction; the diagnostics come from the app's own timing and error signals.
     - Problem reports are emails the user writes, reviews and sends themselves, which likely fall under Apple's "optional disclosure" exemption for user-initiated feedback. Check its criteria when you fill in the questionnaire.
   - Description, keywords, category (Reference or Lifestyle), age rating.
5. **Submit for review.**
