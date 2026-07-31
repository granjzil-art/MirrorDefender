## TerrainRenderer -- visualizes canonical terrain columns and 1:N ramps.
##
## Terrain models are optional. Missing flat/ramp slots fall back to vertex-
## colored greybox geometry without changing gameplay state.
class_name TerrainRenderer
extends Node3D

const TOP_LIFT: float = 0.01
const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Greybox Presentation")
@export_range(0.0, 0.8, 0.01) var cliff_darkening: float = 0.20
@export_range(0.0, 0.5, 0.01) var layer_band_darkening: float = 0.06

var _grid: GridManager
var _terrain_manager: TerrainManagerScript
var _greybox_instance: MeshInstance3D
var _greybox_material: StandardMaterial3D
var _custom_models_root: Node3D


func _ready() -> void:
	_setup_visual_roots()


func set_grid(value: GridManager) -> void:
	if _grid != null and _grid.grid_changed.is_connected(_rebuild):
		_grid.grid_changed.disconnect(_rebuild)
	_grid = value
	if is_node_ready() and _grid != null:
		if not _grid.grid_changed.is_connected(_rebuild):
			_grid.grid_changed.connect(_rebuild)
		_rebuild()


func set_terrain_manager(value: TerrainManagerScript) -> void:
	if _terrain_manager != null:
		if _terrain_manager.terrain_loaded.is_connected(_on_terrain_loaded):
			_terrain_manager.terrain_loaded.disconnect(_on_terrain_loaded)
		if _terrain_manager.terrain_cleared.is_connected(_rebuild):
			_terrain_manager.terrain_cleared.disconnect(_rebuild)
	_terrain_manager = value
	if is_node_ready() and _terrain_manager != null:
		if not _terrain_manager.terrain_loaded.is_connected(_on_terrain_loaded):
			_terrain_manager.terrain_loaded.connect(_on_terrain_loaded)
		if not _terrain_manager.terrain_cleared.is_connected(_rebuild):
			_terrain_manager.terrain_cleared.connect(_rebuild)
		_rebuild()


func _on_terrain_loaded(_level_resource: LevelResource) -> void:
	_rebuild()


func _setup_visual_roots() -> void:
	_greybox_material = StandardMaterial3D.new()
	_greybox_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_greybox_material.vertex_color_use_as_albedo = true
	_greybox_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_greybox_instance = MeshInstance3D.new()
	_greybox_instance.name = "TerrainGreybox"
	_greybox_instance.material_override = _greybox_material
	add_child(_greybox_instance)
	_custom_models_root = Node3D.new()
	_custom_models_root.name = "TerrainModels"
	add_child(_custom_models_root)


func _rebuild() -> void:
	if _greybox_instance == null or _custom_models_root == null:
		return
	_clear_custom_models()
	_greybox_instance.mesh = null
	if not feature_enabled or _grid == null or _terrain_manager == null:
		return
	if _terrain_manager.get_level_resource() == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_geometry := false
	var custom_ramps: Dictionary = {}
	for cell in _grid.enumerate_cells():
		var grid_cell := _terrain_manager.get_grid_cell(cell)
		if grid_cell == null:
			continue
		var ramp := _terrain_manager.get_ramp_for_cell(cell)
		if ramp != null:
			var ramp_terrain := _terrain_manager.get_terrain(cell)
			var ramp_asset: ModelAssetDefinition = null
			if ramp_terrain != null:
				ramp_asset = ramp_terrain.get_ramp_model_asset(ramp.run_length)
			if ramp_asset != null and ramp_asset.is_configured():
				if not custom_ramps.has(ramp.ramp_id):
					_add_custom_ramp(ramp, ramp_asset)
					custom_ramps[ramp.ramp_id] = true
				if ramp.base_layer > 1:
					has_geometry = _add_support_column(mesh, cell, ramp.base_layer - 1) or has_geometry
				continue
			has_geometry = _add_surface_cell(mesh, cell) or has_geometry
			continue
		var terrain := _terrain_manager.get_terrain(cell)
		var flat_asset: ModelAssetDefinition = terrain.flat_model_asset if terrain != null else null
		if flat_asset != null and flat_asset.is_configured():
			_add_flat_models(cell, grid_cell.layer_count, flat_asset)
			continue
		has_geometry = _add_surface_cell(mesh, cell) or has_geometry
	if has_geometry:
		mesh.surface_end()
		_greybox_instance.mesh = mesh


func _add_surface_cell(mesh: ImmediateMesh, cell: Vector3i) -> bool:
	var corners := _grid.get_corners(cell)
	if corners.size() < 3:
		return false
	var color := _terrain_manager.get_terrain_color(cell)
	var center := _grid.cell_to_world(cell)
	center.y = _terrain_manager.sample_surface_height(cell, center) + TOP_LIFT
	for index in range(corners.size()):
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % corners.size()]
		a.y = _terrain_manager.sample_surface_height(cell, a) + TOP_LIFT
		b.y = _terrain_manager.sample_surface_height(cell, b) + TOP_LIFT
		_add_triangle(mesh, color, center, a, b)
		_add_exposed_side(mesh, cell, index, a, b, color)
	return true


