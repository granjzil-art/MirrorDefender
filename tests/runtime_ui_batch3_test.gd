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
	settings.set_values(37.0, true, 1.25, false, RuntimeSettings.RENDER_QUALITY_PERFORMANCE)
	_expect(settings.save_to_file(path) == OK, "runtime settings save to an isolated user cfg")
	var loaded := RuntimeSettings.new()
	_expect(loaded.load_from_file(path) == OK, "runtime settings reload from user cfg")
	_expect(is_equal_approx(loaded.main_volume_percent, 37.0), "saved main volume round-trips")
	_expect(loaded.fullscreen, "saved fullscreen mode round-trips")
	_expect(is_equal_approx(loaded.ui_scale, 1.25), "saved UI scale round-trips")
	_expect(not loaded.depth_of_field_enabled, "saved depth-of-field setting round-trips")
	_expect(loaded.render_quality_preset == RuntimeSettings.RENDER_QUALITY_PERFORMANCE, "saved render quality round-trips")
	loaded.set_values(-10.0, false, 9.0)
	_expect(is_zero_approx(loaded.main_volume_percent) and is_equal_approx(loaded.ui_scale, 1.5), "runtime settings clamp editable ranges")
	var render_window := Window.new()
	render_window.size = Vector2i(3840, 2160)
	var scale_settings := RuntimeSettings.new()
	scale_settings.set_values(100.0, false, 1.0, true, RuntimeSettings.RENDER_QUALITY_BALANCED)
	_expect(
		is_equal_approx(scale_settings.get_effective_3d_scale(render_window), 2.0 / 3.0),
		"balanced render quality maps 4K output to a 1440p 3D buffer"
	)
	scale_settings.set_values(100.0, false, 1.0, true, RuntimeSettings.RENDER_QUALITY_PERFORMANCE)
	_expect(
		is_equal_approx(scale_settings.get_effective_3d_scale(render_window), 0.5),
		"performance render quality maps 4K output to a 1080p 3D buffer"
	)
	scale_settings.set_values(100.0, false, 1.0, true, RuntimeSettings.RENDER_QUALITY_NATIVE)
	_expect(
		is_equal_approx(scale_settings.get_effective_3d_scale(render_window), 1.0),
		"native render quality keeps the full 3D buffer"
	)
	render_window.free()


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
	base_core.current_hp = 75.0
	base_core.max_hp = 120.0
	base_core.health_changed.emit(base_core.current_hp, base_core.max_hp)
	wave_manager.state_changed.emit(WaveManager.State.ACTIVE, 1, 3, 4)
	resource_manager.try_register_building(0.0)
	resource_manager.try_register_mirror(ResourceManager.COPY_MIRROR_KIND)
	resource_manager.try_register_mirror(ResourceManager.REFLECT_MIRROR_KIND)
	var summary := panel.get_summary_text()
	_expect(summary.split("\n")[0] == "75", "heart stat follows the remaining BaseCore health")
	_expect(summary.contains("1/3"), "head stat follows current and total wave counts")
	_expect(summary.contains("1/20"), "tower stat follows the building count and cap")
	_expect(summary.contains("1/5"), "copy-mirror stat follows its independent count and cap")
	_expect(summary.contains("1/10"), "reflect-mirror stat follows its independent count and cap")
	_expect(panel.get_node_or_null("GlassPanel") == null, "icon stats render without the legacy information frame")
	for icon_path in [
		"StatsGrid/HealthStat/Icon",
		"StatsGrid/WaveStat/Icon",
		"StatsGrid/CopyMirrorStat/Icon",
		"StatsGrid/ReflectMirrorStat/Icon",
		"StatsGrid/EconomyPanel/Content/ResourceIcon",
		"StatsGrid/BuildingStat/Icon",
	]:
		var icon := panel.get_node(icon_path) as TextureRect
		_expect(icon != null and icon.texture != null, "global icon stat owns its supplied texture")
	resource_manager.unregister_building()
	resource_manager.unregister_mirror(ResourceManager.COPY_MIRROR_KIND)
	resource_manager.unregister_mirror(ResourceManager.REFLECT_MIRROR_KIND)
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
	time_controller.reset_runtime_state()
	controls.configure(time_controller)
	var slow_style := controls.tactical_slow_button.get_theme_stylebox("normal") as StyleBoxFlat
	var pause_style := controls.pause_button.get_theme_stylebox("normal") as StyleBoxFlat
	var speed_style := controls.fast_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		controls.fast_button.text == "1x"
		and speed_style != null and speed_style.bg_color.is_equal_approx(controls.speed_1x_color),
		"speed control starts at green 1x"
	)
	_expect(
		slow_style != null and slow_style.bg_color.is_equal_approx(controls.tactical_slow_color)
		and pause_style != null and pause_style.bg_color.is_equal_approx(controls.pause_color),
		"slow and pause controls use the authored light purple and light gray"
	)
	controls.fast_button.pressed.emit()
	speed_style = controls.fast_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		controls.fast_button.text == "2x"
		and is_equal_approx(time_controller.get_playback_scale(), 2.0)
		and is_equal_approx(time_controller.get_effective_scale(), 2.0)
		and speed_style != null and speed_style.bg_color.is_equal_approx(controls.speed_2x_color),
		"speed control advances to orange 2x"
	)
	controls.fast_button.pressed.emit()
	speed_style = controls.fast_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		controls.fast_button.text == "4x"
		and is_equal_approx(time_controller.get_playback_scale(), 4.0)
		and is_equal_approx(time_controller.get_effective_scale(), 4.0)
		and speed_style != null and speed_style.bg_color.is_equal_approx(controls.speed_4x_color),
		"speed control advances to red 4x"
	)
	controls.pause_button.pressed.emit()
	_expect(time_controller.is_paused() and is_zero_approx(time_controller.get_effective_scale()), "formal pause button has highest priority")
	_expect(controls.pause_button.text == "继续", "pause button exposes its resume action")
	controls.pause_button.pressed.emit()
	_expect(not time_controller.is_paused() and is_equal_approx(time_controller.get_effective_scale(), 4.0), "resume restores remembered 4x time")
	controls.fast_button.pressed.emit()
	speed_style = controls.fast_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		controls.fast_button.text == "1x"
		and is_equal_approx(time_controller.get_effective_scale(), 1.0)
		and speed_style != null and speed_style.bg_color.is_equal_approx(controls.speed_1x_color),
		"speed control cycles from 4x back to green 1x"
	)
	time_controller.set_playback_scale(4.0)
	time_controller.set_paused(true)
	time_controller.reset_runtime_state()
	_expect(
		not time_controller.is_paused()
		and not time_controller.is_fast_enabled()
		and is_equal_approx(time_controller.get_playback_scale(), 1.0),
		"runtime reset clears pause and restores the 1x player speed"
	)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0) and is_equal_approx(Engine.time_scale, 1.0), "runtime reset restores normal engine time")
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
	pause.exit_level_requested.connect(_on_exit_requested)
	pause.open_menu()
	_expect(pause.is_open() and pause.mouse_filter == Control.MOUSE_FILTER_STOP, "pause menu opens as an input-blocking modal")
	pause.settings_button.pressed.emit()
	_expect(pause.settings_panel.visible, "settings button expands the first settings group")
	pause.volume_slider.value = 62.0
	pause.ui_scale_slider.value = 1.15
	pause.render_quality.select(RuntimeSettings.RENDER_QUALITY_NATIVE)
	pause.render_quality.item_selected.emit(RuntimeSettings.RENDER_QUALITY_NATIVE)
	pause.depth_of_field_toggle.set_pressed_no_signal(false)
	pause.depth_of_field_toggle.toggled.emit(false)
	var persisted := RuntimeSettings.new()
	_expect(persisted.load_from_file(_test_settings_path()) == OK, "pause settings save immediately")
	_expect(is_equal_approx(persisted.main_volume_percent, 62.0) and is_equal_approx(persisted.ui_scale, 1.15), "pause menu persists volume and UI scale")
	_expect(not persisted.depth_of_field_enabled, "pause menu persists the depth-of-field toggle")
	_expect(persisted.render_quality_preset == RuntimeSettings.RENDER_QUALITY_NATIVE, "pause menu persists render quality")
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
	hud.configure_wave_controls(fixture["wave"])
	hud.apply_level_configuration(fixture["level"], "memory://runtime-ui-batch3")
	_expect(hud.get_node_or_null("GlobalInfoPanel") != null, "runtime HUD owns the right-top icon stats")
	_expect(hud.get_node_or_null("GlobalInfoPanel/StatsGrid/EconomyPanel") != null, "right-top stats own the animated economy cell")
	_expect(hud.get_node_or_null("TimeControlPanel") != null, "runtime HUD owns formal time controls")
	_expect(hud.get_node_or_null("PauseMenu") != null, "runtime HUD owns the pause modal")
	_expect(hud.get_node_or_null("DefeatMenu") != null, "runtime HUD owns the defeat modal")
	_expect(hud.get_node_or_null("VictoryMenu") != null, "runtime HUD owns the victory modal")
	_expect(hud.get_node_or_null("ConfirmationDialog") != null, "runtime HUD owns the centered destructive-action confirmation")
	_expect(
		hud.get_victory_star_count(0.0) == 0
		and hud.get_victory_star_count(5.0) == 1
		and hud.get_victory_star_count(5.1) == 2
		and hud.get_victory_star_count(15.0) == 2
		and hud.get_victory_star_count(15.1) == 3,
		"victory rating uses non-overlapping 0/5/15 remaining-health boundaries"
	)
	var modal_changes: Array[bool] = []
	hud.modal_state_changed.connect(func(open: bool) -> void: modal_changes.append(open))
	fixture["time"].set_paused(true)
	await process_frame
	_expect(hud.is_modal_open(), "GameTimeController pause state opens the modal")
	_expect(not modal_changes.is_empty() and modal_changes.back(), "HUD broadcasts modal input-lock state")
	var pause_modal := hud.get_node("PauseMenu") as Control
	var time_controls := hud.get_node("TimeControlPanel") as Control
	var debug_overlay := hud.get_node("DebugOverlayPanel") as Control
	_expect(pause_modal.z_index > time_controls.z_index, "pause modal renders above time controls")
	_expect(pause_modal.z_index > debug_overlay.z_index, "pause modal renders above the debug overlay")
	hud.close_pause_menu()
	await process_frame
	_expect(not hud.is_modal_open() and not fixture["time"].is_paused(), "closing the HUD modal resumes simulation")
	var running_restart_requests: Array[bool] = []
	var running_exit_requests: Array[bool] = []
	hud.restart_level_requested.connect(func() -> void: running_restart_requests.append(true))
	hud.exit_level_requested.connect(func() -> void: running_exit_requests.append(true))
	fixture["time"].set_playback_scale(4.0)
	hud.wave_control_panel.restart_button.pressed.emit()
	await process_frame
	_expect(
		hud.is_confirmation_open()
		and hud.confirmation_message.text == "将重启关卡，确认吗"
		and fixture["time"].is_paused()
		and is_zero_approx(Engine.time_scale),
		"right-side restart opens the centered confirmation and pauses gameplay"
	)
	_expect(not pause_modal.visible and running_restart_requests.is_empty(), "restart confirmation does not open the pause menu or emit early")
	hud.confirmation_cancel_button.pressed.emit()
	await process_frame
	_expect(
		not hud.is_confirmation_open()
		and not fixture["time"].is_paused()
		and is_equal_approx(fixture["time"].get_effective_scale(), 4.0),
		"cancelling a running-game confirmation restores the remembered playback speed"
	)
	hud.wave_control_panel.exit_button.pressed.emit()
	await process_frame
	_expect(
		hud.is_confirmation_open()
		and hud.confirmation_message.text == "将返回标题，确认吗"
		and running_exit_requests.is_empty(),
		"right-side exit uses the return-title confirmation copy without emitting early"
	)
	hud.confirmation_cancel_button.pressed.emit()
	await process_frame

	var defeat_restart_requests: Array[bool] = []
	var defeat_exit_requests: Array[bool] = []
	hud.restart_level_requested.connect(func() -> void: defeat_restart_requests.append(true))
	hud.exit_level_requested.connect(func() -> void: defeat_exit_requests.append(true))
	var wave_manager: WaveManager = fixture["wave"]
	wave_manager.defeat.emit()
	await process_frame
	_expect(hud.is_defeat_menu_open() and hud.is_modal_open(), "defeat opens the input-blocking result modal")
	_expect(fixture["time"].is_paused() and is_zero_approx(Engine.time_scale), "defeat freezes gameplay time")
	hud.close_top_modal()
	_expect(hud.is_defeat_menu_open(), "generic modal cancellation cannot dismiss the defeat result")
	var defeat_menu := hud.get_node("DefeatMenu") as PauseMenu
	var pause_menu := hud.get_node("PauseMenu") as PauseMenu
	defeat_menu.depth_of_field_toggle.set_pressed_no_signal(true)
	defeat_menu.depth_of_field_toggle.toggled.emit(true)
	_expect(pause_menu.depth_of_field_toggle.button_pressed, "defeat and pause menus share the same settings state")
	defeat_menu.restart_button.pressed.emit()
	_expect(hud.is_confirmation_open() and hud.confirmation_message.text == "将重启关卡，确认吗", "defeat restart is routed through the shared confirmation")
	_expect(defeat_restart_requests.is_empty(), "defeat restart does not emit before confirmation")
	hud.confirmation_confirm_button.pressed.emit()
	_expect(defeat_restart_requests.size() == 1, "defeat restart reuses the high-level level reload request")
	hud.prepare_for_level_transition()
	_expect(not hud.is_defeat_menu_open() and not fixture["time"].is_paused(), "level transition closes defeat and restores gameplay time")
	wave_manager.defeat.emit()
	defeat_menu.exit_button.pressed.emit()
	_expect(hud.is_confirmation_open(), "defeat return opens confirmation above the result modal")
	hud.confirmation_cancel_button.pressed.emit()
	_expect(hud.is_defeat_menu_open() and fixture["time"].is_paused(), "cancelling from a result modal preserves its paused state")
	_expect(defeat_exit_requests.is_empty(), "cancelled defeat return emits no exit request")
	defeat_menu.exit_button.pressed.emit()
	hud.confirmation_confirm_button.pressed.emit()
	_expect(defeat_exit_requests.size() == 1, "defeat exit reuses the return-to-level-selection request")
	hud.prepare_for_level_transition()

	var base_core: BaseCore = fixture["base"]
	var victory_menu := hud.get_node("VictoryMenu") as PauseMenu
	base_core.current_hp = 5.0
	wave_manager.victory.emit()
	await process_frame
	_expect(hud.is_victory_menu_open() and hud.is_modal_open(), "victory opens the input-blocking result modal")
	_expect(hud.get_displayed_victory_star_count() == 1 and victory_menu.result_label.text.contains("★☆☆"), "five remaining health displays one star")
	_expect(not victory_menu.settings_button.visible, "victory result hides settings and keeps only two choices")
	var visible_victory_choices := 0
	for child in victory_menu.settings_button.get_parent().get_children():
		if child is Button and (child as Button).visible:
			visible_victory_choices += 1
	_expect(visible_victory_choices == 2, "victory result exposes exactly restart and return-title buttons")
	hud.close_top_modal()
	_expect(hud.is_victory_menu_open(), "generic modal cancellation cannot dismiss the victory result")
	hud.prepare_for_level_transition()
	base_core.current_hp = 15.0
	wave_manager.victory.emit()
	_expect(hud.get_displayed_victory_star_count() == 2 and victory_menu.result_label.text.contains("★★☆"), "fifteen remaining health displays two stars")
	hud.prepare_for_level_transition()
	base_core.current_hp = 16.0
	wave_manager.victory.emit()
	_expect(hud.get_displayed_victory_star_count() == 3 and victory_menu.result_label.text.contains("★★★"), "more than fifteen remaining health displays three stars")
	var victory_restart_requests: Array[bool] = []
	hud.restart_level_requested.connect(func() -> void: victory_restart_requests.append(true))
	victory_menu.restart_button.pressed.emit()
	_expect(victory_restart_requests.is_empty() and hud.is_confirmation_open(), "victory restart waits for confirmation")
	hud.confirmation_confirm_button.pressed.emit()
	_expect(victory_restart_requests.size() == 1, "victory restart reuses the current-level reload request")
	hud.prepare_for_level_transition()
	base_core.current_hp = 15.0
	wave_manager.victory.emit()
	var victory_exit_requests: Array[bool] = []
	hud.exit_level_requested.connect(func() -> void: victory_exit_requests.append(true))
	victory_menu.exit_button.pressed.emit()
	_expect(victory_exit_requests.is_empty() and hud.is_confirmation_open(), "victory return-title waits for confirmation")
	hud.confirmation_confirm_button.pressed.emit()
	_expect(victory_exit_requests.size() == 1, "victory return-title reuses the safe level-exit request")
	hud.prepare_for_level_transition()

	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.position = Vector2.ZERO
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		hud.size = Vector2(resolution)
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
		var cards_rect := (hud.get_node("BuildCardBar/Layout/Cards") as Control).get_global_rect()
		var global_rect := (hud.get_node("GlobalInfoPanel") as Control).get_global_rect()
		var economy_rect := (hud.get_node("GlobalInfoPanel/StatsGrid/EconomyPanel") as Control).get_global_rect()
		var time_rect := (hud.get_node("TimeControlPanel") as Control).get_global_rect()
		var wave_controls_rect := (hud.get_node("WaveControlPanel") as Control).get_global_rect()
		for rect in [global_rect, economy_rect, time_rect, wave_controls_rect]:
			_expect(viewport_rect.encloses(rect), "batch 3 HUD region stays inside %dx%d" % [resolution.x, resolution.y])
		var wave_right_margin := viewport_rect.end.x - wave_controls_rect.end.x
		_expect(wave_right_margin >= 14.0 and wave_right_margin <= 18.1, "wave buttons keep a 14-18px right safety margin at %dx%d" % [resolution.x, resolution.y])
		_expect(not economy_rect.intersects(time_rect), "economy and time controls do not overlap at %dx%d" % [resolution.x, resolution.y])
		_expect(not wave_controls_rect.intersects(global_rect), "right-edge wave buttons leave global information clear at %dx%d" % [resolution.x, resolution.y])
		_expect(not cards_rect.intersects(global_rect), "cards leave global information clear at %dx%d" % [resolution.x, resolution.y])
	hud.queue_free()
	await process_frame
	return


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
	building_manager.pulse_laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.PULSE_LASER_TOWER)
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
	level.copy_mirror_cap = 5
	level.reflect_mirror_cap = 10
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
