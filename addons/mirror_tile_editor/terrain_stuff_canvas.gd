@tool
## TerrainStuffCanvas -- authoring-only 2.5D viewport for canonical Terrain,
## ramps, and Stuff. Path/wave/camera authoring is intentionally absent.
class_name TerrainStuffCanvas
extends Control

const HEX_SHAPE := 0
const BACKGROUND_COLOR := Color(0.055, 0.075, 0.11, 1.0)
const OUTLINE_COLOR := Color(0.65, 0.75, 0.86, 0.72)
const SELECTED_COLOR := Color(0.98, 0.85, 0.30, 1.0)
const PATH_COLOR := Color("ffb93b")
const WALL_DARKEN := 0.62
const DEFAULT_PITCH := deg_to_rad(52.0)
const MIN_PITCH := deg_to_rad(18.0)
const MAX_PITCH := deg_to_rad(82.0)
const DEFAULT_YAW := deg_to_rad(-35.0)
const MIN_ZOOM := 6.0
const MAX_ZOOM := 300.0
const CAMERA_MOVE_SPEED := 7.0
const CAMERA_ROTATE_SPEED := deg_to_rad(72.0)
const CAMERA_PITCH_SPEED := deg_to_rad(55.0)
const WHEEL_ZOOM_STEP := 10.0
const BRUSH_SAMPLE_SPACING := 4.0

const Authoring := preload("res://addons/mirror_tile_editor/terrain_stuff_authoring.gd")
const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")

enum ToolMode {
	SELECT,
	TERRAIN,
	LAYER,
	PERMISSIONS,
	STUFF,
	RAMP,
}

signal cell_selected(cell: Vector3i)
signal content_changed
signal operation_reported(message: String, success: bool)

var level: LevelResource
var selected_cell: Vector3i = Vector3i.ZERO
var has_selected_cell: bool = false

var _shape: IGridShape
var _ordered_cells: Array[Vector3i] = []
var _path_cells: Dictionary = {}
var _ramp_bindings: Dictionary = {}
var _camera_target := Vector3.ZERO
var _camera_yaw: float = DEFAULT_YAW
var _camera_pitch: float = DEFAULT_PITCH
var _view_zoom: float = 48.0
var _tool_mode: int = ToolMode.SELECT
var _terrain_brush: TerrainDefinitionScript
var _layer_brush: int = 1
var _permission_tile: bool = true
var _permission_edge: bool = true
var _stuff_brush: StuffDefinitionScript
var _stuff_facing: int = 0
var _ramp_facing: int = 0
var _ramp_run_length: int = 1
var _ramp_base_layer: int = 1
var _ramp_terrain_override: TerrainDefinitionScript
var _is_painting: bool = false
var _last_paint_position := Vector2.ZERO
var _painted_cells: Dictionary = {}
var _hover_cell: Vector3i = Vector3i.ZERO
var _has_hover_cell: bool = false
var _view_reset_pending: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(_on_canvas_resized)
	visibility_changed.connect(_on_canvas_visibility_changed)
	set_process(true)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not has_focus():
		return
	var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += forward
	if Input.is_key_pressed(KEY_S):
		move -= forward
	if Input.is_key_pressed(KEY_D):
		move += right
	if Input.is_key_pressed(KEY_A):
		move -= right
	var changed := false
	if not move.is_zero_approx():
		_camera_target += move.normalized() * CAMERA_MOVE_SPEED * delta
		changed = true
	if Input.is_key_pressed(KEY_Q):
		_camera_yaw += CAMERA_ROTATE_SPEED * delta
		changed = true
	if Input.is_key_pressed(KEY_E):
		_camera_yaw -= CAMERA_ROTATE_SPEED * delta
		changed = true
	var pitch_input := 0.0
	if Input.is_key_pressed(KEY_X):
		pitch_input -= 1.0
	if Input.is_key_pressed(KEY_C):
		pitch_input += 1.0
	if pitch_input != 0.0:
		_camera_pitch = clampf(
			_camera_pitch + CAMERA_PITCH_SPEED * delta * pitch_input,
			MIN_PITCH,
			MAX_PITCH
		)
		changed = true
	if changed:
		_refresh_draw_order()
		queue_redraw()


