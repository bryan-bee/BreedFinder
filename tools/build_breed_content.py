"""Merge the breed profiles (content/breeds/*.json) and photo credits into
Resources/breeds.json, the file the app loads, and validate them.

    python tools/build_breed_content.py --labels ~/breedfinder-data/v2/labels.json [--check-wikidata]

Fails if a model label has no profile or a profile is missing a field. Breeds
without a photo are allowed (the app shows a placeholder) but are listed.
--check-wikidata compares each profile's origin with Wikidata's "country of
origin" and prints disagreements for a human to review.
"""

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {"summary": str, "origin": str, "lifespan": str, "weight": str, "group": str,
            "temperament": list, "funFacts": list}
USER_AGENT = "BreedFinder/0.1 (iOS dog breed app; github.com/bryan-bee/BreedFinder)"

# Origins whose parenthetical holds the countries the Breeds tab should group by.
ORIGIN_COUNTRIES = {
    "Pomerania (Germany and Poland)": ["Germany", "Poland"],
    "Mediterranean (developed in France and Belgium)": ["France", "Belgium"],
    "Central Africa (Congo)": ["Congo"],
    "Southern Africa (Zimbabwe)": ["Zimbabwe"],
}
AKC_GROUPS = ["Sporting", "Hound", "Working", "Terrier", "Toy", "Non-Sporting", "Herding"]


def origin_countries(origin: str) -> list[str]:
    """'Scotland and England' -> both; 'United States (Alaska)' -> 'United States'."""
    if origin in ORIGIN_COUNTRIES:
        return ORIGIN_COUNTRIES[origin]
    base = re.sub(r"\s*\(.*\)$", "", origin)
    return [part.strip().removeprefix("the ") for part in re.split(r",| and ", base) if part.strip()]


def clean_author(author: str) -> str:
    """Commons author fields can contain wiki markup and boilerplate; keep the readable part."""
    author = re.sub(r"\(\s*\[\[[^\]]*\|\s*talk\s*\]\]\s*\)", "", author)          # "([[User talk:X|talk]])"
    author = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", author)              # [[target|label]] -> label
    assumed = re.match(r"No machine-readable author provided\.\s*(.+?) assumed", author)
    if assumed:
        return f"{assumed.group(1)} (assumed)"
    # Derivative works name their source file first: 'Original.jpg: "Jane Doe" derivative work: X'.
    author = re.sub(r"^[^:]+\.(jpe?g|png):\s*", "", author, flags=re.I).replace('"', "")
    author = re.sub(r"\s*;?\s*derivative work:", "; derivative work:", author)
    return " ".join(author.split()).strip(" ;,") or "Unknown"


def photo_title(credit: dict) -> str:
    """The Commons file name without "File:" or the extension, e.g. "Akita Inu (male)"."""
    if credit.get("title"):
        return credit["title"]
    name = urllib.parse.unquote((credit.get("sourceURL") or "").rsplit("/", 1)[-1]).removeprefix("File:")
    return re.sub(r"\.(jpe?g|png)$", "", name.replace("_", " "), flags=re.I) or "Photo"


def group_key(group: str) -> str:
    """Normalize the display group to an AKC group, 'Designer crossbreed' or 'Other'."""
    for akc in sorted(AKC_GROUPS, key=len, reverse=True):  # "Non-Sporting" before "Sporting"
        if group == akc or group.startswith(akc + " "):
            return akc
    return "Designer crossbreed" if group == "Designer crossbreed" else "Other"


def load_profiles() -> dict:
    profiles = {}
    for part in sorted((ROOT / "content" / "breeds").glob("*.json")):
        for name, profile in json.loads(part.read_text(encoding="utf-8")).items():
            if name in profiles:
                sys.exit(f"{name} is defined twice (second time in {part.name})")
            profiles[name] = profile
    return profiles


