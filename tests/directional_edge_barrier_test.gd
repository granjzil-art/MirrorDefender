extends SceneTree

var _failures: int = 0
var _checks: int = 0
var _projectile_spawn_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[DirectionalEdgeBarrier] running")
	_test_level_geometry_contract()
	await _test_edge_placement_for_shape(GridManager.Shape.HEX)
	await _test_edge_placement_for_shape(GridManager.Shape.SQUARE)
	await _test_directional_blocking_and_lifecycle()
	await _test_melee_and_ranged_enemy_integration()
	if _failures == 0:
		print("[DirectionalEdgeBarrier] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[DirectionalEdgeBarrier] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_level_geometry_contract() -> void:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.HEX
	_expect(level.get_geometry_tag() == &"hex", "hex level exposes the derived hex tag")
	_expect(level.get_tile_building_facing_count() == 6, "hex tile buildings use six facings")
	_expect(level.get_edge_building_facing_count() == 6, "hex edge buildings use six edges")
	level.grid_shape = GridManager.Shape.SQUARE
	_expect(level.get_geometry_tag() == &"square", "square level exposes the derived square tag")
	_expect(level.get_tile_building_facing_count() == 8, "square tile buildings use eight facings")
	_expect(level.get_edge_building_facing_count() == 4, "square edge buildings use four edges")

func _test_edge_placement_for_shape(shape: GridManager.Shape) -> void:
	var level := _make_level(shape, false)
	var fixture := _make_building_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var path: PathDefinition = level.paths[0]
	var from_cell := path.cells[1]
	var to_cell := path.cells[2]
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	_expect(edge_index >= 0, "%s path segment maps to a grid edge" % grid.get_geometry_tag())
	var barrier := building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier)
	_expect(barrier != null, "%s edge barrier can be placed on a forward path edge" % grid.get_geometry_tag())
	if barrier != null:
		_expect(barrier.edge_to_cell == to_cell, "edge placement retains its directed destination")
		_expect(barrier.get_facing_slot_count() == grid.get_edge_building_facing_count(), "edge barrier facing count follows level geometry")
		var facing_before := barrier.facing_index
		_expect(not building_manager.rotate_selected(), "placed edge barrier rejects free rotation")
		_expect(barrier.facing_index == facing_before, "rejected rotation preserves edge alignment")
		_expect(building_manager.get_edge_building(barrier.edge_id) == barrier, "physical edge occupancy is queryable by canonical id")
		_expect(building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier) == null, "one physical edge rejects a second building")
		var canonical_id := barrier.edge_id
		barrier.queue_free()
		await process_frame
		_expect(building_manager.get_edge_building(canonical_id) == null, "external edge-building deletion clears edge occupancy")
		_expect(resource_manager.get_building_count() == 0, "external edge-building deletion releases building cap usage")
	host.queue_free()
	await process_frame

func _test_directional_blocking_and_lifecycle() -> void:
	var level := _make_level(GridManager.Shape.HEX, false)
	var fixture := _make_building_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var path: PathDefinition = level.paths[0]
	var from_cell := path.cells[1]
	var to_cell := path.cells[2]
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var initial_resource := resource_manager.main_resource
	var barrier := building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier)
	_expect(barrier != null, "directional barrier fixture is placed")
	if barrier != null:
		_expect(building_manager.resolve_path_blocker(from_cell, to_cell) == barrier, "matching forward path resolves the edge barrier")
		_expect(building_manager.resolve_path_blocker(to_cell, from_cell) == null, "reverse traversal of the same physical edge is not blocked")
		var unrelated_from := path.cells[2]
		var unrelated_to := path.cells[3]
		_expect(building_manager.resolve_path_blocker(unrelated_from, unrelated_to) == null, "another path direction ignores the edge barrier")
		var level_two_stats := barrier.definition.get_level_stats(2)
		_expect(building_manager.upgrade_selected(), "edge barrier uses the shared upgrade transaction")
		_expect(barrier.level == 2 and is_equal_approx(barrier.maximum_durability, level_two_stats.max_durability), "edge barrier upgrade applies level durability")
		barrier.take_structure_damage(30.0)
		var damaged_durability := barrier.current_durability
		barrier._process(level_two_stats.regeneration_delay + 1.0)
		_expect(barrier.current_durability > damaged_durability, "edge barrier reuses out-of-combat regeneration")
		var level_three_stats := barrier.definition.get_level_stats(3)
		_expect(building_manager.upgrade_selected(), "edge barrier can reach the shared level cap")
		var reflection_target := CombatTarget.new()
		reflection_target.debug_visual_enabled = false
		host.add_child(reflection_target)
		var hp_before_reflection := reflection_target.current_hp
		barrier.take_structure_damage(10.0, reflection_target)
		_expect(reflection_target.current_hp < hp_before_reflection, "edge barrier reuses configured damage reflection")
		_expect(not building_manager.upgrade_selected(), "max-level edge barrier rejects another upgrade")
		var expected_after_delete := initial_resource - barrier.definition.get_level_stats(1).cost - level_two_stats.cost - level_three_stats.cost + level_three_stats.refund_amount
		_expect(building_manager.remove_selected_building(), "edge barrier uses the shared delete transaction")
		_expect(is_equal_approx(resource_manager.main_resource, expected_after_delete), "edge barrier delete refunds its current-level amount")
		_expect(building_manager.get_edge_building(grid.canonical_edge_id(from_cell, edge_index)) == null, "delete releases physical edge occupancy")
	host.queue_free()
	await process_frame

