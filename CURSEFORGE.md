# ProfPath

**The cheapest way to level your professions, worked out from your realm's live auction prices.**

Leveling guides give everyone the same fixed route. ProfPath looks at *your* character (what you know,
what's in your bags, what you can afford) and at what things cost on *your* auction house right now,
then works out the cheapest path from your current skill. As you level, it keeps checking.

Made for **WoW: Forever**.

## What's new

**v0.2.1: Trainers, owned stock and steadier plans** *(2026-11-21)*

- **The right trainer:** "learn" steps point to the closest trainer who can teach that recipe's skill.
- **Owned stock always helps:** a big stock of one material no longer pulls in a route that needs far more of it.
- **Steadier plans:** equally cheap recipes go to the best yield, then the quickest craft, so the plan is the same every session. Changing "How far ahead" re-plans a plan you're following.
- Show route works on the skinning list, and long text wraps.
- Now also on [Wago Addons](https://addons.wago.io/addons/profpath).

Earlier: **v0.2.0** added gathering routes for Mining, Herbalism and Skinning, skinning by level,
fishing advice and a smarter planner.

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
