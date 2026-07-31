## CameraController —— 斜俯视 gimbal 相机
##
## 结构：本节点 = pivot（焦点，可平移 + 绕 Y 旋转 yaw）。
##       子 Camera3D 以可调 pitch 俯视、沿 -forward 后退 zoom_distance。
## 操作（InputMap）：
##   WASD  cam_move_*   —— 沿当前 yaw 朝向在 XZ 平面平移焦点
##   QE    cam_rotate_* —— 绕 Y 轴旋转 yaw
##   XC    cam_pitch_*  —— 降低/提高俯仰角
##   中键拖动           —— 沿相机屏幕平面平移焦点
##   右键拖动           —— 环绕旋转；短点击请求取消
##   鼠标滚轮           —— 唯一缩放输入
## 铁律「参数化」：速度/角度/缩放范围全 @export，运行时可调。
class_name CameraController
extends Node3D

signal cancel_requested

@export_group("Feature")
@export var input_enabled: bool = true

@export_group("Mouse Navigation")
@export var mouse_navigation_enabled: bool = true
@export_range(0.0, 0.02, 0.0001, "or_greater") var pan_sensitivity: float = 0.003
@export_range(0.0, 2.0, 0.01, "or_greater") var orbit_sensitivity: float = 0.2
@export_range(0.0, 64.0, 0.5, "or_greater") var drag_threshold_pixels: float = 6.0

@export_group("Move")
@export var move_speed: float = 8.0
## 屏幕边缘平移（可开关）。初版默认关。
@export var edge_pan: bool = false
@export var edge_pan_margin: float = 16.0

@export_group("Rotate")
@export var rotate_speed: float = 90.0  # 度/秒

@export_group("Zoom")
@export var zoom_distance: float = 16.0
@export var zoom_min: float = 2.0
@export var zoom_max: float = 30.0
@export var zoom_wheel_step: float = 1.5   # 滚轮每格步进

@export_group("Pitch")
@export var pitch_angle: float = 50.0
@export var pitch_min: float = 18.0
@export var pitch_max: float = 82.0
@export var pitch_speed: float = 55.0

@onready var _camera: Camera3D = $Camera3D
var _preset_transition_active: bool = false
var _middle_drag_active: bool = false
var _right_drag_active: bool = false
var _right_orbit_allowed: bool = false
var _right_dragging: bool = false
var _right_drag_distance: float = 0.0
var _pointer_over_gui_override_enabled: bool = false
var _pointer_over_gui_override: bool = false

func _ready() -> void:
	zoom_distance = clampf(zoom_distance, zoom_min, zoom_max)
	pitch_angle = clampf(pitch_angle, pitch_min, pitch_max)
	_apply_camera_transform()

func _process(delta: float) -> void:
	if not input_enabled or _preset_transition_active:
		return
	# Engine.time_scale slows gameplay simulation. Camera navigation remains
	# responsive during tactical slow by using the reconstructed real delta.
	var real_delta := delta
	if Engine.time_scale > 0.0001:
		real_delta /= Engine.time_scale
	_handle_move(real_delta)
	_handle_rotate(real_delta)
	_handle_pitch(real_delta)

func _handle_move(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("cam_move_right") - Input.get_action_strength("cam_move_left"),
		Input.get_action_strength("cam_move_back") - Input.get_action_strength("cam_move_forward")
	)
	if edge_pan:
		input += _edge_pan_input()
	if input == Vector2.ZERO:
		return
	# 把输入按当前 yaw 旋转到世界方向（只在 XZ 平面）。
	var yaw := rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var move := (right * input.x + forward * -input.y).normalized()
	global_position += move * move_speed * delta

func _edge_pan_input() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var mp := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	var out := Vector2.ZERO
	if mp.x < edge_pan_margin: out.x -= 1
	elif mp.x > size.x - edge_pan_margin: out.x += 1
	if mp.y < edge_pan_margin: out.y -= 1
	elif mp.y > size.y - edge_pan_margin: out.y += 1
	return out

func _handle_rotate(delta: float) -> void:
	var r := Input.get_action_strength("cam_rotate_right") - Input.get_action_strength("cam_rotate_left")
	if r != 0.0:
		rotation.y -= deg_to_rad(rotate_speed * delta) * r

func _handle_pitch(delta: float) -> void:
	var value := Input.get_action_strength("cam_pitch_raise") - Input.get_action_strength("cam_pitch_lower")
	if value != 0.0:
		_set_pitch(pitch_angle + pitch_speed * delta * value)


