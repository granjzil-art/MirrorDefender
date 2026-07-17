@tool
## A reusable spawn location for one or more wave groups.
class_name SpawnPointDefinition
extends Resource

@export_group("Identity")
@export var spawn_id: StringName = &"north"
@export var display_name: String = "北侧入口"

@export_group("Location")
@export var cell: Vector3i = Vector3i.ZERO
