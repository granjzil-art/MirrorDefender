@tool
## A fixed wave containing concurrently scheduled spawn groups.
class_name WaveDefinition
extends Resource

@export_group("Identity")
@export var display_name: String = "第 1 波"

@export_group("Groups")
@export var spawn_groups: Array[SpawnGroupDefinition] = []

@export_group("Economy")
## Multiplies each enemy's authored reward. WaveManager snapshots this value at spawn.
@export_range(0.0, 10.0, 0.05, "or_greater") var enemy_drop_multiplier: float = 1.0
## Granted once after every pending group and living enemy from this wave is cleared.
@export_range(0.0, 100000.0, 1.0, "or_greater") var completion_reward: float = 40.0
