extends SceneTree

const TileEditorCanvasScript := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")

var _checks: int = 0
var _failures: int = 0
var _cancel_requests: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[CameraInput] running")
	var rig := CameraController.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	await process_frame
	rig.cancel_requested.connect(_on_cancel_requested)
	_expect(InputMap.has_action("cam_pitch_lower") and InputMap.has_action("cam_pitch_raise"), "X/C use dedicated pitch InputMap actions")
	_expect(not InputMap.has_action("cam_zoom_in") and not InputMap.has_action("cam_zoom_out"), "keyboard zoom actions are removed")
	_expect(is_equal_approx(rig.zoom_min, 2.0) and is_equal_approx(rig.zoom_max, 30.0), "runtime camera supports the larger 2-to-30 zoom distance range")
	_expect(rig.mouse_navigation_enabled and rig.pan_sensitivity > 0.0 and rig.orbit_sensitivity > 0.0, "runtime mouse navigation is parameterized and enabled by default")

	var original_zoom := rig.get_zoom_distance()
	Input.action_press("cam_pitch_lower")
	rig._process(1.0)
	Input.action_release("cam_pitch_lower")
	_expect(is_equal_approx(rig.get_pitch_angle(), rig.pitch_min), "X lowers and clamps the camera pitch")
	_expect(is_equal_approx(rig.get_zoom_distance(), original_zoom), "pitch input never changes zoom distance")
	rig._set_pitch(50.0)
	Input.action_press("cam_pitch_raise")
	rig._process(1.0)
	Input.action_release("cam_pitch_raise")
	_expect(is_equal_approx(rig.get_pitch_angle(), rig.pitch_max), "C raises and clamps the camera pitch")

	rig.apply_view_state(Vector3.ZERO, 0.0, 50.0, 10.0)
	var pan_relative := Vector2(20.0, -10.0)
	var expected_pan := (
		-camera.global_basis.x.normalized() * pan_relative.x
		+ camera.global_basis.y.normalized() * pan_relative.y
	) * rig.get_zoom_distance() * rig.pan_sensitivity
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, true))
	rig._input(_mouse_motion(pan_relative))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, false))
	var near_pan := rig.global_position
	_expect(near_pan.is_equal_approx(expected_pan), "middle drag pans the pivot in grab-the-view screen-plane direction")
	_expect(near_pan.x < 0.0 and near_pan.y < 0.0, "middle right/up drag moves the camera left/down so the scene follows right/up with Y change")

	rig.apply_view_state(Vector3.ZERO, 0.0, 50.0, 20.0)
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, true))
	rig._input(_mouse_motion(pan_relative))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, false))
	var far_pan := rig.global_position
	_expect(is_equal_approx(far_pan.length(), near_pan.length() * 2.0), "middle drag world sensitivity scales linearly with zoom distance")

	_cancel_requests = 0
	rig.apply_view_state(Vector3.ZERO, 0.0, 50.0, 16.0)
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(_cancel_requests == 1 and is_zero_approx(rig.rotation.y), "short right click emits one cancel request on release without changing yaw")
	_cancel_requests = 0
	rig.mouse_navigation_enabled = false
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(_cancel_requests == 1, "disabling mouse navigation preserves short-click cancellation")
	rig.mouse_navigation_enabled = true

	_cancel_requests = 0
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_motion(Vector2(2.0, 0.0)))
	rig._input(_mouse_motion(Vector2(2.0, 0.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(_cancel_requests == 1 and is_zero_approx(rig.rotation.y), "accumulated right motion below threshold remains one short click")

	_cancel_requests = 0
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_motion(Vector2(4.0, 0.0)))
	_expect(is_zero_approx(rig.rotation.y), "right motion does not orbit before the drag threshold")
	rig._input(_mouse_motion(Vector2(4.0, -5.0)))
	var drag_yaw := rad_to_deg(rig.rotation.y)
	var drag_pitch := rig.get_pitch_angle()
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(drag_yaw > 0.0 and drag_pitch > 50.0, "right/up drag orbits in grab-the-view yaw and raised-pitch directions")
	_expect(_cancel_requests == 0, "right drag above threshold never emits cancel")

	rig.apply_view_state(Vector3.ZERO, 0.0, 80.0, 16.0)
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_motion(Vector2(0.0, -20.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(is_equal_approx(rig.get_pitch_angle(), 82.0), "mouse orbit clamps raised pitch to 82 degrees")
	rig._set_pitch(20.0)
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig._input(_mouse_motion(Vector2(0.0, 20.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(is_equal_approx(rig.get_pitch_angle(), 18.0), "mouse orbit clamps lowered pitch to 18 degrees")

	_cancel_requests = 0
	rig.apply_view_state(Vector3.ZERO, 0.0, 50.0, 16.0)
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, true))
	rig.set_input_enabled(false)
	rig.set_input_enabled(true)
	rig._input(_mouse_motion(Vector2(20.0, 20.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, false))
	_expect(rig.global_position == Vector3.ZERO, "disabling input clears an active middle drag")
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig.set_input_enabled(false)
	rig.set_input_enabled(true)
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(_cancel_requests == 0, "disabling input clears an active right click")

	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	rig.set_preset_transition_active(true)
	rig.set_preset_transition_active(false)
	rig._input(_mouse_motion(Vector2(20.0, -20.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	_expect(is_zero_approx(rig.rotation.y) and is_equal_approx(rig.get_pitch_angle(), 50.0), "preset transition clears orbit state and blocks stale motion")
	_expect(_cancel_requests == 0, "preset transition clears pending short-click cancellation")

	rig.set_input_enabled(false)
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, true))
	rig._input(_mouse_motion(Vector2(20.0, 20.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, false))
	rig.set_input_enabled(true)
	_expect(rig.global_position == Vector3.ZERO, "disabled camera ignores new mouse gestures")

	rig.set_pointer_over_gui_for_test(true, true)
	_cancel_requests = 0
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(50.0, 50.0)))
	rig._input(_mouse_motion(Vector2(20.0, -20.0), Vector2(70.0, 30.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(70.0, 30.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, true, Vector2(50.0, 50.0)))
	rig._input(_mouse_motion(Vector2(20.0, 20.0), Vector2(70.0, 70.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_MIDDLE, false, Vector2(70.0, 70.0)))
	_expect(_cancel_requests == 0 and rig.global_position == Vector3.ZERO, "HUD-started drag gestures never navigate or become short clicks")
	_expect(is_zero_approx(rig.rotation.y) and is_equal_approx(rig.get_pitch_angle(), 50.0), "HUD-started right drag leaves orbit unchanged")
	_cancel_requests = 0
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(50.0, 50.0)))
	rig._input(_mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(50.0, 50.0)))
	_expect(_cancel_requests == 1, "HUD-started short right click preserves global cancellation on release")
	rig.set_pointer_over_gui_for_test(false)

	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	for _index in range(20):
		rig._unhandled_input(wheel_up)
	_expect(is_equal_approx(rig.get_zoom_distance(), 2.0), "mouse wheel still reaches the maximum magnification")
	_expect(is_equal_approx(camera.position.length(), rig.get_zoom_distance()), "gimbal camera distance still follows wheel zoom")
	var editor_canvas := TileEditorCanvasScript.new()
	var editor_constants: Dictionary = editor_canvas.get_script().get_script_constant_map()
	_expect(is_equal_approx(float(editor_constants.get("MAX_ZOOM", 0.0)), 300.0), "level editor maximum canvas magnification is raised to 300")
	_expect(editor_constants.has("CAMERA_PITCH_SPEED") and not editor_constants.has("CAMERA_ZOOM_SPEED"), "level editor X/C controls pitch instead of zoom")
	editor_canvas.free()
	rig.queue_free()
	await process_frame
	if _failures == 0:
		print("[CameraInput] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[CameraInput] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)

func _mouse_button(
	button_index: MouseButton,
	pressed: bool,
	position: Vector2 = Vector2(400.0, 300.0)
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = position
	return event


func _mouse_motion(
	relative: Vector2,
	position: Vector2 = Vector2(400.0, 300.0)
) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = position
	return event


func _on_cancel_requested() -> void:
	_cancel_requests += 1


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
