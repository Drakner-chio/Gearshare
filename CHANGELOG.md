# GearShare

## v0.2.0

- **Minimap button**: left click loot window, right click group gear, shift-click
  settings; drag it round the minimap. `/gs minimap on|off`.
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
