@tool
extends Control

const DRAG_KIND := "mirror_tile_preset"
const HEX_SHAPE := 0
const BACKGROUND_COLOR := Color(0.055, 0.075, 0.11, 1.0)
const OUTLINE_COLOR := Color(0.65, 0.75, 0.86, 0.72)
const SELECTED_COLOR := Color(0.98, 0.85, 0.30, 1.0)
const BLOCKED_MARKER_COLOR := Color(0.10, 0.13, 0.18, 0.9)
const OBSTACLE_COLOR := Color(0.65, 0.70, 0.70, 1.0)
const WALL_DARKEN := 0.62
const CAMERA_PITCH := deg_to_rad(52.0)
const DEFAULT_YAW := deg_to_rad(-35.0)
const MIN_ZOOM := 6.0
const MAX_ZOOM := 180.0
const CAMERA_MOVE_SPEED := 7.0
const CAMERA_ROTATE_SPEED := deg_to_rad(72.0)
const CAMERA_ZOOM_SPEED := 80.0
const WHEEL_ZOOM_STEP := 10.0
const BRUSH_SAMPLE_SPACING := 4.0
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")

enum BrushMode {
	NONE,
	TILE_TYPE,
	HEIGHT,
}

signal cell_selected(cell: Vector3i)
signal layout_changed

var level: LevelResource
var selected_cell: Vector3i = Vector3i.ZERO
var has_selected_cell: bool = false

var _shape: IGridShape
var _ordered_cells: Array[Vector3i] = []
var _camera_target := Vector3.ZERO
var _camera_yaw: float = DEFAULT_YAW
var _view_zoom: float = 48.0
var _brush_mode: int = BrushMode.NONE
var _brush_preset_path := ""
var _height_brush_level: int = -1
var _is_painting: bool = false
var _last_paint_position := Vector2.ZERO
var _painted_cells: Dictionary = {}

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_refresh_layout)
	_refresh_layout()

func _process(delta: float) -> void:
	if not has_focus():
		return
	var movement := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W):
		movement.y += 1.0
	if Input.is_key_pressed(KEY_S):
		movement.y -= 1.0
	var did_change := false
	if movement != Vector2.ZERO:
		var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
		var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
		var planar_move := (right * movement.x + forward * movement.y).normalized()
		_camera_target += planar_move * CAMERA_MOVE_SPEED * delta
		did_change = true
	if Input.is_key_pressed(KEY_Q):
		_camera_yaw += CAMERA_ROTATE_SPEED * delta
		did_change = true
	if Input.is_key_pressed(KEY_E):
		_camera_yaw -= CAMERA_ROTATE_SPEED * delta
		did_change = true
	if Input.is_key_pressed(KEY_X):
		_view_zoom = clampf(_view_zoom + CAMERA_ZOOM_SPEED * delta, MIN_ZOOM, MAX_ZOOM)
		did_change = true
	if Input.is_key_pressed(KEY_C):
		_view_zoom = clampf(_view_zoom - CAMERA_ZOOM_SPEED * delta, MIN_ZOOM, MAX_ZOOM)
		did_change = true
	if did_change:
		_refresh_draw_order()
		queue_redraw()

func set_level(value: LevelResource) -> void:
	level = value
	has_selected_cell = false
	_brush_mode = BrushMode.NONE
	_brush_preset_path = ""
	_height_brush_level = -1
	_painted_cells.clear()
	_refresh_layout()
	call_deferred("reset_view")

func set_brush_preset(value: String) -> void:
	_brush_preset_path = value
	_height_brush_level = -1
	_brush_mode = BrushMode.TILE_TYPE if not value.is_empty() else BrushMode.NONE
	_painted_cells.clear()

func set_height_brush(value: int) -> void:
	_height_brush_level = clampi(value, 0, level.height_levels - 1) if level != null and value >= 0 else -1
	_brush_preset_path = ""
	_brush_mode = BrushMode.HEIGHT if _height_brush_level >= 0 else BrushMode.NONE
	_painted_cells.clear()

func refresh() -> void:
	_refresh_layout()

func reset_view() -> void:
	_camera_yaw = DEFAULT_YAW
	if _ordered_cells.is_empty():
		queue_redraw()
		return
	var min_world := Vector3(INF, 0.0, INF)
	var max_world := Vector3(-INF, 0.0, -INF)
	for cell in _ordered_cells:
		for corner in _shape.get_corners(cell):
			min_world.x = minf(min_world.x, corner.x)
			min_world.z = minf(min_world.z, corner.z)
			max_world.x = maxf(max_world.x, corner.x)
			max_world.z = maxf(max_world.z, corner.z)
	_camera_target = Vector3(
		(min_world.x + max_world.x) * 0.5,
		0.0,
		(min_world.z + max_world.z) * 0.5
	)
	var world_span := maxf(max_world.x - min_world.x, max_world.z - min_world.z)
	var viewport_span := minf(size.x, size.y)
	_view_zoom = clampf(viewport_span / maxf(1.0, world_span * 1.45), MIN_ZOOM, MAX_ZOOM)
	_refresh_draw_order()
	queue_redraw()

