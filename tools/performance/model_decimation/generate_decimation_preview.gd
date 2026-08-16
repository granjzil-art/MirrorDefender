extends SceneTree

## Isolated model-decimation evaluation batch.
##
## The script only reads the source model and its `.import` sidecar, then writes
## new PackedScene resources below OUTPUT_ROOT. It never saves the source scene,
## changes import options, or updates runtime scene/resource references.

const OUTPUT_ROOT := "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval"
const NORMAL_DEVIATION_THRESHOLD := 1.0
const RATIOS := [0.70, 0.50, 0.30]
const TARGETS := [
	{
		"id": "desert_castle",
		"label": "Desert Castle",
		"source": "res://assets/buildings/Castle/fbx/desertcastle.fbx",
	},
	{
		"id": "arrow_tower_3_1",
		"label": "Arrow Tower 3-1",
		"source": "res://assets/buildings/ArrowTower/fbx/arrowtower3_1.fbx",
	},
	{
		"id": "mace_8",
		"label": "Mace 8",
		"source": "res://assets/buildings/mace/mace8.glb",
	},
]


func _init() -> void:
	var started_ms := Time.get_ticks_msec()
	var manifest := {
		"batch": "2026-08-16_meshoptimizer_eval",
		"purpose": "Isolated geometry-decimation preview; not applied to production assets or scenes.",
		"algorithm": "Godot SurfaceTool.generate_lod (meshoptimizer) with compacted referenced vertices",
		"normal_deviation_threshold": NORMAL_DEVIATION_THRESHOLD,
		"requested_ratios": RATIOS,
		"output_root": OUTPUT_ROOT,
		"source_configuration_modified": false,
		"models": [],
		"errors": [],
	}

	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		manifest.errors.append("Cannot create output root: %s" % error_string(mkdir_error))
		_finish(manifest, started_ms)
		return

	for target in TARGETS:
		var source_path := str(target.source)
		var integrity_before := _capture_source_integrity(source_path)
		var model_record := {
			"id": str(target.id),
			"label": str(target.label),
			"source": source_path,
			"source_integrity_before": integrity_before,
			"variants": [],
		}

		for ratio in RATIOS:
			var variant_result := _generate_variant(target, float(ratio))
			model_record.variants.append(variant_result)
			if not bool(variant_result.get("success", false)):
				manifest.errors.append("%s %.0f%%: %s" % [target.id, ratio * 100.0, variant_result.get("error", "unknown error")])

		var integrity_after := _capture_source_integrity(source_path)
		model_record.source_integrity_after = integrity_after
		model_record.source_integrity_unchanged = integrity_before == integrity_after
		if not model_record.source_integrity_unchanged:
			manifest.errors.append("Source integrity changed unexpectedly: %s" % source_path)
		manifest.models.append(model_record)

	_finish(manifest, started_ms)


