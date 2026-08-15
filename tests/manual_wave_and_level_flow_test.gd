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
	_expect(app.serialize_heavy_world_transitions, "heavy world transitions are serialized by default")
	_expect(app.gpu_release_barrier_frames == 2, "GPU release barrier keeps two empty render frames")
	_expect(app.force_gpu_sync_after_release, "GPU release barrier synchronizes the render thread before loading")
	_expect(app.get_active_level_select() is LevelSelectView, "AppRoot starts on level selection")
	_expect(app.get_active_main() == null and app.get_active_content_count() == 1, "startup owns only one level-selection child")
	var view := app.get_active_level_select() as LevelSelectView
	var selected_level := view.get_slot_level(0)
	var unselected_level_refs := _collect_unselected_level_refs(view, 0)
	var barrier_starts: Array[StringName] = []
	var barrier_completions: Array[StringName] = []
	app.transition_release_barrier_started.connect(
		func(direction: StringName) -> void: barrier_starts.append(direction)
	)
	app.transition_release_barrier_completed.connect(
		func(direction: StringName) -> void: barrier_completions.append(direction)
	)
	_expect(selected_level != null, "default selection exposes a playable LevelResource")
	view.activate_face_for_test(0)
	_expect(view.get_loaded_level_count() == 0, "selection releases all portal level graphs before Main starts loading")
	await _wait_until(func() -> bool: return app.is_release_barrier_active())
	_expect(
		app.get_release_barrier_direction() == AppFlowController.TRANSITION_TO_BATTLE,
		"battle startup enters the GPU release barrier"
	)
	_expect(
		app.get_active_level_select() == null
		and app.get_active_main() == null
		and app.get_active_content_count() == 0,
		"battle startup has one fully empty content interval before Main is instantiated"
	)
	await _wait_until(func() -> bool: return app.get_active_main() != null)
	var main := app.get_active_main() as MainController
	_expect(main != null and app.get_active_content_count() == 1, "selection creates exactly one Main child")
	_expect(
		barrier_starts.count(AppFlowController.TRANSITION_TO_BATTLE) == 1
		and barrier_completions.count(AppFlowController.TRANSITION_TO_BATTLE) == 1,
		"battle startup completes exactly one release barrier before loading"
	)
	_expect(_all_weak_refs_released(unselected_level_refs), "battle startup retains none of the three unselected LevelResource objects")
	if main == null:
		app.queue_free()
		await process_frame
		return
	_expect(main.level_loader.get_current_level() == selected_level, "Main first load uses the selected LevelResource")
	_expect(main.runtime_hud.get_node_or_null("WaveTimelinePanel") == null, "formal HUD no longer instantiates the legacy timeline")
	var wave_controls := main.runtime_hud.wave_control_panel as WaveControlPanel
	_expect(wave_controls != null and wave_controls.button_column.get_child_count() == 3, "formal HUD owns the three wave-control buttons")
	main.game_time_controller.set_playback_scale(4.0)
	_expect(
		main.runtime_interaction.select_building_card(main.building_manager.arrow_tower)
		and is_equal_approx(main.game_time_controller.get_effective_scale(), 0.1),
		"selecting a card creates tactical slow before a manual wave release"
	)
	wave_controls.start_button.pressed.emit()
	await process_frame
	_expect(
		main.runtime_interaction.is_select_mode()
		and main.building_manager.get_selected_building() == null
		and main.mirror_manager.get_selected_mirror() == null,
		"clicking release next wave clears the current card and world selection"
	)
	_expect(
		is_equal_approx(main.game_time_controller.get_effective_scale(), 4.0),
		"manual wave release exits tactical slow and restores the remembered playback speed"
	)
	var restart_requests: Array[bool] = []
	main.runtime_hud.restart_level_requested.connect(func() -> void: restart_requests.append(true))
	wave_controls.restart_button.pressed.emit()
	_expect(main.runtime_hud.is_confirmation_open() and restart_requests.is_empty(), "round restart waits for the centered confirmation")
	main.runtime_hud.confirmation_confirm_button.pressed.emit()
	await process_frame
	_expect(restart_requests.size() == 1, "round button emits one high-level restart request")
	var level_source_before_victory_restart := main.level_loader.get_current_source_path()
	main.base_core.current_hp = 15.0
	main.wave_manager.victory.emit()
	await process_frame
	_expect(
		main.runtime_hud.is_victory_menu_open()
		and main.runtime_hud.get_displayed_victory_star_count() == 2,
		"victory opens the formal result with the remaining-health rating"
	)
	main.runtime_hud.victory_menu.restart_button.pressed.emit()
	_expect(main.runtime_hud.is_confirmation_open(), "victory restart opens the confirmation layer")
	main.runtime_hud.confirmation_confirm_button.pressed.emit()
	await process_frame
	_expect(
		main.level_loader.get_current_source_path() == level_source_before_victory_restart
		and main.base_core.current_hp > 0.0
		and not main.runtime_hud.is_victory_menu_open(),
		"victory restart reloads the same level and closes the result"
	)
	var level_source_before_defeat_restart := main.level_loader.get_current_source_path()
	main.base_core.take_damage(main.base_core.current_hp)
	await process_frame
	_expect(main.runtime_hud.is_defeat_menu_open(), "base defeat opens the formal failure result")
	main.runtime_hud.defeat_menu.restart_button.pressed.emit()
	_expect(main.runtime_hud.is_confirmation_open(), "failure restart opens the confirmation layer")
	main.runtime_hud.confirmation_confirm_button.pressed.emit()
	await process_frame
	_expect(
		main.level_loader.get_current_source_path() == level_source_before_defeat_restart
		and main.base_core.current_hp > 0.0
		and main.wave_manager.get_state() != WaveManager.State.DEFEAT,
		"failure restart reloads and resets the active level"
	)
	_expect(not main.runtime_hud.is_defeat_menu_open() and is_equal_approx(Engine.time_scale, 1.0), "failure restart closes the result and restores normal time")
	var return_requests: Array[bool] = []
	main.return_to_level_select_requested.connect(func() -> void: return_requests.append(true))
	main.base_core.current_hp = 16.0
	main.wave_manager.victory.emit()
	await process_frame
	main.runtime_hud.victory_menu.exit_button.pressed.emit()
	_expect(main.runtime_hud.is_confirmation_open() and return_requests.is_empty(), "victory return-title waits for confirmation")
	main.runtime_hud.confirmation_confirm_button.pressed.emit()
	_expect(return_requests.size() == 1, "victory return-title requests the selection screen without quitting SceneTree")
	await _wait_until(func() -> bool: return app.is_release_barrier_active())
	_expect(
		app.get_release_barrier_direction() == AppFlowController.TRANSITION_TO_LEVEL_SELECT,
		"return enters the GPU release barrier"
	)
	_expect(
		app.get_active_main() == null
		and app.get_active_level_select() == null
		and app.get_active_content_count() == 0,
		"return has one fully empty content interval before previews are instantiated"
	)
	await _wait_until(func() -> bool: return app.get_active_level_select() != null)
	_expect(app.get_active_main() == null and app.get_active_level_select() is LevelSelectView, "return removes Main and restores level selection")
	_expect(app.get_active_content_count() == 1, "return leaves only one level-selection child")
	_expect(
		barrier_starts.count(AppFlowController.TRANSITION_TO_LEVEL_SELECT) == 1
		and barrier_completions.count(AppFlowController.TRANSITION_TO_LEVEL_SELECT) == 1,
		"return completes exactly one release barrier before preview loading"
	)
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
	_expect(main.runtime_hud.is_confirmation_open() and return_requests.is_empty(), "right-side cross waits for confirmation")
	main.runtime_hud.confirmation_confirm_button.pressed.emit()
	_expect(return_requests.size() == 1, "right-side cross emits a return request without quitting SceneTree")
	main.queue_free()
	await process_frame


func _collect_unselected_level_refs(view: LevelSelectView, selected_slot: int) -> Array[WeakRef]:
	var result: Array[WeakRef] = []
	for slot_index in range(view.get_slot_count()):
		if slot_index == selected_slot:
			continue
		var level := view.get_slot_level(slot_index)
		if level != null:
			result.append(weakref(level))
	return result


func _all_weak_refs_released(refs: Array[WeakRef]) -> bool:
	for reference in refs:
		if reference.get_ref() != null:
			return false
	return true


func _wait_until(predicate: Callable, maximum_frames: int = 20) -> bool:
	for _frame_index in range(maximum_frames):
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
