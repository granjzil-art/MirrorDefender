## Transactional runtime authoring session for Terrain, ramps and Stuff.
##
## Preview state is applied to TerrainManager for exact visual feedback but is
## never added to history until commit_terrain_preview() succeeds.
class_name RuntimeStuffEditSession
extends Node

const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")
const BuildingPlacementDataScript := preload("res://scripts/building/BuildingPlacementData.gd")
const MirrorPlacementDataScript := preload("res://scripts/mirror/MirrorPlacementData.gd")
const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")
const RuntimeTerrainEditServiceScript := preload("res://scripts/terrain/RuntimeTerrainEditService.gd")
const CANONICAL_TERRAIN_CONTENT_VERSION: int = 2

signal session_started(level: LevelResource, source_path: String)
signal session_changed(dirty: bool)
signal session_saved(path: String)
signal session_ended(saved: bool)
signal operation_failed(reason: String, warning: bool)

var _stuff_manager: StuffManager
var _validator: StuffPlacementValidatorScript
var _route_refresh: Callable
var _building_snapshot_provider: Callable
var _mirror_snapshot_provider: Callable
var _terrain_manager: TerrainManagerScript
var _world_refresh: Callable
var _level: LevelResource
var _source_path: String = ""
var _original_snapshot: Dictionary = {}
var _current_snapshot: Dictionary = {}
var _terrain_preview_snapshot: Dictionary = {}
var _terrain_preview_result: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _active: bool = false
var _dirty: bool = false


func configure(
	stuff_manager: StuffManager,
	validator: StuffPlacementValidatorScript,
	route_refresh: Callable = Callable(),
	building_snapshot_provider: Callable = Callable(),
	mirror_snapshot_provider: Callable = Callable(),
	terrain_manager: TerrainManagerScript = null,
	world_refresh: Callable = Callable()
) -> void:
	_stuff_manager = stuff_manager
	_validator = validator
	_route_refresh = route_refresh
	_building_snapshot_provider = building_snapshot_provider
	_mirror_snapshot_provider = mirror_snapshot_provider
	_terrain_manager = terrain_manager
	_world_refresh = world_refresh


func begin(level: LevelResource, source_path: String = "") -> bool:
	if _active or level == null or _stuff_manager == null or _validator == null:
		return false
	_level = level
	_source_path = source_path if not source_path.is_empty() else level.resource_path
	_current_snapshot = _capture_runtime_snapshot()
	_original_snapshot = _duplicate_snapshot(_current_snapshot)
	_terrain_preview_snapshot.clear()
	_terrain_preview_result.clear()
	_undo_stack.clear()
	_redo_stack.clear()
	_active = true
	_set_dirty(false)
	session_started.emit(level, _source_path)
	return true


func is_active() -> bool:
	return _active


func is_dirty() -> bool:
	return _dirty


func has_terrain_changes() -> bool:
	return _active and not _terrain_equal(_current_snapshot, _original_snapshot)


func has_terrain_preview() -> bool:
	return not _terrain_preview_snapshot.is_empty()


func can_undo() -> bool:
	return _active and not _undo_stack.is_empty()


func can_redo() -> bool:
	return _active and not _redo_stack.is_empty()


func validate_placement(
	cell: Vector3i,
	definition: StuffDefinition,
	facing_index: int = 0
) -> Dictionary:
	if not _active:
		return {"valid": false, "warning": false, "reason": "运行时关卡编辑尚未开启"}
	return _validator.validate_placement(cell, definition, facing_index)


func place_stuff(
	cell: Vector3i,
	definition: StuffDefinition,
	facing_index: int = 0,
	allow_warning: bool = false
) -> StuffRuntime:
	clear_terrain_preview()
	if not _active:
		_fail("运行时关卡编辑尚未开启", false)
		return null
	var validation := _validator.validate_placement(cell, definition, facing_index)
	if not bool(validation.get("valid", false)):
		_fail(str(validation.get("reason", "放置失败")), false)
		return null
	if bool(validation.get("warning", false)) and not allow_warning:
		_fail(str(validation.get("reason", "该放置会导致路径不可达")), true)
		return null
	var before := _duplicate_snapshot(_current_snapshot)
	var runtime := _stuff_manager.add_stuff(cell, definition, facing_index)
	if runtime == null:
		_fail("关卡元素运行时拒绝放置", false)
		return null
	_record_success(before)
	return runtime


