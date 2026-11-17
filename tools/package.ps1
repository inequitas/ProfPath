# Builds an upload-ready zip for CurseForge (or sharing): dist\ProfPath-<version>.zip containing
# only ProfPath\ProfPath.toc, *.lua, Data\*.lua and Media\icon.tga. Version comes from the .toc.
# Usage (from the ProfPath folder):  powershell -ExecutionPolicy Bypass -File tools\package.ps1
$root = Split-Path $PSScriptRoot -Parent
$toc = Get-Content (Join-Path $root "ProfPath.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $matches[1].Trim() }) | Select-Object -First 1
if (-not $version) { throw "No '## Version:' line in ProfPath.toc" }

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("ProfPath-pkg-" + [guid]::NewGuid())
$dir = Join-Path $stage "ProfPath"
New-Item -ItemType Directory -Force "$dir\Data", "$dir\Media" | Out-Null
Copy-Item (Join-Path $root "ProfPath.toc"), (Join-Path $root "*.lua"), (Join-Path $root "LICENSE.txt") $dir
Copy-Item (Join-Path $root "Data\*.lua") "$dir\Data"
Copy-Item (Join-Path $root "Media\icon.tga") "$dir\Media"

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "ProfPath-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
# Write entries with forward slashes (Compress-Archive in PowerShell 5.1 uses backslashes, which
# CurseForge and non-Windows unzip tools may not handle).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
Get-ChildItem $dir -Recurse -File | ForEach-Object {
    $rel = "ProfPath/" + $_.FullName.Substring($dir.Length + 1).Replace('\', '/')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel)
}
$archive.Dispose()
Remove-Item -Recurse -Force $stage
Write-Host "built $zip"
