## Transactional runtime combat-data authoring. Disk .tres files are the only
## persistent source; working Resources exist only for the running session.
class_name RuntimeCombatDataEditSession
extends Node

const ENEMY_DIRECTORY := "res://resources/enemies"

const BUILDING_PROPERTIES := [
	"affects_airborne",
	"prioritizes_airborne",
	"base_damage",
	"targeting_range",
	"attack_range",
	"attacks_per_second",
	"laser_dps",
	"target_priority",
	"projectile_direction_count",
	"laser_beam_width",
	"laser_propagation_speed",
	"laser_slow_multiplier",
	"laser_slow_duration",
	"laser_burst_interval",
	"laser_burst_radius",
	"laser_freeze_duration",
	"max_durability",
	"regeneration_delay",
	"regeneration_per_second",
	"damage_reflection_ratio",
	"projectile_fire_mode",
	"projectile_speed",
	"projectile_penetration_count",
	"projectile_is_missile",
	"missile_explosion_radius",
	"missile_orbit_duration",
	"missile_orbit_radius_x",
	"missile_orbit_radius_z",
	"missile_orbit_vertical_amplitude",
	"missile_homing_turn_speed_degrees",
	"missile_speed_variation_ratio",
	"missile_speed_variation_frequency",
	"pulse_laser_reflect_max",
	"pulse_laser_width",
	"pulse_laser_emission_energy",
	"pulse_laser_fade_in_time",
	"pulse_laser_hold_time",
	"pulse_laser_fade_out_time",
]

const ENEMY_PROPERTIES := [
	"max_hp",
	"move_speed",
	"armor",
	"reward",
	"hit_radius",
	"is_airborne",
	"flight_height",
	"is_elite",
	"movement_active_duration",
	"movement_pause_duration",
	"armor_aura_radius",
	"armor_aura_bonus",
	"reflection_pattern",
	"reflection_side_length",
	"reflection_height",
	"reflection_max_durability",
	"attack_damage",
	"attacks_per_second",
	"attack_range",
	"projectile_speed",
	"hit_particle_color",
	"hit_particle_brightness",
	"hit_particle_size",
	"hit_particle_count",
]

signal dirty_changed(dirty: bool)
signal catalogs_changed
signal building_value_changed(kind: int, level: int, property: StringName, value: Variant)
signal enemy_value_changed(path: String, property: StringName, value: Variant)
signal session_saved(paths: PackedStringArray)
signal session_discarded

var _building_manager: BuildingManager
var _wave_manager: WaveManager
var _level_loader: LevelLoader
var _building_working: Dictionary = {}
var _enemy_working: Dictionary = {}
var _baselines: Dictionary = {}
var _building_path_by_kind: Dictionary = {}
var _enemy_path_by_id: Dictionary = {}
var _dirty_types: Dictionary = {}
var _dirty_building_levels: Dictionary = {}
var _active: bool = false


func configure(
	building_manager: BuildingManager,
	wave_manager: WaveManager,
	level_loader: LevelLoader
) -> bool:
	_building_manager = building_manager
	_wave_manager = wave_manager
	_level_loader = level_loader
	return begin()


func begin() -> bool:
	if _active:
		return true
	if _building_manager == null or _wave_manager == null or _level_loader == null:
		return false
	_building_working.clear()
	_enemy_working.clear()
	_baselines.clear()
	_building_path_by_kind.clear()
	_enemy_path_by_id.clear()
	for source in _building_manager.get_all_definitions(false):
		_register_building_source(source)
	_discover_enemy_directory()
	_discover_level_enemies()
	_active = not _building_working.is_empty()
	if not _active:
		return false
	_bind_working_data()
	catalogs_changed.emit()
	return true


func is_active() -> bool:
	return _active


func is_dirty() -> bool:
	return not _dirty_types.is_empty()


func can_save_permanently() -> bool:
	return OS.has_feature("editor")


func get_building_definitions() -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	if _building_manager == null:
		return result
	for source in _building_manager.get_all_definitions(false):
		if source == null:
			continue
		var path := source.resource_path
		var definition := _building_working.get(path) as BuildingDefinition
		if definition != null:
			result.append(definition)
	return result