func _test_melee_and_ranged_enemy_integration() -> void:
	var level := _make_level(GridManager.Shape.HEX, true)
	var fixture := _make_building_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var building_manager: BuildingManager = fixture["building"]
	var path: PathDefinition = level.paths[0]
	var from_cell := path.cells[6]
	var to_cell := path.cells[7]
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var barrier := building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier)
	_expect(barrier != null, "combat fixture edge barrier is placed")
	if barrier == null:
		host.queue_free()
		await process_frame
		return
	var path_points := PackedVector3Array()
	for cell in path.cells:
		path_points.append(grid.cell_to_world(cell) + Vector3(0.0, tile_manager.get_world_height(cell), 0.0))
	var melee_definition := EnemyDefinition.new()
	melee_definition.display_name = "测试近战"
	melee_definition.move_speed = 100.0
	melee_definition.attack_damage = 15.0
	melee_definition.attacks_per_second = 1.0
	melee_definition.attack_range = 0.65
	melee_definition.projectile_speed = 0.0
	var melee := EnemyUnit.new()
	melee.debug_visual_enabled = false
	melee.configure_unit(
		melee_definition,
		path_points,
		path.cells,
		grid.cell_size,
		Callable(building_manager, "resolve_path_blocker")
	)
	host.add_child(melee)
	var durability_before := barrier.current_durability
	melee._process(1.0)
	_expect(melee.is_attacking(), "matching melee enemy stops in attack state")
	_expect(barrier.current_durability < durability_before, "matching melee enemy damages the edge barrier")
	melee.queue_free()
	await process_frame

	var archer_resource: Resource = ResourceLoader.load(
		"res://resources/enemies/Archer.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	var archer_definition := archer_resource as EnemyDefinition
	_expect(archer_definition != null, "Archer definition loads for ranged regression")
	if archer_definition == null:
		host.queue_free()
		await process_frame
		return
	var archer := EnemyUnit.new()
	archer.debug_visual_enabled = false
	archer.configure_unit(
		archer_definition,
		path_points,
		path.cells,
		grid.cell_size,
		Callable(building_manager, "resolve_path_blocker")
	)
	host.add_child(archer)
	_projectile_spawn_count = 0
	archer.projectile_spawned.connect(_on_projectile_spawned)
	archer._process(20.0)
	_expect(archer.is_attacking(), "archer enters attack state after approaching along a bent path")
	_expect(_projectile_spawn_count == 1, "archer launches a projectile immediately on reaching range")
	_expect(archer.global_position.distance_to(path_points[path_points.size() - 1]) > 0.1, "archer stops before reaching the base")
	host.queue_free()
	await process_frame

func _make_building_fixture(level: LevelResource) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	resource_manager.apply_level_configuration(level)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	var edge_resource: Resource = ResourceLoader.load(
		"res://resources/buildings/EdgeBarrier.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	building_manager.edge_barrier = edge_resource as BuildingDefinition
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	_expect(loader.load_level(level, "memory://edge-test"), "edge test level loads")
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
	}

func _make_level(shape: GridManager.Shape, long_path: bool) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = shape
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(5, 5)
	level.initial_resource = 2000
	level.building_cap = 20
	level.base_resource_per_second = 0.0
	var path := PathDefinition.new()
	path.path_id = &"path_1"
	path.display_name = "路径1"
	if shape == GridManager.Shape.HEX:
		if long_path:
			path.cells.append_array([
				Vector3i(-4, 0, 4),
				Vector3i(-3, 0, 3),
				Vector3i(-2, 0, 2),
				Vector3i(-1, 0, 1),
				Vector3i.ZERO,
				Vector3i(1, -1, 0),
				Vector3i(2, -2, 0),
				Vector3i(3, -3, 0),
				Vector3i(4, -4, 0),
			])
		else:
			path.cells.append_array([
				Vector3i(-2, 0, 2),
				Vector3i(-1, 0, 1),
				Vector3i.ZERO,
				Vector3i(1, -1, 0),
				Vector3i(2, -2, 0),
			])
	else:
		path.cells.append_array([
			Vector3i(0, 2, 0),
			Vector3i(1, 2, 0),
			Vector3i(2, 2, 0),
			Vector3i(3, 2, 0),
			Vector3i(4, 2, 0),
		])
	var spawn_point := SpawnPointDefinition.new()
	spawn_point.spawn_id = &"path_1_spawn"
	spawn_point.display_name = "路径1出生点"
	spawn_point.cell = path.get_start_cell()
	level.base_cell = path.get_end_cell()
	level.paths.append(path)
	level.spawn_points.append(spawn_point)
	return level

func _on_projectile_spawned(_unit: EnemyUnit, _projectile: EnemyProjectile) -> void:
	_projectile_spawn_count += 1

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
