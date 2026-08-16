extends SceneTree

## Generates isolated 20% triangle-count scene copies for every model in the
## inventory whose source scene contains more than 5,000 triangles.
## Existing source models, import sidecars and runtime references are read-only.

const BATCH_NAME := "2026-08-16_all_models_20pct"
const OUTPUT_ROOT := "res://outputs/model_decimation_20pct/" + BATCH_NAME
const MODEL_OUTPUT_ROOT := OUTPUT_ROOT + "/models"
const INVENTORY_PATH := OUTPUT_ROOT + "/inventory.json"
const MANIFEST_PATH := OUTPUT_ROOT + "/manifest.json"
const PARTIAL_MANIFEST_PATH := OUTPUT_ROOT + "/manifest.partial.json"
const REPORT_PATH := OUTPUT_ROOT + "/REPORT.md"
const AGGRESSIVE_FALLBACK_OUTPUT_ROOT := OUTPUT_ROOT + "/aggressive_fallback/outputs"
const TRIANGLE_THRESHOLD := 5000
const TARGET_RATIO := 0.20
const NORMAL_DEVIATION_THRESHOLD := 1.0
const EXCLUDED_SOURCES := {
	"res://assets/greattree/realistic_tree_gltf/scene.gltf": "user_excluded_realistic_tree",
}


func _initialize() -> void:
	var started_ms := Time.get_ticks_msec()
	var inventory := _read_json(INVENTORY_PATH)
	if inventory.is_empty():
		push_error("Inventory is missing or invalid: %s" % INVENTORY_PATH)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODEL_OUTPUT_ROOT))
	var manifest := {
		"batch": BATCH_NAME,
		"purpose": "All project asset models above 5,000 triangles reduced to a 20% isolated evaluation copy.",
		"scope": "res://assets/**/*.{fbx,glb,gltf,obj,dae}",
		"triangle_threshold_exclusive": TRIANGLE_THRESHOLD,
		"target_triangle_ratio": TARGET_RATIO,
		"normal_deviation_threshold": NORMAL_DEVIATION_THRESHOLD,
		"explicit_exclusions": EXCLUDED_SOURCES,
		"algorithm": "Godot SurfaceTool.generate_lod (meshoptimizer), followed by unreferenced-vertex compaction",
		"production_references_modified": false,
		"source_model_configuration_modified": false,
		"processed": [],
		"skipped": [],
		"failed": [],
		"summary": {},
	}

	for raw_record in inventory.models:
		var inventory_record: Dictionary = raw_record
		var source_path := str(inventory_record.source)
		var triangle_count := int(inventory_record.get("triangles", 0))
		if EXCLUDED_SOURCES.has(source_path):
			var stale_output_path := _output_path_for_source(source_path)
			var stale_output_removed := true
			if FileAccess.file_exists(stale_output_path):
				stale_output_removed = DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_output_path)) == OK
			manifest.skipped.append({
				"source": source_path,
				"triangles": triangle_count,
				"reason": EXCLUDED_SOURCES[source_path],
				"stale_output_removed": stale_output_removed,
			})
			if not stale_output_removed:
				manifest.failed.append({
					"source": source_path,
					"reason": "Could not remove the stale excluded output: %s" % stale_output_path,
				})
		elif not bool(inventory_record.get("loaded", false)):
			manifest.failed.append({
				"source": source_path,
				"reason": "Inventory could not load the source model",
			})
		elif triangle_count <= TRIANGLE_THRESHOLD:
			manifest.skipped.append({
				"source": source_path,
				"triangles": triangle_count,
				"reason": "triangle_count_at_or_below_5000",
			})
		else:
			var result := _generate_model(source_path, triangle_count)
			if bool(result.get("success", false)):
				manifest.processed.append(result)
			else:
				manifest.failed.append(result)
			print("[%d/%d candidates] %s -> %s" % [
				manifest.processed.size() + manifest.failed.size(),
				int(inventory.summary.process_candidates) - EXCLUDED_SOURCES.size(),
				source_path,
				"OK" if result.get("success", false) else "FAILED: %s" % result.get("reason", "unknown"),
			])
		_write_json(PARTIAL_MANIFEST_PATH, manifest)

	manifest.summary = _build_summary(manifest, inventory, started_ms)
	manifest.completed = manifest.failed.is_empty()
	_write_json(MANIFEST_PATH, manifest)
	_write_report(manifest)
	if FileAccess.file_exists(PARTIAL_MANIFEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PARTIAL_MANIFEST_PATH))
	print("Manifest=%s Report=%s" % [MANIFEST_PATH, REPORT_PATH])
	print(JSON.stringify(manifest.summary))
	quit(0 if manifest.completed else 1)


