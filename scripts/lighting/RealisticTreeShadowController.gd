## RealisticTreeShadowController -- fits one authored tree to the current level and lets lights cast its shadow.
class_name RealisticTreeShadowController
extends Node3D

signal enabled_changed(enabled: bool)

const BOUNDS_EPSILON := 0.00001
const LEAF_SHADOW_CASTER_META := &"realistic_tree_leaf_shadow_caster"
const LeafShadowCutoutShader := preload("res://resources/lighting/RealisticLeafShadowCutout.gdshader")

var _grid: GridManager
var _terrain_manager: TerrainManager
var _definition: Resource
var _model_root: Node3D
var _effect_enabled: bool = true
var _last_level_bounds := AABB()
var _last_cell_size: float = 1.0


func configure(
	grid: GridManager,
	terrain_manager: TerrainManager,
	definition: Resource
) -> bool:
	_grid = grid
	_terrain_manager = terrain_manager
	_definition = definition
	_clear_model()
	if _definition == null or not _definition.validate_configuration().is_empty():
		_effect_enabled = false
		return false
	_model_root = _definition.model_asset.instantiate_grounded_model(&"RealisticTreeModel")
	if _model_root == null:
		_effect_enabled = false
		return false
	add_child(_model_root)
	_prepare_render_nodes(_model_root)
	_effect_enabled = _definition.feature_enabled
	_apply_visibility()
	return true


func rebuild(level_bounds: AABB, cell_size: float) -> bool:
	if _definition == null or _model_root == null or not _is_valid_bounds(level_bounds) or cell_size <= 0.0:
		return false
	var source_result: Dictionary = _definition.model_asset.get_authored_visual_bounds()
	var source_bounds: AABB = source_result.get("bounds", AABB())
	if not bool(source_result.get("valid", false)) or source_bounds.size.y <= BOUNDS_EPSILON:
		return false
	_last_level_bounds = level_bounds
	_last_cell_size = cell_size
	var authored_scale: Vector3 = _definition.model_asset.runtime_scale
	var scaled_source_height: float = source_bounds.size.y * authored_scale.y
	if scaled_source_height <= BOUNDS_EPSILON:
		return false
	var uniform_fit: float = _definition.target_height_cells * cell_size / scaled_source_height
	_model_root.scale = authored_scale * uniform_fit
	_model_root.rotation = Vector3(0.0, deg_to_rad(_definition.yaw_degrees), 0.0)
	var x := lerpf(level_bounds.position.x, level_bounds.end.x, _definition.position_normalized.x)
	var z := lerpf(level_bounds.position.z, level_bounds.end.z, _definition.position_normalized.y)
	var ground_position := Vector3(x, level_bounds.position.y, z)
	if _grid != null and _terrain_manager != null:
		var cell := _grid.world_to_cell(ground_position)
		if _grid.is_in_bounds(cell):
			ground_position.y = _terrain_manager.sample_surface_height(cell, ground_position)
	ground_position.y += _definition.ground_offset_cells * cell_size
	_model_root.position = ground_position
	_apply_visibility()
	return true


func set_effect_enabled(enabled: bool) -> void:
	_effect_enabled = enabled and _definition != null and _definition.feature_enabled
	_apply_visibility()
	enabled_changed.emit(is_effect_enabled())


func is_effect_enabled() -> bool:
	return _effect_enabled and _model_root != null and _model_root.visible


func get_model_root() -> Node3D:
	return _model_root


func get_definition() -> Resource:
	return _definition


func get_mesh_count() -> int:
	return _count_meshes(_model_root)


func get_collision_node_count() -> int:
	return _count_collisions(_model_root)


func get_leaf_shadow_caster_count() -> int:
	return _count_leaf_shadow_casters(_model_root)


func get_model_world_bounds() -> AABB:
	if _model_root == null:
		return AABB()
	var state := {"valid": false, "bounds": AABB()}
	_collect_world_bounds(_model_root, state)
	return state.get("bounds", AABB())


