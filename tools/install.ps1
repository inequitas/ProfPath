# Copies the addon (not tools/tests) into the WoW: Forever AddOns folder.
param([string]$Dest = "E:\World of Warcraft\_forever_\Interface\AddOns\ProfPath")
$src = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force "$Dest\Data", "$Dest\Media" | Out-Null
Copy-Item "$src\ProfPath.toc", "$src\*.lua" $Dest -Force
Copy-Item "$src\Data\*.lua" "$Dest\Data" -Force
Copy-Item "$src\Media\icon.tga" "$Dest\Media" -Force
Write-Host "installed to $Dest - type /reload in game"
