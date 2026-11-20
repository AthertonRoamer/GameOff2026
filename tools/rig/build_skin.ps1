<#
Builds a role's skin: renders its sheets in Blender, packs them into game/player/skin/<role>/, and has Godot import and bake them.

    tools\rig\build_skin.ps1 -Role guard                                   # everything (a long time: over an hour)
    tools\rig\build_skin.ps1 -Role guard -Only torso_draw,legs_side_walk   # just these (a trailing * matches a prefix: torso_tr_*)

-Godot is the Godot console executable (or set $env:GODOT). The renders and the packing work are left in tools\rig\out\<role>\.
Needs the venv with bpy, numpy and pillow, and the models and clips in tools\rig\assets (see README.md).
#>
param(
    [string]$Role = "guard",
    [string[]]$Only = @(),
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = "Stop"
$rig = $PSScriptRoot
$project = (Resolve-Path (Join-Path $rig "..\..")).Path
$skin = Join-Path $project "game\player\skin\$Role"
$out = Join-Path $rig "out\$Role"
$python = Join-Path $rig "venv\Scripts\python.exe"
if (-not (Test-Path $python)) { throw "No venv at $python (see README.md)" }
if (-not $Godot) { throw "Say where Godot is: -Godot <path to the console executable> or set `$env:GODOT" }

# 1. the pictures, and the shoulder and head positions (the same states again, with no pictures; the forward and sideways upper bodies are needed to line up the heads)
$states = $Only -join ","
$heads = "torso_walk,torso_run,torso_side_walk,torso_side_run,torso_back,torso_back_run"
Remove-Item (Join-Path $out "pictures"), (Join-Path $out "shoulders") -Recurse -Force -ErrorAction SilentlyContinue
$env:SHOULDERS = $null
if ($states) { & $python (Join-Path $rig "anim.py") -- $Role (Join-Path $out "pictures") $states } else { & $python (Join-Path $rig "anim.py") -- $Role (Join-Path $out "pictures") }
$env:SHOULDERS = "1"
if ($states) { & $python (Join-Path $rig "anim.py") -- $Role (Join-Path $out "shoulders") "$states,$heads" } else { & $python (Join-Path $rig "anim.py") -- $Role (Join-Path $out "shoulders") }
$env:SHOULDERS = $null

# 2. the packing
& $python (Join-Path $rig "pack\pack_skin.py") (Join-Path $out "pictures\$Role") (Join-Path $out "shoulders\$Role") $skin

# 3. Godot imports the sheets (compressed on the GPU: BC7, see project.godot) and bakes the SpriteFrames
& $Godot --headless --path $project --import | Out-Null
foreach ($file in Get-ChildItem (Join-Path $skin "*.png.import")) {
    $text = [IO.File]::ReadAllText($file.FullName)
    if ($text -match "compress/mode=0") {  # a new sheet: Godot made its import file with the defaults
        $text = $text.Replace("compress/mode=0", "compress/mode=2").Replace("compress/high_quality=false", "compress/high_quality=true")
        [IO.File]::WriteAllText($file.FullName, $text, (New-Object Text.UTF8Encoding $false))
    }
}
& $Godot --headless --path $project --import | Out-Null
& $Godot --headless --path $project --script res://tools/art/bake_skin_frames.gd -- $Role
