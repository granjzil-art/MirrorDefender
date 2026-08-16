extends SceneTree

const ASSET_ROOT := "res://assets"
const OUTPUT_PATH := "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/inventory.json"
const TRIANGLE_THRESHOLD := 5000
const MODEL_EXTENSIONS := ["fbx", "glb", "gltf", "obj", "dae"]


func _initialize() -> void:
	var source_paths: Array[String] = []
	_scan_model_paths(ASSET_ROOT, source_paths)
	source_paths.sort()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))

	var records: Array[Dictionary] = []
	var candidates := 0
	var skipped := 0
	var failed := 0
	var total_triangles := 0
	for source_path in source_paths:
		var record := _inspect_model(source_path)
		record.action = "process" if int(record.get("triangles", 0)) > TRIANGLE_THRESHOLD else "skip"
		if not bool(record.get("loaded", false)):
			record.action = "failed_inventory"
			failed += 1
		elif record.action == "process":
			candidates += 1
		else:
			skipped += 1
		total_triangles += int(record.get("triangles", 0))
		records.append(record)
		print("[%d/%d] %s triangles=%d action=%s" % [records.size(), source_paths.size(), source_path, record.get("triangles", 0), record.action])

	var inventory := {
		"asset_root": ASSET_ROOT,
		"triangle_threshold_exclusive": TRIANGLE_THRESHOLD,
		"extensions": MODEL_EXTENSIONS,
		"summary": {
			"source_files": source_paths.size(),
			"process_candidates": candidates,
			"skipped_at_or_below_threshold": skipped,
			"inventory_failures": failed,
			"total_triangles_across_source_scenes": total_triangles,
		},
		"models": records,
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write inventory: %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(inventory, "\t", false, true))
	file.close()
	print("Inventory=%s candidates=%d skipped=%d failed=%d" % [OUTPUT_PATH, candidates, skipped, failed])
	quit(0 if failed == 0 else 1)


func _scan_model_paths(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Cannot scan directory: %s" % directory_path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_scan_model_paths(child_path, output)
			elif entry.get_extension().to_lower() in MODEL_EXTENSIONS:
				output.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _inspect_model(source_path: String) -> Dictionary:
	var record := {
		"source": source_path,
		"extension": source_path.get_extension().to_lower(),
		"source_bytes": _file_size(source_path),
		"import_exists": FileAccess.file_exists(source_path + ".import"),
		"loaded": false,
		"mesh_instances": 0,
		"unique_meshes": 0,
		"surfaces": 0,
		"triangle_surfaces": 0,
		"unindexed_triangle_surfaces": 0,
		"non_triangle_surfaces": 0,
		"triangles": 0,
		"vertices": 0,
		"blend_shapes": 0,
		"skinned_mesh_instances": 0,
	}
	var packed := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		record.error = "PackedScene load failed"
		return record
	var root := packed.instantiate()
	if root == null:
		record.error = "PackedScene instantiate failed"
		return record

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	var unique_mesh_ids := {}
	for mesh_instance in mesh_instances:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		record.mesh_instances += 1
		unique_mesh_ids[mesh.get_instance_id()] = true
		record.blend_shapes += mesh.get_blend_shape_count()
		if not mesh_instance.skeleton.is_empty() or mesh_instance.skin != null:
			record.skinned_mesh_instances += 1
		for surface_index in mesh.get_surface_count():
			record.surfaces += 1
			var primitive: Mesh.PrimitiveType = mesh.surface_get_primitive_type(surface_index)
			var vertex_count := _surface_vertex_count(mesh, surface_index)
			var index_count := _surface_index_count(mesh, surface_index)
			record.vertices += vertex_count
			if primitive == Mesh.PRIMITIVE_TRIANGLES:
				record.triangle_surfaces += 1
				if index_count == 0:
					record.unindexed_triangle_surfaces += 1
				record.triangles += index_count / 3 if index_count > 0 else vertex_count / 3
			else:
				record.non_triangle_surfaces += 1
	record.unique_meshes = unique_mesh_ids.size()
	record.loaded = true
	root.free()
	return record


func _surface_vertex_count(mesh: Mesh, surface_index: int) -> int:
	if mesh.has_method("surface_get_array_len"):
		return int(mesh.call("surface_get_array_len", surface_index))
	var arrays := mesh.surface_get_arrays(surface_index)
	return arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX] != null else 0


func _surface_index_count(mesh: Mesh, surface_index: int) -> int:
	if mesh.has_method("surface_get_array_index_len"):
		return int(mesh.call("surface_get_array_index_len", surface_index))
	var arrays := mesh.surface_get_arrays(surface_index)
	return arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, output)


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size
