## CameraController —— 斜俯视 gimbal 相机
##
## 结构：本节点 = pivot（焦点，可平移 + 绕 Y 旋转 yaw）。
##       子 Camera3D 以固定 pitch 俯视、沿 -forward 后退 zoom_distance。
## 操作（InputMap）：
##   WASD  cam_move_*   —— 沿当前 yaw 朝向在 XZ 平面平移焦点
##   QE    cam_rotate_* —— 绕 Y 轴旋转 yaw
##   XC    cam_zoom_*   —— 拉近/拉远
##   鼠标滚轮           —— 缩放
## 铁律「参数化」：速度/角度/缩放范围全 @export，运行时可调。
class_name CameraController
extends Node3D

@export_group("Move")
@export var move_speed: float = 8.0
## 屏幕边缘平移（可开关）。初版默认关。
@export var edge_pan: bool = false
@export var edge_pan_margin: float = 16.0

@export_group("Rotate")
@export var rotate_speed: float = 90.0  # 度/秒

@export_group("Zoom")
@export var zoom_distance: float = 16.0
@export var zoom_min: float = 5.0
@export var zoom_max: float = 30.0
@export var zoom_speed: float = 20.0       # XC 持续缩放速度
@export var zoom_wheel_step: float = 1.5   # 滚轮每格步进
@export var pitch_angle: float = 50.0      # 俯仰角(度)，固定

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	_apply_camera_transform()

func _process(delta: float) -> void:
	_handle_move(delta)
	_handle_rotate(delta)
	_handle_zoom_keys(delta)

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

func _handle_zoom_keys(delta: float) -> void:
	var z := Input.get_action_strength("cam_zoom_out") - Input.get_action_strength("cam_zoom_in")
	if z != 0.0:
		_set_zoom(zoom_distance + zoom_speed * delta * z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom_distance - zoom_wheel_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom_distance + zoom_wheel_step)

func _set_zoom(v: float) -> void:
	zoom_distance = clampf(v, zoom_min, zoom_max)
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
