## Data-only definition for one constructible M3 building type.
class_name BuildingDefinition
extends Resource

enum Kind {
	ARROW_TOWER,
	LASER_TOWER,
}

@export_group("Identity")
@export var kind: Kind = Kind.ARROW_TOWER
@export var display_name: String = "箭塔"

@export_group("Construction")
@export_range(0.0, 100000.0, 1.0, "or_greater") var cost: float = 75.0
@export var produces_resource: bool = false

@export_group("Combat")
@export_range(0.0, 100000.0, 0.1, "or_greater") var base_damage: float = 20.0
@export_range(0.1, 100.0, 0.1, "or_greater") var attack_range: float = 4.0
@export_range(0.01, 100.0, 0.01, "or_greater") var attacks_per_second: float = 1.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var laser_dps: float = 30.0
@export_range(0.0, 100.0, 0.05, "or_greater") var level_factor: float = 1.0
@export_range(0.0, 100.0, 0.05, "or_greater") var extra_factor: float = 1.0
@export_enum("最近", "最远", "最高血", "最低血", "最快", "首个进入", "锁定") var target_priority: int = 0

@export_group("Presentation")
@export var tower_color: Color = Color(0.90, 0.52, 0.16, 1.0)
@export var attack_color: Color = Color(1.0, 0.82, 0.28, 1.0)
