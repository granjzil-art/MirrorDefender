extends SceneTree

const LevelSelectCatalogScript := preload("res://scripts/level/LevelSelectCatalog.gd")
const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")
const LevelThumbnailScript := preload("res://scripts/ui/LevelThumbnail.gd")
const LevelSelectViewScript := preload("res://scripts/ui/LevelSelectView.gd")
const LevelSelectViewScene := preload("res://scenes/ui/LevelSelectView.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[LevelSelect] running")
	_test_page_and_catalog_validation()
	await _test_view_portal_cube_and_signal()
	await _test_thumbnail_geometry_and_read_only_data()
	_test_default_resources()
	if _failures == 0:
		print("[LevelSelect] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[LevelSelect] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_page_and_catalog_validation() -> void:
	var valid_level := _make_level("Valid")
	var duplicate_page := LevelSelectPageDefinitionScript.new()
	duplicate_page.levels = _level_array([valid_level, valid_level])
	var page_errors := duplicate_page.validate_configuration()
	_expect(_contains_text(page_errors, "重复引用"), "page validation reports duplicate level references")
	_expect(duplicate_page.levels.size() == 2, "page validation does not rewrite duplicate slots")

	var overflow_page := LevelSelectPageDefinitionScript.new()
	overflow_page.levels.resize(5)
	page_errors = overflow_page.validate_configuration()
	_expect(_contains_text(page_errors, "最多只能配置 4"), "page validation rejects more than four portal faces")
	_expect(overflow_page.levels.size() == 5, "overflow validation remains read-only")

	var invalid_level := _make_level("Invalid")
	invalid_level.grid_shape = 99
	var invalid_page := LevelSelectPageDefinitionScript.new()
	invalid_page.levels = _level_array([invalid_level])
	page_errors = invalid_page.validate_configuration()
	_expect(_contains_text(page_errors, "关卡无效"), "page validation reports invalid LevelResource content")
	_expect(invalid_level.grid_shape == 99, "invalid-level validation does not repair authored data")

	var cross_page := LevelSelectPageDefinitionScript.new()
	cross_page.levels = _level_array([valid_level])
	var catalog := LevelSelectCatalogScript.new()
	catalog.pages = _page_array([duplicate_page, null, cross_page])
	var catalog_errors := catalog.validate_configuration()
	_expect(_contains_text(catalog_errors, "第 2 页引用为空"), "catalog validation reports null page references")
	_expect(_contains_text(catalog_errors, "重复引用同一关卡"), "catalog validation reports levels repeated across pages")
	_expect(catalog.pages.size() == 3 and catalog.pages[1] == null, "catalog validation preserves page ordering and nulls")

	var path_page := LevelSelectPageDefinitionScript.new()
	path_page.level_paths = PackedStringArray([
		"res://resources/levels/Level1.tres",
		"res://resources/levels/Level1.tres",
	])
	_expect(
		_contains_text(path_page.validate_configuration(), "重复引用"),
		"path-backed page validation detects duplicate levels without retaining resources"
	)


func _test_view_portal_cube_and_signal() -> void:
	var levels: Array[LevelResource] = []
	for index in range(4):
		levels.append(_make_level("Level %d" % (index + 1)))
	var page := LevelSelectPageDefinitionScript.new()
	page.display_name = "Portal Cube"
	page.levels = _level_array([levels[0], null, levels[1], levels[2]])
	var catalog := LevelSelectCatalogScript.new()
	catalog.pages = _page_array([page])

	var view: LevelSelectViewScript = LevelSelectViewScene.instantiate() as LevelSelectViewScript
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280.0, 720.0)
	root.add_child(view)
	await process_frame
	view.configure(catalog)
	await process_frame
	await process_frame

	var background := view.get_node("Background") as ColorRect
	var viewport_container := view.get_node("CubeViewportContainer") as SubViewportContainer
	var cube_viewport := view.get_node("CubeViewportContainer/CubeViewport") as SubViewport
	_expect(background.color == Color(0.006, 0.01, 0.016, 1.0), "portal cube uses the authored dark background")
	_expect(viewport_container.stretch, "cube viewport stretches with the full-screen selection view")
	_expect(cube_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "outer cube viewport remains live while the cube rotates")
	_expect(view.get_slot_count() == 4 and view.get_face_count() == 4, "selection cube owns exactly four level faces")
	_expect(view.get_title_face() != null and view.get_base_root() != null, "cube owns a title top and a non-selectable display base")
	_expect(not view.is_previous_page_visible() and not view.is_next_page_visible(), "four-face selection has no paging arrows")
	_expect(view.get_face_level(0) == levels[0] and view.get_face_level(2) == levels[1], "face order preserves authored level order without compacting holes")
	_expect(view.get_face_level(1) == null, "authored null remains an empty cube face")
	_expect(view.get_face_area(0).collision_layer != 0, "filled level face participates in selection raycasts")
	_expect(view.get_face_area(1).collision_layer == 0, "empty level face is excluded from selection raycasts")
	_expect(view.get_face_area(0).get_meta("level_face_index") == 0, "face hit area retains its stable authored index")
	_expect(view.get_loaded_level_count() == 3, "selection view owns only its three non-empty transient preview levels")

	var first_preview = view.get_preview(0)
	_expect(first_preview != null and first_preview.get_level() == levels[0], "first face owns an isolated preview viewport for its exact level")
	_expect(first_preview.is_loaded(), "valid sparse level loads into the preview renderer stack")
	_expect(first_preview.get_content_scale() > 0.0, "preview content is normalized into the canonical display volume")
	_expect(first_preview.get_preview_camera().projection == Camera3D.PROJECTION_FRUSTUM, "visible preview uses an off-axis frustum")
	for face_index in range(4):
		var preview = view.get_preview(face_index)
		var label_instance := preview.get_level_label_mesh() as MeshInstance3D
		var label_geometry := label_instance.mesh as TextMesh
		_expect(preview.get_level_label_text() == "Level%d" % (face_index + 1), "face %d owns its stable level number" % (face_index + 1))
		_expect(label_geometry != null and label_geometry.depth > 0.0, "face %d level number is extruded TextMesh geometry" % (face_index + 1))
	_expect(view.get_preview(0).get_level_label_mesh().visible, "loaded level shows its physical number above the scene")
	_expect(not view.get_preview(1).get_level_label_mesh().visible, "empty level keeps its physical number hidden")
	_expect(absf(view.get_preview(0).get_level_label_mesh().position.z) < 0.75, "level number is suspended over the normalized scene center instead of the cabinet edge")

	var camera_transform := view.get_cube_camera().global_transform
	var yaw_before := view.get_cube_yaw()
	var pitch_before := view.get_cube_pitch()
	var observer_before := first_preview.get_last_observer_local()
	view.apply_drag_for_test(Vector2(36.0, -18.0))
	await process_frame
	_expect(view.get_cube_yaw() > yaw_before, "rightward drag increases cube yaw after horizontal direction inversion")
	_expect(view.get_cube_pitch() < pitch_before, "upward drag decreases cube pitch after vertical direction inversion")
	_expect(view.get_cube_camera().global_transform.is_equal_approx(camera_transform), "dragging changes the cube, never the fixed external camera")
	_expect(not first_preview.get_last_observer_local().is_equal_approx(observer_before), "cube rotation remaps the observer inside the face preview world")

	view.apply_drag_for_test(Vector2(0.0, -10000.0))
	_expect(view.get_cube_pitch() <= deg_to_rad(view.maximum_pitch_degrees) + 0.0001, "cube pitch is clamped before exposing the underside")

	var selected: Array[LevelResource] = []
	view.level_selected.connect(func(level: LevelResource) -> void: selected.append(level))
	view.activate_face_for_test(1)
	_expect(selected.is_empty(), "empty cube face emits no level")
	view.activate_face_for_test(0)
	_expect(selected.size() == 1 and selected[0] == levels[0], "filled cube face emits the exact LevelResource")
	_expect(view.get_loaded_level_count() == 0, "accepted selection immediately releases every preview level reference")
	view.activate_face_for_test(2)
	_expect(selected.size() == 1, "selection locks after the first accepted face activation")

	view.size = Vector2(1600.0, 900.0)
	await process_frame
	_expect(viewport_container.size.is_equal_approx(view.size), "portal cube remains full-screen after resizing")
	view.queue_free()
	await process_frame
	return


