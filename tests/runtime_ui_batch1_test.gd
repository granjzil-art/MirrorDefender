extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")

var _failures: int = 0
var _checks: int = 0
var _placement_results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUiBatch1] running")
	_test_level_and_asset_interfaces()
	var fixture := await _make_fixture()
	await _test_card_bar(fixture)
	await _test_one_shot_placement_and_time_priority(fixture)
	var host: Node = fixture["host"]
	host.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[RuntimeUiBatch1] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[RuntimeUiBatch1] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_level_and_asset_interfaces() -> void:
	var level := LevelResource.new()
	_expect(level.building_card_slot_count == 6, "levels default to six building card slots")
	level.building_card_slot_count = 13
	_expect(
		level.validate_runtime().any(func(message: String) -> bool: return message.contains("卡槽")),
		"level validation rejects out-of-range card slot counts"
	)
	var building := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	var mirror := TestDefinitionFactory.make_copy_mirror_definition()
	_expect(building.card_icon == null, "building definitions expose an optional card icon")
	_expect(mirror.card_icon == null, "copy mirror definitions expose an optional card icon")


func _test_card_bar(fixture: Dictionary) -> void:
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var mirror_manager: MirrorManager = fixture["mirror"]
	var card_bar := BuildCardBarScript.new()
	root.add_child(card_bar)
	await process_frame
	var cards: Array[BuildingDefinition] = [
		building_manager.arrow_tower,
		building_manager.laser_tower,
		building_manager.barrier,
	]
	card_bar.configure(resource_manager, mirror_manager.copy_mirror_definition, cards, 6)
	_expect(card_bar.get_building_slot_count() == 6, "card bar respects the configured six-slot capacity")
	_expect(card_bar.get_filled_building_card_count() == 3, "default loadout fills arrow, laser, and barrier cards")
	_expect(card_bar.get_empty_building_card_count() == 3, "unused loadout positions render as three empty mirror slots")
	_expect(card_bar.is_mirror_card_available(), "dedicated mirror card is available outside building slots")
	_expect(card_bar.is_building_card_available(building_manager.arrow_tower), "affordable building card is available")

	resource_manager.spend(resource_manager.main_resource, "test_empty_wallet")
	_expect(not card_bar.is_building_card_available(building_manager.arrow_tower), "resource shortage disables building cards")
	_expect(not card_bar.is_mirror_card_available(), "resource shortage disables the mirror card")
	resource_manager.gain(500.0, "test_restore_wallet")
	_expect(card_bar.is_building_card_available(building_manager.arrow_tower), "resource gain immediately restores card availability")
	card_bar.queue_free()
	await process_frame

	var hud_scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	_expect(hud_scene != null, "runtime HUD scene loads as a modular component")
	if hud_scene != null:
		var hud := hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		_expect(hud.get_node_or_null("BuildCardBar") != null, "runtime HUD owns the formal bottom card bar")
		_expect(hud.get_node_or_null("TacticalSlowButton") != null, "runtime HUD owns the automatic slow toggle")
		var original_window_size := root.size
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
			root.size = resolution
			await process_frame
			var cards_row := hud.get_node("BuildCardBar/Layout/Cards") as Control
			var slow_button := hud.get_node("TacticalSlowButton") as Control
			# canvas_items keeps the authored 1600x900 logical viewport while the
			# Window scales it to each physical 16:9 resolution.
			var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
			_expect(
				hud.get_node_or_null("BuildCardBar/Layout/Frame") == null,
				"card bar has no outer frame slot at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				cards_row.get_parent() == hud.get_node("BuildCardBar/Layout"),
				"cards are direct layout children at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				cards_row.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"card row gaps do not intercept world input at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				viewport_rect.encloses(cards_row.get_global_rect()),
				"card row stays inside the %dx%d viewport" % [resolution.x, resolution.y]
			)
			_expect(
				not cards_row.get_global_rect().intersects(slow_button.get_global_rect()),
				"card row does not overlap the slow button at %dx%d" % [resolution.x, resolution.y]
			)
		root.size = original_window_size
		hud.queue_free()
		await process_frame