func _generate_model(source_path: String, inventory_triangles: int) -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var source_integrity_before := _capture_source_integrity(source_path)
	var source_scene := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if source_scene == null:
		return _model_error(source_path, "PackedScene load failed", started_ms)
	var root := source_scene.instantiate()
	if root == null:
		return _model_error(source_path, "PackedScene instantiate failed", started_ms)

	var before_stats := _collect_scene_stats(root)
	if int(before_stats.triangles) != inventory_triangles:
		root.free()
		return _model_error(source_path, "Inventory triangle count changed from %d to %d" % [inventory_triangles, before_stats.triangles], started_ms)

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	var mesh_records: Array[Dictionary] = []
	var optimized_mesh_cache := {}
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue
		var source_mesh := mesh_instance.mesh
		var mesh_id := source_mesh.get_instance_id()
		var optimized_result: Dictionary
		if optimized_mesh_cache.has(mesh_id):
			optimized_result = optimized_mesh_cache[mesh_id]
		else:
			optimized_result = _build_optimized_mesh(source_mesh, source_path, str(root.get_path_to(mesh_instance)))
			if not bool(optimized_result.get("success", false)):
				root.free()
				return _model_error(
					source_path,
					"%s: %s" % [root.get_path_to(mesh_instance), optimized_result.get("reason", "mesh optimization failed")],
					started_ms
				)
			optimized_mesh_cache[mesh_id] = optimized_result
		mesh_instance.mesh = optimized_result.mesh
		var mesh_record: Dictionary = optimized_result.record.duplicate(true)
		mesh_record.node_path = str(root.get_path_to(mesh_instance))
		mesh_records.append(mesh_record)

	var after_build_stats := _collect_scene_stats(root)
	var output_path := _output_path_for_source(source_path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		root.free()
		return _model_error(source_path, "Output directory creation failed: %s" % error_string(mkdir_error), started_ms)

	var packed_output := PackedScene.new()
	var pack_error := packed_output.pack(root)
	if pack_error != OK:
		root.free()
		return _model_error(source_path, "PackedScene.pack failed: %s" % error_string(pack_error), started_ms)
	var save_error := ResourceSaver.save(packed_output, output_path)
	root.free()
	if save_error != OK:
		return _model_error(source_path, "ResourceSaver.save failed: %s" % error_string(save_error), started_ms)

	var validation_scene := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if validation_scene == null:
		return _model_error(source_path, "Saved output cannot be reloaded", started_ms)
	var validation_root := validation_scene.instantiate()
	if validation_root == null:
		return _model_error(source_path, "Saved output cannot be instantiated", started_ms)
	var reload_stats := _collect_scene_stats(validation_root)
	validation_root.free()

	var source_integrity_after := _capture_source_integrity(source_path)
	var source_integrity_unchanged := source_integrity_before == source_integrity_after
	var structural_validation := (
		int(before_stats.nodes) == int(reload_stats.nodes)
		and int(before_stats.mesh_instances) == int(reload_stats.mesh_instances)
		and int(before_stats.surfaces) == int(reload_stats.surfaces)
		and int(before_stats.non_null_materials) == int(reload_stats.non_null_materials)
		and int(before_stats.skeletons) == int(reload_stats.skeletons)
		and int(before_stats.animation_players) == int(reload_stats.animation_players)
		and int(after_build_stats.triangles) == int(reload_stats.triangles)
		and int(after_build_stats.vertices) == int(reload_stats.vertices)
	)
	if not source_integrity_unchanged:
		return _model_error(source_path, "Source model or .import hash changed during generation", started_ms)
	if not structural_validation:
		return _model_error(source_path, "Reloaded output failed structural validation", started_ms)

	return {
		"success": true,
		"source": source_path,
		"output": output_path,
		"source_bytes": _file_size(source_path),
		"output_bytes": _file_size(output_path),
		"original_triangles": before_stats.triangles,
		"reduced_triangles": reload_stats.triangles,
		"triangle_ratio": _safe_ratio(reload_stats.triangles, before_stats.triangles),
		"triangles_removed": int(before_stats.triangles) - int(reload_stats.triangles),
		"original_vertices": before_stats.vertices,
		"reduced_vertices": reload_stats.vertices,
		"vertex_ratio": _safe_ratio(reload_stats.vertices, before_stats.vertices),
		"vertices_removed": int(before_stats.vertices) - int(reload_stats.vertices),
		"mesh_records": mesh_records,
		"before_stats": before_stats,
		"reload_stats": reload_stats,
		"source_integrity_before": source_integrity_before,
		"source_integrity_after": source_integrity_after,
		"source_integrity_unchanged": source_integrity_unchanged,
		"structural_validation_passed": structural_validation,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}


func _build_optimized_mesh(source_mesh: Mesh, source_path: String, node_path: String) -> Dictionary:
	var optimized_mesh := ArrayMesh.new()
	optimized_mesh.resource_name = source_mesh.resource_name + "_decimated_20pct"
	for blend_shape_index in source_mesh.get_blend_shape_count():
		optimized_mesh.add_blend_shape(source_mesh.get_blend_shape_name(blend_shape_index))
	if source_mesh.get_blend_shape_count() > 0:
		optimized_mesh.set_blend_shape_mode(source_mesh.get_blend_shape_mode())

	var record := {
		"mesh_name": source_mesh.resource_name,
		"blend_shapes": source_mesh.get_blend_shape_count(),
		"surfaces": [],
		"original_triangles": 0,
		"reduced_triangles": 0,
		"original_vertices": 0,
		"reduced_vertices": 0,
	}

	for surface_index in source_mesh.get_surface_count():
		var primitive: Mesh.PrimitiveType = source_mesh.surface_get_primitive_type(surface_index)
		var source_arrays := source_mesh.surface_get_arrays(surface_index)
		var source_blend_shapes := source_mesh.surface_get_blend_shape_arrays(surface_index)
		var source_vertices = source_arrays[Mesh.ARRAY_VERTEX]
		if source_vertices == null or source_vertices.size() == 0:
			return {"success": false, "reason": "Surface %d has no vertices" % surface_index}

		var surface_record := {
			"surface": surface_index,
			"primitive": primitive,
			"original_vertices": source_vertices.size(),
			"reduced_vertices": source_vertices.size(),
			"original_triangles": 0,
			"reduced_triangles": 0,
			"simplified": false,
		}
		var output_arrays: Array = source_arrays
		var output_blend_shapes: Array = source_blend_shapes

		if primitive == Mesh.PRIMITIVE_TRIANGLES:
			var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
			if source_indices.is_empty() or source_indices.size() % 3 != 0:
				return {"success": false, "reason": "Surface %d must have an indexed triangle buffer" % surface_index}
			var target_index_count := maxi(3, int(floor(source_indices.size() * TARGET_RATIO / 3.0)) * 3)
			var surface_tool := SurfaceTool.new()
			surface_tool.create_from(source_mesh, surface_index)
			var reduced_indices := surface_tool.generate_lod(NORMAL_DEVIATION_THRESHOLD, target_index_count)
			if reduced_indices.is_empty() or reduced_indices.size() % 3 != 0:
				return {"success": false, "reason": "Surface %d simplifier returned an invalid index buffer" % surface_index}
			var compaction: Dictionary
			if reduced_indices.size() > target_index_count:
				var fallback_key := (source_path + "|" + node_path + "|" + str(surface_index)).sha256_text()
				var fallback_path := AGGRESSIVE_FALLBACK_OUTPUT_ROOT + "/" + fallback_key + ".json"
				var fallback_data := _read_json(fallback_path)
				if fallback_data.is_empty():
					return {
						"success": false,
						"reason": "Surface %d stopped at %d triangles; aggressive fallback is missing: %s" % [surface_index, reduced_indices.size() / 3, fallback_path],
					}
				compaction = _build_fallback_arrays(source_arrays, source_blend_shapes, fallback_data, target_index_count)
				surface_record.algorithm = str(fallback_data.get("engine", "aggressive fallback"))
				reduced_indices = compaction.get("indices", PackedInt32Array())
			else:
				compaction = _build_compaction(source_arrays, source_blend_shapes, reduced_indices)
				surface_record.algorithm = "meshoptimizer"
			if not bool(compaction.get("success", false)):
				return {"success": false, "reason": "Surface %d: %s" % [surface_index, compaction.get("reason", "compaction failed")]}
			output_arrays = compaction.arrays
			output_blend_shapes = compaction.blend_shapes
			surface_record.original_triangles = source_indices.size() / 3
			surface_record.reduced_triangles = reduced_indices.size() / 3
			surface_record.reduced_vertices = compaction.reduced_vertices
			surface_record.simplified = true

		var surface_flags := 0
		if _has_custom_vertex_channels(output_arrays):
			output_arrays = _encode_custom_vertex_channels(output_arrays)
			var encoded_blend_shapes: Array = []
			for blend_shape_arrays in output_blend_shapes:
				encoded_blend_shapes.append(_encode_custom_vertex_channels(blend_shape_arrays))
			output_blend_shapes = encoded_blend_shapes
			surface_flags = source_mesh.surface_get_format(surface_index)
		var previous_surface_count := optimized_mesh.get_surface_count()
		optimized_mesh.add_surface_from_arrays(primitive, output_arrays, output_blend_shapes, {}, surface_flags)
		if optimized_mesh.get_surface_count() != previous_surface_count + 1:
			return {"success": false, "reason": "Surface %d could not be rebuilt with its original vertex format" % surface_index}
		var output_surface := optimized_mesh.get_surface_count() - 1
		optimized_mesh.surface_set_material(output_surface, source_mesh.surface_get_material(surface_index))
		optimized_mesh.surface_set_name(output_surface, source_mesh.surface_get_name(surface_index))
		record.surfaces.append(surface_record)
		record.original_triangles += int(surface_record.original_triangles)
		record.reduced_triangles += int(surface_record.reduced_triangles)
		record.original_vertices += int(surface_record.original_vertices)
		record.reduced_vertices += int(surface_record.reduced_vertices)

	optimized_mesh.set("custom_aabb", source_mesh.get_aabb())
	if source_mesh.get("lightmap_size_hint") != null:
		optimized_mesh.set("lightmap_size_hint", source_mesh.get("lightmap_size_hint"))
	return {"success": true, "mesh": optimized_mesh, "record": record}


func _build_compaction(source_arrays: Array, source_blend_shapes: Array, reduced_indices: PackedInt32Array) -> Dictionary:
	var source_vertex_count: int = source_arrays[Mesh.ARRAY_VERTEX].size()
	var old_to_new := PackedInt32Array()
	old_to_new.resize(source_vertex_count)
	old_to_new.fill(-1)
	var new_to_old := PackedInt32Array()
	var remapped_indices := PackedInt32Array()
	remapped_indices.resize(reduced_indices.size())
	for index_position in reduced_indices.size():
		var old_index := reduced_indices[index_position]
		if old_index < 0 or old_index >= source_vertex_count:
			return {"success": false, "reason": "Out-of-range simplified vertex index %d" % old_index}
		var new_index := old_to_new[old_index]
		if new_index == -1:
			new_index = new_to_old.size()
			old_to_new[old_index] = new_index
			new_to_old.append(old_index)
		remapped_indices[index_position] = new_index

	var compact_base := _compact_attribute_arrays(source_arrays, source_vertex_count, new_to_old)
	if not bool(compact_base.get("success", false)):
		return compact_base
	var compact_arrays: Array = compact_base.arrays
	compact_arrays[Mesh.ARRAY_INDEX] = remapped_indices

	var compact_blend_shapes: Array = []
	for blend_shape_arrays in source_blend_shapes:
		var compact_blend := _compact_attribute_arrays(blend_shape_arrays, source_vertex_count, new_to_old)
		if not bool(compact_blend.get("success", false)):
			return compact_blend
		compact_blend_shapes.append(compact_blend.arrays)

	return {
		"success": true,
		"arrays": compact_arrays,
		"blend_shapes": compact_blend_shapes,
		"reduced_vertices": new_to_old.size(),
	}


func _build_fallback_arrays(
	source_arrays: Array,
	source_blend_shapes: Array,
	fallback_data: Dictionary,
	target_index_count: int
) -> Dictionary:
	var flat_vertices: Array = fallback_data.get("vertices", [])
	var flat_triangles: Array = fallback_data.get("triangles", [])
	var reduced_to_original: Array = fallback_data.get("reduced_to_original", [])
	if flat_vertices.size() % 3 != 0 or flat_triangles.size() % 3 != 0:
		return {"success": false, "reason": "Aggressive fallback arrays are malformed"}
	var reduced_vertex_count := flat_vertices.size() / 3
	if reduced_to_original.size() != reduced_vertex_count:
		return {"success": false, "reason": "Aggressive fallback attribute mapping size mismatch"}
	if flat_triangles.size() > target_index_count:
		return {"success": false, "reason": "Aggressive fallback still exceeds the requested triangle budget"}

	var source_vertex_count: int = source_arrays[Mesh.ARRAY_VERTEX].size()
	var compact_arrays: Array = []
	compact_arrays.resize(Mesh.ARRAY_MAX)
	var output_vertices := PackedVector3Array()
	output_vertices.resize(reduced_vertex_count)
	for vertex_index in reduced_vertex_count:
		output_vertices[vertex_index] = Vector3(
			float(flat_vertices[vertex_index * 3]),
			float(flat_vertices[vertex_index * 3 + 1]),
			float(flat_vertices[vertex_index * 3 + 2])
		)
	compact_arrays[Mesh.ARRAY_VERTEX] = output_vertices

	for array_index in range(Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX):
		var source_attribute = source_arrays[array_index]
		if source_attribute == null or source_attribute.size() == 0:
			continue
		if source_attribute.size() % source_vertex_count != 0:
			return {"success": false, "reason": "Fallback attribute %d has an unsupported stride" % array_index}
		var stride: int = source_attribute.size() / source_vertex_count
		var compact_attribute = source_attribute.duplicate()
		compact_attribute.resize(reduced_vertex_count * stride)
		for new_index in reduced_vertex_count:
			var source_index := int(reduced_to_original[new_index])
			if source_index < 0 or source_index >= source_vertex_count:
				return {"success": false, "reason": "Fallback representative vertex is out of range"}
			for component in stride:
				compact_attribute[new_index * stride + component] = source_attribute[source_index * stride + component]
		compact_arrays[array_index] = compact_attribute

	var output_indices := PackedInt32Array()
	output_indices.resize(flat_triangles.size())
	for index_position in flat_triangles.size():
		output_indices[index_position] = int(flat_triangles[index_position])
	compact_arrays[Mesh.ARRAY_INDEX] = output_indices
	if source_blend_shapes.is_empty():
		var normal_tool := SurfaceTool.new()
		normal_tool.create_from_arrays(compact_arrays)
		normal_tool.generate_normals()
		if compact_arrays[Mesh.ARRAY_TEX_UV] != null and compact_arrays[Mesh.ARRAY_TEX_UV].size() > 0:
			normal_tool.generate_tangents()
		compact_arrays = normal_tool.commit_to_arrays()

	var compact_blend_shapes: Array = []
	for blend_shape_arrays in source_blend_shapes:
		var compact_blend: Array = []
		compact_blend.resize(Mesh.ARRAY_MAX)
		for array_index in range(Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX):
			var source_attribute = blend_shape_arrays[array_index]
			if source_attribute == null or source_attribute.size() == 0:
				continue
			var stride: int = source_attribute.size() / source_vertex_count
			var compact_attribute = source_attribute.duplicate()
			compact_attribute.resize(reduced_vertex_count * stride)
			for new_index in reduced_vertex_count:
				var source_index := int(reduced_to_original[new_index])
				for component in stride:
					compact_attribute[new_index * stride + component] = source_attribute[source_index * stride + component]
			compact_blend[array_index] = compact_attribute
		compact_blend_shapes.append(compact_blend)

	return {
		"success": true,
		"arrays": compact_arrays,
		"blend_shapes": compact_blend_shapes,
		"indices": output_indices,
		"reduced_vertices": reduced_vertex_count,
	}


func _compact_attribute_arrays(source_arrays: Array, source_vertex_count: int, new_to_old: PackedInt32Array) -> Dictionary:
	var compact_arrays: Array = []
	compact_arrays.resize(Mesh.ARRAY_MAX)
	for array_index in Mesh.ARRAY_INDEX:
		var source_attribute = source_arrays[array_index]
		if source_attribute == null or source_attribute.size() == 0:
			continue
		if source_attribute.size() % source_vertex_count != 0:
			return {
				"success": false,
				"reason": "Attribute %d size %d is not divisible by vertex count %d" % [array_index, source_attribute.size(), source_vertex_count],
			}
		var stride: int = source_attribute.size() / source_vertex_count
		var compact_attribute = source_attribute.duplicate()
		compact_attribute.resize(new_to_old.size() * stride)
		for new_index in new_to_old.size():
			var old_index := new_to_old[new_index]
			for component in stride:
				compact_attribute[new_index * stride + component] = source_attribute[old_index * stride + component]
		compact_arrays[array_index] = compact_attribute
	return {"success": true, "arrays": compact_arrays}


func _has_custom_vertex_channels(arrays: Array) -> bool:
	for array_index in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
		if arrays[array_index] != null and arrays[array_index].size() > 0:
			return true
	return false


func _encode_custom_vertex_channels(arrays: Array) -> Array:
	var encoded := arrays.duplicate()
	for array_index in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
		var attribute = encoded[array_index]
		if attribute is PackedFloat32Array:
			encoded[array_index] = (attribute as PackedFloat32Array).to_byte_array()
		elif attribute is PackedInt32Array:
			encoded[array_index] = (attribute as PackedInt32Array).to_byte_array()
	return encoded


func _collect_scene_stats(root: Node) -> Dictionary:
	var stats := {
		"nodes": 0,
		"mesh_instances": 0,
		"surfaces": 0,
		"non_null_materials": 0,
		"triangles": 0,
		"vertices": 0,
		"skeletons": 0,
		"animation_players": 0,
	}
	_collect_node_stats(root, stats)
	return stats


func _collect_node_stats(node: Node, stats: Dictionary) -> void:
	stats.nodes += 1
	if node is Skeleton3D:
		stats.skeletons += 1
	if node is AnimationPlayer:
		stats.animation_players += 1
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			stats.mesh_instances += 1
			for surface_index in mesh.get_surface_count():
				stats.surfaces += 1
				if mesh.surface_get_material(surface_index) != null or mesh_instance.get_surface_override_material(surface_index) != null:
					stats.non_null_materials += 1
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				stats.vertices += vertices.size() if vertices != null else 0
				if mesh.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES:
					stats.triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in node.get_children():
		_collect_node_stats(child, stats)


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


func _output_path_for_source(source_path: String) -> String:
	var relative := source_path.trim_prefix("res://assets/")
	return "%s/%s/%s_20pct.scn" % [MODEL_OUTPUT_ROOT, relative.get_base_dir(), relative.get_file().get_basename()]


func _build_summary(manifest: Dictionary, inventory: Dictionary, started_ms: int) -> Dictionary:
	var original_triangles := 0
	var reduced_triangles := 0
	var original_vertices := 0
	var reduced_vertices := 0
	var source_bytes := 0
	var output_bytes := 0
	for record in manifest.processed:
		original_triangles += int(record.original_triangles)
		reduced_triangles += int(record.reduced_triangles)
		original_vertices += int(record.original_vertices)
		reduced_vertices += int(record.reduced_vertices)
		source_bytes += int(record.source_bytes)
		output_bytes += int(record.output_bytes)
	return {
		"inventory_source_files": int(inventory.summary.source_files),
		"processed_models": manifest.processed.size(),
		"skipped_models": manifest.skipped.size(),
		"failed_models": manifest.failed.size(),
		"original_triangles": original_triangles,
		"reduced_triangles": reduced_triangles,
		"triangle_ratio": _safe_ratio(reduced_triangles, original_triangles),
		"triangles_removed": original_triangles - reduced_triangles,
		"original_vertices": original_vertices,
		"reduced_vertices": reduced_vertices,
		"vertex_ratio": _safe_ratio(reduced_vertices, original_vertices),
		"vertices_removed": original_vertices - reduced_vertices,
		"source_container_bytes": source_bytes,
		"output_scene_bytes": output_bytes,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}


func _write_report(manifest: Dictionary) -> void:
	var summary: Dictionary = manifest.summary
	var lines: PackedStringArray = []
	lines.append("# 全模型 20% 程序减面报告")
	lines.append("")
	lines.append("- 扫描范围：`res://assets/**/*.{fbx,glb,gltf,obj,dae}`")
	lines.append("- 规则：原场景三角面 `> 5,000` 时生成 20% 独立副本；`<= 5,000` 跳过；写实大树按用户要求明确排除。")
	lines.append("- 生产接入：未替换任何源模型、`.import`、`.tscn`、`.tres` 或现有资源引用。")
	lines.append("- 结果：处理 %d，跳过 %d，失败 %d。" % [summary.processed_models, summary.skipped_models, summary.failed_models])
	lines.append("- 三角面：%s → %s（%.2f%%，减少 %s）。" % [
		_format_integer(summary.original_triangles),
		_format_integer(summary.reduced_triangles),
		float(summary.triangle_ratio) * 100.0,
		_format_integer(summary.triangles_removed),
	])
	lines.append("- 顶点：%s → %s（%.2f%%）。" % [
		_format_integer(summary.original_vertices),
		_format_integer(summary.reduced_vertices),
		float(summary.vertex_ratio) * 100.0,
	])
	lines.append("- 受拓扑约束的 3 个模型使用第二级策略：大理石块为保留属性缝的体素聚类；弩与钉子局部表面为 fast-simplification QEM。")
	lines.append("- 额外画面对比入口：`compare_fallback_models.tscn`；弩在严格 20% 档的近景轮廓与高光变化最明显，接入生产前需重点确认可接受性。")
	lines.append("")
	lines.append("## 已处理模型（完整清单）")
	lines.append("")
	lines.append("| # | 源模型 | 原三角面 | 20% 后 | 实际比例 | 原顶点 | 新顶点 | 输出 |")
	lines.append("|---:|---|---:|---:|---:|---:|---:|---|")
	for index in manifest.processed.size():
		var record: Dictionary = manifest.processed[index]
		lines.append("| %d | `%s` | %s | %s | %.2f%% | %s | %s | `%s` |" % [
			index + 1,
			record.source,
			_format_integer(record.original_triangles),
			_format_integer(record.reduced_triangles),
			float(record.triangle_ratio) * 100.0,
			_format_integer(record.original_vertices),
			_format_integer(record.reduced_vertices),
			record.output,
		])
	lines.append("")
	lines.append("## 跳过模型（完整清单）")
	lines.append("")
	lines.append("| # | 源模型 | 三角面 | 原因 |")
	lines.append("|---:|---|---:|---|")
	for index in manifest.skipped.size():
		var record: Dictionary = manifest.skipped[index]
		var reason := "用户指定不修改" if record.reason == "user_excluded_realistic_tree" else "`<= 5,000`"
		lines.append("| %d | `%s` | %s | %s |" % [index + 1, record.source, _format_integer(record.triangles), reason])
	lines.append("")
	lines.append("## 失败模型")
	lines.append("")
	if manifest.failed.is_empty():
		lines.append("无。")
	else:
		lines.append("| 源模型 | 原因 |")
		lines.append("|---|---|")
		for record in manifest.failed:
			lines.append("| `%s` | %s |" % [record.get("source", "unknown"), record.get("reason", "unknown")])
	lines.append("")
	lines.append("## 完整性与回退")
	lines.append("")
	lines.append("每个已处理模型均在保存后重新加载，校验节点数、MeshInstance 数、表面数、非空材质槽、Skeleton、AnimationPlayer、三角面和顶点数；同时比较源模型与 `.import` 生成前后 SHA-256。删除本批次目录即可撤销全部输出，不需要恢复生产资源。")
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: %s" % REPORT_PATH)
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _model_error(source_path: String, reason: String, started_ms: int) -> Dictionary:
	push_error("%s: %s" % [source_path, reason])
	return {
		"success": false,
		"source": source_path,
		"reason": reason,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write JSON: %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t", false, true))
	file.close()


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


func _safe_ratio(numerator: Variant, denominator: Variant) -> float:
	return float(numerator) / float(denominator) if float(denominator) > 0.0 else 0.0


func _format_integer(value: Variant) -> String:
	var text := str(int(value))
	var output := ""
	while text.length() > 3:
		output = "," + text.right(3) + output
		text = text.left(text.length() - 3)
	return text + output
