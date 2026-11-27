param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[switch]$SkipSlow #skip the killed-client scenario (waits for ENet to time the client out) and the latency comparison
)

# Runs every automated check for the template and the rollback layer, and prints one PASS/FAIL line per check.
# Takes several minutes: each scenario starts real Godot processes. Needs Python for the latency checks.
$here = $PSScriptRoot
$smoke = Join-Path $here "harness\run_smoke.ps1"
$project = Resolve-Path (Join-Path $here "..")
$results = [ordered]@{}

function Add-SmokeResult($name, $lines) {
	$pass = ($lines | Select-String -Pattern "^SMOKE: PASS" -Quiet)
	$results[$name] = $pass
	"{0,-62} {1}" -f $name, $(if ($pass) { "PASS" } else { "FAIL" })
	if (-not $pass) { $lines | Select-String -Pattern "FAIL|did not|missing|wrong|MISALIGNED|disagree|not fresh|not cope|no result" | ForEach-Object { "      " + $_.Line } }
}

# unit test of the lag compensator (a scene, because script mode has no autoloads)
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_lag_compensator.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\lagtest.out" -RedirectStandardError "$env:TEMP\lagtest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\lagtest.out" -Pattern "RESULT: PASS" -Quiet)
$results["lag compensator unit test"] = $unit
"{0,-62} {1}" -f "lag compensator unit test", $(if ($unit) { "PASS" } else { "FAIL" })

# unit test of the facility map scene: rooms, doors and consoles placed in the editor still add up (a scene, because the consoles use autoloads)
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_facility_map.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\maptest.out" -RedirectStandardError "$env:TEMP\maptest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$mapPass = (Select-String -Path "$env:TEMP\maptest.out" -Pattern "RESULT: PASS" -Quiet)
$results["facility map unit test"] = $mapPass
"{0,-62} {1}" -f "facility map unit test", $(if ($mapPass) { "PASS" } else { "FAIL" })
if (-not $mapPass) { Select-String -Path "$env:TEMP\maptest.out" -Pattern "FAIL" | ForEach-Object { "      " + $_.Line } }
# unit test of the power system: regions, generators, door costs, the shared pool, switching off in shed_order, repair (and the wings map's regions)
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_power_grid.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\powertest.out" -RedirectStandardError "$env:TEMP\powertest.err"
if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force }
$powerPass = (Select-String -Path "$env:TEMP\powertest.out" -Pattern "RESULT: PASS" -Quiet)
$results["power grid unit test"] = $powerPass
"{0,-62} {1}" -f "power grid unit test", $(if ($powerPass) { "PASS" } else { "FAIL" })
if (-not $powerPass) { Select-String -Path "$env:TEMP\powertest.out" -Pattern "FAIL" | ForEach-Object { "      " + $_.Line } }
# unit test of the rooms' ceiling lights: one per room, sized from its rectangles, stopped by walls and shut doors, spilling out of open doorways
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_room_lights.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\lightstest.out" -RedirectStandardError "$env:TEMP\lightstest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$lightsPass = (Select-String -Path "$env:TEMP\lightstest.out" -Pattern "RESULT: PASS" -Quiet)
$results["room lights unit test"] = $lightsPass
"{0,-62} {1}" -f "room lights unit test", $(if ($lightsPass) { "PASS" } else { "FAIL" })
if (-not $lightsPass) { Select-String -Path "$env:TEMP\lightstest.out" -Pattern "FAIL" | ForEach-Object { "      " + $_.Line } }
# unit test of the rooms' cameras: switched like lights from the door console, 5 pts/s, shed before lights, right-click on the map, seen by PlayerSight
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_cameras.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\camerastest.out" -RedirectStandardError "$env:TEMP\camerastest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$camerasPass = (Select-String -Path "$env:TEMP\camerastest.out" -Pattern "RESULT: PASS" -Quiet)
$results["cameras unit test"] = $camerasPass
"{0,-62} {1}" -f "cameras unit test", $(if ($camerasPass) { "PASS" } else { "FAIL" })
if (-not $camerasPass) { Select-String -Path "$env:TEMP\camerastest.out" -Pattern "FAIL" | ForEach-Object { "      " + $_.Line } }
# unit test of the map streaming: tiles near the view only, decor in and out of the tree
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_map_streaming.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\streamtest.out" -RedirectStandardError "$env:TEMP\streamtest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$streamPass = (Select-String -Path "$env:TEMP\streamtest.out" -Pattern "RESULT: PASS" -Quiet)
$results["map streaming unit test"] = $streamPass
"{0,-62} {1}" -f "map streaming unit test", $(if ($streamPass) { "PASS" } else { "FAIL" })
if (-not $streamPass) { Select-String -Path "$env:TEMP\streamtest.out" -Pattern "FAIL" | ForEach-Object { "      " + $_.Line } }
# unit test of role and team assignment
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_role_assigner.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\roletest.out" -RedirectStandardError "$env:TEMP\roletest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\roletest.out" -Pattern "RESULT: PASS" -Quiet)
$results["role assigner unit test"] = $unit
"{0,-62} {1}" -f "role assigner unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# unit test of the game clock
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_game_clock.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\clocktest.out" -RedirectStandardError "$env:TEMP\clocktest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\clocktest.out" -Pattern "RESULT: PASS" -Quiet)
$results["game clock unit test"] = $unit
"{0,-62} {1}" -f "game clock unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# unit test of the win rules and the end screen
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_match_director.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\matchtest.out" -RedirectStandardError "$env:TEMP\matchtest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\matchtest.out" -Pattern "RESULT: PASS" -Quiet)
$results["match director unit test"] = $unit
"{0,-62} {1}" -f "match director unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# every artifact has a unique name and image
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_artifacts.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\artifacttest.out" -RedirectStandardError "$env:TEMP\artifacttest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\artifacttest.out" -Pattern "RESULT: PASS" -Quiet)
$results["artifacts unit test"] = $unit
"{0,-62} {1}" -f "artifacts unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# pickups: placement, who may take an artifact, the item reaching the inventory
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_pickups.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\pickuptest.out" -RedirectStandardError "$env:TEMP\pickuptest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\pickuptest.out" -Pattern "RESULT: PASS" -Quiet)
$results["pickups unit test"] = $unit
"{0,-62} {1}" -f "pickups unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# ammunition, reloading, stamina, the minimap and the map screen
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_ammo.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\ammotest.out" -RedirectStandardError "$env:TEMP\ammotest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\ammotest.out" -Pattern "RESULT: PASS" -Quiet)
$results["ammo, stamina and map unit test"] = $unit
"{0,-62} {1}" -f "ammo, stamina and map unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# the roles' abilities: the shade's quiet, the gunner's shotgun, the medic's revive, the ventrat's vents
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_abilities.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\abilitytest.out" -RedirectStandardError "$env:TEMP\abilitytest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\abilitytest.out" -Pattern "RESULT: PASS" -Quiet)
$results["role abilities unit test"] = $unit
"{0,-62} {1}" -f "role abilities unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# the attackers' win: the target artifact carried into an exit zone
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_artifact_escape.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\escapetest.out" -RedirectStandardError "$env:TEMP\escapetest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\escapetest.out" -Pattern "RESULT: PASS" -Quiet)
$results["artifact escape unit test"] = $unit
"{0,-62} {1}" -f "artifact escape unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# the phases before play (role reveal), and play waiting for them
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_match_phases.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\phasestest.out" -RedirectStandardError "$env:TEMP\phasestest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\phasestest.out" -Pattern "RESULT: PASS" -Quiet)
$results["match phases unit test"] = $unit
"{0,-62} {1}" -f "match phases unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# the reusable map view (scroll, zoom, layers) and the door console screen built on it
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_map_view.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\mapviewtest.out" -RedirectStandardError "$env:TEMP\mapviewtest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\mapviewtest.out" -Pattern "RESULT: PASS" -Quiet)
$results["map view unit test"] = $unit
"{0,-62} {1}" -f "map view unit test", $(if ($unit) { "PASS" } else { "FAIL" })
# choosing where to start: spawn rooms, who sees whose pick, the spawn phase placing players
$p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://tests/unit/test_spawn_select.tscn" -NoNewWindow -PassThru `
	-RedirectStandardOutput "$env:TEMP\spawntest.out" -RedirectStandardError "$env:TEMP\spawntest.err"
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force }
$unit = (Select-String -Path "$env:TEMP\spawntest.out" -Pattern "RESULT: PASS" -Quiet)
$results["spawn selection unit test"] = $unit
"{0,-62} {1}" -f "spawn selection unit test", $(if ($unit) { "PASS" } else { "FAIL" })