func _test_thumbnail_geometry_and_read_only_data() -> void:
	var hex_level := _make_level("Hex")
	hex_level.grid_shape = 0
	hex_level.grid_size = Vector2i(1, 1)
	var explicit_tile := TileCellData.new()
	explicit_tile.configure(Vector3i.ZERO, TileCellData.TileType.BUILDABLE, 1)
	hex_level.tiles = [explicit_tile]
	var hex_spawn := SpawnPointDefinition.new()
	hex_spawn.spawn_id = &"thumbnail_spawn"
	hex_spawn.cell = Vector3i(-1, 1, 0)
	hex_spawn.display_number = 2
	var hex_base := BasePointDefinition.new()
	hex_base.base_id = &"thumbnail_base"
	hex_base.cell = Vector3i(1, -1, 0)
	hex_base.display_number = 3
	var hex_path := PathDefinition.new()
	hex_path.path_id = &"thumbnail_path"
	hex_path.cells = [hex_spawn.cell, Vector3i.ZERO, hex_base.cell]
	hex_path.spawn_point = hex_spawn
	hex_path.target_base = hex_base
	hex_level.spawn_points.assign([hex_spawn])
	hex_level.base_points.assign([hex_base])
	hex_level.paths.assign([hex_path])
	var original_tiles := hex_level.tiles.duplicate()
	var thumbnail := LevelThumbnailScript.new()
	thumbnail.size = Vector2(300.0, 170.0)
	root.add_child(thumbnail)
	thumbnail.set_level(hex_level)
	await process_frame
	var hex_data := thumbnail.debug_get_draw_data()
	_expect(thumbnail.debug_get_geometry_tag() == &"hex", "thumbnail instantiates flat-top HEX geometry")
	_expect(hex_data.size() == 7, "radius-one HEX thumbnail prepares all seven cells")
	_expect(_count_implicit_cells(hex_data) == 6, "sparse HEX cells are prepared as default buildable terrain")
	var hex_paths := thumbnail.debug_get_path_draw_data()
	var hex_spawns := thumbnail.debug_get_spawn_draw_data()
	var hex_bases := thumbnail.debug_get_base_draw_data()
	_expect(hex_paths.size() == 1 and hex_paths[0].size() == 3, "HEX thumbnail prepares the complete authored path polyline")
	_expect(hex_spawns.size() == 1 and int(hex_spawns[0]["number"]) == 2, "HEX thumbnail preserves the authored spawn marker number")
	_expect(hex_bases.size() == 1 and int(hex_bases[0]["number"]) == 3, "HEX thumbnail preserves the authored base marker number")
	hex_paths[0][0] = Vector2(999.0, 999.0)
	_expect(thumbnail.debug_get_path_draw_data()[0][0] != Vector2(999.0, 999.0), "thumbnail overlay debug data is returned as a defensive copy")
	_expect(hex_level.tiles == original_tiles and hex_level.get("_legacy_base_point") == null, "HEX thumbnail leaves LevelResource data and compatibility cache untouched")

	var square_level := _make_level("Square")
	square_level.grid_shape = 1
	square_level.grid_size = Vector2i(3, 2)
	var original_grid_size := square_level.grid_size
	thumbnail.set_level(square_level)
	await process_frame
	var square_data := thumbnail.debug_get_draw_data()
	_expect(thumbnail.debug_get_geometry_tag() == &"square", "thumbnail instantiates SQUARE geometry")
	_expect(square_data.size() == 6 and _count_implicit_cells(square_data) == 6, "sparse SQUARE thumbnail prepares every missing cell")
	_expect(thumbnail.debug_get_base_draw_data().size() == 1, "SQUARE thumbnail supports the legacy base_cell marker")
	_expect(square_level.grid_size == original_grid_size and square_level.tiles.is_empty(), "SQUARE thumbnail preparation is read-only")
	thumbnail.clear()
	_expect(thumbnail.get_level() == null and thumbnail.debug_get_draw_data().is_empty(), "thumbnail clear removes only preview state")
	thumbnail.queue_free()
	await process_frame


