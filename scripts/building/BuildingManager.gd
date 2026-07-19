## Building entry point for placement, preview, upgrades, occupancy, and rotation.
class_name BuildingManager
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Definitions")
@export var arrow_tower: BuildingDefinition
@export var laser_tower: BuildingDefinition
@export var barrier: BuildingDefinition

signal building_placed(building: Building)
signal building_removed(building: Building)
signal building_selected(building: Building)
signal building_upgraded(building: Building, previous_level: int, new_level: int)
signal building_destroyed(building: Building, attacker: Node)
signal placement_failed(cell: Vector3i, reason: String)
signal upgrade_failed(building: Building, reason: String)
signal preview_updated(building: Building)
signal preview_cleared

var _grid: GridManager
var _tile_manager: TileManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _buildings: Dictionary = {}
var _selected_building: Building
var _preview_building: Building
var _preview_definition: BuildingDefinition
var _preview_cell: Vector3i = Vector3i.ZERO
var _preview_facing_index: int = 0
var _path_cells: Dictionary = {}
var _protected_path_cells: Dictionary = {}
var _building_exit_callbacks: Dictionary = {}

func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	resource_manager: ResourceManager,
	combat_manager: CombatManager
) -> void:
	if _tile_manager != null and _tile_manager.level_loaded.is_connected(_on_level_loaded):
		_tile_manager.level_loaded.disconnect(_on_level_loaded)
	_grid = grid_manager
	_tile_manager = tile_manager
	_resource_manager = resource_manager
	_combat_manager = combat_manager
	arrow_tower = _reload_definition(arrow_tower)
	laser_tower = _reload_definition(laser_tower)
	barrier = _reload_definition(barrier)
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)

func place_building(
	cell: Vector3i,
	definition: BuildingDefinition,
	placement_facing: int = -1
) -> Building:
	var failure := _validate_placement(cell, definition)
	if not failure.is_empty():
		placement_failed.emit(cell, failure)
		return null
	var level_one_stats := definition.get_level_stats(1)
	var building := Building.new()
	add_child(building)
	building.configure(definition, cell, _grid, _tile_manager, _combat_manager)
	building.structure_destroyed.connect(_on_building_destroyed)
	var exit_callback := _on_building_tree_exited.bind(building)
	building.tree_exited.connect(exit_callback)
	_building_exit_callbacks[building] = exit_callback
	if placement_facing >= 0:
		building.set_facing_index(placement_facing)
	var occupied := _tile_manager.place_path_occupant(cell, building) if building.is_path_blocker() else _tile_manager.place_occupant(cell, building)
	if not occupied:
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(cell, "地块已被占用")
		return null
	if not _resource_manager.try_register_building(level_one_stats.cost):
		_tile_manager.clear_occupant(cell, building)
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(cell, "资源不足或达到建筑上限")
		return null
	_buildings[cell] = building
	_sync_building_income()
	select_building(building)
	building_placed.emit(building)
	return building

func upgrade_selected() -> bool:
	return upgrade_building(get_selected_building())

