@tool
## Transactional authoring service used by the editor catalog manager.
## It owns identity, persistence and reference safety; UI code only edits the
## returned StuffDefinition resources and asks this service to commit changes.
class_name StuffCatalogAuthoring
extends RefCounted

const LevelResourceScript := preload("res://scripts/level/LevelResource.gd")
const ModelAssetDefinitionScript := preload("res://scripts/presentation/ModelAssetDefinition.gd")
const StuffCatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")

const DEFAULT_DEFINITION_DIRECTORY := "res://resources/stuffs"


func create_definition(
	catalog: StuffCatalogScript,
	requested_id: String,
	display_name: String,
	model_scene: PackedScene = null,
	runtime_scale: Vector3 = Vector3.ONE
) -> Dictionary:
	if catalog == null:
		return _failure("关卡元素目录为空")
	var definition := StuffDefinitionScript.new()
	definition.stuff_id = StringName(make_unique_id(catalog, requested_id))
	definition.display_name = display_name.strip_edges()
	if definition.display_name.is_empty():
		definition.display_name = String(definition.stuff_id)
	definition.description = ""
	definition.authoring_enabled = true
	definition.exclusive_with_other_stuff = true
	definition.blocks_tile_building = true
	definition.blocks_edge_building = false
	definition.blocks_ballistics = false
	definition.enemy_navigation = StuffDefinitionScript.EnemyNavigation.PASSABLE
	definition.navigation_affects_airborne = false
	definition.durability_mode = StuffDefinitionScript.DurabilityMode.INDESTRUCTIBLE
	definition.max_durability = 100.0
	set_model_scene(definition, model_scene, runtime_scale)
	if not catalog.add_definition(definition):
		return _failure("无法把新关卡元素加入目录；请检查 ID 是否重复")
	return _success(definition)


func duplicate_definition(
	catalog: StuffCatalogScript,
	source: StuffDefinitionScript
) -> Dictionary:
	if catalog == null or source == null or not catalog.contains_definition(source):
		return _failure("只能复制目录中已有的关卡元素")
	var duplicate := source.duplicate(true) as StuffDefinitionScript
	duplicate.resource_path = ""
	duplicate.stuff_id = StringName(make_unique_id(catalog, "%s_copy" % source.stuff_id))
	duplicate.display_name = "%s 副本" % source.display_name
	duplicate.authoring_enabled = true
	if not catalog.add_definition(duplicate):
		return _failure("复制关卡元素失败")
	var source_index := catalog.definitions.find(source)
	var duplicate_index := catalog.definitions.find(duplicate)
	if source_index >= 0 and duplicate_index >= 0:
		catalog.move_definition(duplicate_index, source_index + 1)
	return _success(duplicate)


func set_model_scene(
	definition: StuffDefinitionScript,
	model_scene: PackedScene,
	runtime_scale: Vector3 = Vector3.ONE
) -> void:
	if definition == null:
		return
	if model_scene == null:
		definition.model_asset = null
		definition.visual_scene = null
		definition.emit_changed()
		return
	if definition.model_asset == null:
		definition.model_asset = ModelAssetDefinitionScript.new()
	definition.model_asset.scene = model_scene
	definition.model_asset.runtime_scale = runtime_scale
	definition.visual_scene = null
	definition.model_asset.emit_changed()
	definition.emit_changed()


func make_unique_id(catalog: StuffCatalogScript, requested_id: String) -> String:
	var base_id := sanitize_id(requested_id)
	if base_id.is_empty():
		base_id = "stuff"
	if catalog == null or catalog.get_definition(StringName(base_id), true) == null:
		return base_id
	var suffix := 2
	while catalog.get_definition(StringName("%s_%d" % [base_id, suffix]), true) != null:
		suffix += 1
	return "%s_%d" % [base_id, suffix]


func sanitize_id(value: String) -> String:
	var source := value.strip_edges().to_lower()
	var result := ""
	var previous_was_separator := false
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var code := character.unicode_at(0)
		var accepted := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or character == "_"
		)
		if accepted:
			result += character
			previous_was_separator = false
		elif not previous_was_separator and not result.is_empty():
			result += "_"
			previous_was_separator = true
	return result.trim_suffix("_")


func save_definition(
	catalog: StuffCatalogScript,
	definition: StuffDefinitionScript,
	definition_directory: String = DEFAULT_DEFINITION_DIRECTORY,
	catalog_path: String = ""
) -> Dictionary:
	if catalog == null or definition == null or not catalog.contains_definition(definition):
		return _failure("待保存元素不属于当前目录")
	var result := save_catalog(catalog, definition_directory, catalog_path)
	result["definition"] = definition
	result["path"] = definition.resource_path if bool(result.get("success", false)) else ""
	return result


