extends SceneTree

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TileElementsAndRerouting] running")
	_test_tile_definition_contracts()
	await _test_edge_permission_contract()
	await _test_element_renderer_batches()
	await _test_shortest_manual_detour(GridManager.Shape.SQUARE)
	await _test_shortest_manual_detour(GridManager.Shape.HEX)
	await _test_exact_intersection_and_no_route()
	await _test_spike_and_void_effects()
	await _test_enemy_reroute_trigger_and_resource_immutability()
	if _failures == 0:
		print("[TileElementsAndRerouting] PASS: %d checks" % _checks)
		call_deferred("_finish", 0)
	else:
		push_error("[TileElementsAndRerouting] FAIL: %d/%d checks failed" % [_failures, _checks])
		call_deferred("_finish", 1)

func _finish(exit_code: int) -> void:
	quit(exit_code)

func _test_tile_definition_contracts() -> void:
	var legacy := TileCellData.new()
	legacy.configure(Vector3i.ZERO, TileCellData.TileType.BUILDABLE, 0)
	_expect(legacy.is_buildable() and legacy.allows_tile_building(), "legacy enum-only buildable tiles remain compatible")
	_expect(legacy.allows_edge_building() and legacy.can_use_for_reroute(), "legacy tiles keep edge placement and reroute compatibility")
	for preset_path in [
		"res://resources/tiles/SpikeTile.tres",
		"res://resources/tiles/VoidTile.tres",
		"res://resources/tiles/RockTile.tres",
	]:
		var preset := ResourceLoader.load(preset_path) as TilePreset
		_expect(preset != null and preset.definition != null, "%s loads a reusable tile definition" % preset_path.get_file())
		if preset == null or preset.definition == null:
			continue
		var tile := preset.make_tile(Vector3i.ZERO, 3) as TileCellData
		_expect(not tile.allows_tile_building(), "%s rejects tile buildings" % preset.display_name)
		_expect(tile.allows_edge_building(), "%s allows edge buildings" % preset.display_name)
	var rock := (ResourceLoader.load("res://resources/tiles/RockTile.tres") as TilePreset).make_tile(Vector3i.ZERO, 3) as TileCellData
	_expect(rock.blocks_enemy_navigation() and not rock.can_use_for_reroute(), "rock blocks navigation and is excluded from detours")
	var void_tile := (ResourceLoader.load("res://resources/tiles/VoidTile.tres") as TilePreset).make_tile(Vector3i.ZERO, 3) as TileCellData
	_expect(not void_tile.blocks_enemy_navigation() and not void_tile.can_use_for_reroute(), "void is passable on an initial route but excluded from voluntary detours")

func _test_edge_permission_contract() -> void:
	var level := _make_level(GridManager.Shape.SQUARE)
	var first := Vector3i(1, 1, 0)
	var second := Vector3i(2, 1, 0)
	level.store_tile(_make_tile(first, _make_definition(&"edge_yes", true, null)))
	level.store_tile(_make_tile(second, _make_definition(&"edge_yes_2", true, null)))
	var fixture := _make_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	resource_manager.apply_level_configuration(level)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var rules := BuildingPlacementRules.new()
	rules.configure(grid, tile_manager, resource_manager, combat_manager)
	rules.rebuild_level_cache(level)
	var definition := ResourceLoader.load("res://resources/buildings/EdgeBarrier.tres") as BuildingDefinition
	var edge_index := grid.find_edge_index(first, second)
	var allowed := rules.validate_edge(first, edge_index, definition, Callable(), false)
	_expect(str(allowed["failure"]).is_empty(), "an interior edge is allowed when both adjacent tiles permit edge buildings")
	tile_manager.get_tile(second).definition = _make_definition(&"edge_no", false, null)
	var rejected := rules.validate_edge(first, edge_index, definition, Callable(), false)
	_expect(not str(rejected["failure"]).is_empty(), "either adjacent tile can veto shared-edge placement")
	host.queue_free()
	await process_frame

