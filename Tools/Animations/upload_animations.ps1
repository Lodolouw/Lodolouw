# Uploads every animation in upload\ with a Roblox API key (Open Cloud), then
# writes the IDs straight into ReplicatedStorage\Config.lua (Rojo syncs it to
# Studio). Run it by double-clicking upload_animations.bat.
#
# Finished uploads are remembered in upload\ids.txt, so running it again only
# does the ones that are missing (no duplicates).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = Join-Path $here 'upload'
$config = Join-Path $here '..\..\ReplicatedStorage\Config.lua'
$idsFile = Join-Path $dir 'ids.txt'

Write-Host ''
Write-Host 'Uploads the weapon animations and puts their IDs in Config.' -ForegroundColor Yellow
Write-Host ''
$key = (Read-Host 'Paste your Open Cloud API key').Trim()
$group = (Read-Host 'Is the game owned by a GROUP? (y/n)').Trim().ToLower()
if ($group -eq 'y') {
    $gid = (Read-Host 'The group ID').Trim()
    $creator = @{ groupId = $gid }
} else {
    $uid = (Read-Host 'Your Roblox user ID (the number in your profile link)').Trim()
    $creator = @{ userId = $uid }
}

$ids = [ordered]@{}
if (Test-Path $idsFile) {
    foreach ($line in [IO.File]::ReadAllLines($idsFile)) {
        $p = $line.Split('=')
        if ($p.Count -eq 2) { $ids[$p[0].Trim()] = $p[1].Trim() }
    }
}

$http = New-Object System.Net.Http.HttpClient
$http.DefaultRequestHeaders.Add('x-api-key', $key)

function Upload($name) {
    $path = Join-Path $dir "$name.rbxmx"
    $request = @{
        assetType = 'Animation'
        displayName = $name
        description = 'Weapon animation'
        creationContext = @{ creator = $creator }
    } | ConvertTo-Json -Depth 5 -Compress
    for ($try = 0; $try -lt 6; $try++) {
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent($request)), 'request')
        $file = New-Object System.Net.Http.ByteArrayContent(, [IO.File]::ReadAllBytes($path))
        $file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('model/x-rbxm')
        $form.Add($file, 'fileContent', "$name.rbxmx")
        $res = $http.PostAsync('https://apis.roblox.com/assets/v1/assets', $form).Result
        $body = $res.Content.ReadAsStringAsync().Result
        if ([int]$res.StatusCode -eq 429) { Start-Sleep -Seconds ([math]::Pow(2, $try)); continue }
        if (-not $res.IsSuccessStatusCode) { throw "Roblox said $([int]$res.StatusCode): $body" }
        $op = $body | ConvertFrom-Json
        break
    }
    # the upload finishes in the background: ask until it's done
    for ($i = 0; $i -lt 15; $i++) {
        if ($op.done -and $op.response) { return $op.response.assetId }
        Start-Sleep -Seconds 2
        $opId = if ($op.operationId) { $op.operationId } else { ($op.path -split '/')[-1] }
        $r = $http.GetAsync("https://apis.roblox.com/assets/v1/operations/$opId").Result
        $op = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    }
    throw 'Roblox took too long to finish the upload (run it again)'
}

$order = [IO.File]::ReadAllLines((Join-Path $dir 'order.txt')) | Where-Object { $_.Trim() }
$failed = 0
foreach ($line in $order) {
    $names = $line.Split(' ') | Select-Object -Skip 1
    foreach ($name in $names) {
        if ($ids.Contains($name)) { Write-Host "  $name already uploaded ($($ids[$name]))" -ForegroundColor DarkGray; continue }
        try {
            $id = Upload $name
            $ids[$name] = $id
            [IO.File]::AppendAllText($idsFile, "$name = $id`r`n")
            Write-Host "  $name -> $id" -ForegroundColor Green
        } catch {
            $failed++
            Write-Host "  $name FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# into Config: each type's  Animations = { Idle = "...", Swings = { ... } }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [IO.File]::ReadAllText($config, $utf8)
foreach ($line in $order) {
    $parts = $line.Split(' ')
    $kind, $idle, $swings = $parts[0], $parts[1], ($parts | Select-Object -Skip 2)
    if (-not $ids.Contains($idle) -or ($swings | Where-Object { -not $ids.Contains($_) })) { continue }
    $list = ($swings | ForEach-Object { '"rbxassetid://' + $ids[$_] + '"' }) -join ', '
    $new = 'Animations = { Idle = "rbxassetid://' + $ids[$idle] + '", Swings = { ' + $list + ' } }'
    $pattern = '(?s)(\t\t' + $kind + ' = \{.*?)Animations = \{ Idle = "[^"]*", Swings = \{[^}]*\} \}'
    $text = [regex]::new($pattern).Replace($text, { param($m) $m.Groups[1].Value + $new }, 1)
    Write-Host "  Config: $kind done" -ForegroundColor Cyan
}
[IO.File]::WriteAllText($config, $text, $utf8)

Write-Host ''
if ($failed -gt 0) { Write-Host "$failed failed - fix what it says and run it again (the rest are kept)." -ForegroundColor Red }
else { Write-Host 'All done. Copy these lines to Claude:' -ForegroundColor Yellow }
foreach ($k in $ids.Keys) { Write-Host "$k = $($ids[$k])" }
