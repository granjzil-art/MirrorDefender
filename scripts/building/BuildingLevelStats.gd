## Complete editable parameters for one building level, capped at three levels in M3.
class_name BuildingLevelStats
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

enum ProjectileFireMode {
	TARGET_ONLY,
	TARGET_OR_FACING,
	FACING_ONLY,
}

@export_group("Economy")
## Level 1 uses this as construction cost; later levels use it as upgrade cost.
@export_range(0.0, 100000.0, 1.0, "or_greater") var cost: float = 75.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var resource_per_second: float = 0.0

@export_group("Combat")
@export var affects_airborne: bool = true
## When any airborne enemy is in targeting range, restricts the priority pass
## to airborne candidates before applying target_priority.
@export var prioritizes_airborne: bool = false
@export_range(0.0, 100000.0, 0.1, "or_greater") var base_damage: float = 20.0
@export_range(0.1, 100.0, 0.1, "or_greater") var targeting_range: float = 5.0
@export_range(0.1, 100.0, 0.1, "or_greater") var attack_range: float = 4.0
@export_range(0.01, 100.0, 0.01, "or_greater") var attacks_per_second: float = 1.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var laser_dps: float = 0.0
@export_range(0.0, 100.0, 0.05, "or_greater") var level_factor: float = 1.0
@export_range(0.0, 100.0, 0.05, "or_greater") var extra_factor: float = 1.0
@export_enum("最近", "最远", "最高血", "最低血", "最快", "首个进入", "锁定") var target_priority: int = 0
@export_range(1, 8, 1) var projectile_direction_count: int = 1

@export_group("Continuous Laser")
## Persistent beam presentation. Width follows the pulse laser's grid-relative contract.
@export var laser_beam_color: Color = Color(0.88, 0.96, 1.0, 0.96)
@export_range(0.01, 2.0, 0.01, "or_greater") var laser_beam_width: float = 0.08
@export_range(0.0, 32.0, 0.1, "or_greater") var laser_beam_emission_energy: float = 3.0
## Grid cells traveled per second. The logical hit endpoint uses this same front.
@export_range(0.01, 100.0, 0.1, "or_greater") var laser_propagation_speed: float = 4.0
## Effective movement speed multiplier while cold; 0.4 means 40% speed.
@export_range(0.0, 1.0, 0.05) var laser_slow_multiplier: float = 0.4
@export_range(0.0, 60.0, 0.1, "or_greater") var laser_slow_duration: float = 3.0
## Zero disables endpoint bursts for this level.
@export_range(0.0, 60.0, 0.1, "or_greater") var laser_burst_interval: float = 0.0
## Measured in grid cells and converted to world distance at runtime.
@export_range(0.0, 20.0, 0.1, "or_greater") var laser_burst_radius: float = 1.0
## Zero disables freeze for this level. Slow time pauses while frozen.
@export_range(0.0, 60.0, 0.1, "or_greater") var laser_freeze_duration: float = 0.0

@export_group("Defense")
@export_range(1.0, 1000000.0, 1.0, "or_greater") var max_durability: float = 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var regeneration_delay: float = 3.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var regeneration_per_second: float = 0.0
@export_range(0.0, 1.0, 0.01) var damage_reflection_ratio: float = 0.0

@export_group("Projectile")
## TARGET_OR_FACING tracks a target when available and otherwise fires along the
## logical facing. FACING_ONLY never queries targets and always uses that facing.
@export var projectile_fire_mode: ProjectileFireMode = ProjectileFireMode.TARGET_ONLY
@export_range(0.1, 100.0, 0.1, "or_greater") var projectile_speed: float = 7.0
@export_range(0.1, 5.0, 0.05, "or_greater") var projectile_length: float = 0.32
@export_range(0.02, 2.0, 0.01, "or_greater") var projectile_width: float = 0.07
## Extra targets this projectile may pass through after its first hit.
@export_range(0, 32, 1) var projectile_penetration_count: int = 0
@export var projectile_model_asset: ModelAssetDefinition

