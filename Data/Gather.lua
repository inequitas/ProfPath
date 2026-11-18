-- Gathered materials: which gathering profession gets them and from what skill (Classic values).
-- Used when the auction house has none: if you have the profession (and the skill), the plan has
-- you gather them yourself. Skinning values are approximate (they depend on the creature's level).
local _, ns = ...

local MINING, HERBALISM, SKINNING = "mining", "herbalism", "skinning"

ns.Gather = {
    -- skill line IDs of each gathering profession (both IDs this client uses)
    lines = { [186] = MINING, [2946] = MINING, [182] = HERBALISM, [2944] = HERBALISM,
              [393] = SKINNING, [2947] = SKINNING },
    label = { [MINING] = "Mining", [HERBALISM] = "Herbalism", [SKINNING] = "Skinning" },
    -- [itemID] = { profession, required skill }
    items = {
        -- ore
        [2770] = { MINING, 1 },     -- Copper Ore
        [2771] = { MINING, 65 },    -- Tin Ore
        [2775] = { MINING, 75 },    -- Silver Ore
        [2772] = { MINING, 125 },   -- Iron Ore
        [2776] = { MINING, 155 },   -- Gold Ore
        [3858] = { MINING, 175 },   -- Mithril Ore
        [7911] = { MINING, 230 },   -- Truesilver Ore
        [11370] = { MINING, 230 },  -- Dark Iron Ore
        [10620] = { MINING, 245 },  -- Thorium Ore
        -- herbs
        [2447] = { HERBALISM, 1 },    -- Peacebloom
        [765] = { HERBALISM, 1 },     -- Silverleaf
        [2449] = { HERBALISM, 15 },   -- Earthroot
        [785] = { HERBALISM, 50 },    -- Mageroyal
        [2450] = { HERBALISM, 70 },   -- Briarthorn
        [3820] = { HERBALISM, 85 },   -- Stranglekelp
        [2453] = { HERBALISM, 100 },  -- Bruiseweed
        [3355] = { HERBALISM, 115 },  -- Wild Steelbloom
        [3369] = { HERBALISM, 120 },  -- Grave Moss
        [3356] = { HERBALISM, 125 },  -- Kingsblood
        [3357] = { HERBALISM, 150 },  -- Liferoot
        [3818] = { HERBALISM, 160 },  -- Fadeleaf
        [3821] = { HERBALISM, 170 },  -- Goldthorn
        [3358] = { HERBALISM, 185 },  -- Khadgar's Whisker
        [3819] = { HERBALISM, 195 },  -- Wintersbite
        [4625] = { HERBALISM, 205 },  -- Firebloom
        [8831] = { HERBALISM, 210 },  -- Purple Lotus
        [8836] = { HERBALISM, 220 },  -- Arthas' Tears
        [8838] = { HERBALISM, 230 },  -- Sungrass
        [8839] = { HERBALISM, 235 },  -- Blindweed
        [8845] = { HERBALISM, 245 },  -- Ghost Mushroom
        [8846] = { HERBALISM, 250 },  -- Gromsblood
        [13464] = { HERBALISM, 260 }, -- Golden Sansam
        [13463] = { HERBALISM, 270 }, -- Dreamfoil
        [13465] = { HERBALISM, 280 }, -- Mountain Silversage
        [13466] = { HERBALISM, 285 }, -- Plaguebloom
        [13467] = { HERBALISM, 290 }, -- Icecap
        [13468] = { HERBALISM, 300 }, -- Black Lotus
        -- leather and hides (approximate)
        [2934] = { SKINNING, 1 },   -- Ruined Leather Scraps
        [2318] = { SKINNING, 1 },   -- Light Leather
        [783] = { SKINNING, 1 },    -- Light Hide
        [2319] = { SKINNING, 100 }, -- Medium Leather
        [4232] = { SKINNING, 100 }, -- Medium Hide
        [4234] = { SKINNING, 150 }, -- Heavy Leather
        [4235] = { SKINNING, 150 }, -- Heavy Hide
        [4304] = { SKINNING, 200 }, -- Thick Leather
        [8169] = { SKINNING, 200 }, -- Thick Hide
        [8170] = { SKINNING, 250 }, -- Rugged Leather
        [8171] = { SKINNING, 250 }, -- Rugged Hide
    },
    -- Mining mostly levels by mining nodes; smelting adds points along the way.
    miningRoute = {
        { 1, 65, 2770 }, { 65, 125, 2771 }, { 125, 175, 2772 }, { 175, 245, 3858 }, { 245, 300, 10620 },
    },
}
