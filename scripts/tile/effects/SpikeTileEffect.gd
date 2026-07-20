@tool
## Frame-rate-independent damage while an enemy occupies a spike tile.
class_name SpikeTileEffect
extends TileEffect

@export_group("Damage")
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage_per_second: float = 20.0
@export var ignores_armor: bool = true

func apply_stay(target: Node, duration: float) -> void:
	if target == null or not is_instance_valid(target) or duration <= 0.0 or not affects_target(target):
		return
	if ignores_armor and target.has_method("take_unmitigated_damage"):
		target.call("take_unmitigated_damage", damage_per_second * duration)
	elif target.has_method("take_damage_over_time"):
		target.call("take_damage_over_time", damage_per_second, duration)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage_per_second * duration)

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(damage_per_second) or damage_per_second < 0.0:
		errors.append("尖刺每秒伤害必须为有限非负数")
	return errors

func get_copy_kind() -> StringName:
	return &"spike"

func get_copy_display_name() -> String:
	return "尖刺"

func get_copy_color() -> Color:
	return Color(0.9, 0.28, 0.2)
