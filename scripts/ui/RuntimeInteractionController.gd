## Runtime interaction state machine for the production HUD.
##
## One selected card owns exactly one world placement attempt. Every success or
## failure returns to SELECT and clears previews plus entity selection.
class_name RuntimeInteractionController
extends Node

enum Mode {
	SELECT,
	PLACE_BLOCK_BUILDING,
	PLACE_EDGE_BUILDING,
	PLACE_COPY_MIRROR,
}

signal mode_changed(mode: Mode)
signal placement_resolved(success: bool, reason: String)
signal status_changed(message: String)

var _building_manager: BuildingManager
var _mirror_manager: MirrorManager
var _mode: Mode = Mode.SELECT
var _selected_definition: BuildingDefinition
var _last_failure_reason: String = ""


func configure(building_manager: BuildingManager, mirror_manager: MirrorManager) -> void:
	_disconnect_managers()
	_building_manager = building_manager
	_mirror_manager = mirror_manager
	if _building_manager != null:
		_building_manager.placement_failed.connect(_on_placement_failed)
	if _mirror_manager != null:
		_mirror_manager.placement_failed.connect(_on_mirror_placement_failed)
	cancel_to_select(false)


func get_mode() -> Mode:
	return _mode


func is_select_mode() -> bool:
	return _mode == Mode.SELECT


func is_copy_mirror_mode() -> bool:
	return _mode == Mode.PLACE_COPY_MIRROR


func get_selected_definition() -> BuildingDefinition:
	return _selected_definition


func select_building_card(definition: BuildingDefinition) -> bool:
	if definition == null or _building_manager == null:
		return false
	_clear_world_selection()
	_selected_definition = definition
	_set_mode(
		Mode.PLACE_EDGE_BUILDING
		if definition.is_edge_building()
		else Mode.PLACE_BLOCK_BUILDING
	)
	status_changed.emit("选择 %s：左键放置，右键取消" % definition.display_name)
	return true


func select_copy_mirror_card() -> bool:
	if _mirror_manager == null or _mirror_manager.copy_mirror_definition == null:
		return false
	_clear_world_selection()
	_selected_definition = null
	_set_mode(Mode.PLACE_COPY_MIRROR)
	status_changed.emit("选择 %s：左键放置，R 翻面，右键取消" % _mirror_manager.copy_mirror_definition.display_name)
	return true


func cancel_to_select(clear_world_selection: bool = true) -> void:
	_selected_definition = null
	if _building_manager != null:
		_building_manager.clear_preview()
	if _mirror_manager != null:
		_mirror_manager.clear_preview()
	if clear_world_selection:
		_clear_world_selection()
	_set_mode(Mode.SELECT)


## Returns a stable result dictionary so UI and tests never need to infer a
## synchronous manager signal. `attempted` is false only in SELECT mode.
func handle_primary(cell_pick: Dictionary, edge_pick: Dictionary) -> Dictionary:
	if _mode == Mode.SELECT:
		_select_world(cell_pick, edge_pick)
		return {
			"attempted": false,
			"success": false,
			"reason": "",
		}

	var success := false
	var reason := ""
	_last_failure_reason = ""
	match _mode:
		Mode.PLACE_BLOCK_BUILDING:
			if not bool(cell_pick.get("hit", false)):
				reason = "未命中地图格"
			elif _selected_definition == null:
				reason = "未选择建筑卡"
			else:
				var placed := _building_manager.place_building(
					cell_pick.get("cell", Vector3i.ZERO),
					_selected_definition,
					_building_manager.get_preview_facing_index()
				)
				success = placed != null
		Mode.PLACE_EDGE_BUILDING:
			if not bool(edge_pick.get("hit", false)):
				reason = "未命中有效边"
			elif _selected_definition == null:
				reason = "未选择边建筑卡"
			else:
				var placed := _building_manager.place_edge_building(
					edge_pick.get("cell", Vector3i.ZERO),
					int(edge_pick.get("edge_index", -1)),
					_selected_definition
				)
				success = placed != null
		Mode.PLACE_COPY_MIRROR:
			if not bool(edge_pick.get("hit", false)):
				reason = "未命中有效边"
			else:
				var active_from_side: Variant = null
				var preview := _mirror_manager.get_preview_info()
				if not preview.is_empty():
					active_from_side = (
						preview.get("active_cell", edge_pick.get("cell", Vector3i.ZERO))
						== edge_pick.get("cell", Vector3i.ZERO)
					)
				var placed := _mirror_manager.place_copy_mirror(
					edge_pick.get("cell", Vector3i.ZERO),
					int(edge_pick.get("edge_index", -1)),
					active_from_side
				)
				success = placed != null

	if not success and reason.is_empty():
		reason = _last_failure_reason if not _last_failure_reason.is_empty() else "放置失败"
	var message := "放置成功" if success else reason
	cancel_to_select(true)
	placement_resolved.emit(success, message)
	return {
		"attempted": true,
		"success": success,
		"reason": message,
	}


func _select_world(cell_pick: Dictionary, edge_pick: Dictionary) -> void:
	if _building_manager == null or _mirror_manager == null:
		return
	if not bool(cell_pick.get("hit", false)):
		_clear_world_selection()
		return
	var edge_id := String(edge_pick.get("id", "")) if bool(edge_pick.get("hit", false)) else ""
	var mirror := _mirror_manager.select_at_edge(edge_id)
	if mirror != null:
		_building_manager.select_building(null)
		return
	_mirror_manager.select_mirror(null)
	_building_manager.select_at(cell_pick.get("cell", Vector3i.ZERO), edge_id)


func _clear_world_selection() -> void:
	if _building_manager != null:
		_building_manager.select_building(null)
	if _mirror_manager != null:
		_mirror_manager.select_mirror(null)


func _set_mode(value: Mode) -> void:
	if _mode == value:
		mode_changed.emit(_mode)
		return
	_mode = value
	mode_changed.emit(_mode)


func _on_placement_failed(_cell: Vector3i, reason: String) -> void:
	_last_failure_reason = reason


func _on_mirror_placement_failed(_cell: Vector3i, reason: String) -> void:
	_last_failure_reason = reason


func _disconnect_managers() -> void:
	if _building_manager != null and _building_manager.placement_failed.is_connected(_on_placement_failed):
		_building_manager.placement_failed.disconnect(_on_placement_failed)
	if _mirror_manager != null and _mirror_manager.placement_failed.is_connected(_on_mirror_placement_failed):
		_mirror_manager.placement_failed.disconnect(_on_mirror_placement_failed)