func remove_stuff(placement_id: StringName) -> bool:
	clear_terrain_preview()
	if not _active or _stuff_manager.get_stuff(placement_id) == null:
		return false
	var before := _duplicate_snapshot(_current_snapshot)
	if not _stuff_manager.remove_stuff(placement_id):
		return false
	_record_success(before)
	return true


func rotate_stuff(placement_id: StringName, step: int = 1) -> bool:
	clear_terrain_preview()
	if not _active or _stuff_manager.get_stuff(placement_id) == null:
		return false
	var before := _duplicate_snapshot(_current_snapshot)
	if not _stuff_manager.rotate_stuff(placement_id, step):
		return false
	_record_success(before)
	return true


## Applies an exact candidate to TerrainManager for hover/rotation preview.
## Returns `{success, message, ramp_id}`; failed candidates leave the committed
## runtime state visible.
func preview_terrain_change(operation: StringName, parameters: Dictionary) -> Dictionary:
	if not _active or _terrain_manager == null:
		return _save_result(false, "", "运行时地形编辑尚未启用")
	clear_terrain_preview()
	var candidate_result := _build_terrain_candidate(operation, parameters)
	if not bool(candidate_result.get("success", false)):
		_terrain_preview_result = candidate_result.duplicate()
		return candidate_result
	var candidate_snapshot: Dictionary = candidate_result.get("snapshot", {})
	if not _terrain_manager.replace_runtime_content(
		candidate_snapshot.get("grid_cells", []),
		candidate_snapshot.get("ramp_placements", [])
	):
		return {"success": false, "message": "TerrainManager 拒绝预览候选", "ramp_id": &""}
	_terrain_preview_snapshot = _duplicate_snapshot(candidate_snapshot)
	_terrain_preview_result = candidate_result.duplicate()
	_refresh_world()
	return candidate_result


func get_terrain_preview_result() -> Dictionary:
	return _terrain_preview_result.duplicate()


func clear_terrain_preview() -> void:
	if _terrain_preview_snapshot.is_empty():
		_terrain_preview_result.clear()
		return
	_terrain_preview_snapshot.clear()
	_terrain_preview_result.clear()
	if _terrain_manager != null:
		_terrain_manager.replace_runtime_content(
			_current_snapshot.get("grid_cells", []),
			_current_snapshot.get("ramp_placements", [])
		)
		_refresh_world()


func commit_terrain_preview() -> Dictionary:
	if not _active or _terrain_preview_snapshot.is_empty():
		return {"success": false, "message": "没有可提交的地形预览", "ramp_id": &""}
	var before := _duplicate_snapshot(_current_snapshot)
	_current_snapshot = _duplicate_snapshot(_terrain_preview_snapshot)
	var result := _terrain_preview_result.duplicate()
	_terrain_preview_snapshot.clear()
	_terrain_preview_result.clear()
	if not _snapshots_equal(before, _current_snapshot):
		_record_snapshot_success(before)
	return result


## Commits one non-hover terrain operation, used by selected ramp rotation,
## terrain override changes and deletion.
func apply_terrain_change(operation: StringName, parameters: Dictionary) -> Dictionary:
	clear_terrain_preview()
	if not _active or _terrain_manager == null:
		return {"success": false, "message": "运行时地形编辑尚未启用", "ramp_id": &""}
	var candidate_result := _build_terrain_candidate(operation, parameters)
	if not bool(candidate_result.get("success", false)):
		return candidate_result
	var candidate_snapshot: Dictionary = candidate_result.get("snapshot", {})
	if not _terrain_manager.replace_runtime_content(
		candidate_snapshot.get("grid_cells", []),
		candidate_snapshot.get("ramp_placements", [])
	):
		return {"success": false, "message": "TerrainManager 拒绝地形修改", "ramp_id": &""}
	var before := _duplicate_snapshot(_current_snapshot)
	_current_snapshot = _duplicate_snapshot(candidate_snapshot)
	_record_snapshot_success(before)
	_refresh_world()
	return candidate_result


