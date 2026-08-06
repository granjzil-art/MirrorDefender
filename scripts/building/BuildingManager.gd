## Building entry point for placement, preview, upgrades, occupancy, and rotation.
class_name BuildingManager
extends Node3D

const BuildingPlacementRulesScript := preload("res://scripts/building/BuildingPlacementRules.gd")
const BuildingPlacementDataScript := preload("res://scripts/building/BuildingPlacementData.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Definitions")
@export var arrow_tower: BuildingDefinition
@export var laser_tower: BuildingDefinition
@export var barrier: BuildingDefinition
@export var edge_barrier: BuildingDefinition
@export var crossbow_tower: BuildingDefinition

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
var _edge_buildings: Dictionary = {}
var _selected_building: Building
var _preview_building: Building
var _preview_definition: BuildingDefinition
var _preview_cell: Vector3i = Vector3i.ZERO
var _preview_edge_id: String = ""
var _preview_facing_index: int = 0
var _placement_rules: RefCounted = BuildingPlacementRulesScript.new()
var _building_exit_callbacks: Dictionary = {}
var _edge_occupancy_registry: EdgeOccupancyRegistry
var _projection_blocker_resolver: Callable
var _path_connectivity_validator: Callable

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
	_placement_rules.configure(_grid, _tile_manager, _resource_manager, _combat_manager)
	arrow_tower = _reload_definition(arrow_tower)
	laser_tower = _reload_definition(laser_tower)
	barrier = _reload_definition(barrier)
	edge_barrier = _reload_definition(edge_barrier)
	crossbow_tower = _reload_definition(crossbow_tower)
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)

func set_edge_occupancy_registry(value: EdgeOccupancyRegistry) -> void:
	_edge_occupancy_registry = value

func set_projection_blocker_resolver(value: Callable) -> void:
	_projection_blocker_resolver = value


func set_path_connectivity_validator(value: Callable) -> void:
	_path_connectivity_validator = value

func place_building(
	cell: Vector3i,
	definition: BuildingDefinition,
	placement_facing: int = -1
) -> Building:
	return _place_tile_building(cell, definition, placement_facing, 1, true, true, true)


func place_edge_building(
	from_cell: Vector3i,
	placement_edge_index: int,
	definition: BuildingDefinition
) -> Building:
	return _place_edge_building(from_cell, placement_edge_index, definition, 1, true, true, true)


## Captures only real Buildings. Preview nodes and mirror projections are excluded.
func export_initial_placements() -> Array[BuildingPlacementData]:
	var placements: Array[BuildingPlacementData] = []
	for building in get_buildings():
		var placement := BuildingPlacementDataScript.new()
		placement.configure(
			building.definition,
			building.cell,
			building.facing_index,
			building.edge_index if building.is_edge_placement() else -1,
			building.level
		)
		placements.append(placement)
	placements.sort_custom(func(a: BuildingPlacementData, b: BuildingPlacementData) -> bool:
		return _placement_sort_key(a) < _placement_sort_key(b)
	)
	return placements


## Keeps current runtime state while re-sampling edited terrain heights.
func refresh_world_transforms() -> void:
	for building in get_buildings():
		building.refresh_world_transform()
	if _preview_building != null and is_instance_valid(_preview_building):
		_preview_building.refresh_world_transform()


## Rebuilds the authored initial layout without charging initial_resource.
## Returns one message per rejected placement and rolls back partial assembly.
func load_initial_placements(placements: Array) -> Array[String]:
	clear_buildings(false)
	var errors: Array[String] = []
	for index in range(placements.size()):
		var raw_placement: Variant = placements[index]
		if not raw_placement is BuildingPlacementDataScript:
			errors.append("初始建筑 %d 数据类型无效" % (index + 1))
			continue
		var placement: BuildingPlacementData = raw_placement
		var building: Building
		if placement.is_edge_placement():
			building = _place_edge_building(
				placement.cell,
				placement.edge_index,
				placement.definition,
				placement.level,
				false,
				false,
				false
			)
		else:
			building = _place_tile_building(
				placement.cell,
				placement.definition,
				placement.facing_index,
				placement.level,
				false,
				false,
				false
			)
		if building == null:
			errors.append("初始建筑 %d 装配失败" % (index + 1))
	if not errors.is_empty():
		clear_buildings(true)
	else:
		select_building(null)
	return errors