def wikidata_origins(articles: dict[str, str]) -> dict[str, list[str]]:
    """breed -> Wikidata 'country of origin' labels, looked up through each Wikipedia article."""
    def get(url, params):
        full = url + "?" + urllib.parse.urlencode({"format": "json", **params})
        with urllib.request.urlopen(urllib.request.Request(full, headers={"User-Agent": USER_AGENT}), timeout=60) as r:
            return json.load(r)

    items, titles = {}, list(articles.items())
    for i in range(0, len(titles), 50):
        batch = dict(titles[i:i + 50])
        data = get("https://en.wikipedia.org/w/api.php", {"action": "query", "prop": "pageprops", "ppprop": "wikibase_item",
                                                         "redirects": 1, "titles": "|".join(batch.values())})
        resolved = {r["to"]: r["from"] for r in data["query"].get("redirects", [])}
        by_title = {title: breed for breed, title in batch.items()}
        for page in data["query"]["pages"].values():
            breed = by_title.get(resolved.get(page["title"], page["title"]))
            if breed and "wikibase_item" in page.get("pageprops", {}):
                items[breed] = page["pageprops"]["wikibase_item"]

    countries, qids = {}, list(items.items())
    for i in range(0, len(qids), 50):
        batch = dict(qids[i:i + 50])
        data = get("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": "|".join(batch.values()), "props": "claims"})
        for breed, qid in batch.items():
            claims = data["entities"].get(qid, {}).get("claims", {}).get("P495", [])
            countries[breed] = [c["mainsnak"]["datavalue"]["value"]["id"] for c in claims if "datavalue" in c["mainsnak"]]
    country_ids = sorted({c for cs in countries.values() for c in cs})
    names = {}
    for i in range(0, len(country_ids), 50):
        data = get("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": "|".join(country_ids[i:i + 50]),
                                                          "props": "labels", "languages": "en"})
        names.update({q: e.get("labels", {}).get("en", {}).get("value", q) for q, e in data["entities"].items()})
    return {breed: [names[c] for c in cs] for breed, cs in countries.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument("--check-wikidata", action="store_true")
    args = parser.parse_args()

    breeds = [b for b in json.loads(args.labels.read_text()) if b != "Not a dog"]
    profiles = load_profiles()
    credits_path = ROOT / "Resources" / "BreedPhotos" / "credits.json"
    credits = json.loads(credits_path.read_text(encoding="utf-8")) if credits_path.exists() else {}

    problems = [f"no profile for {b}" for b in breeds if b not in profiles]
    for name, profile in profiles.items():
        for field, kind in REQUIRED.items():
            if not isinstance(profile.get(field), kind) or not profile.get(field):
                problems.append(f"{name}: missing or empty {field}")
    if problems:
        sys.exit("\n".join(problems))

    out = {}
    for name in breeds:
        entry = {"name": name, **profiles[name],
                 "originCountries": origin_countries(profiles[name]["origin"]),
                 "groupKey": group_key(profiles[name]["group"])}
        if name in credits:
            c = credits[name]
            license_url = c.get("licenseURL")
            entry["photo"] = {
                "file": c["file"],
                "title": photo_title(c),
                "author": clean_author(c.get("author") or ""),
                "license": c["license"],
                "licenseURL": license_url.replace("http://", "https://") if license_url else None,
                "sourceURL": c.get("sourceURL"),
            }
            # CC BY and CC BY-SA require crediting the author and linking the license.
            if c["license"].upper().startswith("CC BY"):
                if entry["photo"]["author"] == "Unknown" or not entry["photo"]["licenseURL"]:
                    problems.append(f"{name}: {c['license']} photo needs an author and a license link")
        out[name] = entry
    if problems:
        sys.exit("\n".join(problems))
    (ROOT / "Resources" / "breeds.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    unused = sorted(set(profiles) - set(breeds))
    print(f"Wrote Resources/breeds.json: {len(out)} breeds, {sum('photo' in e for e in out.values())} with photos")
    countries = sorted({c for e in out.values() for c in e["originCountries"]})
    groups = sorted({e["groupKey"] for e in out.values()})
    print(f"Origin countries ({len(countries)}): {countries}")
    print(f"Groups: {groups}")
    print(f"Without photos: {[b for b in breeds if b not in credits]}")
    if unused:
        print(f"Profiles not in the model (ignored): {unused}")

    if args.check_wikidata:
        articles = {b: credits.get(b, {}).get("article") or b for b in breeds}
        origins = wikidata_origins(articles)
        print("\nOrigin vs. Wikidata 'country of origin' (only disagreements):")
        for breed in breeds:
            wd = origins.get(breed, [])
            ours = profiles[breed]["origin"].lower()
            if wd and not any(c.lower() in ours or ours in c.lower() for c in wd):
                print(f"  {breed:34s} ours: {profiles[breed]['origin']!r:45s} wikidata: {wd}")


if __name__ == "__main__":
    main()