func _test_default_resources() -> void:
	var catalog: LevelSelectCatalogScript = load("res://resources/level_select/LevelSelectCatalog.tres") as LevelSelectCatalogScript
	_expect(catalog != null and catalog.get_page_count() > 0, "default catalog loads with at least one authored page")
	if catalog == null:
		return
	var pages_fit_fixed_grid := true
	var authored_pages_are_path_backed := true
	for page_index in range(catalog.get_page_count()):
		var page: LevelSelectPageDefinitionScript = catalog.get_page(page_index)
		pages_fit_fixed_grid = pages_fit_fixed_grid and page != null and page.get_configured_slot_count() <= LevelSelectPageDefinitionScript.SLOT_COUNT
		authored_pages_are_path_backed = authored_pages_are_path_backed and page != null and page.levels.is_empty()
	_expect(pages_fit_fixed_grid, "every authored page fits the fixed four-face cube")
	_expect(authored_pages_are_path_backed, "authored selection pages retain paths instead of LevelResource objects")
	var page_dependencies := ResourceLoader.get_dependencies("res://resources/level_select/LevelSelectPage01.tres")
	var retains_level_dependency := false
	for dependency in page_dependencies:
		if String(dependency).contains("res://resources/levels/"):
			retains_level_dependency = true
	_expect(not retains_level_dependency, "authored page resource has no eager dependency on any full level")
	return


func _make_level(display_name: String) -> LevelResource:
	var level := LevelResource.new()
	level.display_name = display_name
	return level


func _level_array(values: Array) -> Array[LevelResource]:
	var result: Array[LevelResource] = []
	for value in values:
		result.append(value as LevelResource)
	return result


func _page_array(values: Array) -> Array[LevelSelectPageDefinitionScript]:
	var result: Array[LevelSelectPageDefinitionScript] = []
	for value in values:
		result.append(value as LevelSelectPageDefinitionScript)
	return result


func _count_implicit_cells(draw_data: Array[Dictionary]) -> int:
	var count := 0
	for cell_data in draw_data:
		if not bool(cell_data["is_explicit"]):
			count += 1
	return count


func _contains_text(values: Array[String], fragment: String) -> bool:
	for value in values:
		if fragment in value:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
