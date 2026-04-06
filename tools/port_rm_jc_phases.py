#!/usr/bin/env python3
"""Port RecipeMaster_TBC's Jewelcrafting phase annotations into RecipeBook.

Reads RecipeMaster_TBC/Source/Database/Recipes/Jewelcrafting.lua and rewrites
Data/Recipes/Jewelcrafting.lua so that every recipe has an explicit
`phase = N,` field matching RM's annotation (defaulting to 1 when RM has none).

RM is the authoritative source for TBC recipe release phases — the MaNGOS-
derived dataset bundled in Data/Phases.lua mis-tags many JC designs, so this
adds a per-recipe override consulted first by Core.lua:GetRecipePhase.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RM = "/Volumes/Exine/World of Warcraft/_anniversary_/Interface/AddOns/RecipeMaster_TBC/Source/Database/Recipes/Jewelcrafting.lua"
RB = os.path.join(REPO, "Data", "Recipes", "Jewelcrafting.lua")


def parse_phases(path):
    """Return {recipeID: phase} from a RecipeMaster recipe file."""
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


def main():
    phases = parse_phases(RM)
    print(f"RM phase entries: {len(phases)}", file=sys.stderr)

    with open(RB) as f:
        text = f.read()

    added = 0
    replaced = 0
    missing = 0

    def patch(m):
        nonlocal added, replaced, missing
        rid = int(m.group(1))
        body = m.group(2)
        phase = phases.get(rid)
        if phase is None:
            missing += 1
            return m.group(0)

        # If a phase field already exists, replace its value; otherwise insert
        # just before the closing brace.
        if re.search(r"phase\s*=\s*\d+", body):
            new_body = re.sub(r"phase\s*=\s*\d+", f"phase = {phase}", body)
            replaced += 1
        else:
            new_body = body.rstrip() + f"\n\t\tphase = {phase},\n\t"
            added += 1
        return f"\t[{rid}] = {{{new_body}}}"

    # Bracket-balanced replacement per top-level [id] = { ... }
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
        block = text[rid_start:j]  # includes leading \t[id] = { ... }
        # Extract parts for patching
        inner = text[body_start:j - 1]
        rid = int(m.group(1))
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
            new_block = f"\t[{rid}] = {{{new_inner}}}"
            pieces.append(new_block)
        i = j

    new_text = "".join(pieces)

    with open(RB, "w") as f:
        f.write(new_text)

    print(f"added={added} replaced={replaced} missing={missing}", file=sys.stderr)


if __name__ == "__main__":
    main()