func undo() -> bool:
	clear_terrain_preview()
	if not can_undo():
		return false
	var previous: Dictionary = _undo_stack.pop_back()
	var current := _duplicate_snapshot(_current_snapshot)
	if not _apply_snapshot(previous):
		_undo_stack.append(previous)
		return false
	_redo_stack.append(current)
	_current_snapshot = _duplicate_snapshot(previous)
	_update_dirty()
	return true


func redo() -> bool:
	clear_terrain_preview()
	if not can_redo():
		return false
	var next: Dictionary = _redo_stack.pop_back()
	var current := _duplicate_snapshot(_current_snapshot)
	if not _apply_snapshot(next):
		_redo_stack.append(next)
		return false
	_undo_stack.append(current)
	_current_snapshot = _duplicate_snapshot(next)
	_update_dirty()
	return true


func can_save_full_layout() -> bool:
	return (
		_building_snapshot_provider.is_valid()
		and _mirror_snapshot_provider.is_valid()
	)


func save(destination_path: String = "", include_initial_layout: bool = false) -> Dictionary:
	clear_terrain_preview()
	if not _active or _level == null:
		return _save_result(false, "", "运行时关卡编辑尚未开启")
	if include_initial_layout and not can_save_full_layout():
		return _save_result(false, "", "全量保存尚未注入建筑与镜子快照")
	if not include_initial_layout and not _terrain_equal(_current_snapshot, _original_snapshot):
		return _save_result(false, "", "存在地形或斜坡修改，请使用“全量保存”")
	var target_path := _resolve_save_path(destination_path)
	if target_path.is_empty():
		return _save_result(false, "", "无法确定关卡保存路径")
	var save_copy := _level.duplicate(true) as LevelResource
	if save_copy == null:
		return _save_result(false, target_path, "无法创建关卡保存副本")
	save_copy.stuff_placements.assign(_duplicate_placements(_current_snapshot.get("stuff_placements", [])))
	if include_initial_layout:
		save_copy.terrain_content_version = CANONICAL_TERRAIN_CONTENT_VERSION
		save_copy.tiles = []
		save_copy.grid_cells.assign(_duplicate_grid_cells(_current_snapshot.get("grid_cells", [])))
		save_copy.ramp_placements.assign(_duplicate_ramps(_current_snapshot.get("ramp_placements", [])))
		var raw_buildings: Variant = _building_snapshot_provider.call()
		var raw_mirrors: Variant = _mirror_snapshot_provider.call()
		if not raw_buildings is Array or not raw_mirrors is Array:
			return _save_result(false, target_path, "建筑或镜子快照类型无效")
		save_copy.initial_building_placements.assign(_duplicate_building_placements(raw_buildings))
		save_copy.initial_mirror_placements.assign(_duplicate_mirror_placements(raw_mirrors))
	var errors := save_copy.validate_runtime()
	if not errors.is_empty():
		return _save_result(false, target_path, "关卡校验失败：\n%s" % "\n".join(errors))
	if target_path.begins_with("user://"):
		var absolute_dir := ProjectSettings.globalize_path(target_path.get_base_dir())
		var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			return _save_result(false, target_path, "无法创建运行时关卡目录")
	var save_error := ResourceSaver.save(save_copy, target_path)
	if save_error != OK:
		return _save_result(false, target_path, "保存失败，错误码 %d" % save_error)
	_level.stuff_placements.assign(_duplicate_placements(_current_snapshot.get("stuff_placements", [])))
	if include_initial_layout:
		_level.terrain_content_version = CANONICAL_TERRAIN_CONTENT_VERSION
		_level.tiles = []
		_level.grid_cells.assign(_duplicate_grid_cells(_current_snapshot.get("grid_cells", [])))
		_level.ramp_placements.assign(_duplicate_ramps(_current_snapshot.get("ramp_placements", [])))
		_level.initial_building_placements.assign(_duplicate_building_placements(save_copy.initial_building_placements))
		_level.initial_mirror_placements.assign(_duplicate_mirror_placements(save_copy.initial_mirror_placements))
	_level.emit_changed()
	_original_snapshot = _duplicate_snapshot(_current_snapshot)
	_undo_stack.clear()
	_redo_stack.clear()
	_set_dirty(false)
	session_saved.emit(target_path)
	var message := "已全量保存地形、斜坡、元素和初始陈列：%s" % target_path if include_initial_layout else "已保存关卡元素：%s" % target_path
	return _save_result(true, target_path, message)


