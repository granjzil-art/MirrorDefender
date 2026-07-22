extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0
var _restart_requests: int = 0
var _exit_requests: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUiBatch3] running")
	_test_settings_persistence()
	var fixture := await _make_fixture()
	await _test_economy_panel(fixture)
	await _test_global_info_panel(fixture)
	await _test_time_controls_and_pause_menu(fixture)
	await _test_runtime_hud_integration_and_layout(fixture)
	await _test_level_reload(fixture)
	var host: Node = fixture["host"]
	host.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	_cleanup_settings_file(_test_settings_path())
	if _failures == 0:
		print("[RuntimeUiBatch3] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeUiBatch3] FAIL: %d of %d checks failed" % [_failures, _checks])
	quit(1)


func _test_settings_persistence() -> void:
	var path := _test_settings_path()
	_cleanup_settings_file(path)
	var settings := RuntimeSettings.new()
	settings.set_values(37.0, true, 1.25)
	_expect(settings.save_to_file(path) == OK, "runtime settings save to an isolated user cfg")
	var loaded := RuntimeSettings.new()
	_expect(loaded.load_from_file(path) == OK, "runtime settings reload from user cfg")
	_expect(is_equal_approx(loaded.main_volume_percent, 37.0), "saved main volume round-trips")
	_expect(loaded.fullscreen, "saved fullscreen mode round-trips")
	_expect(is_equal_approx(loaded.ui_scale, 1.25), "saved UI scale round-trips")
	loaded.set_values(-10.0, false, 9.0)
	_expect(is_zero_approx(loaded.main_volume_percent) and is_equal_approx(loaded.ui_scale, 1.5), "runtime settings clamp editable ranges")


func _test_economy_panel(fixture: Dictionary) -> void:
	var scene := load("res://scenes/ui/EconomyPanel.tscn") as PackedScene
	_expect(scene != null, "economy panel scene loads")
	if scene == null:
		return
	var panel := scene.instantiate() as EconomyPanel
	root.add_child(panel)
	await process_frame
	var resource_manager: ResourceManager = fixture["resource"]
	panel.configure(resource_manager)
	var initial := panel.get_displayed_resource()
	resource_manager.gain(25.0, "batch3_gain")
	_expect(is_equal_approx(panel.get_displayed_resource(), initial), "resource number does not jump immediately")
	_expect(panel.get_popup_count() == 1, "one resource event creates one popup")
	Engine.time_scale = 0.0
	panel.advance_ui_time(panel.number_roll_duration * 0.5)
	_expect(panel.get_displayed_resource() > initial and panel.get_displayed_resource() < initial + 25.0, "resource number rolls between old and new values while paused")
	panel.advance_ui_time(panel.number_roll_duration)
	_expect(is_equal_approx(panel.get_displayed_resource(), initial + 25.0), "resource number reaches the latest real value")
	resource_manager.spend(10.0, "batch3_spend")
	_expect(panel.get_popup_count() == 2, "consecutive changes preserve separate popups")
	panel.advance_ui_time(panel.popup_duration + 0.01)
	_expect(panel.get_popup_count() == 0, "resource popups rise and expire in unscaled UI time")
	Engine.time_scale = 1.0
	panel.queue_free()
	await process_frame


func _test_global_info_panel(fixture: Dictionary) -> void:
	var scene := load("res://scenes/ui/GlobalInfoPanel.tscn") as PackedScene
	_expect(scene != null, "global information panel scene loads")
	if scene == null:
		return
	var panel := scene.instantiate() as GlobalInfoPanel
	root.add_child(panel)
	await process_frame
	var resource_manager: ResourceManager = fixture["resource"]
	var wave_manager: WaveManager = fixture["wave"]
	var base_core: BaseCore = fixture["base"]
	panel.configure(resource_manager, wave_manager, base_core)
	var level: LevelResource = fixture["level"]
	panel.set_level_context(level, "res://resources/levels/FallbackName.tres")
	base_core.current_hp = 75.0
	base_core.max_hp = 120.0
	base_core.health_changed.emit(base_core.current_hp, base_core.max_hp)
	wave_manager.state_changed.emit(WaveManager.State.ACTIVE, 1, 3, 4)
	resource_manager.try_register_building(0.0)
	resource_manager.try_register_mirror(0.0)
	var summary := panel.get_summary_text()
	_expect(summary.contains("批次 3 测试关卡"), "global panel uses the editable level display name")
	_expect(summary.contains("据点 75 / 120 HP"), "global panel follows BaseCore health signals")
	_expect(summary.contains("场上敌人 · 4"), "global panel follows WaveManager enemy counts")
	_expect(summary.contains("建筑 1/20 · 镜子 1/6"), "global panel follows ResourceManager entity caps")
	level.display_name = ""
	panel.set_level_context(level, "res://resources/levels/FallbackName.tres")
	_expect(panel.get_summary_text().contains("FallbackName"), "level filename is the stable fallback display name")
	level.display_name = "批次 3 测试关卡"
	resource_manager.unregister_building()
	resource_manager.unregister_mirror()
	panel.queue_free()
	await process_frame