func set_level(value: LevelResource) -> void:
	level = value
	has_selected_cell = false
	_tool_mode = ToolMode.SELECT
	_refresh_layout()
	reset_view()


func set_select_tool() -> void:
	_tool_mode = ToolMode.SELECT
	queue_redraw()


func set_terrain_brush(terrain: TerrainDefinitionScript) -> void:
	_terrain_brush = terrain
	_tool_mode = ToolMode.TERRAIN if terrain != null else ToolMode.SELECT
	queue_redraw()


func set_layer_brush(layer_count: int) -> void:
	_layer_brush = clampi(layer_count, 1, 4)
	_tool_mode = ToolMode.LAYER
	queue_redraw()


func set_permission_brush(allows_tile: bool, allows_edge: bool) -> void:
	_permission_tile = allows_tile
	_permission_edge = allows_edge
	_tool_mode = ToolMode.PERMISSIONS
	queue_redraw()


func set_stuff_brush(definition: StuffDefinitionScript, facing_index: int = 0) -> void:
	_stuff_brush = definition
	_stuff_facing = maxi(0, facing_index)
	_tool_mode = ToolMode.STUFF if definition != null else ToolMode.SELECT
	queue_redraw()


func set_ramp_brush(
	facing_index: int,
	run_length: int,
	base_layer: int,
	terrain_override: TerrainDefinitionScript = null
) -> void:
	_ramp_facing = maxi(0, facing_index)
	_ramp_run_length = clampi(run_length, 1, 4)
	_ramp_base_layer = clampi(base_layer, 1, 3)
	_ramp_terrain_override = terrain_override
	_tool_mode = ToolMode.RAMP
	queue_redraw()


func get_tool_mode() -> int:
	return _tool_mode


func refresh() -> void:
	_rebuild_path_cells()
	_rebuild_ramp_bindings()
	_refresh_draw_order()
	queue_redraw()


func reset_view() -> void:
	_camera_yaw = DEFAULT_YAW
	_camera_pitch = DEFAULT_PITCH
	if _ordered_cells.is_empty() or size.x <= 1.0 or size.y <= 1.0:
		# Main-screen plugins start hidden and can remain at a zero layout size
		# indefinitely. Never enqueue reset_view recursively in that state: the
		# unbounded deferred-call queue can crash the Godot 4.7 editor process.
		_view_reset_pending = true
		return
	_view_reset_pending = false
	var minimum := Vector3(INF, 0.0, INF)
	var maximum := Vector3(-INF, 0.0, -INF)
	for cell in _ordered_cells:
		for corner in _shape.get_corners(cell):
			minimum.x = minf(minimum.x, corner.x)
			minimum.z = minf(minimum.z, corner.z)
			maximum.x = maxf(maximum.x, corner.x)
			maximum.z = maxf(maximum.z, corner.z)
	_camera_target = Vector3(
		(minimum.x + maximum.x) * 0.5,
		0.0,
		(minimum.z + maximum.z) * 0.5
	)
	var world_span := maxf(maximum.x - minimum.x, maximum.z - minimum.z)
	var viewport_span := minf(size.x, size.y)
	_view_zoom = clampf(viewport_span / maxf(1.0, world_span * 1.45), MIN_ZOOM, MAX_ZOOM)
	_refresh_draw_order()
	queue_redraw()


func _on_canvas_resized() -> void:
	if _view_reset_pending:
		reset_view()


func _on_canvas_visibility_changed() -> void:
	if _view_reset_pending and is_visible_in_tree():
		reset_view()


