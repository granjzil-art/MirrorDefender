@tool
## GridCellData -- canonical serialized data for one terrain column.
##
## Paths are derived from LevelResource.paths. Stuff and buildings are stored
## separately and only contribute runtime restrictions on top of these fields.
class_name GridCellData
extends Resource

const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")

const MIN_LAYER_COUNT: int = 1
const MAX_LAYER_COUNT: int = 4

@export_group("Identity")
@export var cell: Vector3i = Vector3i.ZERO

@export_group("Terrain")
@export var terrain: TerrainDefinitionScript
@export_range(1, 4, 1) var layer_count: int = MIN_LAYER_COUNT

@export_group("Base Placement Permissions")
@export var allows_tile_building: bool = true
@export var allows_edge_building: bool = true

## Runtime-only building occupancy. Stuff occupancy belongs to StuffManager.
var occupant: Node = null


func configure(
	p_cell: Vector3i,
	p_terrain: TerrainDefinitionScript,
	p_layer_count: int,
	p_allows_tile_building: bool = true,
	p_allows_edge_building: bool = true
) -> void:
	cell = p_cell
	terrain = p_terrain
	layer_count = clampi(p_layer_count, MIN_LAYER_COUNT, MAX_LAYER_COUNT)
	allows_tile_building = p_allows_tile_building
	allows_edge_building = p_allows_edge_building
	emit_changed()


func get_effective_terrain(fallback: TerrainDefinitionScript = null) -> TerrainDefinitionScript:
	return terrain if terrain != null else fallback


func get_surface_height(layer_height: float) -> float:
	return float(layer_count - 1) * layer_height


func can_place_base() -> bool:
	return allows_tile_building and occupant == null


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if layer_count < MIN_LAYER_COUNT or layer_count > MAX_LAYER_COUNT:
		errors.append("地块层数必须位于 1 到 4 之间")
	return errors
