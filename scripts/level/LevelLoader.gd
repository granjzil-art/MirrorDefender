## Runtime level loading entry point shared by debug and future production UI.
class_name LevelLoader
extends Node

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Startup")
@export var initial_level: LevelResource

signal level_loaded(level_resource: LevelResource, source_path: String)
signal level_load_failed(source_path: String, reason: String)

var _grid: GridManager
var _tile_manager: TileManager
var _current_level: LevelResource

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager

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
	_grid.apply_configuration(
		level_resource.grid_shape,
		level_resource.grid_cell_size,
		level_resource.grid_size
	)
	if not _tile_manager.load_level(level_resource):
		_report_failure(resolved_path, "TileManager 拒绝加载关卡")
		return false
	_current_level = level_resource
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
	var resource: Resource = ResourceLoader.load(
		normalized_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	if not resource is LevelResource:
		_report_failure(normalized_path, "所选资源不是 LevelResource")
		return false
	return load_level(resource, normalized_path)

func get_current_level() -> LevelResource:
	return _current_level

func _report_failure(source_path: String, reason: String) -> void:
	level_load_failed.emit(source_path, reason)
