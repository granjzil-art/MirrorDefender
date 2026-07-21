param(
	[string]$GodotBinary = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotBinary)) {
	$KnownBinary = "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
	if (Test-Path -LiteralPath $KnownBinary) {
		$GodotBinary = $KnownBinary
	}
}

if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot executable not found. Pass -GodotBinary or set GODOT_BIN."
}

$Tests = @(
	"airborne_effects_test.gd",
	"camera_input_test.gd",
	"copy_mirror_test.gd",
	"directional_edge_barrier_test.gd",
	"level_reflection_test.gd",
	"path_spawn_pairing_test.gd",
	"path_terrain_color_test.gd",
	"robustness_baseline_test.gd",
	"tile_elements_and_rerouting_test.gd"
)

$FailedTests = [System.Collections.Generic.List[string]]::new()
foreach ($Test in $Tests) {
	Write-Host "`n=== $Test ==="
	$TestOutput = @(& $GodotBinary --headless --path $ProjectRoot --script "res://tests/$Test" 2>&1)
	$TestExitCode = $LASTEXITCODE
	$TestOutput | ForEach-Object { Write-Host $_ }
	$EngineErrors = @($TestOutput | Where-Object {
		$_ -match "^(SCRIPT ERROR|ERROR:|WARNING: .*leaked)"
	})
	if ($TestExitCode -ne 0 -or $EngineErrors.Count -gt 0) {
		$FailedTests.Add($Test)
	}
}

if ($FailedTests.Count -gt 0) {
	Write-Error ("{0} test suite(s) failed: {1}" -f $FailedTests.Count, ($FailedTests -join ", "))
	exit 1
}

Write-Host "`nAll $($Tests.Count) test suites passed."
exit 0
