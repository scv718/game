<#
.SYNOPSIS
    TASK-3D-VIS-001-1: Downloads the 7 core Quaternius packs (official itch.io
    distribution), extracts the originals into a Godot-invisible _source/ folder
    and copies only the curated runtime subset into assets/third_party/quaternius/models/.

.DESCRIPTION
    All packs are CC0 (see quaternius.com pack pages) so the curated copy is
    redistributable and is committed. The full original archives stay in
    _source/, which is both .gdignore'd (Godot never imports it) and git-ignored.

    Flow (per pack, mirrors tools/download_tiny_swords.ps1):
      1. GET  {base}[/purchase]                  -> csrf token (NYOP packs need /purchase)
      2. POST {base}/download_url {csrf_token}   -> download page url
      3. GET  download page                      -> upload id(s)
      4. POST {base}/file/<id> {csrf_token}      -> signed zip url
      5. Download zip into _source/zips/ (skipped when already present)
      6. Extract into _source/extracted/<pack>/
      7. Copy curated glTF/GLB models (+ .bin and every texture URI they
         reference) into models/<pack>/
      8. Copy each pack's own License txt into license/
      9. Verify: every copied .gltf resolves all of its URIs inside its folder.

    The curated model list below is the runtime catalog seed for VIS tasks.
    Extend $Curated when later tasks need more models, then re-run.
