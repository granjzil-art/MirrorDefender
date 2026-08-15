## Extensible resource hook for effects granted by copy/reflect mirror levels.
## Concrete effects may attach persistent attack state on copy, modify that state
## on reflection, react to projectile impact, or request reflected branch angles.
@tool
class_name MirrorAttackEffect
extends Resource

@export var effect_id: StringName = &"mirror_attack_effect"
@export_range(1, 2, 1) var minimum_mirror_level: int = 1


func get_effect_id() -> StringName:
	return effect_id


func is_active_for_level(mirror_level: int) -> bool:
	return mirror_level >= minimum_mirror_level


func apply_on_copy(
	_attack_effects: AttackEffectPayload,
	_context: Dictionary
) -> void:
	pass


func apply_on_reflection(
	_attack_effects: AttackEffectPayload,
	_context: Dictionary
) -> void:
	pass


func get_reflection_branch_angles(_context: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array()


func get_reflection_penetration_bonus(_context: Dictionary) -> int:
	return 0


## Optional persistent visual properties for laser segments after this effect
## has been attached to the attack payload by a reflection.
func get_laser_visual_modifiers(_context: Dictionary) -> Dictionary:
	return {}


func on_projectile_impact(
	_attack_effects: AttackEffectPayload,
	_state: Dictionary,
	_projectile: Object,
	_target: CombatTarget
) -> void:
	pass


func on_missile_explosion(
	_attack_effects: AttackEffectPayload,
	_state: Dictionary,
	_missile: Object,
	_world_position: Vector3,
	_explosion_damage: float
) -> void:
	pass


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if effect_id == StringName():
		errors.append("镜子攻击效果 ID 不能为空")
	if minimum_mirror_level < 1 or minimum_mirror_level > 2:
		errors.append("镜子攻击效果最低等级必须在 1..2")
	return errors
