## StuffManager -- canonical runtime state/query boundary for level Stuff.
##
## Multiple Stuff instances may share a cell. Placement restrictions compose
## independently from Terrain and disappear with the removed Stuff instance.
class_name StuffManager
extends Node3D

const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const StuffRuntimeScript := preload("res://scripts/stuff/StuffRuntime.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

signal stuff_loaded(level_resource: LevelResource)
signal stuff_cleared
signal stuff_changed(cell: Vector3i)
signal stuff_removed(stuff: StuffRuntime)
signal obstacle_destroyed(cell: Vector3i)
signal obstacle_durability_changed(cell: Vector3i, current: float, maximum: float)

var _grid: GridManager
var _terrain_manager: Node
var _level: LevelResource
var _by_id: Dictionary = {}
var _by_cell: Dictionary = {}
var _visual_snapshot_resolver: Callable


func configure(grid_manager: GridManager, terrain_manager: Node) -> void:
	_grid = grid_manager
	_terrain_manager = terrain_manager


## Builds a complete next state before replacing the active Stuff collection.
func load_level(level_resource: LevelResource) -> bool:
	if not feature_enabled or level_resource == null or _grid == null:
		return false
	if not level_resource.validate_runtime().is_empty():
		return false
	var snapshot := level_resource.get_effective_content_snapshot()
	var placements: Array[StuffPlacementData] = []
	var ids: Dictionary = {}
	var cells: Dictionary = {}
	for raw_placement in snapshot.get("stuff_placements", []):
		if not raw_placement is StuffPlacementDataScript:
			return false
		var source: StuffPlacementData = raw_placement
		if not _grid.is_in_bounds(source.cell) or source.definition == null or ids.has(source.placement_id):
			return false
		var clone := _clone_placement(source)
		var existing: Array = cells.get(clone.cell, [])
		for other in existing:
			if not clone.definition.can_coexist_with(other.definition):
				return false
		existing.append(clone)
		cells[clone.cell] = existing
		ids[clone.placement_id] = true
		placements.append(clone)
	clear_level()
	_level = level_resource
	for placement in placements:
		_create_runtime(placement)
	stuff_loaded.emit(level_resource)
	return true


func clear_level() -> void:
	for raw_runtime in _by_id.values():
		var runtime: StuffRuntime = raw_runtime
		if runtime != null and is_instance_valid(runtime):
			runtime.free()
	_by_id.clear()
	_by_cell.clear()
	_level = null
	stuff_cleared.emit()


func get_level_resource() -> LevelResource:
	return _level


func get_stuff(placement_id: StringName) -> StuffRuntime:
	var runtime: StuffRuntime = _by_id.get(placement_id)
	return runtime if runtime != null and is_instance_valid(runtime) and not runtime.is_queued_for_deletion() else null


func get_all_stuff() -> Array[StuffRuntime]:
	var out: Array[StuffRuntime] = []
	for raw_runtime in _by_id.values():
		var runtime: StuffRuntime = raw_runtime
		if runtime != null and is_instance_valid(runtime) and not runtime.is_queued_for_deletion():
			out.append(runtime)
	out.sort_custom(func(a: StuffRuntime, b: StuffRuntime) -> bool: return String(a.placement_id) < String(b.placement_id))
	return out


func get_stuff_at(cell: Vector3i) -> Array[StuffRuntime]:
	var out: Array[StuffRuntime] = []
	for raw_runtime in _by_cell.get(cell, []):
		var runtime: StuffRuntime = raw_runtime
		if runtime != null and is_instance_valid(runtime) and not runtime.is_queued_for_deletion():
			out.append(runtime)
	out.sort_custom(func(a: StuffRuntime, b: StuffRuntime) -> bool: return String(a.placement_id) < String(b.placement_id))
	return out


func get_effect_bindings(cell: Vector3i) -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for runtime in get_stuff_at(cell):
		var effect := runtime.get_effect()
		if effect == null:
			continue
		bindings.append({
			"effect": effect,
			"source_cell": runtime.cell,
			"state_key": runtime.get_effect_state_key(),
			"source": runtime,
		})
	return bindings


func get_all_effect_bindings() -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for runtime in get_all_stuff():
		var effect := runtime.get_effect()
		if effect != null:
			bindings.append({
				"effect": effect,
				"source_cell": runtime.cell,
				"state_key": runtime.get_effect_state_key(),
				"source": runtime,
			})
	return bindings


func allows_tile_building(cell: Vector3i) -> bool:
	for runtime in get_stuff_at(cell):
		if runtime.definition != null and runtime.definition.blocks_tile_building:
			return false
	return true


func allows_edge_building(cell: Vector3i) -> bool:
	for runtime in get_stuff_at(cell):
		if runtime.definition != null and runtime.definition.blocks_edge_building:
			return false
	return true


func blocks_enemy_navigation(cell: Vector3i, target: Node = null) -> bool:
	for runtime in get_stuff_at(cell):
		if runtime.blocks_enemy_navigation(target):
			return true
	return false


func can_use_for_reroute(cell: Vector3i, target: Node = null) -> bool:
	for runtime in get_stuff_at(cell):
		if not runtime.can_use_for_reroute(target):
			return false
	return true


func resolve_navigation_blocker(cell: Vector3i, target: Node = null) -> Node:
	for runtime in get_stuff_at(cell):
		if runtime.is_destructible() and runtime.blocks_enemy_navigation(target):
			return runtime
	return null


func get_runtime_obstacle(cell: Vector3i) -> Node:
	return resolve_navigation_blocker(cell)


func destroy_obstacle_at(cell: Vector3i) -> bool:
	var obstacle := resolve_navigation_blocker(cell)
	if not obstacle is StuffRuntime:
		return false
	return remove_stuff(obstacle.placement_id)


func remove_stuff(placement_id: StringName) -> bool:
	var runtime := get_stuff(placement_id)
	if runtime == null:
		return false
	var cell := runtime.cell
	_by_id.erase(placement_id)
	var cell_items: Array = _by_cell.get(cell, [])
	cell_items.erase(runtime)
	if cell_items.is_empty():
		_by_cell.erase(cell)
	else:
		_by_cell[cell] = cell_items
	stuff_removed.emit(runtime)
	stuff_changed.emit(cell)
	if runtime.is_destructible():
		obstacle_destroyed.emit(cell)
	runtime.queue_free()
	return true


func set_visual_snapshot_resolver(value: Callable) -> void:
	_visual_snapshot_resolver = value
	for runtime in get_all_stuff():
		runtime.set_visual_snapshot_resolver(value)


func _create_runtime(placement: StuffPlacementData) -> void:
	var runtime: StuffRuntime = StuffRuntimeScript.new()
	runtime.name = "Stuff_%s" % String(placement.placement_id)
	add_child(runtime)
	if not runtime.configure(placement, _grid, Callable(_terrain_manager, "get_world_height")):
		runtime.free()
		return
	runtime.durability_changed.connect(_on_durability_changed)
	runtime.depleted.connect(_on_depleted)
	runtime.set_visual_snapshot_resolver(_visual_snapshot_resolver)
	_by_id[runtime.placement_id] = runtime
	var cell_items: Array = _by_cell.get(runtime.cell, [])
	cell_items.append(runtime)
	_by_cell[runtime.cell] = cell_items


func _clone_placement(source: StuffPlacementData) -> StuffPlacementData:
	var clone := StuffPlacementDataScript.new()
	clone.configure(source.placement_id, source.cell, source.definition, source.facing_index)
	return clone


func _on_durability_changed(runtime: StuffRuntime, current: float, maximum: float) -> void:
	if get_stuff(runtime.placement_id) != runtime:
		return
	obstacle_durability_changed.emit(runtime.cell, current, maximum)
	stuff_changed.emit(runtime.cell)


func _on_depleted(runtime: StuffRuntime, _attacker: Node) -> void:
	if get_stuff(runtime.placement_id) == runtime:
		remove_stuff(runtime.placement_id)
