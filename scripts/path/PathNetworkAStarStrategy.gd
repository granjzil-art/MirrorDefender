## Deterministic A* over the serialized road-cell network for one target base.
class_name PathNetworkAStarStrategy
extends "res://scripts/path/IAutoRouteStrategy.gd"


func find_route(
	grid: GridManager,
	tile_manager: TileManager,
	start: Vector3i,
	goal: Vector3i,
	allowed_cells: Dictionary,
	target: Node = null
) -> Array[Vector3i]:
	if grid == null or tile_manager == null or start == goal:
		return []
	if not allowed_cells.has(start) or not allowed_cells.has(goal):
		return []
	var open: Array[Vector3i] = [start]
	var open_lookup: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var distance_from_start: Dictionary = {start: 0}
	while not open.is_empty():
		var current := _select_best(open, distance_from_start, goal, grid)
		if current == goal:
			return _reconstruct(came_from, current)
		open.erase(current)
		open_lookup.erase(current)
		for neighbor in grid.get_neighbors(current):
			if not allowed_cells.has(neighbor):
				continue
			if neighbor != goal and not tile_manager.can_use_for_reroute(neighbor, target):
				continue
			if neighbor == goal and tile_manager.blocks_enemy_navigation(neighbor, target):
				continue
			var tentative_distance := int(distance_from_start[current]) + 1
			var known_distance := int(distance_from_start.get(neighbor, 2147483647))
			if tentative_distance >= known_distance:
				continue
			came_from[neighbor] = current
			distance_from_start[neighbor] = tentative_distance
			if not open_lookup.has(neighbor):
				open.append(neighbor)
				open_lookup[neighbor] = true
	return []


func _select_best(
	open: Array[Vector3i],
	distance_from_start: Dictionary,
	goal: Vector3i,
	grid: GridManager
) -> Vector3i:
	var best := open[0]
	var best_distance := int(distance_from_start[best])
	var best_heuristic := grid.distance(best, goal)
	var best_score := best_distance + best_heuristic
	for index in range(1, open.size()):
		var candidate: Vector3i = open[index]
		var candidate_distance := int(distance_from_start[candidate])
		var candidate_heuristic := grid.distance(candidate, goal)
		var candidate_score := candidate_distance + candidate_heuristic
		if candidate_score < best_score or (
			candidate_score == best_score and candidate_heuristic < best_heuristic
		) or (
			candidate_score == best_score
			and candidate_heuristic == best_heuristic
			and _cell_key(candidate) < _cell_key(best)
		):
			best = candidate
			best_distance = candidate_distance
			best_heuristic = candidate_heuristic
			best_score = candidate_score
	return best


func _reconstruct(came_from: Dictionary, end: Vector3i) -> Array[Vector3i]:
	var reversed: Array[Vector3i] = [end]
	var current := end
	while came_from.has(current):
		current = came_from[current]
		reversed.append(current)
	reversed.reverse()
	return reversed


func _cell_key(cell: Vector3i) -> String:
	return "%+011d,%+011d,%+011d" % [cell.x, cell.y, cell.z]
