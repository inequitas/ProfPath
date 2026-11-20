-- Runs the REAL addon (every .toc file, real Data/Recipes.lua) against a saved ProfPathDB with stubbed WoW APIs,
-- and prints the plan ns.recalc produces. Run from the ProfPath folder:
--   lua tests/real_sim.lua <SavedVariables path> [profession=Leatherworking] [rank] [budgetCopper] [range] [gold]
-- Env: PP_NOLOCK=1 drops the locked plan first; PP_GATHER=off disables gathering.
local svPath, profName = arg[1], arg[2] or "Leatherworking"
local noop = function() end
local function newFrame()
    local f = { scripts = {}, shown = true }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:IsShown() return self.shown end
    function f:CreateTexture() return setmetatable({}, { __index = function() return noop end }) end
    function f:CreateFontString() return setmetatable({}, { __index = function() return noop end }) end
    return setmetatable(f, { __index = function() return noop end })
end
CreateFrame = function() return newFrame() end
Minimap = newFrame(); Minimap.GetWidth = function() return 140 end
Minimap.GetCenter = function() return 1000, 800 end
Minimap.GetEffectiveScale = function() return 1 end
GameTooltip = setmetatable({}, { __index = function() return noop end })
GetCursorPosition = function() return 1000, 900 end
UIParent, UISpecialFrames, SlashCmdList = {}, {}, {}
tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
C_Timer = { After = function(_, fn) fn() end }
GetBuildInfo = function() return "1.60.1", "70959", "Nov 17 2026", 16001 end
UnitLevel = function() return 60 end
GetCoinTextureString = function(c) return c .. "c" end
GetItemInfo = function() return nil end
C_Spell = { GetSpellName = function() return nil end }

dofile(svPath)
local DB = ProfPathDB
local key, char
for k, c in pairs(DB.chars) do if c.skill and c.skill[profName] then key, char = k, c end end
assert(key, "no saved character with " .. profName)
local sk = char.skill[profName]
local rank = tonumber(arg[3]) or sk.rank
local realm, name = key:match("^(.-)%-(.*)$") -- "Nocktoria-CAMWOW EU4 Realm 1 PvE"
UnitName = function() return realm end
GetRealmName = function() return name end
GetMoney = function() return tonumber(arg[6]) or 196100 end
local BAGS = {}
for id, n in (os.getenv("PP_BAGS") or ""):gmatch("(%d+)=(%d+)") do BAGS[tonumber(id)] = tonumber(n) end
GetItemCount = function(id) return BAGS[id] or 0 end
GetProfessions = function() return 1, 2 end
local others = {}
for n, s in pairs(char.skill) do if n ~= profName then others[#others + 1] = { n, s } end end
GetProfessionInfo = function(i)
    if i == 1 then return profName, nil, rank, sk.max, 0, 0, sk.skillLine end
    local o = others[1]
    if o and (o[1] == "Skinning" or o[1] == "Mining" or o[1] == "Herbalism") then
        return o[1], nil, o[2].rank, o[2].max, 0, 0, o[2].skillLine
    end
    for _, x in ipairs(others) do
        if x[1] == "Skinning" then return x[1], nil, x[2].rank, x[2].max, 0, 0, x[2].skillLine end
    end
    return "Cooking", nil, 1, 75, 0, 0, 185
end
C_TradeSkillUI = {}

local ns = {}
local files = {}
for line in io.lines("ProfPath.toc") do
    if not line:match("^##") and line:match("%S") then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, f in ipairs(files) do assert(loadfile(f))("ProfPath", ns) end
-- ADDON_LOADED would reset ProfPathDB defaults; apply the same ones without clobbering saved values.
local opt = DB.options
if os.getenv("PP_NOLOCK") then char.commit = {} end
if arg[4] then opt.budgetAmount = tonumber(arg[4]) end
if arg[5] then opt.range = tonumber(arg[5]) or false end
if os.getenv("PP_GATHER") == "off" then opt.gather = false end
time = function() return 1795122400 end
ns.UI.show = function() end -- headless: no rendering
char.selectedProf = profName
ns.recalc()

local st = ns.state
local function money(c) c = math.floor((c or 0) + 0.5); return ("%dg%02ds%02dc"):format(c // 10000, (c // 100) % 100, c % 100) end
print(("profession %s rank %d/%d line %s; options: budget=%s amount=%s range=%s gather=%s"):format(profName, rank, sk.max,
    tostring(sk.skillLine), tostring(opt.budget), tostring(opt.budgetAmount), tostring(opt.range), tostring(opt.gather)))
print("locked: " .. tostring(st.committed ~= nil) .. "  target: " .. tostring(st.target))
local res = st.result
if st.budget then print(("budget gold %s reach %s full %s limited %s fullCost %s"):format(money(st.budget.gold),
    tostring(st.budget.reach), tostring(st.budget.full), tostring(st.budget.limited), money(st.budget.fullCost))) end
print("ok=" .. tostring(res and res.ok))
for _, s in ipairs(res and res.steps or {}) do
    print(("  %d-%d %s x%.0f cost %s learn %s"):format(s.fromSkill, s.toSkill, s.recipe.name, s.expectedCrafts, money(s.cost), money(s.learnCost)))
end
if res and res.ok then
    print(("  cash %s + learn %s - sellBack %s = net %s"):format(money(res.cash), money(res.learnTotal), money(res.sellBack),
        money(res.cash + res.learnTotal - res.sellBack)))
end
return ns
