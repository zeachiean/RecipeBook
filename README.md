<p align="center">
  <img src="art/logo.png" alt="RecipeBook" width="200"/>
</p>

<h1 align="center">RecipeBook</h1>

<p align="center">
  A World of Warcraft TBC Anniversary addon for browsing profession recipes by source type.<br/>
  Track known recipes, filter by zone, phase, and faction, and set waypoints to vendors and trainers.
</p>

<p align="center">
  <strong>Author:</strong> Breakbone - Dreamscythe&nbsp;&nbsp;|&nbsp;&nbsp;<strong>Interface:</strong> 20505 (TBC Anniversary)
</p>

---

## Browse Recipes

View every TBC profession recipe organized by source type — Trainer, Vendor, Quest, Drop, and more. Collapsible sections let you focus on what matters. Recipes show name, required skill, and source details at a glance.

<img src="screenshot.png" alt="RecipeBook Main Window" width="600"/>

- 12 professions: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Fishing, Jewelcrafting, Leatherworking, Mining, Poisons, Tailoring
- Recipes grouped by source type with counts
- Recipe names colored by item quality
- Shift-click any recipe to link it in chat

## Known Recipe Tracking

Open your profession window and RecipeBook automatically scans what you've learned. Toggle **Hide Known** to see only the recipes you still need.

- Smart profession dropdown separates your known professions from others
- Hide Known auto-enables for professions you've opened

## Filtering

Narrow results with multiple filter options that work together:

- **Continent & Zone** — dropdown filters with Auto-detect mode for your current location
- **Phase** — filter by content phase (1–5) to see only what's available now
- **My Faction** — hide opposite-faction vendors and quests (enabled by default). Non-BoP vendor recipes remain visible since they're tradeable via neutral AH; opposite-faction vendors are marked with (A) or (H)
- **Search** — filter by recipe name as you type

## Waypoint Integration

Click the green arrow next to any vendor or trainer to set a TomTom waypoint via AddressBook. Trainers link to the nearest trainer for that profession.

- Requires both [AddressBook](https://www.curseforge.com/wow/addons/addressbook) and [TomTom](https://www.curseforge.com/wow/addons/tomtom)

## Data Sources

Recipe data is sourced from [RecipeMaster TBC](https://www.curseforge.com/wow/addons/recipe-master).

## Usage

- **Minimap button** — left-click to toggle the window
- `/rb` — toggle RecipeBook
- `/rb phase <N>` — set max phase (1–5)
- `/rb reset` — reset window position

## Dependencies

RecipeBook ships with these bundled libraries:

- LibStub
- CallbackHandler-1.0
- LibDataBroker-1.1
- LibDBIcon-1.0

**Optional:** AddressBook + TomTom for waypoint integration.

## Installation

Extract the `RecipeBook` folder into your WoW AddOns directory:

```
World of Warcraft/_anniversary_/Interface/AddOns/RecipeBook/
```

After installation, open all of your profession panels to allow RecipeBook to scan your known recipes.
