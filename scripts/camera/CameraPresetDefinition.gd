@tool
## One optional per-level camera view. LevelResource owns up to six instances.
class_name CameraPresetDefinition
extends Resource

@export_group("View")
## CameraController pivot position in world space.
@export var focus_position: Vector3 = Vector3.ZERO
@export_range(-360.0, 360.0, 0.1) var yaw_degrees: float = 0.0
@export_range(1.0, 89.0, 0.1) var pitch_degrees: float = 50.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var zoom_distance: float = 16.0


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if not focus_position.is_finite():
		errors.append("焦点坐标必须为有限数")
	if not is_finite(yaw_degrees):
		errors.append("水平旋转角必须为有限数")
	if not is_finite(pitch_degrees) or pitch_degrees <= 0.0 or pitch_degrees >= 90.0:
		errors.append("俯仰角必须位于 0 到 90 度之间")
	if not is_finite(zoom_distance) or zoom_distance <= 0.0:
		errors.append("缩放距离必须为有限正数")
	return errors


func to_camera_state() -> Dictionary:
	return {
		"focus_position": focus_position,
		"yaw_degrees": yaw_degrees,
		"pitch_degrees": pitch_degrees,
		"zoom_distance": zoom_distance,
	}
