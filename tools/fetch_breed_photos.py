"""Fetch one reference photo per breed for the app's result cards.

Each breed's photo is the lead image of its English Wikipedia article, which lives on
Wikimedia Commons under a free license. The app ships these photos, so only licenses
that allow redistribution with attribution are accepted (public domain, CC0, CC BY,
CC BY-SA). Author and license go to credits.json, which the app shows under the photo.

    python tools/fetch_breed_photos.py --labels ~/breedfinder-data/v2/labels.json

Writes Resources/BreedPhotos/<slug>.jpg (longest side 800 px) and
Resources/BreedPhotos/credits.json. Breeds that already have a photo are skipped.
"""

import argparse
import html
import io
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

USER_AGENT = "BreedFinder/0.1 (iOS dog breed app; github.com/bryan-bee/BreedFinder)"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
OUT_DIR = Path(__file__).resolve().parent.parent / "Resources" / "BreedPhotos"
MAX_SIDE = 800
FREE_LICENSE = re.compile(r"^(public domain|pd\b|cc0|cc[ -]by(-sa)?[ -]\d|copyrighted free use|attribution$)", re.I)
# Licenses that don't require crediting an author.
NO_ATTRIBUTION = re.compile(r"^(public domain|pd\b|cc0|copyrighted free use)", re.I)


def artist(info: dict) -> str:
    raw = info.get("extmetadata", {}).get("Artist", {}).get("value", "")
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", raw)).split())


def usable(info: dict) -> bool:
    """Freely licensed, and if the license requires credit, the author is known."""
    license_name = info.get("extmetadata", {}).get("LicenseShortName", {}).get("value", "")
    return bool(FREE_LICENSE.search(license_name)) and (bool(NO_ATTRIBUTION.search(license_name)) or bool(artist(info)))

# Breeds with no Wikipedia article of their own (or whose lead image isn't usable):
# pick a photo from this Commons category instead.
CATEGORIES = {
    "Bernedoodle": "Bernedoodle",
    "Maltipoo": "Maltipoo",
    "Pomsky": "Pomsky",
    "Cavapoo": "Cavapoo",
    # Both redirect to the shared "Belgian Shepherd" article, whose photo is one variety.
    "Belgian Malinois": "Belgian Shepherd Malinois",
    "Belgian Sheepdog": "Belgian Shepherd Groenendael",
}

# Hand-picked Commons files, checked by eye, where the automatic choice was wrong for a
# card (a collage, a drawing, a skull, a plaque) or its author wasn't recorded.
FILES = {
    "Affenpinscher": "Pinczer małpi 756.jpg",
    "Akita": "Akita Inu (male).jpg",
    "American Foxhound": "American Foxhound.jpg",
    "Beagle": "A Beagle standing on the beach.jpg",
    "Bearded Collie": "Bearded Collie.jpg",
    "Belgian Tervuren": "Belgian Tervuren-7-Ch-Sidekicks Masters Di Villa Roma CB RN BN 02 (16397932470).jpg",
    "Border Collie": "Black and white Border Collies.jpg",
    "Curly-Coated Retriever": "Curly coated retriever.JPG",
    "English Bulldog": "AKC English Bulldog Great Falls June 2011.jpg",
    "Gordon Setter": "Nike the Gordon Setter (18 June 2005).jpg",
    "Norwegian Buhund": "Buhunden.jpg",
}