func _place_tile_building(
	cell: Vector3i,
	definition: BuildingDefinition,
	placement_facing: int,
	initial_level: int,
	charge_cost: bool,
	check_connectivity: bool,
	select_after_placement: bool
) -> Building:
	var failure := _validate_placement(cell, definition, charge_cost)
	if not failure.is_empty():
		placement_failed.emit(cell, failure)
		return null
	var level_one_stats := definition.get_level_stats(1)
	var building := Building.new()
	add_child(building)
	building.configure(definition, cell, _grid, _tile_manager, _combat_manager, initial_level)
	var connectivity_failure := (
		_validate_path_connectivity({"extra_tile_blocker": building})
		if check_connectivity and building.is_tile_path_blocker()
		else ""
	)
	if not connectivity_failure.is_empty():
		building.queue_free()
		placement_failed.emit(cell, connectivity_failure)
		return null
	_register_building_lifecycle(building)
	if placement_facing >= 0:
		building.set_facing_index(placement_facing)
	var occupied := _tile_manager.place_path_occupant(cell, building) if building.is_path_blocker() else _tile_manager.place_occupant(cell, building)
	if not occupied:
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(cell, "地块已被占用")
		return null
	var registered := (
		_resource_manager.try_register_building(level_one_stats.cost)
		if charge_cost
		else _resource_manager.try_register_initial_building()
	)
	if not registered:
		_tile_manager.clear_occupant(cell, building)
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(cell, "资源不足或达到建筑上限" if charge_cost else "初始建筑超过建筑上限")
		return null
	_buildings[cell] = building
	_sync_building_income()
	if select_after_placement:
		select_building(building)
	building_placed.emit(building)
	return building


func _place_edge_building(
	from_cell: Vector3i,
	placement_edge_index: int,
	definition: BuildingDefinition,
	initial_level: int,
	charge_cost: bool,
	check_connectivity: bool,
	select_after_placement: bool
) -> Building:
	var validation := _validate_edge_placement(from_cell, placement_edge_index, definition, charge_cost)
	var failure: String = validation["failure"]
	if not failure.is_empty():
		placement_failed.emit(from_cell, failure)
		return null
	var to_cell: Vector3i = validation["to_cell"]
	var canonical_id: String = validation["edge_id"]
	var level_one_stats := definition.get_level_stats(1)
	var building := Building.new()
	add_child(building)
	building.configure_edge(
		definition,
		from_cell,
		to_cell,
		placement_edge_index,
		canonical_id,
		_grid,
		_tile_manager,
		_combat_manager,
		initial_level
	)
	var connectivity_failure := (
		_validate_path_connectivity({"extra_edge_blocker": building})
		if check_connectivity and building.is_edge_path_blocker()
		else ""
	)
	if not connectivity_failure.is_empty():
		building.queue_free()
		placement_failed.emit(from_cell, connectivity_failure)
		return null
	_register_building_lifecycle(building)
	var registered := (
		_resource_manager.try_register_building(level_one_stats.cost)
		if charge_cost
		else _resource_manager.try_register_initial_building()
	)
	if not registered:
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(from_cell, "资源不足或达到建筑上限" if charge_cost else "初始建筑超过建筑上限")
		return null
	if _edge_occupancy_registry != null and not _edge_occupancy_registry.try_register(canonical_id, building):
		_resource_manager.unregister_building(level_one_stats.cost if charge_cost else 0.0)
		_disconnect_building_lifecycle(building)
		building.queue_free()
		placement_failed.emit(from_cell, "该物理边已被占用")
		return null
	_edge_buildings[canonical_id] = building
	_sync_building_income()
	if select_after_placement:
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
	return _release_building(building, building.get_refund_amount(), true, true)

func clear_buildings(update_resource_count: bool = true) -> void:
	var buildings := get_buildings()
	for building in buildings:
		_release_building(building, 0.0, update_resource_count, true, false)
	_buildings.clear()
	_edge_buildings.clear()
	_building_exit_callbacks.clear()
	select_building(null)
	clear_preview()
	_sync_building_income()

func update_preview(cell: Vector3i, definition: BuildingDefinition) -> bool:
	if not _can_preview(cell, definition):
		clear_preview(false)
		return false
	if _preview_building != null and _preview_definition == definition and _preview_cell == cell:
		_refresh_preview_connectivity()
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
	_refresh_preview_connectivity()
	preview_updated.emit(_preview_building)
	return true

