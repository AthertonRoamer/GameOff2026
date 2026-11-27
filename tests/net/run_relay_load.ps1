## Load-tests the noray relay with made-up traffic (see relay_load.gd). Takes about two minutes. It loads the shared noray server: not during a playtest.
## Two players join through the relay from this computer, so the traffic goes up and down this connection twice.
param(
	[string]$Godot = "C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
	[string]$OutDir = "$env:TEMP\relay_load"
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
New-Item -ItemType Directory -Force $OutDir | Out-Null
$oid = Join-Path $OutDir "oid.txt"
Remove-Item $oid -ErrorAction SilentlyContinue
function Start-Side($role) {
	Start-Process $Godot -ArgumentList "--headless", "--max-fps", "240", "--path", "`"$project`"", "res://tests/net/relay_load.tscn", "--", $role, "`"$oid`"" -PassThru -NoNewWindow -RedirectStandardOutput "$OutDir\$role.out" -RedirectStandardError "$OutDir\$role.err"
}
$hostSide = Start-Side "host"
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path $oid) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
if (-not (Test-Path $oid)) { "the host never registered with noray"; Get-Content "$OutDir\host.out"; $hostSide.Kill(); exit 1 }
Start-Sleep -Milliseconds 500
$clientSide = Start-Side "client"
if (-not $clientSide.WaitForExit(240000)) { $clientSide.Kill() }
if (-not $hostSide.WaitForExit(15000)) { $hostSide.Kill() }
Get-Content "$OutDir\client.out" | Where-Object { $_ -match "^\[CLIENT\]" }
Get-Content "$OutDir\host.out" | Where-Object { $_ -match "^\[HOST\]" }
