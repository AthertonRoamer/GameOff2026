param(
	[double]$LatencyMs = 120,
	[int]$TimeoutSeconds = 120
)

# Runs the moving-target scenario with lag compensation on and off, through the latency proxy, and compares how many shots land.
$smoke = Join-Path $PSScriptRoot "run_smoke.ps1"

function Get-Hits($lines) {
	$line = $lines | Where-Object { $_ -match "MOVING: .*: (\d+) shots hit" } | Select-Object -First 1
	if ($null -eq $line) { return $null }
	return [int]$Matches[1]
}

$on = & $smoke -Moving -LatencyMs $LatencyMs -TimeoutSeconds $TimeoutSeconds
$off = & $smoke -Moving -NoLagComp -LatencyMs $LatencyMs -TimeoutSeconds $TimeoutSeconds
$hitsOn = Get-Hits $on
$hitsOff = Get-Hits $off
$on | Where-Object { $_ -match "^MOVING|SMOKE" }
$off | Where-Object { $_ -match "^MOVING|SMOKE" }
if ($null -eq $hitsOn -or $null -eq $hitsOff) {
	"LAGCOMP CHECK: FAIL (no result)"
} elseif ($LatencyMs -ge 80 -and $hitsOn -le $hitsOff) {
	"LAGCOMP CHECK: FAIL ($hitsOn hits with lag compensation vs $hitsOff without, $LatencyMs ms each way: it should clearly help at this latency)"
} elseif ($hitsOn -lt $hitsOff) {
	"LAGCOMP CHECK: FAIL ($hitsOn hits with lag compensation vs $hitsOff without, $LatencyMs ms each way: it made things worse)"
} else {
	"LAGCOMP CHECK: PASS ($hitsOn hits with lag compensation vs $hitsOff without, $LatencyMs ms each way)"
}
