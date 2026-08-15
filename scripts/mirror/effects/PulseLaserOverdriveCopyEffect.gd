## L2 CopyMirror effect for pulse-laser copies. Logical charge ownership lives
## on the source Building; this resource contains only adjustable gameplay and
## programmatic presentation values.
@tool
class_name PulseLaserOverdriveCopyEffect
extends MirrorAttackEffect

@export_range(1, 64, 1) var charge_shots: int = 5
@export_range(0.0, 120.0, 0.1, "or_greater") var overdrive_duration: float = 10.0
@export var charge_orb_color: Color = Color(1.0, 0.025, 0.01, 0.92)
@export_range(0.01, 10.0, 0.01, "or_greater") var charge_orb_min_scale: float = 0.65
@export_range(0.01, 10.0, 0.01, "or_greater") var charge_orb_max_scale: float = 1.35
@export_range(0.01, 100.0, 0.1, "or_greater") var charge_orb_pulse_speed: float = 12.0
@export_range(0.01, 20.0, 0.01, "or_greater") var charge_orb_radius_multiplier: float = 2.2
@export var dps_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 1.15, 1.30])
@export var beam_width_multipliers: PackedFloat32Array = PackedFloat32Array([1.5, 1.75, 2.0])
@export_range(0.01, 100.0, 0.1, "or_greater") var propagation_speed_cells_per_second: float = 20.0
@export_range(0.01, 4.0, 0.01, "or_greater") var sine_thickness_multiplier: float = 1.0
@export_range(0.0, 4.0, 0.01, "or_greater") var sine_amplitude_ratio: float = 0.42
@export_range(0.1, 100.0, 0.1, "or_greater") var sine_wavelength_ratio: float = 13.0
@export_range(0.0, 20.0, 0.05, "or_greater") var sine_flow_cycles_per_second: float = 1.25
@export_range(1.0, 64.0, 1.0, "or_greater") var sine_samples_per_cycle: float = 12.0
@export_range(1, 256, 1) var sine_min_subdivisions: int = 8
@export_range(1, 512, 1) var sine_max_subdivisions: int = 128


func _init() -> void:
	effect_id = &"pulse_laser_overdrive"
	minimum_mirror_level = 2


func apply_on_copy(attack_effects: AttackEffectPayload, context: Dictionary) -> void:
	if StringName(context.get("copy_kind", &"")) != &"pulse_laser_tower":
		return
	attack_effects.add_effect(self)


func get_dps_multiplier(copy_upgrade_count: int) -> float:
	return _get_tier_value(dps_multipliers, copy_upgrade_count, 1.0)


func get_beam_width_multiplier(copy_upgrade_count: int) -> float:
	return _get_tier_value(beam_width_multipliers, copy_upgrade_count, 1.0)


func _get_tier_value(values: PackedFloat32Array, copy_upgrade_count: int, fallback: float) -> float:
	var index := clampi(copy_upgrade_count, 1, 3) - 1
	return maxf(0.0, float(values[index])) if index < values.size() else fallback


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if dps_multipliers.size() != 3:
		errors.append("镭射爆发 DPS 倍率必须配置复制强化 1..3 共三档")
	if beam_width_multipliers.size() != 3:
		errors.append("镭射爆发宽度倍率必须配置复制强化 1..3 共三档")
	if charge_orb_max_scale < charge_orb_min_scale:
		errors.append("镭射充能球最大缩放不能小于最小缩放")
	if sine_min_subdivisions > sine_max_subdivisions:
		errors.append("镭射正弦最小细分不能大于最大细分")
	return errors
