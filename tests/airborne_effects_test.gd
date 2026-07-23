extends SceneTree

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[AirborneEffects] running")
	_test_flying_definition_and_height()
	await _test_tile_effect_filtering_and_navigation()
	await _test_building_effect_filtering()
	if _failures == 0:
		print("[AirborneEffects] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[AirborneEffects] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_flying_definition_and_height() -> void:
	var definition := ResourceLoader.load("res://resources/enemies/Flyer.tres") as EnemyDefinition
	_expect(definition != null and definition.is_airborne, "flying test enemy loads with the airborne classification")
	if definition == null:
		return
	var unit := EnemyUnit.new()
	unit.debug_visual_enabled = false
	unit.configure_unit(
		definition,
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT]),
		[Vector3i.ZERO, Vector3i(1, 0, 0)]
	)
	_expect(unit.is_airborne_unit(), "EnemyUnit copies the airborne classification from EnemyDefinition")
	_expect(is_equal_approx(unit.position.y, definition.flight_height), "airborne path points receive the configured flight height")
	unit.free()

func _test_tile_effect_filtering_and_navigation() -> void:
	var level := _make_level()
	var spike := SpikeTileEffect.new()
	spike.affects_airborne = false
	spike.damage_per_second = 20.0
	var void_effect := VoidTileEffect.new()
	void_effect.affects_airborne = false
	var rock := RockTileEffect.new()
	rock.affects_airborne = false
	level.store_tile(_make_effect_tile(Vector3i.ZERO, &"spike_test", spike))
	level.store_tile(_make_effect_tile(Vector3i(1, 0, 0), &"void_test", void_effect))
	level.store_tile(_make_effect_tile(Vector3i(2, 0, 0), &"rock_test", rock))
	var original := _make_path(&"original", [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)])
	var detour := _make_path(&"detour", [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0), Vector3i(3, 0, 0)])
	level.paths = [original, detour]
	level.base_cell = Vector3i(3, 0, 0)
	_attach_path_spawn(level, original, 1)
	_attach_path_spawn(level, detour, 2)

	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	_expect(tile_manager.load_level(level), "airborne tile fixture loads")
	var effects := TileEffectSystem.new()
	host.add_child(effects)
	effects.configure(tile_manager)
	var planner := PathRoutePlanner.new()
	host.add_child(planner)
	planner.configure(grid, tile_manager)
	planner.load_level(level)

	var ground := _make_target(host, false)
	var flying := _make_target(host, true)
	effects.apply_stay(ground, Vector3i.ZERO, 1.0)
	effects.apply_stay(flying, Vector3i.ZERO, 1.0)
	_expect(is_equal_approx(ground.current_hp, 80.0), "spikes still damage a ground enemy")
	_expect(is_equal_approx(flying.current_hp, 100.0), "spikes ignore an airborne enemy when disabled")
	effects.apply_enter(flying, Vector3i(1, 0, 0))
	effects._process(void_effect.swallow_interval)
	_expect(flying.is_alive(), "periodic void checks ignore an airborne enemy when disabled")
	_expect(tile_manager.blocks_enemy_navigation(Vector3i(2, 0, 0), ground), "rock still blocks a ground enemy")
	_expect(not tile_manager.blocks_enemy_navigation(Vector3i(2, 0, 0), flying), "rock navigation ignores an airborne enemy when disabled")
	var ground_detour := planner.find_detour(original, Vector3i(1, 0, 0), Vector3i(2, 0, 0), ground)
	var flying_detour := planner.find_detour(original, Vector3i(1, 0, 0), Vector3i(2, 0, 0), flying)
	_expect(bool(ground_detour["triggered"]), "ground enemy requests a detour around an applicable rock")
	_expect(not bool(flying_detour["triggered"]), "flying enemy keeps its authored path through an inapplicable rock")

	spike.affects_airborne = true
	effects.apply_stay(flying, Vector3i.ZERO, 1.0)
	_expect(is_equal_approx(flying.current_hp, 80.0), "enabling the same bool makes spikes affect airborne enemies")
	host.queue_free()
	await process_frame