func _refresh_layout() -> void:
	_ordered_cells.clear()
	_ramp_bindings.clear()
	_path_cells.clear()
	if level == null:
		queue_redraw()
		return
	_shape = HexGridShape.new() if level.grid_shape == HEX_SHAPE else SquareGridShape.new()
	_shape.setup(level.grid_cell_size)
	_ordered_cells = _shape.enumerate_cells(level.grid_size)
	_rebuild_path_cells()
	_rebuild_ramp_bindings()
	_refresh_draw_order()
	queue_redraw()


func _refresh_draw_order() -> void:
	if _shape == null:
		return
	_ordered_cells.sort_custom(Callable(self, "_sort_cells_by_depth"))


func _sort_cells_by_depth(a: Vector3i, b: Vector3i) -> bool:
	var camera_back := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	)
	return _shape.cell_to_world(a).dot(camera_back) < _shape.cell_to_world(b).dot(camera_back)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	if level == null or _shape == null:
		return
	for cell in _ordered_cells:
		_draw_cell(cell)
	_draw_ramps()
	_draw_ramp_preview()
	if has_selected_cell:
		_draw_cell_outline(selected_cell, SELECTED_COLOR, 3.0)


func _draw_cell(cell: Vector3i) -> void:
	var top_color := _terrain_color(cell)
	var corners := _shape.get_corners(cell)
	for edge_index in range(corners.size()):
		var neighbor := _shape.neighbor_across_edge(cell, edge_index)
		var a: Vector3 = corners[edge_index]
		var b: Vector3 = corners[(edge_index + 1) % corners.size()]
		var current_a := _surface_height_at(cell, a)
		var current_b := _surface_height_at(cell, b)
		var neighbor_a := _surface_height_at(neighbor, a) if _shape.is_in_bounds(neighbor, level.grid_size) else 0.0
		var neighbor_b := _surface_height_at(neighbor, b) if _shape.is_in_bounds(neighbor, level.grid_size) else 0.0
		if current_a <= neighbor_a + 0.001 and current_b <= neighbor_b + 0.001:
			continue
		var wall := PackedVector2Array([
			_project_world(Vector3(a.x, current_a, a.z)),
			_project_world(Vector3(b.x, current_b, b.z)),
			_project_world(Vector3(b.x, neighbor_b, b.z)),
			_project_world(Vector3(a.x, neighbor_a, a.z)),
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
	_draw_permission_marker(cell)
	_draw_stuff_markers(cell)


func _draw_permission_marker(cell: Vector3i) -> void:
	var data := Authoring.get_grid_cell(level, cell)
	if data == null:
		return
	var center := _cell_center_screen(cell)
	var text := ""
	if not data.allows_tile_building:
		text += "■"
	if not data.allows_edge_building:
		text += "◇"
	if not text.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-12.0, 18.0),
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			24.0,
			13,
			Color(0.10, 0.13, 0.18, 0.92)
		)
	var corners := _shape.get_corners(cell)
	for edge_index in range(mini(corners.size(), GridCellDataScript.SQUARE_EDGE_COUNT)):
		if data.allows_edge(edge_index):
			continue
		var a: Vector3 = corners[edge_index]
		var b: Vector3 = corners[(edge_index + 1) % corners.size()]
		var screen_a := _project_world(Vector3(a.x, _surface_height_at(cell, a) + 0.012, a.z))
		var screen_b := _project_world(Vector3(b.x, _surface_height_at(cell, b) + 0.012, b.z))
		draw_line(screen_a, screen_b, Color(0.96, 0.18, 0.16, 0.96), 3.0, true)


