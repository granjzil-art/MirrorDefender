extends SceneTree

const AppRootScene := preload("res://scenes/AppRoot.tscn")
const MainScene := preload("res://scenes/Main.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[ManualWaveAndLevelFlow] running")
	await _test_app_flow()
	await _test_configuration_failure_fallback()
	await _test_direct_main_compatibility()
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[ManualWaveAndLevelFlow] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[ManualWaveAndLevelFlow] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_app_flow() -> void:
	var app := AppRootScene.instantiate() as AppFlowController
	root.add_child(app)
	await process_frame
	await process_frame
	_expect(app.get_active_level_select() is LevelSelectView, "AppRoot starts on level selection")
	_expect(app.get_active_main() == null and app.get_active_content_count() == 1, "startup owns only one level-selection child")
	var view := app.get_active_level_select() as LevelSelectView
	var selected_level := view.get_slot_level(0)
	_expect(selected_level != null, "default selection exposes a playable LevelResource")
	view.activate_face_for_test(0)
	await process_frame
	await process_frame
	var main := app.get_active_main() as MainController
	_expect(main != null and app.get_active_content_count() == 1, "selection creates exactly one Main child")
	if main == null:
		app.queue_free()
		await process_frame
		return
	_expect(main.level_loader.get_current_level() == selected_level, "Main first load uses the selected LevelResource")
	_expect(main.runtime_hud.get_node_or_null("WaveTimelinePanel") == null, "formal HUD no longer instantiates the legacy timeline")
	var wave_controls := main.runtime_hud.wave_control_panel as WaveControlPanel
	_expect(wave_controls != null and wave_controls.button_column.get_child_count() == 3, "formal HUD owns the three wave-control buttons")
	var restart_requests: Array[bool] = []
	main.runtime_hud.restart_level_requested.connect(func() -> void: restart_requests.append(true))
	wave_controls.restart_button.pressed.emit()
	_expect(restart_requests.size() == 1, "round button emits one high-level restart request")
	var return_requests: Array[bool] = []
	main.return_to_level_select_requested.connect(func() -> void: return_requests.append(true))
	main.runtime_hud.pause_menu.open_menu()
	main.runtime_hud.pause_menu.exit_button.pressed.emit()
	_expect(return_requests.size() == 1, "pause exit requests return to selection without quitting SceneTree")
	await process_frame
	await process_frame
	_expect(app.get_active_main() == null and app.get_active_level_select() is LevelSelectView, "return removes Main and restores level selection")
	_expect(app.get_active_content_count() == 1, "return leaves only one level-selection child")
	_expect(is_equal_approx(Engine.time_scale, 1.0), "return restores Engine.time_scale to one")
	app.queue_free()
	await process_frame


func _test_configuration_failure_fallback() -> void:
	var app := AppRootScene.instantiate() as AppFlowController
	app.main_scene = null
	root.add_child(app)
	await process_frame
	var view := app.get_active_level_select() as LevelSelectView
	view.activate_face_for_test(0)
	await process_frame
	_expect(app.get_active_main() == null and app.get_active_level_select() == view, "missing Main configuration safely keeps level selection")
	app.queue_free()
	await process_frame

	var fallback_app := AppRootScene.instantiate() as AppFlowController
	fallback_app.level_select_scene = null
	root.add_child(fallback_app)
	await process_frame
	_expect(fallback_app.get_active_level_select() != null and fallback_app.get_active_content_count() == 1, "missing selection scene shows a safe fallback instead of crashing")
	fallback_app.queue_free()
	await process_frame

	var invalid_level := LevelResource.new()
	invalid_level.grid_shape = 99
	var invalid_page := LevelSelectPageDefinition.new()
	invalid_page.levels.assign([invalid_level])
	var invalid_catalog := LevelSelectCatalog.new()
	invalid_catalog.pages.assign([invalid_page])
	var invalid_catalog_app := AppRootScene.instantiate() as AppFlowController
	invalid_catalog_app.level_select_catalog = invalid_catalog
	root.add_child(invalid_catalog_app)
	await process_frame
	_expect(not invalid_catalog_app.get_active_level_select() is LevelSelectView, "invalid catalog content opens a safe non-clickable fallback")
	_expect(invalid_catalog_app.get_active_main() == null and invalid_catalog_app.get_active_content_count() == 1, "invalid catalog never creates a battle scene")
	invalid_catalog_app.queue_free()
	await process_frame


func _test_direct_main_compatibility() -> void:
	var main := MainScene.instantiate() as MainController
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.level_loader.get_current_level() != null, "direct Main scene keeps LevelLoader.initial_level compatibility")
	_expect(main.runtime_interaction.select_copy_mirror_card(), "direct Main can enter placement mode before cancellation input")
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	main._input(right_press)
	_expect(not main.runtime_interaction.is_select_mode(), "non-modal right press no longer cancels before drag classification")
	main.cam_rig.cancel_requested.emit()
	_expect(main.runtime_interaction.is_select_mode(), "camera short-click release signal performs Main cancellation")
	var first_wave_result: Dictionary = main.runtime_debug_bindings.command_registry.execute("wave start")
	var second_wave_result: Dictionary = main.runtime_debug_bindings.command_registry.execute("wave start")
	_expect(bool(first_wave_result.get("success", false)) and bool(second_wave_result.get("success", false)), "debug wave start releases the next wave on every command")
	_expect(main.wave_manager.get_released_wave_count() == 2, "two debug wave commands release exactly two authored waves")
	var return_requests: Array[bool] = []
	main.return_to_level_select_requested.connect(func() -> void: return_requests.append(true))
	main.runtime_hud.wave_control_panel.exit_button.pressed.emit()
	_expect(return_requests.size() == 1, "right-side cross emits a return request without quitting SceneTree")
	main.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
