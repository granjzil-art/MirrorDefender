## Selects deterministic detours when permanent terrain blocks the next cell.
## Authored same-target paths have priority; the fallback A* is restricted to
## the union of authored road cells leading to that same target base.
class_name PathRoutePlanner
extends Node3D

const IAutoRouteStrategyScript := preload("res://scripts/path/IAutoRouteStrategy.gd")
const PathNetworkAStarStrategyScript := preload("res://scripts/path/PathNetworkAStarStrategy.gd")
const PathRouteSnapshotCacheScript := preload("res://scripts/path/PathRouteSnapshotCache.gd")
const PathNavigationProfileScript := preload("res://scripts/path/PathNavigationProfile.gd")

@export_group("Feature")
@export var feature_enabled: bool = true
@export var automatic_route_enabled: bool = true

@export_group("Shared Route Snapshot")
@export var route_snapshot_enabled: bool = true
@export_range(0.1, 10.0, 0.1, "or_greater") var route_refresh_interval: float = 0.5

@export_group("Debug Visual")
@export var show_selected_detour: bool = false
@export var detour_color: Color = Color(0.22, 0.72, 1.0, 1.0)
@export_range(0.01, 1.0, 0.01, "or_greater") var line_lift: float = 0.12

signal route_snapshot_changed(snapshot: Dictionary)

var _grid: GridManager
var _tile_manager: TileManager
var _level: LevelResource
var _debug_mesh: MeshInstance3D
var _auto_route_strategy: IAutoRouteStrategyScript
var _route_refresh_elapsed: float = 0.0
var _ground_route_cache: PathRouteSnapshotCacheScript = PathRouteSnapshotCacheScript.new()
var _airborne_route_cache: PathRouteSnapshotCacheScript = PathRouteSnapshotCacheScript.new()
var _airborne_profile: PathNavigationProfileScript = PathNavigationProfileScript.new()

func _ready() -> void:
	_debug_mesh = MeshInstance3D.new()
	add_child(_debug_mesh)
	if _airborne_profile.get_parent() == null:
		add_child(_airborne_profile)
	if _auto_route_strategy == null:
		_auto_route_strategy = PathNetworkAStarStrategyScript.new()
	_airborne_profile.configure(true)


func _process(delta: float) -> void:
	advance_route_refresh(delta)

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_airborne_profile.configure(true)
	if _auto_route_strategy == null:
		_auto_route_strategy = PathNetworkAStarStrategyScript.new()

func load_level(level_resource: LevelResource) -> void:
	_level = level_resource
	_route_refresh_elapsed = 0.0
	_ground_route_cache.reset()
	_airborne_route_cache.reset()
	_clear_debug_visual()
	refresh_route_snapshot()


func set_auto_route_strategy(strategy: IAutoRouteStrategyScript) -> void:
	_auto_route_strategy = strategy


func set_debug_route_visible(enabled: bool) -> void:
	show_selected_detour = enabled
	if not enabled:
		_clear_debug_visual()


## Advances the shared whole-path refresh clock. Exposed for deterministic tests;
## runtime calls it once per process frame and only recalculates at the interval.
func advance_route_refresh(delta: float) -> void:
	if not feature_enabled or not route_snapshot_enabled or _level == null:
		return
	_route_refresh_elapsed += maxf(0.0, delta)
	var interval := maxf(0.1, route_refresh_interval)
	if _route_refresh_elapsed + 0.000001 < interval:
		return
	_route_refresh_elapsed = fposmod(_route_refresh_elapsed, interval)
	refresh_route_snapshot()


## Rebuilds ground and airborne snapshots per authored path. They are shared
## only when a matching unit actually reaches the recorded blocked segment;
## background prediction never mutates PathDefinition.cells or unit progress.
func refresh_route_snapshot() -> void:
	var level := _level if feature_enabled and route_snapshot_enabled and _grid != null else null
	var ground_changed := _ground_route_cache.refresh(
		level,
		_tile_manager,
		Callable(self, "_calculate_snapshot_detour")
	)
	var airborne_changed := _airborne_route_cache.refresh(
		level,
		_tile_manager,
		Callable(self, "_calculate_snapshot_detour"),
		_airborne_profile
	)
	if ground_changed or airborne_changed:
		route_snapshot_changed.emit(get_route_snapshot())