func _test_element_renderer_batches() -> void:
	var level := _make_level(GridManager.Shape.SQUARE)
	level.store_tile((ResourceLoader.load("res://resources/tiles/SpikeTile.tres") as TilePreset).make_tile(Vector3i(0, 0, 0), 3))
	level.store_tile((ResourceLoader.load("res://resources/tiles/VoidTile.tres") as TilePreset).make_tile(Vector3i(1, 0, 0), 3))
	level.store_tile((ResourceLoader.load("res://resources/tiles/RockTile.tres") as TilePreset).make_tile(Vector3i(2, 0, 0), 3))
	var fixture := _make_fixture(level)
	var host: Node3D = fixture["host"]
	var renderer := TileRenderer.new()
	host.add_child(renderer)
	renderer.set_grid(fixture["grid"])
	renderer.set_tile_manager(fixture["tile"])
	_expect(renderer._element_instance.mesh != null, "runtime renderer batches all configured element greyboxes")
	var blank := _make_level(GridManager.Shape.SQUARE)
	_expect((fixture["tile"] as TileManager).load_level(blank), "blank renderer fixture loads")
	_expect(renderer._element_instance.mesh == null, "empty element batches clear the mesh without ending a zero-vertex surface")
	host.queue_free()
	await process_frame

func _test_shortest_manual_detour(shape: GridManager.Shape) -> void:
	var level := _make_detour_level(shape)
	var fixture := _make_fixture(level)
	var host: Node3D = fixture["host"]
	var tile_manager: TileManager = fixture["tile"]
	var planner: PathRoutePlanner = fixture["planner"]
	var original: PathDefinition = level.paths[0]
	var current_cell: Vector3i = original.cells[1]
	var blocked_cell: Vector3i = original.cells[2]
	_expect(tile_manager.blocks_enemy_navigation(blocked_cell), "%s fixture marks the authored path's next cell as rock" % _shape_name(shape))
	var result := planner.find_detour(original, current_cell, blocked_cell)
	_expect(bool(result["triggered"]) and bool(result["found"]), "%s rock triggers a manual-path detour" % _shape_name(shape))
	_expect(result["path"] == level.paths[2], "%s chooses the shorter blue path even when the longer purple path is serialized first" % _shape_name(shape))
	var route: Array = result["cells"]
	_expect(route.front() == current_cell and not route.has(blocked_cell), "%s detour starts at the preceding cell and avoids the rock" % _shape_name(shape))
	host.queue_free()
	await process_frame

func _test_exact_intersection_and_no_route() -> void:
	var level := _make_level(GridManager.Shape.SQUARE)
	var original := _make_path(&"red", [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0)])
	var exact := _make_path(&"exact", [Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 2, 0), Vector3i(2, 2, 0), Vector3i(3, 2, 0), Vector3i(3, 1, 0)])
	level.base_cell = Vector3i(3, 1, 0)
	level.paths = [original, exact]
	level.store_tile(_rock_tile(Vector3i(2, 1, 0)))
	var fixture := _make_fixture(level)
	var result := (fixture["planner"] as PathRoutePlanner).find_detour(original, Vector3i(1, 1, 0), Vector3i(2, 1, 0))
	_expect(bool(result["found"]) and result["join_cell"] == Vector3i(1, 1, 0), "an actual shared cell is a zero-cost path intersection")
	_expect(int(result["cost"]) == 4, "exact-intersection score counts only remaining grid edges")
	level.paths = [original]
	(fixture["planner"] as PathRoutePlanner).load_level(level)
	var missing := (fixture["planner"] as PathRoutePlanner).find_detour(original, Vector3i(1, 1, 0), Vector3i(2, 1, 0))
	_expect(bool(missing["triggered"]) and not bool(missing["found"]), "a rock with no eligible authored path reports a stable no-route result")
	(fixture["host"] as Node).queue_free()
	await process_frame

