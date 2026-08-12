## Formal slow, fast-forward, and pause controls for GameTimeController.
class_name TimeControlPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Optional Icons")
@export var tactical_slow_icon: Texture2D
@export var fast_icon: Texture2D
@export var pause_icon: Texture2D

@export_group("Button Colors")
@export var speed_1x_color: Color = Color("b9e8c2")
@export var speed_2x_color: Color = Color("ffd09a")
@export var speed_4x_color: Color = Color("f6aaa6")
@export var tactical_slow_color: Color = Color("d8c4f0")
@export var pause_color: Color = Color("d2d5da")
@export var button_text_color: Color = Color("26313a")

@onready var tactical_slow_button: Button = $Controls/TacticalSlowButton
@onready var fast_button: Button = $Controls/FastButton
@onready var pause_button: Button = $Controls/PauseButton
@onready var scale_label: Label = $Controls/ScaleLabel

var _time_controller: GameTimeController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = feature_enabled
	tactical_slow_button.pressed.connect(_on_slow_pressed)
	fast_button.pressed.connect(_on_fast_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	_apply_icons()
	_refresh()


func configure(time_controller: GameTimeController) -> void:
	_disconnect_controller()
	_time_controller = time_controller
	if _time_controller != null:
		_time_controller.tactical_slow_enabled_changed.connect(_on_slow_changed)
		_time_controller.playback_scale_changed.connect(_on_playback_scale_changed)
		_time_controller.fast_enabled_changed.connect(_on_fast_changed)
		_time_controller.paused_changed.connect(_on_paused_changed)
		_time_controller.time_scale_changed.connect(_on_scale_changed)
	_refresh()


func _on_slow_pressed() -> void:
	if feature_enabled and _time_controller != null:
		_time_controller.set_tactical_slow_enabled(tactical_slow_button.button_pressed)


func _on_fast_pressed() -> void:
	if feature_enabled and _time_controller != null:
		_time_controller.cycle_playback_scale()


func _on_pause_pressed() -> void:
	if feature_enabled and _time_controller != null:
		_time_controller.set_paused(not _time_controller.is_paused())


func _on_slow_changed(_enabled: bool) -> void:
	_refresh()


func _on_fast_changed(_enabled: bool) -> void:
	_refresh()


func _on_playback_scale_changed(_scale: float) -> void:
	_refresh()


func _on_paused_changed(_paused: bool) -> void:
	_refresh()


func _on_scale_changed(_scale: float) -> void:
	_refresh()


func _refresh() -> void:
	if tactical_slow_button == null:
		return
	var slow_enabled := _time_controller != null and _time_controller.tactical_slow_enabled
	var paused := _time_controller != null and _time_controller.is_paused()
	var scale := _time_controller.get_effective_scale() if _time_controller != null else 1.0
	var playback_scale := _time_controller.get_playback_scale() if _time_controller != null else 1.0
	tactical_slow_button.set_pressed_no_signal(slow_enabled)
	tactical_slow_button.text = "慢放 开" if slow_enabled else "慢放 关"
	fast_button.text = "%dx" % roundi(playback_scale)
	pause_button.text = "继续" if paused else "暂停"
	scale_label.text = "当前 %.1fx" % scale
	_apply_button_palette(tactical_slow_button, tactical_slow_color)
	_apply_button_palette(pause_button, pause_color)
	_apply_button_palette(fast_button, _get_speed_color(playback_scale))


func _get_speed_color(scale: float) -> Color:
	if scale >= 4.0 or is_equal_approx(scale, 4.0):
		return speed_4x_color
	if scale >= 2.0 or is_equal_approx(scale, 2.0):
		return speed_2x_color
	return speed_1x_color


func _apply_button_palette(button: Button, color: Color) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _make_button_style(color))
	button.add_theme_stylebox_override("hover", _make_button_style(color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _make_button_style(color.darkened(0.08)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color_name, button_text_color)


func _make_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.darkened(0.24)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _apply_icons() -> void:
	tactical_slow_button.icon = tactical_slow_icon
	fast_button.icon = fast_icon
	pause_button.icon = pause_icon


func _disconnect_controller() -> void:
	if _time_controller == null:
		return
	if _time_controller.tactical_slow_enabled_changed.is_connected(_on_slow_changed):
		_time_controller.tactical_slow_enabled_changed.disconnect(_on_slow_changed)
	if _time_controller.playback_scale_changed.is_connected(_on_playback_scale_changed):
		_time_controller.playback_scale_changed.disconnect(_on_playback_scale_changed)
	if _time_controller.fast_enabled_changed.is_connected(_on_fast_changed):
		_time_controller.fast_enabled_changed.disconnect(_on_fast_changed)
	if _time_controller.paused_changed.is_connected(_on_paused_changed):
		_time_controller.paused_changed.disconnect(_on_paused_changed)
	if _time_controller.time_scale_changed.is_connected(_on_scale_changed):
		_time_controller.time_scale_changed.disconnect(_on_scale_changed)