@export_group("Missile")
## Replaces the normal arrow projectile with the orbiting explosive missile.
@export var projectile_is_missile: bool = false
## Horizontal area damage radius in grid cells. Height is intentionally ignored.
@export_range(0.0, 20.0, 0.05, "or_greater") var missile_explosion_radius: float = 1.0
## Pure-presentation launch loop. It consumes neither range nor collision checks.
@export_range(0.01, 10.0, 0.01, "or_greater") var missile_orbit_duration: float = 0.72
@export_range(0.0, 10.0, 0.05, "or_greater") var missile_orbit_radius_x: float = 0.95
@export_range(0.0, 10.0, 0.05, "or_greater") var missile_orbit_radius_z: float = 0.62
@export_range(0.0, 5.0, 0.01, "or_greater") var missile_orbit_vertical_amplitude: float = 0.12
## Targeted missiles curve toward their marked target after the launch loop.
@export_range(1.0, 2160.0, 1.0, "or_greater") var missile_homing_turn_speed_degrees: float = 540.0
## Actual speed variation. A value of 0.12 varies between 88% and 112%.
@export_range(0.0, 0.95, 0.01) var missile_speed_variation_ratio: float = 0.12
@export_range(0.01, 30.0, 0.01, "or_greater") var missile_speed_variation_frequency: float = 2.4
## Visual-only lateral drift and roll; neither changes homing nor collision.
@export_range(0.0, 2.0, 0.01, "or_greater") var missile_visual_wobble: float = 0.045
@export_range(0.0, 180.0, 1.0, "or_greater") var missile_visual_roll_degrees: float = 12.0
@export_range(0.05, 5.0, 0.01, "or_greater") var missile_trail_lifetime: float = 0.42
@export_range(0.005, 1.0, 0.005, "or_greater") var missile_trail_width: float = 0.055
@export_range(0.05, 5.0, 0.05, "or_greater") var missile_target_marker_size: float = 0.72
@export_range(0.05, 5.0, 0.01, "or_greater") var missile_explosion_duration: float = 0.48

@export_group("Presentation")
@export var model_asset: ModelAssetDefinition
@export var tower_color: Color = Color(0.90, 0.52, 0.16, 1.0)
@export var attack_color: Color = Color(1.0, 0.82, 0.28, 1.0)

## Serialized compatibility for pre-contract resources. New content must use
## model_asset so scene and additive runtime scale stay one atomic setting.
@export_storage var visual_scene: PackedScene

@export_group("Pulse Laser")
## Per-level reflection budget. BuildingDefinition keeps its old root value only
## as serialized compatibility; runtime combat reads this level_data field.
@export_range(0, 64, 1) var pulse_laser_reflect_max: int = 8
@export_range(0.01, 2.0, 0.01, "or_greater") var pulse_laser_width: float = 0.12
@export_range(0.0, 32.0, 0.1, "or_greater") var pulse_laser_emission_energy: float = 3.0
@export_range(0.0, 10.0, 0.01, "or_greater") var pulse_laser_fade_in_time: float = 0.05
@export_range(0.0, 10.0, 0.01, "or_greater") var pulse_laser_hold_time: float = 0.06
@export_range(0.0, 10.0, 0.01, "or_greater") var pulse_laser_fade_out_time: float = 0.18


