extends SceneTree

## Validates that the generated 20% PackedScenes preserve the public scene-tree
## interface of their source models. This is intentionally independent from the
## reference-switching script so it can be run before applying or after rollback.

const MANIFEST_PATH := "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/manifest.json"
const SWITCH_MANIFEST_PATH := "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/production_reference_switch.json"


func _initialize() -> void:
	var manifest := _read_json(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing or invalid decimation manifest: %s" % MANIFEST_PATH)
		quit(1)
		return

	var failures: Array[Dictionary] = []
	var validated := 0
	for raw_entry in manifest.get("processed", []):
		var entry: Dictionary = raw_entry
		if not bool(entry.get("success", false)):
			continue
		var source_path := str(entry.get("source", ""))
		var output_path := str(entry.get("output", ""))
		var source_scene := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var output_scene := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if source_scene == null or output_scene == null:
			failures.append({
				"source": source_path,
				"output": output_path,
				"reason": "PackedScene load failed",
			})
			continue

		var source_root := source_scene.instantiate()
		var output_root := output_scene.instantiate()
		if source_root == null or output_root == null:
			if source_root != null:
				source_root.free()
			if output_root != null:
				output_root.free()
			failures.append({
				"source": source_path,
				"output": output_path,
				"reason": "PackedScene instantiate failed",
			})
			continue

		var source_signature: Array[Dictionary] = []
		var output_signature: Array[Dictionary] = []
		_collect_node_signature(source_root, source_root, source_signature)
		_collect_node_signature(output_root, output_root, output_signature)
		if source_signature != output_signature:
			failures.append({
				"source": source_path,
				"output": output_path,
				"reason": "node path/type signature differs",
				"source_signature": source_signature,
				"output_signature": output_signature,
			})
		else:
			validated += 1

		source_root.free()
		output_root.free()

	var uid_records: Array[Dictionary] = []
	for raw_entry in manifest.get("processed", []):
		var entry: Dictionary = raw_entry
		if not bool(entry.get("success", false)):
			continue
		var output_path := str(entry.get("output", ""))
		var output_uid := ResourceSaver.get_resource_id_for_path(output_path, false)
		uid_records.append({
			"path": output_path,
			"uid": ResourceUID.id_to_text(output_uid) if output_uid != ResourceUID.INVALID_ID else "",
		})

	var production_failures: Array[Dictionary] = []
	var production_resources_loaded := 0
	if FileAccess.file_exists(SWITCH_MANIFEST_PATH):
		var switch_manifest := _read_json(SWITCH_MANIFEST_PATH)
		if str(switch_manifest.get("status", "")) == "applied":
			for raw_change in switch_manifest.get("changes", []):
				var change: Dictionary = raw_change
				var production_path := "res://" + str(change.get("file", ""))
				var text := _read_text(production_path)
				var reference_text_valid := true
				for raw_replacement in change.get("replacements", []):
					var replacement: Dictionary = raw_replacement
					if str(replacement.get("source", "")) in text or not str(replacement.get("output", "")) in text:
						reference_text_valid = false
						break
				if not reference_text_valid:
					production_failures.append({
						"path": production_path,
						"reason": "reference text does not match the applied switch manifest",
					})
					continue

				var resource := ResourceLoader.load(production_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				if resource == null:
					production_failures.append({
						"path": production_path,
						"reason": "production resource load failed",
					})
					continue
				if resource is PackedScene:
					var instance := (resource as PackedScene).instantiate()
					if instance == null:
						production_failures.append({
							"path": production_path,
							"reason": "production PackedScene instantiate failed",
						})
						continue
					instance.free()
				production_resources_loaded += 1

	print(JSON.stringify({
		"validated": validated,
		"failed": failures.size(),
		"failures": failures,
		"production_resources_loaded": production_resources_loaded,
		"production_failed": production_failures.size(),
		"production_failures": production_failures,
		"output_uids": uid_records,
	}))
	quit(0 if failures.is_empty() and production_failures.is_empty() else 1)


func _collect_node_signature(root: Node, node: Node, records: Array[Dictionary]) -> void:
	records.append({
		"path": "." if node == root else str(root.get_path_to(node)),
		"type": node.get_class(),
	})
	for child in node.get_children():
		_collect_node_signature(root, child, records)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
