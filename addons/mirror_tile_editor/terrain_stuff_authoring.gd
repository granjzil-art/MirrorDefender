@tool
## TerrainStuffAuthoring -- canonical editor mutation boundary for Grid, ramps,
## and Stuff. It deliberately knows nothing about paths, waves, or cameras.
class_name TerrainStuffAuthoring
extends RefCounted

const CANONICAL_CONTENT_VERSION: int = 2
const DEFAULT_TERRAIN_PATH := "res://resources/terrains/Grass.tres"

const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")


## Returns `{changed: bool, migrated: bool, added_cells: int}`. Legacy content
## is imported once and then removed from the authoring document so only the
## canonical arrays can be edited or saved.
static func prepare_level(level: Resource, shape: IGridShape) -> Dictionary:
	if level == null or shape == null:
		return {"changed": false, "migrated": false, "added_cells": 0}
	var migrated := false
	var changed := false
	if not bool(level.call("uses_canonical_content")):
		migrated = bool(level.call("migrate_legacy_content_in_place"))
		changed = migrated
	if int(level.get("terrain_content_version")) != CANONICAL_CONTENT_VERSION:
		level.set("terrain_content_version", CANONICAL_CONTENT_VERSION)
		changed = true
	var default_terrain: TerrainDefinitionScript = level.get("default_terrain") as TerrainDefinitionScript
	if default_terrain == null:
		default_terrain = load(DEFAULT_TERRAIN_PATH) as TerrainDefinitionScript
		level.set("default_terrain", default_terrain)
		changed = true
	var layer_height := float(level.get("layer_height"))
	if not is_finite(layer_height) or layer_height <= 0.0:
		layer_height = maxf(0.05, float(level.get("height_step")))
		level.set("layer_height", layer_height)
		changed = true
	# Legacy fields stay as compatibility metadata but no longer contain a
	# second editable copy after import.
	var legacy_tiles: Variant = level.get("tiles")
	if legacy_tiles is Array and not legacy_tiles.is_empty():
		level.set("tiles", [])
		changed = true
	if int(level.get("height_levels")) != GridCellDataScript.MAX_LAYER_COUNT:
		level.set("height_levels", GridCellDataScript.MAX_LAYER_COUNT)
		changed = true
	if not is_equal_approx(float(level.get("height_step")), layer_height):
		level.set("height_step", layer_height)
		changed = true
	var added_cells := _materialize_missing_cells(level, shape, default_terrain)
	changed = changed or added_cells > 0
	if changed:
		level.emit_changed()
	return {"changed": changed, "migrated": migrated, "added_cells": added_cells}


static func rebuild_grid(
	level: Resource,
	shape: IGridShape,
	shape_id: int,
	grid_size: Vector2i
) -> void:
	if level == null or shape == null:
		return
	level.set("grid_shape", shape_id)
	level.set("grid_size", grid_size)
	level.set("terrain_content_version", CANONICAL_CONTENT_VERSION)
	var empty_cells: Array[GridCellDataScript] = []
	var empty_ramps: Array[RampPlacementDataScript] = []
	var empty_stuff: Array[StuffPlacementDataScript] = []
	level.set("grid_cells", empty_cells)
	level.set("ramp_placements", empty_ramps)
	level.set("stuff_placements", empty_stuff)
	level.set("tiles", [])
	shape.setup(float(level.get("grid_cell_size")))
	_materialize_missing_cells(
		level,
		shape,
		level.get("default_terrain") as TerrainDefinitionScript
	)
	level.emit_changed()


static func get_grid_cell(level: Resource, cell: Vector3i) -> GridCellDataScript:
	if level == null:
		return null
	var raw_cells: Variant = level.get("grid_cells")
	if not raw_cells is Array:
		return null
	for raw_cell in raw_cells:
		if raw_cell is GridCellDataScript and raw_cell.cell == cell:
			return raw_cell
	return null


static func get_or_create_grid_cell(level: Resource, cell: Vector3i) -> GridCellDataScript:
	var current := get_grid_cell(level, cell)
	if current != null:
		return current
	if level == null:
		return null
	var created := GridCellDataScript.new()
	created.configure(
		cell,
		level.get("default_terrain") as TerrainDefinitionScript,
		GridCellDataScript.MIN_LAYER_COUNT,
		true,
		true
	)
	var next_cells: Array[GridCellDataScript] = []
	for raw_cell in _as_array(level.get("grid_cells")):
		if raw_cell is GridCellDataScript:
			next_cells.append(raw_cell)
	next_cells.append(created)
	level.set("grid_cells", next_cells)
	return created


static func paint_terrain(level: Resource, cell: Vector3i, terrain: Resource) -> bool:
	if level == null or not terrain is TerrainDefinitionScript:
		return false
	var grid_cell := get_or_create_grid_cell(level, cell)
	if grid_cell == null or grid_cell.get_effective_terrain(level.get("default_terrain")) == terrain:
		return false
	grid_cell.terrain = terrain
	grid_cell.emit_changed()
	level.emit_changed()
	return true


