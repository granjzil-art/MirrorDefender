@tool
## Adds warm self-illumination to authored moon and star meshes.
## The imported assets already include their suspension cords, so the scene only
## owns placement and presentation; it never participates in gameplay collision.
class_name LevelCelestialDecoration
extends Node3D

@export_color_no_alpha var emission_color: Color = Color("ffd27a")
@export_range(0.0, 16.0, 0.05, "or_greater") var emission_energy: float = 2.0
@export_group("Ceiling Suspension")
@export var snap_cords_to_ceiling: bool = true
@export_range(0.0, 64.0, 0.1, "or_greater") var ceiling_underside_y: float = 22.5


func _ready() -> void:
	if snap_cords_to_ceiling:
		_align_ornaments_to_ceiling()
	for child in get_children():
		if child.is_in_group(&"celestial_ornament"):
			_apply_emission_recursive(child)


func get_ornament_count() -> int:
	return get_tree().get_nodes_in_group(&"celestial_ornament").filter(
		func(node: Node) -> bool: return is_ancestor_of(node)
	).size()


func get_emissive_mesh_count() -> int:
	return _count_emissive_meshes(self)


func get_ornament_bounds(ornament: Node3D) -> AABB:
	if ornament == null or not is_ancestor_of(ornament):
		return AABB()
	var state := {"has_bounds": false, "bounds": AABB()}
	_collect_visual_bounds(ornament, state)
	return state.bounds if bool(state.has_bounds) else AABB()


func _align_ornaments_to_ceiling() -> void:
	for child in get_children():
		if not child is Node3D or not child.is_in_group(&"celestial_ornament"):
			continue
		var ornament := child as Node3D
		var bounds := get_ornament_bounds(ornament)
		if bounds.size == Vector3.ZERO:
			continue
		ornament.position.y += ceiling_underside_y - bounds.end.y


func _collect_visual_bounds(node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var relative_transform := global_transform.affine_inverse() * mesh_instance.global_transform
			var visual_bounds := relative_transform * mesh_instance.get_aabb()
			if bool(state.has_bounds):
				state.bounds = (state.bounds as AABB).merge(visual_bounds)
			else:
				state.bounds = visual_bounds
				state.has_bounds = true
	for child in node.get_children():
		_collect_visual_bounds(child, state)


func _apply_emission_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_apply_mesh_emission(node as MeshInstance3D)
	for child in node.get_children():
		_apply_emission_recursive(child)


func _apply_mesh_emission(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for surface_index in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate(true) as StandardMaterial3D
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_texture = material.albedo_texture
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = emission_energy
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.set_surface_override_material(surface_index, material)


func _count_emissive_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0:
			var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if material != null and material.emission_enabled:
				count += 1
				break
	for child in node.get_children():
		count += _count_emissive_meshes(child)
	return count
