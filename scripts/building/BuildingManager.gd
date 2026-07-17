## Building entry point for placement, preview, upgrades, occupancy, and rotation.
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
signal building_upgraded(building: Building, previous_level: int, new_level: int)
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
	if placement_facing >= 0:
		building.set_facing_index(placement_facing)
	if not _tile_manager.place_occupant(cell, building):
		building.queue_free()
		placement_failed.emit(cell, "地块已被占用")
		return null
	if not _resource_manager.try_register_building(level_one_stats.cost):
		_tile_manager.clear_occupant(cell, building)
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
	_buildings.erase(cell)
	_tile_manager.clear_occupant(cell, building)
	_resource_manager.unregister_building(refund)
	if _selected_building == building:
		select_building(null)
	building.shutdown()
	building_removed.emit(building)
	building.queue_free()
	_sync_building_income()
	return true

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
		_buildings.erase(cell)
		if building == null:
			continue
		_tile_manager.clear_occupant(cell, building)
		if update_resource_count:
			_resource_manager.unregister_building()
		building.shutdown()
		building_removed.emit(building)
		building.queue_free()
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
	if kind == BuildingDefinition.Kind.LASER_TOWER:
		return laser_tower
	return arrow_tower

func _validate_placement(cell: Vector3i, definition: BuildingDefinition) -> String:
	if not feature_enabled:
		return "建筑系统已关闭"
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		return "建筑系统依赖尚未注入"
	if definition == null or not definition.is_configured():
		return "建筑等级参数未配置"
	if not _grid.is_in_bounds(cell):
		return "目标格位于地图外"
	if not _tile_manager.can_place(cell):
		return "目标地块不可建造或已被占用"
	if not _resource_manager.can_add_building():
		return "已达到建筑上限"
	if not _resource_manager.can_afford(definition.get_level_stats(1).cost):
		return "主资源不足"
	return ""

func _can_preview(cell: Vector3i, definition: BuildingDefinition) -> bool:
	return feature_enabled and definition != null and definition.is_configured() and _grid != null and _grid.is_in_bounds(cell) and _tile_manager != null and _tile_manager.can_place(cell)

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

func _on_level_loaded(_level_resource: LevelResource) -> void:
	clear_buildings(true)
