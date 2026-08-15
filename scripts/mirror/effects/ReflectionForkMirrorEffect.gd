## Level-gated reflect effect: after the normal reflected direction is resolved,
## two complete attack branches are cloned to its left/right by the given angle.
@tool
class_name ReflectionForkMirrorEffect
extends MirrorAttackEffect

@export_range(0.1, 89.0, 0.1) var branch_angle_degrees: float = 15.0


func _init() -> void:
	effect_id = &"reflection_fork"
	minimum_mirror_level = 2


func get_reflection_branch_angles(_context: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array([-branch_angle_degrees, branch_angle_degrees])


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if (
		not is_finite(branch_angle_degrees)
		or branch_angle_degrees <= 0.0
		or branch_angle_degrees >= 90.0
	):
		errors.append("反射分支角必须在 (0, 90) 度")
	return errors
