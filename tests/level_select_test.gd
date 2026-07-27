extends SceneTree

const LevelSelectCatalogScript := preload("res://scripts/level/LevelSelectCatalog.gd")
const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")
const LevelThumbnailScript := preload("res://scripts/ui/LevelThumbnail.gd")
const LevelSelectSlotScript := preload("res://scripts/ui/LevelSelectSlot.gd")
const LevelSelectViewScript := preload("res://scripts/ui/LevelSelectView.gd")
const LevelSelectViewScene := preload("res://scenes/ui/LevelSelectView.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[LevelSelect] running")
	_test_page_and_catalog_validation()
	await _test_view_slots_paging_and_signal()
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
	overflow_page.levels.resize(7)
	page_errors = overflow_page.validate_configuration()
	_expect(_contains_text(page_errors, "最多只能配置 6"), "page validation rejects more than six slots")
	_expect(overflow_page.levels.size() == 7, "overflow validation remains read-only")

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


func _test_view_slots_paging_and_signal() -> void:
	var levels: Array[LevelResource] = []
	for index in range(8):
		levels.append(_make_level("Level %d" % (index + 1)))
	var page_1 := LevelSelectPageDefinitionScript.new()
	page_1.display_name = "Page One"
	page_1.levels = _level_array([levels[0], null, levels[1], levels[2], levels[3], levels[4]])
	var page_2 := LevelSelectPageDefinitionScript.new()
	page_2.levels = _level_array([levels[5]])
	var page_3 := LevelSelectPageDefinitionScript.new()
	page_3.levels = _level_array([levels[6], levels[7]])
	var catalog := LevelSelectCatalogScript.new()
	catalog.pages = _page_array([page_1, page_2, page_3])

	var view: LevelSelectViewScript = LevelSelectViewScene.instantiate() as LevelSelectViewScript
	root.add_child(view)
	await process_frame
	view.configure(catalog)
	await process_frame
	_expect(view.get_slot_count() == 6, "view always creates exactly six slots")
	_expect(view.get_slot_level(0) == levels[0] and view.get_slot_level(2) == levels[1], "slot order follows authored page order")
	_expect(view.get_slot_level(1) == null, "authored null remains an empty slot")
	var empty_slot: LevelSelectSlotScript = view.get_node("Center/Panel/Content/LevelGrid/LevelSlot2") as LevelSelectSlotScript
	_expect(empty_slot != null and empty_slot.disabled, "empty slot is visible and non-clickable")
	_expect(not view.is_previous_page_visible() and view.is_next_page_visible(), "first page shows only the right arrow")

	var selected: Array[LevelResource] = []
	view.level_selected.connect(func(level: LevelResource) -> void: selected.append(level))
	var first_slot: LevelSelectSlotScript = view.get_node("Center/Panel/Content/LevelGrid/LevelSlot1") as LevelSelectSlotScript
	first_slot.pressed.emit()
	_expect(selected.size() == 1 and selected[0] == levels[0], "filled-slot click emits the exact LevelResource")
	empty_slot.pressed.emit()
	_expect(selected.size() == 1, "empty-slot activation emits no level")

	var next_button := view.get_node("Center/Panel/Content/Navigation/NextButton") as Button
	var previous_button := view.get_node("Center/Panel/Content/Navigation/PreviousButton") as Button
	next_button.pressed.emit()
	_expect(view.get_current_page_index() == 1, "right arrow advances one page")
	_expect(view.is_previous_page_visible() and view.is_next_page_visible(), "middle page shows both arrows")
	next_button.pressed.emit()
	_expect(view.get_current_page_index() == 2, "right arrow reaches the final page")
	_expect(view.is_previous_page_visible() and not view.is_next_page_visible(), "last page shows only the left arrow")
	previous_button.pressed.emit()
	_expect(view.get_current_page_index() == 1, "left arrow returns one page")
	var single_page_catalog := LevelSelectCatalogScript.new()
	single_page_catalog.pages = _page_array([page_1])
	view.configure(single_page_catalog)
	_expect(not view.is_previous_page_visible() and not view.is_next_page_visible(), "single-page catalog hides both arrows")
	view.queue_free()
	await process_frame


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
	var page: LevelSelectPageDefinitionScript = catalog.get_page(0) if catalog != null else null
	_expect(catalog != null and catalog.get_page_count() == 1, "default catalog loads with one page")
	_expect(page != null and page.get_level(0) != null, "default first slot contains the official level")
	_expect(page != null and page.get_level(0).resource_path == "res://resources/levels/M4DemoLevel.tres", "default catalog publishes only M4DemoLevel in slot one")
	var other_slots_empty := page != null
	if page != null:
		for slot_index in range(1, LevelSelectPageDefinitionScript.SLOT_COUNT):
			other_slots_empty = other_slots_empty and page.get_level(slot_index) == null
	_expect(other_slots_empty, "default page leaves the remaining five slots empty")


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
