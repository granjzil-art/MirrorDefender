## RuntimeTerrainEditService -- pure mutation rules for a transient LevelResource.
##
## Callers own the document copy and decide whether it is a preview, a commit,
## or a discarded candidate. This service never touches live managers directly.
class_name RuntimeTerrainEditService
extends RefCounted

const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")


static func paint_terrain(
	level: LevelResource,
	shape: IGridShape,
	cell: Vector3i,
	terrain: TerrainDefinitionScript
) -> Dictionary:
	if level == null or shape == null or terrain == null:
		return _result(false, "地形、关卡或网格无效")
	var target_cells: Array[Vector3i] = [cell]
	var ramp := get_ramp_at(level, shape, cell)
	if ramp != null:
		target_cells = ramp.get_footprint_cells(shape)
	var changed := false
	for target_cell in target_cells:
		var data := _get_grid_cell(level, target_cell)
		if data == null or data.terrain == terrain:
			continue
		data.terrain = terrain
		data.emit_changed()
		changed = true
	if changed:
		level.emit_changed()
	var result := _result(true, "已将地形设置为 %s" % terrain.display_name if changed else "地形已经是 %s" % terrain.display_name)
	result["changed"] = changed
	return result


static func paint_layer(
	level: LevelResource,
	shape: IGridShape,
	cell: Vector3i,
	layer_count: int
) -> Dictionary:
	if level == null or shape == null:
		return _result(false, "关卡或网格无效")
	if get_ramp_at(level, shape, cell) != null:
		return _result(false, "该格属于斜坡；请先编辑或移除斜坡")
	var data := _get_grid_cell(level, cell)
	if data == null:
		return _result(false, "目标格不存在")
	var resolved_layer := clampi(
		layer_count,
		GridCellDataScript.MIN_LAYER_COUNT,
		GridCellDataScript.MAX_LAYER_COUNT
	)
	if data.layer_count == resolved_layer:
		var unchanged := _result(true, "当前已经是第 %d 层" % resolved_layer)
		unchanged["changed"] = false
		return unchanged
	data.layer_count = resolved_layer
	data.emit_changed()
	level.emit_changed()
	var result := _result(true, "已设置为第 %d 层" % resolved_layer)
	result["changed"] = true
	return result


static func place_ramp(
	level: LevelResource,
	shape: IGridShape,
	anchor_cell: Vector3i,
	facing_index: int,
	run_length: int,
	base_layer: int,
	terrain_override: TerrainDefinitionScript = null
) -> Dictionary:
	if level == null or shape == null:
		return _result(false, "关卡或网格无效")
	if facing_index < 0 or facing_index >= shape.edge_count():
		return _result(false, "斜坡方向超出当前网格边数")
	var ramp := RampPlacementDataScript.new()
	ramp.ramp_id = _next_ramp_id(level)
	ramp.anchor_cell = anchor_cell
	ramp.facing_index = facing_index
	ramp.run_length = clampi(run_length, RampPlacementDataScript.MIN_RUN_LENGTH, RampPlacementDataScript.MAX_RUN_LENGTH)
	ramp.base_layer = clampi(base_layer, RampPlacementDataScript.MIN_BASE_LAYER, RampPlacementDataScript.MAX_BASE_LAYER)
	ramp.terrain_override = terrain_override
	var structural_error := _get_structural_error(level, shape, ramp, &"")
	if not structural_error.is_empty():
		return _result(false, structural_error)
	_apply_ramp_constraints(level, shape, ramp)
	level.ramp_placements.append(ramp)
	level.emit_changed()
	return {
		"success": true,
		"message": "已放置 1:%d 斜坡" % ramp.run_length,
		"ramp_id": ramp.ramp_id,
	}


static func rotate_ramp(
	level: LevelResource,
	shape: IGridShape,
	ramp_id: StringName,
	step: int = 1
) -> Dictionary:
	var ramp := get_ramp_by_id(level, ramp_id)
	if ramp == null or shape == null:
		return _result(false, "未找到斜坡")
	var facing_count := maxi(1, shape.edge_count())
	var next_facing := posmod(ramp.facing_index + step, facing_count)
	if next_facing == ramp.facing_index:
		return _result(false, "斜坡方向没有变化")
	ramp.facing_index = next_facing
	var structural_error := _get_structural_error(level, shape, ramp, ramp.ramp_id)
	if not structural_error.is_empty():
		return _result(false, structural_error)
	_apply_ramp_constraints(level, shape, ramp)
	ramp.emit_changed()
	level.emit_changed()
	return {
		"success": true,
		"message": "斜坡已旋转到方向 %d" % next_facing,
		"ramp_id": ramp.ramp_id,
	}


