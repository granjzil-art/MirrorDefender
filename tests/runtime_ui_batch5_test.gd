extends SceneTree

const CameraPresetDefinitionScript := preload("res://scripts/camera/CameraPresetDefinition.gd")
const CameraPresetControllerScript := preload("res://scripts/camera/CameraPresetController.gd")
const CameraPresetEditorScript := preload("res://addons/mirror_tile_editor/camera_preset_editor.gd")
const TileEditorCanvasScript := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")
const TileEditorPanelScript := preload("res://addons/mirror_tile_editor/tile_editor_panel.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUIBatch5] running")
	_test_input_map_and_level_data()
	await _test_runtime_transition()
	await _test_editor_component()
	await _test_editor_panel_integration()
	if _failures == 0:
		print("[RuntimeUIBatch5] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeUIBatch5] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_input_map_and_level_data() -> void:
	for slot_number in range(1, 7):
		_expect(
			InputMap.has_action("camera_preset_%d" % slot_number),
			"InputMap exposes camera preset action %d" % slot_number
		)
	var old_level := LevelResource.new()
	_expect(old_level.camera_presets.is_empty(), "old levels keep the empty-array compatibility representation")
	_expect(old_level.get_camera_preset(0) == null, "an unconfigured compatibility slot resolves to null")
	var preset := CameraPresetDefinitionScript.new()
	preset.focus_position = Vector3(3.0, 1.0, -4.0)
	preset.yaw_degrees = -75.0
	preset.pitch_degrees = 58.0
	preset.zoom_distance = 12.0
	_expect(old_level.set_camera_preset(2, preset), "a valid zero-based slot accepts a preset")
	_expect(old_level.camera_presets.size() == 3, "writing slot 3 only grows storage through that optional slot")
	_expect(old_level.get_camera_preset(2) == preset, "the authored slot preserves its resource reference")
	_expect(old_level.get_configured_camera_preset_count() == 1, "configured preset count ignores empty leading slots")
	_expect(not old_level.set_camera_preset(6, preset), "the seventh slot is rejected")
	var save_path := "user://runtime_ui_batch5_camera_level.tres"
	_expect(ResourceSaver.save(old_level, save_path) == OK, "camera slots serialize inside LevelResource")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelResource
	var loaded_preset := loaded.get_camera_preset(2) if loaded != null else null
	_expect(
		loaded_preset != null and loaded_preset.focus_position.is_equal_approx(preset.focus_position),
		"serialized camera slot loads with its authored view"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var invalid := CameraPresetDefinitionScript.new()
	invalid.zoom_distance = -1.0
	old_level.set_camera_preset(4, invalid)
	var errors := old_level.validate_runtime()
	_expect(_contains_text(errors, "镜头预设 5"), "runtime validation reports the exact invalid camera slot")
	old_level.camera_presets.resize(7)
	errors = old_level.validate_runtime()
	_expect(_contains_text(errors, "不能超过 6"), "runtime validation rejects serialized camera overflow")


func _test_runtime_transition() -> void:
	var rig := CameraController.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	var controller := CameraPresetControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller.configure(rig)
	var level := LevelResource.new()
	var preset := CameraPresetDefinitionScript.new()
	preset.focus_position = Vector3(10.0, 2.0, -6.0)
	preset.yaw_degrees = -170.0
	preset.pitch_degrees = 70.0
	preset.zoom_distance = 24.0
	level.set_camera_preset(0, preset)
	controller.load_level(level)
	controller.transition_duration = 1.0
	rig.apply_view_state(Vector3.ZERO, 170.0, 40.0, 8.0)
	_expect(not controller.request_preset(1), "an unconfigured runtime slot performs no action")
	_expect(controller.request_preset(0), "a configured runtime slot starts a transition")
	_expect(controller.is_transition_active() and rig.is_preset_transition_active(), "transition temporarily suppresses manual camera input")
	controller.advance_transition(0.5)
	var middle_state := rig.get_view_state()
	var middle_focus: Vector3 = middle_state["focus_position"]
	var middle_yaw: float = float(middle_state["yaw_degrees"])
	_expect(middle_focus.is_equal_approx(Vector3(5.0, 1.0, -3.0)), "focus position interpolates at the smoothstep midpoint")
	_expect(absf(absf(middle_yaw) - 180.0) < 0.01, "yaw follows the shortest angular path across 180 degrees")
	controller.advance_transition(0.5)
	var completed_state := rig.get_view_state()
	var completed_focus: Vector3 = completed_state["focus_position"]
	_expect(completed_focus.is_equal_approx(preset.focus_position), "completed transition reaches the authored focus")
	_expect(is_equal_approx(rig.get_pitch_angle(), 70.0) and is_equal_approx(rig.get_zoom_distance(), 24.0), "completed transition reaches authored pitch and zoom")
	_expect(not controller.is_transition_active() and not rig.is_preset_transition_active(), "manual camera input is restored after completion")
	controller.transition_duration = 0.0
	var instant := CameraPresetDefinitionScript.new()
	instant.focus_position = Vector3(-2.0, 0.0, 7.0)
	instant.yaw_degrees = 25.0
	instant.pitch_degrees = 200.0
	instant.zoom_distance = 200.0
	# Invalid preset values must be rejected before CameraController clamping.
	level.set_camera_preset(2, instant)
	_expect(not controller.request_preset(2), "invalid authored preset never starts a runtime transition")
	instant.pitch_degrees = 82.0
	instant.zoom_distance = 30.0
	_expect(controller.request_preset(2), "zero-duration configuration applies immediately")
	var instant_state := rig.get_view_state()
	var instant_focus: Vector3 = instant_state["focus_position"]
	_expect(instant_focus.is_equal_approx(instant.focus_position), "instant transition applies the target focus")
	controller.transition_duration = 1.0
	_expect(controller.request_preset(0), "transition can start again before a level reload")
	rig.set_input_enabled(false)
	var paused_focus: Vector3 = rig.global_position
	controller._process(0.5)
	_expect(rig.global_position.is_equal_approx(paused_focus), "modal camera lock freezes an in-flight preset transition")
	rig.set_input_enabled(true)
	controller.load_level(LevelResource.new())
	_expect(not controller.is_transition_active() and not rig.is_preset_transition_active(), "loading a level cancels stale transition state")
	controller.queue_free()
	rig.queue_free()
	await process_frame


func _test_editor_component() -> void:
	var level := LevelResource.new()
	var canvas := TileEditorCanvasScript.new()
	canvas.size = Vector2(960.0, 600.0)
	root.add_child(canvas)
	canvas.set_level(level)
	await process_frame
	canvas.apply_camera_view_state(Vector3(4.0, 1.5, -3.0), -42.0, 61.0, 12.0)
	var editor := CameraPresetEditorScript.new()
	root.add_child(editor)
	editor.configure(level, canvas)
	_expect(editor.capture_slot(3), "camera editor captures the current view into slot 4")
	var stored := level.get_camera_preset(3)
	_expect(stored != null and stored.focus_position.is_equal_approx(Vector3(4.0, 1.5, -3.0)), "capture stores the editor focus in world space")
	_expect(
		stored != null and is_equal_approx(stored.yaw_degrees, -42.0) and is_equal_approx(stored.pitch_degrees, 61.0),
		"capture stores editor yaw and pitch in runtime degrees"
	)
	_expect(stored != null and is_equal_approx(stored.zoom_distance, 12.0), "editor pixel scale round-trips to runtime zoom distance")
	_expect("已配置" in editor.get_slot_status(3), "slot UI exposes configured state")
	canvas.apply_camera_view_state(Vector3.ZERO, 0.0, 50.0, 8.0)
	_expect(editor.preview_slot(3), "preview jumps the dedicated camera canvas to the stored slot")
	var preview_state: Dictionary = canvas.get_camera_view_state()
	var preview_focus: Vector3 = preview_state["focus_position"]
	_expect(preview_focus.is_equal_approx(stored.focus_position), "preview restores the stored focus")
	_expect(editor.clear_slot(3), "camera editor clears a configured slot")
	_expect(level.get_camera_preset(3) == null and "未配置" in editor.get_slot_status(3), "cleared slot returns to unconfigured state")
	var compatibility_level := LevelResource.new()
	editor.configure(compatibility_level, canvas)
	_expect(compatibility_level.camera_presets.is_empty(), "opening an old level in the camera editor performs no migration write")
	editor.queue_free()
	canvas.queue_free()
	await process_frame


func _test_editor_panel_integration() -> void:
	var editor_main_host := VBoxContainer.new()
	editor_main_host.size = Vector2(1600.0, 900.0)
	root.add_child(editor_main_host)
	var panel := TileEditorPanelScript.new()
	editor_main_host.add_child(panel)
	await process_frame
	await process_frame
	var camera_canvas: Control = panel.get("_camera_canvas")
	var camera_editor: Control = panel.get("_camera_preset_editor")
	var tabs: TabContainer
	for child in panel.find_children("*", "TabContainer", true, false):
		tabs = child as TabContainer
		break
	_expect(
		panel.size_flags_vertical == Control.SIZE_EXPAND_FILL and panel.size.y > 800.0,
		"editor main-screen panel expands inside Godot's VBoxContainer host"
	)
	_expect(tabs != null and tabs.get_tab_count() == 4, "level editor exposes terrain, path, wave, and camera pages")
	tabs.current_tab = 1
	await process_frame
	await process_frame
	var path_canvas: Control = panel.get("_path_canvas")
	var path_page := tabs.get_tab_control(1)
	var path_sidebar := path_page.get_child(0) as Control
	var path_sidebar_content := path_sidebar.get_child(0) as Control
	_expect(float(path_canvas.get("_view_zoom")) > 6.0, "hidden path page fits the level after its first real layout")
	_expect(
		path_sidebar.is_visible_in_tree() and path_sidebar_content.is_visible_in_tree() and path_sidebar_content.size.y > 0.0,
		"path page keeps its editing sidebar visible"
	)
	_click_canvas_center(path_canvas)
	_expect(path_canvas.has_focus() and bool(path_canvas.get("has_selected_cell")), "path page accepts focus and cell input after first display")
	tabs.current_tab = 3
	await process_frame
	await process_frame
	_expect(float(camera_canvas.get("_view_zoom")) > 6.0, "hidden camera page fits the level after its first real layout")
	var first_slot_status: String = camera_editor.call("get_slot_status", 0)
	_expect(camera_editor.is_visible_in_tree() and not first_slot_status.is_empty(), "camera page keeps its six-slot editor visible")
	_click_canvas_center(camera_canvas)
	_expect(camera_canvas.has_focus() and bool(camera_canvas.get("has_selected_cell")), "camera preview accepts focus and cell input after first display")
	_expect(camera_canvas != null and camera_editor != null, "level editor builds an independent camera page component and preview canvas")
	_expect(camera_canvas != panel.get("_canvas"), "camera authoring does not reuse or mutate the terrain page canvas")
	var level := panel.get("_level") as LevelResource
	_expect(level != null and level.camera_presets.is_empty(), "new level starts with six logically empty camera slots")
	var undo_redo := panel.get("_undo_redo") as UndoRedo
	panel.free()
	undo_redo.free()
	editor_main_host.queue_free()
	await process_frame


func _click_canvas_center(canvas: Control) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = canvas.size * 0.5
	canvas._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = press.position
	canvas._gui_input(release)


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
