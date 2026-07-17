@tool
## Ordered, designer-authored cells from spawn to base.
class_name PathDefinition
extends Resource

@export_group("Identity")
@export var path_id: StringName = &"main"
@export var display_name: String = "主路径"

@export_group("Route")
@export var cells: Array[Vector3i] = []

func has_minimum_cells() -> bool:
	return cells.size() >= 2

func get_start_cell() -> Vector3i:
	return cells.front() if not cells.is_empty() else Vector3i.ZERO

func get_end_cell() -> Vector3i:
	return cells.back() if not cells.is_empty() else Vector3i.ZERO
