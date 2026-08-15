## L2 CopyMirror effect for missile-tower copies. The burning area is independent
## from the missile's explosion radius and grows only with copy reinforcement.
@tool
class_name BurningMissileMirrorEffect
extends MirrorAttackEffect

@export_range(0.0, 20.0, 0.05, "or_greater") var base_radius_cells: float = 1.5
@export var radius_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5])
@export_range(0.0, 60.0, 0.1, "or_greater") var burn_duration: float = 4.0
@export_range(0.0, 10.0, 0.005, "or_greater") var damage_per_second_ratio: float = 0.125


func _init() -> void:
	effect_id = &"burning_missile"
	minimum_mirror_level = 2


func apply_on_copy(attack_effects: AttackEffectPayload, context: Dictionary) -> void:
	if StringName(context.get("copy_kind", &"")) != &"crossbow_tower":
		return
	attack_effects.add_effect(self)


func on_missile_explosion(
	attack_effects: AttackEffectPayload,
	_state: Dictionary,
	missile: Object,
	world_position: Vector3,
	explosion_damage: float
) -> void:
	if missile == null or not missile.has_method("apply_burning_area"):
		return
	var copy_count := clampi(attack_effects.get_copy_upgrade_count(), 1, 3)
	var multiplier := (
		float(radius_multipliers[copy_count - 1])
		if radius_multipliers.size() >= copy_count
		else 1.0
	)
	var cell_size := (
		float(missile.call("get_grid_cell_size"))
		if missile.has_method("get_grid_cell_size")
		else 1.0
	)
	missile.call(
		"apply_burning_area",
		world_position,
		base_radius_cells * maxf(0.0, multiplier) * maxf(0.001, cell_size),
		maxf(0.0, explosion_damage) * damage_per_second_ratio,
		burn_duration
	)


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if radius_multipliers.size() != 3:
		errors.append("导弹燃烧半径倍率必须配置复制强化 1..3 共三档")
	return errors
