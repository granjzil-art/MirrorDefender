## Complete editable parameters for one building level, capped at three levels in M3.
class_name BuildingLevelStats
extends Resource

@export_group("Economy")
## Level 1 uses this as construction cost; later levels use it as upgrade cost.
@export_range(0.0, 100000.0, 1.0, "or_greater") var cost: float = 75.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var resource_per_second: float = 0.0

@export_group("Combat")
@export_range(0.0, 100000.0, 0.1, "or_greater") var base_damage: float = 20.0
@export_range(0.1, 100.0, 0.1, "or_greater") var targeting_range: float = 5.0
@export_range(0.1, 100.0, 0.1, "or_greater") var attack_range: float = 4.0
@export_range(0.01, 100.0, 0.01, "or_greater") var attacks_per_second: float = 1.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var laser_dps: float = 0.0
@export_range(0.0, 100.0, 0.05, "or_greater") var level_factor: float = 1.0
@export_range(0.0, 100.0, 0.05, "or_greater") var extra_factor: float = 1.0
@export_enum("最近", "最远", "最高血", "最低血", "最快", "首个进入", "锁定") var target_priority: int = 0

@export_group("Projectile")
@export_range(0.1, 100.0, 0.1, "or_greater") var projectile_speed: float = 7.0
@export_range(0.1, 5.0, 0.05, "or_greater") var projectile_length: float = 0.32
@export_range(0.02, 2.0, 0.01, "or_greater") var projectile_width: float = 0.07

@export_group("Presentation")
@export var visual_scene: PackedScene
@export var tower_color: Color = Color(0.90, 0.52, 0.16, 1.0)
@export var attack_color: Color = Color(1.0, 0.82, 0.28, 1.0)
