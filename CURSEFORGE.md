# ProfPath

**The cheapest way to level your professions, worked out from your realm's live auction prices.**

Leveling guides give everyone the same fixed route. ProfPath looks at *your* character (what you know,
what's in your bags, what you can afford) and at what things cost on *your* auction house right now,
then works out the cheapest path from your current skill. As you level, it keeps checking.

Made for **WoW: Forever**.

## What's new

**v0.2.0: Gathering routes, skinning, fishing and a smarter planner** *(2026-11-21)*

- **Gathering routes** for Mining, Herbalism and Skinning: where to go for your skill, and a compact loop on the world map and minimap that stays on walkable ground, goes around lakes and avoids enemy towns and dangerous camps. Closest zones (and ones with a known flight path) come first.
- **Skinning by level:** beasts that suit your skill and your character level, listed by name.
- **Hot spots and caves:** mines and dense clusters near a route; cave waypoints go to the entrance.
- **Fishing advice:** what to do at your skill, lures, and waypoints to Old Man Heming and Nat Pagle.
- **Smarter planner:** owned items only cover the units you have, batches stay fixed while you craft, and recalculating no longer freezes the game.
- **Crafting stations** are named, and **non-English game clients** are supported.

Full history: [changelog on GitHub](https://github.com/inequitas/ProfPath/blob/main/CHANGELOG.md).

## What it does

- **Plans the cheapest path** to your target skill, counting:
  - the chance of a skill-up at every point;
  - recipe costs (trainer or recipe item);
  - crafting your own intermediates (cured hides, bolts, leather) when that's cheaper;
  - vendor reagents;
  - what you get back from vendoring what you craft.
- **Fits your budget:** use the gold in your bags or type an amount. It plans as far as your money goes,
  buying in batches and vendoring as you go, or everything up front.
- **Scans the auction house:** a fast full scan, or a smart item-by-item scan that skips items only
  used by clearly overpriced recipes and copes with the server's search limits.
- **Step-by-step "Do it" list:** what to learn, what to buy (counting what's already in your bags),
  what to craft first, and when to stop. A big card shows your progress and your skill-up luck.
- **Keeps watching while you level:** it re-checks on every skill-up, tells you when a step is done,
  and offers a cheaper path if prices change. It never switches by itself.
- **Rank-ups and trainers:** it tells you when you can train Expert or Artisan, and points you to the
  nearest trainer who teaches it, with a map waypoint (TomTom is used if you have it).
- **Gathering routes** for Mining, Herbalism and Skinning: the best zones for your skill (closest first), with a
  compact loop on the world map and minimap, hot spots and cave entrances. Fishing gets advice per skill.
- **Minimap button** to open it, with your current step in the tooltip.

## How to use it

1. Open your profession window once (**K**) and visit your profession trainer once.
2. At the auction house, click **Full scan**.
3. Type **/pp** or click the minimap button: **Prepare → Plan → Do it**.

## Commands

| Command | What it does |
|---|---|
| `/pp` | open or close the window |
| `/pp budget 2g` / `mine` / `off` | plan with a set budget, the gold in your bags, or ignore gold |
| `/pp range 30` / `all` | how far ahead to plan |
| `/pp effort 25` | extra cost per craft, if you prefer fewer crafts |
| `/pp route off` | hide the gathering route and its waypoint |
| `/pp gather off` / `on` | gather materials nobody sells yourself (needs the gathering profession) |
| `/pp minimap on` / `off` | show or hide the minimap button |
| `/pp about` | version and credits |

## Feedback

Questions or feedback: [Discord](https://discord.com/users/120143105952317440) or [open an issue on GitHub](https://github.com/inequitas/ProfPath/issues).

## Credits

- **Trainer, ore, herb and creature locations:** [Wowhead](https://www.wowhead.com/forever) (WoW: Forever database).
- **Gathering zones** follow the WoW: Forever guides on [Wowhead](https://www.wowhead.com/forever) and
  [wow-professions.com](https://www.wow-professions.com/forever); the routes themselves are computed by ProfPath.
- **Recipe data and terrain** (skill-up colours, reagents, recipe items, height maps): read from the game's own data files via
  [wago.tools](https://wago.tools).

## Notes

- Recipe data matches game build 1.60.1. After a Forever patch, update ProfPath for the newest data.
- Trainer ranks come from their Wowhead titles. What a trainer actually shows you in game always takes
  priority.
