## Runtime edge entity. It owns presentation, active-side state, and one
## throttled planar reflection view; MirrorManager owns projection logic.
class_name CopyMirror
extends Node3D

const MirrorReflectionViewScript := preload("res://scripts/mirror/MirrorReflectionView.gd")

signal side_changed(mirror: CopyMirror)

var definition: CopyMirrorDefinition
var from_cell: Vector3i
var to_cell: Vector3i
var edge_index: int = -1
var edge_id: String = ""
var active_from_side: bool = true
var placement_order: int = 0
var preview_mode: bool = false

var _grid: GridManager
var _tile_manager: TileManager
var _source_camera: Camera3D
var _frame_material: StandardMaterial3D
var _side_marker: MeshInstance3D
var _reflection_view: Node3D
var _selected: bool = false

func configure(
	mirror_definition: CopyMirrorDefinition,
	p_from_cell: Vector3i,
	p_to_cell: Vector3i,
	p_edge_index: int,
	p_edge_id: String,
	grid_manager: GridManager,
	tile_manager: TileManager,
	p_active_from_side: bool,
	p_preview_mode: bool = false
) -> void:
	definition = mirror_definition
	from_cell = p_from_cell
	to_cell = p_to_cell
	edge_index = p_edge_index
	edge_id = p_edge_id
	_grid = grid_manager
	_tile_manager = tile_manager
	active_from_side = p_active_from_side
	preview_mode = p_preview_mode
	_update_transform()
	_build_visual()

func set_reflection_camera(camera: Camera3D) -> void:
	_source_camera = camera
	if _reflection_view != null:
		_reflection_view.set_source_camera(camera)

func request_reflection_refresh() -> bool:
	return _reflection_view != null and _reflection_view.request_refresh()

func refresh_visual() -> void:
	_build_visual()

func flip_side() -> void:
	active_from_side = not active_from_side
	_update_active_side_visual()
	side_changed.emit(self)

func get_active_cell() -> Vector3i:
	return from_cell if active_from_side else to_cell

func get_axis_endpoints() -> Array[Vector3]:
	return _grid.get_edge_endpoints(from_cell, edge_index) if _grid != null else []

func get_edge_direction() -> Vector3:
	var endpoints := get_axis_endpoints()
	return endpoints[1] - endpoints[0] if endpoints.size() == 2 else Vector3.ZERO

func get_active_normal() -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	var normal := _grid.cell_to_world(get_active_cell()) - global_position
	normal.y = 0.0
	return normal.normalized()

func get_mirror_width() -> float:
	return maxf(0.01, get_edge_direction().length())

func get_mirror_height() -> float:
	return _grid.cell_size * definition.mirror_height_ratio if _grid != null and definition != null else 1.20

func get_mirror_thickness() -> float:
	return _grid.cell_size * definition.mirror_thickness_ratio if _grid != null and definition != null else 0.08

func get_reflection_surface() -> MeshInstance3D:
	return _reflection_view.get_surface() if _reflection_view != null else null

func get_reflection_camera() -> Camera3D:
	return _reflection_view.get_reflection_camera() if _reflection_view != null else null

func get_action_anchor() -> Vector3:
	return global_position + Vector3(0.0, get_mirror_height() + 0.2, 0.0)

func set_selected(selected: bool) -> void:
	_selected = selected
	if _frame_material != null:
		_frame_material.emission_energy_multiplier = 3.6 if selected else 1.5

func _update_transform() -> void:
	if _grid == null or _tile_manager == null:
		return
	var endpoints := _grid.get_edge_endpoints(from_cell, edge_index)
	var midpoint := _grid.cell_to_world(from_cell)
	if endpoints.size() == 2:
		midpoint = (endpoints[0] + endpoints[1]) * 0.5
	var height := maxf(_tile_manager.get_world_height(from_cell), _tile_manager.get_world_height(to_cell))
	position = midpoint + Vector3(0.0, height, 0.0)

func _build_visual() -> void:
	for child in get_children():
		child.queue_free()
	_reflection_view = null
	_side_marker = null
	if _grid == null or definition == null or get_axis_endpoints().size() != 2:
		return
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(get_mirror_width(), get_mirror_height(), get_mirror_thickness())
	body.mesh = body_mesh
	body.position.y = get_mirror_height() * 0.5
	body.rotation.y = -atan2(get_edge_direction().z, get_edge_direction().x)
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = definition.mirror_back_face_color
	_frame_material.metallic = 0.82
	_frame_material.roughness = 0.22
	_frame_material.emission_enabled = true
	_frame_material.emission = definition.mirror_color.darkened(0.48)
	_frame_material.emission_energy_multiplier = 1.5
	if preview_mode:
		var preview_color := _frame_material.albedo_color
		preview_color.a = 0.72
		_frame_material.albedo_color = preview_color
		_frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material_override = _frame_material
	add_child(body)
	_side_marker = MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(_grid.cell_size * 0.22, _grid.cell_size * 0.08, _grid.cell_size * 0.10)
	_side_marker.mesh = marker_mesh
	_side_marker.material_override = _make_marker_material()
	add_child(_side_marker)
	_reflection_view = MirrorReflectionViewScript.new()
	add_child(_reflection_view)
	_reflection_view.configure(self, definition, _source_camera, preview_mode)
	_update_active_side_visual()
	set_selected(_selected)

func _update_active_side_visual() -> void:
	var normal := get_active_normal()
	if _side_marker != null:
		_side_marker.position = Vector3.UP * (get_mirror_height() + _grid.cell_size * 0.07) + normal * _grid.cell_size * 0.13
		_side_marker.look_at(_side_marker.global_position + normal, Vector3.UP, true)
	if _reflection_view != null:
		_reflection_view.update_active_side()

func _make_marker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = definition.mirror_color
	material.emission_enabled = true
	material.emission = definition.mirror_color
	material.emission_energy_multiplier = 3.0
	return material