func _test_building_effect_filtering() -> void:
	var level := _make_level()
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	_expect(tile_manager.load_level(level), "airborne building fixture loads")
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var ground := _make_target(host, false, Vector3(2.0, 0.0, 0.0))
	var flying := _make_target(host, true, Vector3(1.0, 0.0, 0.0))
	combat_manager.register_target(ground)
	combat_manager.register_target(flying)

	var tower_stats := _make_building_stats(false)
	var tower := _make_building(host, BuildingDefinition.Kind.ARROW_TOWER, tower_stats, grid, tile_manager, combat_manager)
	_expect(tower.acquire_target() == ground, "single-target tower filters the nearer airborne enemy when disabled")
	tower_stats.affects_airborne = true
	_expect(tower.acquire_target() == flying, "single-target tower can target airborne enemies when enabled")

	var laser_stats := _make_building_stats(false)
	laser_stats.laser_dps = 10.0
	var laser := _make_building(host, BuildingDefinition.Kind.LASER_TOWER, laser_stats, grid, tile_manager, combat_manager)
	ground.current_hp = 100.0
	flying.current_hp = 100.0
	LaserAttackStrategy.new().tick(laser, 1.0)
	_expect(is_equal_approx(ground.current_hp, 90.0), "laser still damages ground targets on its segment")
	_expect(is_equal_approx(flying.current_hp, 100.0), "laser piercing query filters airborne targets when disabled")
	laser_stats.affects_airborne = true
	LaserAttackStrategy.new().tick(laser, 1.0)
	_expect(is_equal_approx(flying.current_hp, 90.0), "laser damages airborne targets after enabling the bool")

	var barrier_stats := _make_building_stats(false)
	barrier_stats.damage_reflection_ratio = 0.5
	var barrier := _make_building(host, BuildingDefinition.Kind.BARRIER, barrier_stats, grid, tile_manager, combat_manager, Vector3i(2, 0, 0))
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager._grid = grid
	building_manager._buildings[barrier.cell] = barrier
	_expect(building_manager.get_path_blocker(barrier.cell, ground) == barrier, "tile barrier blocks an applicable ground enemy")
	_expect(building_manager.get_path_blocker(barrier.cell, flying) == null, "tile barrier lets an inapplicable airborne enemy pass")
	var flying_hp_before_reflection := flying.current_hp
	barrier.take_structure_damage(10.0, flying)
	_expect(is_equal_approx(flying.current_hp, flying_hp_before_reflection), "barrier reflection ignores an inapplicable airborne attacker")
	barrier_stats.affects_airborne = true
	_expect(building_manager.get_path_blocker(barrier.cell, flying) == barrier, "tile barrier blocks airborne enemies after enabling the bool")
	barrier.take_structure_damage(10.0, flying)
	_expect(flying.current_hp < flying_hp_before_reflection, "barrier reflection affects an enabled airborne attacker")

	var edge_stats := _make_building_stats(false)
	var edge_definition := BuildingDefinition.new()
	edge_definition.kind = BuildingDefinition.Kind.EDGE_BARRIER
	edge_definition.levels.append(edge_stats)
	var edge_from := Vector3i(0, 1, 0)
	var edge_to := Vector3i(1, 1, 0)
	var edge_index := grid.find_edge_index(edge_from, edge_to)
	var edge_id := grid.canonical_edge_id(edge_from, edge_index)
	var edge_barrier := Building.new()
	host.add_child(edge_barrier)
	edge_barrier.configure_edge(edge_definition, edge_from, edge_to, edge_index, edge_id, grid, tile_manager, combat_manager)
	building_manager._edge_buildings[edge_id] = edge_barrier
	_expect(building_manager.resolve_path_blocker(edge_from, edge_to, ground) == edge_barrier, "edge barrier blocks an applicable ground enemy")
	_expect(building_manager.resolve_path_blocker(edge_from, edge_to, flying) == null, "edge barrier lets an inapplicable airborne enemy pass")
	edge_stats.affects_airborne = true
	_expect(building_manager.resolve_path_blocker(edge_from, edge_to, flying) == edge_barrier, "edge barrier blocks airborne enemies after enabling the bool")
	host.queue_free()
	await process_frame

func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 3)
	level.base_cell = Vector3i(3, 0, 0)
	return level

func _make_target(host: Node, is_flying: bool, world_position: Vector3 = Vector3.ZERO) -> CombatTarget:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.airborne = is_flying
	target.max_hp = 100.0
	target.position = world_position
	host.add_child(target)
	return target

func _make_effect_tile(cell: Vector3i, tile_id: StringName, effect: TileEffect) -> TileCellData:
	var definition := TileDefinition.new()
	definition.tile_id = tile_id
	definition.display_name = str(tile_id)
	definition.effect = effect
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.BLOCKED, 0, definition)
	return tile

func _make_path(path_id: StringName, cells: Array[Vector3i]) -> PathDefinition:
	var path := PathDefinition.new()
	path.path_id = path_id
	path.display_name = str(path_id)
	path.cells = cells
	return path


func _attach_path_spawn(level: LevelResource, path: PathDefinition, number: int) -> void:
	var spawn := SpawnPointDefinition.new()
	spawn.spawn_id = StringName("airborne_spawn_%d" % number)
	spawn.display_name = "测试出生点 %d" % number
	spawn.display_number = number
	spawn.cell = path.get_start_cell()
	level.spawn_points.append(spawn)
	path.spawn_point = spawn

func _make_building_stats(affects_flying: bool) -> BuildingLevelStats:
	var stats := BuildingLevelStats.new()
	stats.affects_airborne = affects_flying
	stats.targeting_range = 10.0
	stats.attack_range = 10.0
	stats.base_damage = 10.0
	stats.max_durability = 100.0
	return stats

func _make_building(
	host: Node,
	kind: BuildingDefinition.Kind,
	stats: BuildingLevelStats,
	grid: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	cell: Vector3i = Vector3i.ZERO
) -> Building:
	var definition := BuildingDefinition.new()
	definition.kind = kind
	definition.levels.append(stats)
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, cell, grid, tile_manager, combat_manager)
	return building

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
