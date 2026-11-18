# Generates Data\Recipes.lua from wago.tools DB2 exports for one WoW: Forever build.
# Usage (from the ProfPath folder):  powershell -ExecutionPolicy Bypass -File tools\build_data.ps1
# Optional:  -Build 1.60.1.70959   -Refresh (re-download cached tables)
param(
    [string]$Build = "1.60.1.70959",
    [switch]$Refresh,
    [string]$CacheDir,
    [string]$OutFile
)
$ErrorActionPreference = "Stop"
$root  = Split-Path $PSScriptRoot -Parent
$cache = if ($CacheDir) { $CacheDir } else { Join-Path $PSScriptRoot ".cache\$Build" }
$out   = if ($OutFile) { $OutFile } else { Join-Path $root "Data\Recipes.lua" }
New-Item -ItemType Directory -Force $cache, (Split-Path $out) | Out-Null

function Get-Table([string]$name, [string[]]$required) {
    $file = Join-Path $cache "$name.csv"
    if ($Refresh -or -not (Test-Path $file)) {
        $url = "https://wago.tools/db2/$name/csv?build=$Build"
        Write-Host "download $url"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file -UserAgent "ProfPath-data-builder/0.1"
    }
    $rows = @(Import-Csv $file)
    if ($rows.Count -eq 0) { throw "$name is empty" }
    $cols = $rows[0].PSObject.Properties.Name
    $missing = $required | Where-Object { $cols -notcontains $_ }
    if ($missing) { throw "$name lacks columns: $($missing -join ', '). Has: $($cols -join ', ')" }
    Write-Host ("{0,-18} {1,7} rows" -f $name, $rows.Count)
    return $rows
}

