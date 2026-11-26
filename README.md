# ProfPath

[![CurseForge downloads](https://img.shields.io/curseforge/dt/1812869?label=CurseForge%20downloads)](https://www.curseforge.com/wow/addons/profpath)
[![Latest release](https://img.shields.io/github/v/release/inequitas/ProfPath)](https://github.com/inequitas/ProfPath/releases/latest)
[![CI](https://github.com/inequitas/ProfPath/actions/workflows/ci.yml/badge.svg?branch=beta)](https://github.com/inequitas/ProfPath/actions/workflows/ci.yml)

**The cheapest way to level your professions in WoW: Forever, worked out from your realm's live auction prices.**

Download: [CurseForge](https://www.curseforge.com/wow/addons/profpath) or [Wago Addons](https://addons.wago.io/addons/profpath) (WoW: Forever).
Questions or feedback: [Discord](https://discord.com/users/120143105952317440) or [open an issue](https://github.com/inequitas/ProfPath/issues).

ProfPath looks at your character (known recipes, bags, gold) and your auction house, plans the cheapest
path from your current skill, and keeps re-checking it while you level. Type `/pp` in game or use the
minimap button: **Prepare → Plan → Do it**. Run `/pp help` for all commands.

<p>
  <img src="Media/screenshots/2-plan.png" alt="Plan tab: the cheapest path with cost per step" width="49%">
  <img src="Media/screenshots/4-do-it.png" alt="Do it tab: what to learn, buy and craft, in batches" width="49%">
</p>

## What's new

**[v0.2.2](https://github.com/inequitas/ProfPath/releases/tag/v0.2.2): Settings, leftovers and a simpler Prepare tab** *(2026-11-26)*

- **Settings:** all options in one place, in plain words (`/pp settings`, the Settings button, or
  Options → AddOns → ProfPath).
- **Leftovers:** the plan makes what it needs from what you have, like Heavy Leather from your Medium
  Leather, or cured hides with vendor salt.
- **Simpler Prepare tab:** gold and how far ahead are one click each.
- The window remembers its position and can be locked or opened with your profession window.
- The minimap route is drawn in the right place. Data for game build 1.60.1.71139.

Earlier: **v0.2.1** picked the right trainer for each recipe and made plans steadier; **v0.2.0** added
gathering routes for Mining, Herbalism and Skinning, skinning by level, fishing advice and a smarter planner.

Earlier versions and full details: [CHANGELOG.md](CHANGELOG.md).

## Development

Requirements: Windows PowerShell, and [Lua 5.4](https://www.lua.org) for the offline tests.

| Task | Command (from this folder) |
|---|---|
| Rebuild recipe data for a new game build | `powershell -ExecutionPolicy Bypass -File tools\build_data.ps1 -Build <build>` |
| Run the optimizer tests | `lua tests/optimizer_spec.lua` |
| Run the simulated in-game test | `lua tests/wow_sim.lua` |
| Install into the game | `powershell -ExecutionPolicy Bypass -File tools\install.ps1` |
| Build the release zip (`dist\`) | `powershell -ExecutionPolicy Bypass -File tools\package.ps1` |
| Regenerate the icon | `powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1` |

Layout: `Optimizer.lua` (pure Lua: planning, budget fitting, scan pruning), `Prices.lua` (auction prices,
scans), `Recipes.lua` (professions, recipes, trainers), `Capture.lua` (vendors, trainers), `Track.lua`
(live tracking), `UI.lua` (window), `Minimap.lua`, `Core.lua` (glue, slash commands), `Data/` (generated
data). Design notes are in `PLAN.md`.

To release: raise `## Version:` in `ProfPath.toc`, add the release to `CHANGELOG.md` and to "What's new"
above, run the tests, commit, then push a matching tag
(`git tag v0.1.1` and `git push origin v0.1.1`). The Release workflow (`.github/workflows/release.yml`,
BigWigs packager with `.pkgmeta`) builds the zip and uploads it to CurseForge and Wago Addons for WoW Forever and
to a GitHub release. It needs the repository secrets `CF_API_KEY` (CurseForge API token) and `WAGO_API_TOKEN`
(Wago API key).

## Credits

- Trainer, ore, herb and creature locations: [Wowhead](https://www.wowhead.com/forever).
- Recipe data and terrain: the game's data files via [wago.tools](https://wago.tools).
- Gathering zones follow the WoW: Forever guides on Wowhead and [wow-professions.com](https://www.wow-professions.com/forever).

## License

MIT, see [LICENSE.txt](LICENSE.txt).
