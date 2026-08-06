@tool
## Projectile-reflection effect tuning for one physical edge mirror type.
class_name ReflectMirrorDefinition
extends MirrorDefinition

@export_group("Projectile Reflection")
## Prevents the reflected ray from immediately hitting the same plane again.
@export_range(0.0001, 0.05, 0.0001) var collision_epsilon_ratio: float = 0.002
## Safety budget for very high-speed projectiles crossing many mirrors in one frame.
## This is not a lifetime cap; unfinished travel continues next frame.
@export_range(1, 32, 1) var max_reflections_per_frame: int = 8


func _init() -> void:
	display_name = "反射镜"


func validate_configuration() -> Array[String]:
	var errors: Array[String] = super.validate_configuration()
	ConfigValidator.require_number(errors, "反射碰撞偏移比例", collision_epsilon_ratio, 0.0001, 0.05)
	ConfigValidator.require_integer_range(errors, "单帧反射上限", max_reflections_per_frame, 1, 32)
	return errors
