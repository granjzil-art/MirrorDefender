extends SceneTree

const RejectingTileManager := preload("res://tests/fixtures/RejectingTileManager.gd")

var _failures: int = 0
var _checks: int = 0
var _reentrant_target_removed_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[RobustnessBaseline] running")
	_test_level_validation()
	_test_editable_configuration_validation()
	_test_production_definition_smoke()
	_test_resource_manager_rejects_non_finite_transactions()
	await _test_atomic_loading_and_runtime_tile_isolation()
	await _test_height_aware_grid_picking()
	await _test_empty_geometry_is_safe()
	await _test_combat_registration_lifecycle()
	await _test_building_external_removal_cleanup()
	await _test_wave_spawn_failure_is_not_victory()
	_test_production_level_smoke()
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

func _test_editable_configuration_validation() -> void:
	var stats := BuildingLevelStats.new()
	_expect(stats.validate_configuration().is_empty(), "default building level stats validate")
	stats.cost = NAN
	_expect(not stats.validate_configuration().is_empty(), "building level rejects non-finite tuning")

	var building := BuildingDefinition.new()
	building.levels = [BuildingLevelStats.new(), null]
	_expect(not building.validate_configuration().is_empty(), "building validates every configured level")
	building.levels = [BuildingLevelStats.new()]
	_expect(building.validate_configuration().is_empty(), "complete building definition validates")
	building.aim_mode = 99
	building.visual_turn_speed_degrees = NAN
	_expect(not building.validate_configuration().is_empty(), "building rejects invalid orientation configuration")

	var enemy := EnemyDefinition.new()
	_expect(enemy.validate_configuration().is_empty(), "default enemy definition validates")
	enemy.attack_damage = INF
	_expect(not enemy.validate_configuration().is_empty(), "enemy rejects non-finite combat tuning")

	var mirror := CopyMirrorDefinition.new()
	_expect(mirror.validate_configuration().is_empty(), "default copy mirror definition validates")
	mirror.reflection_surface_offset_ratio = 0.5
	_expect(not mirror.validate_configuration().is_empty(), "copy mirror rejects an embedded reflection surface")

	var reflection := LevelReflectionDefinition.new()
	_expect(reflection.validate_configuration().is_empty(), "default level reflection definition validates")
	reflection.vertical_offset = NAN
	_expect(not reflection.validate_configuration().is_empty(), "level reflection rejects non-finite presentation tuning")

func _test_resource_manager_rejects_non_finite_transactions() -> void:
	var manager := ResourceManager.new()
	manager.main_resource = 200.0
	manager.gain(NAN, "invalid_gain")
	_expect(is_equal_approx(manager.main_resource, 200.0), "resource gain rejects NaN")
	_expect(not manager.spend(INF, "invalid_spend"), "resource spend rejects infinity")
	manager.set_building_resource_per_second(NAN)
	_expect(is_zero_approx(manager.get_building_resource_per_second()), "passive income rejects NaN")
	manager.free()

