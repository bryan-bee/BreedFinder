"""Check that every breed photo the app ships is legal to use and correctly credited.

    python tools/audit_breed_photos.py            # needs Pillow and imagehash (the training venv has both)
    python tools/audit_breed_photos.py --no-images

For every photo in Resources/breeds.json it checks, against its Wikimedia Commons page:
  1. the file still exists and isn't tagged for deletion, as a copyright violation, or as
     missing a source, license or permission;
  2. its license on Commons is the one we credit;
  3. the right to use it rests on something solid: a permission ticket, a passed Flickr or
     license review, the photographer's own upload (self-license by the credited author), or
     a by-hand review recorded in REVIEWED below;
  4. any credit text the photographer requires appears in our credit;
  5. (unless --no-images) the photo we ship is the credited file, by perceptual hash.

Exits with status 1 if anything needs attention. Run it before every release, and after
changing any photo.
"""

import argparse
import html
import io
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "BreedFinder/0.1 (iOS dog breed app; github.com/bryan-bee/BreedFinder)"
MAX_HASH_DISTANCE = 8

PROBLEM_CATEGORIES = re.compile(r"deletion|copyright violation|copyvio|without (a )?(source|license|permission)|"
                                r"no (source|license|permission)|missing permission|possible copyright|unknown copyright", re.I)
PERMISSION_TICKET = re.compile(r"\{\{\s*(PermissionTicket|OTRS|VRT|PermissionOTRS)\b", re.I)
REVIEW_PASSED = re.compile(r"FlickreviewR[^}]*(status\s*=\s*passed|reviewed-pass)|FlickreviewR/reviewed-pass|"
                           r"\{\{\s*Flickrreview\s*\|\s*[^|}]+\|\s*[^|}]+\}\}|Flickr upload bot/upload\|[^}]*reviewer\s*=\s*\w|"
                           r"\{\{\s*LicenseReview\s*\|[^}]*\w", re.I)
SELF_LICENSE = re.compile(r"\{\{\s*(self|PD-self|GFDL-self[^|}]*|GFDL-user[^|}]*|GFDL-with-disclaimers|Cc-by(-sa)?-[\d.]+-self)\b|"
                          r"(source|quelle)\s*=\s*\{\{\s*own|\{\{\s*own\s*\}\}|own work|eigenes werk", re.I)
BOTS = re.compile(r"bot\b|Bot \(|CommonsDelinker|Flickr upload bot", re.I)