func _refresh_layout() -> void:
	if level == null:
		_ordered_cells.clear()
		queue_redraw()
		return
	_shape = HexGridShape.new() if level.grid_shape == HEX_SHAPE else SquareGridShape.new()
	_shape.setup(level.grid_cell_size)
	_ordered_cells = _shape.enumerate_cells(level.grid_size)
	_refresh_draw_order()
	queue_redraw()

func _refresh_draw_order() -> void:
	if _shape == null:
		return
	_ordered_cells.sort_custom(Callable(self, "_sort_cells_by_depth"))

func _sort_cells_by_depth(a: Vector3i, b: Vector3i) -> bool:
	return _cell_depth(a) < _cell_depth(b)

func _cell_depth(cell: Vector3i) -> float:
	var camera_back := Vector3(
		sin(_camera_yaw) * cos(CAMERA_PITCH),
		sin(CAMERA_PITCH),
		cos(_camera_yaw) * cos(CAMERA_PITCH)
	)
	return _shape.cell_to_world(cell).dot(camera_back)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	if level == null or _shape == null:
		return
	for cell in _ordered_cells:
		_draw_cell(cell)
	if has_selected_cell:
		var selected_polygon := _top_polygon(selected_cell)
		if not selected_polygon.is_empty():
			var selected_outline := PackedVector2Array(selected_polygon)
			selected_outline.append(selected_polygon[0])
			draw_polyline(selected_outline, SELECTED_COLOR, 3.0, true)

