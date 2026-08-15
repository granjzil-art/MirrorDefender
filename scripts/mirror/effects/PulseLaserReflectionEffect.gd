## L2 ReflectMirror effect for ordinary pulse beams and copied overdrive beams.
@tool
class_name PulseLaserReflectionEffect
extends MirrorAttackEffect

@export var reflection_colors: Array[Color] = [
	Color(1.0, 0.08, 0.04, 1.0),
	Color(1.0, 0.36, 0.03, 1.0),
	Color(1.0, 0.88, 0.04, 1.0),
	Color(0.16, 1.0, 0.20, 1.0),
	Color(0.02, 0.92, 1.0, 1.0),
	Color(0.10, 0.34, 1.0, 1.0),
	Color(0.62, 0.12, 1.0, 1.0),
]
@export_range(0.0, 2.0, 0.01, "or_greater") var width_per_upgrade: float = 0.25


func _init() -> void:
	effect_id = &"pulse_laser_reflection"
	minimum_mirror_level = 2


func apply_on_reflection(
	attack_effects: AttackEffectPayload,
	context: Dictionary
) -> void:
	if StringName(context.get("attack_kind", &"")) not in [&"pulse_laser", &"pulse_overdrive"]:
		return
	attack_effects.add_effect(self)


func get_laser_visual_modifiers(context: Dictionary) -> Dictionary:
	var count := maxi(0, int(context.get("reflection_upgrade_count", 0)))
	var result := {"width_multiplier": 1.0 + count * maxf(0.0, width_per_upgrade)}
	if not reflection_colors.is_empty():
		result["color"] = reflection_colors[count % reflection_colors.size()]
	return result


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if reflection_colors.is_empty():
		errors.append("镭射二级反射颜色序列不能为空")
	return errors