func update_edge_preview(
	from_cell: Vector3i,
	placement_edge_index: int,
	definition: BuildingDefinition
) -> bool:
	var validation := _validate_edge_placement(from_cell, placement_edge_index, definition, false)
	var failure: String = validation["failure"]
	if not failure.is_empty():
		clear_preview(false)
		return false
	var canonical_id: String = validation["edge_id"]
	if _preview_building != null and _preview_definition == definition and _preview_edge_id == canonical_id and _preview_cell == from_cell:
		_refresh_preview_connectivity()
		return true
	clear_preview(false)
	_preview_definition = definition
	_preview_cell = from_cell
	_preview_edge_id = canonical_id
	_preview_facing_index = placement_edge_index
	var to_cell: Vector3i = validation["to_cell"]
	_preview_building = Building.new()
	add_child(_preview_building)
	_preview_building.configure_edge(
		definition,
		from_cell,
		to_cell,
		placement_edge_index,
		canonical_id,
		_grid,
		_tile_manager,
		_combat_manager,
		1,
		true
	)
	_refresh_preview_connectivity()
	preview_updated.emit(_preview_building)
	return true

func clear_preview(clear_definition: bool = true) -> void:
	var had_visible_preview := _preview_building != null and is_instance_valid(_preview_building)
	if _preview_building != null and is_instance_valid(_preview_building):
		_preview_building.queue_free()
	_preview_building = null
	_preview_edge_id = ""
	if clear_definition:
		_preview_definition = null
	if had_visible_preview:
		preview_cleared.emit()

func rotate_preview(step: int = 1) -> bool:
	if _preview_building == null or not is_instance_valid(_preview_building):
		return false
	if not _preview_building.rotate_facing(step):
		return false
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
	for raw_building in _edge_buildings.values():
		var building: Building = raw_building
		if building != null and is_instance_valid(building):
			out.append(building)
	return out

func get_edge_building(edge_id: String) -> Building:
	if edge_id.is_empty() or not _edge_buildings.has(edge_id):
		return null
	var building: Building = _edge_buildings[edge_id]
	return building if is_instance_valid(building) else null

func select_at(cell: Vector3i, edge_id: String = "") -> Building:
	var building := get_edge_building(edge_id) if not edge_id.is_empty() else null
	if building == null:
		building = get_building(cell)
	select_building(building)
	return building

func select_building(building: Building) -> void:
	_selected_building = building
	building_selected.emit(building)

func rotate_selected(step: int = 1) -> bool:
	var building := get_selected_building()
	if building == null:
		return false
	return building.rotate_facing(step)

func get_selected_building() -> Building:
	return _selected_building if is_instance_valid(_selected_building) else null

func get_definition(kind: int) -> BuildingDefinition:
	if kind == BuildingDefinition.Kind.CROSSBOW_TOWER:
		return crossbow_tower
	if kind == BuildingDefinition.Kind.EDGE_BARRIER:
		return edge_barrier
	if kind == BuildingDefinition.Kind.BARRIER:
		return barrier
	if kind == BuildingDefinition.Kind.LASER_TOWER:
		return laser_tower
	return arrow_tower

func get_path_blocker(cell: Vector3i, target: Node = null) -> Node:
	var building := get_building(cell)
	if building == null or not building.is_path_blocker() or not building.is_structure_alive() or not building.affects_target(target):
		return null
	return building

## Unified enemy-facing blocker contract. Directed edge blockers are checked
## before the tile blocker at the destination cell of the same route segment.
func resolve_path_blocker(from_cell: Vector3i, to_cell: Vector3i, target: Node = null) -> Node:
	var physical := resolve_physical_path_blocker(from_cell, to_cell, target)
	if physical != null:
		return physical
	if _projection_blocker_resolver.is_valid():
		var projected: Variant = _projection_blocker_resolver.call(to_cell, target)
		if projected is Node:
			return projected
	return null