func get_route_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	var ground := _ground_route_cache.get_snapshot()
	var airborne := _airborne_route_cache.get_snapshot()
	for path_id in ground.keys():
		snapshot[path_id] = {
			"ground": (ground[path_id] as Array).duplicate(),
			"airborne": (airborne.get(path_id, ground[path_id]) as Array).duplicate(),
		}
	return snapshot


func get_effective_route_cells(path: PathDefinition, airborne: bool = false) -> Array[Vector3i]:
	return _airborne_route_cache.get_effective_cells(path) if airborne else _ground_route_cache.get_effective_cells(path)

## Returns {triggered, found, path, cells, cost, join_cell, blocker}. A reroute
## is only triggered for a navigation-blocking next tile and only searches
## other manually-authored paths in their serialized order before the bounded
## A* fallback. When none is found, blocker identifies the obstruction at the
## blocked cell so the enemy can attack it.
func find_detour(
	current_path: PathDefinition,
	current_cell: Vector3i,
	blocked_cell: Vector3i,
	target: Node = null
) -> Dictionary:
	var result := _make_empty_result()
	if not feature_enabled or _grid == null or _tile_manager == null or _level == null:
		return result
	if not _tile_manager.blocks_enemy_navigation(blocked_cell, target):
		return result
	if route_snapshot_enabled and _uses_ground_navigation(target):
		var cached: Dictionary = _ground_route_cache.get_cached_detour(current_path, current_cell, blocked_cell)
		if not cached.is_empty():
			cached["blocker"] = _tile_manager.resolve_navigation_blocker(blocked_cell, target)
			if bool(cached.get("found", false)):
				_rebuild_debug_visual(cached.get("cells", []))
			else:
				_clear_debug_visual()
			return cached
	elif route_snapshot_enabled:
		var cached: Dictionary = _airborne_route_cache.get_cached_detour(current_path, current_cell, blocked_cell)
		if not cached.is_empty():
			cached["blocker"] = _tile_manager.resolve_navigation_blocker(blocked_cell, target)
			if bool(cached.get("found", false)):
				_rebuild_debug_visual(cached.get("cells", []))
			else:
				_clear_debug_visual()
			return cached
	return _calculate_detour(current_path, current_cell, blocked_cell, target, true)


func _calculate_snapshot_detour(
	current_path: PathDefinition,
	current_cell: Vector3i,
	blocked_cell: Vector3i,
	target: Node
) -> Dictionary:
	return _calculate_detour(current_path, current_cell, blocked_cell, target, false)


