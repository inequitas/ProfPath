# Draws the ProfPath icon: a round dark badge with a gold rim, three rising gold steps and an
# upward arrow (the "path"). Writes Media\icon.tga (64x64, for the game) and Media\icon-256.png
# (for the CurseForge project page).
# Usage (from the ProfPath folder):  powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$media = Join-Path $root "Media"
New-Item -ItemType Directory -Force $media | Out-Null

function Draw-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = $size / 256.0
    function P([double]$v) { [single]($v * $s) }

    # badge: dark teal radial gradient
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse((P 8), (P 8), (P 240), (P 240))
    $brush = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
    $brush.CenterColor = [System.Drawing.Color]::FromArgb(255, 38, 78, 96)
    $brush.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 10, 24, 32))
    $g.FillPath($brush, $path)

    # gold rim
    $rim = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 226, 180, 70)), (P 12)
    $g.DrawEllipse($rim, (P 14), (P 14), (P 228), (P 228))

    # three rising steps
    $gold = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 246, 210, 110))
    $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 180, 130, 40))
    $steps = @(@(62, 150, 40, 42), @(108, 118, 40, 74), @(154, 86, 40, 106))
    foreach ($st in $steps) {
        $g.FillRectangle($shade, (P ($st[0] + 4)), (P ($st[1] + 4)), (P $st[2]), (P $st[3]))
        $g.FillRectangle($gold, (P $st[0]), (P $st[1]), (P $st[2]), (P $st[3]))
    }

    # arrow rising over the steps
    $arrowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 235, 248, 255)), (P 14)
    $arrowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($arrowPen, (P 58), (P 128), (P 168), (P 60))
    $head = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF((P 198), (P 42))),
        (New-Object System.Drawing.PointF((P 150), (P 46))),
        (New-Object System.Drawing.PointF((P 178), (P 86))))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 248, 255))), $head)
    $g.Dispose()
    return $bmp
}

# PNGs for the CurseForge project page
$big = Draw-Icon 256
$big.Save((Join-Path $media "icon-256.png"), [System.Drawing.Imaging.ImageFormat]::Png)
(Draw-Icon 512).Save((Join-Path $media "icon-512.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# 64x64 TGA for the game: uncompressed 32-bit BGRA, top-left origin
$small = Draw-Icon 64
$w = $small.Width; $h = $small.Height
$header = New-Object byte[] 18
$header[2] = 2                      # uncompressed true-colour
$header[12] = $w -band 0xFF; $header[13] = ($w -shr 8) -band 0xFF
$header[14] = $h -band 0xFF; $header[15] = ($h -shr 8) -band 0xFF
$header[16] = 32                    # bits per pixel
$header[17] = 0x28                  # 8 alpha bits, top-left origin
$pixels = New-Object byte[] ($w * $h * 4)
$i = 0
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $c = $small.GetPixel($x, $y)
        $pixels[$i] = $c.B; $pixels[$i + 1] = $c.G; $pixels[$i + 2] = $c.R; $pixels[$i + 3] = $c.A
        $i += 4
    }
}
$out = Join-Path $media "icon.tga"
$fs = [System.IO.File]::Create($out)
$fs.Write($header, 0, 18); $fs.Write($pixels, 0, $pixels.Length); $fs.Close()
# also a 64 PNG preview of exactly what the game shows
$small.Save((Join-Path $media "icon-64-preview.png"), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "wrote $out and icon-256.png"
