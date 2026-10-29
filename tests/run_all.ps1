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
	$lag = & (Join-Path $here "harness\run_lagcomp_check.ps1") -LatencyMs 120
	$lagPass = ($lag | Select-String -Pattern "LAGCOMP CHECK: PASS" -Quiet)
	$results["lag compensation helps at 120 ms each way"] = $lagPass
	"{0,-62} {1}" -f "lag compensation helps at 120 ms each way", $(if ($lagPass) { "PASS" } else { "FAIL" })
	if (-not $lagPass) { $lag | Select-String -Pattern "MOVING|LAGCOMP" | ForEach-Object { "      " + $_.Line } }
}

$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value }).Count
""
"ALL CHECKS: $(if ($failed -eq 0) { 'PASS' } else { "$failed FAILED" }) ($($results.Count) run)"
