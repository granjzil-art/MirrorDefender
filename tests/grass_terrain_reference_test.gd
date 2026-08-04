extends SceneTree

const FORMAL_GRASS_PATH := "res://resources/terrains/Grass.tres"
const LEVEL_DIRECTORY := "res://resources/levels"
const LevelResourceScript := preload("res://scripts/level/LevelResource.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var new_level := LevelResourceScript.new()
	_expect(
		_is_formal_grass(new_level.default_terrain),
		"new level default terrain is formal Grass.tres"
	)
	var level_files := DirAccess.get_files_at(LEVEL_DIRECTORY)
	level_files.sort()
	for file_name in level_files:
		if file_name.get_extension().to_lower() != "tres":
			continue
		_audit_level("%s/%s" % [LEVEL_DIRECTORY, file_name])
	if _failures == 0:
		print("grass_terrain_reference_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error(
			"grass_terrain_reference_test: %d/%d checks failed"
			% [_failures, _checks]
		)
		quit(1)


func _audit_level(path: String) -> void:
	var level := ResourceLoader.load(
		path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as LevelResourceScript
	_expect(level != null, "%s loads as LevelResource" % path.get_file())
	if level == null:
		return
	var snapshot := level.get_effective_content_snapshot()
	_expect_grass_is_formal(snapshot["default_terrain"], "%s runtime default" % path.get_file())
	for index in range(snapshot["grid_cells"].size()):
		var runtime_cell = snapshot["grid_cells"][index]
		if runtime_cell != null:
			_expect_grass_is_formal(
				runtime_cell.terrain,
				"%s runtime Grid %d" % [path.get_file(), index]
			)
	for index in range(snapshot["ramp_placements"].size()):
		var runtime_ramp = snapshot["ramp_placements"][index]
		if runtime_ramp != null:
			_expect_grass_is_formal(
				runtime_ramp.terrain_override,
				"%s runtime ramp %d" % [path.get_file(), index]
			)


func _expect_grass_is_formal(terrain: TerrainDefinitionScript, label: String) -> void:
	if terrain == null or not terrain.is_grass():
		return
	_expect(_is_formal_grass(terrain), "%s uses formal Grass.tres" % label)


func _is_formal_grass(terrain: TerrainDefinitionScript) -> bool:
	return terrain != null and terrain.resource_path == FORMAL_GRASS_PATH


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)
