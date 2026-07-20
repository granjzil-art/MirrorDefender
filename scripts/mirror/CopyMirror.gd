## Runtime edge entity. It owns presentation and side state, not projections.
class_name CopyMirror
extends Node3D

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
var _material: StandardMaterial3D

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

func flip_side() -> void:
	active_from_side = not active_from_side
	_update_side_material()
	side_changed.emit(self)

func get_active_cell() -> Vector3i:
	return from_cell if active_from_side else to_cell

func get_axis_endpoints() -> Array[Vector3]:
	return _grid.get_edge_endpoints(from_cell, edge_index) if _grid != null else []

func get_action_anchor() -> Vector3:
	var height := _grid.cell_size * definition.mirror_height_ratio if _grid != null and definition != null else 0.8
	return global_position + Vector3(0.0, height + 0.2, 0.0)

func set_selected(selected: bool) -> void:
	if _material == null or definition == null:
		return
	_material.emission_energy_multiplier = 4.0 if selected else 2.0

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
	if _grid == null or definition == null:
		return
	var endpoints := get_axis_endpoints()
	if endpoints.size() != 2:
		return
	var edge_direction: Vector3 = endpoints[1] - endpoints[0]
	var edge_length := maxf(0.01, edge_direction.length())
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		edge_length,
		_grid.cell_size * definition.mirror_height_ratio,
		_grid.cell_size * definition.mirror_thickness_ratio
	)
	body.mesh = mesh
	body.position.y = mesh.size.y * 0.5
	body.rotation.y = -atan2(edge_direction.z, edge_direction.x)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = definition.mirror_color
	_material.emission_enabled = true
	_material.emission = definition.mirror_color
	_material.emission_energy_multiplier = 2.0
	if preview_mode or definition.mirror_color.a < 1.0:
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material_override = _material
	add_child(body)
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(_grid.cell_size * 0.18, _grid.cell_size * 0.10, _grid.cell_size * 0.18)
	marker.mesh = marker_mesh
	marker.position.y = mesh.size.y + _grid.cell_size * 0.08
	marker.material_override = _material
	add_child(marker)
	_update_side_material()

func _update_side_material() -> void:
	if _material == null or definition == null:
		return
	var color := definition.mirror_color
	if not active_from_side:
		color = color.lerp(Color(0.66, 0.3, 1.0, color.a), 0.38)
	_material.albedo_color = color
	_material.emission = color