func _test_spike_and_void_effects() -> void:
	var spike := SpikeTileEffect.new()
	spike.damage_per_second = 20.0
	spike.ignores_armor = true
	var armored := EnemyUnit.new()
	armored.debug_visual_enabled = false
	armored.max_hp = 100.0
	armored.current_hp = 100.0
	armored.armor = 9.0
	spike.apply_stay(armored, 0.25)
	spike.apply_stay(armored, 0.75)
	_expect(is_equal_approx(armored.current_hp, 80.0), "spike DPS is frame-rate independent and can ignore armor")
	armored.current_hp = 100.0
	spike.ignores_armor = false
	spike.apply_stay(armored, 0.25)
	spike.apply_stay(armored, 0.75)
	_expect(is_equal_approx(armored.current_hp, 89.0), "optional armor mitigation reduces the DPS rate without frame dependence")
	armored.free()

	var level := _make_level(GridManager.Shape.SQUARE)
	var path := _make_path(&"void_path", [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)])
	level.base_cell = path.get_end_cell()
	level.paths = [path]
	level.store_tile((ResourceLoader.load("res://resources/tiles/VoidTile.tres") as TilePreset).make_tile(Vector3i(1, 0, 0), 3))
	var fixture := _make_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var effects := TileEffectSystem.new()
	host.add_child(effects)
	effects.configure(tile_manager)
	var points := PackedVector3Array()
	for cell in path.cells:
		points.append(grid.cell_to_world(cell))
	var enemy_definition := EnemyDefinition.new()
	enemy_definition.max_hp = 100.0
	enemy_definition.move_speed = 100.0
	enemy_definition.reward = 7.0
	var enemy := EnemyUnit.new()
	enemy.debug_visual_enabled = false
	enemy.configure_unit(
		enemy_definition,
		points,
		path.cells,
		1.0,
		Callable(),
		path,
		Callable(),
		Callable(),
		Callable(effects, "apply_enter"),
		Callable(effects, "apply_stay")
	)
	var rewards: Array[float] = []
	enemy.died.connect(func(_target: CombatTarget, amount: float) -> void: rewards.append(amount))
	host.add_child(enemy)
	enemy._process(0.1)
	_expect(not enemy.is_alive(), "high-speed movement cannot skip a void tile crossed in one frame")
	_expect(rewards.size() == 1 and is_equal_approx(rewards[0], 7.0), "void defeat uses its configurable reward multiplier")
	host.queue_free()
	await process_frame

func _test_enemy_reroute_trigger_and_resource_immutability() -> void:
	var level := _make_detour_level(GridManager.Shape.SQUARE)
	var fixture := _make_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var planner: PathRoutePlanner = fixture["planner"]
	var effects := TileEffectSystem.new()
	host.add_child(effects)
	effects.configure(tile_manager)
	var original: PathDefinition = level.paths[0]
	var original_cells := original.cells.duplicate()
	var points := PackedVector3Array()
	for cell in original.cells:
		points.append(grid.cell_to_world(cell))
	var definition := EnemyDefinition.new()
	definition.move_speed = 10.0
	var enemy := EnemyUnit.new()
	enemy.debug_visual_enabled = false
	var reroute_events: Array[Dictionary] = []
	enemy.rerouted.connect(func(
		_unit: EnemyUnit,
		from_path: PathDefinition,
		to_path: PathDefinition,
		join_cell: Vector3i
	) -> void:
		reroute_events.append({
			"from_path": from_path,
			"to_path": to_path,
			"join_cell": join_cell,
		})
	)
	enemy.configure_unit(
		definition,
		points,
		original.cells,
		1.0,
		Callable(),
		original,
		Callable(planner, "find_detour"),
		func(cell: Vector3i) -> Vector3: return grid.cell_to_world(cell),
		Callable(effects, "apply_enter"),
		Callable(effects, "apply_stay")
	)
	host.add_child(enemy)
	enemy._process(0.05)
	_expect(enemy.global_position != points[0], "enemy follows its unchanged initial authored path before the preceding rock cell")
	enemy._process(0.2)
	_expect(reroute_events.size() == 1, "enemy installs one runtime detour at the cell immediately before the rock")
	_expect(
		reroute_events.size() == 1
		and reroute_events[0]["from_path"] == original
		and reroute_events[0]["to_path"] == level.paths[2],
		"runtime detour switches from the blocked path to the shortest adjacent path"
	)
	_expect(enemy.global_position != points[1], "enemy continues moving after installing the runtime detour")
	_expect(grid.world_to_cell(enemy.global_position) != original.cells[2], "enemy never enters the rock cell after rerouting")
	_expect(original.cells == original_cells, "runtime rerouting never mutates the serialized PathDefinition")

	var no_route_level := _make_level(GridManager.Shape.SQUARE)
	var blocked_path := _make_path(&"only", [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)])
	no_route_level.base_cell = blocked_path.get_end_cell()
	no_route_level.paths = [blocked_path]
	no_route_level.store_tile(_rock_tile(Vector3i(1, 0, 0)))
	var no_route_fixture := _make_fixture(no_route_level)
	var no_route_grid: GridManager = no_route_fixture["grid"]
	var waiting := EnemyUnit.new()
	waiting.debug_visual_enabled = false
	var waiting_points := PackedVector3Array()
	for cell in blocked_path.cells:
		waiting_points.append(no_route_grid.cell_to_world(cell))
	waiting.configure_unit(
		definition,
		waiting_points,
		blocked_path.cells,
		1.0,
		Callable(),
		blocked_path,
		Callable(no_route_fixture["planner"], "find_detour"),
		func(cell: Vector3i) -> Vector3: return no_route_grid.cell_to_world(cell)
	)
	(no_route_fixture["host"] as Node).add_child(waiting)
	waiting._process(5.0)
	_expect(waiting.global_position == waiting_points[0] and waiting.is_alive(), "enemy idles in place when no authored detour is available")
	host.queue_free()
	(no_route_fixture["host"] as Node).queue_free()
	await process_frame

