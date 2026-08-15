## L2 ReflectMirror effect for missiles. Growth is recalculated linearly from
## the original projectile, never multiplied from the previous reflection.
@tool
class_name MissileReflectionGrowthEffect
extends MirrorAttackEffect

@export_range(0.0, 2.0, 0.01, "or_greater") var visual_scale_per_upgrade: float = 0.15
@export_range(0.0, 2.0, 0.01, "or_greater") var explosion_radius_per_upgrade: float = 0.10


func _init() -> void:
	effect_id = &"missile_reflection_growth"
	minimum_mirror_level = 2


func apply_on_reflection(
	_attack_effects: AttackEffectPayload,
	context: Dictionary
) -> void:
	if StringName(context.get("attack_kind", &"")) != &"missile":
		return
	var projectile: Object = context.get("projectile") as Object
	if projectile == null or not projectile.has_method("apply_mirror_reflection_growth"):
		return
	projectile.call(
		"apply_mirror_reflection_growth",
		maxi(0, int(context.get("reflection_upgrade_count", 0))),
		visual_scale_per_upgrade,
		explosion_radius_per_upgrade
	)
