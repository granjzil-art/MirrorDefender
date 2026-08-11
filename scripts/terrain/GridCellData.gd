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
const SQUARE_EDGE_COUNT: int = 4
const ALL_SQUARE_EDGES_MASK: int = (1 << SQUARE_EDGE_COUNT) - 1

@export_group("Identity")
@export var cell: Vector3i = Vector3i.ZERO

@export_group("Terrain")
@export var terrain: TerrainDefinitionScript
@export_range(1, 4, 1) var layer_count: int = MIN_LAYER_COUNT

@export_group("Base Placement Permissions")
@export var allows_tile_building: bool = true
## Legacy cell-wide gate. New authoring uses edge_building_mask per edge.
@export var allows_edge_building: bool = true
@export_flags("右", "上", "左", "下") var edge_building_mask: int = ALL_SQUARE_EDGES_MASK

## Runtime-only building occupancy. Stuff occupancy belongs to StuffManager.
var occupant: Node = null


func configure(
	p_cell: Vector3i,
	p_terrain: TerrainDefinitionScript,
	p_layer_count: int,
	p_allows_tile_building: bool = true,
	p_allows_edge_building: bool = true,
	p_edge_building_mask: int = ALL_SQUARE_EDGES_MASK
) -> void:
	cell = p_cell
	terrain = p_terrain
	layer_count = clampi(p_layer_count, MIN_LAYER_COUNT, MAX_LAYER_COUNT)
	allows_tile_building = p_allows_tile_building
	allows_edge_building = p_allows_edge_building
	edge_building_mask = p_edge_building_mask & ALL_SQUARE_EDGES_MASK
	emit_changed()


func get_effective_terrain(fallback: TerrainDefinitionScript = null) -> TerrainDefinitionScript:
	return terrain if terrain != null else fallback


func get_surface_height(layer_height: float) -> float:
	return float(layer_count - 1) * layer_height


func can_place_base() -> bool:
	return allows_tile_building and occupant == null


func allows_edge(edge_index: int) -> bool:
	if not allows_edge_building or edge_index < 0 or edge_index >= SQUARE_EDGE_COUNT:
		return false
	return (edge_building_mask & (1 << edge_index)) != 0


func set_edge_allowed(edge_index: int, allowed: bool) -> bool:
	if edge_index < 0 or edge_index >= SQUARE_EDGE_COUNT:
		return false
	var previous := edge_building_mask
	if allowed:
		edge_building_mask |= 1 << edge_index
	else:
		edge_building_mask &= ~(1 << edge_index)
	if edge_building_mask == previous:
		return false
	allows_edge_building = true
	emit_changed()
	return true


func set_all_edges_allowed(allowed: bool) -> bool:
	var next_mask := ALL_SQUARE_EDGES_MASK if allowed else 0
	if allows_edge_building and edge_building_mask == next_mask:
		return false
	allows_edge_building = true
	edge_building_mask = next_mask
	emit_changed()
	return true


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if layer_count < MIN_LAYER_COUNT or layer_count > MAX_LAYER_COUNT:
		errors.append("地块层数必须位于 1 到 4 之间")
	if edge_building_mask < 0 or edge_building_mask > ALL_SQUARE_EDGES_MASK:
		errors.append("地块边建筑权限掩码无效")
	return errors
