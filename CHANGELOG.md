# Changelog

## v0.2.0: Gathering, crafting stations and other languages *(unreleased)*

**Added**
- **Gather it yourself.** When nobody sells a material on the auction house and you have the gathering profession for it (Mining, Herbalism or Skinning, with enough skill), the plan has you gather it instead of giving up. It counts at its vendor price and costs no gold; the Do it list says "Gather" instead of "Buy". Turn it off with `/pp gather off`.
- **Mining, Herbalism, Skinning and Fishing.** These level by gathering, which no shopping list can cover. Instead of "Not enough gold", the Plan and Do it tabs now say there is nothing to buy and what to gather at your skill: the ore route for Mining (Copper, Tin, Iron, Mithril, Thorium), the best herbs for you and the next ones you unlock for Herbalism, the highest creature level you can skin for Skinning, and tips for Fishing. Smelting steps use ore you mine yourself when the auction house has none.
- **Gathering routes.** For Mining and Herbalism, the Plan tab lists the best zones for your skill and faction (Wowhead's Forever guide picks first, then the zones with the most nodes you can use) with a **Show route** button. It draws a loop on the world map and the minimap that passes within 120 yards of every node it covers, close enough for Find Minerals or Find Herbs to show them, and sets a waypoint to the nearest point of the loop. Skinning and Fishing get the zone lists. Routes are planned ahead from Wowhead's WoW: Forever node locations and only step between nearby nodes, so they don't cut across mountains. `/pp route off` hides the route; `/pp route test` shows one without the profession.
- **Crafting stations.** Steps that need an anvil, forge, cooking fire, loom, tanning rack or other station say so, in the plan and on the Do it craft card.

**Fixed**
- **Non-English game clients.** Recipe names now show in your game's language, trainer recipe costs are matched in any language, and Expert and Artisan rank-ups are recognized at trainers in any language.

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
