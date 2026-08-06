extends SceneTree

const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const RuntimeStuffEditorControllerScript := preload("res://scripts/stuff/RuntimeStuffEditorController.gd")
const RuntimeStuffEditorPanelScene := preload("res://scenes/ui/RuntimeStuffEditorPanel.tscn")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")
const StuffRendererScript := preload("res://scripts/stuff/StuffRenderer.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeStuffEditor] running")
	var fixture := _make_fixture()
	var validator = StuffPlacementValidatorScript.new()
	validator.configure(fixture.grid, fixture.tile, fixture.terrain, fixture.stuff)
	var session: Node = RuntimeStuffEditSessionScript.new()
	fixture.host.add_child(session)
	session.configure(
		fixture.stuff,
		validator,
		Callable(),
		Callable(self, "_empty_building_layout"),
		Callable(self, "_empty_mirror_layout")
	)
	var time := GameTimeController.new()
	fixture.host.add_child(time)
	time.fast_scale = 2.0
	time.configure(null, null, null)
	time.set_fast_enabled(true)
	var controller: Node = RuntimeStuffEditorControllerScript.new()
	fixture.host.add_child(controller)
	controller.configure(
		fixture.grid,
		fixture.terrain,
		fixture.stuff,
		fixture.renderer,
		fixture.loader,
		session,
		time
	)
	var panel: Control = RuntimeStuffEditorPanelScene.instantiate()
	fixture.host.add_child(panel)
	panel.configure(controller)
	var enabled_definition_count: int = fixture.stuff.stuff_catalog.get_enabled_definitions().size()
	_expect(enabled_definition_count > 0, "runtime editor fixture has enabled catalog definitions")
	_expect(panel.get_palette_definition_count() == enabled_definition_count, "runtime editor palette comes from the explicit catalog")
	_expect(controller.set_active(true), "runtime editor opens")
	_expect(time.is_authoring_paused() and is_zero_approx(Engine.time_scale), "runtime editor owns a non-menu authoring pause")
	_expect(panel.is_workspace_visible(), "runtime authoring workspace expands while active")
	var full_save_button := panel.find_child("FullLevelSaveButton", true, false) as Button
	_expect(full_save_button != null and not full_save_button.disabled, "runtime editor exposes an enabled full-save action")
	if full_save_button != null:
		full_save_button.pressed.emit()
	var full_save_path: String = session.get_default_save_path()
	_expect(ResourceLoader.exists(full_save_path), "full-save button delegates to the authoring save transaction")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(full_save_path))
	var tree: StuffDefinition = load("res://resources/stuffs/Tree.tres")
	_expect(controller.select_definition(tree), "catalog definition becomes the active brush")
	controller.update_preview({"hit": true, "cell": Vector3i(1, 1, 0)}, false)
	_expect(controller.get_preview_visual() != null, "valid cell renders the real Stuff model preview")
	_expect(bool(controller.get_preview_result().valid), "preview and commit share the validator result")
	var placement_result: Dictionary = controller.handle_primary({"hit": true, "cell": Vector3i(1, 1, 0)})
	_expect(bool(placement_result.success), "left-click places the selected Stuff")
	_expect(fixture.stuff.get_all_stuff().size() == 1, "runtime editor placement reaches StuffManager")
	var shared_cell := Vector3i(2, 1, 0)
	var original_exclusivity := tree.exclusive_with_other_stuff
	tree.exclusive_with_other_stuff = false
	_expect(session.place_stuff(shared_cell, tree) != null, "fixture adds first non-exclusive Stuff")
	_expect(session.place_stuff(shared_cell, tree) != null, "fixture adds second non-exclusive Stuff")
	controller.select_tool()
	controller.handle_primary({"hit": true, "cell": shared_cell})
	var first_selected: StuffRuntime = controller.get_selected_runtime()
	controller.handle_primary({"hit": true, "cell": shared_cell})
	var second_selected: StuffRuntime = controller.get_selected_runtime()
	_expect(first_selected != null and second_selected != null, "selection tool resolves overlapping Stuff")
	_expect(first_selected.placement_id != second_selected.placement_id, "repeated clicks cycle overlapping Stuff")
	var delete_button := panel.find_child("DeleteSelectedStuffButton", true, false) as Button
	_expect(delete_button != null, "runtime editor exposes an explicit delete button")
	_expect(delete_button != null and not delete_button.disabled, "delete button enables for the selected Stuff instance")
	var count_before_delete: int = fixture.stuff.get_all_stuff().size()
	if delete_button != null:
		delete_button.pressed.emit()
	_expect(fixture.stuff.get_all_stuff().size() == count_before_delete - 1, "delete button removes only the selected overlapping Stuff")
	_expect(controller.get_selected_runtime() == null, "delete button clears the removed selection")
	_expect(delete_button != null and delete_button.disabled, "delete button disables after the selection is removed")
	_expect(not controller.set_active(false), "dirty editor cannot close without save or discard")
	_expect(controller.discard_and_close(), "explicit discard closes the editor")
	tree.exclusive_with_other_stuff = original_exclusivity
	_expect(fixture.stuff.get_all_stuff().is_empty(), "discard restores the opening Stuff snapshot")
	_expect(not time.is_authoring_paused() and is_equal_approx(Engine.time_scale, 2.0), "closing restores the previous fast-time request")
	_expect(not panel.is_workspace_visible(), "workspace collapses after closing")
	first_selected = null
	second_selected = null
	fixture.host.queue_free()
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[RuntimeStuffEditor] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[RuntimeStuffEditor] FAIL: %d/%d checks failed" % [_failures, _checks])
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
	stuff.stuff_catalog = load("res://resources/stuffs/StuffCatalog.tres")
	host.add_child(stuff)
	stuff.configure(grid, terrain)
	var renderer := StuffRendererScript.new()
	host.add_child(renderer)
	renderer.configure(grid, stuff)
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
	_expect(loader.load_level(level, "memory://runtime-stuff-editor"), "runtime editor fixture loads")
	return {
		"host": host,
		"grid": grid,
		"terrain": terrain,
		"stuff": stuff,
		"renderer": renderer,
		"tile": tile,
		"loader": loader,
	}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.display_name = "Runtime Editor Test"
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


func _empty_building_layout() -> Array[BuildingPlacementData]:
	return []


func _empty_mirror_layout() -> Array[MirrorPlacementData]:
	return []


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
