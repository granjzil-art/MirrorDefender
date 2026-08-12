extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[ManualWaveRelease] running")
	await _test_manual_release_flow()
	await _test_preflight_failure_is_not_victory()
	if _failures == 0:
		print("[ManualWaveRelease] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[ManualWaveRelease] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_manual_release_flow() -> void:
	var level := _make_three_wave_level()
	_expect(is_equal_approx(level.get_enemy_hp_multiplier(-1), 1.0), "debug spawns remain at base HP")
	_expect(is_equal_approx(level.get_enemy_hp_multiplier(100), 5.0), "long levels respect the configured HP multiplier cap")
	var fixture := _make_runtime_fixture(level)
	var host: Node3D = fixture["host"]
	var manager: WaveManager = fixture["wave"]
	var path_manager: PathManager = fixture["path"]
	path_manager.set_debug_paths_visible(false)
	var path_display := RuntimePathDisplayController.new()
	host.add_child(path_display)
	var flow_renderer := path_display.get_flow_renderer()
	flow_renderer.flow_speed = 2.0
	flow_renderer.segment_length = 0.5
	flow_renderer.restart_delay = 0.25
	path_display.configure(manager, path_manager)
	var continuous_preview := path_display.get_continuous_preview()
	var spawned_names: Array[String] = []
	var spawned_max_hp: Array[float] = []
	var released_numbers: Array[int] = []
	var started_numbers: Array[int] = []
	var next_numbers: Array[int] = []
	manager.enemy_spawned.connect(
		func(unit: EnemyUnit) -> void:
			spawned_names.append(unit.definition.display_name)
			spawned_max_hp.append(unit.max_hp)
	)
	manager.wave_released.connect(
		func(wave_number: int, _wave: WaveDefinition) -> void:
			released_numbers.append(wave_number)
	)
	manager.wave_started.connect(
		func(wave_number: int, _wave: WaveDefinition) -> void:
			started_numbers.append(wave_number)
	)
	manager.next_wave_changed.connect(
		func(wave_number: int, _wave: WaveDefinition) -> void:
			next_numbers.append(wave_number)
	)

	manager._process(30.0)
	_expect(manager.get_active_enemy_count() == 0, "no enemy spawns before the first manual release")
	_expect(manager.should_show_continuous_paths(), "paths remain continuous before the first manual release")
	var first_requests := manager.get_next_wave_path_requests()
	_expect(
		first_requests.size() == 1 and first_requests[0].get("path") == level.paths[0],
		"the pre-wave path request set contains only wave one's route"
	)
	_expect(not path_manager.is_runtime_path_display_visible(), "the legacy yellow runtime layer stays hidden before wave one")
	_expect(path_manager._path_mesh.mesh == null, "the legacy yellow route geometry is not used for continuous presentation")
	_expect(continuous_preview.get_active_path_count() == 1, "continuous presentation reuses the hover-style route preview")
	_expect(not continuous_preview.get_marker_positions().is_empty(), "continuous presentation includes hover-style flow markers")
	path_display.set_external_preview_active(true)
	_expect(continuous_preview.get_active_path_count() == 0, "an external hover preview suppresses the duplicate continuous overlay")
	path_display.set_external_preview_active(false)
	_expect(continuous_preview.get_active_path_count() == 1, "clearing external hover restores the continuous preview")
	_expect(manager.get_released_wave_count() == 0, "no wave is released implicitly")
	_expect(manager.get_next_wave_number() == 1 and manager.get_next_wave() == level.waves[0], "next-wave queries expose the first pending wave")

	_expect(manager.start_battle(), "start_battle compatibility entry releases the first wave")
	_expect(manager.is_wave_action_active(), "a released wave with living or pending enemies is action-active")
	_expect(path_display.get_display_phase() == RuntimePathDisplayController.DisplayPhase.FLOWING, "active combat changes path display to moving-segment mode")
	_expect(not path_manager.is_runtime_path_display_visible(), "active combat hides the continuous whole-route layer")
	_expect(continuous_preview.get_active_path_count() == 0, "active combat clears the inter-wave hover-style preview")
	_expect(flow_renderer.get_active_path_ids() == [&"manual_wave_path"], "moving hints are filtered to active authored paths")
	_expect(flow_renderer.has_visible_geometry() and flow_renderer.get_visible_segment_count() == 1, "one short segment starts at the active path origin")
	var initial_heads := flow_renderer.get_segment_head_positions()
	path_display.advance_display_time(0.30)
	var moved_heads := flow_renderer.get_segment_head_positions()
	_expect(not initial_heads.is_empty() and not moved_heads.is_empty() and initial_heads[0].distance_to(moved_heads[0]) > 0.1, "the short segment advances from spawn toward the base")
	path_display.advance_display_time(0.80)
	_expect(not flow_renderer.has_visible_geometry(), "the segment clears during its configurable restart gap")
	path_display.advance_display_time(0.20)
	_expect(flow_renderer.has_visible_geometry(), "the segment restarts from the path origin after the gap")
	_expect(path_manager._path_mesh.mesh == null, "moving hints never restore continuous whole-route geometry during combat")
	_expect(manager.get_released_wave_count() == 1 and released_numbers == [1], "one click releases exactly one wave")
	_expect(manager.get_current_wave_number() == 1 and manager.get_next_wave_number() == 2, "current and next wave numbers follow the release cursor")
	_expect(spawned_names == ["W1 Early"], "the earliest group starts immediately even with a non-zero authored delay")
	_expect(is_equal_approx(spawned_max_hp[0], 100.0), "wave one keeps the authored base HP")
	_expect(started_numbers == [1], "wave_started still reports the first successfully registered enemy")

	manager._process(1.99)
	_expect(spawned_names == ["W1 Early"], "later groups wait for their wave-relative delay")
	manager._process(0.01)
	_expect(spawned_names == ["W1 Early", "W1 Late"], "later groups preserve start_delay minus the wave minimum")

	_expect(manager.start_next_wave(), "the next wave can be released while earlier enemies remain")
	_expect(manager.get_released_wave_count() == 2 and released_numbers == [1, 2], "the second click releases only wave two")
	_expect(spawned_names.back() == "W2" and manager.get_active_enemy_count() == 3, "overlapping release keeps earlier enemies and starts wave two immediately")
	_expect(is_equal_approx(spawned_max_hp.back(), 110.0), "wave two applies one HP growth step")
	_expect(started_numbers == [1, 2], "each released wave emits wave_started only after its first spawn succeeds")

	await _clear_active_enemies(manager)
	_expect(manager.get_state() == WaveManager.State.ACTIVE, "clearing released waves cannot win while a wave remains unreleased")
	_expect(manager.should_show_continuous_paths(), "a cleared interval with another unreleased wave is a continuous-path interval")
	_expect(flow_renderer.is_finishing(), "a generated short segment enters a finishing pass when the wave ends")
	_expect(flow_renderer.has_visible_geometry(), "the wave-end transition keeps the generated segment visible")
	path_display.advance_display_time(0.40)
	_expect(flow_renderer.has_visible_geometry(), "the finishing segment continues travelling instead of disappearing abruptly")
	path_display.advance_display_time(0.70)
	_expect(not flow_renderer.is_finishing(), "the finishing pass ends only after the segment leaves its target")
	_expect(path_display.get_display_phase() == RuntimePathDisplayController.DisplayPhase.CONTINUOUS, "the controller enters inter-wave mode after the short segment finishes")
	var final_wave_requests := manager.get_next_wave_path_requests()
	_expect(
		final_wave_requests.size() == 1 and final_wave_requests[0].get("path") == level.paths[1],
		"the inter-wave request set advances to the final wave's distinct route"
	)
	_expect(continuous_preview.get_active_path_count() == 1, "only the next wave route uses hover-style presentation throughout the wave interval")
	_expect(not path_manager.is_runtime_path_display_visible() and path_manager._path_mesh.mesh == null, "wave intervals never restore the legacy yellow line")
	_expect(manager.get_next_wave_number() == 3 and manager.can_start_next_wave(), "the final unreleased wave remains explicitly available")

	_expect(manager.start_next_wave(), "the final wave can be released manually")
	_expect(is_equal_approx(spawned_max_hp.back(), 121.0), "wave three compounds the configured HP growth")
	_expect(manager.are_all_waves_released() and released_numbers == [1, 2, 3], "all-waves query changes only after the final release")
	_expect(manager.get_next_wave_path_requests().is_empty(), "no continuous path request remains after the final release")
	_expect(next_numbers == [2, 3, 0], "next-wave signal advances after each release and reports zero after the last")
	_expect(manager.get_state() == WaveManager.State.ACTIVE, "the battle does not win while the final wave enemy remains")
	var debug_result := manager.spawn_debug_enemy(_make_enemy(&"debug", "Debug"), level.paths[0])
	_expect(bool(debug_result["success"]) and manager.get_released_wave_count() == 3, "debug spawning does not change authored wave release progress")
	await _clear_enemy_named(manager, "W3")
	_expect(manager.get_state() == WaveManager.State.ACTIVE and manager.get_active_enemy_count() == 1, "a debug-spawned enemy still blocks final clear victory")
	await _clear_active_enemies(manager)
	_expect(manager.get_state() == WaveManager.State.VICTORY, "victory occurs after all waves are released, spawned, and every enemy is cleared")
	_expect(not manager.start_next_wave() and not manager.can_start_next_wave(), "no wave can be released after the final wave")
	var terminal_spawn := manager.spawn_debug_enemy(_make_enemy(&"terminal", "Terminal"), level.paths[0])
	_expect(not bool(terminal_spawn.get("success", false)), "debug spawning is rejected after victory")
	var base_core: BaseCore = fixture["base"]
	base_core.take_damage(base_core.max_hp * 2.0)
	_expect(manager.get_state() == WaveManager.State.VICTORY, "base damage cannot reverse victory into defeat")

	host.queue_free()
	await process_frame


func _test_preflight_failure_is_not_victory() -> void:
	var level := _make_three_wave_level()
	var fixture := _make_runtime_fixture(level)
	var host: Node3D = fixture["host"]
	var manager: WaveManager = fixture["wave"]
	var combat_manager: CombatManager = fixture["combat"]
	combat_manager.feature_enabled = false
	_expect(not manager.start_next_wave(), "runtime preflight rejects an unavailable combat dependency")
	_expect(manager.get_state() == WaveManager.State.CONFIG_ERROR, "preflight failure enters CONFIG_ERROR")
	_expect(manager.get_state() != WaveManager.State.VICTORY, "configuration failure cannot become a false victory")
	_expect(manager.get_released_wave_count() == 0 and manager.get_active_enemy_count() == 0, "failed preflight releases no wave and leaves no enemy")
	_expect(not manager.start_next_wave(), "repeated release calls are safe after configuration failure")
	host.queue_free()
	await process_frame


func _make_runtime_fixture(level: LevelResource) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	tile_manager.load_level(level)
	var path_manager := PathManager.new()
	host.add_child(path_manager)
	path_manager.configure(grid, tile_manager)
	path_manager.load_level(level)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	resource_manager.apply_level_configuration(level)
	var base_core := BaseCore.new()
	host.add_child(base_core)
	base_core.configure(grid, tile_manager)
	base_core.load_level(level)
	var wave_manager := WaveManager.new()
	host.add_child(wave_manager)
	wave_manager.configure(path_manager, combat_manager, resource_manager, base_core)
	wave_manager.load_level(level)
	return {
		"host": host,
		"wave": wave_manager,
		"combat": combat_manager,
		"base": base_core,
		"path": path_manager,
	}


func _make_three_wave_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(3, 1)
	level.base_cell = Vector3i(2, 0, 0)
	var path := PathDefinition.new()
	path.path_id = &"manual_wave_path"
	path.display_name = "Manual Wave Path"
	path.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]
	var spawn_point := SpawnPointDefinition.new()
	spawn_point.spawn_id = &"manual_wave_spawn"
	spawn_point.display_name = "Manual Wave Spawn"
	spawn_point.cell = path.get_start_cell()
	path.spawn_point = spawn_point
	level.paths.append(path)
	level.spawn_points.append(spawn_point)
	var final_path := PathDefinition.new()
	final_path.path_id = &"manual_final_wave_path"
	final_path.display_name = "Manual Final Wave Path"
	final_path.cells = path.cells.duplicate()
	final_path.spawn_point = spawn_point
	level.paths.append(final_path)

	var first_wave := WaveDefinition.new()
	first_wave.display_name = "Wave 1"
	first_wave.spawn_groups.append(_make_group(_make_enemy(&"w1_early", "W1 Early"), path, spawn_point, 5.0))
	first_wave.spawn_groups.append(_make_group(_make_enemy(&"w1_late", "W1 Late"), path, spawn_point, 7.0))
	level.waves.append(first_wave)

	var second_wave := WaveDefinition.new()
	second_wave.display_name = "Wave 2"
	second_wave.spawn_groups.append(_make_group(_make_enemy(&"w2", "W2"), path, spawn_point, 30.0))
	level.waves.append(second_wave)

	var third_wave := WaveDefinition.new()
	third_wave.display_name = "Wave 3"
	third_wave.spawn_groups.append(_make_group(_make_enemy(&"w3", "W3"), final_path, spawn_point, 0.0))
	level.waves.append(third_wave)
	return level


func _make_enemy(enemy_id: StringName, display_name: String) -> EnemyDefinition:
	var enemy := EnemyDefinition.new()
	enemy.enemy_id = enemy_id
	enemy.display_name = display_name
	return enemy


func _make_group(
	enemy: EnemyDefinition,
	path: PathDefinition,
	spawn_point: SpawnPointDefinition,
	start_delay: float
) -> SpawnGroupDefinition:
	var group := SpawnGroupDefinition.new()
	group.enemy = enemy
	group.path = path
	group.spawn_point = spawn_point
	group.count = 1
	group.interval = 1.0
	group.start_delay = start_delay
	return group


func _clear_enemy_named(manager: WaveManager, display_name: String) -> void:
	for child in manager.get_children():
		if child is EnemyUnit and child.definition.display_name == display_name:
			child.queue_free()
	await process_frame
	manager._process(0.0)


func _clear_active_enemies(manager: WaveManager) -> void:
	for child in manager.get_children():
		if child is EnemyUnit:
			child.queue_free()
	await process_frame
	manager._process(0.0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