#>
param(
    [string]$TargetRoot = "$PSScriptRoot\..\assets\third_party\quaternius"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$ZipDir     = Join-Path $TargetRoot "_source\zips"
$ExtractDir = Join-Path $TargetRoot "_source\extracted"
$ModelsDir  = Join-Path $TargetRoot "models"
$LicenseDir = Join-Path $TargetRoot "license"
foreach ($d in @($ZipDir, $ExtractDir, $ModelsDir, $LicenseDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# --- Curated runtime subset per pack (paths relative to the extracted root).
# Keys: itch.io slug; values: display name + files to copy into models/<key>/.
$Packs = [ordered]@{
    "medieval-village-megakit" = @{
        Name    = "Medieval Village MegaKit"
        RootDir = "Medieval Village MegaKit[Standard]"
        Models  = @(
            "glTF/Wall_Plaster_Straight.gltf",
            "glTF/Wall_Plaster_WoodGrid.gltf",
            "glTF/Wall_UnevenBrick_Straight.gltf",
            "glTF/Wall_Plaster_Window_Wide_Flat.gltf",
            "glTF/Wall_UnevenBrick_Window_Wide_Flat.gltf",
            "glTF/Wall_Plaster_Door_Flat.gltf",
            "glTF/Wall_UnevenBrick_Door_Flat.gltf",
            "glTF/Door_1_Flat.gltf",
            "glTF/Window_Wide_Flat1.gltf",
            "glTF/WindowShutters_Wide_Flat_Open.gltf",
            "glTF/Roof_RoundTiles_6x6.gltf",
            "glTF/Roof_Wooden_2x1.gltf",
            "glTF/Overhang_Roof_Plaster.gltf",
            "glTF/Floor_WoodLight.gltf",
            "glTF/Floor_Brick.gltf",
            "glTF/Stairs_Exterior_Straight.gltf",
            "glTF/Prop_Crate.gltf",
            "glTF/Prop_Wagon.gltf",
            "glTF/Prop_Chimney.gltf",
            "glTF/Prop_Vine1.gltf",
            "glTF/Prop_WoodenFence_Single.gltf"
        )
    }
    "stylized-nature-megakit" = @{
        Name    = "Stylized Nature MegaKit"
        RootDir = "."
        Models  = @(
            "glTF/CommonTree_1.gltf", "glTF/CommonTree_2.gltf", "glTF/CommonTree_3.gltf",
            "glTF/CommonTree_4.gltf", "glTF/CommonTree_5.gltf",
            "glTF/Pine_1.gltf", "glTF/Pine_2.gltf",
            "glTF/DeadTree_1.gltf", "glTF/DeadTree_2.gltf",
            "glTF/Rock_Medium_1.gltf", "glTF/Rock_Medium_2.gltf", "glTF/Rock_Medium_3.gltf",
            "glTF/Grass_Common_Short.gltf", "glTF/Grass_Common_Tall.gltf",
            "glTF/Grass_Wispy_Tall.gltf",
            "glTF/Bush_Common.gltf", "glTF/Bush_Common_Flowers.gltf",
            "glTF/Flower_3_Group.gltf", "glTF/Flower_4_Group.gltf",
            "glTF/Mushroom_Common.gltf"
        )
    }
    "fantasy-props-megakit" = @{
        Name    = "Fantasy Props MegaKit"
        RootDir = "."
        Models  = @(
            "Exports/glTF/Barrel.gltf",
            "Exports/glTF/Crate_Wooden.gltf",
            "Exports/glTF/Chest_Wood.gltf",
            "Exports/glTF/Axe_Bronze.gltf",
            "Exports/glTF/Pickaxe_Bronze.gltf",
            "Exports/glTF/Sword_Bronze.gltf",
            "Exports/glTF/Anvil.gltf",
            "Exports/glTF/Anvil_Log.gltf",
            "Exports/glTF/Workbench.gltf",
            "Exports/glTF/Whetstone.gltf",
            "Exports/glTF/Stall_Cart_Empty.gltf",
            "Exports/glTF/Stall_Empty.gltf",
            "Exports/glTF/FarmCrate_Apple.gltf",
            "Exports/glTF/FarmCrate_Carrot.gltf",
            "Exports/glTF/FarmCrate_Empty.gltf",
            "Exports/glTF/Coin_Pile.gltf",
            "Exports/glTF/Lantern_Wall.gltf",
            "Exports/glTF/Torch_Metal.gltf",
            "Exports/glTF/Rope_1.gltf",
            "Exports/glTF/Bag.gltf",
            "Exports/glTF/Potion_1.gltf"
        )
    }
    "universal-base-characters" = @{
        Name    = "Universal Base Characters"
        RootDir = "Universal Base Characters[Standard]"
        Models  = @(
            "Base Characters/Godot - UE/Superhero_Male_FullBody.gltf",
            "Base Characters/Godot - UE/Superhero_Female_FullBody.gltf",
            # 'Origin at 0/glTF (Godot)' 변형은 buffer byteLength(32032)가 실제
            # .bin(51332)과 달라 Godot import가 실패하는 원본 결함이 있다.
            # byteLength가 정확한 Rigged to Head Bone 변형을 사용한다.
            "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_SimpleParted.gltf"
        )
    }
    "modular-character-outfits-fantasy" = @{
        Name    = "Modular Character Outfits - Fantasy"
        RootDir = "Modular Character Outfits - Fantasy[Standard]"
        Models  = @(
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Peasant_Arms.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Peasant_Body.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Peasant_Feet.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Peasant_Legs.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Arms.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Body.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Feet_Boots.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Legs.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Head_Hood.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Male_Ranger_Acc_Pauldron.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Female_Peasant_Arms.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Female_Peasant_Body.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Female_Peasant_Feet.gltf",
            "Exports/glTF (Godot-Unreal)/Modular Parts/Female_Peasant_Legs.gltf",
            "Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf",
            "Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf",
            "Exports/glTF (Godot-Unreal)/Outfits/Female_Peasant.gltf"
        )
    }
    "universal-animation-library" = @{
        Name    = "Universal Animation Library"
        RootDir = "Universal Animation Library[Standard]"
        Models  = @( "Unreal-Godot/UAL1_Standard.glb" )
    }
    "universal-animation-library-2" = @{
        Name    = "Universal Animation Library 2"
        RootDir = "Universal Animation Library 2[Standard]"
        Models  = @(
            "Unreal-Godot/UAL2_Standard.glb",
            "Female Mannequin/Unreal-Godot/Mannequin_F.glb"
        )
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

function JoinLines($arr) { [string]::Join("`n", $arr) }

function Get-CsrfToken([string]$Html) {
    $m = [regex]::Match($Html, 'name="csrf_token" value="([^"]+)"')
    if (-not $m.Success) { throw "csrf_token not found." }
    return $m.Groups[1].Value
}

function Get-PackZip {
    param([string]$Slug, [string]$OutPath)
    if (Test-Path -LiteralPath $OutPath) {
        Write-Host "[$Slug] zip already present, skipping download."
        return
    }
    Write-Host "[$Slug] requesting download url from itch.io ..."
    $page = JoinLines (curl.exe -s -L --max-time 60 "https://quaternius.itch.io/$Slug")
    if ($page -match 'name="csrf_token" value="([^"]+)"') { $tokens = @($Matches[1]) }
    $purch = JoinLines (curl.exe -s -L --max-time 60 "https://quaternius.itch.io/$Slug/purchase")
    if ($purch -match 'name="csrf_token" value="([^"]+)"') { $tokens += $Matches[1] }

    $dlUrl = $null
    foreach ($tok in $tokens) {
        $body = "csrf_token=$([uri]::EscapeDataString($tok))"
        $json = JoinLines (curl.exe -s --max-time 60 -X POST `
            -H "Content-Type: application/x-www-form-urlencoded" -H "Accept: application/json" `
            --data $body "https://quaternius.itch.io/$Slug/download_url")
        if ($json -match '"url"') {
            $dlUrl = ($json | ConvertFrom-Json).url
            break
        }
    }
    if (-not $dlUrl) { throw "[$Slug] could not obtain download url." }

    $dlPage = JoinLines (curl.exe -s -L --max-time 60 $dlUrl)
    $csrf2 = Get-CsrfToken $dlPage
    $ids = ([regex]::Matches($dlPage, 'data-upload_id="(\d+)"') | ForEach-Object { $_.Groups[1].Value })
    if (-not $ids) { throw "[$Slug] no uploads on download page." }

    # Quaternius packs expose exactly one Standard upload per game page.
    $id = $ids[0]
    $body2 = "csrf_token=$([uri]::EscapeDataString($csrf2))"
    $fjson = JoinLines (curl.exe -s --max-time 60 -X POST `
        -H "Content-Type: application/x-www-form-urlencoded" -H "Accept: application/json" `
        --data $body2 "https://quaternius.itch.io/$Slug/file/$id")
    $fileUrl = ($fjson | ConvertFrom-Json).url
    if (-not $fileUrl) { throw "[$Slug] no signed file url for upload ${id}." }

    Write-Host "[$Slug] downloading zip ..."
    curl.exe -s -L --max-time 1800 --retry 3 --retry-delay 5 -o $OutPath $fileUrl
    if ($LASTEXITCODE -ne 0) { throw "[$Slug] download failed." }
    Write-Host ("[{0}] downloaded {1:N0} bytes" -f $Slug, (Get-Item -LiteralPath $OutPath).Length)
}

function Build-TextureIndex {
    # Index every file under the pack root by name so glTF sidecars (.bin,
    # textures) resolve no matter which subfolder the exporter referenced them
    # from. Godot-specific folders win over engine-generic copies of the same
    # name (e.g. flipped-Y normal maps), Unreal-only variants are excluded.
    param([string]$SrcRoot)
    $index = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $SrcRoot -Recurse -File)) {
        if ($f.FullName -match "UnrealEngine|__MACOSX") { continue }
        $godot = ($f.FullName -match "Godot")
        if (-not $index.ContainsKey($f.Name) -or $godot) { $index[$f.Name] = $f.FullName }
    }
    return $index
}

function Resolve-Dependency {
    # Returns the source path for a glTF URI, or $null when unresolvable.
    # Alias fallback repairs Quaternius export bugs like 'T_X_Normal_png.png'
    # where the shipped file is actually 'T_X_Normal.png' (recorded in the
    # VIS-001-1 import report instead of silently patched inside the .gltf).
    param([string]$GltfDir, [string]$Name, [hashtable]$TexIndex)

    $direct = Join-Path $GltfDir $Name
    if (Test-Path -LiteralPath $direct) { return $direct }
    if ($TexIndex.ContainsKey($Name)) { return $TexIndex[$Name] }
    foreach ($alias in @(($Name -replace "_png\.png$", ".png"), ($Name -replace "\.png$", "_png.png"))) {
        if ($alias -ne $Name) {
            if (Test-Path -LiteralPath (Join-Path $GltfDir $alias)) { return (Join-Path $GltfDir $alias) }
            if ($TexIndex.ContainsKey($alias)) { return $TexIndex[$alias] }
        }
    }
    return $null
}

function Copy-CuratedModels {
    param([string]$SrcRoot, [string]$DestDir, [string[]]$ModelFiles)

    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    Get-ChildItem -LiteralPath $DestDir -File | Remove-Item -Force
    $texIndex = Build-TextureIndex -SrcRoot $SrcRoot

    foreach ($rel in $ModelFiles) {
        $src = Join-Path $SrcRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { throw "curated model missing in source: $rel" }
        Copy-Item -LiteralPath $src -Destination $DestDir -Force
    }

    # Resolve sidecar dependencies (.bin buffers + texture URIs) of every copied .gltf.
    $pending = @(Get-ChildItem -LiteralPath $DestDir -Filter "*.gltf")
    while ($pending.Count -gt 0) {
        $gltf = $pending[0]
        $pending = @($pending | Select-Object -Skip 1)
        $txt = Get-Content -LiteralPath $gltf.FullName -Raw
        foreach ($uri in [regex]::Matches($txt, '"uri"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) {
            if ($uri -match '^data:' -or $uri -match ':/') { continue }
            $depName = [uri]::UnescapeDataString($uri)
            $depDst = Join-Path $DestDir $depName
            if (Test-Path -LiteralPath $depDst) { continue }
            # Copy under the exact referenced name so the .gltf stays untouched;
            # the source file itself may come from an alias (see Resolve-Dependency).
            $depSrc = Resolve-Dependency -GltfDir (Split-Path -Parent $gltf.FullName) -Name $depName -TexIndex $texIndex
            if (-not $depSrc) { throw "missing dependency '$depName' referenced by $($gltf.Name)" }
            Copy-Item -LiteralPath $depSrc -Destination $depDst -Force
            if ($depName -like "*.gltf") { $pending = @($pending) + @(Get-Item -LiteralPath $depDst) }
        }
    }
}

function Test-ResolvedUris {
    param([string]$DestDir)
    foreach ($gltf in (Get-ChildItem -LiteralPath $DestDir -Filter "*.gltf")) {
        $txt = Get-Content -LiteralPath $gltf.FullName -Raw
        foreach ($uri in [regex]::Matches($txt, '"uri"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) {
            if ($uri -match '^data:' -or $uri -match ':/') { continue }
            $dep = Join-Path $DestDir ([uri]::UnescapeDataString($uri))
            if (-not (Test-Path -LiteralPath $dep)) {
                throw "unresolved uri '$uri' in $($gltf.Name)"
            }
        }
    }
}

foreach ($slug in $Packs.Keys) {
    $info = $Packs[$slug]
    $zipPath = Join-Path $ZipDir "$slug.zip"

    Get-PackZip -Slug $slug -OutPath $zipPath

    $packExtract = Join-Path $ExtractDir $slug
    if (-not (Test-Path -LiteralPath $packExtract)) {
        Write-Host "[$slug] extracting ..."
        New-Item -ItemType Directory -Path $packExtract -Force | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $packExtract)
    } else {
        Write-Host "[$slug] already extracted, skipping."
    }

    $srcRoot = Join-Path $packExtract $info.RootDir
    if ($info.RootDir -eq ".") { $srcRoot = $packExtract }
    if (-not (Test-Path -LiteralPath $srcRoot)) { throw "[$slug] extracted root not found: $srcRoot" }

    $dest = Join-Path $ModelsDir $slug
    Write-Host "[$slug] copying curated models -> $dest"
    Copy-CuratedModels -SrcRoot $srcRoot -DestDir $dest -ModelFiles $info.Models
    Test-ResolvedUris -DestDir $dest

    # Preserve the pack's own license text next to our attribution docs.
    foreach ($lic in (Get-ChildItem -LiteralPath $packExtract -Recurse -File |
            Where-Object { $_.Name -match "^License.*\.txt$" })) {
        $dst = Join-Path $LicenseDir ("{0}_{1}" -f $slug, $lic.Name)
        Copy-Item -LiteralPath $lic.FullName -Destination $dst -Force
    }
}

Write-Host ""
Write-Host "Per-pack curated file counts:"
Get-ChildItem -LiteralPath $ModelsDir -Directory | ForEach-Object {
    $n = (Get-ChildItem -LiteralPath $_.FullName -File).Count
    $mb = [Math]::Round(((Get-ChildItem -LiteralPath $_.FullName -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Host ("  {0,-38} {1,4} files {2,8} MB" -f $_.Name, $n, $mb)
}
Write-Host "Done."
