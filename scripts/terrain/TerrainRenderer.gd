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

@export_group("Batching")
## Groups identical static flat-terrain meshes into MultiMesh draw batches.
## Unsupported model trees automatically fall back to the original node path.
@export var batch_flat_models: bool = true

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
	var flat_batches: Dictionary = {}
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
			if batch_flat_models:
				_queue_flat_models(cell, grid_cell.layer_count, flat_asset, flat_batches)
			else:
				_add_flat_models(cell, grid_cell.layer_count, flat_asset)
			continue
		has_geometry = _add_surface_cell(mesh, cell) or has_geometry
	if batch_flat_models:
		_flush_flat_model_batches(flat_batches)
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
	var target_bounds := _get_flat_voxel_bounds(cell)
	for layer_index in range(layer_count):
		var instance_name := StringName("Terrain_%d_%d_%d_L%d" % [cell.x, cell.y, cell.z, layer_index + 1])
		var layer_y := float(layer_index) * _terrain_manager.get_layer_height() + TOP_LIFT
		_instantiate_flat_model(asset, target_bounds, instance_name, center + Vector3.UP * layer_y)


func _queue_flat_models(
	cell: Vector3i,
	layer_count: int,
	asset: ModelAssetDefinition,
	batches: Dictionary
) -> void:
	var center := _grid.cell_to_world(cell)
	var target_bounds := _get_flat_voxel_bounds(cell)
	var key := "%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f" % [
		asset.get_instance_id(),
		target_bounds.position.x,
		target_bounds.position.y,
		target_bounds.position.z,
		target_bounds.size.x,
		target_bounds.size.y,
		target_bounds.size.z,
	]
	if not batches.has(key):
		batches[key] = {
			"asset": asset,
			"target_bounds": target_bounds,
			"entries": [],
		}
	var entries: Array = batches[key]["entries"]
	for layer_index in range(layer_count):
		var layer_y := float(layer_index) * _terrain_manager.get_layer_height() + TOP_LIFT
		entries.append({
			"name": StringName("Terrain_%d_%d_%d_L%d" % [cell.x, cell.y, cell.z, layer_index + 1]),
			"transform": Transform3D(Basis.IDENTITY, center + Vector3.UP * layer_y),
		})


func _flush_flat_model_batches(batches: Dictionary) -> void:
	for batch_value in batches.values():
		var batch: Dictionary = batch_value
		var asset: ModelAssetDefinition = batch.get("asset")
		var target_bounds: AABB = batch.get("target_bounds", AABB())
		var entries: Array = batch.get("entries", [])
		if asset == null or entries.is_empty():
			continue
		var prototype := asset.instantiate_fitted_model(
			&"TerrainBatchPrototype",
			target_bounds,
			true,
			ModelAssetDefinition.FIT_VERTICAL_MAXIMUM
		)
		if prototype == null:
			continue
		var parts: Array[Dictionary] = []
		var state := {"supported": true}
		_collect_batch_mesh_parts(prototype, Transform3D.IDENTITY, true, parts, state)
		prototype.free()
		if not bool(state.get("supported", false)) or parts.is_empty():
			_instantiate_flat_batch_fallback(asset, target_bounds, entries)
			continue
		for part_index in range(parts.size()):
			_create_flat_multimesh_batch(asset, parts[part_index], entries, part_index)


func _collect_batch_mesh_parts(
	node: Node,
	parent_transform: Transform3D,
	parent_visible: bool,
	parts: Array[Dictionary],
	state: Dictionary
) -> void:
	if not bool(state.get("supported", false)):
		return
	var current_transform := parent_transform
	var branch_visible := parent_visible
	if node is Node3D:
		var node_3d := node as Node3D
		current_transform = parent_transform * node_3d.transform
		branch_visible = parent_visible and node_3d.visible
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and branch_visible:
			if mesh_instance.skin != null or _has_surface_material_overrides(mesh_instance):
				state["supported"] = false
				return
			parts.append({
				"mesh": mesh_instance.mesh,
				"local_transform": current_transform,
				"material_override": mesh_instance.material_override,
				"material_overlay": mesh_instance.material_overlay,
				"cast_shadow": mesh_instance.cast_shadow,
				"gi_mode": mesh_instance.gi_mode,
				"layers": mesh_instance.layers,
			})
	elif node is VisualInstance3D:
		# MultiMesh, particles, decals and other visual nodes need their original
		# scene hierarchy. Keep the correctness-first fallback for those assets.
		state["supported"] = false
		return
	for child in node.get_children():
		_collect_batch_mesh_parts(child, current_transform, branch_visible, parts, state)


func _has_surface_material_overrides(mesh_instance: MeshInstance3D) -> bool:
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		if mesh_instance.get_surface_override_material(surface_index) != null:
			return true
	return false