func _generate_variant(target: Dictionary, requested_ratio: float) -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var source_path := str(target.source)
	var source_scene := load(source_path) as PackedScene
	if source_scene == null:
		return _variant_error(requested_ratio, "Cannot load source PackedScene: %s" % source_path, started_ms)

	var root := source_scene.instantiate()
	if root == null:
		return _variant_error(requested_ratio, "Cannot instantiate source PackedScene: %s" % source_path, started_ms)

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	if mesh_instances.is_empty():
		root.free()
		return _variant_error(requested_ratio, "No MeshInstance3D found", started_ms)

	var result := {
		"success": true,
		"requested_ratio": requested_ratio,
		"mesh_instances": [],
		"original_triangles": 0,
		"reduced_triangles": 0,
		"original_vertices": 0,
		"reduced_vertices": 0,
	}

	for mesh_instance in mesh_instances:
		var optimized_result := _build_optimized_mesh(mesh_instance.mesh, requested_ratio)
		if not bool(optimized_result.get("success", false)):
			root.free()
			return _variant_error(
				requested_ratio,
				"%s: %s" % [root.get_path_to(mesh_instance), optimized_result.get("error", "mesh optimization failed")],
				started_ms
			)

		mesh_instance.mesh = optimized_result.mesh
		var mesh_record: Dictionary = optimized_result.record
		mesh_record.node_path = str(root.get_path_to(mesh_instance))
		result.mesh_instances.append(mesh_record)
		result.original_triangles += int(mesh_record.original_triangles)
		result.reduced_triangles += int(mesh_record.reduced_triangles)
		result.original_vertices += int(mesh_record.original_vertices)
		result.reduced_vertices += int(mesh_record.reduced_vertices)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return _variant_error(requested_ratio, "PackedScene.pack failed: %s" % error_string(pack_error), started_ms)

	var target_dir := "%s/%s" % [OUTPUT_ROOT, target.id]
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		root.free()
		return _variant_error(requested_ratio, "Cannot create target directory: %s" % error_string(mkdir_error), started_ms)

	var ratio_percent := int(round(requested_ratio * 100.0))
	var output_path := "%s/%s_%02d.scn" % [target_dir, target.id, ratio_percent]
	var save_error := ResourceSaver.save(packed, output_path)
	root.free()
	if save_error != OK:
		return _variant_error(requested_ratio, "ResourceSaver.save failed: %s" % error_string(save_error), started_ms)

	result.output = output_path
	result.output_bytes = _file_size(output_path)
	result.actual_triangle_ratio = _safe_ratio(result.reduced_triangles, result.original_triangles)
	result.actual_vertex_ratio = _safe_ratio(result.reduced_vertices, result.original_vertices)
	result.triangles_removed = int(result.original_triangles) - int(result.reduced_triangles)
	result.vertices_removed = int(result.original_vertices) - int(result.reduced_vertices)
	result.elapsed_ms = Time.get_ticks_msec() - started_ms
	print("Generated %s: %d -> %d triangles (%.2f%%), %d -> %d vertices" % [
		output_path,
		result.original_triangles,
		result.reduced_triangles,
		result.actual_triangle_ratio * 100.0,
		result.original_vertices,
		result.reduced_vertices,
	])
	return result


func _build_optimized_mesh(source_mesh: Mesh, requested_ratio: float) -> Dictionary:
	if source_mesh == null:
		return {"success": false, "error": "Mesh resource is null"}
	if source_mesh.get_blend_shape_count() > 0:
		return {"success": false, "error": "Blend-shape meshes are excluded from this static evaluation batch"}

	var optimized_mesh := ArrayMesh.new()
	optimized_mesh.resource_name = "%s_decimated_%02d" % [source_mesh.resource_name, int(round(requested_ratio * 100.0))]
	var record := {
		"mesh_name": source_mesh.resource_name,
		"original_triangles": 0,
		"reduced_triangles": 0,
		"original_vertices": 0,
		"reduced_vertices": 0,
		"surfaces": [],
	}

	for surface_index in source_mesh.get_surface_count():
		var primitive: Mesh.PrimitiveType = source_mesh.surface_get_primitive_type(surface_index)
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			return {"success": false, "error": "Surface %d is not a triangle surface" % surface_index}

		var source_arrays := source_mesh.surface_get_arrays(surface_index)
		var source_vertices = source_arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
		if source_vertices == null or source_vertices.size() == 0:
			return {"success": false, "error": "Surface %d has no vertices" % surface_index}
		if source_indices.is_empty() or source_indices.size() % 3 != 0:
			return {"success": false, "error": "Surface %d must have a triangle index buffer" % surface_index}

		var target_index_count := maxi(3, int(floor(source_indices.size() * requested_ratio / 3.0)) * 3)
		var surface_tool := SurfaceTool.new()
		surface_tool.create_from(source_mesh, surface_index)
		var reduced_indices := surface_tool.generate_lod(NORMAL_DEVIATION_THRESHOLD, target_index_count)
		if reduced_indices.is_empty() or reduced_indices.size() % 3 != 0:
			return {"success": false, "error": "Surface %d simplifier returned an invalid index buffer" % surface_index}

		var compact_result := _compact_surface_arrays(source_arrays, reduced_indices)
		if not bool(compact_result.get("success", false)):
			return {"success": false, "error": "Surface %d: %s" % [surface_index, compact_result.get("error", "compaction failed")]}

		var compact_arrays: Array = compact_result.arrays
		optimized_mesh.add_surface_from_arrays(primitive, compact_arrays)
		var output_surface := optimized_mesh.get_surface_count() - 1
		optimized_mesh.surface_set_material(output_surface, source_mesh.surface_get_material(surface_index))
		optimized_mesh.surface_set_name(output_surface, source_mesh.surface_get_name(surface_index))

		var surface_record := {
			"surface": surface_index,
			"original_triangles": source_indices.size() / 3,
			"reduced_triangles": reduced_indices.size() / 3,
			"original_vertices": source_vertices.size(),
			"reduced_vertices": compact_result.reduced_vertices,
		}
		surface_record.actual_triangle_ratio = _safe_ratio(surface_record.reduced_triangles, surface_record.original_triangles)
		surface_record.actual_vertex_ratio = _safe_ratio(surface_record.reduced_vertices, surface_record.original_vertices)
		record.surfaces.append(surface_record)
		record.original_triangles += int(surface_record.original_triangles)
		record.reduced_triangles += int(surface_record.reduced_triangles)
		record.original_vertices += int(surface_record.original_vertices)
		record.reduced_vertices += int(surface_record.reduced_vertices)

	return {"success": true, "mesh": optimized_mesh, "record": record}


