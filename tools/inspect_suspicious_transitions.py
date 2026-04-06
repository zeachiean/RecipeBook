#!/usr/bin/env python3
"""List recipes where RM's phase differs from our current dataset in ways
that look suspicious (demotions: 2→1, 5→1, etc.).

For each hit, prints: itemID, spellID (teaches), name, RM phase, current phase.
Used to spot-check whether RM's annotation or our dataset is correct on
Anniversary before wholesale porting.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RM_DIR = "/Volumes/Exine/World of Warcraft/_anniversary_/Interface/AddOns/RecipeMaster_TBC/Source/Database/Recipes"
RB_DIR = os.path.join(REPO, "Data", "Recipes")

# Load our dataset-derived phase map (spell+item → max)
PHASES_LUA = os.path.join(REPO, "Data", "Phases.lua")


def load_dataset_phases():
    """Return (spell→phase, item→phase) from Data/Phases.lua."""
    with open(PHASES_LUA) as f:
        text = f.read()
    # Two tables: RecipeBook.recipeSpellPhases and RecipeBook.recipePhases
    spell = {}
    item = {}

    def grab(varname):
        m = re.search(rf"{varname}\s*=\s*\{{(.*?)\n\}}", text, re.DOTALL)
        if not m:
            return {}
        out = {}
        for em in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", m.group(1)):
            out[int(em.group(1))] = int(em.group(2))
        return out

    spell = grab(r"RecipeBook\.recipeSpellPhases")
    item = grab(r"RecipeBook\.recipePhases")
    return spell, item


def parse_rm(path):
    """Return list of (itemID, teaches, name, phase) from RM recipe file."""
    with open(path) as f:
        text = f.read()
    out = []
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
        tm = re.search(r"spellID\s*=\s*(\d+)", body) or re.search(r"teaches\s*=\s*(\d+)", body)
        nm = re.search(r'name\s*=\s*"([^"]*)"', body)
        out.append((
            rid,
            int(tm.group(1)) if tm else None,
            nm.group(1) if nm else "?",
            int(pm.group(1)) if pm else 1,
        ))
        i = j
    return out


def current_phase(spell_map, item_map, item_id, spell_id):
    p = 1
    if spell_id and spell_id in spell_map:
        p = max(p, spell_map[spell_id])
    if item_id in item_map:
        p = max(p, item_map[item_id])
    return p


def main():
    spell_map, item_map = load_dataset_phases()
    print(f"Loaded {len(spell_map)} spell phases, {len(item_map)} item phases",
          file=sys.stderr)

    targets = {
        "Engineering": [(2, 1), (5, 1)],
        "Tailoring": [(5, 1)],
    }

    for prof, transitions in targets.items():
        rm_path = os.path.join(RM_DIR, f"{prof}.lua")
        entries = parse_rm(rm_path)
        print(f"\n=== {prof} ({len(entries)} recipes) ===")
        for rm_phase_from, rm_phase_to in transitions:
            print(f"\n  Current {rm_phase_from} → RM {rm_phase_to}:")
            for rid, teaches, name, rm_phase in entries:
                if rm_phase != rm_phase_to:
                    continue
                cur = current_phase(spell_map, item_map, rid, teaches)
                if cur != rm_phase_from:
                    continue
                print(f"    [{rid}] spell={teaches} cur={cur} rm={rm_phase}  {name}")


if __name__ == "__main__":
    main()