# Photos whose right to use was checked by hand (November 2026), because the automatic rules
# can't see it: a crop whose original is fine, a photographer's own upload to another wiki,
# permission recorded elsewhere, or a first-person statement by the photographer. Each is tied
# to the exact Commons file, so a new photo needs a new review.
REVIEWED = {
    "Airedale Terrier": ("Airedale Terrier.jpg", "Photographer's statement: \"taken by myself, Jane Harvey\""),
    "American Staffordshire Terrier": ("AMERICAN STAFFORDSHIRE TERRIER, Zican’s Bz Ez Dragon (24208348891).2.jpg",
                                       "Crop of a Flickr-reviewed photo by Svenska Mässan"),
    "Bloodhound": ("Bloodhound Erland22.jpg", "Crop of Erland22's own upload"),
    "Boston Terrier": ("Boston-terrier-carlos-de.JPG", "Uploader's own photograph (\"eigene Fotografie\"), self-licensed"),
    "Brittany": ("Zuri txakurra 1 (cropped).JPG", "Crop of the photographer's (Souligne) own upload"),
    "Bull Terrier": ("Bullterrier-3453301920.jpg", "Pixabay photo from 2014, when Pixabay released photos as CC0"),
    "Cairn Terrier": ("Cairn-Terrier-Garten1.jpg", "Photographer's (Ketterechts) own upload to German Wikipedia"),
    "Cane Corso": ("Cane corso temi 1 1024x768x24 (cropped).png", "Crop of the photographer's (Cdomiziani) own upload"),
    "Chihuahua": ("Chihuahua1 bvdb.jpg", "Bonnie van den Born's permission recorded on Dutch Wikipedia; credit names bonfoto.nl"),
    "Chinook": ("Mountan Laurel Ajax the Chinook dog.jpg", "Uploader: \"taken and copyright (2004) by uploader… All rights released\""),
    "Collie": ("Rough-Collie-japan08 (cropped).jpg", "Crop of Yasu w's own upload"),
    "Dandie Dinmont Terrier": ("Dandie Dinmont Terrier 600.jpg", "Sannse's own upload to English Wikipedia"),
    "Dingo": ("Dingo (Canis lupus dingo) Kakadu 2.jpg", "Charles J Sharp's own upload"),
    "Finnish Lapphund": ("Finnish Lapphund Glenchess Revontuli.jpg", "Apdevries' own upload to English Wikipedia, CC BY-SA 2.5"),
    "German Pinscher": ("Bvdb-duitse pincher.jpg", "Bonnie van den Born's permission recorded on Dutch Wikipedia; credit names bonfoto.nl"),
    "German Shepherd": ("German Shepherd - DSC 0346 (10096362833).jpg", "Crop of a Flickr-reviewed photo by gomagoti"),
    "German Shorthaired Pointer": ("Duitse staande korthaar 10-10-2.jpg",
                                   "Bonnie van den Born's permission recorded on Dutch Wikipedia; credit names bonfoto.nl"),
    "German Wirehaired Pointer": ("Dan vom hardenberg (cropped).jpg", "Crop of JainaKo's own upload"),
    "Irish Wolfhound": ("(2) Irish Wolfhound 4.jpg", "Crop of Dux's own upload"),
    "Lakeland Terrier": ("Lakeland Terrier.jpg", "Sannse's own upload to English Wikipedia; the Commons page only lacks a Source field",
                         "Images without source"),
    "Maltese": ("Maltese 600.jpg", "Sannse's own upload to English Wikipedia"),
    "Miniature Schnauzer": ("Miniature Schnauzer salt & pepper (cropped).jpg", "Crop of Canarian's own upload"),
    "Mudi": ("Hondenras Mudi.jpg", "Vulpes' own upload to Dutch Wikipedia, released to the public domain"),
    "Neapolitan Mastiff": ("5 Year old male in Napoli Stance (2).jpg", "Photographer's statement: \"Photo taken by me Philip Thompson\""),
    "Norwegian Elkhound": ("Elkhound2020 (cropped).jpg", "Crop of HawkNightingale175's own upload"),
    "Norwich Terrier": ("Norwichterrier.jpg", "Own upload by its photographer H. Gisin (Hgisin)"),
    "Nova Scotia Duck Tolling Retriever": ("Duck Toller.jpg", "Cal119's own upload to English Wikipedia, released to the public domain"),
    "Petit Basset Griffon Vendeen": ("P Basset Griffon Vendeen 600.jpg", "Sannse's own upload to English Wikipedia"),
    "Pug": ("Mops oct09 cropped2.jpg", "Crop of a Flickr-reviewed photo by Dagur Brynjólfsson"),
    "Puli": ("PuliBlack wb.jpg", "Ellen Levy Finch's (Elf) own upload to English Wikipedia"),
    "Rhodesian Ridgeback": ("Rhodesian ridgeback.jpg", "Bonnie van den Born's permission recorded on Dutch Wikipedia; credit names bonfoto.nl"),
    "Saluki": ("Red Smooth Saluki.jpg", "Own upload by its photographer (Redgunamo)"),
    "Shar-Pei": ("Adult sharpei.jpg", "Self-photographed by the uploader (Denisrw)"),
    "Shiba Inu": ("Taka Shiba.jpg", "Takashiba's own upload to English Wikipedia, released to the public domain"),
    "Shih Tzu": ("Shihtzu (cropped).jpg", "Crop of Canino21's own upload"),
    "Standard Schnauzer": ("Standard Grey Schnauzer (cropped).JPG", "Crop of Tamorlan's own upload"),
    "Tibetan Terrier": ("Tibet Terrier Bennie (cropped).jpg", "Crop of Mr407SW's own upload"),
    "Wire Fox Terrier": ("Elias1červen2006.jpg", "Own upload by the dog's owner and photographer, Simona Nováková (Prskavka)"),
    "Yorkshire Terrier": ("(2 version) Grupp 3, YORKSHIRETERRIER, NO UCH SE UCH Oxzar Amazing Bel’s Toffy (24310212305).jpg",
                          "Crop of a Flickr-reviewed photo by Svenska Mässan"),
}


