## Read-only structural validation for authored initial Buildings and mirrors.
class_name InitialLayoutValidator
extends RefCounted

const BuildingPlacementDataScript := preload("res://scripts/building/BuildingPlacementData.gd")
const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const MirrorPlacementDataScript := preload("res://scripts/mirror/MirrorPlacementData.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")


static func validate(level: Resource, shape: IGridShape) -> Array[String]:
	var errors: Array[String] = []
	if level == null or shape == null:
		return errors
	var raw_buildings: Variant = level.get("initial_building_placements")
	var raw_mirrors: Variant = level.get("initial_mirror_placements")
	if not raw_buildings is Array:
		errors.append("初始建筑数组类型无效")
		return errors
	if not raw_mirrors is Array:
		errors.append("初始镜子数组类型无效")
		return errors
	if raw_buildings.size() > int(level.get("building_cap")):
		errors.append("初始建筑数量超过建筑上限")
	var copy_mirror_count := 0
	var reflect_mirror_count := 0
	for raw_mirror in raw_mirrors:
		if not raw_mirror is MirrorPlacementDataScript:
			continue
		if raw_mirror.mirror_kind == MirrorPlacementDataScript.MirrorKind.PROJECTILE_REFLECT:
			reflect_mirror_count += 1
		else:
			copy_mirror_count += 1
	var copy_mirror_cap := int(level.call("get_copy_mirror_cap"))
	var reflect_mirror_cap := int(level.call("get_reflect_mirror_cap"))
	if copy_mirror_count > copy_mirror_cap:
		errors.append("初始复制镜数量超过复制镜上限")
	if reflect_mirror_count > reflect_mirror_cap:
		errors.append("初始反射镜数量超过反射镜上限")
	var context := _build_context(level)
	var occupied_cells: Dictionary = {}
	var occupied_edges: Dictionary = {}
	var validated_definitions: Dictionary = {}
	for index in range(raw_buildings.size()):
		var raw_placement: Variant = raw_buildings[index]
		if not raw_placement is BuildingPlacementDataScript:
			errors.append("初始建筑数组第 %d 项不是 BuildingPlacementData" % (index + 1))
			continue
		_validate_building(
			errors,
			raw_placement,
			index,
			level,
			shape,
			context,
			occupied_cells,
			occupied_edges,
			validated_definitions
		)
	for index in range(raw_mirrors.size()):
		var raw_placement: Variant = raw_mirrors[index]
		if not raw_placement is MirrorPlacementDataScript:
			errors.append("初始镜子数组第 %d 项不是 MirrorPlacementData" % (index + 1))
			continue
		_validate_mirror(errors, raw_placement, index, level, shape, context, occupied_edges)
	return errors


static func _validate_building(
	errors: Array[String],
	placement: BuildingPlacementData,
	index: int,
	level: Resource,
	shape: IGridShape,
	context: Dictionary,
	occupied_cells: Dictionary,
	occupied_edges: Dictionary,
	validated_definitions: Dictionary
) -> void:
	var label := "初始建筑 %d" % (index + 1)
	for placement_error in placement.validate_configuration():
		errors.append("%s：%s" % [label, placement_error])
	if placement.definition == null:
		return
	var definition_id := placement.definition.get_instance_id()
	if not validated_definitions.has(definition_id):
		validated_definitions[definition_id] = true
		ConfigValidator.append_prefixed(
			errors,
			"%s定义 %s" % [label, placement.definition.display_name],
			placement.definition.validate_configuration()
		)
	if not _is_valid_cell(placement.cell, int(level.get("grid_shape"))):
		errors.append("%s坐标格式无效：%s" % [label, str(placement.cell)])
		return
	var grid_size: Vector2i = level.get("grid_size")
	if not shape.is_in_bounds(placement.cell, grid_size):
		errors.append("%s位于地图外：%s" % [label, str(placement.cell)])
		return
	if placement.is_edge_placement():
		_validate_edge(
			errors,
			label,
			placement.cell,
			placement.edge_index,
			level,
			shape,
			context,
			occupied_edges
		)
		return
	var facing_count := 36
	if placement.facing_index >= facing_count:
		errors.append("%s朝向超出当前网格方向数" % label)
	if occupied_cells.has(placement.cell):
		errors.append("初始块建筑占格重复：%s" % str(placement.cell))
	else:
		occupied_cells[placement.cell] = true
	var path_cells: Dictionary = context["path_cells"]
	var protected_cells: Dictionary = context["protected_cells"]
	if placement.definition.is_path_tile_building():
		if not path_cells.has(placement.cell):
			errors.append("%s的路径屏障不在敌人路径上" % label)
		if protected_cells.has(placement.cell):
			errors.append("%s不能占据出生点或据点" % label)
		if _stuff_blocks(context, placement.cell, true):
			errors.append("%s所在格的关卡元素禁止块建筑" % label)
		return
	if path_cells.has(placement.cell):
		errors.append("%s的普通建筑不能占据敌人路径" % label)
	if not _base_allows(context, placement.cell, true) or _stuff_blocks(context, placement.cell, true):
		errors.append("%s所在格禁止块建筑" % label)


