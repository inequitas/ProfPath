# ProfPath — dynamic profession leveling optimizer (WoW addon)

## Status (2026-11-16)
Built: M1 optimizer (14 tests incl. 300 random brute-force checks), M2 adapter + data generator,
M3 prices (Auctionator > TSM > own C_AuctionHouse scan; merchant + trainer capture), M4 window (`/pp`).
`tests/wow_sim.lua` loads every file against stubbed WoW APIs and runs a full recalc. Run tests with
`lua tests/optimizer_spec.lua` and `lua tests/wow_sim.lua` (Lua 5.4 at %LOCALAPPDATA%\Programs\Lua\bin).
Install with `tools\install.ps1`.

Research findings:
- Forever changes gray thresholds 25–35 points vs Classic and adds 600+ recipes: Classic guides/data are wrong.
- wago.tools publishes Forever DB2 tables per build (CSV: `https://wago.tools/db2/<Table>/csv?build=1.60.1.70938`).
  It blocks automated fetches from Claude's environment; the user runs `tools\build_data.ps1`, or downloads
  the CSVs in a browser into `tools\.cache\1.60.1.70938\` (SkillLine, SkillLineAbility, SpellReagents,
  SpellEffect, SpellName, ItemSparse, ItemEffect, ItemXItemEffect) and reruns the script.
- Reference implementation of the same data pipeline: github.com/cjber/skillup-forever (GPL-3.0; read for
  approach only, do not copy code or data). Trainer costs are not in DB2; ProfPath captures them in game.

Verified from the in-game API dump (2026-11-16): GetProfessions/GetProfessionInfo, C_TradeSkillUI
(GetBaseProfessionInfo, GetRecipeInfo with learned/relativeDifficulty/maxTrivialLevel, GetRecipeSchematic),
full C_AuctionHouse search API, C_MerchantFrame.GetItemInfo, trainer globals. Missing globals: GetItemInfo,
GetItemCount, GetCoinTextureString, GetMerchantItemInfo, GetSkillLineInfo (use C_Item.*).
GetAllRecipeIDs returns recipes of every profession: filter by skill line. Skill line names repeat
(165 and 2945 are both "Leatherworking"): pick the one with recipes. DB2 MinSkillLineRank is 1 for nearly
all recipes, so learn requirements come from trainer capture (GetTrainerServiceSkillReq) and recipe items
(ItemSparse.RequiredSkillRank). Recipe items link via ItemEffect TriggerType 6 → SpellID = recipe.

AH scanning (verified from scan logs): replies take 0.06–0.4 s. After ~70 quick searches the client
throttles by silently ignoring SendSearchQuery (no AUCTION_HOUSE_THROTTLED_MESSAGE_SENT). Scanner waits
1 s for SENT, then backs off 1→15 s and retries the same item, widening spacing between requests.
Regular items send ITEM_SEARCH_RESULTS_UPDATED twice (second is fuller); commodities report unitPrice.
Scan scope: `range` option (default next 30 points) + learnable recipes only + intermediates chain;
`Optimizer.dominated` prunes items only used by recipes whose lower-bound cost per point exceeds 1.5x
(3x if product unpriced) a fully priced KNOWN recipe at every level (randomized test: never loses optimum).
Performance: recalcs debounced 1 s and suppressed during scans; item-name loads only redraw;
profession-window capture debounced; scan timer at 10 Hz. Recalc ~3 ms at range 30 on real LW data.

Window (UI.lua): three-tab wizard. 1 Prepare = checklist (profession read, trainer, data, prices + Full
scan / Scan buttons, range). 2 Plan = cards (spend/back/net/crafts) + clickable steps with detail.
3 Do it = Learn / Buy / Craft first / Level up with live ticks. Track.lua: counts crafts and points per
recipe vs expected (sum of chances) for luck, re-plans on every skill-up even when hidden, alerts
(UIErrorsFrame + sound + chat) on planned step change or a cheaper switch. `/pp track off` disables.
Full AH snapshot (ReplicateItems) verified working on Forever; 15-min cooldown.
Offline tools: tests/repro_real.lua (plan from real SavedVariables), tests/compare_guide.lua.

Locked plans: opening Do it commits the plan (char.commit[prof] = steps {from,to,recipeID}, target)
and records the bags as starting stock (char.stock[prof]); stock only decreases (min with bags), so
materials bought later are valued at cost, never free. Locked plan = optimize with lockAt(skill).
A fresh plan is computed alongside; offered (alert + Switch button) only if it saves >=10% and >=20s.
"New plan" unlocks but keeps the stock; reaching the target clears both. Budget fitting applies before
locking only. `/pp owned on` = treat all bags as free.

Ranks: Recipes.RANKS (Classic: Journeyman 150 @50/lvl10, Expert 225 @125/lvl20, Artisan 300 @200/lvl35),
overridden by trainer capture (ProfPathDB.ranks). Plans go past the cap when the character level allows,
with rank cost in learnTotal and a rank row before the first step past the cap. Unseen trainer recipes
(no recipe item, not on the trainer list) get estimated req (yellow - gap; yellow if gap <= 10) and cost
(captured costs near that skill, else scaled by (req/maxReq)^2). Alert at the rank's skill; when the cap
rises the lock is dropped and a fresh plan is made. Rank service names on the Forever trainer unverified.

Trainers: Data/Trainers.lua = 289 trainers for all 12 professions (Wowhead Forever world-map data file
nether.wowhead.com/forever/data/world-map + per-NPC tooltips for title and exact coords; uiMap from the
map's "places"). Rank cap from title (Journeyman 150 / Expert 225 / Artisan|Master 300). Merged with
trainers visited in game (seen ranks win). Distance via C_Map.GetWorldPosFromMapPos for player and
trainer, same continent only. Titles may lag the game: UI always shows a second option.

Still unverified (check via `/pp api`, `/pp probe`, `/reload`, then read
`WTF\Account\*\SavedVariables\ProfPath.lua`): GetProfessions vs GetSkillLineInfo; C_TradeSkillUI
GetBaseProfessionInfo / GetRecipeInfo fields (learned, relativeDifficulty); C_AuctionHouse search events and
whether ItemSearchResultInfo.buyoutAmount is per unit (`itemScanSample`); trainer and merchant APIs.

Goal: read the player's professions, price every option from live auction data, and show the
cheapest path from current skill to max. Recompute whenever skill, bags or prices change.

Rules for the implementer: verify every WoW API against warcraft.wiki.gg for the detected
client build before using it; do not trust memory. Keep each milestone working and loadable.

## M0 — Identify the client (blocker, do first)
Known: `GetBuildInfo()` = 1.60.1, build 70938 (Nov 12 2026), interface **16001** → `## Interface: 16001`
in the `.toc`. Confirmed in game: `C_TradeSkillUI` and `C_AuctionHouse` exist; `GetNumTradeSkills` and
`GetNumCrafts` do not. **Use adapter A only; do not build adapter B.** Consequences:
- A 1.x client may expose only a subset of the modern namespaces, and this build postdates the
  planner's documentation. First task: write a throwaway `/profpath api` command that prints every
  function name in `C_TradeSkillUI`, `C_AuctionHouse` and `C_Item`, have the user paste the output,
  and code only against what is listed.
