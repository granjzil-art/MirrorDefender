## Runtime authoring state machine for selecting, previewing and editing Stuff.
## It is separate from gameplay building placement and never spends resources.
class_name RuntimeStuffEditorController
extends Node3D

const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const StuffCatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const StuffRuntimeScript := preload("res://scripts/stuff/StuffRuntime.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")

enum Tool {
	SELECT,
	STUFF,
	TERRAIN,
	LAYER,
	RAMP,
}

@export_group("Preview")
@export_range(0.0, 1.0, 0.01) var preview_transparency: float = 0.34
@export var valid_preview_color: Color = Color(0.25, 1.0, 0.48, 0.48)
@export var invalid_preview_color: Color = Color(1.0, 0.18, 0.16, 0.62)

signal active_changed(active: bool)
signal definition_selected(definition: StuffDefinition)
signal runtime_selected(runtime: StuffRuntime)
signal tool_changed(tool: Tool)
signal ramp_selected(ramp: RampPlacementData)
signal preview_changed(result: Dictionary)
signal status_changed(message: String, is_error: bool)

var _grid: GridManager
var _terrain_manager: Node
var _stuff_manager: StuffManager
var _stuff_renderer: StuffRenderer
var _level_loader: LevelLoader
var _session: RuntimeStuffEditSessionScript
var _time_controller: GameTimeController
var _active: bool = false
var _tool: Tool = Tool.SELECT
var _selected_definition: StuffDefinition
var _selected_terrain: TerrainDefinitionScript
var _selected_layer: int = 1
var _ramp_run_length: int = 1
var _ramp_base_layer: int = 1
var _ramp_terrain_override: TerrainDefinitionScript
var _selected_placement_id: StringName = &""
var _selected_ramp_id: StringName = &""
var _preview: Node3D
var _terrain_overlay: MeshInstance3D
var _preview_cell: Vector3i = Vector3i.ZERO
var _preview_facing_index: int = 0
var _preview_signature: String = ""
var _last_preview_result: Dictionary = {}
var _allow_path_warning: bool = false
var _previous_paused: bool = false


func configure(
	grid_manager: GridManager,
	terrain_manager: Node,
	stuff_manager: StuffManager,
	stuff_renderer: StuffRenderer,
	level_loader: LevelLoader,
	session: RuntimeStuffEditSessionScript,
	time_controller: GameTimeController
) -> void:
	_disconnect_manager()
	_grid = grid_manager
	_terrain_manager = terrain_manager
	_stuff_manager = stuff_manager
	_stuff_renderer = stuff_renderer
	_level_loader = level_loader
	_session = session
	_time_controller = time_controller
	if _stuff_manager != null:
		_stuff_manager.stuff_changed.connect(_on_stuff_changed)
		_stuff_manager.stuff_removed.connect(_on_stuff_removed)
	clear_preview()


func set_active(value: bool) -> bool:
	if _active == value:
		return true
	if value:
		if _level_loader == null or _session == null:
			return false
		var level := _level_loader.get_current_level()
		if level == null or not _session.begin(level, _level_loader.get_current_source_path()):
			status_changed.emit("无法开启关卡元素编辑", true)
			return false
		_previous_paused = _time_controller.is_paused() if _time_controller != null else false
		if _time_controller != null:
			if _previous_paused:
				_time_controller.set_paused(false)
			_time_controller.set_authoring_paused(true)
		_active = true
		active_changed.emit(true)
		status_changed.emit("运行时关卡编辑已开启：可编辑地形、层数、斜坡与关卡元素", false)
		return true
	if _session != null and _session.is_active():
		if _session.is_dirty():
			status_changed.emit("存在未保存修改，请保存或放弃修改后退出", true)
			return false
		if not _session.end_clean():
			return false
	clear_preview()
	_tool = Tool.SELECT
	_selected_definition = null
	_selected_terrain = null
	_selected_ramp_id = &""
	select_runtime(null)
	if _time_controller != null:
		_time_controller.set_authoring_paused(false)
		if _previous_paused:
			_time_controller.set_paused(true)
	_previous_paused = false
	_active = false
	active_changed.emit(false)
	return true


