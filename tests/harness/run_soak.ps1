param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[int]$Runs = 4,
	[int]$Seconds = 90, #how long each game runs
	[int]$Clients = 2, #3 players = -Clients 2
	[switch]$Move, #players walk squares instead of standing still
	[switch]$NoLogLimit, #print every netfox warning (upstream behaviour) instead of rate limiting them, for comparison
	[int]$MaxLate = 100, #a process with more late-data events than this in one run counts as a sync failure (a cascade has thousands)
	[string]$Label = "soak" #name for the kept logs: %TEMP%\godot_soak\<Label>_run<n>
)

# Plays the real game for a while, several times, and reports how well sync held up in each run, per process (lobby included):
# late-data events from netfox (data rejected as older than its 64 tick history, or rollbacks past it), frame hitches (> 250 ms),
# late clock-log timers (CLOCKGAP) and netfox clock panics. Every run's logs are kept, with a CLOCK line per second per process.
# Ends with "SOAK: n of m runs kept sync".
$smoke = Join-Path $PSScriptRoot "run_smoke.ps1"
$dir = Join-Path $env:TEMP "godot_smoke"
$keep = Join-Path $env:TEMP "godot_soak"
New-Item -ItemType Directory -Force $keep | Out-Null
$env:HARNESS_CLOCK = "1"
if ($NoLogLimit) { $env:HARNESS_NO_LOG_LIMIT = "1" }

function Count-Late($file) {
	#each printed line is one event, plus the copies the rate limit skipped and reported on it
	$total = 0
	foreach ($m in (Select-String -Path $file -Pattern "older than 64|past the history" -ErrorAction SilentlyContinue)) {
		if ($m.Line -match "^(WARNING|ERROR): ") { continue } #the debugger copy of a printed line
		$total += 1
		if ($m.Line -match "and (\d+) more like this") { $total += [int]$Matches[1] }
	}
	return $total
}

$kept = 0
foreach ($i in 1..$Runs) {
	$a = @{ Godot = $Godot; SoakSeconds = $Seconds; Clients = $Clients; TimeoutSeconds = ($Seconds + 150) }
	if ($Move) { $a["SoakMove"] = $true }
	$out = & $smoke @a
	$r = ($out | Select-String -Pattern "SMOKE: (PASS|FAIL)").Matches[0].Groups[1].Value
	$parts = @()
	$synced = $true
	$names = @("lobby", "host") + (1..$Clients | ForEach-Object { if ($_ -eq 1) { "client" } else { "client$_" } })
	foreach ($name in $names) {
		$file = if ($name -eq "lobby") { Join-Path $dir "lobby.log" } else { Join-Path $dir "$name.out" }
		$late = Count-Late $file
		if ($late -gt $MaxLate) { $synced = $false }
		$hitch = (Select-String -Path $file -Pattern "\] HITCH" -ErrorAction SilentlyContinue | Measure-Object).Count
		$gaps = (Select-String -Path $file -Pattern "\] CLOCKGAP" -ErrorAction SilentlyContinue | Measure-Object).Count
		$panic = (Select-String -Path $file -Pattern "above panic threshold" -ErrorAction SilentlyContinue | Where-Object { $_.Line -notmatch "^WARNING: " } | Measure-Object).Count
		$first = (Select-String -Path $file -Pattern "\[@(\d+)\]\[#\d+\].*(older than 64|past the history)" -ErrorAction SilentlyContinue | Select-Object -First 1)
		$start = (Select-String -Path $file -Pattern "game starting on tick (\d+)" -ErrorAction SilentlyContinue | Select-Object -First 1)
		$when = if ($first -and $start) { " from +$([int]$first.Matches[0].Groups[1].Value - [int]$start.Matches[0].Groups[1].Value)" } else { "" }
		$parts += "${name}: late $late$when, hitch $hitch, gap $gaps, panic $panic"
	}
	if ($synced) { $kept++ }
	"$Label run ${i}: $r, sync $(if ($synced) { 'OK' } else { 'LOST' }) | $($parts -join ' | ')"
	$target = Join-Path $keep "${Label}_run$i"
	Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
	Copy-Item $dir $target -Recurse
}
$env:HARNESS_CLOCK = $null
$env:HARNESS_NO_LOG_LIMIT = $null
"SOAK: $kept of $Runs runs kept sync"