$skillLine = Get-Table SkillLine        @("ID", "DisplayName_lang", "CategoryID")
$sla       = Get-Table SkillLineAbility @("Spell", "SkillLine", "MinSkillLineRank", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh", "AcquireMethod")
$reag      = Get-Table SpellReagents    @("SpellID", "Reagent_0", "ReagentCount_0")
$effect    = Get-Table SpellEffect      @("SpellID", "Effect", "EffectItemType", "EffectBasePointsF", "EffectTriggerSpell")
$names     = Get-Table SpellName        @("ID", "Name_lang")
$items     = Get-Table ItemSparse       @("ID", "BuyPrice", "SellPrice", "VendorStackCount", "RequiredSkillRank", "RequiredAbility", "TotemCategoryID")
$itemEff   = Get-Table ItemEffect       @("ID", "SpellID", "TriggerType")
$itemXEff  = Get-Table ItemXItemEffect  @("ItemID", "ItemEffectID")
$totems    = Get-Table SpellTotems      @("SpellID", "RequiredTotemCategoryID_0", "RequiredTotemCategoryID_1")
$totemCat  = Get-Table TotemCategory    @("ID", "Name_lang", "TotemCategoryType", "TotemCategoryMask")
$cooldowns = Get-Table SpellCooldowns   @("SpellID", "RecoveryTime", "CategoryRecoveryTime")

# Profession skill lines: category 11 = primary professions, 9 = secondary (cooking, first aid, fishing).
$profs = @{}
foreach ($s in $skillLine) {
    if ($s.CategoryID -eq "11" -or $s.CategoryID -eq "9") { $profs[$s.ID] = $s.DisplayName_lang }
}

$spellName = @{}
foreach ($n in $names) { $spellName[$n.ID] = $n.Name_lang }

$reagents = @{}
foreach ($r in $reag) {
    $list = @()
    for ($i = 0; $i -le 7; $i++) {
        $id = $r."Reagent_$i"; $qty = $r."ReagentCount_$i"
        if ($id -and $id -ne "0" -and $qty -and $qty -ne "0") { $list += "$id,$qty" }
    }
    if ($list.Count) { $reagents[$r.SpellID] = $list -join "," }
}

$product = @{}; $teaches = @{}
foreach ($e in $effect) {
    if ($e.Effect -eq "24" -and $e.EffectItemType -ne "0") {          # CREATE_ITEM
        $qty = [math]::Max(1, [int][math]::Round([double]$e.EffectBasePointsF))
        $product[$e.SpellID] = "$($e.EffectItemType),$qty"
    } elseif ($e.Effect -eq "36" -and $e.EffectTriggerSpell -ne "0") { # LEARN_SPELL
        $teaches[$e.SpellID] = $e.EffectTriggerSpell
    }
}

# Recipe items: an ItemEffect with TriggerType 6 (learn) names the recipe spell directly.
# Older data uses an on-use spell whose LEARN_SPELL effect names it; both are handled.
$effSpell = @{}; $effLearn = @{}
foreach ($ie in $itemEff) {
    if ($ie.TriggerType -eq "6") { $effLearn[$ie.ID] = $ie.SpellID } else { $effSpell[$ie.ID] = $ie.SpellID }
}
$recipeItem = @{}
foreach ($x in $itemXEff) {
    $taught = $effLearn[$x.ItemEffectID]
    if (-not $taught) { $sp = $effSpell[$x.ItemEffectID]; if ($sp) { $taught = $teaches[$sp] } }
    if ($taught -and -not $recipeItem.ContainsKey($taught)) { $recipeItem[$taught] = $x.ItemID }
}
$itemReq = @{}; $itemAbility = @{}; $itemTotem = @{}
foreach ($it in $items) {
    if ($it.RequiredSkillRank -and $it.RequiredSkillRank -ne "0") { $itemReq[$it.ID] = $it.RequiredSkillRank }
    # A recipe item that needs a spell (e.g. Tribal Leatherworking, Armorsmith) is for that specialization.
    if ($it.RequiredAbility -and $it.RequiredAbility -ne "0") { $itemAbility[$it.ID] = $it.RequiredAbility }
    if ($it.TotemCategoryID -and $it.TotemCategoryID -ne "0") { $itemTotem[$it.ID] = $it.TotemCategoryID }
}

# Tools: a recipe can require tool categories (Blacksmith Hammer, Runed Copper Rod...). An item of
# category C satisfies required category R when both have the same type and C's mask covers R's
# (so a Runed Arcanite Rod also counts as a Runed Copper Rod).
$cat = @{}
foreach ($t in $totemCat) { $cat[$t.ID] = $t }
$spellTools = @{}
foreach ($t in $totems) {
    $list = @($t.RequiredTotemCategoryID_0, $t.RequiredTotemCategoryID_1 | Where-Object { $_ -and $_ -ne "0" })
    if ($list.Count) { $spellTools[$t.SpellID] = $list }
}
function Get-ToolItems([string]$reqCat) {
    $r = $cat[$reqCat]
    if (-not $r) { return @() }
    $mask = [int64]$r.TotemCategoryMask
    $out = @()
    foreach ($id in $itemTotem.Keys) {
        $c = $cat[$itemTotem[$id]]
        if ($c -and $c.TotemCategoryType -eq $r.TotemCategoryType -and (([int64]$c.TotemCategoryMask -band $mask) -eq $mask)) { $out += $id }
    }
    return $out
}

# Cooldowns of 10 minutes or more (transmutes, Mooncloth...): not usable for leveling.
$spellCooldown = @{}
foreach ($c in $cooldowns) {
    $ms = [math]::Max([int64]$c.RecoveryTime, [int64]$c.CategoryRecoveryTime)
    if ($ms -ge 600000) { $spellCooldown[$c.SpellID] = [int]($ms / 1000) }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- Generated by tools/build_data.ps1 from wago.tools DB2, build $Build. Do not edit.")
[void]$sb.AppendLine("local _, ns = ...")
[void]$sb.AppendLine("ns.Data = { build = `"$Build`", skillLines = {}, recipes = {}, recipeItems = {}, items = {},")
[void]$sb.AppendLine("    tools = {}, toolNames = {}, toolItems = {}, cooldown = {}, autoLearn = {} }")
[void]$sb.AppendLine("local D = ns.Data")
foreach ($id in ($profs.Keys | Sort-Object { [int]$_ })) {
    [void]$sb.AppendLine("D.skillLines[$id] = `"$($profs[$id] -replace '"', '\"')`"")
}

# recipes[spellID] = { skillLine, minSkill, yellow, gray, productID, productQty, {item,qty,...}, "name" }
$used = @{}; $count = 0; $neededCats = @{}
[void]$sb.AppendLine("local R = D.recipes")
foreach ($a in $sla) {
    if (-not $profs.ContainsKey($a.SkillLine)) { continue }
    $gray = [int]$a.TrivialSkillLineRankHigh
    if ($gray -le 0 -or -not $reagents.ContainsKey($a.Spell)) { continue }
    $p = $product[$a.Spell]; if (-not $p) { $p = "nil,nil" }
    $nm = ($spellName[$a.Spell] -replace '"', '\"')
    [void]$sb.AppendLine("R[$($a.Spell)]={$($a.SkillLine),$($a.MinSkillLineRank),$($a.TrivialSkillLineRankLow),$gray,$p,{$($reagents[$a.Spell])},`"$nm`"}")
    $toks = $reagents[$a.Spell] -split ","
    for ($k = 0; $k -lt $toks.Count; $k += 2) { $used[$toks[$k]] = $true }
    if ($product[$a.Spell]) { $used[($product[$a.Spell] -split ",")[0]] = $true }
    # recipeItems[spellID] = { itemID, requiredSkill, requiredSpell (specialization) or 0 }
    $ri = $recipeItem[$a.Spell]
    if ($ri) {
        $req = $itemReq[$ri]; if (-not $req) { $req = 0 }
        $ab = $itemAbility[$ri]; if (-not $ab) { $ab = 0 }
        [void]$sb.AppendLine("D.recipeItems[$($a.Spell)]={$ri,$req,$ab}")
        $used[$ri] = $true
    }
    # tools[spellID] = { toolCategory, ... }
    if ($spellTools[$a.Spell]) {
        [void]$sb.AppendLine("D.tools[$($a.Spell)]={$($spellTools[$a.Spell] -join ',')}")
        foreach ($c in $spellTools[$a.Spell]) { $neededCats[$c] = $true }
    }
    if ($spellCooldown[$a.Spell]) { [void]$sb.AppendLine("D.cooldown[$($a.Spell)]=$($spellCooldown[$a.Spell])") }
    # learned automatically together with the profession
    if ($a.AcquireMethod -eq "1") { [void]$sb.AppendLine("D.autoLearn[$($a.Spell)]=true") }
    $count++
}

# Tool names and the items that satisfy each needed tool category.
foreach ($c in $neededCats.Keys) {
    $nm = if ($cat[$c]) { $cat[$c].Name_lang -replace '"', '\"' } else { "Tool $c" }
    [void]$sb.AppendLine("D.toolNames[$c]=`"$nm`"")
    $ti = Get-ToolItems $c
    if ($ti.Count) {
        [void]$sb.AppendLine("D.toolItems[$c]={$($ti -join ',')}")
        foreach ($i in $ti) { $used[$i] = $true }
    }
}

# items[itemID] = { buyPricePerUnit, sellPrice }. BuyPrice exists for many items no vendor sells;
# Prices.lua only trusts it for items seen at a merchant or in the vendor list.
[void]$sb.AppendLine("local I = D.items")
foreach ($it in $items) {
    if (-not $used.ContainsKey($it.ID)) { continue }
    $stack = [math]::Max(1, [int]$it.VendorStackCount)
    $buy = [math]::Floor([double]$it.BuyPrice / $stack)
    [void]$sb.AppendLine("I[$($it.ID)]={$buy,$($it.SellPrice)}")
}

if ($count -eq 0) { throw "No recipes matched. Check SkillLine CategoryID values for this build: $(($skillLine | Group-Object CategoryID | ForEach-Object { $_.Name }) -join ', ')" }
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
$riCount = @($recipeItem.Keys | Where-Object { $reagents.ContainsKey($_) }).Count
Write-Host "wrote $out : $count recipes, $riCount recipe items, $($profs.Count) skill lines, $($used.Count) items"
