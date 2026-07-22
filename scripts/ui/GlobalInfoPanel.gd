## Signal-driven read-only summary for the current level and runtime counts.
class_name GlobalInfoPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@onready var level_label: Label = $GlassPanel/Content/LevelName
@onready var base_label: Label = $GlassPanel/Content/BaseHealth
@onready var enemy_label: Label = $GlassPanel/Content/EnemyCount
@onready var limits_label: Label = $GlassPanel/Content/Limits

var _resource_manager: ResourceManager
var _wave_manager: WaveManager
var _base_core: BaseCore
var _level_name: String = "未加载关卡"
var _base_current: float = 0.0
var _base_maximum: float = 0.0
var _active_enemies: int = 0
var _building_count: int = 0
var _building_limit: int = 0
var _mirror_count: int = 0
var _mirror_limit: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = feature_enabled
	_refresh_labels()


func configure(resource_manager: ResourceManager, wave_manager: WaveManager, base_core: BaseCore) -> void:
	_disconnect_sources()
	_resource_manager = resource_manager
	_wave_manager = wave_manager
	_base_core = base_core
	if _resource_manager != null:
		_resource_manager.limits_changed.connect(_on_limits_changed)
		_building_count = _resource_manager.get_building_count()
		_building_limit = _resource_manager.building_cap
		_mirror_count = _resource_manager.get_mirror_count()
		_mirror_limit = _resource_manager.mirror_cap
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_wave_state_changed)
		_active_enemies = _wave_manager.get_active_enemy_count()
	if _base_core != null:
		_base_core.health_changed.connect(_on_health_changed)
		_base_current = _base_core.current_hp
		_base_maximum = _base_core.max_hp
	_refresh_labels()


func set_level_context(level: LevelResource, source_path: String = "") -> void:
	_level_name = _resolve_level_name(level, source_path)
	_refresh_labels()


func get_summary_text() -> String:
	return "\n".join([
		level_label.text if level_label != null else "",
		base_label.text if base_label != null else "",
		enemy_label.text if enemy_label != null else "",
		limits_label.text if limits_label != null else "",
	])


func _on_limits_changed(building_count: int, building_limit: int, mirror_count: int, mirror_limit: int) -> void:
	_building_count = building_count
	_building_limit = building_limit
	_mirror_count = mirror_count
	_mirror_limit = mirror_limit
	_refresh_labels()


func _on_health_changed(current_hp: float, maximum_hp: float) -> void:
	_base_current = current_hp
	_base_maximum = maximum_hp
	_refresh_labels()


func _on_wave_state_changed(_state: WaveManager.State, _current_wave: int, _total_waves: int, active_enemy_count: int) -> void:
	_active_enemies = active_enemy_count
	_refresh_labels()


func _refresh_labels() -> void:
	if level_label == null:
		return
	level_label.text = "关卡 · %s" % _level_name
	base_label.text = "据点 %d / %d HP" % [ceili(_base_current), ceili(_base_maximum)]
	enemy_label.text = "场上敌人 · %d" % _active_enemies
	limits_label.text = "建筑 %d/%d · 镜子 %d/%d" % [
		_building_count,
		_building_limit,
		_mirror_count,
		_mirror_limit,
	]


func _resolve_level_name(level: LevelResource, source_path: String) -> String:
	if level != null and not level.display_name.strip_edges().is_empty():
		return level.display_name.strip_edges()
	var path := source_path.strip_edges()
	if path.is_empty() and level != null:
		path = level.resource_path
	if path.begins_with("res://"):
		return path.get_file().get_basename()
	return "未命名关卡"


func _disconnect_sources() -> void:
	if _resource_manager != null and _resource_manager.limits_changed.is_connected(_on_limits_changed):
		_resource_manager.limits_changed.disconnect(_on_limits_changed)
	if _wave_manager != null and _wave_manager.state_changed.is_connected(_on_wave_state_changed):
		_wave_manager.state_changed.disconnect(_on_wave_state_changed)
	if _base_core != null and _base_core.health_changed.is_connected(_on_health_changed):
		_base_core.health_changed.disconnect(_on_health_changed)
