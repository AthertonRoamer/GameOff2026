<#
Builds the other roles' skins: each is the guard's legs (shared, see pack/seed_shared_legs.py) plus its own upper body (every torso sheet) and its falls, rendered in Blender
from the same recipes as the guard (the role's look is ROLES and the gear_* functions in anim.py).

    tools\rig\build_roles.ps1 -Godot "C:\path\to\Godot_console.exe"                          # medic, gunner, electrician, shade, ventrat, intruder
    tools\rig\build_roles.ps1 -Roles gunner,ventrat -Godot ... -Only torso_idle_aim,torso_draw # just these roles, just these sheets (a trailing * matches a prefix)

The renders and packing work are left in tools\rig\out\<role>\. Godot imports the new sheets once at the end (compressed on the GPU: BC7) and bakes each <role>_frames.tres.
#>
param(
    [string[]]$Roles = @("medic", "gunner", "electrician", "shade", "ventrat", "intruder"),
    [string[]]$Only = @("torso_*", "death_*"),
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = "Stop"
$rig = $PSScriptRoot
$project = (Resolve-Path (Join-Path $rig "..\..")).Path
$python = Join-Path $rig "venv\Scripts\python.exe"
if (-not (Test-Path $python)) { throw "No venv at $python (see README.md)" }
if (-not $Godot) { throw "Say where Godot is: -Godot <path to the console executable> or set `$env:GODOT" }
$guard = Join-Path $project "game\player\skin\guard"
$states = $Only -join ","
$heads = "torso_walk,torso_run,torso_side_walk,torso_side_run,torso_back,torso_back_run"

foreach ($role in $Roles) {
    $started = Get-Date
    $out = Join-Path $rig "out\$role"
    $skin = Join-Path $project "game\player\skin\$role"
    Write-Host "== $role"
    Remove-Item (Join-Path $out "pictures"), (Join-Path $out "shoulders") -Recurse -Force -ErrorAction SilentlyContinue
    $env:SHOULDERS = $null
    & $python (Join-Path $rig "anim.py") -- $role (Join-Path $out "pictures") $states
    $env:SHOULDERS = "1"
    & $python (Join-Path $rig "anim.py") -- $role (Join-Path $out "shoulders") "$states,$heads"
    $env:SHOULDERS = $null
    & $python (Join-Path $rig "pack\seed_shared_legs.py") $guard $skin
    & $python (Join-Path $rig "pack\pack_skin.py") (Join-Path $out "pictures\$role") (Join-Path $out "shoulders\$role") $skin
    Write-Host ("== {0} rendered and packed in {1:N0} s" -f $role, ((Get-Date) - $started).TotalSeconds)
}

& $Godot --headless --path $project --import | Out-Null
foreach ($role in $Roles) {
    foreach ($file in Get-ChildItem (Join-Path $project "game\player\skin\$role\*.png.import")) {
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text -match "compress/mode=0") {  # a new sheet: Godot made its import file with the defaults
            $text = $text.Replace("compress/mode=0", "compress/mode=2").Replace("compress/high_quality=false", "compress/high_quality=true")
            [IO.File]::WriteAllText($file.FullName, $text, (New-Object Text.UTF8Encoding $false))
        }
    }
}
& $Godot --headless --path $project --import | Out-Null
foreach ($role in $Roles) { & $Godot --headless --path $project --script res://tools/art/bake_skin_frames.gd -- $role }