def get(url: str, raw: bool = False):
    for _ in range(6):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read() if raw else json.load(response)
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(int(error.headers.get("Retry-After", "60")))
    raise RuntimeError(f"Gave up on {url}")


def users_in(text: str) -> set[str]:
    names = set()
    for pattern in [r"(?:User|Benutzer|Gebruiker|Utilisateur|Usuario|Участник)\s*:\s*([^\]|}/<\n]+)",
                    r"\{\{\s*user at project\s*\|\s*([^|}]+)", r"\{\{\s*User\s*\|\s*([^|}]+)",
                    r"Special:Contributions/([^\]|}\s]+)"]:
        names |= {normalize(name) for name in re.findall(pattern, text or "", re.I)}
    return names


def normalize(name: str) -> str:
    return re.sub(r"[\s_]+", "", name.split("~")[0]).lower()


def field(text: str, *names: str) -> str:
    for name in names:
        match = re.search(r"\|\s*" + name + r"\s*=\s*(.*?)(?=\n\s*\||\n\}\})", text, re.I | re.S)
        if match and match.group(1).strip():
            return match.group(1).strip()
    return ""


def other_photographer(text: str) -> str | None:
    """A photographer named in the description ("Author: Jane Doe", "Photo by …"), whom a
    self-license by the uploader doesn't cover unless they're the same person. The Smooth Fox
    Terrier photo was self-licensed by "Tialin" but described as "Author: Virginia M. O'Connor"."""
    description = field(text, "description", "beschreibung")
    match = re.search(r"\b(?:author|photo(?:graph)?(?: taken)? by|picture taken by|foto(?:grafie)? (?:door|von))\s*:?\s*"
                      r"((?:[A-Z][\w.'’-]+ ){1,3}[A-Z][\w.'’-]+)", description)
    return match.group(1) if match else None


