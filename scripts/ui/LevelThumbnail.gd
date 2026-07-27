@tool
## Read-only 2D preview of LevelResource data. It never instantiates gameplay nodes.
class_name LevelThumbnail
extends Control

const HEX_SHAPE: int = 0
const SQUARE_SHAPE: int = 1
const BACKGROUND_COLOR := Color(0.055, 0.075, 0.10, 1.0)
const EMPTY_COLOR := Color(0.17, 0.19, 0.21, 1.0)
const OUTLINE_COLOR := Color(0.60, 0.69, 0.76, 0.62)
const BLOCKED_COLOR := Color(0.34, 0.37, 0.40, 1.0)
const SPAWN_COLOR := Color(0.28, 0.92, 0.55, 1.0)
const BASE_COLOR := Color(0.32, 0.72, 1.0, 1.0)
const DRAW_PADDING: float = 10.0

var _level: LevelResource
var _shape: IGridShape
var _cell_draw_data: Array[Dictionary] = []
var _path_draw_data: Array[PackedVector2Array] = []
var _spawn_draw_data: Array[Dictionary] = []
var _base_draw_data: Array[Dictionary] = []
var _world_min := Vector2.ZERO
var _world_max := Vector2.ONE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_level(value: LevelResource) -> void:
	_level = value
	_rebuild_draw_data()
	queue_redraw()


func clear() -> void:
	_level = null
	_shape = null
	_cell_draw_data.clear()
	_path_draw_data.clear()
	_spawn_draw_data.clear()
	_base_draw_data.clear()
	queue_redraw()


func get_level() -> LevelResource:
	return _level


## Test-only read query. The deep copy prevents callers from mutating cached draw data.
func debug_get_draw_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for data in _cell_draw_data:
		result.append(data.duplicate(true))
	return result


func debug_get_geometry_tag() -> StringName:
	if _level == null or _shape == null:
		return &""
	return _level.get_geometry_tag()


func debug_get_path_draw_data() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for points in _path_draw_data:
		result.append(points.duplicate())
	return result


func debug_get_spawn_draw_data() -> Array[Dictionary]:
	return _spawn_draw_data.duplicate(true)


func debug_get_base_draw_data() -> Array[Dictionary]:
	return _base_draw_data.duplicate(true)


func _rebuild_draw_data() -> void:
	_cell_draw_data.clear()
	_path_draw_data.clear()
	_spawn_draw_data.clear()
	_base_draw_data.clear()
	_shape = null
	if _level == null:
		return
	if _level.grid_shape != HEX_SHAPE and _level.grid_shape != SQUARE_SHAPE:
		return
	if _level.grid_shape == HEX_SHAPE and _level.grid_size.x < 1:
		return
	if _level.grid_shape == SQUARE_SHAPE and (_level.grid_size.x < 1 or _level.grid_size.y < 1):
		return
	if _level.grid_shape == HEX_SHAPE:
		_shape = HexGridShape.new()
	else:
		_shape = SquareGridShape.new()
	var safe_cell_size := _level.grid_cell_size if is_finite(_level.grid_cell_size) and _level.grid_cell_size > 0.0 else 1.0
	_shape.setup(safe_cell_size)
	var path_cells := _collect_path_cells()
	for cell in _shape.enumerate_cells(_level.grid_size):
		var tile: Resource = _level.get_tile(cell)
		var polygon_world := PackedVector2Array()
		for corner in _shape.get_corners(cell):
			polygon_world.append(Vector2(corner.x, corner.z))
		var height_level := int(tile.get("height_level")) if tile != null else 0
		_cell_draw_data.append({
			"cell": cell,
			"polygon_world": polygon_world,
			"color": _resolve_terrain_color(cell, tile, height_level, path_cells),
			"height_level": height_level,
			"is_explicit": tile != null,
			"is_path": path_cells.has(cell),
		})
	_rebuild_overlay_data()
	_rebuild_world_bounds()


func _collect_path_cells() -> Dictionary:
	var result: Dictionary = {}
	for path in _level.paths:
		if path == null:
			continue
		for cell in path.cells:
			if _shape.is_in_bounds(cell, _level.grid_size):
				result[cell] = true
	return result


func _resolve_terrain_color(
	cell: Vector3i,
	tile: Resource,
	height_level: int,
	path_cells: Dictionary
) -> Color:
	if path_cells.has(cell):
		return _level.path_terrain_color
	var height_color := _level.get_height_color(height_level)
	if tile == null:
		return height_color
	var fallback := BLOCKED_COLOR if tile.has_method("is_blocked") and bool(tile.call("is_blocked")) else height_color
	if tile.has_method("get_terrain_color"):
		return Color(tile.call("get_terrain_color", fallback))
	return fallback


