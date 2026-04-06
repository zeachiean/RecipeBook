#!/usr/bin/env python3
"""Scrape Wowhead for each JC world-drop design's drop locations.

Reads Data/Sources/Jewelcrafting.lua, finds all [id] = { worldDrop = true }
entries, fetches the Wowhead item page, parses the "dropped-by" Listview's
`data: [...]` block, collects unique `location` area IDs across all dropping
creatures, and writes the result to tools/jc_worlddrop_zones.json as
{ "recipeItemID": [areaID, ...], ... }.

Run once; the JSON is committed for reproducibility. Downstream:
  tools/apply_jc_worlddrop_zones.py — patches Data/Sources/Jewelcrafting.lua.
"""

import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "Data", "Sources", "Jewelcrafting.lua")
OUT = os.path.join(HERE, "jc_worlddrop_zones.json")

HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; RecipeBook-tools)"}


def find_worlddrop_ids(text):
    return [int(m.group(1)) for m in re.finditer(
        r"\t\[(\d+)\]\s*=\s*\{\s*worldDrop\s*=\s*true", text)]


def fetch_drop_areas(item_id):
    url = f"https://www.wowhead.com/tbc/item={item_id}"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=20) as r:
        html = r.read().decode("utf-8", errors="replace")

    marker = "id: 'dropped-by'"
    idx = html.find(marker)
    if idx < 0:
        return []
    data_kw = html.find("data:", idx)
    if data_kw < 0:
        return []
    lb = html.find("[", data_kw)
    if lb < 0:
        return []

    # Bracket-match skipping string contents
    depth = 0
    i = lb
    n = len(html)
    while i < n:
        c = html[i]
        if c == '"':
            i += 1
            while i < n and html[i] != '"':
                if html[i] == "\\":
                    i += 1
                i += 1
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                break
        i += 1

    raw = html[lb:i + 1]
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"  parse error for {item_id}: {e}", file=sys.stderr)
        return []

    areas = set()
    for row in rows:
        for a in row.get("location", []) or []:
            areas.add(int(a))
    return sorted(areas)


def main():
    with open(SRC) as f:
        ids = find_worlddrop_ids(f.read())
    print(f"Found {len(ids)} worldDrop JC designs", file=sys.stderr)

    # Resume support
    result = {}
    if os.path.exists(OUT):
        with open(OUT) as f:
            result = {int(k): v for k, v in json.load(f).items()}

    todo = [i for i in ids if i not in result]
    print(f"{len(todo)} to fetch, {len(result)} cached", file=sys.stderr)

    for idx, rid in enumerate(todo, 1):
        try:
            areas = fetch_drop_areas(rid)
            result[rid] = areas
            print(f"[{idx}/{len(todo)}] {rid}: {len(areas)} areas", file=sys.stderr)
        except Exception as e:
            print(f"[{idx}/{len(todo)}] {rid}: ERROR {e}", file=sys.stderr)
            result[rid] = []
        # Flush after each
        with open(OUT, "w") as f:
            json.dump({str(k): v for k, v in sorted(result.items())}, f, indent=2)
        time.sleep(0.4)  # be polite

    print(f"Wrote {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