func _draw_stuff_markers(cell: Vector3i) -> void:
	var placements := Authoring.get_stuff_at(level, cell)
	if placements.is_empty():
		return
	var center := _cell_center_screen(cell)
	var radius := clampf(_view_zoom * 0.105, 5.0, 12.0)
	for index in range(placements.size()):
		var placement: StuffPlacementDataScript = placements[index]
		var definition: StuffDefinitionScript = placement.definition
		if definition == null:
			continue
		var offset := _stuff_offset(index, placements.size(), radius)
		var marker_center := center + offset
		match definition.fallback_visual_kind:
			StuffDefinitionScript.FallbackVisualKind.SPIKES:
				_draw_spike_marker(marker_center, radius, definition.fallback_color)
			StuffDefinitionScript.FallbackVisualKind.HOLE:
				draw_circle(marker_center, radius * 1.15, definition.fallback_color)
			StuffDefinitionScript.FallbackVisualKind.ROCK:
				_draw_rock_marker(marker_center, radius, definition.fallback_color)
			StuffDefinitionScript.FallbackVisualKind.TREE:
				draw_circle(marker_center, radius, definition.fallback_color)
				draw_line(marker_center, marker_center + Vector2(0.0, radius * 1.25), Color(0.25, 0.15, 0.07), 2.0)
			_:
				draw_circle(marker_center, radius, definition.fallback_color)
		draw_arc(marker_center, radius * 1.18, 0.0, TAU, 20, OUTLINE_COLOR.darkened(0.45), 1.4, true)


func _draw_spike_marker(center: Vector2, radius: float, color: Color) -> void:
	for offset in [Vector2(-radius * 0.55, radius * 0.3), Vector2.ZERO, Vector2(radius * 0.55, radius * 0.3)]:
		var c: Vector2 = center + offset
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-radius * 0.28, radius * 0.35),
			c + Vector2(0.0, -radius * 0.72),
			c + Vector2(radius * 0.28, radius * 0.35),
		]), color)


func _draw_rock_marker(center: Vector2, radius: float, color: Color) -> void:
	var rock := PackedVector2Array([
		center + Vector2(-radius, radius * 0.55),
		center + Vector2(-radius * 0.72, -radius * 0.58),
		center + Vector2(-radius * 0.12, -radius),
		center + Vector2(radius * 0.82, -radius * 0.52),
		center + Vector2(radius, radius * 0.48),
		center + Vector2(radius * 0.18, radius),
	])
	draw_colored_polygon(rock, color)


func _draw_ramps() -> void:
	for raw_ramp in level.ramp_placements:
		if not raw_ramp is RampPlacementDataScript:
			continue
		var ramp: RampPlacementDataScript = raw_ramp
		var start := _cell_center_screen(ramp.anchor_cell)
		var high := _cell_center_screen(ramp.get_high_neighbor(_shape))
		var end := start.lerp(high, 0.82)
		draw_line(start, end, Color(0.30, 0.90, 1.0, 0.95), 3.0, true)
		var direction := (end - start).normalized()
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([
			end,
			end - direction * 11.0 + side * 5.0,
			end - direction * 11.0 - side * 5.0,
		]), Color(0.30, 0.90, 1.0, 0.95))


func _draw_ramp_preview() -> void:
	if _tool_mode != ToolMode.RAMP or not _has_hover_cell or _shape == null:
		return
	var preview := RampPlacementDataScript.new()
	preview.anchor_cell = _hover_cell
	preview.facing_index = _ramp_facing
	preview.run_length = _ramp_run_length
	preview.base_layer = _ramp_base_layer
	preview.terrain_override = _ramp_terrain_override
	var cells := preview.get_footprint_cells(_shape)
	var valid := true
	for cell in cells + [preview.get_low_neighbor(_shape), preview.get_high_neighbor(_shape)]:
		if not _shape.is_in_bounds(cell, level.grid_size):
			valid = false
			break
	var color := Color(0.25, 0.95, 0.65, 0.85) if valid else Color(1.0, 0.25, 0.25, 0.85)
	for cell in cells:
		_draw_cell_outline(cell, color, 2.5)


func _draw_cell_outline(cell: Vector3i, color: Color, width: float) -> void:
	if _shape == null or not _shape.is_in_bounds(cell, level.grid_size):
		return
	var polygon := _top_polygon(cell)
	if polygon.is_empty():
		return
	polygon.append(polygon[0])
	draw_polyline(polygon, color, width, true)


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
				_painted_cells.clear()
				_last_paint_position = event.position
				_select_cell_at(event.position)
				_apply_tool_at(event.position)
				_is_painting = _tool_mode in [ToolMode.TERRAIN, ToolMode.LAYER, ToolMode.PERMISSIONS]
			else:
				_is_painting = false
				_painted_cells.clear()
			accept_event()
			return
	if event is InputEventMouseMotion:
		var hit := _find_cell(event.position)
		_has_hover_cell = not hit.is_empty()
		if _has_hover_cell:
			_hover_cell = hit["cell"]
		if _is_painting:
			_paint_between(_last_paint_position, event.position)
			_last_paint_position = event.position
		queue_redraw()
		accept_event()


