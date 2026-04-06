#!/usr/bin/env python3
"""Port RecipeMaster_TBC phase annotations into all RecipeBook profession files.

Generalization of port_rm_jc_phases.py: walks every profession recipe file,
reads RM's hand-curated `phase = N` annotation per recipe, and writes an
explicit `phase = N,` field into the RecipeBook entry (defaulting to 1 when
RM has none).

SKIP_IDS lists recipes where RM is known to be wrong for Anniversary and we
want to leave the existing dataset-derived value untouched (no explicit phase
field inserted). Verified cases:
  35310/35311 — Potion Injector schematics, drop from Kael'thas Sunstrider
    (Magisters' Terrace, patch 2.4) → phase 5, RM says 1.
  35308/35309 — Unyielding Bracers/Girdle patterns, Sunwell-era world drops
    → phase 5, RM says 1.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RM_DIR = "/Volumes/Exine/World of Warcraft/_anniversary_/Interface/AddOns/RecipeMaster_TBC/Source/Database/Recipes"
RB_DIR = os.path.join(REPO, "Data", "Recipes")

PROFESSIONS = [
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "Firstaid", "Fishing", "Jewelcrafting", "Leatherworking", "Mining",
    "Poisons", "Tailoring",
]

SKIP_IDS = {
    35310, 35311,  # Engineering: Potion Injectors (Kael'thas drop, phase 5)
    35308, 35309,  # Tailoring: Unyielding Bracers/Girdle (Sunwell era, phase 5)
    31870, 31873,  # Jewelcrafting: Anniversary phase 2 overrides (RM says 1)
}


def parse_phases(path):
    with open(path) as f:
        text = f.read()
    out = {}
    i = 0
    while i < len(text):
        m = re.search(r"^\t\[(\d+)\]\s*=\s*\{", text[i:], re.MULTILINE)
        if not m:
            break
        rid = int(m.group(1))
        start = i + m.end()
        depth = 1
        j = start
        while j < len(text) and depth > 0:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        body = text[start:j - 1]
        pm = re.search(r"phase\s*=\s*(\d+)", body)
        out[rid] = int(pm.group(1)) if pm else 1
        i = j
    return out


def patch_file(prof):
    rm_path = os.path.join(RM_DIR, f"{prof}.lua")
    rb_path = os.path.join(RB_DIR, f"{prof}.lua")
    if not os.path.exists(rm_path):
        print(f"  SKIP {prof}: no RM file", file=sys.stderr)
        return
    if not os.path.exists(rb_path):
        print(f"  SKIP {prof}: no RB file", file=sys.stderr)
        return

    phases = parse_phases(rm_path)
    with open(rb_path) as f:
        text = f.read()

    added = replaced = missing = skipped = 0
    pieces = []
    i = 0
    while i < len(text):
        m = re.search(r"^\t\[(\d+)\]\s*=\s*\{", text[i:], re.MULTILINE)
        if not m:
            pieces.append(text[i:])
            break
        pieces.append(text[i:i + m.start()])
        rid_start = i + m.start()
        body_start = i + m.end()
        depth = 1
        j = body_start
        while j < len(text) and depth > 0:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        block = text[rid_start:j]
        inner = text[body_start:j - 1]
        rid = int(m.group(1))

        if rid in SKIP_IDS:
            skipped += 1
            pieces.append(block)
            i = j
            continue

        phase = phases.get(rid)
        if phase is None:
            missing += 1
            pieces.append(block)
        else:
            if re.search(r"phase\s*=\s*\d+", inner):
                new_inner = re.sub(r"phase\s*=\s*\d+", f"phase = {phase}", inner)
                replaced += 1
            else:
                new_inner = inner.rstrip() + f"\n\t\tphase = {phase},\n\t"
                added += 1
            pieces.append(f"\t[{rid}] = {{{new_inner}}}")
        i = j

    new_text = "".join(pieces)
    with open(rb_path, "w") as f:
        f.write(new_text)

    print(f"  {prof:15s}  added={added:4d} replaced={replaced:4d} "
          f"missing={missing:4d} skipped={skipped}", file=sys.stderr)


def main():
    for prof in PROFESSIONS:
        patch_file(prof)


if __name__ == "__main__":
    main()