Add-SmokeResult "original demo (host, lobby, join, game, end)" (& $smoke -Godot $Godot)
Add-SmokeResult "all peers start on the same tick (2 players)" (& $smoke -Godot $Godot -Rollback)
Add-SmokeResult "all peers start on the same tick (3 players)" (& $smoke -Godot $Godot -Rollback -Clients 2 -TimeoutSeconds 120)
Add-SmokeResult "rollback demo: movement and shooting agree (2 players)" (& $smoke -Godot $Godot -Demo -TimeoutSeconds 120)
Add-SmokeResult "rollback demo: movement and shooting agree (3 players)" (& $smoke -Godot $Godot -Demo -Clients 2 -TimeoutSeconds 150)
Add-SmokeResult "rollback demo: projectiles kill, player respawns (2 players)" (& $smoke -Godot $Godot -Combat -TimeoutSeconds 150)
Add-SmokeResult "rollback demo: projectiles kill, player respawns (3 players)" (& $smoke -Godot $Godot -Combat -Clients 2 -TimeoutSeconds 150)
Add-SmokeResult "rollback demo: second game in the same lobby" (& $smoke -Godot $Godot -Demo -Rounds 2 -TimeoutSeconds 150)
Add-SmokeResult "rollback demo: a player leaves mid-game" (& $smoke -Godot $Godot -Leave -TimeoutSeconds 150)
if (-not $SkipSlow) {
	Add-SmokeResult "rollback demo: a player's process is killed mid-game" (& $smoke -Godot $Godot -Kill -TimeoutSeconds 200)
	Add-SmokeResult "rollback demo: 80 ms each way, 2% loss" (& $smoke -Godot $Godot -Demo -LatencyMs 80 -LossPercent 2 -TimeoutSeconds 150)
	Add-SmokeResult "rollback demo: projectiles and respawn, 80 ms each way, 2% loss" (& $smoke -Godot $Godot -Combat -LatencyMs 80 -LossPercent 2 -TimeoutSeconds 150)
	$lag = & (Join-Path $here "harness\run_lagcomp_check.ps1") -Godot $Godot -LatencyMs 120
	$lagPass = ($lag | Select-String -Pattern "LAGCOMP CHECK: PASS" -Quiet)
	$results["lag compensation helps at 120 ms each way"] = $lagPass
	"{0,-62} {1}" -f "lag compensation helps at 120 ms each way", $(if ($lagPass) { "PASS" } else { "FAIL" })
	if (-not $lagPass) { $lag | Select-String -Pattern "MOVING|LAGCOMP" | ForEach-Object { "      " + $_.Line } }
}

$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value }).Count
""
"ALL CHECKS: $(if ($failed -eq 0) { 'PASS' } else { "$failed FAILED" }) ($($results.Count) run)"
