extends SceneTree

const INVENTORY_PATH := "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/inventory.json"
const FALLBACK_ROOT := "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/aggressive_fallback"
const REQUESTS_PATH := FALLBACK_ROOT + "/requests.json"
const TARGET_RATIO := 0.20
const TRIANGLE_THRESHOLD := 5000
const EXCLUDED_SOURCES := ["res://assets/greattree/realistic_tree_gltf/scene.gltf"]


func _initialize() -> void:
	var inventory := _read_json(INVENTORY_PATH)
	if inventory.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FALLBACK_ROOT + "/inputs"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FALLBACK_ROOT + "/outputs"))
	var requests: Array[Dictionary] = []
	for record in inventory.models:
		var source_path := str(record.source)
		if int(record.triangles) <= TRIANGLE_THRESHOLD or source_path in EXCLUDED_SOURCES:
			continue
		var scene := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var root := scene.instantiate()
		var mesh_instances: Array[MeshInstance3D] = []
		_collect(root, mesh_instances)
		for mesh_instance in mesh_instances:
			var mesh := mesh_instance.mesh
			for surface_index in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var target_index_count := maxi(3, int(floor(indices.size() * TARGET_RATIO / 3.0)) * 3)
				var tool := SurfaceTool.new()
				tool.create_from(mesh, surface_index)
				var primary_indices := tool.generate_lod(1.0, target_index_count)
				if primary_indices.size() <= target_index_count:
					continue
				var node_path := str(root.get_path_to(mesh_instance))
				var key := (source_path + "|" + node_path + "|" + str(surface_index)).sha256_text()
				var flat_vertices: Array[float] = []
				flat_vertices.resize(vertices.size() * 3)
				for vertex_index in vertices.size():
					var vertex := vertices[vertex_index]
					flat_vertices[vertex_index * 3] = vertex.x
					flat_vertices[vertex_index * 3 + 1] = vertex.y
					flat_vertices[vertex_index * 3 + 2] = vertex.z
				var flat_indices: Array[int] = []
				flat_indices.assign(indices)
				var request := {
					"key": key,
					"source": source_path,
					"node_path": node_path,
					"surface": surface_index,
					"original_vertices": vertices.size(),
					"original_triangles": indices.size() / 3,
					"target_triangles": target_index_count / 3,
					"primary_triangles": primary_indices.size() / 3,
					"vertices": flat_vertices,
					"triangles": flat_indices,
				}
				_write_json(FALLBACK_ROOT + "/inputs/" + key + ".json", request)
				requests.append(request.duplicate(false))
				requests[-1].erase("vertices")
				requests[-1].erase("triangles")
		root.free()
	_write_json(REQUESTS_PATH, {"requests": requests})
	print("Aggressive fallback requests: %d -> %s" % [requests.size(), REQUESTS_PATH])
	quit()


func _collect(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, output)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	return result as Dictionary if result is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
