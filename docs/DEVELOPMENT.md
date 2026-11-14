# GearShare – development notes

## Files

| File | |
|---|---|
| `Core.lua` | settings (`GearShareDB`), events, roster and names, slash commands |
| `Gear.lua` | what I wear, Pawn scores, `Evaluate(link)`: how much a drop improves my gear |
| `Comm.lua` | addon messages (queue that waits for the end of combat and retries) |
| `Loot.lua` | drops, verdicts, the ranking, posting to chat, `/gs test` |
| `LootWindow.lua`, `GroupWindow.lua` | the two windows |
| `Options.lua` | settings window, minimap button, entry in the game's AddOns settings |
| `Theme.lua` | the look (same style as Gatherline, violet accent) |
| `Locale*.lua` | English keys, German translations |

## Protocol (prefix `GearShare`, fields split by `^`)

| Message | Meaning |
|---|---|
| `H^<protocol>^<version>` | hello. Everyone answers with their gear |
| `G^<slot>:<itemID>:<ilvl>:<score>;…` | (part of) the sender's gear. `score` = best Pawn score, empty without Pawn |
| `E^<item>^<status>^<pct>^<ilvl>^<scale>^<reason>^<bis>` | the sender's verdict on a drop; `bis` = rank on their Naowh BiS list (since 0.2.0, older versions send 7 fields) |
| `C^<item>` | please rate this item (`/gs check`) |

`<item>` is an item string with unique ID, level and spec removed, so it's the
same in every client. Drops are keyed by item ID, random suffix and bonus IDs.
Status: `U` upgrade, `E` empty slot, `S` no upgrade, `X` can't use (`reason`
`need` or `armor`).

## Pawn functions used

`PawnGetItemData`, `PawnGetSingleValueFromItem`, `PawnIsScaleVisible`,
`PawnGetScaleLocalizedName`, `PawnIsArmorBestTypeForPlayer`, `PawnCommon.Scales`,
`PawnIsInitialized` (all from Pawn 2.14, which declares interface 16001).

## Naowh Forever functions used

From the global `NaowhForever` (addon NaowhForever_BiS): `IsBisItem(itemID)` (rank on the
BiS list, nil when off or not on it) and `StatWeights.For`, `.ActiveSpec`, `.Spec`, `.Stats`,
`.Worth`, `.DpsShare`, `.Usable`. Naowh's own upgrade percent (`StatWeights.Gain`) is over the
whole character, so GearShare doesn't use it: it takes `Worth` of the new item and of what is
worn in the slot, like Pawn's values.

## Releasing

The same as Gatherline: **Actions → Release → Run workflow** with a version like
`0.1.0` or `0.1.0-beta1`. Before the first CurseForge upload, put
`## X-Curse-Project-ID: …` into `GearShare.toc` and the `CF_API_KEY` secret into
the repo. On CurseForge, set Pawn as an *optional dependency*.

## Tests

```bash
lua5.1 tests/run.lua    # everything, with a fake game API and a fake Pawn
```

## Testing in the game

- `/gs test` shows a made-up drop with made-up members.
- `/gs check [item]` with a friend in the group shows the whole round trip.
- New files are only picked up after restarting WoW, not after `/reload`.
