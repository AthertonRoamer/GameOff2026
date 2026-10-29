param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[int]$TimeoutSeconds = 90,
	[switch]$Noray,
	[switch]$Rollback, #use RollbackGameManager and the probe game, and check every peer starts on the scheduled tick
	[switch]$Demo, #run the rollback demo: the first client shoots and moves, then every peer's view of every player must agree
	[switch]$Moving, #shooter and target run side by side and the shooter fires at where it sees the target; reports how many shots hit
	[switch]$NoLagComp, #with -Moving: the lobby does not rewind targets, for comparison
	[switch]$Leave, #with -Demo: the first client leaves the game gracefully; the host must notice and keep running
	[switch]$Kill, #with -Demo: the first client's process is killed; the host must notice (after ENet times it out) and keep running
	[int]$Clients = 1, #client processes. The first one acts, any others only observe (3 players = -Clients 2)
	[int]$Rounds = 1, #games played back to back in the same lobby (use with -Demo)
	[double]$LatencyMs = 0, #one-way delay added to the first client's connection through tests/harness/latency_proxy.py
	[double]$JitterMs = 0,
	[double]$LossPercent = 0
)

# Launches a host and client harness processes, waits for them, prints their output and a PASS/FAIL line.
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:TEMP "godot_smoke"
New-Item -ItemType Directory -Force $logDir | Out-Null
$hostOut = Join-Path $logDir "host.out"; $hostErr = Join-Path $logDir "host.err"
Remove-Item (Join-Path $logDir "*.out"), (Join-Path $logDir "*.err"), (Join-Path $logDir "lobby_hitch.log") -ErrorAction SilentlyContinue

$scene = "res://tests/harness/harness.tscn"
$common = @()
if ($Noray) { $common += "--noray" }
if ($Rollback) { $common += "--rollback" }
if ($Demo -or $Leave -or $Kill) { $common += "--demo" }
if ($Moving) { $common += "--moving" }
if ($Leave) { $common += "--leave" }
if ($Kill) { $common += "--kill" }
$common += @("--players", ($Clients + 1), "--rounds", $Rounds)
$hostArgs = @("--path", "`"$project`"", $scene, "--", "--role", "host") + $common
if ($NoLagComp) { $hostArgs += "--no-lagcomp" }
$hostProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow -ArgumentList $hostArgs `
	-RedirectStandardOutput $hostOut -RedirectStandardError $hostErr

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not ((Test-Path $hostOut) -and (Select-String -Path $hostOut -Pattern "HOST_READY|FAIL" -Quiet))) {
	Start-Sleep -Milliseconds 500
}

$proxyProc = $null
if ($LatencyMs -gt 0 -or $JitterMs -gt 0 -or $LossPercent -gt 0) {
	$proxyOut = Join-Path $logDir "proxy.out"; $proxyErr = Join-Path $logDir "proxy.err"
	$proxyProc = Start-Process py -PassThru -NoNewWindow `
		-ArgumentList "-3", "`"$PSScriptRoot\latency_proxy.py`"", "--listen", "5100", "--target", "5000", "--delay-ms", $LatencyMs, "--jitter-ms", $JitterMs, "--loss", $LossPercent `
		-RedirectStandardOutput $proxyOut -RedirectStandardError $proxyErr
	Start-Sleep -Seconds 1
}

