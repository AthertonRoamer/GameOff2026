param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[double]$LatencyMs = 80,
	[double]$LossPercent = 5
)

# Runs tests/net/channel_probe.tscn as a server and a client with the latency proxy in between, and prints the server's report.
$project = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:TEMP "godot_probe"
New-Item -ItemType Directory -Force $logDir | Out-Null
$serverOut = Join-Path $logDir "server.out"
Remove-Item $serverOut -ErrorAction SilentlyContinue

$serverProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList "--headless", "--path", "`"$project`"", "res://tests/net/channel_probe.tscn", "--", "--role", "server", "--port", "5200" `
	-RedirectStandardOutput $serverOut -RedirectStandardError (Join-Path $logDir "server.err")
$proxyProc = Start-Process py -PassThru -NoNewWindow `
	-ArgumentList "-3", "`"$project\tests\harness\latency_proxy.py`"", "--listen", "5201", "--target", "5200", "--delay-ms", $LatencyMs, "--loss", $LossPercent `
	-RedirectStandardOutput (Join-Path $logDir "proxy.out") -RedirectStandardError (Join-Path $logDir "proxy.err")
Start-Sleep -Seconds 3
$clientProc = Start-Process $Godot -WorkingDirectory $project -PassThru -NoNewWindow `
	-ArgumentList "--headless", "--path", "`"$project`"", "res://tests/net/channel_probe.tscn", "--", "--role", "client", "--port", "5201" `
	-RedirectStandardOutput (Join-Path $logDir "client.out") -RedirectStandardError (Join-Path $logDir "client.err")

$deadline = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $deadline -and -not $serverProc.HasExited) { Start-Sleep -Milliseconds 500 }
foreach ($p in @($serverProc, $clientProc, $proxyProc)) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
"latency ${LatencyMs} ms each way, loss ${LossPercent}% each way"
Get-Content $serverOut | Where-Object { $_ -match "^PROBE" }