static func paint_layer(level: Resource, cell: Vector3i, layer_count: int) -> bool:
	var grid_cell := get_or_create_grid_cell(level, cell)
	var clamped := clampi(
		layer_count,
		GridCellDataScript.MIN_LAYER_COUNT,
		GridCellDataScript.MAX_LAYER_COUNT
	)
	if grid_cell == null or grid_cell.layer_count == clamped:
		return false
	grid_cell.layer_count = clamped
	grid_cell.emit_changed()
	level.emit_changed()
	return true


static func paint_permissions(
	level: Resource,
	cell: Vector3i,
	allows_tile_building: bool,
	allows_edge_building: bool
) -> bool:
	var grid_cell := get_or_create_grid_cell(level, cell)
	if grid_cell == null:
		return false
	if (
		grid_cell.allows_tile_building == allows_tile_building
		and grid_cell.allows_edge_building == allows_edge_building
	):
		return false
	grid_cell.allows_tile_building = allows_tile_building
	grid_cell.allows_edge_building = allows_edge_building
	grid_cell.emit_changed()
	level.emit_changed()
	return true


static func get_stuff_at(level: Resource, cell: Vector3i) -> Array[StuffPlacementDataScript]:
	var result: Array[StuffPlacementDataScript] = []
	if level == null:
		return result
	for raw_placement in _as_array(level.get("stuff_placements")):
		if raw_placement is StuffPlacementDataScript and raw_placement.cell == cell:
			result.append(raw_placement)
	result.sort_custom(func(a: StuffPlacementDataScript, b: StuffPlacementDataScript) -> bool:
		return String(a.placement_id) < String(b.placement_id)
	)
	return result


## Returns `{success: bool, message: String, placement: StuffPlacementData}`.
static func add_stuff(
	level: Resource,
	cell: Vector3i,
	definition: Resource,
	facing_index: int = 0
) -> Dictionary:
	if level == null or not definition is StuffDefinition:
		return {"success": false, "message": "关卡元素定义无效", "placement": null}
	for existing in get_stuff_at(level, cell):
		if (
			existing.definition == null
			or not definition.can_coexist_with(existing.definition)
		):
			return {
				"success": false,
				"message": "%s 与当前格上的 %s 互斥" % [
					definition.display_name,
					existing.definition.display_name if existing.definition != null else "无效元素",
				],
				"placement": null,
			}
	var placement := StuffPlacementDataScript.new()
	placement.configure(
		_next_stuff_id(level, definition.stuff_id),
		cell,
		definition,
		clampi(facing_index, 0, _stuff_facing_count(level) - 1)
	)
	var next_placements: Array[StuffPlacementDataScript] = []
	for raw_placement in _as_array(level.get("stuff_placements")):
		if raw_placement is StuffPlacementDataScript:
			next_placements.append(raw_placement)
	next_placements.append(placement)
	level.set("stuff_placements", next_placements)
	level.emit_changed()
	return {"success": true, "message": "已放置 %s" % definition.display_name, "placement": placement}


static func remove_stuff(level: Resource, placement_id: StringName) -> bool:
	if level == null or placement_id.is_empty():
		return false
	var next_placements: Array[StuffPlacementDataScript] = []
	var removed := false
	for raw_placement in _as_array(level.get("stuff_placements")):
		if raw_placement is StuffPlacementDataScript and raw_placement.placement_id == placement_id:
			removed = true
			continue
		next_placements.append(raw_placement)
	if not removed:
		return false
	level.set("stuff_placements", next_placements)
	level.emit_changed()
	return true


static func set_stuff_facing(level: Resource, placement_id: StringName, facing_index: int) -> bool:
	if level == null:
		return false
	for raw_placement in _as_array(level.get("stuff_placements")):
		if raw_placement is StuffPlacementDataScript and raw_placement.placement_id == placement_id:
			var next_facing := clampi(facing_index, 0, _stuff_facing_count(level) - 1)
			if raw_placement.facing_index == next_facing:
				return false
			raw_placement.facing_index = next_facing
			raw_placement.emit_changed()
			level.emit_changed()
			return true
	return false


static func get_ramp_at(
	level: Resource,
	shape: IGridShape,
	cell: Vector3i
) -> RampPlacementDataScript:
	if level == null or shape == null:
		return null
	for raw_ramp in _as_array(level.get("ramp_placements")):
		if raw_ramp is RampPlacementDataScript and cell in raw_ramp.get_footprint_cells(shape):
			return raw_ramp
	return null


