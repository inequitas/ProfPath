# Tiny local server for previews / route review. Usage: powershell -File tools\serve.ps1 <rootFolder> <port>
# Static files from <root>; /data/towns.csv from <root>\..\data\towns.csv; GET/POST /notes -> <root>\notes.json
param([string]$Root = ".", [int]$Port = 8765)
$Root = [System.IO.Path]::GetFullPath($Root)
$types = @{ '.html'='text/html; charset=utf-8'; '.json'='application/json; charset=utf-8'; '.csv'='text/csv; charset=utf-8';
            '.js'='application/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8'; '.txt'='text/plain; charset=utf-8';
            '.png'='image/png'; '.jpg'='image/jpeg'; '.svg'='image/svg+xml' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$notesFile = Join-Path $Root 'notes.json'

function Send($ctx, [int]$code, [string]$ctype, [byte[]]$bytes) {
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $ctype
    $ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}
function SendText($ctx, [int]$code, [string]$ctype, [string]$text) { Send $ctx $code $ctype ($utf8.GetBytes($text)) }

$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://localhost:$Port/")
$l.Start()
Write-Host "Serving $Root on http://localhost:$Port/"
while ($l.IsListening) {
    $ctx = $l.GetContext()
    try {
        $req = $ctx.Request
        $urlPath = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
        if ($urlPath -eq '/notes') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, $utf8)
                $body = $sr.ReadToEnd(); $sr.Close()
                $n = $body | ConvertFrom-Json
                if (-not $n.id) { SendText $ctx 400 'application/json' '{"ok":false,"error":"missing id"}' }
                else {
                    $all = $null
                    if (Test-Path $notesFile -PathType Leaf) {
                        $raw = [System.IO.File]::ReadAllText($notesFile, $utf8)
                        if ($raw.Trim()) { $all = $raw | ConvertFrom-Json }
                    }
                    if (-not $all) { $all = New-Object PSObject }
                    $dr = @(); if ($null -ne $n.drawn) { $dr = @($n.drawn) }
                    $ck = @(); if ($null -ne $n.checks) { foreach ($c in @($n.checks)) { if ($null -ne $c) { $ck += [pscustomobject]@{ x = $c.x; y = $c.y; note = [string]$c.note } } } }
                    $entry = [pscustomobject]@{ id = [string]$n.id; tags = @($n.tags); text = [string]$n.text; drawn = $dr; checks = $ck; updated = $n.updated }
                    $all | Add-Member -NotePropertyName ([string]$n.id) -NotePropertyValue $entry -Force
                    $json = ConvertTo-Json -InputObject $all -Depth 6
                    [System.IO.File]::WriteAllText($notesFile, $json, $utf8)
                    SendText $ctx 200 'application/json' '{"ok":true}'
                }
            } else {
                $txt = '{}'
                if (Test-Path $notesFile -PathType Leaf) {
                    $t = [System.IO.File]::ReadAllText($notesFile, $utf8)
                    if ($t.Trim()) { $txt = $t }
                }
                SendText $ctx 200 'application/json; charset=utf-8' $txt
            }
        } elseif ($urlPath -eq '/avoid') {
            $avoidFile = [System.IO.Path]::GetFullPath((Join-Path $Root '..\data\route-avoid.json'))
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, $utf8)
                $body = $sr.ReadToEnd(); $sr.Close()
                $n = $body | ConvertFrom-Json
                if ($null -eq $n.map) { SendText $ctx 400 'application/json' '{"ok":false,"error":"missing map"}' }
                else {
                    $all = $null
                    if (Test-Path $avoidFile -PathType Leaf) {
                        $raw = [System.IO.File]::ReadAllText($avoidFile, $utf8)
                        if ($raw.Trim()) { $all = $raw | ConvertFrom-Json }
                    }
                    if (-not $all) { $all = New-Object PSObject }
                    $list = @()
                    foreach ($c in @($n.circles)) {
                        if ($null -eq $c) { continue }
                        $list += [pscustomobject]@{ x = [math]::Round([double]$c.x, 1); y = [math]::Round([double]$c.y, 1); r = [int][math]::Round([double]$c.r); note = [string]$c.note }
                    }
                    $all | Add-Member -NotePropertyName ([string]$n.map) -NotePropertyValue $list -Force
                    $json = ConvertTo-Json -InputObject $all -Depth 6
                    [System.IO.File]::WriteAllText($avoidFile, $json, $utf8)
                    SendText $ctx 200 'application/json' '{"ok":true}'
                }
            } else {
                $txt = '{}'
                if (Test-Path $avoidFile -PathType Leaf) {
                    $t = [System.IO.File]::ReadAllText($avoidFile, $utf8)
                    if ($t.Trim()) { $txt = $t }
                }
                SendText $ctx 200 'application/json; charset=utf-8' $txt
            }
        } else {
            if ($urlPath -eq '/data/towns.csv') { $path = [System.IO.Path]::GetFullPath((Join-Path $Root '..\data\towns.csv')) }
            else {
                $rel = $urlPath.TrimStart('/')
                if ($rel -eq '') { $rel = 'index.html' }
                $path = [System.IO.Path]::GetFullPath((Join-Path $Root $rel))
                if (-not $path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) { $path = $null }
            }
            if ($path -and (Test-Path $path -PathType Leaf)) {
                $ext = [System.IO.Path]::GetExtension($path).ToLower()
                $ct = $types[$ext]; if (-not $ct) { $ct = 'application/octet-stream' }
                Send $ctx 200 $ct ([System.IO.File]::ReadAllBytes($path))
            } else { SendText $ctx 404 'text/plain' 'not found' }
        }
    } catch {
        try { SendText $ctx 500 'application/json' ('{"ok":false,"error":' + (ConvertTo-Json ([string]$_.Exception.Message)) + '}') } catch {}
    } finally {
        try { $ctx.Response.Close() } catch {}
    }
}