func discard_and_end() -> bool:
	if not _active:
		return false
	clear_terrain_preview()
	if not _apply_snapshot(_original_snapshot):
		return false
	_finish(false)
	return true


func end_after_save() -> bool:
	if not _active or _dirty:
		return false
	_finish(true)
	return true


func end_clean() -> bool:
	if not _active or _dirty:
		return false
	_finish(false)
	return true


## LevelLoader already committed another level; never restore the old snapshot.
func abort_for_level_transition() -> void:
	if _active:
		_terrain_preview_snapshot.clear()
		_finish(false)


func get_source_path() -> String:
	return _source_path


func get_default_save_path() -> String:
	return _resolve_save_path("")


func _build_terrain_candidate(operation: StringName, parameters: Dictionary) -> Dictionary:
	var document := _level.duplicate(true) as LevelResource
	if document == null:
		return {"success": false, "message": "无法创建地形候选副本", "ramp_id": &""}
	document.grid_cells.assign(_duplicate_grid_cells(_current_snapshot.get("grid_cells", [])))
	document.ramp_placements.assign(_duplicate_ramps(_current_snapshot.get("ramp_placements", [])))
	document.stuff_placements.assign(_duplicate_placements(_current_snapshot.get("stuff_placements", [])))
	document.terrain_content_version = CANONICAL_TERRAIN_CONTENT_VERSION
	document.tiles = []
	var shape := _terrain_manager.get_grid_shape() if _terrain_manager != null else null
	if shape == null:
		return {"success": false, "message": "运行时网格形状无效", "ramp_id": &""}
	var result: Dictionary
	match operation:
		&"paint_terrain":
			result = RuntimeTerrainEditServiceScript.paint_terrain(document, shape, parameters.get("cell", Vector3i.ZERO), parameters.get("terrain") as TerrainDefinition)
		&"paint_layer":
			result = RuntimeTerrainEditServiceScript.paint_layer(document, shape, parameters.get("cell", Vector3i.ZERO), int(parameters.get("layer_count", 1)))
		&"place_ramp":
			result = RuntimeTerrainEditServiceScript.place_ramp(
				document,
				shape,
				parameters.get("cell", Vector3i.ZERO),
				int(parameters.get("facing_index", 0)),
				int(parameters.get("run_length", 1)),
				int(parameters.get("base_layer", 1)),
				parameters.get("terrain_override") as TerrainDefinition
			)
		&"rotate_ramp":
			result = RuntimeTerrainEditServiceScript.rotate_ramp(document, shape, parameters.get("ramp_id", &""), int(parameters.get("step", 1)))
		&"remove_ramp":
			result = RuntimeTerrainEditServiceScript.remove_ramp(document, parameters.get("ramp_id", &""))
		&"set_ramp_terrain":
			result = RuntimeTerrainEditServiceScript.set_ramp_terrain(document, parameters.get("ramp_id", &""), parameters.get("terrain_override") as TerrainDefinition)
		_:
			return {"success": false, "message": "未知地形编辑操作：%s" % String(operation), "ramp_id": &""}
	if not bool(result.get("success", false)):
		return result
	var validation_errors := document.validate_runtime()
	if not validation_errors.is_empty():
		return {
			"success": false,
			"message": "该修改会产生非法地形：\n%s" % "\n".join(validation_errors),
			"ramp_id": result.get("ramp_id", &""),
		}
	var snapshot := _duplicate_snapshot(_current_snapshot)
	snapshot["grid_cells"] = _duplicate_grid_cells(document.grid_cells)
	snapshot["ramp_placements"] = _duplicate_ramps(document.ramp_placements)
	result["snapshot"] = snapshot
	return result


