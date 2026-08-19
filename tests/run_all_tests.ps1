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
	"campaign_preflight_test.gd",
	"acrylic_top_highlight_test.gd",
	"airborne_effects_test.gd",
	"ballistic_stuff_blocking_test.gd",
	"base_footprint_test.gd",
	"building_action_panel_test.gd",
	"building_rotation_repeat_test.gd",
	"camera_input_test.gd",
	"copy_mirror_test.gd",
	"crossbow_tower_test.gd",
	"directional_edge_barrier_test.gd",
	"enemy_health_bar_test.gd",
	"enemy_animation_states_test.gd",
	"enemy_model_assets_test.gd",
	"enemy_spawn_interval_jitter_test.gd",
	"enemy_specialists_test.gd",
	"foliage_shadow_test.gd",
	"grass_terrain_reference_test.gd",
	"initial_layout_persistence_test.gd",
	"level_reflection_test.gd",
	"level_select_test.gd",
	"level1_wave_balance_test.gd",
	"level1_special_enemy_addition_test.gd",
	"level234_wave_balance_test.gd",
	"level1_sky_decoration_test.gd",
	"level_celestial_decoration_test.gd",
	"lighting_display_case_test.gd",
	"laser_tower_status_test.gd",
	"mace_tower_test.gd",
	"manual_wave_and_level_flow_test.gd",
	"manual_wave_release_test.gd",
	"wave_completion_reward_test.gd",
	"missile_tower_test.gd",
	"miniature_dof_test.gd",
	"model_asset_contract_test.gd",
	"mirror_placement_cooldown_test.gd",
	"mirror_body_selection_test.gd",
	"mirror_refund_test.gd",
	"mirror_upgrade_test.gd",
	"path_spawn_pairing_test.gd",
	"path_placement_connectivity_test.gd",
	"path_terrain_color_test.gd",
	"performance_optimization_test.gd",
	"projectile_trajectory_preview_test.gd",
	"projectile_fire_mode_test.gd",
	"pulse_laser_tower_test.gd",
	"reflect_mirror_test.gd",
	"robustness_baseline_test.gd",
	"runtime_combat_data_editor_test.gd",
	"runtime_inspection_configuration_test.gd",
	"runtime_stuff_edit_session_test.gd",
	"runtime_stuff_editor_test.gd",
	"runtime_terrain_editor_test.gd",
	"runtime_ui_batch1_test.gd",
	"runtime_ui_batch2_test.gd",
	"runtime_ui_batch3_test.gd",
	"runtime_ui_batch4_test.gd",
	"runtime_ui_batch5_test.gd",
	"runtime_ui_batch6_test.gd",
	"sound_effect_system_test.gd",
	"stuff_catalog_test.gd",
	"stuff_catalog_authoring_test.gd",
	"stuff_catalog_manager_editor_test.gd",
	"stuff_runtime_test.gd",
	"terrain_stuff_contract_test.gd",
	"terrain_stuff_editor_test.gd",
	"terrain_runtime_test.gd",
	"tile_elements_and_rerouting_test.gd",
	"tower_wave_tutorial_test.gd",
	"tutorial_system_test.gd"
)

$FailedTests = [System.Collections.Generic.List[string]]::new()
foreach ($Test in $Tests) {
	Write-Host "`n=== $Test ==="
	# Windows PowerShell converts native stderr into non-terminating ErrorRecord
	# objects. Temporarily continue so warnings are captured and evaluated by the
	# explicit exit-code/engine-error policy below instead of aborting the suite.
	$ErrorActionPreference = "Continue"
	$TestOutput = @(& $GodotBinary --headless --path $ProjectRoot --script "res://tests/$Test" 2>&1)
	$TestExitCode = $LASTEXITCODE
	$ErrorActionPreference = "Stop"
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
