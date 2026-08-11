## Shared validation boundary for runtime Stuff preview and commit.
## Returns stable dictionaries: {valid, warning, reason, placement_id}.
class_name StuffPlacementValidator
extends RefCounted

const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const StuffRuntimeScript := preload("res://scripts/stuff/StuffRuntime.gd")

var _grid: GridManager
var _tile_manager: TileManager
var _terrain_manager: Node
var _stuff_manager: StuffManager
var _edge_occupancy_registry: EdgeOccupancyRegistry
var _path_connectivity_validator: Callable


func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	terrain_manager: Node,
	stuff_manager: StuffManager,
	edge_occupancy_registry: EdgeOccupancyRegistry = null,
	path_connectivity_validator: Callable = Callable()
) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_terrain_manager = terrain_manager
	_stuff_manager = stuff_manager
	_edge_occupancy_registry = edge_occupancy_registry
	_path_connectivity_validator = path_connectivity_validator


func validate_placement(
	cell: Vector3i,
	definition: StuffDefinition,
	facing_index: int = 0,
	placement_id: StringName = &""
) -> Dictionary:
	if _grid == null or _tile_manager == null or _stuff_manager == null:
		return _invalid("关卡元素编辑依赖尚未连接")
	if not _stuff_manager.feature_enabled:
		return _invalid("关卡元素系统已关闭")
	if definition == null:
		return _invalid("未选择关卡元素")
	if not definition.validate_configuration().is_empty():
		return _invalid("关卡元素配置无效")
	if not _grid.is_in_bounds(cell):
		return _invalid("目标格位于地图外")
	var facing_count := maxi(1, _grid.get_tile_content_facing_count())
	if facing_index < 0 or facing_index >= facing_count:
		return _invalid("关卡元素朝向超出当前网格方向数")
	var occupant := _tile_manager.get_occupant(cell)
	if occupant is BaseCore:
		return _invalid("据点占地不允许放置关卡元素")
	if not placement_id.is_empty() and _stuff_manager.get_stuff(placement_id) != null:
		return _invalid("关卡元素实例 ID 已存在：%s" % placement_id)
	for existing in _stuff_manager.get_stuff_at(cell):
		if not definition.can_coexist_with(existing.definition):
			return _invalid("该格已有与其互斥的关卡元素")
	if definition.blocks_tile_building and occupant != null:
		return _invalid("该格已有块建筑，不能放置会阻止块建筑的元素")
	if definition.blocks_edge_building and _has_edge_occupant(cell):
		return _invalid("该格边上已有建筑或镜子，不能放置会阻止边建筑的元素")
	var warning := _get_connectivity_warning(cell, definition, facing_index, placement_id)
	return {
		"valid": true,
		"warning": not warning.is_empty(),
		"reason": warning,
		"placement_id": placement_id,
	}


func _has_edge_occupant(cell: Vector3i) -> bool:
	if _edge_occupancy_registry == null:
		return false
	for edge_index in range(_grid.edge_count()):
		if _edge_occupancy_registry.is_occupied(_grid.canonical_edge_id(cell, edge_index)):
			return true
	return false


func _get_connectivity_warning(
	cell: Vector3i,
	definition: StuffDefinition,
	facing_index: int,
	placement_id: StringName
) -> String:
	if not _path_connectivity_validator.is_valid() or not definition.blocks_enemy_navigation():
		return ""
	var placement := StuffPlacementDataScript.new()
	placement.configure(
		placement_id if not placement_id.is_empty() else &"__stuff_preview__",
		cell,
		definition,
		facing_index
	)
	var candidate: StuffRuntime = StuffRuntimeScript.new()
	var height_resolver := Callable()
	if _terrain_manager != null and _terrain_manager.has_method("get_world_height"):
		height_resolver = Callable(_terrain_manager, "get_world_height")
	if not candidate.configure(placement, _grid, height_resolver):
		candidate.free()
		return "关卡元素阻路预检失败"
	var result: Variant = _path_connectivity_validator.call({"extra_tile_blocker": candidate})
	candidate.free()
	return str(result) if result is String else ""


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "warning": false, "reason": reason, "placement_id": &""}
