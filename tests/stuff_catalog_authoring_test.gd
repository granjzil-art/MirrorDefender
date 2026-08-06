extends SceneTree

const AuthoringScript := preload("res://scripts/stuff/StuffCatalogAuthoring.gd")
const CatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")

var _checks := 0
var _failures := 0
var _directory := "user://stuff_catalog_authoring_test"


func _init() -> void:
	_run()


func _run() -> void:
	_cleanup()
	var authoring := AuthoringScript.new()
	var catalog := CatalogScript.new()
	var created: Dictionary = authoring.create_definition(catalog, "New Tree", "新树")
	var definition: StuffDefinition = created.get("definition")
	_expect(bool(created.get("success", false)), "catalog authoring creates a definition")
	_expect(definition != null and definition.stuff_id == &"new_tree", "new ids are normalized")
	_expect(
		definition.enemy_navigation == StuffDefinition.EnemyNavigation.PASSABLE,
		"new definitions explicitly own navigation"
	)
	_expect(
		definition.durability_mode == StuffDefinition.DurabilityMode.INDESTRUCTIBLE,
		"new definitions explicitly own durability"
	)
	var duplicate_result: Dictionary = authoring.duplicate_definition(catalog, definition)
	var duplicate: StuffDefinition = duplicate_result.get("definition")
	_expect(duplicate != null and duplicate.stuff_id == &"new_tree_copy", "duplicate receives a stable unique id")
	_expect(catalog.definitions[1] == duplicate, "duplicate is inserted beside its source")
	duplicate.authoring_enabled = false
	_expect(catalog.get_enabled_definitions().size() == 1, "disabled definitions stay out of creation palettes")

	var definition_directory := "%s/definitions" % _directory
	var catalog_path := "%s/catalog.tres" % _directory
	var save_result: Dictionary = authoring.save_catalog(
		catalog,
		definition_directory,
		catalog_path
	)
	_expect(bool(save_result.get("success", false)), "definition and catalog save together")
	_expect(ResourceLoader.exists(definition.resource_path), "definition receives a persistent resource path")
	_expect(ResourceLoader.exists(duplicate.resource_path), "one save persists every unsaved catalog definition")
	_expect(ResourceLoader.exists(catalog_path), "catalog order persists")

	var embedded_catalog := CatalogScript.new()
	var embedded_created: Dictionary = authoring.create_definition(
		embedded_catalog,
		"embedded_tree",
		"内嵌树",
		load("res://assets/stuffs/Tree/tscn/coco.tscn") as PackedScene
	)
	var embedded_source_path := "%s/embedded_catalog.tres" % _directory
	_expect(
		bool(embedded_created.get("success", false))
			and ResourceSaver.save(embedded_catalog, embedded_source_path) == OK,
		"embedded catalog fixture saves"
	)
	var reloaded_embedded_catalog := ResourceLoader.load(
		embedded_source_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as CatalogScript
	var embedded_definition: StuffDefinition = (
		reloaded_embedded_catalog.definitions[0]
		if reloaded_embedded_catalog != null and not reloaded_embedded_catalog.definitions.is_empty()
		else null
	)
	_expect(
		embedded_definition != null and "::" in embedded_definition.resource_path,
		"reloaded inline definitions expose a subresource locator"
	)
	var embedded_save_result: Dictionary = authoring.save_catalog(
		reloaded_embedded_catalog,
		"%s/embedded_definitions" % _directory
	)
	_expect(
		bool(embedded_save_result.get("success", false)),
		"catalog save promotes inline definitions to standalone resources"
	)
	_expect(
		embedded_definition != null
			and embedded_definition.resource_path.ends_with("/embedded_tree.tres")
			and "::" not in embedded_definition.resource_path,
		"promoted definitions receive a writable standalone path"
	)
	var promoted_text := FileAccess.get_file_as_string(embedded_definition.resource_path)
	_expect(
		not "embedded_catalog.tres::" in promoted_text,
		"promoted definitions do not retain dependencies on their old catalog subresources"
	)

	var level := LevelResource.new()
	level.display_name = "Catalog Reference Test"
	level.terrain_content_version = 2
	var placement := StuffPlacementData.new()
	placement.configure(&"new_tree_1", Vector3i.ZERO, definition, 0)
	level.stuff_placements.append(placement)
	var level_directory := "%s/levels" % _directory
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(level_directory))
	var level_path := "%s/reference_level.tres" % level_directory
	_expect(ResourceSaver.save(level, level_path) == OK, "reference fixture saves")
	var references := authoring.find_level_references(definition, level_directory)
	_expect(references.size() == 1 and references[0] == level_path, "level references are discovered")
	var blocked_remove: Dictionary = authoring.remove_definition_if_unreferenced(
		catalog,
		definition,
		level_directory
	)
	_expect(not bool(blocked_remove.get("success", false)), "referenced definitions cannot leave the catalog")
	_expect(catalog.contains_definition(definition), "blocked removal preserves catalog membership")
	_cleanup()
	if _failures == 0:
		print("stuff_catalog_authoring_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("stuff_catalog_authoring_test: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _cleanup() -> void:
	_remove_directory(_directory)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := "%s/%s" % [path, entry]
		if directory.current_is_dir():
			_remove_directory(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
