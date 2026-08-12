@tool
## Selects one cloud from the four-model glTF pack and recenters it so each
## instance can be authored like a regular single-model scene.
class_name LowPolyCloudVariant
extends Node3D

@export_range(0, 3, 1) var variant_index: int = 0:
	set(value):
		variant_index = clampi(value, 0, 3)
		if is_inside_tree():
			_configure_variant.call_deferred()


func _ready() -> void:
	_configure_variant()


func get_visible_mesh_count() -> int:
	return _count_visible_meshes(self)


func _configure_variant() -> void:
	var scene_root := get_node_or_null("ImportedClouds/Sketchfab_model/root/GLTF_SceneRootNode") as Node3D
	if scene_root == null:
		return
	var clouds: Array[Node3D] = []
	for child in scene_root.get_children():
		if child is Node3D and child.name.begins_with("Cloud_"):
			clouds.append(child as Node3D)
	for index in clouds.size():
		clouds[index].visible = index == variant_index
	if clouds.is_empty():
		return
	var selected := clouds[mini(variant_index, clouds.size() - 1)]
	selected.position = Vector3.ZERO
	var state := {"has_bounds": false, "bounds": AABB()}
	_collect_visual_bounds(selected, state)
	if bool(state.has_bounds):
		selected.position -= (state.bounds as AABB).get_center()


func _collect_visual_bounds(node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var relative := global_transform.affine_inverse() * mesh_instance.global_transform
			var bounds := relative * mesh_instance.get_aabb()
			if bool(state.has_bounds):
				state.bounds = (state.bounds as AABB).merge(bounds)
			else:
				state.bounds = bounds
				state.has_bounds = true
	for child in node.get_children():
		_collect_visual_bounds(child, state)


func _count_visible_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
		count += 1
	for child in node.get_children():
		count += _count_visible_meshes(child)
	return count
