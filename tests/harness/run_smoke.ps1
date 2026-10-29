param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[int]$TimeoutSeconds = 90,
	[switch]$Noray,
	[switch]$Rollback, #use RollbackGameManager and the probe game, and check both peers start on the scheduled tick
	[switch]$Demo, #run the rollback demo: the client moves, then host and client views of every player must agree
	[switch]$Moving, #shooter and target run side by side and the shooter fires at where it sees the target; reports how many shots hit
	[switch]$NoLagComp, #with -Moving: the lobby does not rewind targets, for comparison
	[double]$LatencyMs = 0, #one-way delay added to the client's connection through tests/harness/latency_proxy.py
	[double]$JitterMs = 0,
	[double]$LossPercent = 0
)

# Launches a host and a client harness process, waits for both, prints their output and a PASS/FAIL line.
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:TEMP "godot_smoke"
New-Item -ItemType Directory -Force $logDir | Out-Null
$hostOut = Join-Path $logDir "host.out"; $hostErr = Join-Path $logDir "host.err"
$clientOut = Join-Path $logDir "client.out"; $clientErr = Join-Path $logDir "client.err"
Remove-Item $hostOut, $hostErr, $clientOut, $clientErr -ErrorAction SilentlyContinue

$scene = "res://tests/harness/harness.tscn"
$hostArgs = @("--path", "`"$project`"", $scene, "--", "--role", "host")
if ($Noray) { $hostArgs += "--noray" }
if ($Rollback) { $hostArgs += "--rollback" }
if ($Demo) { $hostArgs += "--demo" }
if ($Moving) { $hostArgs += "--moving" }
if ($NoLagComp) { $hostArgs += "--no-lagcomp" }
$hostProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList $hostArgs `
	-RedirectStandardOutput $hostOut -RedirectStandardError $hostErr

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not ((Test-Path $hostOut) -and (Select-String -Path $hostOut -Pattern "HOST_READY|FAIL" -Quiet))) {
	Start-Sleep -Milliseconds 500
}