func _test_time_controls_and_pause_menu(fixture: Dictionary) -> void:
	var time_scene := load("res://scenes/ui/TimeControlPanel.tscn") as PackedScene
	_expect(time_scene != null, "time control panel scene loads")
	if time_scene == null:
		return
	var controls := time_scene.instantiate() as TimeControlPanel
	root.add_child(controls)
	await process_frame
	var time_controller: GameTimeController = fixture["time"]
	controls.configure(time_controller)
	controls.fast_button.set_pressed_no_signal(true)
	controls.fast_button.pressed.emit()
	_expect(time_controller.is_fast_enabled() and is_equal_approx(time_controller.get_effective_scale(), 2.0), "formal 2x button toggles fast time")
	controls.pause_button.pressed.emit()
	_expect(time_controller.is_paused() and is_zero_approx(time_controller.get_effective_scale()), "formal pause button has highest priority")
	_expect(controls.pause_button.text == "继续", "pause button exposes its resume action")
	controls.pause_button.pressed.emit()
	_expect(not time_controller.is_paused() and is_equal_approx(time_controller.get_effective_scale(), 2.0), "resume restores remembered fast time")
	time_controller.set_fast_enabled(false)
	controls.queue_free()
	await process_frame

	var pause_scene := load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	_expect(pause_scene != null, "pause menu scene loads")
	if pause_scene == null:
		return
	var pause := pause_scene.instantiate() as PauseMenu
	pause.settings_path = _test_settings_path()
	pause.apply_runtime_settings = false
	root.add_child(pause)
	await process_frame
	pause.configure(root)
	pause.restart_requested.connect(_on_restart_requested)
	pause.exit_requested.connect(_on_exit_requested)
	pause.open_menu()
	_expect(pause.is_open() and pause.mouse_filter == Control.MOUSE_FILTER_STOP, "pause menu opens as an input-blocking modal")
	pause.settings_button.pressed.emit()
	_expect(pause.settings_panel.visible, "settings button expands the first settings group")
	pause.volume_slider.value = 62.0
	pause.ui_scale_slider.value = 1.15
	var persisted := RuntimeSettings.new()
	_expect(persisted.load_from_file(_test_settings_path()) == OK, "pause settings save immediately")
	_expect(is_equal_approx(persisted.main_volume_percent, 62.0) and is_equal_approx(persisted.ui_scale, 1.15), "pause menu persists volume and UI scale")
	pause.restart_button.pressed.emit()
	pause.exit_button.pressed.emit()
	_expect(_restart_requests == 1, "restart button emits one high-level request without reloading inside the UI")
	_expect(_exit_requests == 1, "exit button emits one safe high-level request without quitting inside the UI")
	pause.close_menu()
	_expect(not pause.is_open(), "pause modal closes explicitly")
	pause.queue_free()
	await process_frame


