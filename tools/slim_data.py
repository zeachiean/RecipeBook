#!/usr/bin/env python3
"""Strip unused data from RecipeBook's Lua data files.

Big wins:
1. Add phase=5 to 4 phaseless recipes (so Phases.lua can be deleted)
2. Strip `classification` field from NPCs
3. Strip `difficulty` arrays from recipes
4. Prune unreferenced NPCs

Small wins:
5. Prune unreferenced quests
6. Prune unreferenced objects
7. Prune unreferenced unique entry (ID 16365)
8. Strip `level` and `classification` from uniqueDB
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def strip_field(text, field_name):
    """Remove a field assignment (possibly multi-line for tables) from Lua source."""
    # Single-line: \t\tfield = value,\n
    text = re.sub(rf'\t\t{field_name}\s*=\s*[^{{,\n]+,\n', '', text)
    # Multi-line table: \t\tfield = {\n...\t\t},\n
    text = re.sub(
        rf'\t\t{field_name}\s*=\s*\{{[^}}]*\}},?\n',
        '', text, flags=re.DOTALL)
    return text


def extract_brace_block(text, start):
    """Return the content between matched braces starting at text[start] = '{'."""
    depth = 1
    j = start + 1
    while j < len(text) and depth > 0:
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
        j += 1
    return text[start + 1:j - 1]


def collect_referenced_ids(sources_dir, db_type):
    """Collect all IDs referenced from Sources/*.lua for a given type."""
    ids = set()
    if db_type == 'npc':
        keys = ('trainer', 'vendor', 'drop', 'pickpocket')
    elif db_type == 'object':
        keys = ('object',)
    elif db_type == 'quest':
        keys = ('quest',)
    elif db_type == 'unique':
        keys = ('unique',)
    else:
        return ids

    for fn in os.listdir(sources_dir):
        if not fn.endswith('.lua'):
            continue
        with open(os.path.join(sources_dir, fn)) as f:
            text = f.read()
        for key in keys:
            for m in re.finditer(rf'{key}\s*=\s*\{{', text):
                block = extract_brace_block(text, m.end() - 1)
                if db_type == 'unique':
                    for vm in re.finditer(r'(\d+)', block):
                        ids.add(int(vm.group(1)))
                else:
                    for km in re.finditer(r'\[(\d+)\]', block):
                        ids.add(int(km.group(1)))
    return ids


def collect_quest_startnpc_ids(quest_file):
    """Collect NPC IDs referenced by quest startNPC fields."""
    ids = set()
    with open(quest_file) as f:
        text = f.read()
    for m in re.finditer(r'startNPC\s*=\s*(\d+)', text):
        ids.add(int(m.group(1)))
    return ids


def prune_entries(text, keep_ids):
    """Remove top-level [id] = { ... } blocks whose ID is not in keep_ids."""
    pieces = []
    i = 0
    removed = 0
    while i < len(text):
        m = re.search(r'^\t\[(\d+)\]\s*=\s*\{', text[i:], re.MULTILINE)
        if not m:
            pieces.append(text[i:])
            break
        rid = int(m.group(1))
        # Find preceding comment lines (-- ...)
        block_start = i + m.start()
        # Walk back to grab comment lines
        comment_start = block_start
        lines_before = text[i:block_start].split('\n')
        # Check if last non-empty line before block is a comment
        temp = block_start
        while temp > i:
            line_end = temp
            temp2 = text.rfind('\n', i, temp)
            if temp2 < 0:
                break
            line = text[temp2+1:line_end].strip()
            if line.startswith('--'):
                comment_start = temp2 + 1
                temp = temp2
            else:
                break

        body_start = i + m.end()
        depth = 1
        j = body_start
        while j < len(text) and depth > 0:
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
            j += 1
        # Skip trailing comma and newline
        if j < len(text) and text[j] == ',':
            j += 1
        if j < len(text) and text[j] == '\n':
            j += 1

        if rid in keep_ids:
            pieces.append(text[i:j])
        else:
            pieces.append(text[i:comment_start])
            removed += 1
        i = j

    return ''.join(pieces), removed


def main():
    sources_dir = os.path.join(REPO, 'Data', 'Sources')
    recipes_dir = os.path.join(REPO, 'Data', 'Recipes')

    # ── 1. Add phase=5 to 4 phaseless recipes ──
    phase_fixes = {
        'Engineering.lua': [35310, 35311],
        'Tailoring.lua': [35308, 35309],
    }
    for fn, rids in phase_fixes.items():
        path = os.path.join(recipes_dir, fn)
        with open(path) as f:
            text = f.read()
        for rid in rids:
            # Find the entry and insert phase = 5 before closing },
            pattern = rf'(\t\[{rid}\]\s*=\s*\{{.*?requiredSkill\s*=\s*\d+,\n)(\t\}})'
            m = re.search(pattern, text, re.DOTALL)
            if m and 'phase' not in m.group(0):
                text = text[:m.end(1)] + '\t\tphase = 5,\n' + text[m.start(2):]
                print(f"  Added phase=5 to [{rid}] in {fn}", file=sys.stderr)
        with open(path, 'w') as f:
            f.write(text)

    # ── 2. Strip classification from NPCs ──
    npc_path = os.path.join(REPO, 'Data', 'NPCs.lua')
    with open(npc_path) as f:
        text = f.read()
    orig_len = len(text)
    text = strip_field(text, 'classification')
    with open(npc_path, 'w') as f:
        f.write(text)
    print(f"  NPCs: stripped classification, saved {orig_len - len(text)} bytes",
          file=sys.stderr)

    # ── 3. Strip difficulty from recipes ──
    # difficulty is always indented at \t\t and contains only numbers:
    #   \t\tdifficulty = {
    #   \t\t\t300,
    #   \t\t\t...
    #   \t\t},
    total_saved = 0
    for fn in sorted(os.listdir(recipes_dir)):
        if not fn.endswith('.lua'):
            continue
        path = os.path.join(recipes_dir, fn)
        with open(path) as f:
            text = f.read()
        orig = len(text)
        text = re.sub(
            r'\t\tdifficulty = \{\n(?:\t\t\t\d+,\n)+\t\t\},\n',
            '', text)
        with open(path, 'w') as f:
            f.write(text)
        total_saved += orig - len(text)
    print(f"  Recipes: stripped difficulty, saved {total_saved} bytes", file=sys.stderr)

    # ── 4. Prune unreferenced NPCs ──
    ref_npc_ids = collect_referenced_ids(sources_dir, 'npc')
    quest_npc_ids = collect_quest_startnpc_ids(
        os.path.join(REPO, 'Data', 'Quests.lua'))
    ref_npc_ids |= quest_npc_ids
    with open(npc_path) as f:
        text = f.read()
    text, removed = prune_entries(text, ref_npc_ids)
    with open(npc_path, 'w') as f:
        f.write(text)
    print(f"  NPCs: pruned {removed} unreferenced entries", file=sys.stderr)

    # ── 5. Prune unreferenced quests ──
    ref_quest_ids = collect_referenced_ids(sources_dir, 'quest')
    quest_path = os.path.join(REPO, 'Data', 'Quests.lua')
    with open(quest_path) as f:
        text = f.read()
    text, removed = prune_entries(text, ref_quest_ids)
    with open(quest_path, 'w') as f:
        f.write(text)
    print(f"  Quests: pruned {removed} unreferenced entries", file=sys.stderr)

    # ── 6. Prune unreferenced objects ──
    ref_obj_ids = collect_referenced_ids(sources_dir, 'object')
    obj_path = os.path.join(REPO, 'Data', 'Objects.lua')
    with open(obj_path) as f:
        text = f.read()
    text, removed = prune_entries(text, ref_obj_ids)
    with open(obj_path, 'w') as f:
        f.write(text)
    print(f"  Objects: pruned {removed} unreferenced entries", file=sys.stderr)

    # ── 7. Prune unreferenced unique (ID 16365) ──
    ref_unique_ids = collect_referenced_ids(sources_dir, 'unique')
    unique_path = os.path.join(REPO, 'Data', 'Unique.lua')
    with open(unique_path) as f:
        text = f.read()
    text, removed = prune_entries(text, ref_unique_ids)
    with open(unique_path, 'w') as f:
        f.write(text)
    print(f"  Unique: pruned {removed} unreferenced entries", file=sys.stderr)

    # ── 8. Strip level and classification from uniqueDB ──
    with open(unique_path) as f:
        text = f.read()
    orig = len(text)
    text = strip_field(text, 'level')
    text = strip_field(text, 'classification')
    with open(unique_path, 'w') as f:
        f.write(text)
    print(f"  Unique: stripped level+classification, saved {orig - len(text)} bytes",
          file=sys.stderr)


if __name__ == '__main__':
    main()