# client 1 acts and (if asked) goes through the proxy; the others observe and join directly
$clientProcs = @(); $clientOuts = @(); $clientErrs = @()
foreach ($n in 1..$Clients) {
	$suffix = if ($n -eq 1) { "" } else { "$n" }
	$out = Join-Path $logDir "client$suffix.out"; $err = Join-Path $logDir "client$suffix.err"
	$clientArgs = @("--path", "`"$project`"", $scene, "--", "--role", "client", "--name", "ClientPlayer$n") + $common
	if ($Noray) {
		$gameId = (Select-String -Path $hostOut -Pattern "\[HOST\] GAME_ID (\S+)").Matches.Groups[1].Value
		$clientArgs += @("--game-id", $gameId)
	}
	if ($n -gt 1) { $clientArgs += "--observer" }
	elseif ($null -ne $proxyProc) { $clientArgs += @("--join-port", "5100") }
	$clientProcs += Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow -ArgumentList $clientArgs `
		-RedirectStandardOutput $out -RedirectStandardError $err
	$clientOuts += $out; $clientErrs += $err
	Start-Sleep -Seconds 2
}

$killed = $false
$allProcs = @($hostProc) + $clientProcs
while ((Get-Date) -lt $deadline -and -not (($allProcs | Where-Object { -not $_.HasExited }).Count -eq 0)) {
	if ($Kill -and -not $killed -and (Select-String -Path $clientOuts[0] -Pattern "\[CLIENT\] GAME_STARTED" -Quiet)) {
		Start-Sleep -Seconds 1
		Stop-Process -Id $clientProcs[0].Id -Force
		$killed = $true
		"(killed the first client process)"
	}
	Start-Sleep -Milliseconds 500
}

foreach ($p in ($allProcs + @($proxyProc))) { if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
Start-Sleep -Seconds 1

"----- HOST -----"; Get-Content $hostOut | Where-Object { $_ -match '^\[HOST\]|ERROR|SCRIPT' }
foreach ($n in 1..$Clients) {
	"----- CLIENT $n -----"; Get-Content $clientOuts[$n - 1] | Where-Object { $_ -match '^\[CLIENT\]|ERROR|SCRIPT' }
}
"----- STDERR (host/clients) -----"; Get-Content (@($hostErr) + $clientErrs) -ErrorAction SilentlyContinue | Select-Object -First 20

$ok = Select-String -Path $hostOut -Pattern "\[HOST\] DONE" -Quiet
foreach ($n in 1..$Clients) {
	if ($Kill -and $n -eq 1) { continue } #killed on purpose, it never finishes
	if (-not (Select-String -Path $clientOuts[$n - 1] -Pattern "\[CLIENT\] DONE" -Quiet)) { "client $n did not finish"; $ok = $false }
}

if ($Rollback) {
	$pattern = "scheduled_tick=(\d+) started_at_tick=(-?\d+)"
	$reports = @(Select-String -Path (@($hostOut) + $clientOuts) -Pattern $pattern | ForEach-Object { $_.Matches[0] })
	if ($reports.Count -lt $Clients + 1) {
		"ROLLBACK START: expected $($Clients + 1) start reports, found $($reports.Count)"; $ok = $false
	} else {
		$ticks = @($reports | ForEach-Object { "$($_.Groups[1].Value)/$($_.Groups[2].Value)" } | Select-Object -Unique)
		"ROLLBACK START: scheduled/started per peer: $(($reports | ForEach-Object { "$($_.Groups[1].Value)/$($_.Groups[2].Value)" }) -join ', ')"
		$aligned = $reports.Count -gt 0 -and ($ticks.Count -eq 1) -and ($ticks[0].Split('/')[0] -eq $ticks[0].Split('/')[1])
		if ($aligned) { "ROLLBACK START: aligned" } else { "ROLLBACK START: MISALIGNED"; $ok = $false }
	}
}

function Get-Positions($file, $label) {
	$line = (Select-String -Path $file -Pattern "$label me=(\d+) (.*)$").Matches
	if ($line.Count -eq 0) { return $null }
	$result = @{ me = $line[0].Groups[1].Value; players = @{} }
	foreach ($e in $line[0].Groups[2].Value.Trim() -split ";") {
		if ($e -match "^(\d+)=(-?[\d.]+),(-?[\d.]+),(\d+)$") { $result.players[$Matches[1]] = @([double]$Matches[2], [double]$Matches[3], [int]$Matches[4]) }
	}
	return $result
}

if ($Moving) {
	$m = (Select-String -Path $hostOut -Pattern "MOVING_RESULT health=(\d+)").Matches
	if ($m.Count -eq 0) {
		"MOVING: no result found"; $ok = $false
	} else {
		$hits = (1000 - [int]$m[0].Groups[1].Value) / 25
		$s = (Select-String -Path $clientOuts[0] -Pattern "MOVING_SHOTS shots=(\d+) rtt_ms=(\d+) view_lag=(\d+)").Matches
		$fired = if ($s.Count -gt 0) { $s[0].Groups[1].Value } else { "?" }
		$rtt = if ($s.Count -gt 0) { "measured rtt $($s[0].Groups[2].Value) ms, view lag $($s[0].Groups[3].Value) ticks" } else { "" }
		"MOVING: latency ${LatencyMs}ms each way, lag compensation $(if ($NoLagComp) { 'OFF' } else { 'ON' }): $hits shots hit of $fired fired ($rtt)"
	}
} elseif ($Leave -or $Kill) {
	$d = (Select-String -Path $hostOut -Pattern "DEPARTURE_RESULT ok=(\w+) players=(\d+) seconds=([\d.]+)").Matches
	$r = (Select-String -Path $hostOut -Pattern "HOST_STILL_RUNS moved=(-?[\d.]+)").Matches
	if ($d.Count -eq 0 -or $r.Count -eq 0) {
		"DEPARTURE: no result found"; $ok = $false
	} else {
		"DEPARTURE: host noticed ok=$($d[0].Groups[1].Value), $($d[0].Groups[2].Value) players left, after $($d[0].Groups[3].Value) s; host's own player then moved $($r[0].Groups[1].Value) px"
		if ($d[0].Groups[1].Value -ne "True" -or [double]$r[0].Groups[1].Value -lt 100) { "DEPARTURE: host did not cope"; $ok = $false }
	}
} elseif ($Demo) {
	$hp = Get-Positions $hostOut "DEMO_POS"
	$acting = Get-Positions $clientOuts[0] "DEMO_POS"
	if ($null -eq $hp -or $null -eq $acting) {
		"DEMO: no position report found"; $ok = $false
	} else {
		$moved = $acting.players[$acting.me][0] - 200.0
		if ($Clients -eq 1) {
			"DEMO: client player moved $([math]::Round($moved,1)) px right (expected roughly 250)"
			if ($moved -lt 150 -or $moved -gt 350) { "DEMO: movement out of range"; $ok = $false }
		} else {
			"DEMO: client player moved $([math]::Round($moved,1)) px right (another player stands in the way, so less than 250 is expected)"
		}
		foreach ($n in 1..$Clients) {
			$cp = Get-Positions $clientOuts[$n - 1] "DEMO_POS"
			if ($null -eq $cp) { "DEMO: client $n sent no position report"; $ok = $false; continue }
			foreach ($id in $hp.players.Keys) {
				$a = $hp.players[$id]; $b = $cp.players[$id]
				if ($null -eq $b) { "DEMO: player $id missing for client $n"; $ok = $false; continue }
				$diff = [math]::Max([math]::Abs($a[0] - $b[0]), [math]::Abs($a[1] - $b[1]))
				# the first client's host-side opponent was hit exactly once (100 -> 75), nobody else was hit
				$shooterId = $acting.me
				$expected = if ($id -eq $shooterId) { 100 } elseif ($a[0] -eq 100.0 -and $a[1] -eq 100.0) { 75 } else { 100 }
				"DEMO: client $n, player ${id}: host sees ($($a[0]), $($a[1])) hp $($a[2]), client sees ($($b[0]), $($b[1])) hp $($b[2]), diff $([math]::Round($diff,2)), expected hp $expected"
				if ($diff -gt 2.0) { "DEMO: views disagree"; $ok = $false }
				if ($a[2] -ne $expected -or $b[2] -ne $expected) { "DEMO: health wrong"; $ok = $false }
			}
		}
		if ($Rounds -gt 1) {
			foreach ($round in 2..$Rounds) {
				foreach ($file in (@($hostOut) + $clientOuts)) {
					$p = Get-Positions $file "ROUND_$round POS"
					if ($null -eq $p) { "ROUNDS: round $round report missing in $(Split-Path $file -Leaf)"; $ok = $false; continue }
					foreach ($id in $p.players.Keys) {
						$e = $p.players[$id]
						$fresh = ($e[2] -eq 100) -and ($e[1] -eq 100.0) -and (@(100.0, 200.0, 300.0) -contains $e[0])
						if (-not $fresh) { "ROUNDS: round $round in $(Split-Path $file -Leaf): player $id is not fresh ($($e[0]), $($e[1]) hp $($e[2]))"; $ok = $false }
					}
				}
				"ROUNDS: round $round started on every peer with fresh players"
			}
		}
	}
	Select-String -Path $clientOuts[0] -Pattern "LOCAL_RESPONSE" | ForEach-Object { $_.Line }
}
if ($ok) { "SMOKE: PASS" } else { "SMOKE: FAIL" }
