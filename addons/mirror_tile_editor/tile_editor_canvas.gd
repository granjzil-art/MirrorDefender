@tool
extends Control

const DRAG_KIND := "mirror_tile_preset"
const HEX_SHAPE := 0
const CANVAS_PADDING := 36.0
const MIN_CELL_PIXELS := 18.0
const BUILDABLE_COLOR := Color(0.18, 0.48, 0.34, 1.0)
const DESTRUCTIBLE_COLOR := Color(0.63, 0.36, 0.16, 1.0)
const BLOCKED_COLOR := Color(0.23, 0.29, 0.36, 1.0)
const OUTLINE_COLOR := Color(0.52, 0.66, 0.80, 0.75)
const SELECTED_COLOR := Color(0.96, 0.83, 0.30, 1.0)
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")

signal cell_selected(cell: Vector3i)
signal layout_changed

var level: LevelResource
var selected_cell: Vector3i = Vector3i.ZERO
var has_selected_cell: bool = false

var _shape: IGridShape
var _origin := Vector2.ZERO
var _pixels_per_world_unit := MIN_CELL_PIXELS

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_refresh_layout)
	_refresh_layout()

func set_level(value: LevelResource) -> void:
	level = value
	has_selected_cell = false
	_refresh_layout()

func refresh() -> void:
	_refresh_layout()

func _refresh_layout() -> void:
	if level == null or size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return
	_shape = HexGridShape.new() if level.grid_shape == HEX_SHAPE else SquareGridShape.new()
	_shape.setup(1.0)
	var cells := _shape.enumerate_cells(level.grid_size)
	if cells.is_empty():
		queue_redraw()
		return
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for cell in cells:
		for corner in _shape.get_corners(cell):
			var point := Vector2(corner.x, corner.z)
			min_point = min_point.min(point)
			max_point = max_point.max(point)
	var world_size := max_point - min_point
	var available := size - Vector2(CANVAS_PADDING * 2.0, CANVAS_PADDING * 2.0)
	_pixels_per_world_unit = minf(
		available.x / maxf(1.0, world_size.x),
		available.y / maxf(1.0, world_size.y)
	)
	_pixels_per_world_unit = maxf(MIN_CELL_PIXELS, _pixels_per_world_unit)
	var content_size := world_size * _pixels_per_world_unit
	_origin = (size - content_size) * 0.5 - min_point * _pixels_per_world_unit
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.075, 0.11, 1.0))
	if level == null or _shape == null:
		return
	for cell in _shape.enumerate_cells(level.grid_size):
		var polygon := _cell_polygon(cell)
		var tile: Resource = level.get_tile(cell)
		draw_colored_polygon(polygon, _tile_color(tile))
		var outline := PackedVector2Array(polygon)
		outline.append(polygon[0])
		draw_polyline(outline, OUTLINE_COLOR, 1.2, true)
		if tile != null and bool(tile.call("is_destructible")):
			draw_circle(_cell_center(cell), maxf(4.0, _pixels_per_world_unit * 0.2), Color(0.65, 0.70, 0.70, 1.0))
	if has_selected_cell:
		var selected_polygon := _cell_polygon(selected_cell)
		var selected_outline := PackedVector2Array(selected_polygon)
		selected_outline.append(selected_polygon[0])
		draw_polyline(selected_outline, SELECTED_COLOR, 3.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _find_cell(event.position)
		if hit.is_empty():
			return
		selected_cell = hit.cell
		has_selected_cell = true
		cell_selected.emit(selected_cell)
		queue_redraw()
		accept_event()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind", "") != DRAG_KIND:
		return false
	return not _find_cell(at_position).is_empty()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var hit := _find_cell(at_position)
	if hit.is_empty() or level == null:
		return
	var preset_path: String = data.get("preset_path", "")
	var preset_resource: Resource = ResourceLoader.load(preset_path)
	if preset_resource == null:
		return
	var preset_type: int = preset_resource.get("tile_type")
	var preset_height: int = preset_resource.get("height_level")
	var tile: Resource = TileCellDataScript.new()
	tile.call("configure", hit.cell, preset_type, clampi(preset_height, 0, level.height_levels - 1))
	level.store_tile(tile)
	selected_cell = hit.cell
	has_selected_cell = true
	cell_selected.emit(selected_cell)
	layout_changed.emit()
	queue_redraw()

func _find_cell(point: Vector2) -> Dictionary:
	if level == null or _shape == null:
		return {}
	for cell in _shape.enumerate_cells(level.grid_size):
		if Geometry2D.is_point_in_polygon(point, _cell_polygon(cell)):
			return {"cell": cell}
	return {}

func _cell_polygon(cell: Vector3i) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in _shape.get_corners(cell):
		points.append(Vector2(corner.x, corner.z) * _pixels_per_world_unit + _origin)
	return points

func _cell_center(cell: Vector3i) -> Vector2:
	var world := _shape.cell_to_world(cell)
	return Vector2(world.x, world.z) * _pixels_per_world_unit + _origin

func _tile_color(tile: Resource) -> Color:
	if tile == null or bool(tile.call("is_buildable")):
		return BUILDABLE_COLOR
	if bool(tile.call("is_destructible")):
		return DESTRUCTIBLE_COLOR
	return BLOCKED_COLOR
