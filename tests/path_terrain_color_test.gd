extends SceneTree

const TileEditorCanvasScript := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")
const PATH_COLOR := Color("ffb93b")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[PathTerrainColor] running")
	var level := _make_level()
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var renderer := TileRenderer.new()
	host.add_child(renderer)
	renderer.set_grid(grid)
	renderer.set_tile_manager(tile_manager)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	_expect(loader.load_level(level, "memory://path-terrain"), "path terrain fixture loads")
	var path_cells: Array[Vector3i] = [
		Vector3i(0, 1, 0),
		Vector3i(0, 3, 0),
		Vector3i(1, 1, 0),
		Vector3i(2, 1, 0),
	]
	for cell in path_cells:
		_expect(renderer.is_path_terrain_cell(cell), "path union contains %s" % str(cell))
		_expect(renderer.get_base_terrain_color(cell).is_equal_approx(PATH_COLOR), "path cell %s uses #ffb93b" % str(cell))
	var element_cells: Array[Vector3i] = [Vector3i(4, 0, 0), Vector3i(4, 2, 0), Vector3i(4, 4, 0)]
	for cell in element_cells:
		var tile := tile_manager.get_tile(cell)
		_expect(renderer.get_base_terrain_color(cell).is_equal_approx(level.get_height_color(tile.height_level)), "%s element keeps its height base color" % tile.get_display_name())
	var path_element_cell := Vector3i(2, 1, 0)
	_expect(renderer.get_base_terrain_color(path_element_cell).is_equal_approx(PATH_COLOR), "element on a path keeps the path base color")
	var occupant := Node.new()
	host.add_child(occupant)
	var occupied_path_cell := Vector3i(1, 1, 0)
	var before_occupancy := renderer.get_base_terrain_color(occupied_path_cell)
	_expect(tile_manager.place_occupant(occupied_path_cell, occupant), "fixture places a building-like occupant on a path tile")
	_expect(renderer.get_base_terrain_color(occupied_path_cell).is_equal_approx(before_occupancy), "occupant never changes the tile base color")
	var snapshot := renderer.create_tile_visual_snapshot(path_element_cell)
	_expect(_snapshot_terrain_uses_color(snapshot, PATH_COLOR), "mirror tile snapshot preserves the separated #ffb93b path base")
	snapshot.free()
	var editor_canvas := TileEditorCanvasScript.new()
	root.add_child(editor_canvas)
	editor_canvas.size = Vector2(900.0, 700.0)
	editor_canvas.call("set_level", level)
	_expect(Color(editor_canvas.call("_terrain_color", path_element_cell, level.get_tile(path_element_cell))).is_equal_approx(PATH_COLOR), "level editor shows path color below an element")
	var editor_element: TileCellData = level.get_tile(element_cells[1])
	_expect(Color(editor_canvas.call("_terrain_color", element_cells[1], editor_element)).is_equal_approx(level.get_height_color(editor_element.height_level)), "level editor keeps non-path element base independent")
	host.queue_free()
	editor_canvas.queue_free()
	await process_frame
	if _failures == 0:
		print("[PathTerrainColor] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[PathTerrainColor] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(6, 5)
	level.height_levels = 3
	level.height_step = 0.4
	level.path_terrain_color = PATH_COLOR
	level.base_cell = Vector3i(3, 1, 0)
	var path_1 := _make_path(&"path_1", [
		Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0),
	])
	var path_2 := _make_path(&"path_2", [
		Vector3i(0, 3, 0), Vector3i(1, 3, 0), Vector3i(1, 2, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0),
	])
	level.paths = [path_1, path_2]
	level.spawn_points = [_make_spawn(path_1), _make_spawn(path_2)]
	level.store_tile(_make_element_tile(Vector3i(2, 1, 0), 1, TileDefinition.VisualKind.SPIKES, Color.RED))
	level.store_tile(_make_element_tile(Vector3i(4, 0, 0), 0, TileDefinition.VisualKind.ROCK, Color.BLACK))
	level.store_tile(_make_element_tile(Vector3i(4, 2, 0), 1, TileDefinition.VisualKind.SPIKES, Color.RED))
	level.store_tile(_make_element_tile(Vector3i(4, 4, 0), 2, TileDefinition.VisualKind.HOLE, Color(0.02, 0.02, 0.03)))
	return level

func _make_path(path_id: StringName, cells: Array[Vector3i]) -> PathDefinition:
	var path := PathDefinition.new()
	path.path_id = path_id
	path.display_name = str(path_id)
	path.cells = cells
	return path

func _make_spawn(path: PathDefinition) -> SpawnPointDefinition:
	var spawn := SpawnPointDefinition.new()
	spawn.sync_with_path(path)
	return spawn

func _make_element_tile(cell: Vector3i, height: int, visual_kind: int, element_color: Color) -> TileCellData:
	var definition := TileDefinition.new()
	definition.tile_id = StringName("element_%s" % str(cell))
	definition.display_name = "元素%s" % str(cell)
	definition.surface_kind = TileDefinition.SurfaceKind.ELEMENT
	definition.allows_tile_building = false
	definition.override_terrain_color = true
	definition.terrain_color = element_color
	definition.visual_kind = visual_kind
	definition.visual_color = element_color
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.BLOCKED, height, definition)
	return tile

func _snapshot_terrain_uses_color(snapshot: Node3D, expected: Color) -> bool:
	if snapshot == null or snapshot.get_child_count() == 0:
		return false
	var terrain := snapshot.get_child(0) as MeshInstance3D
	if terrain == null or terrain.mesh == null or terrain.mesh.get_surface_count() == 0:
		return false
	var arrays := terrain.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return false
	for color in colors:
		if not color.is_equal_approx(expected):
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
