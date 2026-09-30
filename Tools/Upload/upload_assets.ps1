# Uploads everything the game loads from Roblox with an Open Cloud API key:
#   * the voxel weapons' models  (Tools\Weapons\out\models\<key>.fbx)
#   * the weapon abilities' animations  (Tools\Animations\abilities\<key>.rbxmx)
#   * the weapons' sound effects  (Tools\Sounds\out\weapons\<name>.ogg)
#   * the Arcade's music and sounds  (Tools\Sounds\out\arcade\<name>.ogg)
#   * floors 7-10's boss sounds  (Tools\Sounds\out\bosses\<name>.ogg)
#   * the weapons' icons  (Tools\Weapons\out\icons\<key>.png, as decals)
#   * the living coin and token's pictures  (Tools\Icons\out\money\<name>.png, as decals)
# then copies ALL their ids (as ReplicatedStorage\AssetIds.lua) to your clipboard,
# to paste to Claude. Run it by double-clicking upload_assets.bat.
#
# What's been uploaded is remembered (in %LOCALAPPDATA%\Lodolouw\assets.txt, with
# a fingerprint of each file), so running it again only uploads what's new or
# changed.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Split-Path -Parent $here
$root = Split-Path -Parent $tools
$memDir = Join-Path $env:LOCALAPPDATA 'Lodolouw'
New-Item -ItemType Directory -Force -Path $memDir | Out-Null
$memFile = Join-Path $memDir 'assets.txt'

# what there is to upload
$items = @()
$models = Join-Path $tools 'Weapons\out\models'
if (Test-Path $models) {
    Get-ChildItem $models -Filter *.fbx | Sort-Object Name | ForEach-Object {
        $items += [pscustomobject]@{ Kind = 'Model'; Key = $_.BaseName; Path = $_.FullName; Type = 'model/fbx' }
    }
}
$anims = Join-Path $tools 'Animations\abilities'
if (Test-Path $anims) {
    Get-ChildItem $anims -Filter *.rbxmx | Sort-Object Name | ForEach-Object {
        $items += [pscustomobject]@{ Kind = 'Animation'; Key = $_.BaseName; Path = $_.FullName; Type = 'model/x-rbxm' }
    }
}
foreach ($folder in @('Sounds\out\weapons', 'Sounds\out\arcade', 'Sounds\out\bosses')) {
    $sounds = Join-Path $tools $folder
    if (Test-Path $sounds) {
        Get-ChildItem $sounds -Filter *.ogg | Sort-Object Name | ForEach-Object {
            $items += [pscustomobject]@{ Kind = 'Audio'; Key = $_.BaseName; Path = $_.FullName; Type = 'audio/ogg' }
        }
    }
}
foreach ($folder in @('Weapons\out\icons', 'Icons\out\money')) {
    $icons = Join-Path $tools $folder
    if (Test-Path $icons) {
        Get-ChildItem $icons -Filter *.png | Sort-Object Name | ForEach-Object {
            $items += [pscustomobject]@{ Kind = 'Decal'; Key = $_.BaseName; Path = $_.FullName; Type = 'image/png' }
        }
    }
}
if ($items.Count -eq 0) { Write-Host 'Nothing to upload (pull first?)' -ForegroundColor Red; exit }

# what's been uploaded before: "Kind:Key:fingerprint = id"
$mem = @{}
if (Test-Path $memFile) {
    foreach ($line in [IO.File]::ReadAllLines($memFile)) {
        $p = $line.Split('=')
        if ($p.Count -eq 2) { $mem[$p[0].Trim()] = $p[1].Trim() }
    }
}
foreach ($it in $items) {
    $hash = (Get-FileHash $it.Path -Algorithm SHA256).Hash.Substring(0, 16)
    $it | Add-Member -NotePropertyName Tag -NotePropertyValue ("{0}:{1}:{2}" -f $it.Kind, $it.Key, $hash)
}
$todo = @($items | Where-Object { -not $mem.ContainsKey($_.Tag) })

