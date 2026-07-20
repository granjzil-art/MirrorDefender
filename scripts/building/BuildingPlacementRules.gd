## Placement-policy service shared by runtime placement and previews.
## It owns level-derived path/protected caches but never owns Building nodes.
class_name BuildingPlacementRules
extends RefCounted

var _grid: GridManager
var _tile_manager: TileManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _path_cells: Dictionary = {}
var _protected_path_cells: Dictionary = {}

func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	resource_manager: ResourceManager,
	combat_manager: CombatManager
) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_resource_manager = resource_manager
	_combat_manager = combat_manager

func rebuild_level_cache(level_resource: LevelResource) -> void:
	_path_cells.clear()
	_protected_path_cells.clear()
	if level_resource == null:
		return
	_protected_path_cells[level_resource.base_cell] = true
	for spawn_point in level_resource.spawn_points:
		if spawn_point != null:
			_protected_path_cells[spawn_point.cell] = true
	for path in level_resource.paths:
		if path == null:
			continue
		for cell in path.cells:
			_path_cells[cell] = true

func is_path_cell(cell: Vector3i) -> bool:
	return _path_cells.has(cell)

func validate_tile(
	cell: Vector3i,
	definition: BuildingDefinition,
	check_economy: bool = true
) -> String:
	var common_failure := _validate_common(definition, check_economy)
	if not common_failure.is_empty():
		return common_failure
	if not _grid.is_in_bounds(cell):
		return "目标格位于地图外"
	if definition.is_edge_building():
		return "边类建筑必须选择路径边放置"
	if definition.is_path_tile_building():
		if not _path_cells.has(cell):
			return "屏障只能放置在敌人路径上"
		if _protected_path_cells.has(cell):
			return "出生点和据点格不能放置屏障"
		if not _tile_manager.can_place_path_occupant(cell):
			return "路径格存在障碍或已被占用"
		if _is_enemy_on_cell(cell):
			return "敌人当前占据该路径格"
		return _validate_economy(definition) if check_economy else ""
	if _path_cells.has(cell):
		return "敌人路径只能放置屏障"
	if not _tile_manager.can_place(cell):
		return "目标地块不可建造或已被占用"
	return _validate_economy(definition) if check_economy else ""

## Returns {failure: String, to_cell: Vector3i, edge_id: String}.
func validate_edge(
	from_cell: Vector3i,
	placement_edge_index: int,
	definition: BuildingDefinition,
	edge_building_resolver: Callable,
	check_economy: bool = true
) -> Dictionary:
	var result := {
		"failure": "",
		"to_cell": Vector3i.ZERO,
		"edge_id": "",
	}
	var common_failure := _validate_common(definition, check_economy)
	if not common_failure.is_empty():
		result["failure"] = common_failure
		return result
	if not definition.is_edge_building():
		result["failure"] = "该建筑不是边类建筑"
		return result
	if not _grid.is_in_bounds(from_cell) or placement_edge_index < 0 or placement_edge_index >= _grid.edge_count():
		result["failure"] = "目标边位于地图外"
		return result
	var to_cell := _grid.neighbor_across_edge(from_cell, placement_edge_index)
	result["to_cell"] = to_cell
	if not _grid.is_in_bounds(to_cell):
		result["failure"] = "边屏障只能放在两个有效地块之间"
		return result
	if not _tile_manager.allows_edge_building(from_cell) or not _tile_manager.allows_edge_building(to_cell):
		result["failure"] = "该边两侧的地块未同时允许边建筑"
		return result
	var canonical_id := _grid.canonical_edge_id(from_cell, placement_edge_index)
	result["edge_id"] = canonical_id
	var occupied: Variant = edge_building_resolver.call(canonical_id) if edge_building_resolver.is_valid() else null
	if occupied != null:
		result["failure"] = "该物理边已被占用"
		return result
	if _is_enemy_on_edge(from_cell, to_cell):
		result["failure"] = "敌人当前占据该边的相邻格"
		return result
	if check_economy:
		result["failure"] = _validate_economy(definition)
	return result

func _validate_common(definition: BuildingDefinition, _check_economy: bool) -> String:
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		return "建筑系统依赖尚未注入"
	if definition == null or not definition.is_configured():
		return "建筑等级参数未配置"
	return ""

func _validate_economy(definition: BuildingDefinition) -> String:
	if not _resource_manager.can_add_building():
		return "已达到建筑上限"
	if not _resource_manager.can_afford(definition.get_level_stats(1).cost):
		return "主资源不足"
	return ""

func _is_enemy_on_cell(cell: Vector3i) -> bool:
	for target in _combat_manager.get_targets():
		if target != null and is_instance_valid(target) and _grid.world_to_cell(target.global_position) == cell:
			return true
	return false

func _is_enemy_on_edge(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	for target in _combat_manager.get_targets():
		if target == null or not is_instance_valid(target):
			continue
		var enemy_cell := _grid.world_to_cell(target.global_position)
		if enemy_cell == from_cell or enemy_cell == to_cell:
			return true
	return false