func _test_one_shot_placement_and_time_priority(fixture: Dictionary) -> void:
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var mirror_manager: MirrorManager = fixture["mirror"]
	var grid: GridManager = fixture["grid"]
	var interaction := RuntimeInteractionControllerScript.new()
	fixture["host"].add_child(interaction)
	interaction.configure(building_manager, mirror_manager)
	interaction.placement_resolved.connect(_on_placement_resolved)
	var time_controller := GameTimeControllerScript.new()
	fixture["host"].add_child(time_controller)
	await process_frame
	time_controller.configure(interaction, building_manager, mirror_manager)

	_expect(interaction.select_building_card(building_manager.arrow_tower), "an available building card enters placement mode")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "selecting a card activates default tactical slow")
	time_controller.set_fast_enabled(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "tactical slow overrides the remembered 2x request")

	var first_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(first_result.success, "valid tile placement succeeds")
	_expect(interaction.is_select_mode(), "successful placement consumes the card and returns to select")
	_expect(building_manager.get_selected_building() == null, "newly placed building is not auto-selected by the formal interaction")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 2.0), "successful placement restores the remembered fast scale")
	_expect(_placement_results.size() == 1, "one successful click emits exactly one placement result")

	time_controller.set_fast_enabled(false)
	resource_manager.main_resource = 0.0
	interaction.select_building_card(building_manager.arrow_tower)
	var resource_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(1, 0, 0)},
		{"hit": false}
	)
	_expect(not resource_result.success and resource_result.reason.contains("资源"), "resource failure reports its concrete reason")
	_expect(interaction.is_select_mode(), "resource failure also consumes the selected card")
	_expect(_placement_results.size() == 2, "resource failure emits exactly one placement result")

	resource_manager.main_resource = 500.0
	resource_manager.building_cap = resource_manager.get_building_count()
	interaction.select_building_card(building_manager.arrow_tower)
	var cap_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(1, 0, 0)},
		{"hit": false}
	)
	_expect(not cap_result.success and cap_result.reason.contains("上限"), "building cap failure reports its concrete reason")
	_expect(interaction.is_select_mode(), "cap failure consumes the selected card")
	_expect(_placement_results.size() == 3, "cap failure emits exactly one placement result")

	resource_manager.building_cap = 20
	interaction.select_building_card(building_manager.arrow_tower)
	var occupied_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(not occupied_result.success and occupied_result.reason.contains("占用"), "invalid occupied tile reports placement rejection")
	_expect(interaction.is_select_mode(), "invalid tile consumes the selected card")
	_expect(_placement_results.size() == 4, "invalid tile emits exactly one placement result")

	interaction.select_copy_mirror_card()
	var missing_edge_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 1, 0)},
		{"hit": false}
	)
	_expect(not missing_edge_result.success and missing_edge_result.reason.contains("边"), "missing edge is a concrete failed mirror attempt")
	_expect(interaction.is_select_mode(), "invalid edge consumes the selected mirror card")
	_expect(_placement_results.size() == 5, "invalid edge emits exactly one placement result")

	var edge_index := grid.find_edge_index(Vector3i(0, 1, 0), Vector3i(1, 1, 0))
	interaction.select_copy_mirror_card()
	var mirror_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 1, 0)},
		{
			"hit": true,
			"cell": Vector3i(0, 1, 0),
			"edge_index": edge_index,
			"id": grid.canonical_edge_id(Vector3i(0, 1, 0), edge_index),
		}
	)
	_expect(mirror_result.success, "valid edge places the dedicated copy mirror")
	_expect(interaction.is_select_mode() and mirror_manager.get_selected_mirror() == null, "mirror placement also returns to unselected select mode")
	_expect(_placement_results.size() == 6, "mirror success emits exactly one placement result")

	interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(building_manager.get_selected_building() != null, "select mode can select an existing real building")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "selecting a real building activates tactical slow")
	interaction.cancel_to_select(true)
	_expect(building_manager.get_selected_building() == null, "right-click contract clears real building selection")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "cancelling real selection restores normal time")

	interaction.select_building_card(building_manager.arrow_tower)
	time_controller.set_tactical_slow_enabled(false)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "slow toggle disables automatic tactical scaling")
	time_controller.set_fast_enabled(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 2.0), "2x applies while automatic slow is disabled")
	time_controller.set_tactical_slow_enabled(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "re-enabling slow restores its priority over 2x")
	time_controller.set_paused(true)
	_expect(is_zero_approx(time_controller.get_effective_scale()), "pause has priority over tactical slow")
	time_controller.set_paused(false)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "leaving pause restores the active tactical context")
	interaction.cancel_to_select(true)
	time_controller.set_fast_enabled(false)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "clearing every context restores 1x")


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
	building_manager.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building_manager.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building_manager.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	building_manager.set_edge_occupancy_registry(registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror_manager.configure(grid, tile_manager, resource_manager, combat_manager, building_manager, registry)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	var level := _make_level()
	resource_manager.apply_level_configuration(level)
	_expect(loader.load_level(level, "memory://runtime-ui"), "runtime UI fixture level loads")
	await process_frame
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
		"mirror": mirror_manager,
	}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 3)
	level.initial_resource = 500
	level.building_cap = 20
	level.mirror_cap = 6
	level.base_resource_per_second = 0.0
	level.base_cell = Vector3i(3, 2, 0)
	return level


func _on_placement_resolved(success: bool, reason: String) -> void:
	_placement_results.append({"success": success, "reason": reason})


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
