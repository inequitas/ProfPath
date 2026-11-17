# Changelog

## Unreleased

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