func _create_flat_multimesh_batch(
	asset: ModelAssetDefinition,
	part: Dictionary,
	entries: Array,
	part_index: int
) -> void:
	var source_mesh: Mesh = part.get("mesh")
	if source_mesh == null:
		return
	var local_transform: Transform3D = part.get("local_transform", Transform3D.IDENTITY)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source_mesh
	multimesh.instance_count = entries.size()
	for entry_index in range(entries.size()):
		var placement: Transform3D = entries[entry_index].get("transform", Transform3D.IDENTITY)
		multimesh.set_instance_transform(entry_index, placement * local_transform)
	var batch_instance := MultiMeshInstance3D.new()
	var asset_label := (
		asset.scene.resource_path.get_file().get_basename()
		if asset.scene != null and not asset.scene.resource_path.is_empty()
		else "asset_%d" % asset.get_instance_id()
	)
	batch_instance.name = "TerrainBatch_%s_P%d" % [asset_label, part_index]
	batch_instance.multimesh = multimesh
	var material_override: Material = part.get("material_override")
	if material_override != null:
		batch_instance.material_override = material_override
	var material_overlay: Material = part.get("material_overlay")
	if material_overlay != null:
		batch_instance.material_overlay = material_overlay
	batch_instance.cast_shadow = int(part.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
	batch_instance.gi_mode = int(part.get("gi_mode", GeometryInstance3D.GI_MODE_STATIC))
	batch_instance.layers = int(part.get("layers", 1))
	batch_instance.set_meta("terrain_batch_instance_count", entries.size())
	batch_instance.set_meta("terrain_asset_path", asset.scene.resource_path if asset.scene != null else "")
	_custom_models_root.add_child(batch_instance)


func _instantiate_flat_batch_fallback(
	asset: ModelAssetDefinition,
	target_bounds: AABB,
	entries: Array
) -> void:
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var placement: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		_instantiate_flat_model(
			asset,
			target_bounds,
			entry.get("name", &"TerrainFallback"),
			placement.origin
		)


func _instantiate_flat_model(
	asset: ModelAssetDefinition,
	target_bounds: AABB,
	instance_name: StringName,
	world_position: Vector3
) -> void:
	var visual := asset.instantiate_fitted_model(
		instance_name,
		target_bounds,
		true,
		ModelAssetDefinition.FIT_VERTICAL_MAXIMUM
	)
	if visual == null:
		return
	visual.position = world_position
	_custom_models_root.add_child(visual)


func _add_custom_ramp(ramp: RampPlacementData, asset: ModelAssetDefinition) -> void:
	var footprint := ramp.get_footprint_cells(_grid.get_shape())
	if footprint.is_empty():
		return
	var axis := _terrain_manager.get_ramp_axis(ramp)
	var target_bounds := _get_ramp_bounds(ramp, axis)
	var visual := asset.instantiate_fitted_model(
		StringName("Ramp_%s" % String(ramp.ramp_id)),
		target_bounds,
		true,
		ModelAssetDefinition.FIT_VERTICAL_MINIMUM
	)
	if visual == null:
		return
	var start := _grid.cell_to_world(footprint[0])
	var end := _grid.cell_to_world(footprint[footprint.size() - 1])
	visual.position = (start + end) * 0.5
	visual.position.y = float(ramp.base_layer - 1) * _terrain_manager.get_layer_height() + TOP_LIFT
	visual.rotation.y = atan2(axis.x, axis.z)
	_custom_models_root.add_child(visual)


func _get_flat_voxel_bounds(cell: Vector3i) -> AABB:
	var center := _grid.cell_to_world(cell)
	var minimum := Vector3(INF, -_terrain_manager.get_layer_height(), INF)
	var maximum := Vector3(-INF, 0.0, -INF)
	for corner in _grid.get_corners(cell):
		minimum.x = minf(minimum.x, corner.x - center.x)
		minimum.z = minf(minimum.z, corner.z - center.z)
		maximum.x = maxf(maximum.x, corner.x - center.x)
		maximum.z = maxf(maximum.z, corner.z - center.z)
	return AABB(minimum, maximum - minimum)


func _get_ramp_bounds(ramp: RampPlacementData, axis: Vector3) -> AABB:
	var center := _grid.cell_to_world(ramp.anchor_cell)
	var perpendicular := Vector3(-axis.z, 0.0, axis.x).normalized()
	var minimum_cross := INF
	var maximum_cross := -INF
	for corner in _grid.get_corners(ramp.anchor_cell):
		var local := corner - center
		var cross_distance := local.dot(perpendicular)
		minimum_cross = minf(minimum_cross, cross_distance)
		maximum_cross = maxf(maximum_cross, cross_distance)
	var width := maximum_cross - minimum_cross
	var run_distance := _terrain_manager.get_ramp_cell_spacing(ramp) * float(ramp.run_length)
	var height := _terrain_manager.get_layer_height()
	return AABB(
		Vector3(-width * 0.5, 0.0, -run_distance * 0.5),
		Vector3(width, height, run_distance)
	)


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