func get_model_asset() -> ModelAssetDefinition:
	if model_asset != null:
		return model_asset
	if visual_scene == null:
		return null
	var legacy_asset := ModelAssetDefinition.new()
	legacy_asset.scene = visual_scene
	return legacy_asset


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_integer_range(
		errors,
		"投射物开火模式",
		projectile_fire_mode,
		ProjectileFireMode.TARGET_ONLY,
		ProjectileFireMode.FACING_ONLY
	)
	ConfigValidator.require_number(errors, "造价", cost, 0.0)
	ConfigValidator.require_number(errors, "每秒资源产出", resource_per_second, 0.0)
	ConfigValidator.require_number(errors, "基础伤害", base_damage, 0.0)
	ConfigValidator.require_number(errors, "索敌范围", targeting_range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "攻击射程", attack_range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "每秒攻击次数", attacks_per_second, 0.0, INF, false)
	ConfigValidator.require_number(errors, "激光每秒伤害", laser_dps, 0.0)
	ConfigValidator.require_number(errors, "等级因子", level_factor, 0.0)
	ConfigValidator.require_number(errors, "额外因子", extra_factor, 0.0)
	ConfigValidator.require_integer_range(errors, "索敌优先级", target_priority, 0, 6)
	ConfigValidator.require_integer_range(errors, "投射物方向数", projectile_direction_count, 1, 8)
	ConfigValidator.require_color(errors, "激光射线颜色", laser_beam_color)
	ConfigValidator.require_number(errors, "激光射线宽度", laser_beam_width, 0.0, INF, false)
	ConfigValidator.require_number(errors, "激光射线发光强度", laser_beam_emission_energy, 0.0)
	ConfigValidator.require_number(errors, "激光传播速度", laser_propagation_speed, 0.0, INF, false)
	ConfigValidator.require_number(errors, "激光减速倍率", laser_slow_multiplier, 0.0, 1.0)
	ConfigValidator.require_number(errors, "激光减速持续时间", laser_slow_duration, 0.0)
	ConfigValidator.require_number(errors, "激光爆发间隔", laser_burst_interval, 0.0)
	ConfigValidator.require_number(errors, "激光爆发半径", laser_burst_radius, 0.0)
	ConfigValidator.require_number(errors, "激光冻结时间", laser_freeze_duration, 0.0)
	ConfigValidator.require_number(errors, "最大耐久", max_durability, 0.0, INF, false)
	ConfigValidator.require_number(errors, "脱战回血延迟", regeneration_delay, 0.0)
	ConfigValidator.require_number(errors, "每秒回血", regeneration_per_second, 0.0)
	ConfigValidator.require_number(errors, "反伤比例", damage_reflection_ratio, 0.0, 1.0)
	ConfigValidator.require_number(errors, "投射物速度", projectile_speed, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物长度", projectile_length, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物宽度", projectile_width, 0.0, INF, false)
	ConfigValidator.require_integer_range(errors, "投射物穿透次数", projectile_penetration_count, 0, 32)
	ConfigValidator.require_number(errors, "导弹爆炸半径", missile_explosion_radius, 0.0)
	ConfigValidator.require_number(errors, "导弹绕圈时长", missile_orbit_duration, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹绕圈横向半径", missile_orbit_radius_x, 0.0)
	ConfigValidator.require_number(errors, "导弹绕圈纵向半径", missile_orbit_radius_z, 0.0)
	ConfigValidator.require_number(errors, "导弹绕圈高度起伏", missile_orbit_vertical_amplitude, 0.0)
	ConfigValidator.require_number(errors, "导弹追踪转向速度", missile_homing_turn_speed_degrees, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹速度波动比例", missile_speed_variation_ratio, 0.0, 0.95)
	ConfigValidator.require_number(errors, "导弹速度波动频率", missile_speed_variation_frequency, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹视觉偏移", missile_visual_wobble, 0.0)
	ConfigValidator.require_number(errors, "导弹视觉滚转", missile_visual_roll_degrees, 0.0)
	ConfigValidator.require_number(errors, "导弹拖尾寿命", missile_trail_lifetime, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹拖尾宽度", missile_trail_width, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹目标标记尺寸", missile_target_marker_size, 0.0, INF, false)
	ConfigValidator.require_number(errors, "导弹爆炸表现时长", missile_explosion_duration, 0.0, INF, false)
	ConfigValidator.require_number(errors, "脉冲镭射宽度", pulse_laser_width, 0.0, INF, false)
	ConfigValidator.require_number(errors, "脉冲镭射发光强度", pulse_laser_emission_energy, 0.0)
	ConfigValidator.require_number(errors, "脉冲镭射渐入时间", pulse_laser_fade_in_time, 0.0)
	ConfigValidator.require_number(errors, "脉冲镭射保持时间", pulse_laser_hold_time, 0.0)
	ConfigValidator.require_number(errors, "脉冲镭射渐出时间", pulse_laser_fade_out_time, 0.0)
	ConfigValidator.require_integer_range(errors, "脉冲镭射最大反射次数", pulse_laser_reflect_max, 0, 64)
	ConfigValidator.require_color(errors, "建筑颜色", tower_color)
	ConfigValidator.require_color(errors, "攻击颜色", attack_color)
	var effective_model_asset := get_model_asset()
	if effective_model_asset != null:
		ConfigValidator.append_prefixed(errors, "建筑模型", effective_model_asset.validate_configuration())
	if projectile_model_asset != null:
		ConfigValidator.append_prefixed(errors, "建筑投射物模型", projectile_model_asset.validate_configuration())
	return errors