## S1 authoring: click the lowest slope cell. The operation validates the
## complete footprint and automatically makes the low connector/base/footprint
## layer consistent while raising the high connector by exactly one layer.
## Returns `{success: bool, message: String, ramp: RampPlacementData}`.
static func place_ramp(
	level: Resource,
	shape: IGridShape,
	anchor_cell: Vector3i,
	facing_index: int,
	run_length: int,
	base_layer: int
) -> Dictionary:
	if level == null or shape == null:
		return {"success": false, "message": "关卡或网格无效", "ramp": null}
	if facing_index < 0 or facing_index >= shape.edge_count():
		return {"success": false, "message": "斜坡方向超出当前网格边数", "ramp": null}
	var ramp := RampPlacementDataScript.new()
	ramp.ramp_id = _next_ramp_id(level)
	ramp.anchor_cell = anchor_cell
	ramp.facing_index = facing_index
	ramp.run_length = clampi(run_length, 1, 4)
	ramp.base_layer = clampi(base_layer, 1, 3)
	var footprint := ramp.get_footprint_cells(shape)
	var low_cell := ramp.get_low_neighbor(shape)
	var high_cell := ramp.get_high_neighbor(shape)
	var grid_size: Vector2i = level.get("grid_size")
	for required_cell in footprint + [low_cell, high_cell]:
		if not shape.is_in_bounds(required_cell, grid_size):
			return {
				"success": false,
				"message": "斜坡占格或高低连接端位于地图外",
				"ramp": null,
			}
	for footprint_cell in footprint:
		if get_ramp_at(level, shape, footprint_cell) != null:
			return {"success": false, "message": "斜坡与已有斜坡重叠", "ramp": null}
	var anchor_data := get_or_create_grid_cell(level, anchor_cell)
	var terrain: TerrainDefinitionScript = anchor_data.get_effective_terrain(
		level.get("default_terrain") as TerrainDefinitionScript
	)
	for footprint_cell in footprint:
		var data := get_or_create_grid_cell(level, footprint_cell)
		data.terrain = terrain
		data.layer_count = ramp.base_layer
		data.emit_changed()
	get_or_create_grid_cell(level, low_cell).layer_count = ramp.base_layer
	get_or_create_grid_cell(level, high_cell).layer_count = ramp.base_layer + 1
	var next_ramps: Array[RampPlacementDataScript] = []
	for raw_ramp in _as_array(level.get("ramp_placements")):
		if raw_ramp is RampPlacementDataScript:
			next_ramps.append(raw_ramp)
	next_ramps.append(ramp)
	level.set("ramp_placements", next_ramps)
	level.emit_changed()
	return {"success": true, "message": "已放置 1:%d 斜坡" % ramp.run_length, "ramp": ramp}


static func remove_ramp(level: Resource, ramp_id: StringName) -> bool:
	if level == null or ramp_id.is_empty():
		return false
	var next_ramps: Array[RampPlacementDataScript] = []
	var removed := false
	for raw_ramp in _as_array(level.get("ramp_placements")):
		if raw_ramp is RampPlacementDataScript and raw_ramp.ramp_id == ramp_id:
			removed = true
			continue
		next_ramps.append(raw_ramp)
	if not removed:
		return false
	level.set("ramp_placements", next_ramps)
	level.emit_changed()
	return true


static func _materialize_missing_cells(
	level: Resource,
	shape: IGridShape,
	default_terrain: TerrainDefinitionScript
) -> int:
	var existing: Dictionary = {}
	var next_cells: Array[GridCellDataScript] = []
	for raw_cell in _as_array(level.get("grid_cells")):
		if raw_cell is GridCellDataScript:
			existing[raw_cell.cell] = true
		next_cells.append(raw_cell)
	var added := 0
	var grid_size: Vector2i = level.get("grid_size")
	for cell in shape.enumerate_cells(grid_size):
		if existing.has(cell):
			continue
		var created := GridCellDataScript.new()
		created.configure(cell, default_terrain, 1, true, true)
		next_cells.append(created)
		added += 1
	level.set("grid_cells", next_cells)
	return added


static func _next_stuff_id(level: Resource, stuff_id: StringName) -> StringName:
	var prefix := String(stuff_id).strip_edges().to_snake_case()
	if prefix.is_empty():
		prefix = "stuff"
	var used: Dictionary = {}
	for raw_placement in _as_array(level.get("stuff_placements")):
		if raw_placement is StuffPlacementDataScript:
			used[raw_placement.placement_id] = true
	var index := 1
	while used.has(StringName("%s_%d" % [prefix, index])):
		index += 1
	return StringName("%s_%d" % [prefix, index])


static func _next_ramp_id(level: Resource) -> StringName:
	var used: Dictionary = {}
	for raw_ramp in _as_array(level.get("ramp_placements")):
		if raw_ramp is RampPlacementDataScript:
			used[raw_ramp.ramp_id] = true
	var index := 1
	while used.has(StringName("ramp_%d" % index)):
		index += 1
	return StringName("ramp_%d" % index)


static func _stuff_facing_count(level: Resource) -> int:
	return 6 if int(level.get("grid_shape")) == 0 else 8


static func _as_array(value: Variant) -> Array:
	return value if value is Array else []
