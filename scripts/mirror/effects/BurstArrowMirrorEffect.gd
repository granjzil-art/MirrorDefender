## Level-gated copy effect: copied arrow projectiles burst into radial arrows on
## every valid piercing impact. Child-only state prevents recursive re-bursting.
@tool
class_name BurstArrowMirrorEffect
extends MirrorAttackEffect

@export var direction_counts: Array[int] = [4, 6, 8]
@export_range(0.0, 2.0, 0.05) var child_damage_multiplier: float = 0.25
@export_range(0.05, 1.0, 0.05) var child_distance_multiplier: float = 0.30
@export_range(0, 16, 1) var child_penetration_count: int = 0


func _init() -> void:
	effect_id = &"burst_arrow"
	minimum_mirror_level = 2


func apply_on_copy(attack_effects: AttackEffectPayload, context: Dictionary) -> void:
	if StringName(context.get("copy_kind", StringName())) != &"arrow_tower":
		return
	attack_effects.add_effect(self, {"is_burst_child": false})


func on_projectile_impact(
	attack_effects: AttackEffectPayload,
	state: Dictionary,
	projectile: Object,
	_target: CombatTarget
) -> void:
	if bool(state.get("is_burst_child", false)):
		return
	if projectile == null or not is_instance_valid(projectile):
		return
	if not projectile.has_method("spawn_radial_attack_copies"):
		return
	var copy_upgrade_count := clampi(attack_effects.get_copy_upgrade_count(), 1, 3)
	var projectile_count := direction_counts[copy_upgrade_count - 1]
	projectile.call(
		"spawn_radial_attack_copies",
		projectile_count,
		child_damage_multiplier,
		child_distance_multiplier,
		child_penetration_count,
		attack_effects,
		{effect_id: {"is_burst_child": true}}
	)


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if direction_counts.size() != 3:
		errors.append("爆裂箭必须配置三档复制强化方向数")
	else:
		for index in range(direction_counts.size()):
			if direction_counts[index] < 2:
				errors.append("爆裂箭第%d档方向数必须至少为 2" % (index + 1))
	if not is_finite(child_damage_multiplier) or child_damage_multiplier < 0.0:
		errors.append("爆裂箭子弹伤害倍率无效")
	if (
		not is_finite(child_distance_multiplier)
		or child_distance_multiplier <= 0.0
		or child_distance_multiplier > 1.0
	):
		errors.append("爆裂箭子弹射程倍率必须在 (0, 1]")
	if child_penetration_count < 0:
		errors.append("爆裂箭子弹穿透数不能小于零")
	return errors
