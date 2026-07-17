@tool
## Editable stats and greybox presentation for one M4 enemy type.
class_name EnemyDefinition
extends Resource

@export_group("Identity")
@export var enemy_id: StringName = &"grunt"
@export var display_name: String = "步兵"

@export_group("Stats")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.1, 100.0, 0.1, "or_greater") var move_speed: float = 1.5
@export_range(0.0, 100000.0, 0.1, "or_greater") var armor: float = 0.0
@export_range(1.0, 100000.0, 1.0, "or_greater") var base_damage: float = 10.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var reward: float = 5.0
@export_range(0.05, 5.0, 0.05, "or_greater") var hit_radius: float = 0.28

@export_group("Presentation")
@export var visual_scene: PackedScene
@export var body_color: Color = Color(0.84, 0.20, 0.24, 1.0)
@export_range(0.1, 3.0, 0.05, "or_greater") var body_height: float = 0.8