$clientArgs = @("--path", "`"$project`"", $scene, "--", "--role", "client")
if ($Noray) {
	$gameId = (Select-String -Path $hostOut -Pattern "\[HOST\] GAME_ID (\S+)").Matches.Groups[1].Value
	$clientArgs += @("--noray", "--game-id", $gameId)
}
if ($Rollback) { $clientArgs += "--rollback" }
if ($Demo) { $clientArgs += "--demo" }
if ($Moving) { $clientArgs += "--moving" }
$proxyProc = $null
if ($LatencyMs -gt 0 -or $JitterMs -gt 0 -or $LossPercent -gt 0) {
	$proxyOut = Join-Path $logDir "proxy.out"; $proxyErr = Join-Path $logDir "proxy.err"
	$proxyProc = Start-Process py -PassThru -NoNewWindow `
		-ArgumentList "-3", "`"$PSScriptRoot\latency_proxy.py`"", "--listen", "5100", "--target", "5000", "--delay-ms", $LatencyMs, "--jitter-ms", $JitterMs, "--loss", $LossPercent `
		-RedirectStandardOutput $proxyOut -RedirectStandardError $proxyErr
	Start-Sleep -Seconds 1
	$clientArgs += @("--join-port", "5100")
}
$clientProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList $clientArgs `
	-RedirectStandardOutput $clientOut -RedirectStandardError $clientErr

while ((Get-Date) -lt $deadline -and -not ($hostProc.HasExited -and $clientProc.HasExited)) {
	Start-Sleep -Milliseconds 500
}

foreach ($p in @($hostProc, $clientProc, $proxyProc)) { if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
Start-Sleep -Seconds 1

"----- HOST -----"; Get-Content $hostOut | Where-Object { $_ -match '^\[HOST\]|ERROR|SCRIPT' }
"----- CLIENT -----"; Get-Content $clientOut | Where-Object { $_ -match '^\[CLIENT\]|ERROR|SCRIPT' }
"----- STDERR (host/client) -----"; Get-Content $hostErr, $clientErr -ErrorAction SilentlyContinue | Select-Object -First 20

$ok = (Select-String -Path $hostOut -Pattern "\[HOST\] DONE" -Quiet) -and (Select-String -Path $clientOut -Pattern "\[CLIENT\] DONE" -Quiet)
if ($Rollback) {
	$pattern = "scheduled_tick=(\d+) started_at_tick=(-?\d+)"
	$h = (Select-String -Path $hostOut -Pattern $pattern).Matches
	$c = (Select-String -Path $clientOut -Pattern $pattern).Matches
	if ($h.Count -eq 0 -or $c.Count -eq 0) {
		"ROLLBACK START: no start report found"; $ok = $false
	} else {
		$hs = $h[0].Groups[1].Value; $ha = $h[0].Groups[2].Value; $cs = $c[0].Groups[1].Value; $ca = $c[0].Groups[2].Value
		"ROLLBACK START: host scheduled=$hs started=$ha | client scheduled=$cs started=$ca"
		if ($hs -ne $cs -or $hs -ne $ha -or $cs -ne $ca) { "ROLLBACK START: MISALIGNED"; $ok = $false } else { "ROLLBACK START: aligned" }
	}
}
if ($Moving) {
	$m = (Select-String -Path $hostOut -Pattern "MOVING_RESULT health=(\d+)").Matches
	if ($m.Count -eq 0) {
		"MOVING: no result found"; $ok = $false
	} else {
		$hits = (1000 - [int]$m[0].Groups[1].Value) / 25
		$s = (Select-String -Path $clientOut -Pattern "MOVING_SHOTS shots=(\d+) rtt_ms=(\d+) view_lag=(\d+)").Matches
		$fired = if ($s.Count -gt 0) { $s[0].Groups[1].Value } else { "?" }
		$rtt = if ($s.Count -gt 0) { "measured rtt $($s[0].Groups[2].Value) ms, view lag $($s[0].Groups[3].Value) ticks" } else { "" }
		"MOVING: latency ${LatencyMs}ms each way, lag compensation $(if ($NoLagComp) { 'OFF' } else { 'ON' }): $hits shots hit of $fired fired ($rtt)"
	}
} elseif ($Demo) {
	function Get-Positions($file) {
		$line = (Select-String -Path $file -Pattern "DEMO_POS me=(\d+) (.*)$").Matches
		if ($line.Count -eq 0) { return $null }
		$result = @{ me = $line[0].Groups[1].Value; players = @{} }
		foreach ($e in $line[0].Groups[2].Value.Trim() -split ";") {
			if ($e -match "^(\d+)=(-?[\d.]+),(-?[\d.]+),(\d+)$") { $result.players[$Matches[1]] = @([double]$Matches[2], [double]$Matches[3], [int]$Matches[4]) }
		}
		return $result
	}
	$hp = Get-Positions $hostOut; $cp = Get-Positions $clientOut
	if ($null -eq $hp -or $null -eq $cp) {
		"DEMO: no position report found"; $ok = $false
	} else {
		$mine = $cp.players[$cp.me]
		$moved = $mine[0] - 200.0
		"DEMO: client player moved $([math]::Round($moved,1)) px right (expected roughly 250)"
		if ($moved -lt 150 -or $moved -gt 350) { "DEMO: movement out of range"; $ok = $false }
		foreach ($id in $hp.players.Keys) {
			$a = $hp.players[$id]; $b = $cp.players[$id]
			if ($null -eq $b) { "DEMO: player $id missing on client"; $ok = $false; continue }
			$diff = [math]::Max([math]::Abs($a[0] - $b[0]), [math]::Abs($a[1] - $b[1]))
			"DEMO: player $id host sees ($($a[0]), $($a[1])) client sees ($($b[0]), $($b[1])) diff $([math]::Round($diff,2))"
			if ($diff -gt 2.0) { "DEMO: views disagree"; $ok = $false }
			# the host's player was hit exactly once (100 -> 75) and the shooter was never hit; both peers must show the same health
			$expected = if ($id -eq $cp.me) { 100 } else { 75 }
			"DEMO: player $id health host sees $($a[2]) client sees $($b[2]) (expected $expected)"
			if ($a[2] -ne $expected -or $b[2] -ne $expected) { "DEMO: health wrong"; $ok = $false }
		}
	}
	Select-String -Path $clientOut -Pattern "LOCAL_RESPONSE" | ForEach-Object { $_.Line }
}
if ($ok) { "SMOKE: PASS" } else { "SMOKE: FAIL" }
