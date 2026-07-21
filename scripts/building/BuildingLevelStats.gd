## Complete editable parameters for one building level, capped at three levels in M3.
class_name BuildingLevelStats
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Economy")
## Level 1 uses this as construction cost; later levels use it as upgrade cost.
@export_range(0.0, 100000.0, 1.0, "or_greater") var cost: float = 75.0
## Exact resource refunded when a building at this level is removed.
@export_range(0.0, 100000.0, 1.0, "or_greater") var refund_amount: float = 38.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var resource_per_second: float = 0.0

@export_group("Combat")
@export var affects_airborne: bool = true
@export_range(0.0, 100000.0, 0.1, "or_greater") var base_damage: float = 20.0
@export_range(0.1, 100.0, 0.1, "or_greater") var targeting_range: float = 5.0
@export_range(0.1, 100.0, 0.1, "or_greater") var attack_range: float = 4.0
@export_range(0.01, 100.0, 0.01, "or_greater") var attacks_per_second: float = 1.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var laser_dps: float = 0.0
@export_range(0.0, 100.0, 0.05, "or_greater") var level_factor: float = 1.0
@export_range(0.0, 100.0, 0.05, "or_greater") var extra_factor: float = 1.0
@export_enum("最近", "最远", "最高血", "最低血", "最快", "首个进入", "锁定") var target_priority: int = 0

@export_group("Defense")
@export_range(1.0, 1000000.0, 1.0, "or_greater") var max_durability: float = 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var regeneration_delay: float = 3.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var regeneration_per_second: float = 0.0
@export_range(0.0, 1.0, 0.01) var damage_reflection_ratio: float = 0.0

@export_group("Projectile")
@export_range(0.1, 100.0, 0.1, "or_greater") var projectile_speed: float = 7.0
@export_range(0.1, 5.0, 0.05, "or_greater") var projectile_length: float = 0.32
@export_range(0.02, 2.0, 0.01, "or_greater") var projectile_width: float = 0.07

@export_group("Presentation")
@export var visual_scene: PackedScene
@export var tower_color: Color = Color(0.90, 0.52, 0.16, 1.0)
@export var attack_color: Color = Color(1.0, 0.82, 0.28, 1.0)


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_number(errors, "造价", cost, 0.0)
	ConfigValidator.require_number(errors, "退款", refund_amount, 0.0)
	ConfigValidator.require_number(errors, "每秒资源产出", resource_per_second, 0.0)
	ConfigValidator.require_number(errors, "基础伤害", base_damage, 0.0)
	ConfigValidator.require_number(errors, "索敌范围", targeting_range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "攻击射程", attack_range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "每秒攻击次数", attacks_per_second, 0.0, INF, false)
	ConfigValidator.require_number(errors, "激光每秒伤害", laser_dps, 0.0)
	ConfigValidator.require_number(errors, "等级因子", level_factor, 0.0)
	ConfigValidator.require_number(errors, "额外因子", extra_factor, 0.0)
	ConfigValidator.require_integer_range(errors, "索敌优先级", target_priority, 0, 6)
	ConfigValidator.require_number(errors, "最大耐久", max_durability, 0.0, INF, false)
	ConfigValidator.require_number(errors, "脱战回血延迟", regeneration_delay, 0.0)
	ConfigValidator.require_number(errors, "每秒回血", regeneration_per_second, 0.0)
	ConfigValidator.require_number(errors, "反伤比例", damage_reflection_ratio, 0.0, 1.0)
	ConfigValidator.require_number(errors, "投射物速度", projectile_speed, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物长度", projectile_length, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物宽度", projectile_width, 0.0, INF, false)
	ConfigValidator.require_color(errors, "建筑颜色", tower_color)
	ConfigValidator.require_color(errors, "攻击颜色", attack_color)
	return errors
