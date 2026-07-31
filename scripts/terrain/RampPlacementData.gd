@tool
## RampPlacementData -- one 1:N ramp footprint in the terrain Grid.
##
## anchor_cell is the lowest ramp cell and facing_index points uphill. The
## footprint occupies run_length consecutive cells and rises exactly one layer.
class_name RampPlacementData
extends Resource

const MIN_RUN_LENGTH: int = 1
const MAX_RUN_LENGTH: int = 4
const MIN_BASE_LAYER: int = 1
const MAX_BASE_LAYER: int = 3

@export_group("Identity")
@export var ramp_id: StringName = &"ramp_1"

@export_group("Footprint")
@export var anchor_cell: Vector3i = Vector3i.ZERO
@export_range(0, 5, 1) var facing_index: int = 0
@export_range(1, 4, 1) var run_length: int = MIN_RUN_LENGTH
@export_range(1, 3, 1) var base_layer: int = MIN_BASE_LAYER


func get_footprint_cells(shape: IGridShape) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if shape == null or facing_index < 0 or facing_index >= shape.edge_count():
		return cells
	var current := anchor_cell
	for _step in range(run_length):
		cells.append(current)
		current = shape.neighbor_across_edge(current, facing_index)
	return cells


func get_low_neighbor(shape: IGridShape) -> Vector3i:
	if shape == null or facing_index < 0 or facing_index >= shape.edge_count():
		return anchor_cell
	var opposite_index := (facing_index + floori(float(shape.edge_count()) / 2.0)) % shape.edge_count()
	return shape.neighbor_across_edge(anchor_cell, opposite_index)


func get_high_neighbor(shape: IGridShape) -> Vector3i:
	if shape == null or facing_index < 0 or facing_index >= shape.edge_count():
		return anchor_cell
	var current := anchor_cell
	for _step in range(run_length):
		current = shape.neighbor_across_edge(current, facing_index)
	return current


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if ramp_id.is_empty():
		errors.append("斜坡 ID 不能为空")
	if run_length < MIN_RUN_LENGTH or run_length > MAX_RUN_LENGTH:
		errors.append("斜坡坡度长度必须位于 1 到 4 之间")
	if base_layer < MIN_BASE_LAYER or base_layer > MAX_BASE_LAYER:
		errors.append("斜坡基础层必须位于 1 到 3 之间")
	if facing_index < 0:
		errors.append("斜坡方向不能为负数")
	return errors
