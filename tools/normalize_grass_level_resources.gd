@tool
## One-shot/reusable content migration for canonical level resources.
##
## Every TerrainDefinition identified as `grass` is rewritten to the formal
## res://resources/terrains/Grass.tres resource before the level is saved.
extends SceneTree

const LEVEL_DIRECTORY := "res://resources/levels"
const LevelResourceScript := preload("res://scripts/level/LevelResource.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var migrated_files := 0
	var migrated_references := 0
	var failures: Array[String] = []
	var file_names := DirAccess.get_files_at(LEVEL_DIRECTORY)
	file_names.sort()
	for file_name in file_names:
		if file_name.get_extension().to_lower() != "tres":
			continue
		var path := "%s/%s" % [LEVEL_DIRECTORY, file_name]
		var level := ResourceLoader.load(
			path,
			"",
			ResourceLoader.CACHE_MODE_REPLACE_DEEP
		) as LevelResourceScript
		if level == null:
			failures.append("Failed to load %s" % path)
			continue
		if not level.uses_canonical_content():
			continue
		var changed_references := level.normalize_grass_references_in_place()
		if changed_references == 0:
			continue
		var save_error := ResourceSaver.save(level, path)
		if save_error != OK:
			failures.append("Failed to save %s: %s" % [path, error_string(save_error)])
			continue
		migrated_files += 1
		migrated_references += changed_references
		print("Normalized %d grass references in %s" % [changed_references, path])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print(
		"Grass migration complete: %d references in %d level files"
		% [migrated_references, migrated_files]
	)
	quit(0)