func _input(event: InputEvent) -> void:
	if not input_enabled or _preset_transition_active:
		return
	if not mouse_navigation_enabled:
		_middle_drag_active = false
		_right_orbit_allowed = false
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		_handle_mouse_button(mouse_button)
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		_handle_mouse_motion(mouse_motion)
	return


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if _can_start_mouse_navigation():
				_middle_drag_active = true
				get_viewport().set_input_as_handled()
		elif _middle_drag_active:
			_middle_drag_active = false
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if event.pressed:
		_right_drag_active = true
		_right_orbit_allowed = _can_start_mouse_navigation()
		_right_dragging = false
		_right_drag_distance = 0.0
		if _right_orbit_allowed:
			get_viewport().set_input_as_handled()
		return
	if not _right_drag_active:
		return
	var should_cancel := not _right_dragging
	_right_drag_active = false
	_right_orbit_allowed = false
	_right_dragging = false
	_right_drag_distance = 0.0
	get_viewport().set_input_as_handled()
	if should_cancel:
		cancel_requested.emit()
	return


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var handled := false
	if _middle_drag_active:
		_pan_from_mouse(event.relative)
		handled = true
	if _right_drag_active:
		_right_drag_distance += event.relative.length()
		if not _right_dragging and _right_drag_distance >= drag_threshold_pixels:
			_right_dragging = true
		if _right_dragging and _right_orbit_allowed:
			_orbit_from_mouse(event.relative)
			handled = true
	if handled:
		get_viewport().set_input_as_handled()
	return


func _can_start_mouse_navigation() -> bool:
	if not mouse_navigation_enabled:
		return false
	if _pointer_over_gui_override_enabled:
		return not _pointer_over_gui_override
	var viewport := get_viewport()
	return viewport != null and viewport.gui_get_hovered_control() == null


func set_pointer_over_gui_for_test(enabled: bool, over_gui: bool = false) -> void:
	_pointer_over_gui_override_enabled = enabled
	_pointer_over_gui_override = over_gui
	return


func _pan_from_mouse(relative: Vector2) -> void:
	if _camera == null or relative == Vector2.ZERO:
		return
	var right := _camera.global_basis.x.normalized()
	var up := _camera.global_basis.y.normalized()
	var world_per_pixel := zoom_distance * pan_sensitivity
	global_position += (-right * relative.x + up * relative.y) * world_per_pixel
	return


func _orbit_from_mouse(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	rotation.y = wrapf(
		rotation.y - deg_to_rad(relative.x * orbit_sensitivity),
		-PI,
		PI
	)
	_set_pitch(pitch_angle + relative.y * orbit_sensitivity)
	return


func _clear_mouse_gestures() -> void:
	_middle_drag_active = false
	_right_drag_active = false
	_right_orbit_allowed = false
	_right_dragging = false
	_right_drag_distance = 0.0
	return


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _preset_transition_active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom_distance - zoom_wheel_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom_distance + zoom_wheel_step)

func _set_zoom(v: float) -> void:
	zoom_distance = clampf(v, zoom_min, zoom_max)
	_apply_camera_transform()

func _set_pitch(v: float) -> void:
	pitch_angle = clampf(v, pitch_min, pitch_max)
	_apply_camera_transform()

## 依据 pitch + zoom 把子相机放到焦点后上方并俯视焦点。
func _apply_camera_transform() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(pitch_angle)
	# 相机在本地空间：位于 -Z 方向后退、+Y 抬高，俯视原点(焦点)。
	var local_pos := Vector3(0.0, sin(pitch), cos(pitch)) * zoom_distance
	_camera.position = local_pos
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)

func get_camera() -> Camera3D:
	return _camera

func get_zoom_distance() -> float:
	return zoom_distance

func get_pitch_angle() -> float:
	return pitch_angle


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_clear_mouse_gestures()
	return


func is_input_enabled() -> bool:
	return input_enabled


func set_preset_transition_active(active: bool) -> void:
	_preset_transition_active = active
	if active:
		_clear_mouse_gestures()
	return


func is_preset_transition_active() -> bool:
	return _preset_transition_active


func get_view_state() -> Dictionary:
	return {
		"focus_position": global_position,
		"yaw_degrees": rad_to_deg(rotation.y),
		"pitch_degrees": pitch_angle,
		"zoom_distance": zoom_distance,
	}


func apply_view_state(
	focus_position: Vector3,
	yaw_degrees: float,
	pitch_degrees: float,
	distance: float
) -> void:
	global_position = focus_position
	rotation.y = deg_to_rad(yaw_degrees)
	pitch_angle = clampf(pitch_degrees, pitch_min, pitch_max)
	zoom_distance = clampf(distance, zoom_min, zoom_max)
	_apply_camera_transform()