- The modern recipe API reports a difficulty colour, not the yellow/gray thresholds. Get thresholds
  from the static data in M2 if the DB2 export for build 70938 is available; otherwise estimate from
  colour (orange 1.0, yellow 0.75, green 0.25, gray 0) and re-read colours after every skill change.
- The modern AH splits commodities and items and throttles searches; the own-scan provider in M3 must
  use the per-item search calls and wait for the throttle events, not a full-AH dump.
- Skill cap and profession list: read from the API, do not hard-code 300.
Install target: `E:\World of Warcraft\_forever_\Interface\AddOns\ProfPath`. Develop in
`F:\Claude\ProfPath` and copy the addon files there (not `tools/`, `tests/` or this plan) after each
milestone; ask the user before the first write outside `F:\Claude`. The user tests with `/reload`.
Original adapter rule, for reference:
- Modern API (`C_TradeSkillUI`, `C_AuctionHouse` exist) → adapter A.
- Legacy API (`GetNumTradeSkills`, `GetTradeSkillInfo`, `QueryAuctionItems`) → adapter B.
Check with `/dump C_TradeSkillUI ~= nil`.

## Layout
```
ProfPath/
  ProfPath.toc          SavedVariables: ProfPathDB
  Core.lua              events, slash /profpath, recalc scheduling (debounced 0.5s)
  Optimizer.lua         PURE Lua, no WoW API calls (testable offline)
  Prices.lua            price provider chain
  Recipes.lua           adapter A or B -> normalized recipe table
  Data/<Profession>.lua generated static recipe DB (only if needed, see M2)
  UI.lua                result window
  tools/build_data.py   generates Data/*.lua
  tests/optimizer_spec.lua
```