# Breed name -> Wikipedia article, where the plain name is ambiguous or titled differently.
ARTICLES = {
    "Akita": "Akita (dog)",
    "Anatolian Shepherd Dog": "Anatolian Shepherd",
    "Belgian Malinois": "Malinois dog",
    "Belgian Sheepdog": "Groenendael dog",
    "Belgian Tervuren": "Tervuren dog",
    "Bichon Frise": "Bichon Frisé",
    "Boxer": "Boxer (dog)",
    "Brittany": "Brittany dog",
    "Brussels Griffon": "Griffon Bruxellois",
    "Chihuahua": "Chihuahua (dog)",
    "Chinese Crested": "Chinese Crested Dog",
    "Cocker Spaniel": "American Cocker Spaniel",
    "Collie": "Rough Collie",
    "Dalmatian": "Dalmatian dog",
    "Doberman Pinscher": "Dobermann",
    "English Bulldog": "Bulldog",
    "English Toy Spaniel": "King Charles Spaniel",
    "Havanese": "Havanese dog",
    "Lowchen": "Löwchen",
    "Maltese": "Maltese dog",
    "Mastiff": "English Mastiff",
    "Newfoundland": "Newfoundland dog",
    "Papillon": "Papillon dog",
    "Petit Basset Griffon Vendeen": "Petit Basset Griffon Vendéen",
    "Pointer": "Pointer (dog breed)",
    "Pomeranian": "Pomeranian dog",
    "Saint Bernard": "St. Bernard (dog)",
    "Samoyed": "Samoyed dog",
    "Shar-Pei": "Shar Pei",
    "Silky Terrier": "Australian Silky Terrier",
    "Soft Coated Wheaten Terrier": "Soft-coated Wheaten Terrier",
    "Toy Terrier": "English Toy Terrier (Black & Tan)",
}


def get_json(url: str, params: dict) -> dict:
    full = url + "?" + urllib.parse.urlencode({"format": "json", "formatversion": 2, **params})
    for _ in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(full, headers={"User-Agent": USER_AGENT}), timeout=60) as r:
                time.sleep(1.0)
                return json.load(r)
        except urllib.error.HTTPError as error:
            if error.code != 429 and error.code < 500:
                raise
            time.sleep(min(int(error.headers.get("Retry-After") or 30), 900))
    raise RuntimeError(f"gave up on {full}")


def chunks(items, size=50):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def lead_images(breeds: list[str]) -> dict[str, tuple[str, str]]:
    """breed -> (article title, lead image file name) via the batch query API."""
    titles = {ARTICLES.get(b, b): b for b in breeds}
    found = {}
    for batch in chunks(list(titles)):
        data = get_json(WIKIPEDIA_API, {"action": "query", "titles": "|".join(batch), "redirects": 1,
                                        "prop": "pageimages|description|pageprops", "piprop": "name",
                                        "ppprop": "disambiguation"})
        redirects = {r["to"]: r["from"] for r in data["query"].get("redirects", [])}
        normalized = {n["to"]: n["from"] for n in data["query"].get("normalized", [])}
        for page in data["query"]["pages"]:
            requested = redirects.get(page["title"], page["title"])
            requested = normalized.get(requested, requested)
            breed = titles.get(requested)
            if breed is None:
                continue
            if page.get("missing") or "disambiguation" in page.get("pageprops", {}):
                print(f"  {breed}: '{requested}' is missing or a disambiguation page")
            elif "pageimage" not in page:
                print(f"  {breed}: '{page['title']}' has no lead image")
            else:
                description = page.get("description", "")
                if not re.search(r"dog|breed|canine|hybrid|cross", description, re.I):
                    print(f"  {breed}: '{page['title']}' is described as {description!r}; check it")
                found[breed] = (page["title"], page["pageimage"])
    return found


def commons_info(files: list[str]) -> dict[str, dict]:
    info = {}
    for batch in chunks(files):
        data = get_json(COMMONS_API, {"action": "query", "titles": "|".join("File:" + f for f in batch),
                                      "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": 960,
                                      "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist"})
        for page in data["query"]["pages"]:
            if page.get("imageinfo"):
                info[page["title"].removeprefix("File:").replace(" ", "_")] = page["imageinfo"][0]
    return info