func _compact_surface_arrays(source_arrays: Array, reduced_indices: PackedInt32Array) -> Dictionary:
	var vertices = source_arrays[Mesh.ARRAY_VERTEX]
	var source_vertex_count: int = vertices.size()
	var old_to_new := PackedInt32Array()
	old_to_new.resize(source_vertex_count)
	old_to_new.fill(-1)
	var new_to_old := PackedInt32Array()
	var remapped_indices := PackedInt32Array()
	remapped_indices.resize(reduced_indices.size())

	for index_position in reduced_indices.size():
		var old_index := reduced_indices[index_position]
		if old_index < 0 or old_index >= source_vertex_count:
			return {"success": false, "error": "Simplifier returned out-of-range vertex index %d" % old_index}
		var new_index := old_to_new[old_index]
		if new_index == -1:
			new_index = new_to_old.size()
			old_to_new[old_index] = new_index
			new_to_old.append(old_index)
		remapped_indices[index_position] = new_index

	var compact_arrays: Array = []
	compact_arrays.resize(Mesh.ARRAY_MAX)
	for array_index in Mesh.ARRAY_INDEX:
		var source_attribute = source_arrays[array_index]
		if source_attribute == null or source_attribute.size() == 0:
			continue
		if source_attribute.size() % source_vertex_count != 0:
			return {
				"success": false,
				"error": "Attribute %d size %d is not divisible by vertex count %d" % [array_index, source_attribute.size(), source_vertex_count],
			}
		var stride: int = source_attribute.size() / source_vertex_count
		var compact_attribute = source_attribute.duplicate()
		compact_attribute.resize(new_to_old.size() * stride)
		for new_index in new_to_old.size():
			var old_index := new_to_old[new_index]
			for component in stride:
				compact_attribute[new_index * stride + component] = source_attribute[old_index * stride + component]
		compact_arrays[array_index] = compact_attribute

	compact_arrays[Mesh.ARRAY_INDEX] = remapped_indices
	return {
		"success": true,
		"arrays": compact_arrays,
		"reduced_vertices": new_to_old.size(),
	}


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, output)


func _capture_source_integrity(source_path: String) -> Dictionary:
	var import_path := source_path + ".import"
	return {
		"source_sha256": FileAccess.get_sha256(source_path),
		"source_bytes": _file_size(source_path),
		"import_path": import_path,
		"import_sha256": FileAccess.get_sha256(import_path),
		"import_bytes": _file_size(import_path),
	}


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _safe_ratio(numerator: Variant, denominator: Variant) -> float:
	if float(denominator) <= 0.0:
		return 0.0
	return float(numerator) / float(denominator)


func _variant_error(requested_ratio: float, message: String, started_ms: int) -> Dictionary:
	push_error(message)
	return {
		"success": false,
		"requested_ratio": requested_ratio,
		"error": message,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}


func _finish(manifest: Dictionary, started_ms: int) -> void:
	manifest.elapsed_ms = Time.get_ticks_msec() - started_ms
	manifest.completed = manifest.errors.is_empty()
	var manifest_path := OUTPUT_ROOT + "/manifest.json"
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write manifest: %s" % manifest_path)
	else:
		file.store_string(JSON.stringify(manifest, "\t", false, true))
		file.close()
	print("Manifest: %s" % manifest_path)
	print("Completed=%s errors=%d elapsed_ms=%d" % [manifest.completed, manifest.errors.size(), manifest.elapsed_ms])
	quit(0 if manifest.completed else 1)