func _make_fixture(level: LevelResource) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	_expect(tile_manager.load_level(level), "%s tile fixture loads" % _shape_name(level.grid_shape))
	var planner := PathRoutePlanner.new()
	host.add_child(planner)
	planner.configure(grid, tile_manager)
	planner.load_level(level)
	return {"host": host, "grid": grid, "tile": tile_manager, "planner": planner}

func _make_level(shape: GridManager.Shape) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = shape
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 4)
	level.base_cell = Vector3i.ZERO
	return level

func _make_detour_level(shape: GridManager.Shape) -> LevelResource:
	var level := _make_level(shape)
	var original: PathDefinition
	var purple: PathDefinition
	var blue: PathDefinition
	var black: PathDefinition
	var rock_cell: Vector3i
	if shape == GridManager.Shape.SQUARE:
		level.grid_size = Vector2i(5, 5)
		original = _make_path(&"red", [Vector3i(0, 2, 0), Vector3i(1, 2, 0), Vector3i(2, 2, 0), Vector3i(3, 2, 0), Vector3i(4, 2, 0)])
		purple = _make_path(&"purple", [Vector3i(0, 3, 0), Vector3i(1, 3, 0), Vector3i(1, 4, 0), Vector3i(2, 4, 0), Vector3i(3, 4, 0), Vector3i(4, 4, 0), Vector3i(4, 3, 0), Vector3i(4, 2, 0)])
		blue = _make_path(&"blue", [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0), Vector3i(3, 2, 0), Vector3i(4, 2, 0)])
		black = _make_path(&"black", [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0), Vector3i(4, 1, 0), Vector3i(4, 2, 0)])
		rock_cell = Vector3i(2, 2, 0)
	else:
		level.grid_size = Vector2i(3, 3)
		original = _make_path(&"red", [Vector3i(-2, 0, 2), Vector3i(-1, 0, 1), Vector3i.ZERO, Vector3i(1, -1, 0), Vector3i(2, -2, 0)])
		purple = _make_path(&"purple", [Vector3i(-2, 1, 1), Vector3i(-2, 2, 0), Vector3i(-1, 2, -1), Vector3i(0, 2, -2), Vector3i(1, 1, -2), Vector3i(2, 0, -2), Vector3i(2, -1, -1), Vector3i(2, -2, 0)])
		blue = _make_path(&"blue", [Vector3i(-2, 2, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, -1), Vector3i(1, 0, -1), Vector3i(2, -1, -1), Vector3i(2, -2, 0)])
		black = _make_path(&"black", [Vector3i(-3, 0, 3), Vector3i(-2, -1, 3), Vector3i(-1, -2, 3), Vector3i(0, -3, 3), Vector3i(1, -3, 2), Vector3i(2, -3, 1), Vector3i(2, -2, 0)])
		rock_cell = Vector3i.ZERO
	level.base_cell = original.get_end_cell()
	level.paths = [original, purple, blue, black]
	level.store_tile(_rock_tile(rock_cell))
	return level

func _make_path(path_id: StringName, cells: Array[Vector3i]) -> PathDefinition:
	var path := PathDefinition.new()
	path.path_id = path_id
	path.display_name = str(path_id)
	path.cells = cells
	return path

func _rock_tile(cell: Vector3i) -> TileCellData:
	return (ResourceLoader.load("res://resources/tiles/RockTile.tres") as TilePreset).make_tile(cell, 3) as TileCellData

func _make_tile(cell: Vector3i, definition: TileDefinition) -> TileCellData:
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.BUILDABLE, 0, definition)
	return tile

func _make_definition(tile_id: StringName, allows_edge: bool, effect: TileEffect) -> TileDefinition:
	var definition := TileDefinition.new()
	definition.tile_id = tile_id
	definition.display_name = str(tile_id)
	definition.allows_tile_building = false
	definition.allows_edge_building = allows_edge
	definition.effect = effect
	return definition

func _shape_name(shape: int) -> String:
	return "hex" if shape == GridManager.Shape.HEX else "square"

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
