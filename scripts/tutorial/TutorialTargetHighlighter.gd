## World-space red/green cell and facing feedback for placement tutorial goals.
class_name TutorialTargetHighlighter
extends Node3D

var _director: TutorialDirector
var _grid: GridManager
var _cell_instance: MeshInstance3D
var _arrow_instance: MeshInstance3D
var _red_material: StandardMaterial3D
var _green_material: StandardMaterial3D
var _current_target: Dictionary = {}
var _linger_remaining: float = 0.0


func _ready() -> void:
	_red_material = _make_material(Color(1.0, 0.09, 0.08, 0.5))
	_green_material = _make_material(Color(0.1, 1.0, 0.34, 0.55))
	_cell_instance = MeshInstance3D.new()
	_cell_instance.visible = false
	add_child(_cell_instance)
	_arrow_instance = MeshInstance3D.new()
	_arrow_instance.visible = false
	add_child(_arrow_instance)


func configure(director: TutorialDirector, grid: GridManager) -> void:
	if _director != null and _director.presentation_changed.is_connected(_refresh):
		_director.presentation_changed.disconnect(_refresh)
	_director = director
	_grid = grid
	if _director != null:
		_director.presentation_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if _linger_remaining > 0.0:
		_linger_remaining -= maxf(0.0, delta)
		if _linger_remaining <= 0.0:
			_current_target.clear()
			_set_visible(false)


func _refresh() -> void:
	if not is_node_ready() or _grid == null:
		return
	var next_target := _director.get_active_placement_target() if _director != null else {}
	if next_target.is_empty():
		if not _current_target.is_empty() and _linger_remaining <= 0.0:
			_current_target["completed"] = true
			_linger_remaining = 0.9
			_rebuild()
		elif _current_target.is_empty():
			_set_visible(false)
		return
	_current_target = next_target
	_linger_remaining = 0.0
	_rebuild()


func _rebuild() -> void:
	if _current_target.is_empty() or _grid == null:
		_set_visible(false)
		return
	var cell: Vector3i = _current_target.get("cell", Vector3i.ZERO)
	if not _grid.is_in_bounds(cell):
		_set_visible(false)
		return
	var completed := bool(_current_target.get("completed", false))
	var material := _green_material if completed else _red_material
	var corners := _grid.get_corners(cell)
	if corners.size() < 3:
		_set_visible(false)
		return
	var center := _grid.cell_to_world(cell)
	center.y = _grid.sample_cell_surface_height(cell, center) + 0.065
	var cell_mesh := ImmediateMesh.new()
	cell_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(corners.size()):
		var first := corners[index]
		var second := corners[(index + 1) % corners.size()]
		first.y = _grid.sample_cell_surface_height(cell, first) + 0.065
		second.y = _grid.sample_cell_surface_height(cell, second) + 0.065
		cell_mesh.surface_add_vertex(center)
		cell_mesh.surface_add_vertex(first)
		cell_mesh.surface_add_vertex(second)
	cell_mesh.surface_end()
	_cell_instance.mesh = cell_mesh
	_cell_instance.material_override = material
	_cell_instance.visible = true
	var require_facing := bool(_current_target.get("require_facing", false))
	_arrow_instance.visible = require_facing
	if not require_facing:
		return
	var facing_index := int(_current_target.get("facing_index", 0))
	var angle := deg_to_rad(10.0 * float(facing_index))
	var direction := Vector3(cos(angle), 0.0, sin(angle)).normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	var shaft_start := center - direction * _grid.cell_size * 0.12
	var shaft_end := center + direction * _grid.cell_size * 0.36
	var tip := center + direction * _grid.cell_size * 0.72
	var shaft_half_width := _grid.cell_size * 0.065
	var head_half_width := _grid.cell_size * 0.18
	var arrow_mesh := ImmediateMesh.new()
	arrow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	arrow_mesh.surface_add_vertex(shaft_start - side * shaft_half_width)
	arrow_mesh.surface_add_vertex(shaft_start + side * shaft_half_width)
	arrow_mesh.surface_add_vertex(shaft_end + side * shaft_half_width)
	arrow_mesh.surface_add_vertex(shaft_start - side * shaft_half_width)
	arrow_mesh.surface_add_vertex(shaft_end + side * shaft_half_width)
	arrow_mesh.surface_add_vertex(shaft_end - side * shaft_half_width)
	arrow_mesh.surface_add_vertex(tip)
	arrow_mesh.surface_add_vertex(shaft_end + side * head_half_width)
	arrow_mesh.surface_add_vertex(shaft_end - side * head_half_width)
	arrow_mesh.surface_end()
	_arrow_instance.mesh = arrow_mesh
	_arrow_instance.material_override = material


func _set_visible(value: bool) -> void:
	if _cell_instance != null:
		_cell_instance.visible = value
	if _arrow_instance != null:
		_arrow_instance.visible = value and bool(_current_target.get("require_facing", false))


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = color
	return material
