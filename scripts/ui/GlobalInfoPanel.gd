## Signal-driven icon summary for health, waves, independent mirrors, and buildings.
class_name GlobalInfoPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@onready var health_label: Label = $StatsGrid/HealthStat/Value
@onready var wave_label: Label = $StatsGrid/WaveStat/Value
@onready var copy_mirror_label: Label = $StatsGrid/CopyMirrorStat/Value
@onready var reflect_mirror_label: Label = $StatsGrid/ReflectMirrorStat/Value
@onready var building_label: Label = $StatsGrid/BuildingStat/Value

var _resource_manager: ResourceManager
var _wave_manager: WaveManager
var _base_core: BaseCore
var _base_current: float = 0.0
var _current_wave: int = 0
var _total_waves: int = 0
var _building_count: int = 0
var _building_limit: int = 0
var _copy_mirror_count: int = 0
var _copy_mirror_limit: int = 0
var _reflect_mirror_count: int = 0
var _reflect_mirror_limit: int = 0


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
		_copy_mirror_count = _resource_manager.get_copy_mirror_count()
		_copy_mirror_limit = _resource_manager.copy_mirror_cap
		_reflect_mirror_count = _resource_manager.get_reflect_mirror_count()
		_reflect_mirror_limit = _resource_manager.reflect_mirror_cap
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_wave_state_changed)
		_current_wave = _wave_manager.get_current_wave_number()
		_total_waves = _wave_manager.get_total_wave_count()
	if _base_core != null:
		_base_core.health_changed.connect(_on_health_changed)
		_base_current = _base_core.current_hp
	_refresh_labels()


func get_summary_text() -> String:
	return "\n".join([
		health_label.text if health_label != null else "",
		wave_label.text if wave_label != null else "",
		copy_mirror_label.text if copy_mirror_label != null else "",
		reflect_mirror_label.text if reflect_mirror_label != null else "",
		building_label.text if building_label != null else "",
	])


func _on_limits_changed(
	building_count: int,
	building_limit: int,
	copy_mirror_count: int,
	copy_mirror_limit: int,
	reflect_mirror_count: int,
	reflect_mirror_limit: int
) -> void:
	_building_count = building_count
	_building_limit = building_limit
	_copy_mirror_count = copy_mirror_count
	_copy_mirror_limit = copy_mirror_limit
	_reflect_mirror_count = reflect_mirror_count
	_reflect_mirror_limit = reflect_mirror_limit
	_refresh_labels()


func _on_health_changed(current_hp: float, _maximum_hp: float) -> void:
	_base_current = current_hp
	_refresh_labels()


func _on_wave_state_changed(_state: WaveManager.State, current_wave: int, total_waves: int, _active_enemy_count: int) -> void:
	_current_wave = current_wave
	_total_waves = total_waves
	_refresh_labels()


func _refresh_labels() -> void:
	if health_label == null:
		return
	health_label.text = "%d" % ceili(_base_current)
	wave_label.text = "%d/%d" % [_current_wave, _total_waves]
	copy_mirror_label.text = "%d/%d" % [_copy_mirror_count, _copy_mirror_limit]
	reflect_mirror_label.text = "%d/%d" % [_reflect_mirror_count, _reflect_mirror_limit]
	building_label.text = "%d/%d" % [_building_count, _building_limit]


func _disconnect_sources() -> void:
	if _resource_manager != null and _resource_manager.limits_changed.is_connected(_on_limits_changed):
		_resource_manager.limits_changed.disconnect(_on_limits_changed)
	if _wave_manager != null and _wave_manager.state_changed.is_connected(_on_wave_state_changed):
		_wave_manager.state_changed.disconnect(_on_wave_state_changed)
	if _base_core != null and _base_core.health_changed.is_connected(_on_health_changed):
		_base_core.health_changed.disconnect(_on_health_changed)