func _draw_cell(cell: Vector3i) -> void:
	var tile: Resource = level.get_tile(cell)
	if tile == null:
		return
	var top_color := _height_color(tile)
	var corners := _shape.get_corners(cell)
	var current_height := _tile_world_height(tile)
	for edge_index in range(corners.size()):
		var neighbor_cell := _shape.neighbor_across_edge(cell, edge_index)
		var neighbor_tile: Resource = level.get_tile(neighbor_cell)
		var neighbor_height := _tile_world_height(neighbor_tile)
		if current_height <= neighbor_height:
			continue
		var a := corners[edge_index]
		var b := corners[(edge_index + 1) % corners.size()]
		var wall := PackedVector2Array([
			_project_world(Vector3(a.x, current_height, a.z)),
			_project_world(Vector3(b.x, current_height, b.z)),
			_project_world(Vector3(b.x, neighbor_height, b.z)),
			_project_world(Vector3(a.x, neighbor_height, a.z)),
		])
		draw_colored_polygon(wall, _wall_color(top_color))
		var wall_outline := PackedVector2Array(wall)
		wall_outline.append(wall[0])
		draw_polyline(wall_outline, OUTLINE_COLOR.darkened(0.3), 1.0, true)
	var polygon := _top_polygon(cell)
	if polygon.is_empty():
		return
	draw_colored_polygon(polygon, top_color)
	var outline := PackedVector2Array(polygon)
	outline.append(polygon[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.2, true)
	_draw_tile_marker(cell, tile, current_height)

func _draw_tile_marker(cell: Vector3i, tile: Resource, world_height: float) -> void:
	var center_world := _shape.cell_to_world(cell)
	var center := _project_world(Vector3(center_world.x, world_height, center_world.z))
	var marker_radius := clampf(_view_zoom * 0.12, 4.0, 12.0)
	if bool(tile.call("is_destructible")):
		draw_circle(center, marker_radius, OBSTACLE_COLOR)
		draw_arc(center, marker_radius, 0.0, TAU, 20, BLOCKED_MARKER_COLOR, 1.5, true)
	elif bool(tile.call("is_blocked")):
		var diagonal := marker_radius * 0.8
		draw_line(center + Vector2(-diagonal, -diagonal), center + Vector2(diagonal, diagonal), BLOCKED_MARKER_COLOR, 2.0, true)
		draw_line(center + Vector2(-diagonal, diagonal), center + Vector2(diagonal, -diagonal), BLOCKED_MARKER_COLOR, 2.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_view_zoom = clampf(_view_zoom + WHEEL_ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_view_zoom = clampf(_view_zoom - WHEEL_ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_is_painting = true
				_painted_cells.clear()
				_last_paint_position = event.position
				_select_cell_at(event.position)
				_paint_at(event.position)
			else:
				_is_painting = false
				_painted_cells.clear()
			accept_event()
			return
	if event is InputEventMouseMotion and _is_painting:
		_paint_between(_last_paint_position, event.position)
		_last_paint_position = event.position
		accept_event()

func _select_cell_at(position: Vector2) -> void:
	var hit := _find_cell(position)
	if hit.is_empty():
		return
	selected_cell = hit.cell
	has_selected_cell = true
	cell_selected.emit(selected_cell)
	queue_redraw()

func _paint_between(from: Vector2, to: Vector2) -> void:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / BRUSH_SAMPLE_SPACING))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		_paint_at(point)

func _paint_at(position: Vector2) -> void:
	if _brush_mode == BrushMode.NONE:
		return
	var hit := _find_cell(position)
	if hit.is_empty():
		return
	var cell: Vector3i = hit.cell
	if _painted_cells.has(cell):
		return
	var did_paint := false
	if _brush_mode == BrushMode.TILE_TYPE:
		did_paint = _apply_preset_to_cell(cell, _brush_preset_path)
	elif _brush_mode == BrushMode.HEIGHT:
		did_paint = _apply_height_to_cell(cell, _height_brush_level)
	if did_paint:
		_painted_cells[cell] = true
		selected_cell = cell
		has_selected_cell = true
		cell_selected.emit(selected_cell)
		layout_changed.emit()
		queue_redraw()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind", "") != DRAG_KIND:
		return false
	return not _find_cell(at_position).is_empty()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var hit := _find_cell(at_position)
	if hit.is_empty() or level == null:
		return
	var preset_path: String = data.get("preset_path", "")
	if not _apply_preset_to_cell(hit.cell, preset_path):
		return
	set_brush_preset(preset_path)
	selected_cell = hit.cell
	has_selected_cell = true
	cell_selected.emit(selected_cell)
	layout_changed.emit()
	queue_redraw()

func _apply_preset_to_cell(cell: Vector3i, preset_path: String) -> bool:
	if level == null or preset_path.is_empty():
		return false
	var preset_resource: Resource = ResourceLoader.load(preset_path)
	if preset_resource == null:
		return false
	var preset_type: int = int(preset_resource.get("tile_type"))
	var preset_height: int = int(preset_resource.get("height_level"))
	var tile: Resource = TileCellDataScript.new()
	tile.call("configure", cell, preset_type, clampi(preset_height, 0, level.height_levels - 1))
	level.store_tile(tile)
	return true

func _apply_height_to_cell(cell: Vector3i, height_level: int) -> bool:
	if level == null:
		return false
	var tile: Resource = level.get_tile(cell)
	if tile == null:
		return false
	var target_height := clampi(height_level, 0, level.height_levels - 1)
	if int(tile.get("height_level")) == target_height:
		return false
	tile.call("set_height_level", target_height, level.height_levels)
	level.emit_changed()
	return true

func _find_cell(point: Vector2) -> Dictionary:
	if level == null or _shape == null:
		return {}
	for index in range(_ordered_cells.size() - 1, -1, -1):
		var cell := _ordered_cells[index]
		if Geometry2D.is_point_in_polygon(point, _top_polygon(cell)):
			return {"cell": cell}
	return {}

func _top_polygon(cell: Vector3i) -> PackedVector2Array:
	if level == null or _shape == null:
		return PackedVector2Array()
	var tile: Resource = level.get_tile(cell)
	var world_height := _tile_world_height(tile)
	var points := PackedVector2Array()
	for corner in _shape.get_corners(cell):
		points.append(_project_world(Vector3(corner.x, world_height, corner.z)))
	return points

func _project_world(world: Vector3) -> Vector2:
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var up := Vector3(
		-sin(_camera_yaw) * sin(CAMERA_PITCH),
		cos(CAMERA_PITCH),
		-cos(_camera_yaw) * sin(CAMERA_PITCH)
	)
	var relative := world - _camera_target
	return Vector2(
		size.x * 0.5 + relative.dot(right) * _view_zoom,
		size.y * 0.5 - relative.dot(up) * _view_zoom
	)

func _tile_world_height(tile: Resource) -> float:
	if tile == null or level == null:
		return 0.0
	var height_level: int = int(tile.get("height_level"))
	return float(height_level) * level.height_step

func _height_color(tile: Resource) -> Color:
	if level == null:
		return Color.WHITE
	var height_level: int = 0 if tile == null else int(tile.get("height_level"))
	return level.get_height_color(height_level)

func _wall_color(top_color: Color) -> Color:
	return Color(
		top_color.r * WALL_DARKEN,
		top_color.g * WALL_DARKEN,
		top_color.b * WALL_DARKEN,
		top_color.a
	)
