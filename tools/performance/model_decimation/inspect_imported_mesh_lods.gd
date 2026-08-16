extends SceneTree

const DEFAULT_MODEL_PATHS: PackedStringArray = [
	"res://assets/buildings/Castle/fbx/desertcastle.fbx",
	"res://assets/buildings/ArrowTower/fbx/arrowtower3_1.fbx",
	"res://assets/buildings/mace/mace8.glb",
	"res://assets/buildings/crossbow/crossbow.glb",
	"res://assets/blocks/fbx/greenstone.fbx",
]


func _initialize() -> void:
	var model_paths := OS.get_cmdline_user_args()
	if model_paths.is_empty():
		model_paths = Array(DEFAULT_MODEL_PATHS)
	var results: Array[Dictionary] = []
	for raw_path in model_paths:
		results.append(_inspect_model(String(raw_path)))
	print(JSON.stringify({"models": results}, "  "))
	quit()


func _inspect_model(model_path: String) -> Dictionary:
	var packed := load(model_path) as PackedScene
	if packed == null:
		return {"path": model_path, "error": "PackedScene load failed"}
	var root := packed.instantiate()
	var mesh_rows: Array[Dictionary] = []
	_collect_mesh_rows(root, root, mesh_rows)
	root.free()
	var original_triangles := 0
	for row in mesh_rows:
		original_triangles += int(row.get("original_triangles", 0))
	return {
		"path": model_path,
		"mesh_instance_count": mesh_rows.size(),
		"original_triangles": original_triangles,
		"meshes": mesh_rows,
	}


func _collect_mesh_rows(node: Node, root: Node, rows: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			rows.append(_inspect_mesh(mesh_instance, root))
	for child in node.get_children():
		_collect_mesh_rows(child, root, rows)


func _inspect_mesh(mesh_instance: MeshInstance3D, root: Node) -> Dictionary:
	var mesh := mesh_instance.mesh
	var surface_rows: Array[Dictionary] = []
	var original_total := 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertex_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var original_triangles := (
			original_indices.size() / 3
			if not original_indices.is_empty()
			else vertex_count / 3
		)
		original_total += original_triangles
		var lod_rows: Array[Dictionary] = []
		var lods: Dictionary = _get_surface_lods(mesh, surface_index)
		var lod_keys: Array = lods.keys()
		lod_keys.sort()
		for lod_key in lod_keys:
			var lod_indices: PackedInt32Array = lods[lod_key]
			lod_rows.append({
				"threshold": float(lod_key),
				"triangles": lod_indices.size() / 3,
				"ratio": (
					float(lod_indices.size()) / float(original_indices.size())
					if not original_indices.is_empty()
					else 1.0
				),
			})
		surface_rows.append({
			"surface": surface_index,
			"primitive": mesh.surface_get_primitive_type(surface_index),
			"vertices": vertex_count,
			"original_triangles": original_triangles,
			"lods": lod_rows,
		})
	return {
		"node_path": str(root.get_path_to(mesh_instance)),
		"mesh_name": mesh.resource_name,
		"original_triangles": original_total,
		"surfaces": surface_rows,
	}


func _get_surface_lods(mesh: Mesh, surface_index: int) -> Dictionary:
	if mesh.has_method("surface_get_lods"):
		return mesh.call("surface_get_lods", surface_index) as Dictionary
	if mesh.has_method("_get_surfaces"):
		var serialized_surfaces: Array = mesh.call("_get_surfaces") as Array
		if surface_index >= 0 and surface_index < serialized_surfaces.size():
			var surface_data: Dictionary = serialized_surfaces[surface_index]
			var raw_lods: Variant = surface_data.get("lods", {})
			if raw_lods is Dictionary:
				return raw_lods as Dictionary
	return {}