def category_photo(category: str) -> tuple[str, dict] | None:
    """First freely licensed, reasonably large, landscape-ish JPEG in a Commons category."""
    data = get_json(COMMONS_API, {"action": "query", "generator": "categorymembers", "gcmtitle": f"Category:{category}",
                                  "gcmtype": "file", "gcmlimit": 50, "prop": "imageinfo",
                                  "iiprop": "url|size|mime|extmetadata", "iiurlwidth": 960,
                                  "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist"})
    candidates = []
    for page in data.get("query", {}).get("pages", []):
        info = (page.get("imageinfo") or [None])[0]
        if not info or info.get("mime") != "image/jpeg" or info.get("width", 0) < 800:
            continue
        if not usable(info) or re.search(r"puppy|puppies|logo|drawing|skull|illustr", page["title"], re.I):
            continue
        aspect = info["width"] / max(info["height"], 1)
        candidates.append((abs(aspect - 1.33), page["title"].removeprefix("File:"), info))
    if not candidates:
        return None
    _, title, info = min(candidates, key=lambda c: c[0])
    return title, info


def download(url: str) -> bytes | None:
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=60) as r:
                data = r.read()
            time.sleep(1.5)
            return data
        except urllib.error.HTTPError as error:
            if error.code != 429:
                return None
            wait = min(int(error.headers.get("Retry-After") or 60), 900)
            print(f"  rate limited; waiting {wait}s", flush=True)
            time.sleep(wait)
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--labels", type=Path, required=True, help="labels.json from build_dataset.py")
    parser.add_argument("--refetch", nargs="*", default=[], help="breeds to fetch again even if they have a photo")
    args = parser.parse_args()

    breeds = [b for b in json.loads(args.labels.read_text()) if b != "Not a dog"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    credits_path = OUT_DIR / "credits.json"
    credits = json.loads(credits_path.read_text()) if credits_path.exists() else {}
    for breed in args.refetch:
        credits.pop(breed, None)
    todo = [b for b in breeds if b not in credits]

    leads = lead_images([b for b in todo if b not in CATEGORIES and b not in FILES])
    infos = commons_info([f for _, f in leads.values()] + list(FILES.values()))
    for breed in todo:
        info, article = None, None
        if breed in FILES:
            file_name = FILES[breed]
            info = infos.get(file_name.replace(" ", "_"))
            if info is None:
                print(f"  {breed}: hand-picked file {file_name} not found on Commons")
                continue
        elif breed in leads:
            article, file_name = leads[breed]
            info = infos.get(file_name.replace(" ", "_"))
            if info is None:
                print(f"  {breed}: lead image {file_name} isn't on Commons (likely non-free)")
            elif not usable(info):
                print(f"  {breed}: lead image {file_name} isn't freely licensed or has no author to credit")
                info = None
        if info is None:
            # Fall back to a photo from the breed's Commons category.
            picked = category_photo(CATEGORIES.get(breed) or (article or breed))
            if picked is None:
                print(f"  {breed}: no usable photo found")
                continue
            file_name, info = picked
            print(f"  {breed}: using {file_name} from its Commons category")
        meta = info.get("extmetadata", {})
        license_name = meta.get("LicenseShortName", {}).get("value", "")
        data = download(info.get("thumburl") or info["url"])
        if data is None:
            print(f"  {breed}: download failed")
            continue
        image = Image.open(io.BytesIO(data)).convert("RGB")
        image.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
        file = f"{slug(breed)}.jpg"
        image.save(OUT_DIR / file, "JPEG", quality=82, optimize=True)
        credits[breed] = {
            "file": file,
            "title": re.sub(r"\.(jpe?g|png)$", "", file_name.replace("_", " "), flags=re.I),
            "author": artist(info) or "Unknown",
            "license": license_name,
            "licenseURL": meta.get("LicenseUrl", {}).get("value"),
            "sourceURL": info.get("descriptionurl"),
            "article": article,
        }
        credits_path.write_text(json.dumps(credits, indent=1, ensure_ascii=False, sort_keys=True))
        print(f"{breed:36s} {file:40s} {license_name}", flush=True)

    missing = [b for b in breeds if b not in credits]
    print(f"\n{len(breeds) - len(missing)}/{len(breeds)} breeds have a photo. Missing: {missing}")


if __name__ == "__main__":
    main()
