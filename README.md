# Breed Finder

An iPhone app that guesses a dog's breed from a 5-second video. Point the camera at a dog, tap record, and the app shows its top 3 guesses. Everything runs on the phone: no server, no account, and the video never leaves the device.

## How it works

Three tabs:

- **Scan:** tap *Scan a Dog* and record 5 seconds (pinch or tap 0.5× / 1× / 2× / 5× to zoom; optional flash), or *Choose Photos* to pick up to 5. Watch the frames or photos get scanned, then get the result: your dog and the best-matching breed as fanned cards, the top 3 guesses (tap one to compare) and the breed's profile. Every scan is saved to your collection; *Wrong breed?* recounts it as the right breed or removes it.
- **Breeds:** a Pokédex of all 176 breeds with how many times you've scanned each, your own dog photos for the ones you've collected, search, and grouping A–Z / by origin / by breed group / collected.
- **Support:** report a problem, how the app works, photo credits, training-data credits.

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

- **The breed model** is a ConvNeXt-Tiny fine-tuned on ~96k photos covering 176 breeds plus "Not a dog" (see [Train the breed model](#train-the-breed-model)).
- **Combining frames:** a frame counts only when the classifier is at least 80% sure it shows a dog (real dogs score above 99%; empty rooms don't). Counting frames add their breed probabilities to a running total, rescaled to 100%, so unsure frames count for less. A video needs at least 2 counting frames and uploaded photos at least 1; otherwise the app says it found no dog instead of guessing.

| File | What it does |
|---|---|
| [ContentView.swift](BreedFinder/ContentView.swift) | The three tabs; the Scan tab's screens |
| [Home/HomeView.swift](BreedFinder/Home/HomeView.swift) | Start screen: *Scan a Dog* and *Choose Photos* |
| [Camera/CameraController.swift](BreedFinder/Camera/CameraController.swift) | Capture session, zoom and flash; records exactly 5 s of portrait video |
| [Camera/ZoomScale.swift](BreedFinder/Camera/ZoomScale.swift) | Turns the Camera app's zoom numbers (0.5×, 1×, 2×, 5×) into the camera's own zoom factors |
| [Scanning/ScanningView.swift](BreedFinder/Scanning/ScanningView.swift) | The frames/photos with a scanner sweep while the model runs |
| [Results/ResultView.swift](BreedFinder/Results/ResultView.swift) | Card fan, top 3, collection status, breed profile |
| [Results/BreedPickerSheet.swift](BreedFinder/Results/BreedPickerSheet.swift) | *Wrong breed?* correction list |
| [Analysis/FrameExtractor.swift](BreedFinder/Analysis/FrameExtractor.swift) | Pulls 5 evenly spaced frames out of the clip |
| [Analysis/PhotoLoader.swift](BreedFinder/Analysis/PhotoLoader.swift) | Loads picked photos the right way up |
| [Analysis/DogAnalyzer.swift](BreedFinder/Analysis/DogAnalyzer.swift) | Per frame: find the dog, crop, classify |
| [Analysis/BreedAggregator.swift](BreedFinder/Analysis/BreedAggregator.swift) | Combines the frames into the top 3 |
| [Breeds/BreedLibrary.swift](BreedFinder/Breeds/BreedLibrary.swift) | Loads breed profiles and reference photos |
| [Breeds/BreedCollection.swift](BreedFinder/Breeds/BreedCollection.swift) | The user's saved scans (on-device JSON + photos) |
| [Breeds/BreedsView.swift](BreedFinder/Breeds/BreedsView.swift), [BreedGrouping.swift](BreedFinder/Breeds/BreedGrouping.swift) | The Breeds tab and its groupings |
| [Support/SupportView.swift](BreedFinder/Support/SupportView.swift) | Support tab, problem reports, credits |
| [ScanModel.swift](BreedFinder/ScanModel.swift) | Scan tab state: home → camera → scanning → result |
| [MLModels/DogBreedClassifier.mlpackage](MLModels/) | The Core ML breed model, generated by `ml/convert_model.py` |

## Breed profiles and photos

- **Profiles** are written in [content/breeds/](content/breeds/) (one JSON object per breed: summary, origin, lifespan, weight, group, temperament, fun facts). [tools/build_breed_content.py](tools/build_breed_content.py) merges them into `Resources/breeds.json` and fails if any breed the model knows has no profile; `--check-wikidata` flags origins that disagree with Wikidata.
- **Reference photos** come from each breed's Wikipedia article (hosted on Wikimedia Commons), fetched by [tools/fetch_breed_photos.py](tools/fetch_breed_photos.py). Only licenses that allow redistribution with credit are used (public domain, CC0, CC BY, CC BY-SA); the app shows author and license under each breed's profile, as those licenses require.

```sh
python tools/fetch_breed_photos.py --labels ~/breedfinder-data/v2/labels.json
python tools/build_breed_content.py --labels ~/breedfinder-data/v2/labels.json --check-wikidata
```

## Run it on your iPhone

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

Change settings in `project.yml`, then run `xcodegen` again. Settings changed in Xcode's UI are lost the next time the project is generated.

**If `xcodegen` gives you trouble**, make the project by hand instead:
1. In Xcode, choose File → New → Project → iOS App. Name it `BreedFinder`, choose SwiftUI, and save it somewhere else.
2. Delete the template's `ContentView.swift`, `BreedFinderApp.swift` and `Assets.xcassets`.
3. Drag this repo's `BreedFinder/` contents and `MLModels/DogBreedClassifier.mlpackage` into the project navigator.
4. In the target settings, set Minimum Deployments to iOS 17 and Supported Destinations to iPhone only. Under the Info tab, add **Privacy - Camera Usage Description** with the text from `project.yml`.

## Train the breed model

The `.mlpackage` is already in the repo, so you only need this to retrain. Training needs Linux or WSL with an NVIDIA GPU; it was developed on an RTX 5060 Ti (16 GB). Data and checkpoints go to `~/breedfinder-data`, outside the repo.

```sh
python3 -m venv ~/.venvs/breedfinder-train && source ~/.venvs/breedfinder-train/bin/activate
pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu128
pip install -r ml/requirements-train.txt

python ml/data/download.py        # datasets below (Kaggle needs ~/.kaggle/access_token)
python ml/data/commons.py         # Wikimedia Commons photos; slow on purpose, resumable
python ml/data/build_dataset.py   # merge labels, resize, dedupe, split  -> ~/breedfinder-data/dataset
python ml/train.py                # fine-tune ConvNeXt-Tiny (~85 min)     -> ~/breedfinder-data/runs/convnext_tiny
python ml/evaluate.py             # test-set report, incl. before/after vs. the ImageNet model
python ml/calibrate.py            # temperature scaling so confidence % are honest
python ml/convert_model.py --checkpoint ~/breedfinder-data/runs/convnext_tiny/best.pt
```

| Source | Photos | Why it's here |
|---|---|---|
| [Stanford Dogs](https://huggingface.co/datasets/maurice-fp/stanford-dogs) | 20.6k | The 120 ImageNet breeds |
| [Tsinghua Dogs](https://huggingface.co/datasets/giacomov/tsinghua_dogs) | 70.4k | Real pet photos; Shiba, Aussie, Husky, Bichon, Cane Corso… |
| [133-breed AKC set](https://s3-us-west-1.amazonaws.com/udacity-aind/dog-project/dogImages.zip) | 8.4k | Dachshund, Bulldog, Akita, Havanese, many rarer breeds |
| [Oxford-IIIT Pets](https://huggingface.co/datasets/timm/oxford-iiit-pet) (CC BY-SA 4.0) | 7.4k | Pit Bull, American Bulldog; its cats become "Not a dog" |
| [Kaggle 70 Dog Breeds](https://www.kaggle.com/datasets/gpiosenka/70-dog-breedsimage-data-set) | 9.3k | Labradoodle, Cockapoo, American Hairless Terrier |
| [Wikimedia Commons](https://commons.wikimedia.org) | varies | Thin popular breeds (Dachshund, English Bulldog…); license and author per photo in each `meta.jsonl` |
| Openverse (one-time, see below) | 1.8k | Doodle mixes: Goldendoodle, Labradoodle, Bernedoodle, Cockapoo, Cavapoo, Maltipoo, Pomsky |
| [COCO val2017](https://cocodataset.org) photos without dogs | 4.8k | Everyday scenes and people for "Not a dog" |

[ml/data/breeds.py](ml/data/breeds.py) maps every dataset's labels onto one breed list; an unmapped label stops the build. Ambiguous labels (Kaggle's "Corgi", ImageNet's husky-like "Eskimo dog") are dropped rather than guessed. Stanford Dogs and Tsinghua Dogs are licensed for non-commercial research, which fits a free app with no ads; revisit the data sources before ever charging for the app.

**About the doodle photos:** they're Creative Commons photos (mostly from Flickr) found through the [Openverse](https://openverse.org) API on 2026-10-31, with license and author recorded in `raw/openverse/<breed>/meta.jsonl`. Openverse's [terms](https://docs.openverse.org/terms_of_service.html) prohibit scraping its catalog, which bulk collection amounts to, so the collector was removed and no more photos will be gathered that way. More doodle photos should come from Wikimedia Commons, or from Openverse only with [expanded access granted by request](https://github.com/WordPress/openverse#keep-in-touch).

`convert_model.py` without `--checkpoint` still builds the original ImageNet-only model. On a Mac, `--test-image photo.jpg` also runs the converted Core ML model so you can check it agrees with PyTorch.

## Accuracy and limitations

Measured on 9,629 held-out test photos (`ml/evaluate.py`), 176 breeds plus "Not a dog":

| | Top-1 | Top-3 |
|---|---|---|
| All test photos | 92.2% | 98.3% |
| Excluding Stanford Dogs (its photos come from ImageNet, which the backbone saw in pretraining) | 93.3% | 98.6% |
| The 116 breeds the original ImageNet-only model knew, excluding Stanford: **original model** | 84.3% | — |
| Same breeds and photos: **this model** | 93.5% | — |

- **"Not a dog"** works: 0.1% of dog photos are rejected, and 1.1% of non-dog photos (people, cats, rooms) are given a breed.
- **Confidence is calibrated** (`ml/calibrate.py`): when the app says 90%, it's right about 90% of the time.
- **Hardest breeds:** look-alikes. Poodle vs. Bichon Frise (teddy-bear-clipped poodles), Pomeranian vs. Japanese Spitz, Husky vs. Malamute, Shih Tzu vs. Lhasa Apso, and the doodle mixes (65–75% top-1, though usually in the top 3). Mixed-breed dogs get their closest breeds, which is often useful but never a DNA test.
- **Not covered:** breeds with too few freely available photos, including Miniature American Shepherd, Rat Terrier, American Bully, Catahoula, Coton de Tulear, Lagotto Romagnolo and smaller designer mixes (Aussiedoodle, Sheepadoodle, Yorkipoo, Morkie…). The app will name the closest breed it knows.

The Swift code doesn't depend on where the model comes from: any Core ML image classifier named `DogBreedClassifier` whose labels are breed names plus `Not a dog` works, as long as `Resources/breeds.json` has a profile for each breed (a unit test checks this).

## Before release

- [x] Support email (`SupportInfo.reportEmail`): breedfinder123@gmail.com.
- [ ] Set `DEVELOPMENT_TEAM` (and if needed `PRODUCT_BUNDLE_IDENTIFIER`) in `project.yml`.
- [ ] Replace the placeholder app icon.
- [ ] Publish a privacy policy page (see below).

## Ship it to the App Store

1. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com) go to Apps → + → New App, choose iOS, and select the bundle ID. The name must be unique on the store. If the bundle ID isn't listed yet, run the app on your phone from Xcode once, or register it under Certificates, Identifiers & Profiles.
2. **Upload a build.** In Xcode, set the run destination to *Any iOS Device*, then Product → Archive → Distribute App → App Store Connect. Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each new upload.
3. **Test with TestFlight.** The build appears in TestFlight after processing. Install it and try it on as many different dogs as you can.
4. **Fill in the listing:**
   - Screenshots for the iPhone size App Store Connect asks for (currently 6.9-inch). Take them on your phone.
   - A **privacy policy URL**, which every app needs. A short page saying the camera video is analyzed on the device and nothing is collected is enough; GitHub Pages works.
   - App Privacy questionnaire: **Data Not Collected**. Problem reports are emails the user writes, reviews and sends themselves, which likely fall under Apple's "optional disclosure" exemption for user-initiated feedback; check its criteria when you fill in the questionnaire.
   - Description, keywords, support URL, category (Reference or Lifestyle), age rating.
5. **Submit for review.**
