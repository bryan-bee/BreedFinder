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
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {"summary": str, "origin": str, "lifespan": str, "weight": str, "group": str,
            "temperament": list, "funFacts": list}
USER_AGENT = "BreedFinder/0.1 (iOS dog breed app; github.com/bryan-bee/BreedFinder)"


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
        entry = {"name": name, **profiles[name]}
        if name in credits:
            c = credits[name]
            entry["photo"] = {k: c.get(k) for k in ("file", "author", "license", "licenseURL", "sourceURL")}
        out[name] = entry
    (ROOT / "Resources" / "breeds.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    unused = sorted(set(profiles) - set(breeds))
    print(f"Wrote Resources/breeds.json: {len(out)} breeds, {sum('photo' in e for e in out.values())} with photos")
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
