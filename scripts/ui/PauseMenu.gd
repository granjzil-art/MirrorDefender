## Always-processing modal menu. Gameplay actions are emitted to the composition root.
class_name PauseMenu
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Persistence")
@export_file("*.cfg") var settings_path: String = "user://settings.cfg"
@export var apply_runtime_settings: bool = true

@export_group("Layout")
@export_range(180.0, 360.0, 1.0) var collapsed_height: float = 230.0
@export_range(320.0, 640.0, 1.0) var expanded_height: float = 410.0

@export_group("Optional Icons")
@export var settings_icon: Texture2D
@export var restart_icon: Texture2D
@export var exit_icon: Texture2D

signal restart_requested
signal exit_requested
signal settings_changed(settings: Dictionary)

@onready var settings_button: Button = $Shade/ModalPanel/Content/ActionButtons/SettingsButton
@onready var restart_button: Button = $Shade/ModalPanel/Content/ActionButtons/RestartButton
@onready var exit_button: Button = $Shade/ModalPanel/Content/ActionButtons/ExitButton
@onready var settings_panel: VBoxContainer = $Shade/ModalPanel/Content/SettingsPanel
@onready var volume_slider: HSlider = $Shade/ModalPanel/Content/SettingsPanel/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Shade/ModalPanel/Content/SettingsPanel/VolumeRow/VolumeValue
@onready var window_mode: OptionButton = $Shade/ModalPanel/Content/SettingsPanel/WindowRow/WindowMode
@onready var ui_scale_slider: HSlider = $Shade/ModalPanel/Content/SettingsPanel/ScaleRow/UiScaleSlider
@onready var ui_scale_value: Label = $Shade/ModalPanel/Content/SettingsPanel/ScaleRow/UiScaleValue
@onready var status_label: Label = $Shade/ModalPanel/Content/SettingsPanel/Status
@onready var modal_panel: PanelContainer = $Shade/ModalPanel

var _settings := RuntimeSettings.new()
var _root_window: Window
var _syncing_controls: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	settings_panel.visible = false
	_update_panel_height()
	window_mode.clear()
	window_mode.add_item("窗口", 0)
	window_mode.add_item("全屏", 1)
	settings_button.pressed.connect(_on_settings_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	volume_slider.value_changed.connect(_on_setting_control_changed)
	window_mode.item_selected.connect(_on_window_mode_changed)
	ui_scale_slider.value_changed.connect(_on_setting_control_changed)
	_apply_icons()


func configure(root_window: Window) -> void:
	_root_window = root_window
	var error := _settings.load_from_file(settings_path)
	_sync_controls_from_settings()
	if apply_runtime_settings:
		_settings.apply_to_runtime(_root_window)
	status_label.text = "" if error == OK else "设置读取失败：%s" % error_string(error)


func open_menu() -> void:
	if not feature_enabled:
		return
	visible = true


func close_menu() -> void:
	visible = false
	settings_panel.visible = false
	_update_panel_height()


func is_open() -> bool:
	return visible


func get_settings_snapshot() -> Dictionary:
	return _settings.to_dictionary()


func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible
	_update_panel_height()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()


func _on_window_mode_changed(_index: int) -> void:
	_on_setting_control_changed(0.0)


func _on_setting_control_changed(_value: float) -> void:
	if _syncing_controls:
		return
	_settings.set_values(volume_slider.value, window_mode.selected == 1, ui_scale_slider.value)
	var error := _settings.save_to_file(settings_path)
	if error == OK and apply_runtime_settings:
		_settings.apply_to_runtime(_root_window)
	status_label.text = "设置已保存" if error == OK else "设置保存失败：%s" % error_string(error)
	_update_value_labels()
	settings_changed.emit(_settings.to_dictionary())


func _sync_controls_from_settings() -> void:
	_syncing_controls = true
	volume_slider.set_value_no_signal(_settings.main_volume_percent)
	window_mode.select(1 if _settings.fullscreen else 0)
	ui_scale_slider.set_value_no_signal(_settings.ui_scale)
	_syncing_controls = false
	_update_value_labels()


func _update_value_labels() -> void:
	volume_value.text = "%d%%" % roundi(volume_slider.value)
	ui_scale_value.text = "%.2fx" % ui_scale_slider.value


func _apply_icons() -> void:
	settings_button.icon = settings_icon
	restart_button.icon = restart_icon
	exit_button.icon = exit_icon


func _update_panel_height() -> void:
	if modal_panel == null:
		return
	var height := expanded_height if settings_panel.visible else collapsed_height
	modal_panel.offset_top = -height * 0.5
	modal_panel.offset_bottom = height * 0.5
