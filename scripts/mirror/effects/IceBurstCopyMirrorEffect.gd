## L2 CopyMirror effect for ice-tower copies. The source Building owns the
## shared interval; every eligible projection resolves its own first-hit point.
@tool
class_name IceBurstCopyMirrorEffect
extends MirrorAttackEffect

@export_range(0.01, 60.0, 0.1, "or_greater") var burst_interval: float = 3.0
@export_range(0.0, 20.0, 0.05, "or_greater") var burst_radius_cells: float = 1.5
@export var freeze_durations: PackedFloat32Array = PackedFloat32Array([1.5, 2.25, 3.0])


func _init() -> void:
	effect_id = &"ice_copy_burst"
	minimum_mirror_level = 2


func apply_on_copy(attack_effects: AttackEffectPayload, context: Dictionary) -> void:
	if StringName(context.get("copy_kind", &"")) != &"laser_tower":
		return
	attack_effects.add_effect(self)


func apply_copy_burst(
	building: Node,
	combat_manager: CombatManager,
	endpoint: Vector3,
	copy_upgrade_count: int,
	damage_multiplier: float
) -> void:
	if building == null or combat_manager == null:
		return
	var radius := burst_radius_cells * maxf(
		0.001,
		float(building.call("get_grid_cell_size"))
	)
	if radius <= 0.0:
		return
	var color: Color = building.call("get_attack_color")
	combat_manager.spawn_laser_burst_visual(endpoint, radius, color)
	var slow_multiplier: float = building.call("get_laser_slow_multiplier")
	var slow_duration: float = building.call("get_laser_slow_duration")
	var copy_count := clampi(copy_upgrade_count, 1, 3)
	var freeze_duration := (
		float(freeze_durations[copy_count - 1])
		if freeze_durations.size() >= copy_count
		else 0.0
	)
	var resolved_damage_multiplier := (
		maxf(0.0, damage_multiplier) if is_finite(damage_multiplier) else 1.0
	)
	var burst_damage := float(building.call("get_laser_burst_damage")) * resolved_damage_multiplier
	for target in combat_manager.get_targets_in_range(endpoint, radius):
		if not bool(building.call("affects_target", target)):
			continue
		target.apply_movement_slow(slow_multiplier, slow_duration)
		if freeze_duration > 0.0:
			target.apply_freeze(freeze_duration)
		target.take_damage(burst_damage)


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if freeze_durations.size() != 3:
		errors.append("冰冻复制爆发冻结时间必须配置复制强化 1..3 共三档")
	return errors