func upgrade_building(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		upgrade_failed.emit(building, "未选中建筑")
		return false
	if not building.can_upgrade():
		upgrade_failed.emit(building, "建筑已达到 3 级上限")
		return false
	var previous_level := building.level
	var upgrade_cost := building.get_upgrade_cost()
	if not _resource_manager.spend(upgrade_cost, "building_upgrade"):
		upgrade_failed.emit(building, "主资源不足")
		return false
	if not building.apply_level(previous_level + 1):
		_resource_manager.gain(upgrade_cost, "upgrade_rollback")
		upgrade_failed.emit(building, "等级参数无效")
		return false
	_sync_building_income()
	building_upgraded.emit(building, previous_level, building.level)
	return true

func remove_building(cell: Vector3i, refund: float = 0.0) -> bool:
	var building := get_building(cell)
	if building == null:
		return false
	return _release_building(building, refund, true, true)

func remove_selected_building() -> bool:
	var building := get_selected_building()
	if building == null:
		return false
	return remove_building(building.cell, building.get_refund_amount())

func clear_buildings(update_resource_count: bool = true) -> void:
	var cells := _buildings.keys()
	for raw_cell in cells:
		var cell: Vector3i = raw_cell
		var building := get_building(cell)
		if building == null:
			var stale_building: Variant = _buildings.get(cell)
			_buildings.erase(cell)
			_building_exit_callbacks.erase(stale_building)
			if _tile_manager != null:
				_tile_manager.clear_occupant(cell)
			if update_resource_count and _resource_manager != null:
				_resource_manager.unregister_building()
			continue
		_release_building(building, 0.0, update_resource_count, true, false)
	select_building(null)
	clear_preview()
	_sync_building_income()

func update_preview(cell: Vector3i, definition: BuildingDefinition) -> bool:
	if not _can_preview(cell, definition):
		clear_preview(false)
		return false
	if _preview_building != null and _preview_definition == definition and _preview_cell == cell:
		return true
	if _preview_definition != definition:
		_preview_facing_index = 0
	clear_preview(false)
	_preview_definition = definition
	_preview_cell = cell
	_preview_building = Building.new()
	add_child(_preview_building)
	_preview_building.configure(definition, cell, _grid, _tile_manager, _combat_manager, 1, true)
	_preview_building.set_facing_index(_preview_facing_index)
	preview_updated.emit(_preview_building)
	return true

func clear_preview(clear_definition: bool = true) -> void:
	var had_visible_preview := _preview_building != null and is_instance_valid(_preview_building)
	if _preview_building != null and is_instance_valid(_preview_building):
		_preview_building.queue_free()
	_preview_building = null
	if clear_definition:
		_preview_definition = null
	if had_visible_preview:
		preview_cleared.emit()

func rotate_preview(step: int = 1) -> bool:
	if _preview_building == null or not is_instance_valid(_preview_building):
		return false
	_preview_building.rotate_facing(step)
	_preview_facing_index = _preview_building.facing_index
	preview_updated.emit(_preview_building)
	return true

func get_preview_building() -> Building:
	return _preview_building if is_instance_valid(_preview_building) else null

func get_preview_facing_index() -> int:
	return _preview_facing_index

func get_building(cell: Vector3i) -> Building:
	if not _buildings.has(cell):
		return null
	var building: Building = _buildings[cell]
	return building if is_instance_valid(building) else null

func get_buildings() -> Array[Building]:
	var out: Array[Building] = []
	for raw_building in _buildings.values():
		var building: Building = raw_building
		if building != null and is_instance_valid(building):
			out.append(building)
	return out

func select_at(cell: Vector3i) -> Building:
	var building := get_building(cell)
	select_building(building)
	return building

func select_building(building: Building) -> void:
	_selected_building = building
	building_selected.emit(building)

func rotate_selected(step: int = 1) -> bool:
	var building := get_selected_building()
	if building == null:
		return false
	building.rotate_facing(step)
	return true

func get_selected_building() -> Building:
	return _selected_building if is_instance_valid(_selected_building) else null

func get_definition(kind: int) -> BuildingDefinition:
	if kind == BuildingDefinition.Kind.BARRIER:
		return barrier
	if kind == BuildingDefinition.Kind.LASER_TOWER:
		return laser_tower
	return arrow_tower

func get_path_blocker(cell: Vector3i) -> Node:
	var building := get_building(cell)
	if building == null or not building.is_path_blocker() or not building.is_structure_alive():
		return null
	return building

func is_path_cell(cell: Vector3i) -> bool:
	return _path_cells.has(cell)

func _validate_placement(cell: Vector3i, definition: BuildingDefinition) -> String:
	if not feature_enabled:
		return "建筑系统已关闭"
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		return "建筑系统依赖尚未注入"
	if definition == null or not definition.is_configured():
		return "建筑等级参数未配置"
	if not _grid.is_in_bounds(cell):
		return "目标格位于地图外"
	var cell_failure := _get_cell_placement_failure(cell, definition)
	if not cell_failure.is_empty():
		return cell_failure
	if not _resource_manager.can_add_building():
		return "已达到建筑上限"
	if not _resource_manager.can_afford(definition.get_level_stats(1).cost):
		return "主资源不足"
	return ""

func _can_preview(cell: Vector3i, definition: BuildingDefinition) -> bool:
	return feature_enabled and definition != null and definition.is_configured() and _grid != null and _grid.is_in_bounds(cell) and _tile_manager != null and _get_cell_placement_failure(cell, definition).is_empty()

func _get_cell_placement_failure(cell: Vector3i, definition: BuildingDefinition) -> String:
	if definition.kind == BuildingDefinition.Kind.BARRIER:
		if not _path_cells.has(cell):
			return "屏障只能放置在敌人路径上"
		if _protected_path_cells.has(cell):
			return "出生点和据点格不能放置屏障"
		if not _tile_manager.can_place_path_occupant(cell):
			return "路径格存在障碍或已被占用"
		if _is_enemy_on_cell(cell):
			return "敌人当前占据该路径格"
		return ""
	if _path_cells.has(cell):
		return "敌人路径只能放置屏障"
	if not _tile_manager.can_place(cell):
		return "目标地块不可建造或已被占用"
	return ""

func _is_enemy_on_cell(cell: Vector3i) -> bool:
	if _combat_manager == null or _grid == null:
		return false
	for target in _combat_manager.get_targets():
		if target != null and is_instance_valid(target) and _grid.world_to_cell(target.global_position) == cell:
			return true
	return false

func _sync_building_income() -> void:
	if _resource_manager == null:
		return
	var total: float = 0.0
	for building in get_buildings():
		total += building.get_resource_per_second()
	_resource_manager.set_building_resource_per_second(total)

func _reload_definition(definition: BuildingDefinition) -> BuildingDefinition:
	if definition == null or definition.resource_path.is_empty():
		return definition
	var resource: Resource = ResourceLoader.load(
		definition.resource_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	return resource if resource is BuildingDefinition else definition

func _on_level_loaded(level_resource: LevelResource) -> void:
	clear_buildings(true)
	_cache_path_cells(level_resource)

func _cache_path_cells(level_resource: LevelResource) -> void:
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

func _on_building_destroyed(building: Building, attacker: Node) -> void:
	if building == null or get_building(building.cell) != building:
		return
	building_destroyed.emit(building, attacker)
	remove_building(building.cell, 0.0)

func _on_building_tree_exited(building: Building) -> void:
	if building == null or not _buildings.has(building.cell) or _buildings[building.cell] != building:
		_building_exit_callbacks.erase(building)
		return
	_release_building(building, 0.0, true, false)

func _release_building(
	building: Building,
	refund: float,
	update_resource_count: bool,
	queue_for_deletion: bool,
	sync_income: bool = true
) -> bool:
	if building == null or not _buildings.has(building.cell) or _buildings[building.cell] != building:
		return false
	_buildings.erase(building.cell)
	if _tile_manager != null:
		_tile_manager.clear_occupant(building.cell, building)
	if update_resource_count and _resource_manager != null:
		_resource_manager.unregister_building(refund)
	if _selected_building == building:
		select_building(null)
	_disconnect_building_lifecycle(building)
	if is_instance_valid(building):
		building.shutdown()
	building_removed.emit(building)
	if queue_for_deletion and is_instance_valid(building):
		building.queue_free()
	if sync_income:
		_sync_building_income()
	return true

func _disconnect_building_lifecycle(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		_building_exit_callbacks.erase(building)
		return
	if building.structure_destroyed.is_connected(_on_building_destroyed):
		building.structure_destroyed.disconnect(_on_building_destroyed)
	if _building_exit_callbacks.has(building):
		var exit_callback: Callable = _building_exit_callbacks[building]
		if building.tree_exited.is_connected(exit_callback):
			building.tree_exited.disconnect(exit_callback)
	_building_exit_callbacks.erase(building)