func _test_runtime_hud_integration_and_layout(fixture: Dictionary) -> void:
	var scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	_expect(scene != null, "batch 3 runtime HUD scene loads")
	if scene == null:
		return
	var hud := scene.instantiate() as RuntimeHud
	hud.get_node("PauseMenu").settings_path = _test_settings_path()
	hud.get_node("PauseMenu").apply_runtime_settings = false
	root.add_child(hud)
	await process_frame
	hud.configure(
		fixture["interaction"],
		fixture["time"],
		fixture["resource"],
		fixture["building"],
		fixture["mirror"],
		6
	)
	hud.configure_global_info(fixture["resource"], fixture["wave"], fixture["base"])
	hud.apply_level_configuration(fixture["level"], "memory://runtime-ui-batch3")
	_expect(hud.get_node_or_null("GlobalInfoPanel") != null, "runtime HUD owns the right-top global panel")
	_expect(hud.get_node_or_null("EconomyPanel") != null, "runtime HUD owns the right-bottom economy panel")
	_expect(hud.get_node_or_null("TimeControlPanel") != null, "runtime HUD owns formal time controls")
	_expect(hud.get_node_or_null("PauseMenu") != null, "runtime HUD owns the pause modal")
	var modal_changes: Array[bool] = []
	hud.modal_state_changed.connect(func(open: bool) -> void: modal_changes.append(open))
	fixture["time"].set_paused(true)
	await process_frame
	_expect(hud.is_modal_open(), "GameTimeController pause state opens the modal")
	_expect(not modal_changes.is_empty() and modal_changes.back(), "HUD broadcasts modal input-lock state")
	hud.close_pause_menu()
	await process_frame
	_expect(not hud.is_modal_open() and not fixture["time"].is_paused(), "closing the HUD modal resumes simulation")

	var original_window_size := root.size
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
		var cards_rect := (hud.get_node("BuildCardBar/Layout/Cards") as Control).get_global_rect()
		var global_rect := (hud.get_node("GlobalInfoPanel") as Control).get_global_rect()
		var inspector_rect := (hud.get_node("TileInspectorPanel") as Control).get_global_rect()
		var economy_rect := (hud.get_node("EconomyPanel") as Control).get_global_rect()
		var time_rect := (hud.get_node("TimeControlPanel") as Control).get_global_rect()
		for rect in [global_rect, inspector_rect, economy_rect, time_rect]:
			_expect(viewport_rect.encloses(rect), "batch 3 HUD region stays inside %dx%d" % [resolution.x, resolution.y])
		_expect(not global_rect.intersects(inspector_rect), "global and tile information do not overlap at %dx%d" % [resolution.x, resolution.y])
		_expect(not inspector_rect.intersects(economy_rect), "tile and economy information do not overlap at %dx%d" % [resolution.x, resolution.y])
		_expect(not economy_rect.intersects(time_rect), "economy and time controls do not overlap at %dx%d" % [resolution.x, resolution.y])
		_expect(not cards_rect.intersects(economy_rect) and not cards_rect.intersects(time_rect), "card row leaves the right-bottom cluster clear at %dx%d" % [resolution.x, resolution.y])
	root.size = original_window_size
	hud.queue_free()
	await process_frame


func _test_level_reload(fixture: Dictionary) -> void:
	var loader: LevelLoader = fixture["loader"]
	var first_level := loader.get_current_level()
	var source_path := loader.get_current_source_path()
	var reload_events: Array[Dictionary] = []
	loader.level_loaded.connect(func(level: LevelResource, path: String) -> void: reload_events.append({"level": level, "path": path}))
	_expect(loader.reload_current_level(), "LevelLoader deep-reloads the active level")
	await process_frame
	_expect(loader.get_current_level() != first_level, "in-memory restart uses a fresh deep level copy")
	_expect(loader.get_current_source_path() == source_path, "level restart preserves its source identity")
	_expect(reload_events.size() == 1, "one restart emits exactly one complete level transaction")


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
	var interaction := RuntimeInteractionController.new()
	host.add_child(interaction)
	interaction.configure(building_manager, mirror_manager)
	var time_controller := GameTimeController.new()
	host.add_child(time_controller)
	time_controller.configure(interaction, building_manager, mirror_manager)
	var base_core := BaseCore.new()
	host.add_child(base_core)
	base_core.current_hp = 100.0
	base_core.max_hp = 100.0
	var wave_manager := WaveManager.new()
	host.add_child(wave_manager)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	var level := LevelResource.new()
	level.display_name = "批次 3 测试关卡"
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(4, 3)
	level.base_cell = Vector3i(3, 2, 0)
	level.initial_resource = 500
	level.building_cap = 20
	level.mirror_cap = 6
	level.base_resource_per_second = 0.0
	resource_manager.apply_level_configuration(level)
	_expect(loader.load_level(level, "memory://runtime-ui-batch3"), "batch 3 fixture level loads")
	await process_frame
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
		"mirror": mirror_manager,
		"interaction": interaction,
		"time": time_controller,
		"base": base_core,
		"wave": wave_manager,
		"loader": loader,
		"level": level,
	}


func _test_settings_path() -> String:
	return "user://runtime_ui_batch3_test.cfg"


func _cleanup_settings_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)


func _on_restart_requested() -> void:
	_restart_requests += 1


func _on_exit_requested() -> void:
	_exit_requests += 1


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
