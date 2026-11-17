# Contributing

Thanks for your interest in ProfPath! Bug reports and pull requests are welcome.

## Branching

Development happens on the **`beta`** branch. `main` only receives release merges.

- Branch your work off `beta`
- Open your pull request **against `beta`**

Accidentally targeted `main`? No problem; just change the base branch with the "Edit" button at the top of your PR, or ask and we'll switch it for you.

## Testing

The planning logic is pure Lua and runs outside the game. With [Lua 5.4](https://www.lua.org) installed, from the repository folder:

```
lua tests/optimizer_spec.lua
lua tests/wow_sim.lua
```

`optimizer_spec.lua` covers the optimizer (including randomized checks against brute force); `wow_sim.lua` loads the whole addon against stubbed game APIs and drives it through scans, plans, budgets, tracking and the window. CI runs both on every push and pull request.

To try a change in game, run `powershell -ExecutionPolicy Bypass -File tools\install.ps1` (edit the destination folder in that script if your game is installed elsewhere) and `/reload`.

If your pull request comes from a fork and it is your first one, the checks wait for a maintainer to approve the workflow run, so you may see no result at all for a while. That is normal, and not something you did wrong.

## Game data

`Data/Recipes.lua` is generated from the game's data tables by `tools/build_data.ps1`, and `Data/Trainers.lua` is compiled from Wowhead. Don't edit them by hand; regenerate `Data/Recipes.lua` for a new game build with `tools\build_data.ps1 -Build <build>`.

## Guidelines

- Keep the addon dependency-free: no libraries, no other addons required.
- No automation. ProfPath suggests; the player clicks. Buying, posting and crafting stay manual, as Blizzard's add-on policy requires.
- Keep it light. Heavy work (planning, pricing) runs only when the window is open or a skill-up happens, and is debounced; a recalculation should stay in the low milliseconds.
- Match the existing code style and run both tests before opening a PR.
