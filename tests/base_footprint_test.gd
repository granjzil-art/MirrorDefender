extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[BaseFootprint] running")
	var level := load("res://resources/levels/Level2.tres") as LevelResource
	_expect(level != null, "Level2 loads as the only maintained gameplay level")
	if level == null:
		_finish()
		return
	var errors := level.validate_runtime()
	_expect(errors.is_empty(), "Level2 remains valid after 3x2 base migration: %s" % "; ".join(errors))
	var base_point := level.get_base_point(&"base_1")
	_expect(base_point != null, "Level2 resolves base_1")
	if base_point == null:
		_finish()
		return
	var expected: Array[Vector3i] = [
		Vector3i(6, 10, 0), Vector3i(7, 10, 0), Vector3i(8, 10, 0),
		Vector3i(6, 11, 0), Vector3i(7, 11, 0), Vector3i(8, 11, 0),
	]
	_expect(base_point.get_footprint_cells() == expected, "front-center anchor and facing produce the confirmed 3x2 footprint")
	for path in level.paths:
		_expect(base_point.contains_cell(path.get_end_cell()), "%s ends in one of the six base cells" % path.display_name)

	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var terrain := TerrainManager.new()
	host.add_child(terrain)
	terrain.set_grid(grid)
	_expect(terrain.load_level(level), "canonical terrain loads Level2")
	var tile_manager := TileManager.new()
	tile_manager.legacy_content_runtime_enabled = false
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	tile_manager.set_surface_height_resolver(Callable(terrain, "get_world_height"))
	tile_manager.set_base_placement_resolvers(
		Callable(terrain, "allows_tile_building"),
		Callable(terrain, "allows_edge_building")
	)
	_expect(tile_manager.load_level(level), "tile runtime loads Level2")
	_expect(not tile_manager.allows_edge_building(Vector3i(6, 10, 0), 0), "an internal base-footprint edge rejects every edge building")
	_expect(tile_manager.allows_edge_building(Vector3i(6, 10, 0), 3), "a base perimeter edge keeps its authored physical-edge permission")
	_expect(not tile_manager.allows_edge_building(Vector3i(0, 0, 0), 3), "an outer map edge still rejects edge buildings")

	var base_core := BaseCore.new()
	host.add_child(base_core)
	base_core.configure(grid, tile_manager)
	base_core.load_level(level)
	_expect(base_core.get_base_point_count() == 1, "one 3x2 base still creates one shared-health base marker")
	_expect(base_core.get_base_cells().size() == 6, "BaseCore exposes all six target/occupied cells")
	var marker_root := base_core.find_child("BasePoint_base_1", true, false) as Node3D
	_expect(
		marker_root != null and marker_root.position.is_equal_approx(Vector3(7.0, terrain.get_world_height(base_point.cell), 10.5)),
		"base presentation is centered over the six cells instead of the anchor cell"
	)
	var all_cells_occupied := true
	for footprint_cell in expected:
		if tile_manager.get_occupant(footprint_cell) != base_core or terrain.get_grid_cell(footprint_cell) == null:
			all_cells_occupied = false
			break
	_expect(all_cells_occupied, "all six cells share BaseCore occupancy while their underlying Grid data remains present")
	var planner := PathRoutePlanner.new()
	host.add_child(planner)
	planner.configure(grid, tile_manager)
	planner.load_level(level)
	var target_network: Dictionary = planner.call("_build_target_path_network", base_point.base_id)
	var network_has_all_goals := true
	for footprint_cell in expected:
		if not target_network.has(footprint_cell):
			network_has_all_goals = false
			break
	_expect(network_has_all_goals, "dynamic rerouting exposes all six cells as goals for the same base ID")
	host.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("[BaseFootprint] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[BaseFootprint] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
