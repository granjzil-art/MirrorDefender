## Building module entry point for placement, occupancy, selection, and rotation.
class_name BuildingManager
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Definitions")
@export var arrow_tower: BuildingDefinition
@export var laser_tower: BuildingDefinition

signal building_placed(building: Building)
signal building_removed(building: Building)
signal building_selected(building: Building)
signal placement_failed(cell: Vector3i, reason: String)

var _grid: GridManager
var _tile_manager: TileManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _buildings: Dictionary = {}
var _selected_building: Building
var _producer_count: int = 0

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
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)

func place_building(cell: Vector3i, definition: BuildingDefinition) -> Building:
	var failure := _validate_placement(cell, definition)
	if not failure.is_empty():
		placement_failed.emit(cell, failure)
		return null
	var building := Building.new()
	add_child(building)
	building.configure(definition, cell, _grid, _tile_manager, _combat_manager)
	if not _tile_manager.place_occupant(cell, building):
		building.queue_free()
		placement_failed.emit(cell, "地块已被占用")
		return null
	if not _resource_manager.try_register_building(definition.cost):
		_tile_manager.clear_occupant(cell, building)
		building.queue_free()
		placement_failed.emit(cell, "资源不足或达到建筑上限")
		return null
	_buildings[cell] = building
	if definition.produces_resource:
		_producer_count += 1
		_resource_manager.set_producer_count(_producer_count)
	select_building(building)
	building_placed.emit(building)
	return building

func remove_building(cell: Vector3i, refund: float = 0.0) -> bool:
	var building := get_building(cell)
	if building == null:
		return false
	_buildings.erase(cell)
	_tile_manager.clear_occupant(cell, building)
	if building.definition.produces_resource:
		_producer_count = maxi(0, _producer_count - 1)
		_resource_manager.set_producer_count(_producer_count)
	_resource_manager.unregister_building(refund)
	if _selected_building == building:
		_selected_building = null
	building.shutdown()
	building_removed.emit(building)
	building.queue_free()
	return true

func clear_buildings(update_resource_count: bool = true) -> void:
	var cells := _buildings.keys()
	for raw_cell in cells:
		var cell: Vector3i = raw_cell
		var building := get_building(cell)
		if building == null:
			continue
		_buildings.erase(cell)
		_tile_manager.clear_occupant(cell, building)
		if update_resource_count:
			_resource_manager.unregister_building()
		building.shutdown()
		building_removed.emit(building)
		building.queue_free()
	_selected_building = null
	_producer_count = 0
	if _resource_manager != null:
		_resource_manager.set_producer_count(0)

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
	if _selected_building == null or not is_instance_valid(_selected_building):
		return false
	_selected_building.rotate_facing(step)
	return true

func get_selected_building() -> Building:
	return _selected_building

func get_definition(kind: int) -> BuildingDefinition:
	if kind == BuildingDefinition.Kind.LASER_TOWER:
		return laser_tower
	return arrow_tower

func _validate_placement(cell: Vector3i, definition: BuildingDefinition) -> String:
	if not feature_enabled:
		return "建筑系统已关闭"
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		return "建筑系统依赖尚未注入"
	if definition == null:
		return "未配置建筑定义"
	if not _grid.is_in_bounds(cell):
		return "目标格位于地图外"
	if not _tile_manager.can_place(cell):
		return "目标地块不可建造或已被占用"
	if not _resource_manager.can_add_building():
		return "已达到建筑上限"
	if not _resource_manager.can_afford(definition.cost):
		return "主资源不足"
	return ""

func _on_level_loaded(_level_resource: LevelResource) -> void:
	clear_buildings(true)
