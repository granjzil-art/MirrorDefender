## Prevents player-created blockers from removing the last route from a spawn
## point to its authored target base. Runtime enemy rerouting remains owned by
## PathRoutePlanner; this service only evaluates hypothetical placement state.
class_name PathPlacementConnectivityGuard
extends Node

const PathNavigationProfileScript := preload("res://scripts/path/PathNavigationProfile.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

var _grid: GridManager
var _tile_manager: TileManager
var _level: LevelResource
var _physical_blocker_resolver: Callable
var _projected_blocked_cells_resolver: Callable
var _ground_profile: PathNavigationProfile
var _airborne_profile: PathNavigationProfile


func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	physical_blocker_resolver: Callable,
	projected_blocked_cells_resolver: Callable
) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_physical_blocker_resolver = physical_blocker_resolver
	_projected_blocked_cells_resolver = projected_blocked_cells_resolver
	_ensure_profiles()


func load_level(level_resource: LevelResource) -> void:
	_level = level_resource


## change supports four optional hypothetical objects:
## - extra_tile_blocker: an unregistered tile Building copied by mirrors too;
## - extra_edge_blocker: an unregistered directional edge Building;
## - candidate_mirror: an unregistered CopyMirror included in the full graph.
## - removed_blocker: a live Building omitted while testing atomic relocation.
## - removed_mirror: a live mirror omitted while testing atomic relocation.
## Returns an empty string when placement remains safe, otherwise a player-facing
## reason. Pre-existing disconnected routes do not reject unrelated placements.
func validate_change(change: Dictionary = {}) -> String:
	if not feature_enabled or _grid == null or _tile_manager == null or _level == null:
		return ""
	_ensure_profiles()
	for requirement in _build_route_requirements():
		var airborne := bool(requirement.get("airborne", false))
		var profile := _airborne_profile if airborne else _ground_profile
		var baseline_projected := _get_projected_blocked_cells(null, null, profile)
		var changed_projected := _get_projected_blocked_cells(
			change.get("extra_tile_blocker"),
			change.get("candidate_mirror"),
			profile,
			change.get("removed_blocker"),
			change.get("removed_mirror")
		)
		if not _is_requirement_reachable(requirement, profile, baseline_projected, {}):
			continue
		if _is_requirement_reachable(requirement, profile, changed_projected, change):
			continue
		var path := requirement.get("path") as PathDefinition
		var spawn_point := _level.resolve_path_spawn_point(path)
		var target_base := _level.resolve_path_target_base(path)
		var spawn_label := _level.get_spawn_marker_label(spawn_point)
		var base_label := _level.get_base_marker_label(target_base)
		return "该障碍会堵死%s到%s的全部可用路径" % [spawn_label, base_label]
	return ""


func _build_route_requirements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for wave in _level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group == null or group.path == null or group.enemy == null:
				continue
			_append_requirement(result, seen, group.path, group.enemy.is_airborne)
	for path in _level.paths:
		if path == null:
			continue
		var has_profile := seen.has(_requirement_key(path, false)) or seen.has(_requirement_key(path, true))
		if not has_profile:
			_append_requirement(result, seen, path, false)
	return result


func _append_requirement(
	result: Array[Dictionary],
	seen: Dictionary,
	path: PathDefinition,
	airborne: bool
) -> void:
	if path == null or path.cells.size() < 2:
		return
	var target_base := _level.resolve_path_target_base(path)
	var spawn_point := _level.resolve_path_spawn_point(path)
	if target_base == null or spawn_point == null:
		return
	var key := _requirement_key(path, airborne)
	if seen.has(key):
		return
	seen[key] = true
	result.append({"path": path, "airborne": airborne})


func _requirement_key(path: PathDefinition, airborne: bool) -> String:
	return "%d|%s" % [path.get_instance_id(), "air" if airborne else "ground"]