def basis(breed: str, title: str, text: str, uploads: list[dict]) -> str | None:
    """What the right to use the photo rests on, or None if nothing solid."""
    if PERMISSION_TICKET.search(text):
        return "permission ticket"
    if REVIEW_PASSED.search(text):
        return "license review passed"
    if SELF_LICENSE.search(text) and not other_photographer(text):
        uploaders = {normalize(u["user"]) for u in uploads if u.get("user") and not BOTS.search(u["user"])}
        # Files moved from another wiki list who uploaded them there; the transferrer doesn't count.
        for log in re.findall(r"original upload log(.*?)(?:\n==|\Z)", text, re.I | re.S):
            uploaders |= users_in(re.sub(r"\{\{\s*transferred from\s*\|[^}]*\}\}", "", log, flags=re.I))
        uploaders |= {normalize(n) for n in re.findall(r"\{\{\s*original uploader\s*\|\s*([^|}]+)", text, re.I)}
        # "{{original uploader|X}}" in the Author field says who uploaded it, not who took it.
        author = re.sub(r"\{\{\s*original uploader[^}]*\}\}", "", field(text, "author", "urheber"), flags=re.I)
        if not author or "assumed" in author.lower() or users_in(author) & uploaders:
            return "photographer's own upload"
    reviewed = REVIEWED.get(breed)
    if reviewed and reviewed[0] == title:
        return f"reviewed by hand: {reviewed[1]}"
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-images", action="store_true", help="skip comparing our photo files with Commons")
    args = parser.parse_args()

    breeds = json.loads((ROOT / "Resources" / "breeds.json").read_text(encoding="utf-8"))
    titles = {"File:" + urllib.parse.unquote(entry["photo"]["sourceURL"].rsplit("/File:", 1)[-1]).replace("_", " "): name
              for name, entry in breeds.items() if entry.get("photo")}
    pages = {}
    items = list(titles)
    for i in range(0, len(items), 20):
        query = urllib.parse.urlencode({
            "action": "query", "format": "json", "formatversion": 2, "titles": "|".join(items[i:i + 20]),
            "prop": "revisions|imageinfo|categories", "rvprop": "content", "rvslots": "main", "cllimit": "max",
            "iiprop": "user|url|extmetadata", "iilimit": 50, "iiurlwidth": 800,
            "iiextmetadatafilter": "LicenseShortName|Attribution"})
        data = get(f"{API}?{query}")
        normalized = {n["to"]: n["from"] for n in data["query"].get("normalized", [])}
        for page in data["query"]["pages"]:
            pages[titles[normalized.get(page["title"], page["title"])]] = page
        time.sleep(1)

    problems, bases = [], {}
    for breed in sorted(breeds):
        credit = breeds[breed].get("photo")
        if not credit:
            continue
        page = pages.get(breed)
        if page is None or page.get("missing"):
            problems.append(f"{breed}: the credited file is gone from Commons")
            continue
        title = page["title"].removeprefix("File:")
        text = page.get("revisions", [{}])[0].get("slots", {}).get("main", {}).get("content", "")
        uploads = page.get("imageinfo", [])
        meta = uploads[0].get("extmetadata", {}) if uploads else {}
        license_now = meta.get("LicenseShortName", {}).get("value", "")
        if license_now.lower() != credit["license"].lower():
            problems.append(f"{breed}: Commons now says {license_now!r}, we credit {credit['license']!r}")
        allowed = set(REVIEWED.get(breed, ("", "", ""))[2:])
        flags = [c["title"].removeprefix("Category:") for c in page.get("categories", [])
                 if PROBLEM_CATEGORIES.search(c["title"]) and c["title"].removeprefix("Category:") not in allowed]
        if flags:
            problems.append(f"{breed}: flagged on Commons: {flags}")
        found = basis(breed, title, text, uploads)
        if found is None:
            problems.append(f"{breed}: nothing shows the uploader had the right to license it ({title})")
        bases[breed] = found
        required = html.unescape(re.sub(r"<[^>]+>", "", meta.get("Attribution", {}).get("value", ""))).strip()
        key = re.sub(r"^(I,\s*|©\s*)", "", required).split(" at ")[0].strip().lower()
        if key and key not in credit["author"].lower():
            problems.append(f"{breed}: the photographer requires the credit {required!r}; ours is {credit['author']!r}")
        if not args.no_images and uploads and uploads[0].get("thumburl"):
            import imagehash
            from PIL import Image

            theirs = Image.open(io.BytesIO(get(uploads[0]["thumburl"], raw=True))).convert("RGB")
            ours = Image.open(ROOT / "Resources" / "BreedPhotos" / credit["file"]).convert("RGB")
            if imagehash.phash(theirs) - imagehash.phash(ours) > MAX_HASH_DISTANCE:
                problems.append(f"{breed}: the photo we ship isn't the credited file {title}")
            time.sleep(0.7)

    counts = {}
    for found in bases.values():
        if found:
            kind = found.split(":")[0]
            counts[kind] = counts.get(kind, 0) + 1
    print(f"Checked {len(bases)} photos: {counts}")
    if problems:
        print(f"\n{len(problems)} need attention:")
        print("\n".join(f"  {p}" for p in problems))
        sys.exit(1)
    print("No problems found.")


if __name__ == "__main__":
    main()