## M1 — Optimizer (pure Lua, build and test first, outside the game)
Normalized recipe:
`{id, name, yellow, gray, learned, learnCost, reagents={{itemID,qty}}, productID, productQty, skillUps=1}`
(`yellow` = skill where it stops being orange, `gray` = skill where it gives nothing.)

Inputs: `skill`, `maxSkill`, `recipes`, `price(itemID, qty)`, `sellValue(itemID)`, `owned[itemID]`.

1. Skill-up chance at skill s: `p = clamp((gray - s) / (gray - yellow), 0, 1)`; 1 while orange.
2. Material cost of one craft = Σ reagent cost, where reagent cost =
   min(AH price, vendor price, cost of crafting it via another known recipe — recursive, memoized, cycle guard).
3. Net craft cost = material cost − recovery, recovery = max(vendor sell, AH value × 0.95 × `resaleFactor`),
   `resaleFactor` default 0.5 (user option; 0 = assume products are worthless).
4. Expected cost of point s→s+1 with recipe r: `net(r) / (p × skillUps)`; infinite if p = 0 or s < required skill.
5. Path = shortest path over skill levels (DAG DP), not greedy, because unlearned recipes have a
   one-off `learnCost`. Edge (s → s2, r) = `learnCost(r if not learned) + prefix[r][s2] − prefix[r][s]`,
   each recipe used in one contiguous range. Limit s2 to r's non-gray range to keep it fast.
6. Depth pass: sum the shopping list, re-price each item for the total quantity needed
   (`price(itemID, qty)` walks the order book when available), rerun the DP once.
7. Owned materials: subtract `owned` from the shopping list; option to value them at 0 (default) or AH price.

Output: ordered steps `{recipe, fromSkill, toSkill, expectedCrafts, cost}`, shopping list, total cost,
list of items with no price (reported, never silently treated as free).

Tests (busted or plain Lua asserts): single recipe; cheaper recipe wins; learnCost flips the choice;
gray recipe never chosen; missing price excluded and reported; intermediate crafting beats buying.

## M2 — Recipe data
- Adapter A: on `TRADE_SKILL_SHOW`/`TRADE_SKILL_LIST_UPDATE` read all recipes (learned and unlearned)
  through `C_TradeSkillUI` (recipe info + schematic), cache in `ProfPathDB` per character and profession.
  Profession list and skill from `GetProfessions`/`GetProfessionInfo`.
- Adapter B: the API only exposes learned recipes, so ship a static DB. `tools/build_data.py` pulls
  DB2 CSV exports for the matching build from wago.tools (SkillLineAbility: `TrivialSkillLineRankLow`
  = yellow, `TrivialSkillLineRankHigh` = gray, `MinSkillLineRank`; SpellReagents; SpellEffect for the
  product; ItemSparse for vendor prices) and emits `Data/*.lua`. Mark learned ones from the trade skill
  window. Trainer cost / recipe-item source: use DB data if present, otherwise price the recipe item from AH.
- If "Forever" is a custom server with changed recipes, static data may be wrong: prefer live API data
  wherever both exist and log mismatches.

## M3 — Prices (provider chain, first hit wins)
1. Auctionator API (`Auctionator.API.v1.GetAuctionPriceByItemID`) if loaded.
2. TSM (`TSM_API.GetCustomPriceValue`) if loaded.
3. Own scan while the AH is open: query only the item IDs the optimizer needs, throttled to the
   client's limits, store `{minBuyout, orderBook, timestamp}` in `ProfPathDB`.
Vendor-sold reagents come from a small static list. Show price age; warn when older than 24h.
Providers 1–2 give a single price, so the depth pass only applies to own-scan data.

## M4 — UI and triggers
- `/profpath` window: profession dropdown, step list ("225→240: craft ~18× X, 41g"), shopping list
  with owned/needed/price, total cost, missing-price warnings, Recalculate button, options
  (resaleFactor, value owned mats, target skill).
- Recalc on: skill change (`SKILL_LINES_CHANGED` or modern equivalent), `BAG_UPDATE_DELAYED`,
  AH closed / new price data, option change. Run the DP in a coroutine if it exceeds ~10ms per frame.

## Done when
Tests pass offline; addon loads with no Lua errors; with the AH scanned, the window shows a path
whose step costs match a hand calculation for two spot-checked steps; changing one reagent's price
enough to flip the cheapest recipe changes the path after recalc.

## Out of scope for v1
Gathering professions, farming-vs-buying time value, cross-realm/region pricing, modern specialization
trees and first-craft/knowledge-point bonuses (add as extra `skillUps` sources later), auto-buying.
