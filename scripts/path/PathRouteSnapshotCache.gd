## Shared ground-route cache for whole-path runtime visualization and detours.
class_name PathRouteSnapshotCache
extends RefCounted

var _records: Dictionary = {}
var _snapshot: Dictionary = {}
var _signature: String = "__uninitialized__"


func reset() -> void:
	_records.clear()
	_snapshot.clear()
	_signature = "__uninitialized__"


## Rebuilds every authored path from one navigation snapshot. Returns true
## only when effective route cells changed and visual consumers must rebuild.
func refresh(
	level: LevelResource,
	tile_manager: TileManager,
	detour_resolver: Callable,
	target: Node = null
) -> bool:
	var next_records: Dictionary = {}
	var next_snapshot: Dictionary = {}
	if level != null and tile_manager != null and detour_resolver.is_valid():
		for path in level.paths:
			if path == null or path.path_id.is_empty():
				continue
			var record := _build_route_record(path, tile_manager, detour_resolver, target)
			next_records[path.path_id] = record
			var effective_cells: Array = record.get("effective_cells", [])
			next_snapshot[path.path_id] = effective_cells.duplicate()
	_records = next_records
	_snapshot = next_snapshot
	var next_signature := _make_signature(level, next_snapshot)
	if next_signature == _signature:
		return false
	_signature = next_signature
	return true


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_effective_cells(path: PathDefinition) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if path == null:
		return cells
	var source: Array = _snapshot.get(path.path_id, path.cells)
	for value in source:
		if value is Vector3i:
			cells.append(value)
	return cells


func get_cached_detour(
	current_path: PathDefinition,
	current_cell: Vector3i,
	blocked_cell: Vector3i
) -> Dictionary:
	if current_path == null or not _records.has(current_path.path_id):
		return {}
	var record: Dictionary = _records[current_path.path_id]
	if (
		not bool(record.get("triggered", false))
		or record.get("trigger_cell", Vector3i.ZERO) != current_cell
		or record.get("blocked_cell", Vector3i.ZERO) != blocked_cell
	):
		return {}
	return {
		"triggered": true,
		"found": bool(record.get("found", false)),
		"path": record.get("path"),
		"cells": (record.get("route_cells", []) as Array).duplicate(),
		"cost": int(record.get("cost", -1)),
		"join_cell": record.get("join_cell", Vector3i.ZERO),
		"blocker": null,
		"route_source": record.get("route_source", &""),
		"target_base_id": record.get("target_base_id", &""),
	}


func _build_route_record(
	path: PathDefinition,
	tile_manager: TileManager,
	detour_resolver: Callable,
	target: Node
) -> Dictionary:
	var effective_cells: Array[Vector3i] = []
	effective_cells.append_array(path.cells)
	var record := {
		"trigger_cell": Vector3i.ZERO,
		"blocked_cell": Vector3i.ZERO,
		"triggered": false,
		"found": false,
		"path": null,
		"route_cells": [],
		"cost": -1,
		"join_cell": Vector3i.ZERO,
		"route_source": &"",
		"target_base_id": &"",
		"effective_cells": effective_cells,
	}
	for index in range(path.cells.size() - 1):
		var blocked_cell: Vector3i = path.cells[index + 1]
		if not tile_manager.blocks_enemy_navigation(blocked_cell, target):
			continue
		var trigger_cell: Vector3i = path.cells[index]
		var resolved: Variant = detour_resolver.call(path, trigger_cell, blocked_cell, target)
		var resolution: Dictionary = resolved if resolved is Dictionary else {}
		record["trigger_cell"] = trigger_cell
		record["blocked_cell"] = blocked_cell
		record["triggered"] = true
		record["found"] = bool(resolution.get("found", false))
		record["path"] = resolution.get("path")
		record["route_cells"] = (resolution.get("cells", []) as Array).duplicate()
		record["cost"] = int(resolution.get("cost", -1))
		record["join_cell"] = resolution.get("join_cell", Vector3i.ZERO)
		record["route_source"] = resolution.get("route_source", &"")
		record["target_base_id"] = resolution.get("target_base_id", &"")
		if bool(record["found"]):
			var bent_cells: Array[Vector3i] = []
			for prefix_index in range(index + 1):
				bent_cells.append(path.cells[prefix_index])
			var route_cells: Array = record["route_cells"]
			for route_index in range(1, route_cells.size()):
				var route_cell: Variant = route_cells[route_index]
				if route_cell is Vector3i:
					bent_cells.append(route_cell)
			record["effective_cells"] = bent_cells
		break
	return record


func _make_signature(level: LevelResource, snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	if level == null:
		return ""
	for path in level.paths:
		if path == null or not snapshot.has(path.path_id):
			continue
		parts.append(String(path.path_id))
		var cells: Array = snapshot[path.path_id]
		for value in cells:
			if value is Vector3i:
				var cell: Vector3i = value
				parts.append("%d,%d,%d" % [cell.x, cell.y, cell.z])
		parts.append(";")
	return "|".join(parts)