func _record_success(before: Dictionary) -> void:
	_current_snapshot = _capture_runtime_snapshot()
	_record_snapshot_success(before)
	_refresh_world()


func _record_snapshot_success(before: Dictionary) -> void:
	_undo_stack.append(_duplicate_snapshot(before))
	_redo_stack.clear()
	_update_dirty()


func _apply_snapshot(snapshot: Dictionary) -> bool:
	var rollback_grid: Array = _terrain_manager.export_grid_cells() if _terrain_manager != null else []
	var rollback_ramps: Array = _terrain_manager.export_ramp_placements() if _terrain_manager != null else []
	if _terrain_manager != null and not _terrain_manager.replace_runtime_content(
		snapshot.get("grid_cells", []),
		snapshot.get("ramp_placements", [])
	):
		return false
	if not _stuff_manager.replace_runtime_placements(snapshot.get("stuff_placements", [])):
		if _terrain_manager != null:
			_terrain_manager.replace_runtime_content(rollback_grid, rollback_ramps)
		return false
	_refresh_world()
	return true


func _capture_runtime_snapshot() -> Dictionary:
	return {
		"grid_cells": _terrain_manager.export_grid_cells() if _terrain_manager != null else _duplicate_grid_cells(_level.grid_cells if _level != null else []),
		"ramp_placements": _terrain_manager.export_ramp_placements() if _terrain_manager != null else _duplicate_ramps(_level.ramp_placements if _level != null else []),
		"stuff_placements": _duplicate_placements(_stuff_manager.export_placements() if _stuff_manager != null else []),
	}


func _finish(saved: bool) -> void:
	_active = false
	_level = null
	_source_path = ""
	_original_snapshot.clear()
	_current_snapshot.clear()
	_terrain_preview_snapshot.clear()
	_terrain_preview_result.clear()
	_undo_stack.clear()
	_redo_stack.clear()
	_set_dirty(false)
	session_ended.emit(saved)


func _update_dirty() -> void:
	_set_dirty(not _snapshots_equal(_current_snapshot, _original_snapshot))


func _set_dirty(value: bool) -> void:
	if _dirty == value:
		return
	_dirty = value
	session_changed.emit(_dirty)


func _fail(reason: String, warning: bool) -> void:
	operation_failed.emit(reason, warning)


func _refresh_world() -> void:
	if _world_refresh.is_valid():
		_world_refresh.call()
	elif _route_refresh.is_valid():
		_route_refresh.call()


func _resolve_save_path(requested: String) -> String:
	var normalized := requested.strip_edges()
	if not normalized.is_empty():
		return normalized if normalized.ends_with(".tres") else ""
	if OS.has_feature("editor") and _source_path.begins_with("res://") and _source_path.ends_with(".tres"):
		return _source_path
	var filename := _source_path.get_file()
	if filename.is_empty() or not filename.ends_with(".tres"):
		filename = "%s.tres" % _safe_filename(_level.display_name if _level != null else "runtime_level")
	return "user://levels/%s" % filename


func _safe_filename(value: String) -> String:
	var result := value.strip_edges().to_snake_case()
	return result if not result.is_empty() else "runtime_level"


func _duplicate_snapshot(source: Dictionary) -> Dictionary:
	return {
		"grid_cells": _duplicate_grid_cells(source.get("grid_cells", [])),
		"ramp_placements": _duplicate_ramps(source.get("ramp_placements", [])),
		"stuff_placements": _duplicate_placements(source.get("stuff_placements", [])),
	}


