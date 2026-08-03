## LevelContentValidator -- read-only validation for canonical Grid/Ramp/Stuff.
class_name LevelContentValidator
extends RefCounted

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const MigrationAdapter := preload("res://scripts/level/LevelContentMigrationAdapter.gd")


static func validate(level: Resource, shape: IGridShape) -> Array[String]:
	var errors: Array[String] = []
	if level == null or shape == null or not MigrationAdapter.uses_canonical_content(level):
		return errors
	var layer_height := float(level.get("layer_height"))
	if not is_finite(layer_height) or layer_height <= 0.0:
		errors.append("体素单层高度必须为有限正数")
	var default_terrain: TerrainDefinitionScript = level.get("default_terrain") as TerrainDefinitionScript
	if default_terrain == null:
		errors.append("规范地块数据必须配置默认地形")
	else:
		ConfigValidator.append_prefixed(errors, "默认地形", default_terrain.validate_configuration())
	var grid_lookup := _validate_grid_cells(errors, level, shape, default_terrain)
	_validate_ramps(errors, level, shape, grid_lookup, default_terrain)
	_validate_stuff(errors, level, shape)
	return errors


static func _validate_grid_cells(
	errors: Array[String],
	level: Resource,
	shape: IGridShape,
	default_terrain: TerrainDefinitionScript
) -> Dictionary:
	var grid_lookup: Dictionary = {}
	var validated_terrains: Dictionary = {}
	if default_terrain != null:
		validated_terrains[default_terrain.get_instance_id()] = true
	var grid_size: Vector2i = level.get("grid_size")
	var grid_shape := int(level.get("grid_shape"))
	var raw_cells: Variant = level.get("grid_cells")
	if not raw_cells is Array:
		errors.append("规范地块数组类型无效")
		return grid_lookup
	for index in range(raw_cells.size()):
		var raw_cell: Variant = raw_cells[index]
		if not raw_cell is GridCellDataScript:
			errors.append("规范地块数组第 %d 项不是 GridCellData" % (index + 1))
			continue
		var grid_cell: GridCellDataScript = raw_cell
		if grid_lookup.has(grid_cell.cell):
			errors.append("规范地块坐标重复：%s" % str(grid_cell.cell))
		else:
			grid_lookup[grid_cell.cell] = grid_cell
		if not _valid_coordinate(grid_cell.cell, grid_shape):
			errors.append("规范地块坐标格式无效：%s" % str(grid_cell.cell))
		elif not shape.is_in_bounds(grid_cell.cell, grid_size):
			errors.append("规范地块 %s 位于地图外" % str(grid_cell.cell))
		for cell_error in grid_cell.validate_configuration():
			errors.append("规范地块 %s：%s" % [str(grid_cell.cell), cell_error])
		var terrain := grid_cell.get_effective_terrain(default_terrain)
		if terrain != null and not validated_terrains.has(terrain.get_instance_id()):
			validated_terrains[terrain.get_instance_id()] = true
			ConfigValidator.append_prefixed(
				errors,
				"地形 %s" % terrain.display_name,
				terrain.validate_configuration()
			)
	return grid_lookup


