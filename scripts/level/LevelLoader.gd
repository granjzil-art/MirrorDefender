## Runtime level loading entry point shared by debug and future production UI.
class_name LevelLoader
extends Node

const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Startup")
@export var initial_level: LevelResource

signal level_loaded(level_resource: LevelResource, source_path: String)
signal level_load_failed(source_path: String, reason: String)

var _grid: GridManager
var _tile_manager: TileManager
var _terrain_manager: TerrainManagerScript
var _stuff_manager: StuffManagerScript
var _current_level: LevelResource
var _current_source_path: String = ""

func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	terrain_manager: TerrainManagerScript = null,
	stuff_manager: StuffManagerScript = null
) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_terrain_manager = terrain_manager
	_stuff_manager = stuff_manager

func load_initial_level() -> bool:
	if initial_level == null:
		_report_failure("", "未配置初始关卡")
		return false
	return load_level(initial_level, initial_level.resource_path)

func load_level(level_resource: LevelResource, source_path: String = "") -> bool:
	if not feature_enabled:
		_report_failure(source_path, "LevelLoader 已关闭")
		return false
	if _grid == null or _tile_manager == null:
		_report_failure(source_path, "LevelLoader 尚未注入 GridManager 与 TileManager")
		return false
	if level_resource == null:
		_report_failure(source_path, "关卡资源为空")
		return false
	var resolved_path := source_path if not source_path.is_empty() else level_resource.resource_path
	var validation_errors := level_resource.validate_runtime()
	if not validation_errors.is_empty():
		_report_failure(resolved_path, "关卡校验失败：\n%s" % "\n".join(validation_errors))
		return false
	if not _tile_manager.feature_enabled:
		_report_failure(resolved_path, "TileManager 已关闭，无法装配关卡")
		return false
	if _terrain_manager != null and not _terrain_manager.feature_enabled:
		_report_failure(resolved_path, "TerrainManager 已关闭，无法装配关卡")
		return false
	if _stuff_manager != null and not _stuff_manager.feature_enabled:
		_report_failure(resolved_path, "StuffManager 已关闭，无法装配关卡")
		return false
	var previous_grid_shape := _grid.grid_shape
	var previous_cell_size := _grid.cell_size
	var previous_grid_size := _grid.grid_size
	var previous_terrain_level: LevelResource = null
	var previous_stuff_level: LevelResource = null
	if _terrain_manager != null:
		previous_terrain_level = _terrain_manager.get_level_resource()
	if _stuff_manager != null:
		previous_stuff_level = _stuff_manager.get_level_resource()
	_grid.apply_configuration(level_resource.grid_shape, level_resource.grid_cell_size, level_resource.grid_size)
	if _terrain_manager != null and not _terrain_manager.load_level(level_resource):
		_grid.apply_configuration(previous_grid_shape, previous_cell_size, previous_grid_size)
		_report_failure(resolved_path, "TerrainManager 拒绝加载关卡")
		return false
	if _stuff_manager != null and not _stuff_manager.load_level(level_resource):
		_grid.apply_configuration(previous_grid_shape, previous_cell_size, previous_grid_size)
		if _terrain_manager != null:
			if previous_terrain_level != null:
				_terrain_manager.load_level(previous_terrain_level)
			else:
				_terrain_manager.clear_level()
		_report_failure(resolved_path, "StuffManager 拒绝加载关卡")
		return false
	if not _tile_manager.load_level(level_resource):
		_grid.apply_configuration(previous_grid_shape, previous_cell_size, previous_grid_size)
		if _terrain_manager != null:
			if previous_terrain_level != null:
				_terrain_manager.load_level(previous_terrain_level)
			else:
				_terrain_manager.clear_level()
		if _stuff_manager != null:
			if previous_stuff_level != null:
				_stuff_manager.load_level(previous_stuff_level)
			else:
				_stuff_manager.clear_level()
		_report_failure(resolved_path, "TileManager 拒绝加载关卡")
		return false
	_current_level = level_resource
	_current_source_path = resolved_path
	level_loaded.emit(level_resource, resolved_path)
	return true

func load_level_path(path: String) -> bool:
	var normalized_path := path.strip_edges()
	if not normalized_path.begins_with("res://"):
		_report_failure(normalized_path, "关卡路径必须位于 res://")
		return false
	if not normalized_path.ends_with(".tres"):
		_report_failure(normalized_path, "关卡文件必须为 .tres")
		return false
	var resource: Resource = ResourceLoader.load(normalized_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if not resource is LevelResource:
		_report_failure(normalized_path, "所选资源不是 LevelResource")
		return false
	return load_level(resource, normalized_path)

func get_current_level() -> LevelResource:
	return _current_level


func get_current_source_path() -> String:
	return _current_source_path


## Releases the currently loaded resource graph. Preview owners use this before
## a battle scene is created so unselected levels can leave the resource cache.
func clear_level() -> void:
	if _terrain_manager != null:
		_terrain_manager.clear_level()
	if _stuff_manager != null:
		_stuff_manager.clear_level()
	if _tile_manager != null:
		_tile_manager.clear_level()
	_current_level = null
	_current_source_path = ""


## Recreates the current level resource before loading it so every runtime
## subsystem receives a fresh level_loaded transaction.
func reload_current_level() -> bool:
	if _current_level == null:
		_report_failure(_current_source_path, "当前没有可重载的关卡")
		return false
	var path := _current_source_path.strip_edges()
	if path.begins_with("res://") and path.ends_with(".tres"):
		return load_level_path(path)
	var duplicated := _current_level.duplicate(true) as LevelResource
	if duplicated == null:
		_report_failure(path, "当前关卡无法深度复制")
		return false
	return load_level(duplicated, path)

func _report_failure(source_path: String, reason: String) -> void:
	level_load_failed.emit(source_path, reason)
