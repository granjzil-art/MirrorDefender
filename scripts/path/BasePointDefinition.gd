@tool
## One target base location. Multiple locations share BaseCore health at runtime.
class_name BasePointDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

enum FootprintMode {
	LEGACY_SINGLE_CELL,
	RECTANGLE_3_X_2,
}

const SQUARE_EDGE_COUNT: int = 4
const FOOTPRINT_WIDTH: int = 3
const FOOTPRINT_DEPTH: int = 2
const SQUARE_DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, -1, 0),
]

@export_group("Identity")
@export var base_id: StringName = &"base_1"
@export var display_name: String = "据点 1"
## Zero means derive a stable display number from LevelResource serialization order.
@export_range(0, 999, 1) var display_number: int = 0

@export_group("Location")
## Front-row center cell. RECTANGLE_3_X_2 extends one row opposite facing.
@export var cell: Vector3i = Vector3i.ZERO
@export_enum("旧版单格", "3×2据点") var footprint_mode: int = FootprintMode.LEGACY_SINGLE_CELL
@export_range(0, 3, 1) var facing_index: int = 0

@export_group("Presentation")
@export var model_asset: ModelAssetDefinition


func get_model_asset() -> ModelAssetDefinition:
	return model_asset


func uses_multi_cell_footprint() -> bool:
	return footprint_mode == FootprintMode.RECTANGLE_3_X_2


## Returns the six SQUARE cells in front-row-first serialization order.
## Legacy/retired resources remain one cell until explicitly migrated.
func get_footprint_cells() -> Array[Vector3i]:
	if not uses_multi_cell_footprint():
		return [cell]
	var forward := get_facing_cell_direction()
	var lateral := Vector3i(-forward.y, forward.x, 0)
	var result: Array[Vector3i] = []
	for depth_index in range(FOOTPRINT_DEPTH):
		var row_center := cell - forward * depth_index
		for width_offset in range(-1, 2):
			result.append(row_center + lateral * width_offset)
	return result


func contains_cell(candidate: Vector3i) -> bool:
	return get_footprint_cells().has(candidate)


func get_facing_cell_direction() -> Vector3i:
	return SQUARE_DIRECTIONS[posmod(facing_index, SQUARE_EDGE_COUNT)]


func get_footprint_center_world(grid: GridManager) -> Vector3:
	if grid == null:
		return Vector3.ZERO
	var cells := get_footprint_cells()
	if cells.is_empty():
		return grid.cell_to_world(cell)
	var sum := Vector3.ZERO
	for footprint_cell in cells:
		sum += grid.cell_to_world(footprint_cell)
	return sum / float(cells.size())


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if footprint_mode < FootprintMode.LEGACY_SINGLE_CELL or footprint_mode > FootprintMode.RECTANGLE_3_X_2:
		errors.append("据点占地模式无效")
	if facing_index < 0 or facing_index >= SQUARE_EDGE_COUNT:
		errors.append("据点朝向必须位于0到3之间")
	if model_asset != null:
		ConfigValidator.append_prefixed(errors, "据点模型", model_asset.validate_configuration())
	return errors


func get_marker_label(resolved_number: int) -> String:
	return "据点 %d" % maxi(1, resolved_number)