func _rebuild_overlay_data() -> void:
	for path in _level.paths:
		if path == null:
			continue
		var points := PackedVector2Array()
		for cell in path.cells:
			if _shape.is_in_bounds(cell, _level.grid_size):
				points.append(_cell_world_position(cell))
		if not points.is_empty():
			_path_draw_data.append(points)
	for spawn_index in range(_level.spawn_points.size()):
		var spawn_point: SpawnPointDefinition = _level.spawn_points[spawn_index]
		if spawn_point == null or not _shape.is_in_bounds(spawn_point.cell, _level.grid_size):
			continue
		var display_number := spawn_point.display_number if spawn_point.display_number > 0 else spawn_index + 1
		_spawn_draw_data.append({"position": _cell_world_position(spawn_point.cell), "number": display_number})
	if _level.base_points.is_empty():
		if _shape.is_in_bounds(_level.base_cell, _level.grid_size):
			_base_draw_data.append({"position": _cell_world_position(_level.base_cell), "number": 1})
		return
	for base_index in range(_level.base_points.size()):
		var base_point: Resource = _level.base_points[base_index]
		if base_point == null:
			continue
		var cell: Vector3i = base_point.get("cell")
		if not _shape.is_in_bounds(cell, _level.grid_size):
			continue
		var authored_number := int(base_point.get("display_number"))
		_base_draw_data.append({
			"position": _cell_world_position(cell),
			"number": authored_number if authored_number > 0 else base_index + 1,
		})


func _cell_world_position(cell: Vector3i) -> Vector2:
	var world := _shape.cell_to_world(cell)
	return Vector2(world.x, world.z)


func _rebuild_world_bounds() -> void:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for data in _cell_draw_data:
		var polygon: PackedVector2Array = data["polygon_world"]
		for point in polygon:
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
	if not is_finite(minimum.x) or not is_finite(minimum.y):
		_world_min = Vector2.ZERO
		_world_max = Vector2.ONE
		return
	_world_min = minimum
	_world_max = maximum


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	if _level == null or _shape == null or _cell_draw_data.is_empty():
		var placeholder_rect := Rect2(Vector2(6.0, 6.0), size - Vector2(12.0, 12.0))
		draw_rect(placeholder_rect, EMPTY_COLOR)
		draw_rect(placeholder_rect, OUTLINE_COLOR, false, 2.0)
		return
	for data in _cell_draw_data:
		var polygon := _polygon_to_local(data["polygon_world"])
		if polygon.size() < 3:
			continue
		draw_colored_polygon(polygon, Color(data["color"]))
		var outline := PackedVector2Array(polygon)
		outline.append(polygon[0])
		draw_polyline(outline, OUTLINE_COLOR, 1.0, true)
	for world_points in _path_draw_data:
		var local_points := PackedVector2Array()
		for point in world_points:
			local_points.append(_world_to_local(point))
		if local_points.size() >= 2:
			draw_polyline(local_points, _level.path_terrain_color.lightened(0.18), 3.0, true)
		for point in local_points:
			draw_circle(point, 2.5, _level.path_terrain_color.lightened(0.24))
	for marker in _spawn_draw_data:
		_draw_spawn_marker(_world_to_local(marker["position"]), int(marker["number"]))
	for marker in _base_draw_data:
		_draw_base_marker(_world_to_local(marker["position"]), int(marker["number"]))


func _polygon_to_local(world_polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in world_polygon:
		result.append(_world_to_local(point))
	return result


func _world_to_local(point: Vector2) -> Vector2:
	var world_span := _world_max - _world_min
	world_span.x = maxf(world_span.x, 0.001)
	world_span.y = maxf(world_span.y, 0.001)
	var available := Vector2(maxf(1.0, size.x - DRAW_PADDING * 2.0), maxf(1.0, size.y - DRAW_PADDING * 2.0))
	var scale_factor := minf(available.x / world_span.x, available.y / world_span.y)
	var used_size := world_span * scale_factor
	var origin := (size - used_size) * 0.5
	return origin + (point - _world_min) * scale_factor


func _draw_spawn_marker(center: Vector2, number: int) -> void:
	var radius := clampf(minf(size.x, size.y) * 0.045, 5.0, 11.0)
	draw_circle(center, radius, Color(0.025, 0.055, 0.065, 0.94))
	draw_arc(center, radius, 0.0, TAU, 20, SPAWN_COLOR, 2.5, true)
	_draw_marker_number(center, number, SPAWN_COLOR)


func _draw_base_marker(center: Vector2, number: int) -> void:
	var radius := clampf(minf(size.x, size.y) * 0.05, 6.0, 12.0)
	var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	draw_rect(rect, Color(0.025, 0.055, 0.065, 0.94))
	draw_rect(rect, BASE_COLOR, false, 2.5)
	_draw_marker_number(center, number, BASE_COLOR)


func _draw_marker_number(center: Vector2, number: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := clampi(roundi(minf(size.x, size.y) * 0.055), 10, 16)
	var width := float(font_size * 2)
	var text_position := center + Vector2(-width * 0.5, float(font_size) * 0.38)
	draw_string_outline(font, text_position, str(maxi(1, number)), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 3, Color(0.01, 0.02, 0.03, 0.95))
	draw_string(font, text_position, str(maxi(1, number)), HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color.lightened(0.25))
