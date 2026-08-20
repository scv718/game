<#
.SYNOPSIS
    Downloads the "Tiny Swords (Free Pack)" from itch.io into assets/tiny_swords/ and
    generates the cropped grass tile used by the game's floor TileMapLayer.

.DESCRIPTION
    Assets are licensed for free use by Pixel Frog ("Tiny Swords") and must NOT be
    redistributed. This script only fetches them into the local, git-ignored
    assets/tiny_swords/ folder (see .gitignore) and reproduces the generated file
    assets/tiny_swords/generated/grass_tile.png referenced by scenes/world.tscn.

    Flow (itches the public web flow):
      1. GET  {base}/purchase                     -> csrf token
      2. POST {base}/download_url   {csrf_token}  -> download page url
      3. GET  download page                       -> free pack upload id
      4. POST {base}/file/<id>?source=game_download {csrf_token} -> signed zip url
      5. Download + extract zip (skips __MACOSX / .DS_Store)
      6. Crop grass tile (7,14) from Tilemap_color1.png -> generated/grass_tile.png
      7. Save license / attribution note locally.
#>
param(
    [string]$BaseUrl = "https://pixelfrog-assets.itch.io/tiny-swords",
    [string]$TargetDir = "$PSScriptRoot\..\assets\tiny_swords"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-CsrfToken([string]$Html) {
    $m = [regex]::Match($Html, '<meta\s+name="csrf_token"\s+content="([^"]+)"')
    if (-not $m.Success) {
        $m = [regex]::Match($Html, '<meta\s+name="csrf_token"\s+value="([^"]+)"')
    }
    if (-not $m.Success) { throw "Could not find csrf_token in purchase page." }
    return $m.Groups[1].Value
}

function Get-DownloadPageUrl {
    param($Session, [string]$Token)
    $resp = Invoke-RestMethod -WebSession $Session -Method Post -Body @{ csrf_token = $Token } "$BaseUrl/download_url"
    if (-not $resp.url) { throw "download_url response had no 'url'." }
    return $resp.url
}

function Find-FreePackUploadId {
    param($Session, [string]$PageUrl)
    $page = Invoke-WebRequest -WebSession $Session -Uri $PageUrl -UseBasicParsing
    $m = [regex]::Match($page.Content, 'data-upload_id="(\d+)"(?:(?!data-upload_id).)*?Tiny\s+Swords\s+\(Free\s+Pack\)')
    if (-not $m.Success) {
        $m = [regex]::Match($page.Content, 'Tiny\s+Swords\s+\(Free\s+Pack\)(?:(?!Tiny\s+Swords).)*?data-upload_id="(\d+)"')
    }
    if (-not $m.Success) { throw "Could not locate the 'Tiny Swords (Free Pack)' upload on the download page." }
    return $m.Groups[1].Value
}

function Get-SignedZipUrl {
    param($Session, [string]$Token, [string]$UploadId)
    $resp = Invoke-RestMethod -WebSession $Session -Method Post -Body @{ csrf_token = $Token } "$BaseUrl/file/$UploadId`?source=game_download"
    if (-not $resp.url) { throw "file response had no 'url'." }
    return $resp.url
}

$TargetDir = [System.IO.Path]::GetFullPath($TargetDir)
$Root = Split-Path -Parent $TargetDir
if (-not (Test-Path -LiteralPath $Root)) { throw "Parent '$Root' does not exist." }
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

Write-Host "Fetching free-pack download links from $BaseUrl ..."
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$purchase = Invoke-WebRequest -WebSession $session -Uri "$BaseUrl/purchase" -UseBasicParsing
$csrf = Get-CsrfToken $purchase.Content
$dlPage = Get-DownloadPageUrl -Session $session -Token $csrf
$uploadId = Find-FreePackUploadId -Session $session -PageUrl $dlPage
$zipUrl = Get-SignedZipUrl -Session $session -Token $csrf -UploadId $uploadId

$zipPath = Join-Path $env:TEMP "tiny_swords_free.zip"
Write-Host "Downloading zip from signed URL ($($zipUrl.Length) chars) ..."
Invoke-WebRequest -WebSession $session -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
Write-Host "Extracting to $TargetDir ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
Get-ChildItem -LiteralPath $TargetDir -Force | Remove-Item -Recurse -Force
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $TargetDir)

Get-ChildItem -LiteralPath $TargetDir -Recurse -Force | Where-Object {
    $_.Name -eq ".DS_Store" -or $_.FullName -match "__MACOSX"
} | Remove-Item -Recurse -Force

$genDir = Join-Path $TargetDir "generated"
New-Item -ItemType Directory -Path $genDir -Force | Out-Null

Add-Type -AssemblyName System.Drawing
$sheet = [System.Drawing.Bitmap]::FromFile((Get-ChildItem -LiteralPath $TargetDir -Recurse -Filter "Tilemap_color1.png" | Select-Object -First 1).FullName)
try {
    $tile = New-Object System.Drawing.Bitmap 16, 16, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($tile)
    try {
        $g.DrawImage($sheet, (New-Object System.Drawing.Rectangle 0, 0, 16, 16),
            (New-Object System.Drawing.Rectangle 112, 224, 16, 16),
            [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $g.Dispose() }
    $out = Join-Path $genDir "grass_tile.png"
    $tile.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Wrote grass tile: $out"
} finally { $tile.Dispose(); $sheet.Dispose() }

$license = @"
Tiny Swords (Free Pack)
by Pixel Frog
Source: $BaseUrl

License / usage: free for use in your projects, with attribution requested by the
author. See the itch.io page above for the exact license text and attribution
requirements. Do not redistribute the raw pack assets.

This copy is a local development asset and is intentionally excluded from the
game repository (.gitignore). The only file this project references directly is
generated/grass_tile.png (a 16x16 crop of Tilemap_color1.png).
"@
Set-Content -Path (Join-Path $TargetDir "LICENSE-NOTE.txt") -Value $license -Encoding UTF8

Write-Host "Done. Tiny Swords assets ready at $TargetDir"