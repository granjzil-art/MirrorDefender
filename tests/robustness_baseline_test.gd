extends SceneTree

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[RobustnessBaseline] running")
	_test_level_validation()
	await _test_atomic_loading_and_runtime_tile_isolation()
	await _test_empty_geometry_is_safe()
	await _test_combat_registration_lifecycle()
	await _test_building_external_removal_cleanup()
	await _test_wave_spawn_failure_is_not_victory()
	_test_m4_demo_contract()
	if _failures == 0:
		print("[RobustnessBaseline] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[RobustnessBaseline] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_level_validation() -> void:
	var valid_level := _make_level()
	_expect(valid_level.validate_runtime().is_empty(), "minimal level passes runtime validation")
	var invalid_level: LevelResource = valid_level.duplicate(true)
	invalid_level.grid_cell_size = 0.0
	invalid_level.base_max_hp = NAN
	var errors := invalid_level.validate_runtime()
	_expect(errors.size() >= 2, "invalid finite/positive level parameters are rejected")

func _test_atomic_loading_and_runtime_tile_isolation() -> void:
	var fixture := _make_runtime_fixture()
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var loader: LevelLoader = fixture["loader"]
	var source_level := _make_level()
	var source_tile: TileCellData = source_level.tiles[0]
	_expect(loader.load_level(source_level, "memory://valid"), "valid level loads")
	var runtime_tile := tile_manager.get_tile(source_tile.cell)
	_expect(runtime_tile != null and runtime_tile != source_tile, "serialized tile is cloned for runtime")
	var occupant := Node.new()
	host.add_child(occupant)
	_expect(tile_manager.place_occupant(source_tile.cell, occupant), "runtime occupant can be placed")
	_expect(source_tile.occupant == null, "runtime occupancy does not leak into LevelResource")
	tile_manager.update_tile_height(source_tile.cell, 2)
	_expect(source_tile.height_level == 1, "runtime height changes do not mutate LevelResource")

	var second_fixture := _make_runtime_fixture()
	var second_host: Node3D = second_fixture["host"]
	var second_loader: LevelLoader = second_fixture["loader"]
	var second_tile_manager: TileManager = second_fixture["tile"]
	_expect(second_loader.load_level(source_level, "memory://second"), "same resource loads into a second runtime")
	_expect(second_tile_manager.get_occupant(source_tile.cell) == null, "two runtimes do not share occupancy")
	_expect(second_tile_manager.get_tile(source_tile.cell).height_level == 1, "two runtimes do not share terrain mutation")

	var previous_grid_size := grid.grid_size
	var previous_runtime_tile := tile_manager.get_tile(source_tile.cell)
	var invalid_level: LevelResource = source_level.duplicate(true)
	invalid_level.grid_size = Vector2i.ZERO
	_expect(not loader.load_level(invalid_level, "memory://invalid"), "invalid level is rejected")
	_expect(loader.get_current_level() == source_level, "rejected load preserves current level")
	_expect(grid.grid_size == previous_grid_size, "rejected load preserves grid configuration")
	_expect(tile_manager.get_tile(source_tile.cell) == previous_runtime_tile, "rejected load preserves runtime tiles")

	host.queue_free()
	second_host.queue_free()
	await process_frame

func _test_empty_geometry_is_safe() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.grid_shape = GridManager.Shape.SQUARE
	grid.grid_size = Vector2i.ZERO
	var grid_renderer := GridRenderer.new()
	host.add_child(grid_renderer)
	grid_renderer.set_grid(grid)
	var grid_mesh := grid_renderer.get_child(0) as MeshInstance3D
	_expect(grid_mesh != null and grid_mesh.mesh == null, "empty grid does not create an ImmediateMesh surface")

	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var path_manager := PathManager.new()
	host.add_child(path_manager)
	path_manager.configure(grid, tile_manager)
	var empty_level := _make_level()
	path_manager.load_level(empty_level)
	var path_mesh := path_manager.get_child(0) as MeshInstance3D
	_expect(path_mesh != null and path_mesh.mesh == null, "level without paths does not create an ImmediateMesh surface")
	host.queue_free()
	await process_frame

func _test_combat_registration_lifecycle() -> void:
	var combat_manager := CombatManager.new()
	root.add_child(combat_manager)
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat_manager.add_child(target)
	_expect(combat_manager.register_target(target), "target registers once")
	combat_manager.unregister_target(target)
	_expect(combat_manager.register_target(target), "target can re-register after explicit removal")
	_expect(combat_manager.get_targets().size() == 1, "re-registration does not duplicate target")
	target.queue_free()
	await process_frame
	_expect(combat_manager.get_targets().is_empty(), "external target deletion clears registry")
	combat_manager.queue_free()
	await process_frame

func _test_building_external_removal_cleanup() -> void:
	var fixture := _make_runtime_fixture()
	var host: Node3D = fixture["host"]
	var tile_manager: TileManager = fixture["tile"]
	var loader: LevelLoader = fixture["loader"]
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager.configure(fixture["grid"], tile_manager, resource_manager, combat_manager)
	var level := _make_level()
	resource_manager.apply_level_configuration(level)
	_expect(loader.load_level(level, "memory://building"), "building fixture level loads")
	var stats := BuildingLevelStats.new()
	stats.cost = 0.0
	var definition := BuildingDefinition.new()
	definition.kind = BuildingDefinition.Kind.ARROW_TOWER
	definition.levels.append(stats)
	var building := building_manager.place_building(Vector3i.ZERO, definition)
	_expect(building != null, "building is placed for lifecycle test")
	_expect(resource_manager.get_building_count() == 1, "placed building increments cap usage")
	building.queue_free()
	await process_frame
	_expect(building_manager.get_building(Vector3i.ZERO) == null, "external building deletion clears manager registry")
	_expect(tile_manager.get_occupant(Vector3i.ZERO) == null, "external building deletion clears tile occupancy")
	_expect(resource_manager.get_building_count() == 0, "external building deletion releases cap usage")
	host.queue_free()
	await process_frame

func _test_wave_spawn_failure_is_not_victory() -> void:
	var fixture := _make_runtime_fixture()
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var loader: LevelLoader = fixture["loader"]
	var level := _make_wave_level(0.1)
	_expect(loader.load_level(level, "memory://wave"), "wave fixture level loads")
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
	_expect(wave_manager.start_battle(), "valid delayed timeline starts")
	combat_manager.feature_enabled = false
	wave_manager._process(0.2)
	_expect(wave_manager.get_state() == WaveManager.State.CONFIG_ERROR, "failed spawn enters explicit configuration error")
	_expect(wave_manager.get_state() != WaveManager.State.VICTORY, "failed spawn cannot become false victory")
	_expect(wave_manager.get_active_enemy_count() == 0, "failed spawn leaves no active enemy")
	host.queue_free()
	await process_frame

func _test_m4_demo_contract() -> void:
	var resource := ResourceLoader.load("res://resources/levels/M4DemoLevel.tres", "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_expect(resource is LevelResource, "M4DemoLevel is a LevelResource")
	if not resource is LevelResource:
		return
	var level: LevelResource = resource
	_expect(level.validate_runtime().is_empty(), "M4DemoLevel passes runtime validation")
	var later_delays: Array[float] = []
	var has_archer := false
	for wave_index in range(level.waves.size()):
		var wave: WaveDefinition = level.waves[wave_index]
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group == null:
				continue
			if wave_index == 0:
				_expect(is_zero_approx(group.start_delay), "all first-wave groups start at delay zero")
			else:
				later_delays.append(group.start_delay)
			if group.enemy != null and group.enemy.enemy_id == &"archer":
				has_archer = true
	later_delays.sort()
	_expect(later_delays == [8.0, 9.0, 10.0], "later M4 groups preserve the 8/9/10 second schedule")
	_expect(has_archer, "M4DemoLevel includes the Archer test enemy")

func _make_runtime_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"loader": loader,
	}

func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.HEX
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(2, 2)
	level.height_levels = 3
	level.height_step = 0.45
	level.base_cell = Vector3i.ZERO
	var tile := TileCellData.new()
	tile.configure(Vector3i.ZERO, TileCellData.TileType.BUILDABLE, 1)
	level.tiles.append(tile)
	return level

func _make_wave_level(first_delay: float) -> LevelResource:
	var level := _make_level()
	var path := PathDefinition.new()
	path.path_id = &"test"
	path.display_name = "Test Path"
	path.cells = [Vector3i(-1, 0, 1), Vector3i.ZERO]
	var spawn_point := SpawnPointDefinition.new()
	spawn_point.spawn_id = &"test"
	spawn_point.display_name = "Test Spawn"
	spawn_point.cell = path.get_start_cell()
	var enemy := EnemyDefinition.new()
	enemy.enemy_id = &"test"
	enemy.display_name = "Test Enemy"
	var group := SpawnGroupDefinition.new()
	group.enemy = enemy
	group.count = 1
	group.interval = 1.0
	group.start_delay = first_delay
	group.path = path
	group.spawn_point = spawn_point
	var wave := WaveDefinition.new()
	wave.display_name = "Test Wave"
	wave.spawn_groups.append(group)
	level.paths.append(path)
	level.spawn_points.append(spawn_point)
	level.waves.append(wave)
	return level

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
