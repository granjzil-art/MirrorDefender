## Level-two reflect effect: only ArrowTower projectiles gain penetration.
@tool
class_name ArrowReflectionMirrorEffect
extends MirrorAttackEffect

@export_range(0, 16, 1) var penetration_bonus: int = 2


func _init() -> void:
	effect_id = &"arrow_reflection"
	minimum_mirror_level = 2


func get_reflection_penetration_bonus(context: Dictionary) -> int:
	var source := context.get("source_building") as Object
	if source == null or not is_instance_valid(source) or not source.has_method("get_copy_kind"):
		return 0
	return penetration_bonus if StringName(source.call("get_copy_kind")) == &"arrow_tower" else 0


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if penetration_bonus < 0:
		errors.append("箭塔反射穿透加成不能小于零")
	return errors
