extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const TileInspectionServiceScript := preload("res://scripts/ui/TileInspectionService.gd")
const TileInspectorPanelScript := preload("res://scripts/ui/TileInspectorPanel.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUiBatch2] running")
	var fixture := await _make_fixture()
	await _test_inspection_model(fixture)
	await _test_runtime_hud_selection_and_layout(fixture)
	var host: Node = fixture["host"]
	host.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[RuntimeUiBatch2] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeUiBatch2] FAIL: %d of %d checks failed" % [_failures, _checks])
	quit(1)


func _test_inspection_model(fixture: Dictionary) -> void:
	var service: TileInspectionServiceScript = fixture["inspection"]
	var building_manager: BuildingManager = fixture["building"]
	var mirror_manager: MirrorManager = fixture["mirror"]
	var tile_manager: TileManager = fixture["tile"]
	var source_cell := Vector3i(1, 1, 0)
	var target_cell := Vector3i(2, 1, 0)
	var spike_cell := Vector3i(0, 2, 0)
	var void_cell := Vector3i(1, 2, 0)
	var rock_cell := Vector3i(2, 2, 0)

	var source_model: Dictionary = service.inspect_cell(source_cell)
	var source_entries: Array = source_model["entries"]
	_expect(source_model.has_content, "source cell is non-empty")
	_expect(source_entries.size() == 3, "source cell lists its tower and both adjacent edge entities")
	_expect(_find_entry(source_entries, &"building") != null, "source model contains the real block building")
	_expect(_find_entry(source_entries, &"edge_building") != null, "source model contains the real edge building")
	_expect(_find_entry(source_entries, &"mirror") != null, "source model contains the adjacent copy mirror")

	var projection_model: Dictionary = service.inspect_cell(target_cell)
	var projection_entries: Array = projection_model["entries"]
	var projection_entry: Dictionary = _find_entry(projection_entries, &"projection")
	_expect(not projection_entry.is_empty(), "projected cell lists the mirror projection")
	_expect(String(projection_entry.get("state")) == "虚像", "projection entry is explicitly marked as virtual")
	_expect(bool(projection_entry.get("has_source")), "projection entry exposes a root source")
	_expect(projection_entry.get("source_cell") == source_cell, "projection entry reports the real root cell")
	_expect(not String(projection_entry.get("mirror_edge_id", "")).is_empty(), "projection entry reports its producing mirror")
	var source_tower_entry: Dictionary = _find_entry(source_entries, &"building")
	_expect(String(source_tower_entry.get("description")) == "测试箭塔自定义说明。", "building entry uses the definition's editable function description verbatim")
	for combat_fragment in ["索敌 8.0 · 射程 7.0", "攻速 1.00/s · 产出 0.0/s", "对空中敌人：有效"]:
		_expect(_lines_contain(source_tower_entry, combat_fragment), "real tower exposes %s" % combat_fragment)
		_expect(_lines_contain(projection_entry, combat_fragment), "copied tower keeps source combat information: %s" % combat_fragment)
	var laser_cell := Vector3i(3, 3, 0)
	var laser := building_manager.place_building(laser_cell, building_manager.laser_tower)
	_expect(laser != null, "fixture places a laser tower for combat-summary regression")
	var laser_entry: Dictionary = _find_entry(service.inspect_cell(laser_cell).entries, &"building")
	_expect(_lines_contain(laser_entry, "DPS 12.0"), "laser tower displays its final continuous DPS")
	_expect(not _lines_contain(laser_entry, "攻速"), "laser tower does not display the unused projectile attack rate")

	var spike_entry: Dictionary = _find_entry(service.inspect_cell(spike_cell).entries, &"tile_element")
	_expect(_lines_contain(spike_entry, "持续伤害"), "spike entry exposes its live DPS parameters")
	var void_entry: Dictionary = _find_entry(service.inspect_cell(void_cell).entries, &"tile_element")
	_expect(_lines_contain(void_entry, "装填：0 / 3"), "void entry exposes current and maximum capacity")
	var rock_entry: Dictionary = _find_entry(service.inspect_cell(rock_cell).entries, &"tile_element")
	_expect(_lines_contain(rock_entry, "耐久：500 / 500"), "rock entry exposes runtime durability")
	var rock: TileObstacleRuntime = tile_manager.get_runtime_obstacle(rock_cell)
	rock.take_structure_damage(125.0)
	_expect(_lines_contain(_find_entry(service.inspect_cell(rock_cell).entries, &"tile_element"), "耐久：375 / 500"), "rock inspection reads updated runtime durability")

	var edge_building: Building = fixture["edge_building"]
	service.set_selected_cell(true, source_cell)
	edge_building.take_structure_damage(25.0)
	await process_frame
	await process_frame
	var changed_edge: Dictionary = _find_entry(service.inspect_cell(source_cell).entries, &"edge_building")
	_expect(_lines_contain(changed_edge, "耐久：125 / 150"), "selected-cell model refreshes after building durability changes")

	var tower: Building = building_manager.get_building(source_cell)
	var previous_facing := tower.facing_index
	tower.rotate_facing()
	await process_frame
	_expect(tower.facing_index != previous_facing, "fixture tower rotates through the existing building operation")
	var changed_tower: Dictionary = _find_entry(service.inspect_cell(source_cell).entries, &"building")
	_expect(_lines_contain(changed_tower, "朝向：2 / 8"), "selected-cell model refreshes after facing changes")

	var mirror: CopyMirror = fixture["copy_mirror"]
	var previous_active_cell := mirror.get_active_cell()
	mirror_manager.select_mirror(mirror)
	_expect(mirror_manager.flip_selected(), "existing mirror flip transaction remains available")
	await process_frame
	var mirror_entry: Dictionary = _find_entry(service.inspect_cell(source_cell).entries, &"mirror")
	_expect(mirror.get_active_cell() != previous_active_cell, "mirror flip changes its active side")
	_expect(_lines_contain(mirror_entry, str(mirror.get_active_cell())), "mirror entry refreshes its active-side information")

	var tile_definition := TileDefinition.new()
	_expect(tile_definition.get("ui_icon") == null, "tile definitions expose an optional inspector icon")