func _duplicate_grid_cells(source: Array) -> Array[GridCellData]:
	var result: Array[GridCellData] = []
	for raw_cell in source:
		if not raw_cell is GridCellDataScript:
			continue
		var clone := GridCellDataScript.new()
		clone.configure(raw_cell.cell, raw_cell.terrain, raw_cell.layer_count, raw_cell.allows_tile_building, raw_cell.allows_edge_building)
		result.append(clone)
	return result


func _duplicate_ramps(source: Array) -> Array[RampPlacementData]:
	var result: Array[RampPlacementData] = []
	for raw_ramp in source:
		if not raw_ramp is RampPlacementDataScript:
			continue
		var clone := RampPlacementDataScript.new()
		clone.ramp_id = raw_ramp.ramp_id
		clone.anchor_cell = raw_ramp.anchor_cell
		clone.facing_index = raw_ramp.facing_index
		clone.run_length = raw_ramp.run_length
		clone.base_layer = raw_ramp.base_layer
		clone.terrain_override = raw_ramp.terrain_override
		result.append(clone)
	return result


func _duplicate_placements(source: Array) -> Array[StuffPlacementData]:
	var result: Array[StuffPlacementData] = []
	for raw_placement in source:
		if not raw_placement is StuffPlacementDataScript:
			continue
		var clone := StuffPlacementDataScript.new()
		clone.configure(raw_placement.placement_id, raw_placement.cell, raw_placement.definition, raw_placement.facing_index)
		result.append(clone)
	return result


func _duplicate_building_placements(source: Array) -> Array[BuildingPlacementData]:
	var result: Array[BuildingPlacementData] = []
	for raw_placement in source:
		if raw_placement is BuildingPlacementDataScript:
			result.append(raw_placement.duplicate_placement())
	return result


func _duplicate_mirror_placements(source: Array) -> Array[MirrorPlacementData]:
	var result: Array[MirrorPlacementData] = []
	for raw_placement in source:
		if raw_placement is MirrorPlacementDataScript:
			result.append(raw_placement.duplicate_placement())
	return result


func _snapshots_equal(first: Dictionary, second: Dictionary) -> bool:
	return (
		_terrain_equal(first, second)
		and _placement_keys(first.get("stuff_placements", [])) == _placement_keys(second.get("stuff_placements", []))
	)


func _terrain_equal(first: Dictionary, second: Dictionary) -> bool:
	return (
		_grid_cell_keys(first.get("grid_cells", [])) == _grid_cell_keys(second.get("grid_cells", []))
		and _ramp_keys(first.get("ramp_placements", [])) == _ramp_keys(second.get("ramp_placements", []))
	)


func _grid_cell_keys(source: Array) -> Array[String]:
	var keys: Array[String] = []
	for raw_cell in source:
		if raw_cell is GridCellDataScript:
			keys.append("%s|%s|%d|%s|%s" % [str(raw_cell.cell), raw_cell.terrain.resource_path if raw_cell.terrain != null else "", raw_cell.layer_count, raw_cell.allows_tile_building, raw_cell.allows_edge_building])
	keys.sort()
	return keys


func _ramp_keys(source: Array) -> Array[String]:
	var keys: Array[String] = []
	for raw_ramp in source:
		if raw_ramp is RampPlacementDataScript:
			keys.append("%s|%s|%d|%d|%d|%s" % [raw_ramp.ramp_id, str(raw_ramp.anchor_cell), raw_ramp.facing_index, raw_ramp.run_length, raw_ramp.base_layer, raw_ramp.terrain_override.resource_path if raw_ramp.terrain_override != null else ""])
	keys.sort()
	return keys


func _placement_keys(source: Array) -> Array[String]:
	var keys: Array[String] = []
	for raw_placement in source:
		if raw_placement is StuffPlacementDataScript:
			keys.append("%s|%s|%s|%d" % [raw_placement.placement_id, str(raw_placement.cell), raw_placement.definition.resource_path if raw_placement.definition != null else "", raw_placement.facing_index])
	keys.sort()
	return keys


func _save_result(success: bool, path: String, message: String) -> Dictionary:
	return {"success": success, "path": path, "message": message}
