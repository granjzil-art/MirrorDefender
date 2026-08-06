extends SceneTree

const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeTerrainEditor] running")
	var fixture := _make_fixture()
	var validator := StuffPlacementValidatorScript.new()
	validator.configure(fixture.grid, fixture.tile, fixture.terrain, fixture.stuff)
	var session := RuntimeStuffEditSessionScript.new()
	fixture.host.add_child(session)
	session.configure(
		fixture.stuff,
		validator,
		Callable(),
		Callable(self, "_empty_buildings"),
		Callable(self, "_empty_mirrors"),
		fixture.terrain
	)
	_expect(session.begin(fixture.level, "memory://runtime-terrain"), "terrain authoring session starts")
	var target := Vector3i(2, 2, 0)
	var grass: TerrainDefinition = load("res://resources/terrains/Grass.tres")
	var mud: TerrainDefinition = load("res://resources/terrains/Mud.tres")
	var terrain_preview: Dictionary = session.preview_terrain_change(&"paint_terrain", {
		"cell": target,
		"terrain": mud,
	})
	_expect(bool(terrain_preview.success), "terrain brush builds a valid preview")
	_expect(fixture.terrain.get_terrain(target) == mud, "terrain preview uses the real TerrainManager renderer state")
	_expect(not session.is_dirty(), "hover preview does not enter history")
	session.clear_terrain_preview()
	_expect(fixture.terrain.get_terrain(target) == grass, "clearing preview restores committed terrain")
	var layer_preview: Dictionary = session.preview_terrain_change(&"paint_layer", {
		"cell": target,
		"layer_count": 2,
	})
	_expect(bool(layer_preview.success) and fixture.terrain.get_grid_cell(target).layer_count == 2, "height brush previews the selected voxel layer")
	_expect(bool(session.commit_terrain_preview().success), "height preview commits through the shared transaction")
	_expect(session.is_dirty() and session.can_undo(), "committed height enters unified history")
	_expect(session.undo(), "height edit can be undone")
	_expect(fixture.terrain.get_grid_cell(target).layer_count == 1, "undo restores terrain layer")
	_expect(session.redo(), "height edit can be redone")
	_expect(fixture.terrain.get_grid_cell(target).layer_count == 2, "redo restores terrain layer")
	_expect(session.undo(), "fixture returns to flat baseline before ramp preview")
	var ramp_preview: Dictionary = session.preview_terrain_change(&"place_ramp", {
		"cell": Vector3i(1, 1, 0),
		"facing_index": 0,
		"run_length": 2,
		"base_layer": 1,
		"terrain_override": mud,
	})
	_expect(bool(ramp_preview.success), "1:2 ramp has an exact runtime preview")
	var preview_ramp: RampPlacementData = fixture.terrain.get_ramp_for_cell(Vector3i(2, 1, 0))
	_expect(preview_ramp != null and preview_ramp.facing_index == 0, "ramp preview exposes footprint and direction")
	var ramp_commit: Dictionary = session.commit_terrain_preview()
	_expect(bool(ramp_commit.success) and fixture.terrain.get_ramps().size() == 1, "ramp preview commits as one history operation")
	var ramp_id: StringName = ramp_commit.get("ramp_id", &"")
	var rotate_result: Dictionary = session.apply_terrain_change(&"rotate_ramp", {
		"ramp_id": ramp_id,
		"step": 1,
	})
	_expect(bool(rotate_result.success), "selected ramp rotation commits immediately")
	var rotated_ramp: RampPlacementData = fixture.terrain.get_ramps()[0]
	_expect(rotated_ramp.facing_index == 1, "rotated ramp direction is visible in canonical runtime state")
	var blocked_layer: Dictionary = session.preview_terrain_change(&"paint_layer", {
		"cell": rotated_ramp.anchor_cell,
		"layer_count": 3,
	})
	_expect(not bool(blocked_layer.success), "height brush refuses to break an existing ramp contract")
	var save_path := "user://runtime_terrain_editor_test.tres"
	var save_result: Dictionary = session.save(save_path, true)
	_expect(bool(save_result.success), "full save persists the complete runtime terrain document")
	var saved := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as LevelResource
	_expect(saved != null and saved.ramp_placements.size() == 1, "saved level contains the edited ramp")
	_expect(saved != null and saved.grid_cells.size() == fixture.level.grid_cells.size(), "saved level contains the complete Grid snapshot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	fixture.host.queue_free()
	await process_frame
	if _failures == 0:
		print("runtime_terrain_editor_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("runtime_terrain_editor_test: %d/%d checks failed" % [_failures, _checks])
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
	tile.set_base_placement_resolvers(Callable(terrain, "allows_tile_building"), Callable(terrain, "allows_edge_building"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain, stuff)
	var level := _make_level()
	_expect(loader.load_level(level, "memory://runtime-terrain"), "terrain fixture loads")
	return {"host": host, "grid": grid, "terrain": terrain, "stuff": stuff, "tile": tile, "level": level}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.display_name = "Runtime Terrain Editor Test"
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(6, 5)
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


func _empty_buildings() -> Array[BuildingPlacementData]:
	return []


func _empty_mirrors() -> Array[MirrorPlacementData]:
	return []


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