Write-Host ''
Write-Host ("{0} models, animations, sounds and icons here, {1} to upload." -f $items.Count, $todo.Count) -ForegroundColor Yellow
Write-Host ''
$badKey = $false
if ($todo.Count -gt 0) {
    # (the key is long - too long to paste into this window safely - so it's
    # read from the clipboard: copy it on the Roblox page, then run this)
    $key = "$(Get-Clipboard -Raw)".Trim()
    if ($key.Length -lt 40 -or $key -match '\s') {
        Write-Host 'Copy your API key first (the Copy button on the Roblox page), then press Enter.' -ForegroundColor Yellow
        Read-Host | Out-Null
        $key = "$(Get-Clipboard -Raw)".Trim()
    }
    Write-Host "Using the key from your clipboard ($($key.Length) characters)."
    $group = (Read-Host 'Is the game owned by a GROUP? (y/n)').Trim().ToLower()
    if ($group -eq 'y') {
        $creator = @{ groupId = (Read-Host 'The group ID').Trim() }
    } else {
        $creator = @{ userId = (Read-Host 'Your Roblox user ID (the number in your profile link)').Trim() }
    }
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromMinutes(3)
    $http.DefaultRequestHeaders.Add('x-api-key', $key)

    function Upload($it) {
        $request = @{
            assetType = $it.Kind
            displayName = $it.Key
            description = $(if ($it.Path -like '*\money\*') { 'Money icon' } elseif ($it.Kind -eq 'Decal') { 'Weapon icon' } elseif ($it.Path -like '*\arcade\*') { 'Arcade sound' } elseif ($it.Path -like '*\bosses\*') { 'Boss sound' } else { 'Weapon ' + $it.Kind.ToLower() })
            creationContext = @{ creator = $creator }
        } | ConvertTo-Json -Depth 5 -Compress
        $op = $null
        for ($try = 0; $try -lt 6; $try++) {
            $form = New-Object System.Net.Http.MultipartFormDataContent
            $form.Add((New-Object System.Net.Http.StringContent($request)), 'request')
            $file = New-Object System.Net.Http.ByteArrayContent(, [IO.File]::ReadAllBytes($it.Path))
            $file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($it.Type)
            $form.Add($file, 'fileContent', [IO.Path]::GetFileName($it.Path))
            $res = $http.PostAsync('https://apis.roblox.com/assets/v1/assets', $form).Result
            $body = $res.Content.ReadAsStringAsync().Result
            if ([int]$res.StatusCode -eq 429) { Start-Sleep -Seconds ([math]::Pow(2, $try + 1)); continue }
            if ([int]$res.StatusCode -eq 401) { $script:badKey = $true; throw "Roblox says the key is wrong ($body)" }
            if (-not $res.IsSuccessStatusCode) { throw "Roblox said $([int]$res.StatusCode): $body" }
            $op = $body | ConvertFrom-Json
            break
        }
        if (-not $op) { throw 'Roblox kept saying "too many" - wait a minute and run it again' }
        for ($i = 0; $i -lt 60; $i++) {
            if ($op.done -and $op.response) { return $op.response.assetId }
            if ($op.done -and $op.error) { throw "Roblox refused it: $($op.error.message)" }
            Start-Sleep -Seconds 2
            $opId = if ($op.operationId) { $op.operationId } else { ($op.path -split '/')[-1] }
            $r = $http.GetAsync("https://apis.roblox.com/assets/v1/operations/$opId").Result
            $op = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        }
        throw 'Roblox took too long to finish it (run this again later)'
    }

    $n = 0
    foreach ($it in $todo) {
        $n++
        try {
            $id = Upload $it
            $mem[$it.Tag] = "$id"
            try { [IO.File]::AppendAllText($memFile, "$($it.Tag) = $id`r`n") } catch { }
            Write-Host ("  {0}/{1}  {2} {3} -> {4}" -f $n, $todo.Count, $it.Kind, $it.Key, $id) -ForegroundColor Green
        } catch {
            Write-Host ("  {0}/{1}  {2} {3} FAILED: {4}" -f $n, $todo.Count, $it.Kind, $it.Key, $_.Exception.Message) -ForegroundColor Red
            if ($script:badKey) { break }
        }
    }
    if ($script:badKey) {
        Write-Host ''
        Write-Host 'Stopped: Roblox did not accept the key. Check it has Assets with Read and Write,' -ForegroundColor Red
        Write-Host '0.0.0.0/0 under Accepted IP Addresses, and is Enabled. Then run this again.' -ForegroundColor Red
    }
}

# every id we have for what's here now, as ReplicatedStorage\AssetIds.lua
$lines = @('return {', "`tModels = {")
foreach ($it in ($items | Where-Object { $_.Kind -eq 'Model' })) {
    if ($mem.ContainsKey($it.Tag)) { $lines += ("`t`t{0} = {1}," -f $it.Key, $mem[$it.Tag]) }
}
$lines += "`t},"
$lines += "`tAnimations = {"
foreach ($it in ($items | Where-Object { $_.Kind -eq 'Animation' })) {
    if ($mem.ContainsKey($it.Tag)) { $lines += ("`t`t{0} = {1}," -f $it.Key, $mem[$it.Tag]) }
}
$lines += "`t},"
$lines += "`tSounds = {"
foreach ($it in ($items | Where-Object { $_.Kind -eq 'Audio' })) {
    if ($mem.ContainsKey($it.Tag)) { $lines += ("`t`t{0} = {1}," -f $it.Key, $mem[$it.Tag]) }
}
$lines += "`t},"
$lines += "`tIcons = {"
foreach ($it in ($items | Where-Object { $_.Kind -eq 'Decal' })) {
    if ($mem.ContainsKey($it.Tag)) { $lines += ("`t`t{0} = {1}," -f $it.Key, $mem[$it.Tag]) }
}
$lines += "`t},"
$lines += '}'
$text = ($lines -join "`r`n")
$have = @($items | Where-Object { $mem.ContainsKey($_.Tag) }).Count
Write-Host ''
Write-Host $text
Write-Host ''
try {
    Set-Clipboard -Value $text
    Write-Host ("Done: {0} of {1} have ids. They're copied - paste them to Claude (Ctrl+V)." -f $have, $items.Count) -ForegroundColor Yellow
} catch {
    Write-Host ("Done: {0} of {1} have ids. Copy the text above and paste it to Claude." -f $have, $items.Count) -ForegroundColor Yellow
}
