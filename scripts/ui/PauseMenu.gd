## Always-processing modal menu. Gameplay actions are emitted to the composition root.
class_name PauseMenu
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Content")
@export var menu_title: String = "已暂停"
@export var restart_button_text: String = "重启关卡"
@export var exit_button_text: String = "退出当前关卡"
@export_multiline var result_text: String = ""
@export var show_settings_button: bool = true

@export_group("Persistence")
@export_file("*.cfg") var settings_path: String = "user://settings.cfg"
@export var apply_runtime_settings: bool = true

@export_group("Layout")
@export_range(180.0, 360.0, 1.0) var collapsed_height: float = 230.0
@export_range(320.0, 640.0, 1.0) var expanded_height: float = 500.0

@export_group("Optional Icons")
@export var settings_icon: Texture2D
@export var restart_icon: Texture2D
@export var exit_icon: Texture2D

signal restart_requested
signal exit_level_requested
signal settings_changed(settings: Dictionary)

@onready var title_label: Label = $Shade/ModalPanel/Content/Title
@onready var result_label: Label = $Shade/ModalPanel/Content/Result
@onready var settings_button: Button = $Shade/ModalPanel/Content/ActionButtons/SettingsButton
@onready var restart_button: Button = $Shade/ModalPanel/Content/ActionButtons/RestartButton
@onready var exit_button: Button = $Shade/ModalPanel/Content/ActionButtons/ExitButton
@onready var settings_panel: VBoxContainer = $Shade/ModalPanel/Content/SettingsPanel
@onready var volume_slider: HSlider = $Shade/ModalPanel/Content/SettingsPanel/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Shade/ModalPanel/Content/SettingsPanel/VolumeRow/VolumeValue
@onready var window_mode: OptionButton = $Shade/ModalPanel/Content/SettingsPanel/WindowRow/WindowMode
@onready var render_quality: OptionButton = $Shade/ModalPanel/Content/SettingsPanel/RenderQualityRow/RenderQuality
@onready var ui_scale_slider: HSlider = $Shade/ModalPanel/Content/SettingsPanel/ScaleRow/UiScaleSlider
@onready var ui_scale_value: Label = $Shade/ModalPanel/Content/SettingsPanel/ScaleRow/UiScaleValue
@onready var depth_of_field_toggle: CheckButton = $Shade/ModalPanel/Content/SettingsPanel/DepthOfFieldRow/DepthOfFieldToggle
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
	title_label.text = menu_title
	set_result_text(result_text)
	settings_button.visible = show_settings_button
	restart_button.text = restart_button_text
	exit_button.text = exit_button_text
	window_mode.clear()
	window_mode.add_item("窗口", 0)
	window_mode.add_item("全屏", 1)
	render_quality.clear()
	render_quality.add_item("性能（1080p 上限）", RuntimeSettings.RENDER_QUALITY_PERFORMANCE)
	render_quality.add_item("平衡（2K 上限，推荐）", RuntimeSettings.RENDER_QUALITY_BALANCED)
	render_quality.add_item("原生分辨率", RuntimeSettings.RENDER_QUALITY_NATIVE)
	settings_button.pressed.connect(_on_settings_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	volume_slider.value_changed.connect(_on_setting_control_changed)
	window_mode.item_selected.connect(_on_window_mode_changed)
	render_quality.item_selected.connect(_on_render_quality_changed)
	ui_scale_slider.value_changed.connect(_on_setting_control_changed)
	depth_of_field_toggle.toggled.connect(_on_depth_of_field_toggled)
	_apply_icons()


func configure(root_window: Window, shared_settings: RuntimeSettings = null) -> void:
	_root_window = root_window
	var error := OK
	if shared_settings != null:
		_settings = shared_settings
	else:
		error = _settings.load_from_file(settings_path)
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


func set_result_text(text: String) -> void:
	result_text = text
	if result_label == null:
		return
	result_label.text = result_text
	result_label.visible = not result_text.is_empty()


func get_runtime_settings() -> RuntimeSettings:
	return _settings


func sync_settings_controls() -> void:
	_sync_controls_from_settings()


func _on_settings_pressed() -> void:
	if not show_settings_button:
		return
	settings_panel.visible = not settings_panel.visible
	_update_panel_height()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_exit_pressed() -> void:
	exit_level_requested.emit()


func _on_window_mode_changed(_index: int) -> void:
	_on_setting_control_changed(0.0)


func _on_render_quality_changed(_index: int) -> void:
	_on_setting_control_changed(0.0)


func _on_depth_of_field_toggled(_enabled: bool) -> void:
	_on_setting_control_changed(0.0)


func _on_setting_control_changed(_value: float) -> void:
	if _syncing_controls:
		return
	_settings.set_values(
		volume_slider.value,
		window_mode.selected == 1,
		ui_scale_slider.value,
		depth_of_field_toggle.button_pressed,
		render_quality.get_selected_id()
	)
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
	render_quality.select(_settings.render_quality_preset)
	ui_scale_slider.set_value_no_signal(_settings.ui_scale)
	depth_of_field_toggle.set_pressed_no_signal(_settings.depth_of_field_enabled)
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
