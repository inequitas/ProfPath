# Changelog

## v0.2.2: Settings, leftovers and a simpler Prepare tab *(2026-11-26)*

**Added**
- **Settings.** All options in one place, in plain words: `/pp settings`, the Settings button in the ProfPath window, or the game's Options → AddOns → ProfPath. Choose how to buy when gold is tight, gold to always keep, cheapest or fewest crafts, what your crafts are worth, alerts, window size and start tab, route colour and thickness, and more.
- **Make what you need from leftovers.** If the plan needs Heavy Leather and you have Medium Leather, it crafts the Heavy Leather from it. Hides you own are cured with salt from a vendor when that beats buying cured ones. Only what's already in your bags counts: it never buys one material on the auction house just to turn it into another.
- **Window conveniences:** the window remembers where you put it, and can be locked in place, opened together with your profession window, or moved back to the middle.

**Changed**
- **Simpler Prepare tab.** Gold (use my gold, set an amount, ignore gold) and how far ahead (15, 30 or 50 points, to your cap, or up to a skill you type) are now one click each, with the current choice lit.
- **Fewer technical details.** The game data build, skipped-recipe counts and calculation time only show if you turn on *Show technical details* in Settings.
- Recipe data updated for game build 1.60.1.71139: the new Leatherworking recipe Centaur Hoofwarmers; rogue poisons no longer sell to vendors.

**Fixed**
- **The minimap route is drawn in the right place** and turns with you.

## v0.2.1: Trainers, owned stock and steadier plans *(2026-11-21)*

**Fixed**
- **The right trainer for each recipe.** A "learn" step now points to the closest trainer who can teach that recipe's skill (Journeyman up to 149, Expert from 150, Artisan from 225), instead of the nearest trainer of any rank. Before, it could send you to a Journeyman who had nothing to teach you.
- **A big stock no longer makes the plan dearer.** With lots of one material in your bags, the planner could pick a route that needs far more of it than you own (Tailoring: 726 Bolts of Runecloth led to a route needing 1799, costing more than with half the bolts). It now also plans as if you owned nothing, takes your stock off that plan's shopping list, and keeps the cheapest. Owned stock now saves about what it's worth in every profession.
- **"How far ahead" works on a plan you're following.** Changing the range now re-plans to the new end point (162 + 30 → 192) instead of keeping the old one.
- **Show route works on the skinning list** (clicking it only expanded the zone).
- **Long text wraps** instead of being cut off.

**Changed**
- **Equally cheap recipes: best yield, then quickest.** When two recipes cost the same, the plan takes the one whose crafts sell for the most over their materials, then the one with the shorter craft time. Plans are now the same every session (before, a tie could go either way after a /reload).
- Also on [Wago Addons](https://addons.wago.io/addons/profpath).

## v0.2.0: Gathering routes, skinning, fishing and a smarter planner *(2026-11-21)*

**Added**
- **Gathering routes for Mining, Herbalism and Skinning.** The Plan tab suggests where to go for your skill and shows a compact, repeatable loop on the world map and minimap (Show route opens the map on that zone and sets a waypoint; Hide route removes both). Routes are planned from WoW: Forever's own node and creature locations and terrain: they stay on walkable ground, go around lakes, and keep away from enemy towns and dangerous camps. Zone choices follow the WoW: Forever leveling guides.
- **Closest zones first.** Zones are ordered by how easy they are to reach from where you are; flight paths you know count as close (ProfPath learns them when you open a flight master). The best zone is shown; the others sit under "Other viable zones". Click a zone for its details.
- **Hot spots and caves.** Mines and dense clusters near a route are drawn in yellow with it; for known caves (such as Azurelode Mine) the waypoint goes to the entrance.
- **Skinning by level.** Skinning routes pick beasts that suit your skill and your character level, and list them by name and level.
- **Fishing advice.** What to do at your skill, which lure to use, and waypoints to Old Man Heming (Expert book, Booty Bay) and Nat Pagle (Artisan quest, Dustwallow Marsh).
- **Gather it yourself.** When nobody sells a material and you have the gathering profession for it, the plan has you gather it. `/pp gather off` turns this off.
- **Crafting stations.** Steps that need an anvil, forge, cooking fire or other station say so.
- **Do it card for gathering professions:** your skill, the route you're following, and what's next.

**Fixed**
- **Owned items no longer make a whole route look free.** Items in your bags only cover the units you have. Before, a few owned Medium Leather could make Leatherworking pick an expensive route (9g instead of almost free).
- **Batches stay fixed.** In batch mode a batch keeps its size once set (learning the recipe no longer grows it), counts down as you craft, and the next one is sized when it's used up.
- **No more freezing while it recalculates.** Planning runs in small slices with a "Calculating your plan" overlay, so the game keeps running.
- **Non-English game clients.** Recipe names show in your language, and trainer costs and rank-ups are recognised in any language.

**Changed**
- Recipe data updated for game build 1.60.1.70959 (no recipe changes).

## v0.1.1: Tools, cooldowns and specializations *(2026-11-17)*

**Fixed**
- **Specialization recipes are no longer suggested without the specialization.** Recipes that need Tribal, Dragonscale or Elemental Leatherworking, Armorsmith or Weaponsmith (and the Master smith lines), or Gnomish or Goblin Engineering are left out unless you have it. Before, Leatherworking 250+ could suggest Chimeric gear you can't learn.
- **Recipes with a long cooldown are no longer leveling steps.** Transmutes, Mooncloth and similar recipes can't be crafted repeatedly, so the plan no longer counts on them (Alchemy 225+ suggested Transmute: Iron to Gold).

**Added**
- **Required tools.** Enchanting rods, the Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor and Philosopher's Stone are now known. If you don't carry the tool a recipe needs, the plan adds the cheapest way to get it (vendor, auction house or crafting it), and the Do it list tells you to get it. Higher-tier rods count for lower ones.
- **Starter recipes** that come with a profession are known before you open the profession window.

## v0.1.0: First release *(2026-11-17)*

First public release for WoW: Forever 1.60.1.

**Added**
- **Cheapest-path planning** from your realm's auction prices, counting skill-up chances, recipe costs, crafting your own intermediates, vendor reagents and what vendoring your crafts returns.
- **Auction house scans:** a full scan of the whole auction house, and an item-by-item scan that copes with the server's search limits and skips items only used by clearly overpriced recipes.
- **Prepare / Plan / Do it** window: a checklist, the plan with its costs, and a step-by-step list of what to learn, buy and craft.
- **Budget fitting:** plans as far as your gold (or a set amount) goes, in batches or bought up front.
- **Live tracking:** re-plans on every skill-up, tells you when a step is done, shows your skill-up luck, and offers a cheaper path when prices change.
- **Rank-ups and trainers:** says when you can train the next rank and points to the nearest trainer who teaches it, with a waypoint.
- **Minimap button.**
