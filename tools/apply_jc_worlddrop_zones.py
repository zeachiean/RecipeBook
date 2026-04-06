#!/usr/bin/env python3
"""Patch Data/Sources/Jewelcrafting.lua worldDrop entries with scraped zones.

Reads tools/jc_worlddrop_zones.json ({ recipeItemID: [areaID, ...] }) and
rewrites each `worldDrop = true` entry to `worldDrop = { areaID, areaID, ... }`.
Entries with no scraped zones are left as `worldDrop = true`.

Negative sentinel area IDs (-1, -3 — Wowhead's "unknown/instance" markers) are
stripped.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "Data", "Sources", "Jewelcrafting.lua")
ZONES = os.path.join(HERE, "jc_worlddrop_zones.json")


def main():
    with open(ZONES) as f:
        raw = json.load(f)
    zones = {int(k): [a for a in v if a > 0] for k, v in raw.items()}

    with open(SRC) as f:
        text = f.read()

    patched = 0
    skipped = 0

    def repl(m):
        nonlocal patched, skipped
        rid = int(m.group(1))
        areas = zones.get(rid, [])
        if not areas:
            skipped += 1
            return m.group(0)  # leave as worldDrop = true
        patched += 1
        area_str = ", ".join(str(a) for a in sorted(set(areas)))
        return f"\t[{rid}] = {{\n\t\tworldDrop = {{ {area_str} }},"

    new_text = re.sub(
        r"\t\[(\d+)\]\s*=\s*\{\s*worldDrop\s*=\s*true,",
        repl,
        text,
    )

    with open(SRC, "w") as f:
        f.write(new_text)

    print(f"Patched: {patched}, left as flag: {skipped}", file=sys.stderr)


if __name__ == "__main__":
    main()
