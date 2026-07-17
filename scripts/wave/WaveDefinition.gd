@tool
## A fixed wave containing concurrently scheduled spawn groups.
class_name WaveDefinition
extends Resource

@export_group("Identity")
@export var display_name: String = "第 1 波"

@export_group("Groups")
@export var spawn_groups: Array[SpawnGroupDefinition] = []
