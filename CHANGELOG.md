# GearShare

## v0.2.0

- **Wishlist** (`/gs wish`, Ctrl-click on the minimap button):
  - **Ctrl+Alt+click** an item to put it on (or off) your wishlist: bags, chat links,
    character panel, the game's journal, professions, and loot addons that hand clicks on
    to the game (AtlasLoot)
  - a **key binding** (Key Bindings → AddOns → GearShare) for the item under the mouse:
    works over every item tooltip, also in OneForAll
  - **OneForAll's wishlist** (Armory → Gear Planner) counts too, read straight from it
    (switch in the settings)
  - the window groups the list by **instance and boss**, **profession** or "not known
    yet". Where an item comes from is taken from the journal or profession window you add
    it from, and learned when it drops (the instance, and the boss killed just before)
  - a line on the item's tooltip, and a **★ wish** next to your name in everyone's ranking
    when it drops (also in the chat post)
- **Fix:** Pawn was never found ("not found" in the settings) and drops were rated by item level
  only. Pawn keeps its ready state to itself; GearShare now asks `PawnIsReady()`.
- `/gs debug` shows what GearShare finds of Pawn and Naowh Forever.
- **Minimap button**: left click loot window, right click group gear, middle or
  shift-click settings; drag it round the minimap. `/gs minimap on|off`.
- **Settings** (`/gs options`, also under *Options → AddOns → GearShare*):
  - loot window: open by itself, hide players who can't use the item, size,
    height before older drops are hidden, how long drops stay
  - group gear: size
  - minimap button on/off, lock windows, reset window positions, test drop
- **Clear** (and `/gs clear`) also closes the loot window.
- **Which drops**: in the settings, from which quality on drops open the loot window and
  show up in it (common, uncommon, rare, epic; default uncommon). Lower drops are still
  rated, so the rest of the group still gets your verdict.
- **Naowh Forever**:
  - a drop on a player's Naowh BiS list gets a star in the ranking (“★ BiS”, “★ 2. pick”),
    also in the chat post
  - Naowh's Stat Weights can rate drops instead of Pawn: *Settings → Rating*
    (Automatic: Pawn, else Naowh, else item level). GearShare compares the item with what
    you wear in its slot either way, so Pawn and Naowh users fit one ranking

## v0.1.0

- First version.
- When a need/greed roll starts, everyone's GearShare rates the drop with their
  own Pawn scales against what they wear. The loot window shows the group's
  ranking, biggest upgrade first. **Post** writes it into group chat.
- `/gs check [item]` asks the group to rate any item.
- `/gs gear`: the group's gear slot by slot, with each player's weakest slots marked.
- English and German.
