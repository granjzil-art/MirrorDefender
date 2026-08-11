## StuffManager -- canonical runtime state/query boundary for level Stuff.
##
## Multiple Stuff instances may share a cell. Placement restrictions compose
## independently from Terrain and disappear with the removed Stuff instance.
class_name StuffManager
extends Node3D

const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const StuffRuntimeScript := preload("res://scripts/stuff/StuffRuntime.gd")
const StuffCatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")
const BallisticGeometryScript := preload("res://scripts/combat/BallisticGeometry.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Catalog")
@export var stuff_catalog: StuffCatalogScript

@export_group("Ballistic Blocking")
@export_range(0.01, 1.0, 0.01, "or_greater") var ballistic_blocker_radius_ratio: float = 0.32
@export_range(0.0, 2.0, 0.01, "or_greater") var ballistic_blocker_height_ratio: float = 0.42

signal stuff_loaded(level_resource: LevelResource)
signal stuff_cleared
signal stuff_placed(stuff: StuffRuntime)
signal stuff_changed(cell: Vector3i)
signal stuff_rotated(stuff: StuffRuntime, previous_facing: int, new_facing: int)
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
	var next_runtimes: Array[StuffRuntime] = []
	for placement in placements:
		var candidate := _instantiate_runtime(placement)
		if candidate == null:
			for prepared_runtime in next_runtimes:
				prepared_runtime.free()
			return false
		next_runtimes.append(candidate)
	clear_level()
	_level = level_resource
	for runtime in next_runtimes:
		_register_runtime(runtime)
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


func get_stuff_catalog() -> StuffCatalogScript:
	return stuff_catalog


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


func trace_ballistic_blocker(
	start: Vector3,
	end: Vector3,
	excluded: Object = null
) -> Dictionary:
	var result := {
		"hit": false,
		"position": end,
		"distance": start.distance_to(end),
		"blocker": null,
	}
	var best_distance := INF
	for runtime in get_all_stuff():
		if runtime == excluded or not runtime.blocks_ballistics():
			continue
		var distance := BallisticGeometryScript.ray_sphere_entry_distance(
			start,
			end,
			get_ballistic_blocker_center(runtime),
			get_ballistic_blocker_radius()
		)
		if distance < 0.0 or distance >= best_distance:
			continue
		best_distance = distance
		var direction := (end - start).normalized()
		result.hit = true
		result.position = start + direction * distance
		result.distance = distance
		result.blocker = runtime
	return result


func get_ballistic_blocker_center(runtime: StuffRuntime) -> Vector3:
	if runtime == null or not is_instance_valid(runtime):
		return Vector3.ZERO
	var size := _grid.cell_size if _grid != null else 1.0
	return runtime.global_position + Vector3.UP * size * ballistic_blocker_height_ratio


func get_ballistic_blocker_radius() -> float:
	var size := _grid.cell_size if _grid != null else 1.0
	return size * ballistic_blocker_radius_ratio


func export_placements() -> Array[StuffPlacementData]:
	var result: Array[StuffPlacementData] = []
	for runtime in get_all_stuff():
		var placement := StuffPlacementDataScript.new()
		placement.configure(
			runtime.placement_id,
			runtime.cell,
			runtime.definition,
			runtime.facing_index
		)
		result.append(placement)
	return result


## Preserves durability/effect state while re-sampling edited terrain heights.
func refresh_world_transforms() -> void:
	for runtime in get_all_stuff():
		runtime.refresh_world_transform()


## Adds one instance atomically without mutating the authored LevelResource.
## RuntimeStuffEditSession decides when the exported placement snapshot is saved.
func add_stuff(
	cell: Vector3i,
	definition: StuffDefinition,
	facing_index: int = 0,
	placement_id: StringName = &""
) -> StuffRuntime:
	if not feature_enabled or _grid == null or _level == null or definition == null:
		return null
	if not _grid.is_in_bounds(cell):
		return null
	var facing_count := maxi(1, _grid.get_tile_content_facing_count())
	if facing_index < 0 or facing_index >= facing_count:
		return null
	var resolved_definition := _resolve_catalog_definition(definition)
	for existing in get_stuff_at(cell):
		if not resolved_definition.can_coexist_with(existing.definition):
			return null
	var resolved_id := placement_id if not placement_id.is_empty() else _next_placement_id(resolved_definition.stuff_id)
	if resolved_id.is_empty() or get_stuff(resolved_id) != null:
		return null
	var placement := StuffPlacementDataScript.new()
	placement.configure(resolved_id, cell, resolved_definition, facing_index)
	var runtime := _create_runtime(placement)
	if runtime == null:
		return null
	stuff_placed.emit(runtime)
	stuff_changed.emit(cell)
	return runtime