func _test_production_definition_smoke() -> void:
	var building_paths: Array[String] = [
		"res://resources/buildings/ArrowTower.tres",
		"res://resources/buildings/LaserTower.tres",
		"res://resources/buildings/Barrier.tres",
		"res://resources/buildings/EdgeBarrier.tres",
	]
	for path in building_paths:
		var building := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as BuildingDefinition
		_expect(building != null, "%s loads as BuildingDefinition" % path.get_file())
		if building != null:
			_expect(building.validate_configuration().is_empty(), "%s passes configuration validation" % path.get_file())

	var enemy_paths: Array[String] = [
		"res://resources/enemies/Grunt.tres",
		"res://resources/enemies/Runner.tres",
		"res://resources/enemies/Archer.tres",
		"res://resources/enemies/Flyer.tres",
	]
	for path in enemy_paths:
		var enemy := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as EnemyDefinition
		_expect(enemy != null, "%s loads as EnemyDefinition" % path.get_file())
		if enemy != null:
			_expect(enemy.validate_configuration().is_empty(), "%s passes configuration validation" % path.get_file())

	var mirror := ResourceLoader.load(
		"res://resources/mirrors/CopyMirror.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as CopyMirrorDefinition
	_expect(mirror != null, "CopyMirror.tres loads as CopyMirrorDefinition")
	if mirror != null:
		_expect(mirror.validate_configuration().is_empty(), "CopyMirror.tres passes configuration validation")

	var reflection := ResourceLoader.load(
		"res://resources/fx/LevelReflection.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as LevelReflectionDefinition
	_expect(reflection != null, "LevelReflection.tres loads as LevelReflectionDefinition")
	if reflection != null:
		_expect(reflection.validate_configuration().is_empty(), "LevelReflection.tres passes configuration validation")

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

	var assembly_failure_level: LevelResource = source_level.duplicate(true)
	assembly_failure_level.grid_shape = GridManager.Shape.SQUARE
	assembly_failure_level.grid_size = Vector2i(3, 3)
	tile_manager.set("reject_next_load", true)
	_expect(not loader.load_level(assembly_failure_level, "memory://assembly-failure"), "unexpected tile assembly rejection fails the load")
	_expect(loader.get_current_level() == source_level, "assembly rejection preserves the current level")
	_expect(grid.grid_shape == GridManager.Shape.HEX and grid.grid_size == previous_grid_size, "assembly rejection rolls back grid configuration")
	_expect(tile_manager.get_level_resource() == source_level, "assembly rejection preserves TileManager level state")
	_expect(tile_manager.get_tile(source_tile.cell) == previous_runtime_tile, "assembly rejection preserves the runtime tile map")

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

func _test_height_aware_grid_picking() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(2, 1))
	var raised_cell := Vector3i(1, 0, 0)
	grid.set_cell_height_resolver(
		func(cell: Vector3i) -> float:
			return 2.0 if cell == raised_cell else 0.0
	)
	var ray_origin := Vector3(2.5, 4.0, 0.0)
	var ray_direction := (Vector3.ZERO - ray_origin).normalized()
	var ground_hit := grid.raycast_ground_from_ray(ray_origin, ray_direction)
	_expect(grid.world_to_cell(ground_hit.pos) == Vector3i.ZERO, "legacy ground-plane ray would select the lower tile")
	var cell_pick := grid.pick_cell_from_ray(ray_origin, ray_direction)
	_expect(cell_pick.hit and cell_pick.cell == raised_cell, "surface ray selects the visible raised tile")
	_expect(is_equal_approx(cell_pick.pos.y, 2.0), "surface ray returns the raised tile's world height")
	var edge_pick := grid.pick_edge_from_ray(ray_origin, ray_direction)
	_expect(edge_pick.hit and edge_pick.cell == raised_cell, "edge picking uses the same raised surface")
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

	_reentrant_target_removed_count = 0
	combat_manager.target_removed.connect(_on_target_removed_reentrant.bind(combat_manager))
	var first_queued_target := CombatTarget.new()
	first_queued_target.debug_visual_enabled = false
	combat_manager.add_child(first_queued_target)
	var second_queued_target := CombatTarget.new()
	second_queued_target.debug_visual_enabled = false
	combat_manager.add_child(second_queued_target)
	_expect(
		combat_manager.register_target(first_queued_target) and combat_manager.register_target(second_queued_target),
		"multiple targets register for reentrant cleanup"
	)
	first_queued_target.queue_free()
	second_queued_target.queue_free()
	await process_frame
	_expect(_reentrant_target_removed_count == 2, "reentrant target_removed listeners observe each removal once")
	_expect(combat_manager.get_targets().is_empty(), "reentrant cleanup leaves an empty stable registry")
	combat_manager.queue_free()
	await process_frame

func _on_target_removed_reentrant(_target: CombatTarget, combat_manager: CombatManager) -> void:
	_reentrant_target_removed_count += 1
	combat_manager.get_targets()

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

func _test_production_level_smoke() -> void:
	var resource := ResourceLoader.load("res://resources/levels/M4DemoLevel.tres", "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_expect(resource is LevelResource, "M4DemoLevel is a LevelResource")
	if not resource is LevelResource:
		return
	var level: LevelResource = resource
	_expect(level.validate_runtime().is_empty(), "M4DemoLevel passes runtime validation")
	_expect(not level.paths.is_empty(), "M4DemoLevel keeps at least one playable path")
	_expect(not level.waves.is_empty(), "M4DemoLevel keeps at least one configured wave")

func _make_runtime_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := RejectingTileManager.new()
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