func is_active() -> bool:
	return _active


func get_session() -> RuntimeStuffEditSessionScript:
	return _session


func get_catalog() -> StuffCatalogScript:
	return _stuff_manager.get_stuff_catalog() if _stuff_manager != null else null


func get_terrain_definitions() -> Array[TerrainDefinitionScript]:
	var result: Array[TerrainDefinitionScript] = []
	for filename in DirAccess.get_files_at("res://resources/terrains"):
		if not filename.ends_with(".tres"):
			continue
		var resource := load("res://resources/terrains/%s" % filename)
		if resource is TerrainDefinitionScript:
			result.append(resource)
	result.sort_custom(func(a: TerrainDefinitionScript, b: TerrainDefinitionScript) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return result


func get_tool() -> Tool:
	return _tool


func get_selected_terrain() -> TerrainDefinitionScript:
	return _selected_terrain


func select_terrain_brush(terrain: TerrainDefinitionScript) -> bool:
	if not _active or terrain == null:
		return false
	clear_preview()
	_tool = Tool.TERRAIN
	_selected_definition = null
	_selected_terrain = terrain
	_selected_ramp_id = &""
	select_runtime(null)
	definition_selected.emit(null)
	ramp_selected.emit(null)
	tool_changed.emit(_tool)
	status_changed.emit("地形刷：%s" % terrain.display_name, false)
	return true


func select_layer_brush(layer_count: int) -> bool:
	if not _active:
		return false
	clear_preview()
	_tool = Tool.LAYER
	_selected_definition = null
	_selected_terrain = null
	_selected_layer = clampi(layer_count, 1, 4)
	_selected_ramp_id = &""
	select_runtime(null)
	definition_selected.emit(null)
	ramp_selected.emit(null)
	tool_changed.emit(_tool)
	status_changed.emit("高度刷：第 %d 层" % _selected_layer, false)
	return true


func select_ramp_tool(
	run_length: int = 1,
	base_layer: int = 1,
	terrain_override: TerrainDefinitionScript = null
) -> bool:
	if not _active:
		return false
	clear_preview()
	_tool = Tool.RAMP
	_selected_definition = null
	_selected_terrain = null
	_ramp_run_length = clampi(run_length, 1, 4)
	_ramp_base_layer = clampi(base_layer, 1, 3)
	_ramp_terrain_override = terrain_override
	_selected_ramp_id = &""
	select_runtime(null)
	definition_selected.emit(null)
	ramp_selected.emit(null)
	tool_changed.emit(_tool)
	status_changed.emit("斜坡工具：1:%d，基础层 %d，R 调整方向" % [_ramp_run_length, _ramp_base_layer], false)
	return true


func set_ramp_brush_settings(
	run_length: int,
	base_layer: int,
	terrain_override: TerrainDefinitionScript
) -> void:
	_ramp_run_length = clampi(run_length, 1, 4)
	_ramp_base_layer = clampi(base_layer, 1, 3)
	_ramp_terrain_override = terrain_override
	_preview_signature = ""


func get_ramp_run_length() -> int:
	return _ramp_run_length


func get_ramp_base_layer() -> int:
	return _ramp_base_layer


func get_ramp_terrain_override() -> TerrainDefinitionScript:
	return _ramp_terrain_override


func select_definition(definition: StuffDefinition) -> bool:
	if not _active or definition == null:
		return false
	_selected_definition = definition
	_selected_terrain = null
	_selected_ramp_id = &""
	_tool = Tool.STUFF
	select_runtime(null)
	_preview_facing_index = 0
	_preview_signature = ""
	definition_selected.emit(definition)
	tool_changed.emit(_tool)
	status_changed.emit("已选择 %s" % definition.display_name, false)
	return true


func select_tool() -> void:
	clear_preview()
	_tool = Tool.SELECT
	_selected_definition = null
	_selected_terrain = null
	_selected_ramp_id = &""
	definition_selected.emit(null)
	ramp_selected.emit(null)
	tool_changed.emit(_tool)
	status_changed.emit("选择工具：左键选择已有元素", false)


func get_selected_definition() -> StuffDefinition:
	return _selected_definition


func get_selected_runtime() -> StuffRuntime:
	return _stuff_manager.get_stuff(_selected_placement_id) if _stuff_manager != null else null


func select_runtime(runtime: StuffRuntime) -> void:
	_selected_placement_id = runtime.placement_id if runtime != null else &""
	if runtime != null:
		_selected_ramp_id = &""
		ramp_selected.emit(null)
	runtime_selected.emit(runtime)


func get_selected_ramp() -> RampPlacementDataScript:
	if _terrain_manager == null or _selected_ramp_id.is_empty():
		return null
	for ramp in _terrain_manager.get_ramps():
		if ramp != null and ramp.ramp_id == _selected_ramp_id:
			return ramp
	return null


func select_ramp(ramp: RampPlacementDataScript) -> void:
	_selected_ramp_id = ramp.ramp_id if ramp != null else &""
	if ramp != null:
		_selected_placement_id = &""
		runtime_selected.emit(null)
	ramp_selected.emit(ramp)


func set_allow_path_warning(value: bool) -> void:
	_allow_path_warning = value
	_preview_signature = ""


func get_allow_path_warning() -> bool:
	return _allow_path_warning


func update_preview(cell_pick: Dictionary, ui_blocked: bool = false) -> void:
	if not _active or _tool == Tool.SELECT or ui_blocked or not bool(cell_pick.get("hit", false)):
		clear_preview()
		return
	var cell: Vector3i = cell_pick.get("cell", Vector3i.ZERO)
	var signature := "%d|%s|%d|%d|%d|%d|%d|%d" % [
		_tool,
		str(cell),
		_preview_facing_index,
		_selected_terrain.get_instance_id() if _selected_terrain != null else 0,
		_selected_layer,
		_ramp_run_length,
		_ramp_base_layer,
		_ramp_terrain_override.get_instance_id() if _ramp_terrain_override != null else 0,
	]
	_preview_cell = cell
	if signature == _preview_signature:
		preview_changed.emit(_last_preview_result)
		return
	_preview_signature = signature
	if _tool == Tool.STUFF and _selected_definition != null:
		_session.clear_terrain_preview()
		var validation := _session.validate_placement(cell, _selected_definition, _preview_facing_index)
		_last_preview_result = validation.duplicate()
		_rebuild_preview(validation)
		preview_changed.emit(validation)
		return
	_clear_stuff_preview_visual()
	var existing_ramp := _terrain_manager.get_ramp_for_cell(cell) as RampPlacementDataScript if _terrain_manager != null else null
	if _tool == Tool.RAMP and existing_ramp != null:
		_session.clear_terrain_preview()
		_last_preview_result = {
			"valid": true,
			"success": false,
			"select_existing": true,
			"message": "点击选择斜坡 %s" % String(existing_ramp.ramp_id),
		}
		_rebuild_cell_overlay(cell, valid_preview_color)
		preview_changed.emit(_last_preview_result)
		return
	var operation := _get_terrain_operation()
	var parameters := _get_terrain_parameters(cell)
	var terrain_result := _session.preview_terrain_change(operation, parameters)
	terrain_result["valid"] = bool(terrain_result.get("success", false))
	terrain_result["warning"] = false
	_last_preview_result = terrain_result.duplicate()
	_rebuild_cell_overlay(cell, valid_preview_color if bool(terrain_result.get("success", false)) else invalid_preview_color)
	preview_changed.emit(terrain_result)


func clear_preview() -> void:
	_preview_signature = ""
	_last_preview_result = {}
	_clear_stuff_preview_visual()
	if _terrain_overlay != null and is_instance_valid(_terrain_overlay):
		_terrain_overlay.free()
	_terrain_overlay = null
	if _session != null:
		_session.clear_terrain_preview()


func get_preview_visual() -> Node3D:
	if _preview != null and is_instance_valid(_preview):
		return _preview
	return _terrain_overlay if _terrain_overlay != null and is_instance_valid(_terrain_overlay) else null


func get_preview_result() -> Dictionary:
	return _last_preview_result.duplicate()


func handle_primary(cell_pick: Dictionary) -> Dictionary:
	if not _active:
		return {"handled": false, "success": false, "message": ""}
	if not bool(cell_pick.get("hit", false)):
		select_runtime(null)
		select_ramp(null)
		return _result(true, false, "未命中地图格")
	var cell: Vector3i = cell_pick.get("cell", Vector3i.ZERO)
	if _tool == Tool.STUFF and _selected_definition != null:
		var runtime := _session.place_stuff(
			cell,
			_selected_definition,
			_preview_facing_index,
			_allow_path_warning
		)
		if runtime == null:
			var validation := _session.validate_placement(cell, _selected_definition, _preview_facing_index)
			var reason := str(validation.get("reason", "放置失败"))
			if bool(validation.get("warning", false)) and not _allow_path_warning:
				reason += "；勾选“允许不可达布局”后可作为作者配置放置"
			status_changed.emit(reason, true)
			return _result(true, false, reason)
		status_changed.emit("已放置 %s" % _selected_definition.display_name, false)
		_preview_signature = ""
		return _result(true, true, "放置成功")
	if _tool == Tool.TERRAIN or _tool == Tool.LAYER or _tool == Tool.RAMP:
		if _tool == Tool.RAMP and bool(_last_preview_result.get("select_existing", false)):
			var existing_ramp := _terrain_manager.get_ramp_for_cell(cell) as RampPlacementDataScript
			select_ramp(existing_ramp)
			status_changed.emit("已选择斜坡 %s；R 旋转，Delete 删除" % String(existing_ramp.ramp_id), false)
			return _result(true, true, "已选择斜坡")
		if not _session.has_terrain_preview() or _preview_cell != cell:
			update_preview(cell_pick, false)
		if not _session.has_terrain_preview():
			var failure := str(_last_preview_result.get("message", "地形修改无效"))
			status_changed.emit(failure, true)
			return _result(true, false, failure)
		var terrain_result := _session.commit_terrain_preview()
		var terrain_success := bool(terrain_result.get("success", false))
		var terrain_message := str(terrain_result.get("message", "地形修改完成"))
		status_changed.emit(terrain_message, not terrain_success)
		_preview_signature = ""
		return _result(true, terrain_success, terrain_message)
	var items := _stuff_manager.get_stuff_at(cell)
	var next_runtime: StuffRuntime = null
	if not items.is_empty():
		var current := get_selected_runtime()
		var current_index := items.find(current)
		next_runtime = items[posmod(current_index + 1, items.size())] if current_index >= 0 else items[0]
	select_runtime(next_runtime)
	if next_runtime == null:
		select_ramp(_terrain_manager.get_ramp_for_cell(cell) as RampPlacementDataScript if _terrain_manager != null else null)
	var selected := get_selected_runtime()
	var selected_ramp := get_selected_ramp()
	var message := "该格没有可编辑对象"
	if selected != null:
		var selected_index := items.find(selected)
		message = "已选择 %s（%d/%d，再次点击切换）" % [
			selected.definition.display_name,
			selected_index + 1,
			items.size(),
		]
	elif selected_ramp != null:
		message = "已选择斜坡 %s（1:%d / 基础层 %d）" % [selected_ramp.ramp_id, selected_ramp.run_length, selected_ramp.base_layer]
	status_changed.emit(message, selected == null and selected_ramp == null)
	return _result(true, selected != null or selected_ramp != null, message)


func rotate_current(step: int = 1) -> bool:
	if not _active:
		return false
	var selected_ramp := get_selected_ramp()
	if selected_ramp != null:
		var result := _session.apply_terrain_change(&"rotate_ramp", {
			"ramp_id": selected_ramp.ramp_id,
			"step": step,
		})
		var success := bool(result.get("success", false))
		if success:
			select_ramp(_find_ramp_by_id(result.get("ramp_id", selected_ramp.ramp_id)))
		status_changed.emit(str(result.get("message", "斜坡旋转失败")), not success)
		_preview_signature = ""
		return success
	if _tool == Tool.STUFF and _selected_definition != null:
		var facing_count := maxi(1, _grid.get_tile_content_facing_count()) if _grid != null else 1
		_preview_facing_index = posmod(_preview_facing_index + step, facing_count)
		_preview_signature = ""
		return true
	if _tool == Tool.RAMP:
		var facing_count := maxi(1, _grid.edge_count()) if _grid != null else 1
		_preview_facing_index = posmod(_preview_facing_index + step, facing_count)
		clear_preview()
		return true
	var runtime := get_selected_runtime()
	return runtime != null and _session.rotate_stuff(runtime.placement_id, step)


func remove_selected() -> bool:
	var runtime := get_selected_runtime()
	if not _active:
		return false
	if runtime != null:
		var display_name := runtime.definition.display_name if runtime.definition != null else String(runtime.placement_id)
		if not _session.remove_stuff(runtime.placement_id):
			return false
		select_runtime(null)
		status_changed.emit("已删除 %s" % display_name, false)
		return true
	var selected_ramp := get_selected_ramp()
	if selected_ramp == null:
		return false
	var result := _session.apply_terrain_change(&"remove_ramp", {"ramp_id": selected_ramp.ramp_id})
	var success := bool(result.get("success", false))
	if success:
		select_ramp(null)
	status_changed.emit(str(result.get("message", "移除斜坡失败")), not success)
	return success


func set_selected_ramp_terrain(terrain_override: TerrainDefinitionScript) -> bool:
	var selected_ramp := get_selected_ramp()
	if not _active or selected_ramp == null:
		return false
	var result := _session.apply_terrain_change(&"set_ramp_terrain", {
		"ramp_id": selected_ramp.ramp_id,
		"terrain_override": terrain_override,
	})
	var success := bool(result.get("success", false))
	if success:
		select_ramp(_find_ramp_by_id(selected_ramp.ramp_id))
	status_changed.emit(str(result.get("message", "斜坡地形修改失败")), not success)
	return success


func cancel_current_tool() -> void:
	if not _active:
		return
	if _tool != Tool.SELECT:
		select_tool()
	else:
		select_runtime(null)
		select_ramp(null)


func undo() -> bool:
	var success := _active and _session.undo()
	if success:
		select_runtime(null)
		select_ramp(null)
		_preview_signature = ""
		status_changed.emit("已撤销", false)
	return success


func redo() -> bool:
	var success := _active and _session.redo()
	if success:
		select_runtime(null)
		select_ramp(null)
		_preview_signature = ""
		status_changed.emit("已重做", false)
	return success


func save() -> Dictionary:
	var result := _session.save() if _active else {"success": false, "path": "", "message": "编辑尚未开启"}
	status_changed.emit(str(result.get("message", "")), not bool(result.get("success", false)))
	return result


func can_save_full_layout() -> bool:
	return _active and _session != null and _session.can_save_full_layout()


func save_full_layout() -> Dictionary:
	var result := (
		_session.save("", true)
		if can_save_full_layout()
		else {"success": false, "path": "", "message": "全量保存尚未启用"}
	)
	status_changed.emit(str(result.get("message", "")), not bool(result.get("success", false)))
	return result


func discard_and_close() -> bool:
	if not _active:
		return false
	if not _session.discard_and_end():
		return false
	return set_active(false)


func save_and_close() -> bool:
	if not _active:
		return false
	var result := save_full_layout() if _session.has_terrain_changes() else save()
	if not bool(result.get("success", false)) or not _session.end_after_save():
		return false
	return set_active(false)


func abort_for_level_transition() -> void:
	if not _active:
		return
	clear_preview()
	_tool = Tool.SELECT
	_selected_definition = null
	_selected_terrain = null
	_selected_ramp_id = &""
	select_runtime(null)
	_session.abort_for_level_transition()
	if _time_controller != null:
		_time_controller.set_authoring_paused(false)
	_previous_paused = false
	_active = false
	active_changed.emit(false)


func _get_terrain_operation() -> StringName:
	match _tool:
		Tool.TERRAIN:
			return &"paint_terrain"
		Tool.LAYER:
			return &"paint_layer"
		Tool.RAMP:
			return &"place_ramp"
	return &""


func _get_terrain_parameters(cell: Vector3i) -> Dictionary:
	match _tool:
		Tool.TERRAIN:
			return {"cell": cell, "terrain": _selected_terrain}
		Tool.LAYER:
			return {"cell": cell, "layer_count": _selected_layer}
		Tool.RAMP:
			return {
				"cell": cell,
				"facing_index": _preview_facing_index,
				"run_length": _ramp_run_length,
				"base_layer": _ramp_base_layer,
				"terrain_override": _ramp_terrain_override,
			}
	return {}


func _find_ramp_by_id(ramp_id: StringName) -> RampPlacementDataScript:
	if _terrain_manager == null or ramp_id.is_empty():
		return null
	for ramp in _terrain_manager.get_ramps():
		if ramp != null and ramp.ramp_id == ramp_id:
			return ramp
	return null


func _clear_stuff_preview_visual() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.free()
	_preview = null


func _rebuild_cell_overlay(cell: Vector3i, color: Color) -> void:
	if _terrain_overlay != null and is_instance_valid(_terrain_overlay):
		_terrain_overlay.free()
	_terrain_overlay = null
	if _grid == null or _terrain_manager == null:
		return
	var corners := _grid.get_corners(cell)
	if corners.size() < 3:
		return
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, clampf(color.a, 0.12, 0.72))
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var center := _grid.cell_to_world(cell)
	center.y = _terrain_manager.sample_surface_height(cell, center) + 0.035
	for index in range(corners.size()):
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % corners.size()]
		a.y = _terrain_manager.sample_surface_height(cell, a) + 0.035
		b.y = _terrain_manager.sample_surface_height(cell, b) + 0.035
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(b)
	mesh.surface_end()
	_terrain_overlay = MeshInstance3D.new()
	_terrain_overlay.name = "RuntimeTerrainPreviewOverlay"
	_terrain_overlay.mesh = mesh
	add_child(_terrain_overlay)


