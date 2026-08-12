@tool
## Presents Level1's sun and clouds outside and above the acrylic display case.
## Every model is visual-only and receives its own duplicated emissive material.
class_name Level1SkyDecoration
extends Node3D

@export_group("Sun Emission")
@export_color_no_alpha var sun_emission_color: Color = Color("ffb52e")
@export_range(0.0, 16.0, 0.05, "or_greater") var sun_emission_energy: float = 5.5
@export_group("Cloud Emission")
@export_color_no_alpha var cloud_emission_color: Color = Color("b9d9ff")
@export_range(0.0, 16.0, 0.05, "or_greater") var cloud_emission_energy: float = 0.9


func _ready() -> void:
	for child in get_children():
		if child.is_in_group(&"sky_sun"):
			_apply_emission_recursive(child, sun_emission_color, sun_emission_energy)
		elif child.is_in_group(&"sky_cloud"):
			_apply_emission_recursive(child, cloud_emission_color, cloud_emission_energy)


func get_sun_count() -> int:
	return _count_group_children(&"sky_sun")


func get_cloud_count() -> int:
	return _count_group_children(&"sky_cloud")


func get_emissive_mesh_count(group_name: StringName = &"") -> int:
	var count := 0
	for child in get_children():
		if group_name.is_empty() or child.is_in_group(group_name):
			count += _count_emissive_meshes(child)
	return count


func get_visual_bounds(model: Node3D) -> AABB:
	if model == null or not is_ancestor_of(model):
		return AABB()
	var state := {"has_bounds": false, "bounds": AABB()}
	_collect_visual_bounds(model, state)
	return state.bounds if bool(state.has_bounds) else AABB()


func _count_group_children(group_name: StringName) -> int:
	var count := 0
	for child in get_children():
		if child.is_in_group(group_name):
			count += 1
	return count


func _apply_emission_recursive(node: Node, color: Color, energy: float) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.is_visible_in_tree():
			_apply_mesh_emission(mesh_instance, color, energy)
	for child in node.get_children():
		_apply_emission_recursive(child, color, energy)


func _apply_mesh_emission(mesh_instance: MeshInstance3D, color: Color, energy: float) -> void:
	if mesh_instance.mesh == null:
		return
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for surface_index in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate(true) as StandardMaterial3D
		material.emission_enabled = true
		material.emission = color
		material.emission_texture = material.albedo_texture
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = energy
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.set_surface_override_material(surface_index, material)


func _collect_visual_bounds(node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree():
			var relative := global_transform.affine_inverse() * mesh_instance.global_transform
			var bounds := relative * mesh_instance.get_aabb()
			if bool(state.has_bounds):
				state.bounds = (state.bounds as AABB).merge(bounds)
			else:
				state.bounds = bounds
				state.has_bounds = true
	for child in node.get_children():
		_collect_visual_bounds(child, state)


func _count_emissive_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree():
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
				if material != null and material.emission_enabled:
					count += 1
					break
	for child in node.get_children():
		count += _count_emissive_meshes(child)
	return count
