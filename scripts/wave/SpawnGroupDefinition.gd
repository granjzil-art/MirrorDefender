@tool
## One timed enemy stream inside a wave. All references are owned by LevelResource.
class_name SpawnGroupDefinition
extends Resource

@export_group("Spawn")
@export var enemy: EnemyDefinition
@export_range(1, 10000, 1, "or_greater") var count: int = 5
@export_range(0.01, 1000.0, 0.01, "or_greater") var interval: float = 0.8
@export_range(0.0, 10000.0, 0.1, "or_greater") var start_delay: float = 0.0

@export_group("Route")
@export var spawn_point: SpawnPointDefinition
@export var path: PathDefinition
