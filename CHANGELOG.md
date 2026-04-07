# RecipeBook Changelog

## v1.4.0

### New Features
- Recipe tooltip: added learnability and ignore status
- Opposite-faction vendors shown with (A) or (H) tags in recipe rows, tooltips, and Sources panel
- Non-BoP vendor recipes now visible regardless of faction filter (tradeable via neutral AH)

### Fixes
- Fixed broken tooltips for Shadoweave and other trainer-taught Tailoring recipes
- Fixed recipe count showing inflated numbers when recipes appeared under multiple source categories
- Removed obsolete Blinding Powder

### Data
- Added missing recipes and sources across Blacksmithing, Cooking, Enchanting, Engineering, Leatherworking, and Tailoring

## v1.3.0

### New Features
- Cross-character viewing: browse any character's professions, known recipes and wishlist
- Per-character wishlists: right-click any recipe to add it to a character's wishlist (gold star marker)
- Per-character ignore list: right-click any recipe to ignore it; ignored recipes are dimmed and struck through
- Wishlist info shown on recipe item tooltips game-wide ("Wishlist: CharName")
- New Settings panel

## v1.2.1

### Fixes
- Fixed additional data inconsistencies that were preventing some recipes from showing

## v1.2.0

### New Features
- Now tracking learniability with a Hide Unlearnable filter for known professions

### Improvements
- Large-scale data remapping to solve bad Trainer/Spell/Item IDs
- Eliminated login lag caused by mass item data requests

## v1.1.2

### Fixes
- Fixed incorrect phase and item data

## v1.1.1

### Fixes
- Updated loading sequence to fix bad lag on first open.

## v1.1.0

### New Features
- Added "All Sources" popup — right-click any recipe to see every source with waypoint support
- Added JC world drop zone data — Jewelcrafting designs now show specific drop zones instead of just "World Drop"

### Improvements
- Large-scale reduction in unused data and streamlining of memory usage.

### Fixes
- Fixed recipe phase accuracy for numerous recipes across all professions

## v1.0.0 - Initial Release

- Browse all TBC profession recipes grouped by source type (Trainer, Vendor, Quest, Drop, etc.)
- 12 professions supported including Jewelcrafting
- Continent and Zone filtering with Auto-detect
- Phase filtering (Phases 1-5) with zone-based phase inference
- My Faction filter to hide opposite-faction recipes
- Search bar for quick recipe lookup
- Known recipe tracking via profession window scanning
- Hide Known toggle (auto-enabled for known professions)
- Collapsible source categories
- Waypoint integration via AddressBook + TomTom
- Shift-click to link recipes into chat
- Recipe names colored by item quality
- World drop detection (10+ NPC threshold)
- Minimap button via LibDataBroker