func _calculate_detour(
	current_path: PathDefinition,
	current_cell: Vector3i,
	blocked_cell: Vector3i,
	target: Node,
	update_debug_visual: bool
) -> Dictionary:
	var result := _make_empty_result()
	if not feature_enabled or _grid == null or _tile_manager == null or _level == null:
		return result
	if not _tile_manager.blocks_enemy_navigation(blocked_cell, target):
		return result
	result["triggered"] = true
	result["blocker"] = _tile_manager.resolve_navigation_blocker(blocked_cell, target)
	var target_base := _level.resolve_path_target_base(current_path)
	if target_base == null:
		if update_debug_visual:
			_clear_debug_visual()
		return result
	result["target_base_id"] = target_base.base_id
	var best_cost := 2147483647
	for path in _level.paths:
		if path == null or path == current_path or path.cells.size() < 2:
			continue
		var candidate_base := _level.resolve_path_target_base(path)
		if candidate_base == null or candidate_base.base_id != target_base.base_id:
			continue
		for join_index in range(path.cells.size()):
			var join_cell: Vector3i = path.cells[join_index]
			var connector_cost := _connector_cost(current_cell, join_cell)
			if connector_cost < 0 or not _suffix_is_usable(path, join_index, target):
				continue
			var candidate_cost := connector_cost + path.cells.size() - 1 - join_index
			if candidate_cost >= best_cost:
				continue
			var route: Array[Vector3i] = [current_cell]
			if join_cell != current_cell:
				route.append(join_cell)
			for suffix_index in range(join_index + 1, path.cells.size()):
				route.append(path.cells[suffix_index])
			if route.size() < 2:
				continue
			best_cost = candidate_cost
			result["found"] = true
			result["path"] = path
			result["cells"] = route
			result["cost"] = candidate_cost
			result["join_cell"] = join_cell
			result["route_source"] = &"manual"
	if bool(result["found"]):
		if update_debug_visual:
			_rebuild_debug_visual(result["cells"])
		return result
	if automatic_route_enabled and _auto_route_strategy != null:
		var allowed_cells := _build_target_path_network(target_base.base_id)
		var automatic_cells: Array[Vector3i] = []
		for goal_cell in target_base.get_footprint_cells():
			var candidate_cells := _auto_route_strategy.find_route(
				_grid,
				_tile_manager,
				current_cell,
				goal_cell,
				allowed_cells,
				target
			)
			if candidate_cells.size() < 2:
				continue
			if automatic_cells.is_empty() or candidate_cells.size() < automatic_cells.size():
				automatic_cells = candidate_cells
		if automatic_cells.size() >= 2:
			result["found"] = true
			result["path"] = current_path
			result["cells"] = automatic_cells
			result["cost"] = automatic_cells.size() - 1
			result["join_cell"] = automatic_cells[1]
			result["route_source"] = &"automatic"
			if update_debug_visual:
				_rebuild_debug_visual(automatic_cells)
			return result
	if update_debug_visual:
		_clear_debug_visual()
	return result


func _make_empty_result() -> Dictionary:
	return {
		"triggered": false,
		"found": false,
		"path": null,
		"cells": [],
		"cost": -1,
		"join_cell": Vector3i.ZERO,
		"blocker": null,
		"route_source": &"",
		"target_base_id": &"",
	}


func _uses_ground_navigation(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not target.has_method("is_airborne_unit"):
		return true
	return not bool(target.call("is_airborne_unit"))
func _build_target_path_network(target_base_id: StringName) -> Dictionary:
	var cells: Dictionary = {}
	if _level == null:
		return cells
	for path in _level.paths:
		if path == null:
			continue
		var path_base := _level.resolve_path_target_base(path)
		if path_base == null or path_base.base_id != target_base_id:
			continue
		for cell in path.cells:
			cells[cell] = true
	var target_base := _level.get_base_point(target_base_id)
	if target_base != null:
		for footprint_cell in target_base.get_footprint_cells():
			cells[footprint_cell] = true
	return cells

func _connector_cost(current_cell: Vector3i, join_cell: Vector3i) -> int:
	if join_cell == current_cell:
		return 0
	return 1 if _grid.get_neighbors(current_cell).has(join_cell) else -1

func _suffix_is_usable(path: PathDefinition, join_index: int, target: Node = null) -> bool:
	for index in range(join_index, path.cells.size()):
		var cell: Vector3i = path.cells[index]
		if not _grid.is_in_bounds(cell) or not _tile_manager.can_use_for_reroute(cell, target):
			return false
		if index > join_index and not _grid.get_neighbors(path.cells[index - 1]).has(cell):
			return false
	return true

func _rebuild_debug_visual(cells: Array[Vector3i]) -> void:
	if _debug_mesh == null or not show_selected_detour or cells.size() < 2:
		_clear_debug_visual()
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = detour_color
	material.emission_enabled = true
	material.emission = detour_color
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(1, cells.size()):
		mesh.surface_add_vertex(_cell_world_position(cells[index - 1]))
		mesh.surface_add_vertex(_cell_world_position(cells[index]))
	mesh.surface_end()
	_debug_mesh.mesh = mesh

func _cell_world_position(cell: Vector3i) -> Vector3:
	var height := _tile_manager.get_world_height(cell) if _tile_manager != null else 0.0
	return _grid.cell_to_world(cell) + Vector3(0.0, height + line_lift, 0.0)

func _clear_debug_visual() -> void:
	if _debug_mesh != null:
		_debug_mesh.mesh = null