func rotate_stuff(placement_id: StringName, step: int = 1) -> bool:
	var runtime := get_stuff(placement_id)
	if runtime == null or _grid == null:
		return false
	var facing_count := maxi(1, _grid.get_tile_content_facing_count())
	var previous := runtime.facing_index
	var next := posmod(previous + step, facing_count)
	if previous == next:
		return false
	runtime.facing_index = next
	runtime.refresh_world_transform()
	stuff_rotated.emit(runtime, previous, next)
	stuff_changed.emit(runtime.cell)
	return true


## Replaces only mutable Stuff runtime state. Terrain, buildings, waves and the
## current LevelResource identity are preserved.
func replace_runtime_placements(placements: Array) -> bool:
	var prepared := _prepare_placements(placements)
	if not bool(prepared.get("success", false)):
		return false
	var next_runtimes: Array[StuffRuntime] = []
	for placement in prepared.get("placements", []):
		var candidate := _instantiate_runtime(placement)
		if candidate == null:
			for prepared_runtime in next_runtimes:
				prepared_runtime.free()
			return false
		next_runtimes.append(candidate)
	_clear_runtime_nodes()
	for runtime in next_runtimes:
		_register_runtime(runtime)
	stuff_loaded.emit(_level)
	return true


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


func _create_runtime(placement: StuffPlacementData) -> StuffRuntime:
	var runtime := _instantiate_runtime(placement)
	if runtime != null:
		_register_runtime(runtime)
	return runtime


func _instantiate_runtime(placement: StuffPlacementData) -> StuffRuntime:
	var runtime: StuffRuntime = StuffRuntimeScript.new()
	runtime.name = "Stuff_%s" % String(placement.placement_id)
	if not runtime.configure(placement, _grid, Callable(_terrain_manager, "get_world_height")):
		runtime.free()
		return null
	return runtime


func _register_runtime(runtime: StuffRuntime) -> void:
	add_child(runtime)
	runtime.durability_changed.connect(_on_durability_changed)
	runtime.depleted.connect(_on_depleted)
	runtime.set_visual_snapshot_resolver(_visual_snapshot_resolver)
	_by_id[runtime.placement_id] = runtime
	var cell_items: Array = _by_cell.get(runtime.cell, [])
	cell_items.append(runtime)
	_by_cell[runtime.cell] = cell_items


func _clone_placement(source: StuffPlacementData) -> StuffPlacementData:
	var clone := StuffPlacementDataScript.new()
	clone.configure(
		source.placement_id,
		source.cell,
		_resolve_catalog_definition(source.definition),
		source.facing_index
	)
	return clone


func _resolve_catalog_definition(definition: StuffDefinition) -> StuffDefinition:
	if definition == null or stuff_catalog == null or definition.stuff_id.is_empty():
		return definition
	var canonical := stuff_catalog.get_definition(definition.stuff_id, true)
	return canonical if canonical != null else definition


func _prepare_placements(raw_placements: Array) -> Dictionary:
	var placements: Array[StuffPlacementData] = []
	var ids: Dictionary = {}
	var cells: Dictionary = {}
	for raw_placement in raw_placements:
		if not raw_placement is StuffPlacementDataScript:
			return {"success": false, "placements": []}
		var source: StuffPlacementData = raw_placement
		if _grid == null or not _grid.is_in_bounds(source.cell) or source.definition == null:
			return {"success": false, "placements": []}
		if source.placement_id.is_empty() or ids.has(source.placement_id):
			return {"success": false, "placements": []}
		var facing_count := maxi(1, _grid.get_tile_content_facing_count())
		if source.facing_index < 0 or source.facing_index >= facing_count:
			return {"success": false, "placements": []}
		var clone := _clone_placement(source)
		var existing: Array = cells.get(clone.cell, [])
		for other in existing:
			if not clone.definition.can_coexist_with(other.definition):
				return {"success": false, "placements": []}
		existing.append(clone)
		cells[clone.cell] = existing
		ids[clone.placement_id] = true
		placements.append(clone)
	return {"success": true, "placements": placements}


func _clear_runtime_nodes() -> void:
	for raw_runtime in _by_id.values():
		var runtime: StuffRuntime = raw_runtime
		if runtime != null and is_instance_valid(runtime):
			runtime.free()
	_by_id.clear()
	_by_cell.clear()
	stuff_cleared.emit()


func _next_placement_id(stuff_id: StringName) -> StringName:
	var prefix := String(stuff_id).strip_edges().to_snake_case()
	if prefix.is_empty():
		prefix = "stuff"
	var index := 1
	while _by_id.has(StringName("%s_%d" % [prefix, index])):
		index += 1
	return StringName("%s_%d" % [prefix, index])


func _on_durability_changed(runtime: StuffRuntime, current: float, maximum: float) -> void:
	if get_stuff(runtime.placement_id) != runtime:
		return
	obstacle_durability_changed.emit(runtime.cell, current, maximum)
	stuff_changed.emit(runtime.cell)


func _on_depleted(runtime: StuffRuntime, _attacker: Node) -> void:
	if get_stuff(runtime.placement_id) == runtime:
		remove_stuff(runtime.placement_id)