func _test_runtime_hud_selection_and_layout(fixture: Dictionary) -> void:
	var interaction := RuntimeInteractionController.new()
	fixture["host"].add_child(interaction)
	interaction.configure(fixture["building"], fixture["mirror"])
	var time_controller := GameTimeController.new()
	fixture["host"].add_child(time_controller)
	time_controller.configure(interaction, fixture["building"], fixture["mirror"])
	var hud_scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	_expect(hud_scene != null, "batch 2 runtime HUD scene loads")
	if hud_scene == null:
		return
	var hud: RuntimeHud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.configure(
		interaction,
		time_controller,
		fixture["resource"],
		fixture["building"],
		fixture["mirror"],
		6
	)
	hud.configure_inspection(
		fixture["grid"],
		fixture["tile"],
		fixture["building"],
		fixture["mirror"],
		fixture["tile_effect"]
	)
	var panel: TileInspectorPanelScript = hud.get_node("TileInspectorPanel")
	_expect(hud.get_node_or_null("TileInspectionService") != null, "runtime HUD owns the read-only inspection service")
	_expect(panel != null, "runtime HUD owns the right-side inspector panel")

	interaction.handle_primary({"hit": true, "cell": Vector3i(4, 3, 0)}, {"hit": false})
	await process_frame
	_expect(not panel.visible, "selecting an empty tile keeps the inspector collapsed")

	interaction.handle_primary({"hit": true, "cell": Vector3i(1, 1, 0)}, {"hit": false})
	await process_frame
	_expect(panel.visible, "selecting a non-empty tile opens the inspector")
	_expect(panel.get_entry_count() == 3, "panel renders every source-cell entry")
	_expect(fixture["building"].get_selected_building() != null, "real building selection still uses BuildingManager")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "real building selection still activates tactical slow")
	_expect((panel.get_node("GlassPanel") as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "inspector consumes UI clicks instead of passing them to the world")

	interaction.cancel_to_select(true)
	await process_frame
	_expect(not panel.visible, "right-click contract collapses the inspector")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "cancelling inspection restores normal time")

	interaction.handle_primary({"hit": true, "cell": Vector3i(2, 1, 0)}, {"hit": false})
	await process_frame
	_expect(panel.visible, "a projection-only cell opens the inspector")
	_expect(fixture["building"].get_selected_building() == null, "virtual projection inspection does not select a real building")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "projection-only inspection does not activate tactical slow")

	var original_window_size := root.size
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
		var panel_rect: Rect2 = panel.get_global_rect()
		var cards_rect := (hud.get_node("BuildCardBar/Layout/Cards") as Control).get_global_rect()
		_expect(viewport_rect.encloses(panel_rect), "inspector stays inside the %dx%d viewport" % [resolution.x, resolution.y])
		_expect(not panel_rect.intersects(cards_rect), "inspector does not overlap cards at %dx%d" % [resolution.x, resolution.y])
	root.size = original_window_size

	var many_entries: Array[Dictionary] = []
	for index in range(12):
		many_entries.append({
			"kind": &"building",
			"name": "条目 %d" % index,
			"category": "块建筑",
			"state": "实体",
			"icon": null,
			"accent": Color(0.3, 0.8, 1.0),
			"lines": ["等级：L1 / L3", "耐久：100 / 100"],
		})
	panel.display_model({
		"has_content": true,
		"cell": Vector3i.ZERO,
		"terrain_name": "测试地块",
		"height_level": 0,
		"allows_tile_building": true,
		"allows_edge_building": true,
		"entries": many_entries,
	})
	await process_frame
	_expect(panel.get_entry_count() == 12, "panel dynamically renders an arbitrary entry count")
	var entries_box := panel.get_node("GlassPanel/Layout/EntriesScroll/Entries") as Control
	_expect(entries_box.size.y > panel.get_scroll_container().size.y, "overflowing entries are contained by the scroll view")
	hud.queue_free()
	interaction.queue_free()
	time_controller.queue_free()
	await process_frame


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var registry := EdgeOccupancyRegistry.new()
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	var arrow_inspection := InspectionDisplayConfig.new()
	arrow_inspection.function_description = "测试箭塔自定义说明。"
	building_manager.arrow_tower.inspection_display = arrow_inspection
	building_manager.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building_manager.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building_manager.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	building_manager.set_edge_occupancy_registry(registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror_manager.configure(grid, tile_manager, resource_manager, combat_manager, building_manager, registry)
	var tile_effect_system := TileEffectSystem.new()
	host.add_child(tile_effect_system)
	tile_effect_system.configure(tile_manager)
	tile_effect_system.set_effect_overlay_resolver(Callable(mirror_manager, "get_projected_effects"))
	tile_effect_system.set_effect_overlay_binding_resolver(Callable(mirror_manager, "get_projected_effect_bindings"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	var level := _make_level()
	resource_manager.apply_level_configuration(level)
	_expect(loader.load_level(level, "memory://runtime-ui-batch2"), "batch 2 fixture level loads")
	await process_frame

	var source_cell := Vector3i(1, 1, 0)
	var tower := building_manager.place_building(source_cell, building_manager.arrow_tower)
	_expect(tower != null, "fixture places a real source tower")
	var edge_to := Vector3i(1, 0, 0)
	var edge_index := grid.find_edge_index(source_cell, edge_to)
	var edge_building := building_manager.place_edge_building(source_cell, edge_index, building_manager.edge_barrier)
	_expect(edge_building != null, "fixture places an adjacent edge building")
	var target_cell := Vector3i(2, 1, 0)
	var mirror_edge_index := grid.find_edge_index(source_cell, target_cell)
	var copy_mirror := mirror_manager.place_copy_mirror(source_cell, mirror_edge_index, true)
	_expect(copy_mirror != null, "fixture places an adjacent copy mirror")
	await process_frame
	mirror_manager.rebuild_now()
	_expect(not mirror_manager.get_projections(target_cell).is_empty(), "fixture creates a projection on the opposite cell")

	var inspection: TileInspectionServiceScript = TileInspectionServiceScript.new()
	host.add_child(inspection)
	inspection.configure(grid, tile_manager, building_manager, mirror_manager, tile_effect_system)
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
		"mirror": mirror_manager,
		"tile_effect": tile_effect_system,
		"inspection": inspection,
		"edge_building": edge_building,
		"copy_mirror": copy_mirror,
	}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(5, 4)
	level.initial_resource = 1000
	level.building_cap = 20
	level.mirror_cap = 6
	level.base_resource_per_second = 0.0
	level.base_cell = Vector3i(4, 3, 0)
	level.tiles = [
		_make_element_tile(Vector3i(0, 2, 0), "尖刺格子", TileDefinition.VisualKind.SPIKES, SpikeTileEffect.new()),
		_make_element_tile(Vector3i(1, 2, 0), "空洞格子", TileDefinition.VisualKind.HOLE, VoidTileEffect.new()),
		_make_element_tile(Vector3i(2, 2, 0), "大石头障碍", TileDefinition.VisualKind.ROCK, RockTileEffect.new()),
	]
	return level


func _make_element_tile(cell: Vector3i, display_name: String, visual_kind: int, effect: TileEffect) -> TileCellData:
	var definition := TileDefinition.new()
	definition.tile_id = StringName(display_name)
	definition.display_name = display_name
	definition.surface_kind = TileDefinition.SurfaceKind.ELEMENT
	definition.allows_tile_building = false
	definition.allows_edge_building = true
	definition.visual_kind = visual_kind
	definition.effect = effect
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.BUILDABLE, 0, definition)
	return tile


func _find_entry(entries: Array, kind: StringName) -> Dictionary:
	for raw_entry in entries:
		if raw_entry is Dictionary and StringName(raw_entry.get("kind", &"")) == kind:
			return raw_entry
	return {}


func _lines_contain(entry: Dictionary, fragment: String) -> bool:
	var raw_lines: Variant = entry.get("lines", [])
	if not raw_lines is Array:
		return false
	for raw_line in raw_lines:
		if fragment in String(raw_line):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
