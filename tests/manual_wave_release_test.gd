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
	var fixture := _make_runtime_fixture(level)
	var host: Node3D = fixture["host"]
	var manager: WaveManager = fixture["wave"]
	var spawned_names: Array[String] = []
	var released_numbers: Array[int] = []
	var started_numbers: Array[int] = []
	var next_numbers: Array[int] = []
	manager.enemy_spawned.connect(
		func(unit: EnemyUnit) -> void:
			spawned_names.append(unit.definition.display_name)
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
	_expect(manager.get_released_wave_count() == 0, "no wave is released implicitly")
	_expect(manager.get_next_wave_number() == 1 and manager.get_next_wave() == level.waves[0], "next-wave queries expose the first pending wave")

	_expect(manager.start_battle(), "start_battle compatibility entry releases the first wave")
	_expect(manager.get_released_wave_count() == 1 and released_numbers == [1], "one click releases exactly one wave")
	_expect(manager.get_current_wave_number() == 1 and manager.get_next_wave_number() == 2, "current and next wave numbers follow the release cursor")
	_expect(spawned_names == ["W1 Early"], "the earliest group starts immediately even with a non-zero authored delay")
	_expect(started_numbers == [1], "wave_started still reports the first successfully registered enemy")

	manager._process(1.99)
	_expect(spawned_names == ["W1 Early"], "later groups wait for their wave-relative delay")
	manager._process(0.01)
	_expect(spawned_names == ["W1 Early", "W1 Late"], "later groups preserve start_delay minus the wave minimum")

	_expect(manager.start_next_wave(), "the next wave can be released while earlier enemies remain")
	_expect(manager.get_released_wave_count() == 2 and released_numbers == [1, 2], "the second click releases only wave two")
	_expect(spawned_names.back() == "W2" and manager.get_active_enemy_count() == 3, "overlapping release keeps earlier enemies and starts wave two immediately")
	_expect(started_numbers == [1, 2], "each released wave emits wave_started only after its first spawn succeeds")

	await _clear_active_enemies(manager)
	_expect(manager.get_state() == WaveManager.State.ACTIVE, "clearing released waves cannot win while a wave remains unreleased")
	_expect(manager.get_next_wave_number() == 3 and manager.can_start_next_wave(), "the final unreleased wave remains explicitly available")

	_expect(manager.start_next_wave(), "the final wave can be released manually")
	_expect(manager.are_all_waves_released() and released_numbers == [1, 2, 3], "all-waves query changes only after the final release")
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
	third_wave.spawn_groups.append(_make_group(_make_enemy(&"w3", "W3"), path, spawn_point, 0.0))
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
