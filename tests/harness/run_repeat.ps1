param(
	[int]$Runs = 10,
	[double]$LatencyMs = 80,
	[double]$LossPercent = 5,
	[string]$Scenario = "Demo" #Demo or Rollback
)

# Repeats run_smoke.ps1 and summarises: result, clock panics, rejected-input warnings and frame hitches (> 250 ms) per process.
# The first failing run's logs are kept in %TEMP%\godot_smoke_fail.
$smoke = Join-Path $PSScriptRoot "run_smoke.ps1"
$dir = Join-Path $env:TEMP "godot_smoke"
$fail = Join-Path $env:TEMP "godot_smoke_fail"
Remove-Item $fail -Recurse -Force -ErrorAction SilentlyContinue
$env:HARNESS_CLOCK = "1"
$passes = 0
foreach ($i in 1..$Runs) {
	$a = @{ LatencyMs = $LatencyMs; LossPercent = $LossPercent; TimeoutSeconds = 200 }
	$a[$Scenario] = $true
	$out = & $smoke @a
	$r = ($out | Select-String -Pattern "SMOKE: (PASS|FAIL)").Matches[0].Groups[1].Value
	$logs = Get-Content (Join-Path $dir "host.out"), (Join-Path $dir "client.out"), (Join-Path $dir "host.err"), (Join-Path $dir "client.err") -ErrorAction SilentlyContinue
	$stale = ($logs | Select-String -Pattern "rejecting because older" | Measure-Object).Count
	$panics = ($logs | Select-String -Pattern "panic threshold" | Measure-Object).Count
	$hitchHost = ($logs | Select-String -Pattern "\[(HOST|CLIENT)\] HITCH" | Measure-Object).Count
	$lobbyLog = Join-Path $dir "lobby_hitch.log"
	$hitchLobby = if (Test-Path $lobbyLog) { (Get-Content $lobbyLog | Measure-Object).Count } else { 0 }
	"run ${i}: $r, clock panics $panics, rejected inputs $stale, hitches host+client $hitchHost lobby $hitchLobby"
	if ($r -eq "PASS") { $passes++ } elseif (-not (Test-Path $fail)) { Copy-Item $dir $fail -Recurse }
}
$env:HARNESS_CLOCK = $null
"SUMMARY: $passes of $Runs passed ($LatencyMs ms each way, $LossPercent% loss each way)"
