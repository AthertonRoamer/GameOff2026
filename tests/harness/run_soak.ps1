param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[int]$Runs = 4,
	[int]$Seconds = 90, #how long each game runs
	[int]$Clients = 2, #3 players = -Clients 2
	[switch]$Move, #players walk squares instead of standing still
	[string]$Label = "soak" #name for the kept logs: %TEMP%\godot_soak\<Label>_run<n>
)

# Plays the real game for a while, several times, and reports how well sync held up in each run:
# late-data messages from netfox (rejected as older than its 64 tick history), frame hitches (> 250 ms) and netfox clock panics,
# per process. Every run's logs are kept, with a CLOCK line per second per process (HARNESS_CLOCK).
$smoke = Join-Path $PSScriptRoot "run_smoke.ps1"
$dir = Join-Path $env:TEMP "godot_smoke"
$keep = Join-Path $env:TEMP "godot_soak"
New-Item -ItemType Directory -Force $keep | Out-Null
$env:HARNESS_CLOCK = "1"
foreach ($i in 1..$Runs) {
	$a = @{ Godot = $Godot; SoakSeconds = $Seconds; Clients = $Clients; TimeoutSeconds = ($Seconds + 150) }
	if ($Move) { $a["SoakMove"] = $true }
	$out = & $smoke @a
	$r = ($out | Select-String -Pattern "SMOKE: (PASS|FAIL)").Matches[0].Groups[1].Value
	$parts = @()
	foreach ($name in @("host") + (1..$Clients | ForEach-Object { if ($_ -eq 1) { "client" } else { "client$_" } })) {
		$file = Join-Path $dir "$name.out"
		$late = (Select-String -Path $file -Pattern "older than 64|past the history" -ErrorAction SilentlyContinue | Measure-Object).Count
		$hitch = (Select-String -Path $file -Pattern "\] HITCH" -ErrorAction SilentlyContinue | Measure-Object).Count
		$panic = (Select-String -Path $file -Pattern "panic" -ErrorAction SilentlyContinue | Measure-Object).Count
		$first = (Select-String -Path $file -Pattern "\[@(\d+)\]\[#\d+\].*(older than 64|past the history)" -ErrorAction SilentlyContinue | Select-Object -First 1)
		$start = (Select-String -Path $file -Pattern "game starting on tick (\d+)" -ErrorAction SilentlyContinue | Select-Object -First 1)
		$when = if ($first -and $start) { " from +$([int]$first.Matches[0].Groups[1].Value - [int]$start.Matches[0].Groups[1].Value) ticks" } else { "" }
		$parts += "${name}: late $late$when, hitches $hitch, panics $panic"
	}
	$lobbyLog = Join-Path $dir "lobby_hitch.log"
	$lobbyHitch = if (Test-Path $lobbyLog) { (Get-Content $lobbyLog | Measure-Object).Count } else { 0 }
	"$Label run ${i}: $r | $($parts -join ' | ') | lobby hitches $lobbyHitch"
	$target = Join-Path $keep "${Label}_run$i"
	Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
	Copy-Item $dir $target -Recurse
}
$env:HARNESS_CLOCK = $null
