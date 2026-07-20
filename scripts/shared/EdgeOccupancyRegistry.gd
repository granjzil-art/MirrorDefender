## Shared physical-edge occupancy for every runtime edge building.
class_name EdgeOccupancyRegistry
extends RefCounted

signal occupancy_changed(edge_id: String, occupant: Object)

var _occupants: Dictionary = {}

func try_register(edge_id: String, occupant: Object) -> bool:
	if edge_id.is_empty() or occupant == null or get_occupant(edge_id) != null:
		return false
	_occupants[edge_id] = occupant
	occupancy_changed.emit(edge_id, occupant)
	return true

func unregister(edge_id: String, expected_occupant: Object = null) -> bool:
	var occupant := get_occupant(edge_id)
	if occupant == null or (expected_occupant != null and occupant != expected_occupant):
		return false
	_occupants.erase(edge_id)
	occupancy_changed.emit(edge_id, null)
	return true

func get_occupant(edge_id: String) -> Object:
	if edge_id.is_empty() or not _occupants.has(edge_id):
		return null
	var occupant: Object = _occupants[edge_id]
	if occupant == null or not is_instance_valid(occupant):
		_occupants.erase(edge_id)
		return null
	return occupant

func is_occupied(edge_id: String) -> bool:
	return get_occupant(edge_id) != null

func clear() -> void:
	var occupied_ids := _occupants.keys()
	_occupants.clear()
	for raw_id in occupied_ids:
		occupancy_changed.emit(str(raw_id), null)
