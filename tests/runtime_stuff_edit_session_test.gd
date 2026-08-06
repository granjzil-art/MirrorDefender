extends SceneTree

const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeStuffEditSession] running")
	var fixture := _make_fixture()
	var stuff: StuffManager = fixture.stuff
	var validator = StuffPlacementValidatorScript.new()
	validator.configure(fixture.grid, fixture.tile, fixture.terrain, stuff)
	var session: Node = RuntimeStuffEditSessionScript.new()
	fixture.host.add_child(session)
	session.configure(stuff, validator)
	_expect(session.begin(fixture.level, "memory://runtime-edit"), "runtime Stuff session starts")
	var tree: StuffDefinition = load("res://resources/stuffs/Tree.tres")
	var spike: StuffDefinition = load("res://resources/stuffs/Spike.tres")
	var first: Variant = session.place_stuff(Vector3i(1, 1, 0), tree, 0)
	var first_id: StringName = first.placement_id if first != null else &""
	_expect(first != null and first_id == &"tree_1", "session places one catalog Stuff with stable generated id")
	_expect(stuff.get_stuff_at(Vector3i(1, 1, 0)).size() == 1, "placed Stuff enters canonical runtime state")
	_expect(session.is_dirty() and session.can_undo(), "successful placement marks session dirty and undoable")
	_expect(session.rotate_stuff(first_id, 1), "session rotates a placed Stuff")
	_expect(stuff.get_stuff(first_id).facing_index == 1, "rotation refreshes canonical runtime facing")
	_expect(session.undo(), "rotation can be undone")
	_expect(stuff.get_stuff(first_id).facing_index == 0, "undo restores previous facing")
	_expect(session.undo(), "placement can be undone")
	_expect(stuff.get_all_stuff().is_empty(), "undo removes the placed runtime instance")
	_expect(session.redo(), "placement can be redone")
	_expect(stuff.get_all_stuff().size() == 1, "redo restores the runtime instance")
	_expect(session.remove_stuff(&"tree_1"), "session removes one selected Stuff")
	_expect(stuff.get_all_stuff().is_empty(), "remove updates runtime state")
	_expect(session.undo(), "remove can be undone")
	_expect(stuff.get_all_stuff().size() == 1, "undo restores removed Stuff")

	var occupant := Node.new()
	fixture.host.add_child(occupant)
	_expect(fixture.tile.place_occupant(Vector3i(2, 1, 0), occupant), "fixture places a tile occupant")
	var occupied_result: Dictionary = session.validate_placement(Vector3i(2, 1, 0), spike, 0)
	_expect(not bool(occupied_result.valid), "validator rejects blocking Stuff over an existing block building")

	var save_path := "user://runtime_stuff_edit_session_test.tres"
	print("[RuntimeStuffEditSession] saving")
	var save_result: Dictionary = session.save(save_path)
	_expect(bool(save_result.success) and ResourceLoader.exists(save_path), "session explicitly saves a valid LevelResource copy")
	_expect(not session.is_dirty() and not session.can_undo(), "save establishes a clean history baseline")
	_expect(session.end_after_save(), "clean saved session ends")
	var saved: LevelResource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_expect(saved != null and saved.stuff_placements.size() == 1, "saved level persists current Stuff placements")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	fixture.host.queue_free()
	await process_frame
	if _failures == 0:
		print("runtime_stuff_edit_session_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("runtime_stuff_edit_session_test: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var terrain := TerrainManager.new()
	host.add_child(terrain)
	terrain.set_grid(grid)
	var stuff := StuffManagerScript.new()
	host.add_child(stuff)
	stuff.configure(grid, terrain)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	tile.legacy_content_runtime_enabled = false
	tile.set_stuff_runtime_provider(stuff)
	tile.set_surface_height_resolver(Callable(terrain, "get_world_height"))
	tile.set_base_placement_resolvers(
		Callable(terrain, "allows_tile_building"),
		Callable(terrain, "allows_edge_building")
	)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain, stuff)
	var level := _make_level()
	_expect(loader.load_level(level, "memory://runtime-edit"), "runtime edit fixture loads")
	return {
		"host": host,
		"grid": grid,
		"terrain": terrain,
		"stuff": stuff,
		"tile": tile,
		"level": level,
	}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.display_name = "Runtime Stuff Edit Test"
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 3)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 1.0
	level.height_step = 1.0
	for x in range(level.grid_size.x):
		for y in range(level.grid_size.y):
			var cell := GridCellData.new()
			cell.configure(Vector3i(x, y, 0), level.default_terrain, 1, true, true)
			level.grid_cells.append(cell)
	return level


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
