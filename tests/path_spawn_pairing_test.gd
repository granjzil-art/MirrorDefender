extends SceneTree

const TileEditorPanel := preload("res://addons/mirror_tile_editor/tile_editor_panel.gd")
const TileEditorCanvas := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")
const TileEditorPlugin := preload("res://addons/mirror_tile_editor/tile_editor_plugin.gd")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[PathSpawnPairing] running")
	_test_definition_naming()
	_expect(TileEditorPlugin != null, "level editor plugin entry script parses without starting external services")
	_test_legacy_pair_lookup()
	await _test_square_continuous_path_recording()
	await _test_editor_creation_and_wave_binding()
	if _failures == 0:
		print("[PathSpawnPairing] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[PathSpawnPairing] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_definition_naming() -> void:
	var path := _make_path(&"path_11", "路径 11", Vector3i(0, 0, 0))
	var spawn := SpawnPointDefinition.new()
	spawn.sync_with_path(path)
	_expect(spawn.spawn_id == &"spawn_path_11", "spawn ID is derived from its path ID")
	_expect(spawn.display_name == "路径 11 出生点", "spawn display name is derived from its path name")
	_expect(spawn.cell == path.get_start_cell(), "spawn cell follows the path start")
	path.path_id = &""
	spawn.sync_with_path(path)
	_expect(spawn.spawn_id == &"spawn_", "temporary empty path IDs keep one editable spawn identity")

func _test_legacy_pair_lookup() -> void:
	var level := LevelResource.new()
	var path := _make_path(&"legacy", "旧路径", Vector3i(1, 0, 0))
	var spawn := SpawnPointDefinition.new()
	spawn.spawn_id = &"old_north"
	spawn.display_name = "旧入口"
	spawn.cell = Vector3i(2, 0, 0)
	var group := SpawnGroupDefinition.new()
	group.path = path
	group.spawn_point = spawn
	var wave := WaveDefinition.new()
	wave.spawn_groups.append(group)
	level.paths.append(path)
	level.spawn_points.append(spawn)
	level.waves.append(wave)
	_expect(level.get_spawn_point_for_path(path) == spawn, "legacy wave references recover the paired spawn")
	_expect(level.get_path_for_spawn_point(spawn) == path, "legacy wave references recover the paired path")
	var duplicate_spawn := SpawnPointDefinition.new()
	duplicate_spawn.spawn_id = &"second_old_spawn"
	duplicate_spawn.cell = path.get_start_cell()
	level.spawn_points.append(duplicate_spawn)
	_expect(level.get_spawn_point_candidates_for_path(path).size() == 2, "legacy duplicate candidates are exposed as ambiguous")
	_expect(level.get_spawn_point_for_path(path) == null, "ambiguous legacy spawns are not guessed")

func _test_square_continuous_path_recording() -> void:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(20, 7)
	var canvas: Control = TileEditorCanvas.new()
	root.add_child(canvas)
	canvas.size = Vector2(1200.0, 700.0)
	canvas.call("set_level", level)
	canvas.call("reset_view")
	var recorded_cells: Array[Vector3i] = []
	canvas.path_cell_clicked.connect(func(cell: Vector3i) -> void: recorded_cells.append(cell))
	var start_cell := Vector3i(19, 3, 0)
	var end_cell := Vector3i(0, 3, 0)
	var start_screen: Vector2 = canvas.call("_cell_center_screen", start_cell)
	var end_screen: Vector2 = canvas.call("_cell_center_screen", end_cell)
	canvas.call("_record_path_between", start_screen, end_screen)
	_expect(recorded_cells.size() == 20, "square path drag records every crossed tile instead of only endpoints")
	_expect(not recorded_cells.is_empty() and recorded_cells.front() == start_cell and recorded_cells.back() == end_cell, "square path drag preserves start-to-end order")
	var shape := SquareGridShape.new()
	shape.setup(level.grid_cell_size)
	var all_adjacent := true
	for index in range(1, recorded_cells.size()):
		if not shape.get_neighbors(recorded_cells[index - 1]).has(recorded_cells[index]):
			all_adjacent = false
			break
	_expect(all_adjacent, "every recorded square path pair is edge-adjacent")
	var path := _make_path(&"square_drag", "四边形连续路径", start_cell)
	path.cells = recorded_cells
	var spawn := SpawnPointDefinition.new()
	spawn.sync_with_path(path)
	level.paths = [path]
	level.spawn_points = [spawn]
	level.base_cell = end_cell
	_expect(level.validate_runtime().is_empty(), "recorded square path passes runtime continuity validation")
	canvas.queue_free()
	await process_frame

func _test_editor_creation_and_wave_binding() -> void:
	var panel: Control = TileEditorPanel.new()
	root.add_child(panel)
	await process_frame
	var legacy_square := LevelResource.new()
	legacy_square.grid_shape = GridManager.Shape.SQUARE
	legacy_square.grid_size = Vector2i(20, 7)
	var legacy_path := _make_path(&"legacy_square", "旧四边形路径", Vector3i(19, 3, 0))
	legacy_path.cells = [Vector3i(19, 3, 0), Vector3i(0, 3, 0)]
	legacy_square.paths = [legacy_path]
	_expect(panel.call("_normalize_square_path_gaps", legacy_square) == 18, "editor migrates a straight square endpoint pair into adjacent cells")
	_expect(legacy_path.cells.size() == 20 and legacy_path.cells[1] == Vector3i(18, 3, 0), "square path migration preserves direction and fills every intermediate tile")
	var tile_canvas: Control = panel.get("_canvas")
	_expect(tile_canvas != null and tile_canvas.has_method("set_level"), "editor canvas exposes set_level after tool-script loading")
	_expect(tile_canvas != null and tile_canvas.has_method("reset_view"), "editor canvas exposes reset_view after tool-script loading")
	panel.call("_add_path")
	panel.call("_on_path_canvas_clicked", Vector3i(0, 0, 0))
	var level := panel.get("_level") as LevelResource
	var first_path: PathDefinition = level.paths[0]
	panel.call("_add_path")
	panel.call("_on_path_canvas_clicked", Vector3i(0, 1, -1))
	var second_path: PathDefinition = level.paths[1]
	_expect(level.paths.size() == 2, "editor creates two paths")
	_expect(level.spawn_points.size() == 2, "editor creates exactly one spawn per recorded path")
	var first_spawn := level.get_spawn_point_for_path(first_path)
	var second_spawn := level.get_spawn_point_for_path(second_path)
	_expect(first_spawn != null and first_spawn.spawn_id == &"spawn_path_1", "first editor path owns spawn_path_1")
	_expect(second_spawn != null and second_spawn.spawn_id == &"spawn_path_2", "second editor path owns spawn_path_2")
	_expect(panel.call("_get_path_option_label", first_path) == "路径 1 [path_1]", "path labels share one display format")
	_expect(panel.call("_get_spawn_option_label", first_spawn) == "路径 1 出生点 [spawn_path_1]", "spawn labels expose their path correspondence")
	first_path.take_over_path("res://resources/levels/FakeContainer.tres::Path_1")
	_expect(not first_path.resource_path.is_empty(), "fixture reproduces a named subresource path")
	_expect(panel.call("_get_resource_option_label", first_path) == "路径 1 [path_1]", "subresource labels do not fall back to the level filename")
	first_path.take_over_path("")
	var duplicate_spawn := SpawnPointDefinition.new()
	duplicate_spawn.spawn_id = &"legacy_duplicate"
	duplicate_spawn.cell = second_path.get_start_cell()
	level.spawn_points.append(duplicate_spawn)
	panel.call("_add_spawn_from_path")
	_expect(level.spawn_points.size() == 3, "sync refuses to create another spawn when legacy candidates are ambiguous")
	level.spawn_points.erase(duplicate_spawn)
	panel.call("_on_path_id_changed", "")
	panel.call("_on_path_id_changed", "custom_route")
	_expect(level.spawn_points.size() == 2, "live path ID editing does not duplicate its spawn")
	_expect(second_spawn.spawn_id == &"spawn_custom_route", "path ID edits rename the same paired spawn")

	panel.call("_add_wave")
	panel.call("_add_spawn_group")
	var group: SpawnGroupDefinition = level.waves[0].spawn_groups[0]
	_expect(group.path == first_path and group.spawn_point == first_spawn, "new wave group starts with a paired path and spawn")
	var path_option := panel.get("_wave_path_select") as OptionButton
	path_option.select(2)
	panel.call("_on_wave_path_selected", 2)
	_expect(group.path == second_path and group.spawn_point == second_spawn, "changing wave path also changes its spawn")
	var spawn_option := panel.get("_wave_spawn_select") as OptionButton
	_expect(spawn_option.disabled, "wave spawn selection is read-only")
	var undo_redo := panel.get("_undo_redo") as UndoRedo
	panel.free()
	undo_redo.free()
	await process_frame

func _make_path(path_id: StringName, display_name: String, start_cell: Vector3i) -> PathDefinition:
	var path := PathDefinition.new()
	path.path_id = path_id
	path.display_name = display_name
	path.cells = [start_cell, start_cell + Vector3i(1, 0, 0)]
	return path

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