func _is_requirement_reachable(
	requirement: Dictionary,
	profile: PathNavigationProfile,
	projected_blocked_cells: Dictionary,
	change: Dictionary
) -> bool:
	var path := requirement.get("path") as PathDefinition
	if path == null:
		return false
	var target_base := _level.resolve_path_target_base(path)
	if target_base == null:
		return false
	var allowed_cells := _build_target_network(target_base.base_id)
	var start := path.get_start_cell()
	var goals: Dictionary = {}
	for footprint_cell in target_base.get_footprint_cells():
		goals[footprint_cell] = true
		allowed_cells[footprint_cell] = true
	if not allowed_cells.has(start) or goals.is_empty():
		return false
	if not _cell_is_usable(start, profile, projected_blocked_cells, change):
		return false
	var frontier: Array[Vector3i] = [start]
	var visited: Dictionary = {start: true}
	while not frontier.is_empty():
		var current: Vector3i = frontier.pop_front()
		if goals.has(current):
			return true
		for neighbor in _grid.get_neighbors(current):
			if visited.has(neighbor) or not allowed_cells.has(neighbor):
				continue
			if not _cell_is_usable(neighbor, profile, projected_blocked_cells, change):
				continue
			if _segment_is_blocked(current, neighbor, profile, change):
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return false


func _build_target_network(target_base_id: StringName) -> Dictionary:
	var allowed_cells: Dictionary = {}
	for path in _level.paths:
		if path == null:
			continue
		var candidate_base := _level.resolve_path_target_base(path)
		if candidate_base == null or candidate_base.base_id != target_base_id:
			continue
		for cell in path.cells:
			allowed_cells[cell] = true
	var target_base := _level.get_base_point(target_base_id)
	if target_base != null:
		for footprint_cell in target_base.get_footprint_cells():
			allowed_cells[footprint_cell] = true
	return allowed_cells


func _cell_is_usable(
	cell: Vector3i,
	profile: PathNavigationProfile,
	projected_blocked_cells: Dictionary,
	change: Dictionary
) -> bool:
	if not _grid.is_in_bounds(cell) or not _tile_manager.can_use_for_reroute_without_navigation_overlay(cell, profile):
		return false
	if projected_blocked_cells.has(cell):
		return false
	var extra_tile := change.get("extra_tile_blocker") as Node
	if extra_tile != null and extra_tile.get("cell") == cell and _blocker_affects_target(extra_tile, profile):
		return false
	return true


func _segment_is_blocked(
	from_cell: Vector3i,
	to_cell: Vector3i,
	profile: PathNavigationProfile,
	change: Dictionary
) -> bool:
	if _physical_blocker_resolver.is_valid():
		var physical: Variant = _physical_blocker_resolver.call(from_cell, to_cell, profile)
		if physical is Node and physical != change.get("removed_blocker"):
			return true
	var extra_edge := change.get("extra_edge_blocker") as Node
	if extra_edge == null or not _blocker_affects_target(extra_edge, profile):
		return false
	return bool(extra_edge.call("blocks_edge_traversal", from_cell, to_cell))


func _blocker_affects_target(blocker: Node, target: Node) -> bool:
	if blocker == null or not is_instance_valid(blocker):
		return false
	if blocker.has_method("is_structure_alive") and not bool(blocker.call("is_structure_alive")):
		return false
	return not blocker.has_method("affects_target") or bool(blocker.call("affects_target", target))


func _get_projected_blocked_cells(
	extra_source: Variant,
	candidate_mirror: Variant,
	target: Node,
	removed_source: Variant = null,
	removed_mirror: Variant = null
) -> Dictionary:
	if not _projected_blocked_cells_resolver.is_valid():
		return {}
	var result: Variant
	if removed_source == null and removed_mirror == null:
		result = _projected_blocked_cells_resolver.call(extra_source, candidate_mirror, target)
	elif removed_mirror == null:
		result = _projected_blocked_cells_resolver.call(
			extra_source,
			candidate_mirror,
			target,
			removed_source
		)
	else:
		result = _projected_blocked_cells_resolver.call(
			extra_source,
			candidate_mirror,
			target,
			removed_source,
			removed_mirror
		)
	return result if result is Dictionary else {}


func _ensure_profiles() -> void:
	if _ground_profile == null:
		_ground_profile = PathNavigationProfileScript.new()
		add_child(_ground_profile)
		_ground_profile.configure(false)
	if _airborne_profile == null:
		_airborne_profile = PathNavigationProfileScript.new()
		add_child(_airborne_profile)
		_airborne_profile.configure(true)