## Physical-only resolver used by hypothetical placement checks. Mirror
## projections are supplied as an explicit current/prospective graph snapshot.
func resolve_physical_path_blocker(from_cell: Vector3i, to_cell: Vector3i, target: Node = null) -> Node:
	if _grid == null:
		return null
	var edge_index := _grid.find_edge_index(from_cell, to_cell)
	if edge_index >= 0:
		var edge_building := get_edge_building(_grid.canonical_edge_id(from_cell, edge_index))
		if edge_building != null and edge_building.blocks_edge_traversal(from_cell, to_cell) and edge_building.is_structure_alive() and edge_building.affects_target(target):
			return edge_building
	var tile_blocker := get_path_blocker(to_cell, target)
	if tile_blocker != null:
		return tile_blocker
	return null

func is_path_cell(cell: Vector3i) -> bool:
	return _placement_rules.is_path_cell(cell)

func _validate_placement(
	cell: Vector3i,
	definition: BuildingDefinition,
	check_economy: bool = true
) -> String:
	if not feature_enabled:
		return "建筑系统已关闭"
	return _placement_rules.validate_tile(cell, definition, check_economy)

func _validate_edge_placement(
	from_cell: Vector3i,
	placement_edge_index: int,
	definition: BuildingDefinition,
	check_economy: bool = true
) -> Dictionary:
	if not feature_enabled:
		return {"failure": "建筑系统已关闭", "to_cell": Vector3i.ZERO, "edge_id": ""}
	return _placement_rules.validate_edge(
		from_cell,
		placement_edge_index,
		definition,
		Callable(self, "_get_edge_occupant"),
		check_economy
	)

func _can_preview(cell: Vector3i, definition: BuildingDefinition) -> bool:
	return feature_enabled and _placement_rules.validate_tile(cell, definition, false).is_empty()


func _validate_path_connectivity(change: Dictionary) -> String:
	if not _path_connectivity_validator.is_valid():
		return ""
	var result: Variant = _path_connectivity_validator.call(change)
	return String(result)


func _refresh_preview_connectivity() -> void:
	if _preview_building == null or not is_instance_valid(_preview_building):
		return
	if not _preview_building.is_path_blocker():
		_preview_building.set_preview_valid(true)
		return
	var key := "extra_edge_blocker" if _preview_building.is_edge_path_blocker() else "extra_tile_blocker"
	var failure := _validate_path_connectivity({key: _preview_building})
	_preview_building.set_preview_valid(failure.is_empty())

func _sync_building_income() -> void:
	if _resource_manager == null:
		return
	var total: float = 0.0
	for building in get_buildings():
		total += building.get_resource_per_second()
	_resource_manager.set_building_resource_per_second(total)


func _placement_sort_key(placement: BuildingPlacementData) -> String:
	return "%d,%d,%d|%d|%d|%s" % [
		placement.cell.x,
		placement.cell.y,
		placement.cell.z,
		placement.edge_index,
		placement.facing_index,
		placement.definition.resource_path if placement.definition != null else "",
	]

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
	_placement_rules.rebuild_level_cache(level_resource)

func _on_building_destroyed(building: Building, attacker: Node) -> void:
	if building == null or not _is_registered_building(building):
		return
	building_destroyed.emit(building, attacker)
	_release_building(building, 0.0, true, true)

func _on_building_tree_exited(building: Building) -> void:
	if building == null or not _is_registered_building(building):
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
	if building == null or not _is_registered_building(building):
		return false
	if building.is_edge_placement():
		_edge_buildings.erase(building.edge_id)
		if _edge_occupancy_registry != null:
			_edge_occupancy_registry.unregister(building.edge_id, building)
	else:
		_buildings.erase(building.cell)
	if _tile_manager != null and not building.is_edge_placement():
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

func _is_registered_building(building: Building) -> bool:
	if building == null:
		return false
	if building.is_edge_placement():
		return _edge_buildings.has(building.edge_id) and _edge_buildings[building.edge_id] == building
	return _buildings.has(building.cell) and _buildings[building.cell] == building

func _register_building_lifecycle(building: Building) -> void:
	building.structure_destroyed.connect(_on_building_destroyed)
	var exit_callback := _on_building_tree_exited.bind(building)
	building.tree_exited.connect(exit_callback)
	_building_exit_callbacks[building] = exit_callback

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

func _get_edge_occupant(edge_id: String) -> Object:
	if _edge_occupancy_registry != null:
		return _edge_occupancy_registry.get_occupant(edge_id)
	return get_edge_building(edge_id)
