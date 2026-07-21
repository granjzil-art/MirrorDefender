## Selects deterministic detours from designer-authored paths when permanent
## terrain blocks the next cell. It never performs free-grid pathfinding and
## never mutates PathDefinition resources.
class_name PathRoutePlanner
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Debug Visual")
@export var show_selected_detour: bool = false
@export var detour_color: Color = Color(0.22, 0.72, 1.0, 1.0)
@export_range(0.01, 1.0, 0.01, "or_greater") var line_lift: float = 0.12

var _grid: GridManager
var _tile_manager: TileManager
var _level: LevelResource
var _debug_mesh: MeshInstance3D

func _ready() -> void:
	_debug_mesh = MeshInstance3D.new()
	add_child(_debug_mesh)

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager

func load_level(level_resource: LevelResource) -> void:
	_level = level_resource
	_clear_debug_visual()

## Returns {triggered, found, path, cells, cost, join_cell, blocker}. A reroute
## is only triggered for a navigation-blocking next tile and only searches
## other manually-authored paths in their serialized order. When no detour is
## found, blocker identifies the attackable obstruction at blocked_cell.
func find_detour(
	current_path: PathDefinition,
	current_cell: Vector3i,
	blocked_cell: Vector3i,
	target: Node = null
) -> Dictionary:
	var result := {
		"triggered": false,
		"found": false,
		"path": null,
		"cells": [],
		"cost": -1,
		"join_cell": Vector3i.ZERO,
		"blocker": null,
	}
	if not feature_enabled or _grid == null or _tile_manager == null or _level == null:
		return result
	if not _tile_manager.blocks_enemy_navigation(blocked_cell, target):
		return result
	result["triggered"] = true
	result["blocker"] = _tile_manager.resolve_navigation_blocker(blocked_cell, target)
	var best_cost := 2147483647
	for path in _level.paths:
		if path == null or path == current_path or path.cells.size() < 2:
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
	if bool(result["found"]):
		_rebuild_debug_visual(result["cells"])
	else:
		_clear_debug_visual()
	return result

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