func save_catalog(
	catalog: StuffCatalogScript,
	definition_directory: String = DEFAULT_DEFINITION_DIRECTORY,
	catalog_path: String = ""
) -> Dictionary:
	if catalog == null:
		return _failure("关卡元素目录为空")
	var errors := catalog.validate_configuration()
	if not errors.is_empty():
		return _failure("配置校验失败：\n%s" % "\n".join(errors))
	var directory_result := _ensure_directory(definition_directory)
	if directory_result != OK:
		return _failure("无法创建关卡元素资源目录：%s" % error_string(directory_result))
	var targets: Dictionary = {}
	for definition in catalog.definitions:
		var target_path := definition.resource_path
		if target_path.is_empty() or _is_embedded_resource_path(target_path):
			target_path = "%s/%s.tres" % [definition_directory.trim_suffix("/"), definition.stuff_id]
			if ResourceLoader.exists(target_path):
				return _failure("目标资源已存在：%s" % target_path)
		if targets.has(target_path):
			return _failure("多个元素指向同一资源路径：%s" % target_path)
		targets[target_path] = definition
	for raw_target_path in targets:
		var target_path: String = raw_target_path
		var target_definition: StuffDefinitionScript = targets[target_path]
		var save_error := ResourceSaver.save(target_definition, target_path)
		if save_error != OK:
			return _failure("保存关卡元素失败：%s（%s）" % [target_path, error_string(save_error)])
		if target_definition.resource_path != target_path:
			target_definition.take_over_path(target_path)
	var resolved_catalog_path := catalog_path if not catalog_path.is_empty() else catalog.resource_path
	if resolved_catalog_path.is_empty():
		return _failure("目录资源没有保存路径")
	var catalog_error := ResourceSaver.save(catalog, resolved_catalog_path)
	if catalog_error != OK:
		return _failure("保存关卡元素目录失败：%s" % error_string(catalog_error))
	return {
		"success": true,
		"message": "已保存 %d 个关卡元素与目录" % catalog.definitions.size(),
		"definition": null,
		"path": resolved_catalog_path,
	}


func _is_embedded_resource_path(path: String) -> bool:
	return "::" in path


func find_level_references(
	definition: StuffDefinitionScript,
	level_directory: String = "res://resources/levels"
) -> PackedStringArray:
	var references := PackedStringArray()
	if definition == null:
		return references
	for path in _collect_resource_paths(level_directory):
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is LevelResourceScript:
			continue
		var level := resource as LevelResourceScript
		var snapshot := level.get_effective_content_snapshot()
		var placements: Array = snapshot.get("stuff_placements", [])
		for placement in placements:
			if placement != null and _same_definition(placement.definition, definition):
				references.append(path)
				break
	references.sort()
	return references


func remove_definition_if_unreferenced(
	catalog: StuffCatalogScript,
	definition: StuffDefinitionScript,
	level_directory: String = "res://resources/levels"
) -> Dictionary:
	if catalog == null or definition == null or not catalog.contains_definition(definition):
		return _failure("待移除元素不属于当前目录")
	var references := find_level_references(definition, level_directory)
	if not references.is_empty():
		return {
			"success": false,
			"message": "仍被以下关卡引用，不能从目录移除：\n%s" % "\n".join(references),
			"references": references,
		}
	if not catalog.remove_definition(definition):
		return _failure("从目录移除关卡元素失败")
	return {
		"success": true,
		"message": "已从目录移除；资源文件未删除",
		"definition": definition,
		"references": references,
	}


func _same_definition(first: StuffDefinitionScript, second: StuffDefinitionScript) -> bool:
	if first == second:
		return true
	if first == null or second == null:
		return false
	if not first.resource_path.is_empty() and first.resource_path == second.resource_path:
		return true
	return first.stuff_id == second.stuff_id


func _collect_resource_paths(directory_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if entry != "." and entry != "..":
				result.append_array(_collect_resource_paths("%s/%s" % [directory_path.trim_suffix("/"), entry]))
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			result.append("%s/%s" % [directory_path.trim_suffix("/"), entry])
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _ensure_directory(directory_path: String) -> Error:
	if DirAccess.dir_exists_absolute(directory_path):
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))


func _success(definition: StuffDefinitionScript) -> Dictionary:
	return {"success": true, "message": "", "definition": definition}


func _failure(message: String) -> Dictionary:
	return {"success": false, "message": message, "definition": null}
