#!/usr/bin/env python3
"""
Build a Kometa metadata file of anime content ratings.

Route:
  Kometa log -> AniDB ID   (Kometa already resolved Plex -> AniDB successfully)
  AniDB ID   -> rating     via mapping.animemap.dev, which returns MAL's
                           rating string at mapping.mal.data.rating

Run inside the Kometa container (Unraid's host has no python3):

  docker exec Kometa python3 /config/anime-ratings-fetch.py \
      /config/logs /config/anime-ratings.yml

The first argument may be a single log file OR a logs directory. If a
directory, every meta*.log in it is scanned, newest first, so rotated
logs are picked up automatically.

Anything that fails to resolve is listed at the end and left OUT of the
YAML rather than guessed, so you get an explicit list to handle by hand.
"""

import glob
import json
import os
import re
import sys
import time
import urllib.request

MAPPING = "https://mapping.animemap.dev/api/v1/mapping/anidb/{}"

# MAL rating string -> numeric age scale (unpadded, matches the other libraries)
SCALE = {
    "G": 2,       # G - All Ages
    "PG": 7,      # PG - Children
    "PG-13": 13,  # PG-13 - Teens 13 or older
    "R": 17,      # R - 17+ (violence & profanity)
    "R+": 17,     # R+ - Mild Nudity
    "Rx": 18,     # Rx - Hentai
}

ITEM = re.compile(r"\|\s*\(\d+/\d+\)\s+(.+?)\s*\|")
ANIDB = re.compile(r"No MyAnimeList ID found for AniDB ID '(\d+)'")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "kometa-anime-ratings/1"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def log_files(path):
    if os.path.isdir(path):
        files = glob.glob(os.path.join(path, "meta*.log"))
        return sorted(files, key=os.path.getmtime, reverse=True)
    return [path]


def parse_log(path):
    """Pair each show title with the AniDB ID reported on a following line."""
    pairs, title = [], None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = ITEM.search(line)
            if m:
                title = m.group(1).strip()
                continue
            m = ANIDB.search(line)
            if m and title:
                pairs.append((title, m.group(1)))
                title = None
    seen, out = set(), []
    for t, a in pairs:
        if t not in seen:
            seen.add(t)
            out.append((t, a))
    return out


def extract_rating(payload):
    """mapping.mal.data.rating, e.g. 'PG-13 - Teens 13 or older'."""
    mal = (payload.get("mapping") or {}).get("mal") or {}
    return ((mal.get("data") or {}).get("rating"), mal.get("match_status"))


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    log_path, out_path = sys.argv[1], sys.argv[2]

    shows = []
    for f in log_files(log_path):
        shows = parse_log(f)
        if shows:
            print(f"Using {f}")
            break

    if not shows:
        print("No AniDB IDs found in any log at that path.")
        print()
        print("Those IDs only appear when the Anime library's operations phase")
        print("runs with the MAL source active. If every log has been rotated")
        print("away, restore 'mass_content_rating_update: mal' for the Anime")
        print("library and run operations-only once to regenerate them.")
        sys.exit(1)

    print(f"Found {len(shows)} shows with AniDB IDs\n")

    results, failures = [], []
    for i, (title, anidb) in enumerate(shows, 1):
        tag = f"[{i}/{len(shows)}] {title}"
        try:
            rating, status = extract_rating(get(MAPPING.format(anidb)))
            if not rating:
                why = f"no MAL rating (match_status={status})"
                failures.append((title, anidb, why))
                print(f"  {tag}: {why}")
                continue

            key = rating.split(" - ")[0].strip()
            value = SCALE.get(key)
            if value is None:
                why = f"unmapped rating {rating!r}"
                failures.append((title, anidb, why))
                print(f"  {tag}: {why}")
                continue

            results.append((title, value, rating))
            print(f"  {tag}: {rating} -> {value}")
        except Exception as exc:
            failures.append((title, anidb, str(exc)))
            print(f"  {tag}: ERROR {exc}")
        time.sleep(0.4)  # be polite to a volunteer-run service

    lines = [
        "# Anime content ratings, sourced from MAL via mapping.animemap.dev.",
        "# Generated file. Re-run the script rather than hand-editing.",
        "#",
        "#   2 = all ages | 7 = children | 13 = teens | 17 = 17+ | 18 = adults only",
        "",
        "metadata:",
    ]
    for title, value, rating in sorted(results, key=lambda r: r[0].lower()):
        lines.append(f'  "{title}":')
        lines.append(f"    content_rating: {value}   # {rating}")
        lines.append("")

    with open(out_path, "w", newline="\n") as fh:
        fh.write("\n".join(lines))

    print(f"\nWrote {len(results)} ratings to {out_path}")
    if failures:
        print(f"\n{len(failures)} unresolved, handle these by hand:")
        for title, anidb, why in failures:
            print(f"  {title}  (AniDB {anidb})  {why}")


if __name__ == "__main__":
    main()