func get_enemy_definitions() -> Array[EnemyDefinition]:
	var result: Array[EnemyDefinition] = []
	for raw_definition in _enemy_working.values():
		var definition := raw_definition as EnemyDefinition
		if definition != null:
			result.append(definition)
	result.sort_custom(func(a: EnemyDefinition, b: EnemyDefinition) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return result


func get_current_paths() -> Array[PathDefinition]:
	var result: Array[PathDefinition] = []
	if _level_loader == null:
		return result
	var level := _level_loader.get_current_level()
	if level == null:
		return result
	for path in level.paths:
		if path != null:
			result.append(path)
	return result


func resolve_enemy_definition(source: EnemyDefinition) -> EnemyDefinition:
	if source == null:
		return null
	if not source.resource_path.is_empty() and _enemy_working.has(source.resource_path):
		return _enemy_working[source.resource_path] as EnemyDefinition
	var path: String = _enemy_path_by_id.get(source.enemy_id, "")
	return _enemy_working.get(path, source) as EnemyDefinition


func set_building_value(
	kind: int,
	building_level: int,
	property: StringName,
	value: Variant
) -> Dictionary:
	if not _active or not BUILDING_PROPERTIES.has(String(property)):
		return _result(false, "该建筑参数不允许在运行时编辑")
	var path: String = _building_path_by_kind.get(kind, "")
	var definition := _building_working.get(path) as BuildingDefinition
	if definition == null:
		return _result(false, "找不到建筑工作副本")
	var level_data := definition.get_level_stats(building_level)
	if level_data == null:
		return _result(false, "建筑等级数据不存在")
	var previous: Variant = level_data.get(property)
	level_data.set(property, value)
	var errors := level_data.validate_configuration()
	if not errors.is_empty():
		level_data.set(property, previous)
		return _result(false, "参数校验失败：%s" % "；".join(errors))
	level_data.emit_changed()
	definition.emit_changed()
	_mark_dirty(path, "building", building_level)
	var rebuilt := _building_manager.rebuild_runtime_buildings(kind, building_level)
	building_value_changed.emit(kind, building_level, property, value)
	return _result(true, "参数已应用，重建 %d 个建筑" % rebuilt)


func set_enemy_value(path: String, property: StringName, value: Variant) -> Dictionary:
	if not _active or not ENEMY_PROPERTIES.has(String(property)):
		return _result(false, "该敌人参数不允许在运行时编辑")
	var definition := _enemy_working.get(path) as EnemyDefinition
	if definition == null:
		return _result(false, "找不到敌人工作副本")
	var previous: Variant = definition.get(property)
	definition.set(property, value)
	var errors := definition.validate_configuration()
	if not errors.is_empty():
		definition.set(property, previous)
		return _result(false, "参数校验失败：%s" % "；".join(errors))
	definition.emit_changed()
	_mark_dirty(path, "enemy")
	enemy_value_changed.emit(path, property, value)
	return _result(true, "参数已应用；已生成敌人保持原值")


func save() -> Dictionary:
	if not is_dirty():
		return _result(true, "没有需要保存的修改")
	if not can_save_permanently():
		return _result(false, "仅项目源码的编辑器运行模式可以写回 res:// .tres")
	var dirty_paths := PackedStringArray(_dirty_types.keys())
	var changed_levels := _dirty_building_levels.duplicate(true)
	for path in dirty_paths:
		var validation := _validate_working_resource(path)
		if not validation.is_empty():
			return _result(false, "%s 校验失败：%s" % [path, "；".join(validation)])
	var saved_paths := PackedStringArray()
	for path in dirty_paths:
		var working := _get_working_resource(path)
		var save_error := ResourceSaver.save(working, path)
		if save_error != OK:
			_rollback_saved_paths(saved_paths)
			return _result(false, "保存 %s 失败，错误码 %d；已回滚先前文件" % [path, save_error])
		saved_paths.append(path)
	if not _reload_paths_from_disk(dirty_paths):
		return _result(false, "文件已保存，但重新读取工作副本失败")
	_dirty_types.clear()
	_dirty_building_levels.clear()
	_bind_working_data()
	_rebuild_changed_buildings(changed_levels)
	dirty_changed.emit(false)
	catalogs_changed.emit()
	session_saved.emit(saved_paths)
	return _result(true, "已永久保存 %d 个 .tres" % saved_paths.size(), {"paths": saved_paths})


func discard() -> Dictionary:
	if not is_dirty():
		return _result(true, "没有需要放弃的修改")
	var dirty_paths := PackedStringArray(_dirty_types.keys())
	var changed_levels := _dirty_building_levels.duplicate(true)
	if not _reload_paths_from_disk(dirty_paths):
		return _result(false, "重新读取 .tres 失败，未放弃当前工作副本")
	_dirty_types.clear()
	_dirty_building_levels.clear()
	_bind_working_data()
	_rebuild_changed_buildings(changed_levels)
	dirty_changed.emit(false)
	catalogs_changed.emit()
	session_discarded.emit()
	return _result(true, "已放弃修改并重新读取 .tres")


func refresh_level_catalog() -> void:
	_discover_level_enemies()
	_bind_working_data()
	catalogs_changed.emit()


func _register_building_source(source: BuildingDefinition) -> void:
	if source == null or source.resource_path.is_empty():
		return
	var path := source.resource_path
	var working := _load_fresh(path) as BuildingDefinition
	if working == null:
		working = source.duplicate(true) as BuildingDefinition
	if working == null:
		return
	_building_working[path] = working
	_baselines[path] = working.duplicate(true)
	_building_path_by_kind[working.kind] = path


func _register_enemy_source(source: EnemyDefinition) -> void:
	if source == null or source.resource_path.is_empty():
		return
	var path := source.resource_path
	if _enemy_working.has(path):
		return
	var working := _load_fresh(path) as EnemyDefinition
	if working == null:
		working = source.duplicate(true) as EnemyDefinition
	if working == null:
		return
	_enemy_working[path] = working
	_baselines[path] = working.duplicate(true)
	_enemy_path_by_id[working.enemy_id] = path


func _discover_enemy_directory() -> void:
	var directory := DirAccess.open(ENEMY_DIRECTORY)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			var path := "%s/%s" % [ENEMY_DIRECTORY, file_name]
			var source := _load_fresh(path) as EnemyDefinition
			_register_enemy_source(source)
		file_name = directory.get_next()
	directory.list_dir_end()


func _discover_level_enemies() -> void:
	if _level_loader == null:
		return
	var level := _level_loader.get_current_level()
	if level == null:
		return
	for wave in level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group != null:
				_register_enemy_source(group.enemy)


func _bind_working_data() -> void:
	if _building_manager != null:
		var overrides: Dictionary = {}
		for raw_kind in _building_path_by_kind:
			var path: String = _building_path_by_kind[raw_kind]
			var definition := _building_working.get(path) as BuildingDefinition
			if definition != null:
				overrides[int(raw_kind)] = definition
		_building_manager.set_runtime_definition_overrides(overrides)
	if _wave_manager != null:
		_wave_manager.set_enemy_definition_resolver(Callable(self, "resolve_enemy_definition"))


func _mark_dirty(path: String, type: String, building_level: int = -1) -> void:
	var was_dirty := is_dirty()
	_dirty_types[path] = type
	if type == "building" and building_level > 0:
		var levels: Dictionary = _dirty_building_levels.get(path, {})
		levels[building_level] = true
		_dirty_building_levels[path] = levels
	if not was_dirty:
		dirty_changed.emit(true)


func _validate_working_resource(path: String) -> Array[String]:
	var building := _building_working.get(path) as BuildingDefinition
	if building != null:
		return building.validate_configuration()
	var enemy := _enemy_working.get(path) as EnemyDefinition
	if enemy != null:
		return enemy.validate_configuration()
	return ["工作副本不存在"]


func _get_working_resource(path: String) -> Resource:
	if _building_working.has(path):
		return _building_working[path] as Resource
	return _enemy_working.get(path) as Resource


func _reload_paths_from_disk(paths: PackedStringArray) -> bool:
	var replacements: Dictionary = {}
	for path in paths:
		var resource := _load_fresh(path)
		if resource == null:
			return false
		replacements[path] = resource
	for path in replacements:
		var resource: Resource = replacements[path]
		if resource is BuildingDefinition:
			_building_working[path] = resource
			_building_path_by_kind[(resource as BuildingDefinition).kind] = path
		elif resource is EnemyDefinition:
			_enemy_working[path] = resource
			_enemy_path_by_id[(resource as EnemyDefinition).enemy_id] = path
		else:
			return false
		_baselines[path] = resource.duplicate(true)
	return true


func _rollback_saved_paths(paths: PackedStringArray) -> void:
	for path in paths:
		var baseline := _baselines.get(path) as Resource
		if baseline != null:
			ResourceSaver.save(baseline, path)


func _rebuild_changed_buildings(changed_levels: Dictionary) -> void:
	if _building_manager == null:
		return
	for path in changed_levels:
		var definition := _building_working.get(path) as BuildingDefinition
		if definition == null:
			continue
		var levels: Dictionary = changed_levels[path]
		for raw_level in levels:
			_building_manager.rebuild_runtime_buildings(definition.kind, int(raw_level))


func _load_fresh(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _result(success: bool, message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": success, "message": message}
	result.merge(extra, true)
	return result