static func _validate_mirror(
	errors: Array[String],
	placement: MirrorPlacementData,
	index: int,
	level: Resource,
	shape: IGridShape,
	context: Dictionary,
	occupied_edges: Dictionary
) -> void:
	var label := "初始镜子 %d" % (index + 1)
	for placement_error in placement.validate_configuration():
		errors.append("%s：%s" % [label, placement_error])
	if not _is_valid_cell(placement.from_cell, int(level.get("grid_shape"))):
		errors.append("%s坐标格式无效：%s" % [label, str(placement.from_cell)])
		return
	_validate_edge(
		errors,
		label,
		placement.from_cell,
		placement.edge_index,
		level,
		shape,
		context,
		occupied_edges
	)


static func _validate_edge(
	errors: Array[String],
	label: String,
	from_cell: Vector3i,
	edge_index: int,
	level: Resource,
	shape: IGridShape,
	context: Dictionary,
	occupied_edges: Dictionary
) -> void:
	if edge_index < 0 or edge_index >= shape.edge_count():
		errors.append("%s边方向超出当前网格边数" % label)
		return
	var grid_size: Vector2i = level.get("grid_size")
	if not shape.is_in_bounds(from_cell, grid_size):
		errors.append("%s位于地图外：%s" % [label, str(from_cell)])
		return
	var to_cell := shape.neighbor_across_edge(from_cell, edge_index)
	if not shape.is_in_bounds(to_cell, grid_size):
		errors.append("%s必须位于两个有效地块之间" % label)
		return
	if (
		not _base_allows_edge(context, shape, from_cell, edge_index)
		or _stuff_blocks(context, from_cell, false)
		or _stuff_blocks(context, to_cell, false)
	):
		errors.append("%s所在物理边不允许放置边建筑" % label)
	var edge_id := shape.canonical_edge_id(from_cell, edge_index)
	if occupied_edges.has(edge_id):
		errors.append("初始边建筑或镜子占用同一物理边：%s" % edge_id)
	else:
		occupied_edges[edge_id] = true


static func _build_context(level: Resource) -> Dictionary:
	var context := {
		"grid_cells": {},
		"stuff_by_cell": {},
		"path_cells": {},
		"protected_cells": {},
		"base_footprint_owners": {},
	}
	var snapshot: Dictionary = level.call("get_effective_content_snapshot")
	for raw_cell in snapshot.get("grid_cells", []):
		if raw_cell is GridCellDataScript:
			context["grid_cells"][raw_cell.cell] = raw_cell
	for raw_stuff in snapshot.get("stuff_placements", []):
		if not raw_stuff is StuffPlacementDataScript:
			continue
		if not context["stuff_by_cell"].has(raw_stuff.cell):
			context["stuff_by_cell"][raw_stuff.cell] = []
		context["stuff_by_cell"][raw_stuff.cell].append(raw_stuff)
	for raw_path in level.get("paths"):
		if raw_path == null:
			continue
		for cell in raw_path.cells:
			context["path_cells"][cell] = true
	for raw_spawn in level.get("spawn_points"):
		if raw_spawn != null:
			context["protected_cells"][raw_spawn.cell] = true
	for raw_base in level.call("get_effective_base_points"):
		if raw_base != null:
			for footprint_cell in raw_base.get_footprint_cells():
				context["protected_cells"][footprint_cell] = true
				context["base_footprint_owners"][footprint_cell] = raw_base.base_id
	return context


static func _base_allows(context: Dictionary, cell: Vector3i, tile: bool) -> bool:
	var data: GridCellData = context["grid_cells"].get(cell) as GridCellData
	if data == null:
		return true
	return data.allows_tile_building if tile else data.allows_edge_building


static func _base_allows_edge(
	context: Dictionary,
	shape: IGridShape,
	from_cell: Vector3i,
	edge_index: int
) -> bool:
	var to_cell := shape.neighbor_across_edge(from_cell, edge_index)
	var path_cells: Dictionary = context["path_cells"]
	if path_cells.has(from_cell) and path_cells.has(to_cell):
		return false
	var opposite_edge := _find_edge_index(shape, to_cell, from_cell)
	if opposite_edge < 0:
		return false
	var from_data: GridCellData = context["grid_cells"].get(from_cell) as GridCellData
	var to_data: GridCellData = context["grid_cells"].get(to_cell) as GridCellData
	if from_data != null and not from_data.allows_edge(edge_index):
		return false
	if to_data != null and not to_data.allows_edge(opposite_edge):
		return false
	var owners: Dictionary = context["base_footprint_owners"]
	var from_owner: Variant = owners.get(from_cell)
	var to_owner: Variant = owners.get(to_cell)
	return from_owner == null or to_owner == null or from_owner != to_owner


static func _find_edge_index(shape: IGridShape, from_cell: Vector3i, to_cell: Vector3i) -> int:
	for candidate in range(shape.edge_count()):
		if shape.neighbor_across_edge(from_cell, candidate) == to_cell:
			return candidate
	return -1


static func _stuff_blocks(context: Dictionary, cell: Vector3i, tile: bool) -> bool:
	for raw_placement in context["stuff_by_cell"].get(cell, []):
		var placement: StuffPlacementData = raw_placement
		if placement.definition == null:
			continue
		if tile and placement.definition.blocks_tile_building:
			return true
		if not tile and placement.definition.blocks_edge_building:
			return true
	return false


static func _is_valid_cell(cell: Vector3i, grid_shape: int) -> bool:
	return cell.x + cell.y + cell.z == 0 if grid_shape == 0 else cell.z == 0