func _select_cell_at(position: Vector2) -> void:
	var hit := _find_cell(position)
	if hit.is_empty():
		return
	selected_cell = hit["cell"]
	has_selected_cell = true
	cell_selected.emit(selected_cell)
	queue_redraw()


func _paint_between(from: Vector2, to: Vector2) -> void:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / BRUSH_SAMPLE_SPACING))
	for index in range(steps + 1):
		_apply_tool_at(from.lerp(to, float(index) / float(steps)))


func _apply_tool_at(position: Vector2) -> void:
	if level == null or _tool_mode == ToolMode.SELECT:
		return
	var hit := _find_cell(position)
	if hit.is_empty():
		return
	var cell: Vector3i = hit["cell"]
	if _painted_cells.has(cell):
		return
	if _tool_mode == ToolMode.TERRAIN and Authoring.get_ramp_at(level, _shape, cell) != null:
		operation_reported.emit("斜坡坡体的地形由斜坡约束；请先移除斜坡。", false)
		return
	var layer_constraint := Authoring.get_ramp_layer_constraint(level, _shape, cell)
	if _tool_mode == ToolMode.LAYER and not layer_constraint.is_empty():
		if bool(layer_constraint.get("conflict", false)):
			operation_reported.emit("该平地同时被多个斜坡要求为不同层数；请调整斜坡连接。", false)
			return
		operation_reported.emit(
			"%s的层数由斜坡 %s 约束为 %d 层；请先移除斜坡。" % [
				str(layer_constraint["role"]),
				(layer_constraint["ramp"] as RampPlacementData).ramp_id,
				int(layer_constraint["expected_layer"]),
			],
			false
		)
		return
	var changed := false
	var message := ""
	var success := true
	match _tool_mode:
		ToolMode.TERRAIN:
			changed = Authoring.paint_terrain(level, cell, _terrain_brush)
		ToolMode.LAYER:
			changed = Authoring.paint_layer(level, cell, _layer_brush)
		ToolMode.PERMISSIONS:
			changed = Authoring.paint_permissions(level, cell, _permission_tile, _permission_edge, _shape)
		ToolMode.STUFF:
			var stuff_result := Authoring.add_stuff(level, cell, _stuff_brush, _stuff_facing)
			changed = bool(stuff_result["success"])
			success = changed
			message = str(stuff_result["message"])
		ToolMode.RAMP:
			var ramp_result := Authoring.place_ramp(
				level,
				_shape,
				cell,
				_ramp_facing,
				_ramp_run_length,
				_ramp_base_layer,
				_ramp_terrain_override
			)
			changed = bool(ramp_result["success"])
			success = changed
			message = str(ramp_result["message"])
	if changed:
		_painted_cells[cell] = true
		selected_cell = cell
		has_selected_cell = true
		refresh()
		cell_selected.emit(cell)
		content_changed.emit()
	if not message.is_empty():
		operation_reported.emit(message, success)


func _find_cell(point: Vector2) -> Dictionary:
	if level == null or _shape == null:
		return {}
	for index in range(_ordered_cells.size() - 1, -1, -1):
		var cell := _ordered_cells[index]
		if Geometry2D.is_point_in_polygon(point, _top_polygon(cell)):
			return {"cell": cell}
	return {}


func _top_polygon(cell: Vector3i) -> PackedVector2Array:
	var points := PackedVector2Array()
	if level == null or _shape == null:
		return points
	for corner in _shape.get_corners(cell):
		points.append(_project_world(Vector3(corner.x, _surface_height_at(cell, corner), corner.z)))
	return points