func _rebuild_preview(validation: Dictionary) -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.free()
	_preview = null
	if _stuff_renderer == null or _grid == null or _selected_definition == null:
		return
	var placement := StuffPlacementDataScript.new()
	placement.configure(&"__stuff_preview__", _preview_cell, _selected_definition, _preview_facing_index)
	var candidate: StuffRuntime = StuffRuntimeScript.new()
	var height_resolver := Callable()
	if _terrain_manager != null and _terrain_manager.has_method("get_world_height"):
		height_resolver = Callable(_terrain_manager, "get_world_height")
	if not candidate.configure(placement, _grid, height_resolver):
		candidate.free()
		return
	_preview = _stuff_renderer.create_preview_visual(candidate)
	if _preview != null:
		add_child(_preview)
		# Candidate is intentionally behaviorless and never enters the tree; its
		# local transform already uses the same world root as this controller.
		_preview.transform = candidate.transform
		var valid := bool(validation.get("valid", false)) and not bool(validation.get("warning", false))
		_apply_preview_overlay(_preview, valid_preview_color if valid else invalid_preview_color)
	candidate.free()


func _apply_preview_overlay(node: Node, color: Color) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.transparency = clampf(preview_transparency, 0.0, 1.0)
		var overlay := StandardMaterial3D.new()
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.albedo_color = color
		overlay.no_depth_test = true
		geometry.material_overlay = overlay
	for child in node.get_children():
		_apply_preview_overlay(child, color)


func _on_stuff_changed(_cell: Vector3i) -> void:
	_preview_signature = ""
	if not _selected_placement_id.is_empty() and get_selected_runtime() == null:
		select_runtime(null)


func _on_stuff_removed(runtime: StuffRuntime) -> void:
	if runtime != null and runtime.placement_id == _selected_placement_id:
		select_runtime(null)


func _disconnect_manager() -> void:
	if _stuff_manager == null:
		return
	if _stuff_manager.stuff_changed.is_connected(_on_stuff_changed):
		_stuff_manager.stuff_changed.disconnect(_on_stuff_changed)
	if _stuff_manager.stuff_removed.is_connected(_on_stuff_removed):
		_stuff_manager.stuff_removed.disconnect(_on_stuff_removed)


func _result(handled: bool, success: bool, message: String) -> Dictionary:
	return {"handled": handled, "success": success, "message": message}
