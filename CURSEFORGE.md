# ProfPath

**The cheapest way to level your professions, worked out from your realm's live auction prices.**

Leveling guides give everyone the same fixed route. ProfPath looks at *your* character (what you know,
what's in your bags, what you can afford) and at what things cost on *your* auction house right now,
then works out the cheapest path from your current skill. As you level, it keeps checking.

Made for **WoW: Forever**.

## What's new

**v0.1.1: Tools, cooldowns and specializations** *(2026-11-17)*

- **Required tools:** enchanting rods, the Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor and Philosopher's Stone are now known. If you don't carry one, the plan includes the cheapest way to get it, and the Do it list tells you to get it.
- **Specialization recipes** (Tribal, Dragonscale and Elemental Leatherworking, Armorsmith, Weaponsmith, Gnomish and Goblin Engineering) are only suggested if you have that specialization.
- **Long cooldowns:** transmutes, Mooncloth and similar recipes are no longer used as leveling steps.
- **Starter recipes** that come with a profession are known right away.

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
| `/pp minimap on` / `off` | show or hide the minimap button |
| `/pp about` | version and credits |

## Feedback

Questions or feedback: [Discord](https://discord.com/users/120143105952317440) or [open an issue on GitHub](https://github.com/inequitas/ProfPath/issues).

## Credits

- **Trainer locations:** [Wowhead](https://www.wowhead.com/forever) (WoW: Forever database and world map).
- **Recipe data** (skill-up colours, reagents, recipe items): read from the game's own data files via
  [wago.tools](https://wago.tools).

## Notes

- Recipe data matches game build 1.60.1. After a Forever patch, update ProfPath for the newest data.
- Trainer ranks come from their Wowhead titles. What a trainer actually shows you in game always takes
  priority.