static func _validate_ramps(
	errors: Array[String],
	level: Resource,
	shape: IGridShape,
	grid_lookup: Dictionary,
	default_terrain: TerrainDefinitionScript
) -> void:
	var ramp_ids: Dictionary = {}
	var occupied_cells: Dictionary = {}
	var grid_size: Vector2i = level.get("grid_size")
	var raw_ramps: Variant = level.get("ramp_placements")
	if not raw_ramps is Array:
		errors.append("斜坡数组类型无效")
		return
	var footprint_lookup := _build_ramp_footprint_lookup(raw_ramps, shape, grid_size)
	for index in range(raw_ramps.size()):
		var raw_ramp: Variant = raw_ramps[index]
		if not raw_ramp is RampPlacementDataScript:
			errors.append("斜坡数组第 %d 项不是 RampPlacementData" % (index + 1))
			continue
		var ramp: RampPlacementDataScript = raw_ramp
		for ramp_error in ramp.validate_configuration():
			errors.append("斜坡 %s：%s" % [ramp.ramp_id, ramp_error])
		if ramp_ids.has(ramp.ramp_id):
			errors.append("斜坡 ID 重复：%s" % ramp.ramp_id)
		else:
			ramp_ids[ramp.ramp_id] = true
		if ramp.facing_index >= shape.edge_count():
			errors.append("斜坡 %s 的方向超出当前网格边数" % ramp.ramp_id)
			continue
		var footprint := ramp.get_footprint_cells(shape)
		if footprint.size() != ramp.run_length:
			errors.append("斜坡 %s 无法生成完整占格" % ramp.ramp_id)
			continue
		var terrain_key: StringName = &""
		for footprint_cell in footprint:
			if not shape.is_in_bounds(footprint_cell, grid_size):
				errors.append("斜坡 %s 的占格 %s 位于地图外" % [ramp.ramp_id, str(footprint_cell)])
				continue
			if occupied_cells.has(footprint_cell):
				errors.append("斜坡占格重叠：%s" % str(footprint_cell))
			else:
				occupied_cells[footprint_cell] = ramp.ramp_id
			var footprint_data := _effective_grid_cell(grid_lookup, footprint_cell)
			if int(footprint_data["layer_count"]) != ramp.base_layer:
				errors.append("斜坡 %s 的占格 %s 必须处于基础层 %d" % [
					ramp.ramp_id,
					str(footprint_cell),
					ramp.base_layer,
				])
			var terrain: TerrainDefinitionScript = footprint_data["terrain"] as TerrainDefinitionScript
			if terrain == null:
				terrain = default_terrain
			var current_key: StringName = terrain.terrain_id if terrain != null else &""
			if terrain_key.is_empty():
				terrain_key = current_key
			elif current_key != terrain_key:
				errors.append("斜坡 %s 的全部占格必须使用同一种地形" % ramp.ramp_id)
		var low_cell := ramp.get_low_neighbor(shape)
		var high_cell := ramp.get_high_neighbor(shape)
		if not shape.is_in_bounds(low_cell, grid_size) or not shape.is_in_bounds(high_cell, grid_size):
			errors.append("斜坡 %s 的高低连接端必须都位于地图内" % ramp.ramp_id)
			continue
		_validate_ramp_connection(
			errors,
			ramp,
			"低端",
			low_cell,
			footprint[0],
			ramp.base_layer,
			shape,
			grid_lookup,
			footprint_lookup
		)
		_validate_ramp_connection(
			errors,
			ramp,
			"高端",
			high_cell,
			footprint[footprint.size() - 1],
			ramp.base_layer + 1,
			shape,
			grid_lookup,
			footprint_lookup
		)


static func _build_ramp_footprint_lookup(
	raw_ramps: Array,
	shape: IGridShape,
	grid_size: Vector2i
) -> Dictionary:
	var lookup: Dictionary = {}
	for raw_ramp in raw_ramps:
		if not raw_ramp is RampPlacementDataScript:
			continue
		var ramp: RampPlacementDataScript = raw_ramp
		if (
			ramp.facing_index < 0
			or ramp.facing_index >= shape.edge_count()
			or ramp.run_length < RampPlacementDataScript.MIN_RUN_LENGTH
			or ramp.run_length > RampPlacementDataScript.MAX_RUN_LENGTH
		):
			continue
		var footprint := ramp.get_footprint_cells(shape)
		if footprint.size() != ramp.run_length:
			continue
		for footprint_cell in footprint:
			if not shape.is_in_bounds(footprint_cell, grid_size):
				continue
			# An overlapped footprint is already invalid. Store null so it cannot
			# masquerade as one deterministic continuous-ramp connection.
			if lookup.has(footprint_cell):
				lookup[footprint_cell] = null
			else:
				lookup[footprint_cell] = ramp
	return lookup