func _prepare_render_nodes(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if _definition.cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_prepare_render_nodes(child)
	if node == _model_root and _definition.cast_shadow and _definition.leaf_alpha_cutout_enabled:
		var leaf_meshes: Array[MeshInstance3D] = []
		_collect_leaf_meshes(node, leaf_meshes)
		for leaf_mesh in leaf_meshes:
			_install_leaf_shadow_caster(leaf_mesh)


func _collect_leaf_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and not node.has_meta(LEAF_SHADOW_CASTER_META):
		var mesh_instance := node as MeshInstance3D
		if _is_leaf_mesh(mesh_instance):
			result.append(mesh_instance)
	for child in node.get_children():
		_collect_leaf_meshes(child, result)


func _is_leaf_mesh(mesh_instance: MeshInstance3D) -> bool:
	if "leaves" in mesh_instance.name.to_lower() or "leaf" in mesh_instance.name.to_lower():
		return true
	if mesh_instance.mesh == null:
		return false
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var material := mesh_instance.get_active_material(surface_index)
		if material != null:
			var material_name := material.resource_name.to_lower()
			if "leaves" in material_name or "leaf" in material_name:
				return true
	return false


func _install_leaf_shadow_caster(source: MeshInstance3D) -> bool:
	if source.mesh == null or source.mesh.get_surface_count() <= 0 or source.get_parent() == null:
		return false
	var source_material := source.get_active_material(0)
	if not source_material is BaseMaterial3D:
		return false
	var cutout_material := ShaderMaterial.new()
	cutout_material.shader = LeafShadowCutoutShader
	cutout_material.set_shader_parameter("albedo_texture", (source_material as BaseMaterial3D).albedo_texture)
	cutout_material.set_shader_parameter("shadow_strength", _definition.leaf_shadow_strength)
	cutout_material.set_shader_parameter("alpha_scissor_threshold", _definition.leaf_alpha_scissor_threshold)
	cutout_material.set_shader_parameter("breakup_scale", _definition.leaf_shadow_breakup_scale)
	cutout_material.set_shader_parameter("gap_threshold", _definition.leaf_shadow_gap_threshold)
	cutout_material.set_shader_parameter("pattern_seed", _definition.leaf_shadow_pattern_seed)
	var caster := MeshInstance3D.new()
	caster.name = "%s_LeafShadowCaster" % source.name
	caster.set_meta(LEAF_SHADOW_CASTER_META, true)
	caster.mesh = source.mesh
	caster.skin = source.skin
	caster.skeleton = source.skeleton
	caster.transform = source.transform
	caster.material_override = cutout_material
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.extra_cull_margin = source.extra_cull_margin
	source.get_parent().add_child(caster)
	source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true


func _apply_visibility() -> void:
	if _model_root != null:
		_model_root.visible = _effect_enabled and _definition != null and _definition.model_visible


func _count_meshes(node: Node) -> int:
	if node == null:
		return 0
	var count := 1 if node is MeshInstance3D or node is MultiMeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _count_collisions(node: Node) -> int:
	if node == null:
		return 0
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collisions(child)
	return count


func _count_leaf_shadow_casters(node: Node) -> int:
	if node == null:
		return 0
	var count := 1 if node.has_meta(LEAF_SHADOW_CASTER_META) else 0
	for child in node.get_children():
		count += _count_leaf_shadow_casters(child)
	return count


func _collect_world_bounds(node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var bounds := (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		if bool(state.get("valid", false)):
			state["bounds"] = (state.get("bounds", AABB()) as AABB).merge(bounds)
		else:
			state["valid"] = true
			state["bounds"] = bounds
	for child in node.get_children():
		_collect_world_bounds(child, state)


func _is_valid_bounds(bounds: AABB) -> bool:
	return bounds.size.x > BOUNDS_EPSILON and bounds.size.y > BOUNDS_EPSILON and bounds.size.z > BOUNDS_EPSILON


func _clear_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.free()
	_model_root = null
