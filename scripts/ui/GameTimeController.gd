## Resolves normal, fast, tactical-slow, and pause requests into one scale.
class_name GameTimeController
extends Node

const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")

@export_group("Tactical Slow")
@export var tactical_slow_enabled: bool = true
@export_range(0.01, 1.0, 0.01) var tactical_slow_scale: float = 0.1

@export_group("Fast Forward")
@export_range(1.0, 8.0, 0.1, "or_greater") var fast_scale: float = 2.0

signal time_scale_changed(scale: float)
signal tactical_slow_enabled_changed(enabled: bool)
signal fast_enabled_changed(enabled: bool)
signal paused_changed(paused: bool)

var _interaction: RuntimeInteractionControllerScript
var _building_manager: BuildingManager
var _mirror_manager: MirrorManager
var _fast_enabled: bool = false
var _paused: bool = false
var _applied_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_scale()


func _exit_tree() -> void:
	if is_equal_approx(Engine.time_scale, _applied_scale):
		Engine.time_scale = 1.0


func configure(
	interaction: RuntimeInteractionControllerScript,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager
) -> void:
	_disconnect_sources()
	_interaction = interaction
	_building_manager = building_manager
	_mirror_manager = mirror_manager
	if _interaction != null:
		_interaction.mode_changed.connect(_on_context_changed)
	if _building_manager != null:
		_building_manager.building_selected.connect(_on_building_selected)
	if _mirror_manager != null:
		_mirror_manager.mirror_selected.connect(_on_mirror_selected)
	_refresh_scale()


func set_tactical_slow_enabled(enabled: bool) -> void:
	if tactical_slow_enabled == enabled:
		return
	tactical_slow_enabled = enabled
	tactical_slow_enabled_changed.emit(enabled)
	_refresh_scale()


func toggle_tactical_slow_enabled() -> void:
	set_tactical_slow_enabled(not tactical_slow_enabled)


func set_fast_enabled(enabled: bool) -> void:
	if _fast_enabled == enabled:
		return
	_fast_enabled = enabled
	fast_enabled_changed.emit(enabled)
	_refresh_scale()


func is_fast_enabled() -> bool:
	return _fast_enabled


func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	paused_changed.emit(paused)
	_refresh_scale()


func is_paused() -> bool:
	return _paused


func get_effective_scale() -> float:
	return _applied_scale


func has_tactical_context() -> bool:
	if _interaction != null and not _interaction.is_select_mode():
		return true
	if _building_manager != null and _building_manager.get_selected_building() != null:
		return true
	return _mirror_manager != null and _mirror_manager.get_selected_mirror() != null


func _refresh_scale() -> void:
	var resolved := 1.0
	if _paused:
		resolved = 0.0
	elif tactical_slow_enabled and has_tactical_context():
		resolved = clampf(tactical_slow_scale, 0.01, 1.0)
	elif _fast_enabled:
		resolved = maxf(1.0, fast_scale)
	if is_equal_approx(_applied_scale, resolved) and is_equal_approx(Engine.time_scale, resolved):
		return
	_applied_scale = resolved
	Engine.time_scale = resolved
	time_scale_changed.emit(resolved)


func _on_context_changed(_value: Variant = null) -> void:
	_refresh_scale()


func _on_building_selected(_building: Building) -> void:
	_refresh_scale()


func _on_mirror_selected(_mirror: CopyMirror) -> void:
	_refresh_scale()


func _disconnect_sources() -> void:
	if _interaction != null and _interaction.mode_changed.is_connected(_on_context_changed):
		_interaction.mode_changed.disconnect(_on_context_changed)
	if _building_manager != null and _building_manager.building_selected.is_connected(_on_building_selected):
		_building_manager.building_selected.disconnect(_on_building_selected)
	if _mirror_manager != null and _mirror_manager.mirror_selected.is_connected(_on_mirror_selected):
		_mirror_manager.mirror_selected.disconnect(_on_mirror_selected)