static func remove_ramp(level: LevelResource, ramp_id: StringName) -> Dictionary:
	if level == null or ramp_id.is_empty():
		return _result(false, "未找到斜坡")
	var next_ramps: Array[RampPlacementData] = []
	var removed := false
	for ramp in level.ramp_placements:
		if ramp != null and ramp.ramp_id == ramp_id:
			removed = true
			continue
		next_ramps.append(ramp)
	if not removed:
		return _result(false, "未找到斜坡")
	level.ramp_placements.assign(next_ramps)
	level.emit_changed()
	return _result(true, "已移除斜坡 %s" % String(ramp_id))


static func set_ramp_terrain(
	level: LevelResource,
	ramp_id: StringName,
	terrain_override: TerrainDefinitionScript
) -> Dictionary:
	var ramp := get_ramp_by_id(level, ramp_id)
	if ramp == null:
		return _result(false, "未找到斜坡")
	if ramp.terrain_override == terrain_override:
		return _result(false, "斜坡地形没有变化")
	ramp.terrain_override = terrain_override
	ramp.emit_changed()
	level.emit_changed()
	return _result(true, "斜坡已跟随基底" if terrain_override == null else "斜坡地形已设置为 %s" % terrain_override.display_name)


static func get_ramp_at(
	level: LevelResource,
	shape: IGridShape,
	cell: Vector3i
) -> RampPlacementDataScript:
	if level == null or shape == null:
		return null
	for ramp in level.ramp_placements:
		if ramp != null and cell in ramp.get_footprint_cells(shape):
			return ramp
	return null


static func get_ramp_by_id(level: LevelResource, ramp_id: StringName) -> RampPlacementDataScript:
	if level == null or ramp_id.is_empty():
		return null
	for ramp in level.ramp_placements:
		if ramp != null and ramp.ramp_id == ramp_id:
			return ramp
	return null


static func _get_structural_error(
	level: LevelResource,
	shape: IGridShape,
	ramp: RampPlacementDataScript,
	ignored_ramp_id: StringName
) -> String:
	var footprint := ramp.get_footprint_cells(shape)
	if footprint.size() != ramp.run_length:
		return "无法生成完整斜坡占格"
	var required_cells := footprint.duplicate()
	required_cells.append(ramp.get_low_neighbor(shape))
	required_cells.append(ramp.get_high_neighbor(shape))
	for required_cell in required_cells:
		if not shape.is_in_bounds(required_cell, level.grid_size):
			return "斜坡占格或高低连接端位于地图外"
	for existing in level.ramp_placements:
		if existing == null or existing.ramp_id == ignored_ramp_id:
			continue
		for footprint_cell in footprint:
			if footprint_cell in existing.get_footprint_cells(shape):
				return "斜坡与已有斜坡 %s 重叠" % String(existing.ramp_id)
	return ""


static func _apply_ramp_constraints(
	level: LevelResource,
	shape: IGridShape,
	ramp: RampPlacementDataScript
) -> void:
	var anchor_data := _get_grid_cell(level, ramp.anchor_cell)
	if anchor_data == null:
		return
	var terrain := anchor_data.get_effective_terrain(level.default_terrain)
	for footprint_cell in ramp.get_footprint_cells(shape):
		var data := _get_grid_cell(level, footprint_cell)
		if data == null:
			continue
		data.terrain = terrain
		data.layer_count = ramp.base_layer
		data.emit_changed()
	_apply_flat_connector(level, shape, ramp.get_low_neighbor(shape), ramp.base_layer, ramp.ramp_id)
	_apply_flat_connector(level, shape, ramp.get_high_neighbor(shape), ramp.base_layer + 1, ramp.ramp_id)


static func _apply_flat_connector(
	level: LevelResource,
	shape: IGridShape,
	cell: Vector3i,
	expected_layer: int,
	ignored_ramp_id: StringName
) -> void:
	for existing in level.ramp_placements:
		if existing == null or existing.ramp_id == ignored_ramp_id:
			continue
		if cell in existing.get_footprint_cells(shape):
			return
	var data := _get_grid_cell(level, cell)
	if data != null:
		data.layer_count = expected_layer
		data.emit_changed()


static func _get_grid_cell(level: LevelResource, cell: Vector3i) -> GridCellDataScript:
	if level == null:
		return null
	for data in level.grid_cells:
		if data != null and data.cell == cell:
			return data
	return null


static func _next_ramp_id(level: LevelResource) -> StringName:
	var used: Dictionary = {}
	for ramp in level.ramp_placements:
		if ramp != null:
			used[ramp.ramp_id] = true
	var index := 1
	while used.has(StringName("ramp_%d" % index)):
		index += 1
	return StringName("ramp_%d" % index)


static func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message, "ramp_id": &""}