static func _validate_ramp_connection(
	errors: Array[String],
	ramp: RampPlacementDataScript,
	endpoint_name: String,
	connection_cell: Vector3i,
	ramp_boundary_cell: Vector3i,
	expected_layer: int,
	shape: IGridShape,
	grid_lookup: Dictionary,
	footprint_lookup: Dictionary
) -> void:
	var connected_ramp := footprint_lookup.get(connection_cell) as RampPlacementDataScript
	if connected_ramp != null and connected_ramp != ramp:
		var connected_layer := connected_ramp.get_connection_layer_toward(
			shape,
			ramp_boundary_cell
		)
		if connected_layer == RampPlacementDataScript.INVALID_CONNECTION_LAYER:
			errors.append("斜坡 %s 的%s连接到斜坡 %s 的侧边" % [
				ramp.ramp_id,
				endpoint_name,
				connected_ramp.ramp_id,
			])
		elif connected_layer != expected_layer:
			errors.append("斜坡 %s 的%s与斜坡 %s 的共享边层数不一致：需要第 %d 层，实际第 %d 层" % [
				ramp.ramp_id,
				endpoint_name,
				connected_ramp.ramp_id,
				expected_layer,
				connected_layer,
			])
		return
	if int(_effective_grid_cell(grid_lookup, connection_cell)["layer_count"]) != expected_layer:
		errors.append("斜坡 %s 的%s必须连接第 %d 层平地或等高斜坡端" % [
			ramp.ramp_id,
			endpoint_name,
			expected_layer,
		])


static func _validate_stuff(
	errors: Array[String],
	level: Resource,
	shape: IGridShape
) -> void:
	var placement_ids: Dictionary = {}
	var placements_by_cell: Dictionary = {}
	var validated_definitions: Dictionary = {}
	var grid_size: Vector2i = level.get("grid_size")
	var facing_count := 6 if int(level.get("grid_shape")) == 0 else 8
	var raw_placements: Variant = level.get("stuff_placements")
	if not raw_placements is Array:
		errors.append("关卡元素数组类型无效")
		return
	for index in range(raw_placements.size()):
		var raw_placement: Variant = raw_placements[index]
		if not raw_placement is StuffPlacementDataScript:
			errors.append("关卡元素数组第 %d 项不是 StuffPlacementData" % (index + 1))
			continue
		var placement: StuffPlacementDataScript = raw_placement
		if placement_ids.has(placement.placement_id):
			errors.append("关卡元素实例 ID 重复：%s" % placement.placement_id)
		else:
			placement_ids[placement.placement_id] = true
		if not shape.is_in_bounds(placement.cell, grid_size):
			errors.append("关卡元素 %s 位于地图外" % placement.placement_id)
		if placement.facing_index >= facing_count:
			errors.append("关卡元素 %s 的朝向超出当前网格方向数" % placement.placement_id)
		for placement_error in placement.validate_configuration():
			errors.append("关卡元素 %s：%s" % [placement.placement_id, placement_error])
		if placement.definition != null and not validated_definitions.has(placement.definition.get_instance_id()):
			validated_definitions[placement.definition.get_instance_id()] = true
			ConfigValidator.append_prefixed(
				errors,
				"关卡元素定义 %s" % placement.definition.display_name,
				placement.definition.validate_configuration()
			)
		if not placements_by_cell.has(placement.cell):
			placements_by_cell[placement.cell] = []
		var same_cell: Array = placements_by_cell[placement.cell]
		for existing_raw in same_cell:
			var existing: StuffPlacementDataScript = existing_raw
			if (
				existing.definition != null
				and placement.definition != null
				and not placement.definition.can_coexist_with(existing.definition)
			):
				errors.append("关卡元素 %s 与 %s 在 %s 互斥" % [
					placement.placement_id,
					existing.placement_id,
					str(placement.cell),
				])
		same_cell.append(placement)


static func _effective_grid_cell(grid_lookup: Dictionary, cell: Vector3i) -> Dictionary:
	if grid_lookup.has(cell):
		var data: GridCellDataScript = grid_lookup[cell]
		return {"layer_count": data.layer_count, "terrain": data.terrain}
	return {"layer_count": GridCellDataScript.MIN_LAYER_COUNT, "terrain": null}


static func _valid_coordinate(cell: Vector3i, grid_shape: int) -> bool:
	return cell.x + cell.y + cell.z == 0 if grid_shape == 0 else cell.z == 0
