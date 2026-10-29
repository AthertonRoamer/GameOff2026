param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[int]$TimeoutSeconds = 90
)

# Launches a host and a client harness process, waits for both, prints their output and a PASS/FAIL line.
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:TEMP "godot_smoke"
New-Item -ItemType Directory -Force $logDir | Out-Null
$hostOut = Join-Path $logDir "host.out"; $hostErr = Join-Path $logDir "host.err"
$clientOut = Join-Path $logDir "client.out"; $clientErr = Join-Path $logDir "client.err"
Remove-Item $hostOut, $hostErr, $clientOut, $clientErr -ErrorAction SilentlyContinue

$scene = "res://tests/harness/harness.tscn"
$hostProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList "--path", "`"$project`"", $scene, "--", "--role", "host" `
	-RedirectStandardOutput $hostOut -RedirectStandardError $hostErr

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not ((Test-Path $hostOut) -and (Select-String -Path $hostOut -Pattern "HOST_READY|FAIL" -Quiet))) {
	Start-Sleep -Milliseconds 500
}

$clientProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList "--path", "`"$project`"", $scene, "--", "--role", "client" `
	-RedirectStandardOutput $clientOut -RedirectStandardError $clientErr

while ((Get-Date) -lt $deadline -and -not ($hostProc.HasExited -and $clientProc.HasExited)) {
	Start-Sleep -Milliseconds 500
}

foreach ($p in @($hostProc, $clientProc)) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
Start-Sleep -Seconds 1

"----- HOST -----"; Get-Content $hostOut | Where-Object { $_ -match '^\[HOST\]|ERROR|SCRIPT' }
"----- CLIENT -----"; Get-Content $clientOut | Where-Object { $_ -match '^\[CLIENT\]|ERROR|SCRIPT' }
"----- STDERR (host/client) -----"; Get-Content $hostErr, $clientErr -ErrorAction SilentlyContinue | Select-Object -First 20

$ok = (Select-String -Path $hostOut -Pattern "\[HOST\] DONE" -Quiet) -and (Select-String -Path $clientOut -Pattern "\[CLIENT\] DONE" -Quiet)
if ($ok) { "SMOKE: PASS" } else { "SMOKE: FAIL" }
