## Signal-driven M6 selection adapter for the read-only tile inspector.
##
## Model construction lives in TileInspectionModelBuilder. This node owns only
## selection state, dependency subscriptions, and refresh scheduling.
class_name TileInspectionService
extends Node

const TileInspectionModelBuilderScript := preload("res://scripts/ui/TileInspectionModelBuilder.gd")
const DYNAMIC_SIGNAL_NAMES := [
	&"durability_changed",
	&"facing_changed",
	&"level_changed",
	&"side_changed",
	&"tree_exited",
]

signal inspection_changed(model: Dictionary)

var _grid: GridManager
var _tile_manager: TileManager
var _building_manager: BuildingManager
var _mirror_manager: MirrorManager
var _tile_effect_system: TileEffectSystem
var _model_builder: TileInspectionModelBuilderScript = TileInspectionModelBuilderScript.new()
var _has_selected_cell: bool = false
var _selected_cell: Vector3i = Vector3i.ZERO
var _selected_edge_id: String = ""
var _dependency_connections: Array[Dictionary] = []
var _dynamic_connections: Array[Dictionary] = []
var _refresh_queued: bool = false


func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	tile_effect_system: TileEffectSystem
) -> void:
	_disconnect_records(_dependency_connections)
	_disconnect_records(_dynamic_connections)
	_grid = grid_manager
	_tile_manager = tile_manager
	_building_manager = building_manager
	_mirror_manager = mirror_manager
	_tile_effect_system = tile_effect_system
	_model_builder.configure(_grid, _tile_manager, _building_manager, _mirror_manager, _tile_effect_system)
	_connect_dependency(_tile_manager, &"tile_changed")
	_connect_dependency(_tile_manager, &"occupant_changed")
	_connect_dependency(_tile_manager, &"obstacle_durability_changed")
	_connect_dependency(_tile_manager, &"level_loaded")
	_connect_dependency(_building_manager, &"building_placed")
	_connect_dependency(_building_manager, &"building_removed")
	_connect_dependency(_building_manager, &"building_upgraded")
	_connect_dependency(_mirror_manager, &"mirror_placed")
	_connect_dependency(_mirror_manager, &"mirror_removed")
	_connect_dependency(_mirror_manager, &"mirror_changed")
	_connect_dependency(_mirror_manager, &"projections_rebuilt")
	_connect_dependency(_tile_effect_system, &"effect_visual_state_changed")
	_refresh_selected()


func set_selected_cell(has_cell: bool, cell: Vector3i, edge_id: String = "") -> void:
	_has_selected_cell = has_cell
	_selected_cell = cell if has_cell else Vector3i.ZERO
	_selected_edge_id = edge_id if has_cell else ""
	_refresh_selected()


func clear_selection() -> void:
	set_selected_cell(false, Vector3i.ZERO, "")


func has_selected_cell() -> bool:
	return _has_selected_cell


func get_selected_cell() -> Vector3i:
	return _selected_cell


## Delegates to the pure builder and returns the stable inspection Dictionary.
func inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary:
	return _model_builder.inspect_cell(cell, selected_edge_id)


func _refresh_selected() -> void:
	_refresh_queued = false
	_disconnect_records(_dynamic_connections)
	if not _has_selected_cell:
		inspection_changed.emit(_model_builder.empty_model())
		return
	var model := inspect_cell(_selected_cell, _selected_edge_id)
	_connect_dynamic_sources(_selected_cell)
	inspection_changed.emit(model)


func _connect_dynamic_sources(cell: Vector3i) -> void:
	var unique_sources: Dictionary = {}
	var occupant: Node = _tile_manager.get_occupant(cell) if _tile_manager != null else null
	_add_dynamic_source(unique_sources, occupant)
	var obstacle: Node = _tile_manager.get_runtime_obstacle(cell) if _tile_manager != null else null
	_add_dynamic_source(unique_sources, obstacle)
	if _grid != null:
		for edge_index in range(_grid.edge_count()):
			var edge_id := _grid.canonical_edge_id(cell, edge_index)
			_add_dynamic_source(unique_sources, _building_manager.get_edge_building(edge_id) if _building_manager != null else null)
			_add_dynamic_source(unique_sources, _mirror_manager.get_mirror(edge_id) if _mirror_manager != null else null)
	if _mirror_manager != null:
		for projection in _mirror_manager.get_projections(cell):
			if projection.payload != null:
				_add_dynamic_source(unique_sources, projection.payload.root_source)
	for raw_source in unique_sources.values():
		var source: Object = raw_source
		for signal_name in DYNAMIC_SIGNAL_NAMES:
			_connect_record(source, signal_name, _dynamic_connections)


func _add_dynamic_source(unique_sources: Dictionary, source: Object) -> void:
	if source != null and is_instance_valid(source):
		unique_sources[source.get_instance_id()] = source


func _connect_dependency(source: Object, signal_name: StringName) -> void:
	_connect_record(source, signal_name, _dependency_connections)


func _connect_record(source: Object, signal_name: StringName, records: Array[Dictionary]) -> void:
	if source == null or not is_instance_valid(source) or not source.has_signal(signal_name):
		return
	var callback := Callable(self, "_on_dependency_changed")
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)
	records.append({"source": source, "signal": signal_name, "callback": callback})


func _disconnect_records(records: Array[Dictionary]) -> void:
	for record in records:
		var source: Object = record.get("source")
		var signal_name: StringName = record.get("signal", &"")
		var callback: Callable = record.get("callback", Callable())
		if source != null and is_instance_valid(source) and source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)
	records.clear()


func _on_dependency_changed(
	_value_a: Variant = null,
	_value_b: Variant = null,
	_value_c: Variant = null,
	_value_d: Variant = null
) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_selected")