func _add_support_column(mesh: ImmediateMesh, cell: Vector3i, layer_count: int) -> bool:
	if layer_count <= 0:
		return false
	var corners := _grid.get_corners(cell)
	if corners.size() < 3:
		return false
	var top_y := float(layer_count - 1) * _terrain_manager.get_layer_height() + TOP_LIFT
	var color := _terrain_manager.get_terrain_color(cell)
	var center := _grid.cell_to_world(cell)
	center.y = top_y
	for index in range(corners.size()):
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % corners.size()]
		a.y = top_y
		b.y = top_y
		_add_triangle(mesh, color, center, a, b)
		_add_column_side_bands(mesh, a, b, -_terrain_manager.get_layer_height(), color)
	return true


func _add_exposed_side(mesh: ImmediateMesh, cell: Vector3i, edge_index: int, top_a: Vector3, top_b: Vector3, color: Color) -> void:
	var neighbor := _grid.neighbor_across_edge(cell, edge_index)
	var lower_a := Vector3(top_a.x, -_terrain_manager.get_layer_height() + TOP_LIFT, top_a.z)
	var lower_b := Vector3(top_b.x, -_terrain_manager.get_layer_height() + TOP_LIFT, top_b.z)
	if _grid.is_in_bounds(neighbor):
		lower_a.y = _terrain_manager.sample_surface_height(neighbor, lower_a) + TOP_LIFT
		lower_b.y = _terrain_manager.sample_surface_height(neighbor, lower_b) + TOP_LIFT
	if top_a.y <= lower_a.y + 0.001 and top_b.y <= lower_b.y + 0.001:
		return
	var side_color := color.darkened(cliff_darkening)
	_add_triangle(mesh, side_color, top_a, lower_a, lower_b)
	_add_triangle(mesh, side_color, top_a, lower_b, top_b)


func _add_column_side_bands(mesh: ImmediateMesh, top_a: Vector3, top_b: Vector3, bottom_y: float, color: Color) -> void:
	var layer_height := _terrain_manager.get_layer_height()
	var band_top := top_a.y
	var band_index := 0
	while band_top > bottom_y + 0.001:
		var band_bottom := maxf(bottom_y, band_top - layer_height)
		var a0 := Vector3(top_a.x, band_top, top_a.z)
		var b0 := Vector3(top_b.x, band_top, top_b.z)
		var a1 := Vector3(top_a.x, band_bottom, top_a.z)
		var b1 := Vector3(top_b.x, band_bottom, top_b.z)
		var darkness := clampf(cliff_darkening + float(band_index) * layer_band_darkening, 0.0, 0.9)
		var band_color := color.darkened(darkness)
		_add_triangle(mesh, band_color, a0, a1, b1)
		_add_triangle(mesh, band_color, a0, b1, b0)
		band_top = band_bottom
		band_index += 1


func _add_flat_models(cell: Vector3i, layer_count: int, asset: ModelAssetDefinition) -> void:
	var center := _grid.cell_to_world(cell)
	for layer_index in range(layer_count):
		var instance_name := StringName("Terrain_%d_%d_%d_L%d" % [cell.x, cell.y, cell.z, layer_index + 1])
		var visual := asset.instantiate_model(instance_name)
		if visual == null:
			continue
		var layer_y := float(layer_index) * _terrain_manager.get_layer_height() + TOP_LIFT
		visual.position = center + Vector3.UP * layer_y
		_custom_models_root.add_child(visual)


func _add_custom_ramp(ramp: RampPlacementData, asset: ModelAssetDefinition) -> void:
	var visual := asset.instantiate_model(StringName("Ramp_%s" % String(ramp.ramp_id)))
	if visual == null:
		return
	var footprint := ramp.get_footprint_cells(_grid.get_shape())
	if footprint.is_empty():
		visual.free()
		return
	var start := _grid.cell_to_world(footprint[0])
	var end := _grid.cell_to_world(footprint[footprint.size() - 1])
	var axis := _terrain_manager.get_ramp_axis(ramp)
	visual.position = (start + end) * 0.5
	visual.position.y = float(ramp.base_layer - 1) * _terrain_manager.get_layer_height() + TOP_LIFT
	visual.rotation.y = atan2(axis.x, axis.z)
	_custom_models_root.add_child(visual)


func _add_triangle(mesh: ImmediateMesh, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(c)


func _clear_custom_models() -> void:
	for child in _custom_models_root.get_children():
		child.free()