func _surface_height_at(cell: Vector3i, world_position: Vector3) -> float:
	if level == null or _shape == null or not _shape.is_in_bounds(cell, level.grid_size):
		return 0.0
	var grid_cell := Authoring.get_grid_cell(level, cell)
	var layer_count := grid_cell.layer_count if grid_cell != null else 1
	var binding: Dictionary = _ramp_bindings.get(cell, {})
	var ramp: RampPlacementDataScript = binding.get("ramp") as RampPlacementDataScript
	if ramp == null:
		return float(layer_count - 1) * level.layer_height
	var next_cell := _shape.neighbor_across_edge(ramp.anchor_cell, ramp.facing_index)
	var axis := _shape.cell_to_world(next_cell) - _shape.cell_to_world(ramp.anchor_cell)
	axis.y = 0.0
	var spacing := axis.length()
	if spacing <= 0.0:
		return float(ramp.base_layer - 1) * level.layer_height
	axis = axis.normalized()
	var anchor_center := _shape.cell_to_world(ramp.anchor_cell)
	var offset := Vector3(world_position.x - anchor_center.x, 0.0, world_position.z - anchor_center.z)
	var distance_from_low_edge := offset.dot(axis) + spacing * 0.5
	var ratio := clampf(distance_from_low_edge / (spacing * float(ramp.run_length)), 0.0, 1.0)
	return float(ramp.base_layer - 1) * level.layer_height + ratio * level.layer_height


func _cell_center_screen(cell: Vector3i) -> Vector2:
	var center := _shape.cell_to_world(cell)
	var height := _surface_height_at(cell, center)
	return _project_world(Vector3(center.x, height + 0.02, center.z))


func _terrain_color(cell: Vector3i) -> Color:
	if _path_cells.has(cell):
		return level.path_terrain_color
	var grid_cell := Authoring.get_grid_cell(level, cell)
	var terrain: TerrainDefinitionScript = (
		grid_cell.get_effective_terrain(level.default_terrain)
		if grid_cell != null
		else level.default_terrain
	)
	var binding: Dictionary = _ramp_bindings.get(cell, {})
	var ramp: RampPlacementDataScript = binding.get("ramp") as RampPlacementDataScript
	if ramp != null:
		terrain = ramp.get_effective_terrain(terrain)
	return terrain.fallback_color if terrain != null else Color.WHITE


func _rebuild_path_cells() -> void:
	_path_cells.clear()
	if level == null:
		return
	for path in level.paths:
		if path == null:
			continue
		for cell in path.cells:
			_path_cells[cell] = true


func _rebuild_ramp_bindings() -> void:
	_ramp_bindings.clear()
	if level == null or _shape == null:
		return
	for raw_ramp in level.ramp_placements:
		if not raw_ramp is RampPlacementDataScript:
			continue
		var ramp: RampPlacementDataScript = raw_ramp
		var footprint := ramp.get_footprint_cells(_shape)
		for index in range(footprint.size()):
			_ramp_bindings[footprint[index]] = {"ramp": ramp, "index": index}


func _project_world(world: Vector3) -> Vector2:
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var up := Vector3(
		-sin(_camera_yaw) * sin(_camera_pitch),
		cos(_camera_pitch),
		-cos(_camera_yaw) * sin(_camera_pitch)
	)
	var relative := world - _camera_target
	return Vector2(
		size.x * 0.5 + relative.dot(right) * _view_zoom,
		size.y * 0.5 - relative.dot(up) * _view_zoom
	)


func _stuff_offset(index: int, count: int, radius: float) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var angle := -PI * 0.5 + TAU * float(index) / float(count)
	return Vector2(cos(angle), sin(angle)) * radius * 1.05


func _wall_color(top_color: Color) -> Color:
	return Color(
		top_color.r * WALL_DARKEN,
		top_color.g * WALL_DARKEN,
		top_color.b * WALL_DARKEN,
		top_color.a
	)
