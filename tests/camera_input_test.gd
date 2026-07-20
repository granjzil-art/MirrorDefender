extends SceneTree

const TileEditorCanvasScript := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")

var _checks: int = 0
var _failures: int = 0

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
	_expect(InputMap.has_action("cam_pitch_lower") and InputMap.has_action("cam_pitch_raise"), "X/C use dedicated pitch InputMap actions")
	_expect(not InputMap.has_action("cam_zoom_in") and not InputMap.has_action("cam_zoom_out"), "keyboard zoom actions are removed")
	_expect(is_equal_approx(rig.zoom_min, 2.0) and is_equal_approx(rig.zoom_max, 30.0), "runtime camera supports the larger 2-to-30 zoom distance range")
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
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	for _index in range(20):
		rig._unhandled_input(wheel_up)
	_expect(is_equal_approx(rig.get_zoom_distance(), 2.0), "mouse wheel reaches the new maximum magnification")
	_expect(is_equal_approx(camera.position.length(), rig.get_zoom_distance()), "gimbal camera distance follows wheel zoom")
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
	else:
		push_error("[CameraInput] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
