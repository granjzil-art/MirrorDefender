## Runtime-only level picker. Production level selection calls LevelLoader directly.
class_name LevelDebugPanel
extends Control

const LevelLoaderScript := preload("res://scripts/level/LevelLoader.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Files")
@export_dir var initial_directory: String = "res://resources/levels"

var _level_loader: LevelLoaderScript
var _status_label: Label
var _load_button: Button
var _file_dialog: FileDialog

func _ready() -> void:
	visible = feature_enabled
	_build_interface()

func configure(level_loader: LevelLoaderScript) -> void:
	_disconnect_loader()
	_level_loader = level_loader
	if _level_loader != null:
		_level_loader.level_loaded.connect(_on_level_loaded)
		_level_loader.level_load_failed.connect(_on_level_load_failed)
	_load_button.disabled = _level_loader == null
	_update_current_level_status()

func _build_interface() -> void:
	var toolbar := HBoxContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)
	_status_label = Label.new()
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.tooltip_text = "当前运行时关卡"
	toolbar.add_child(_status_label)
	_load_button = Button.new()
	_load_button.text = "加载关卡"
	_load_button.tooltip_text = "调试：选择一个 LevelResource .tres"
	_load_button.pressed.connect(_show_file_dialog)
	toolbar.add_child(_load_button)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.add_filter("*.tres ; LevelResource")
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

func _show_file_dialog() -> void:
	if _level_loader == null:
		return
	_file_dialog.current_dir = initial_directory
	_file_dialog.popup_centered_ratio(0.65)

func _on_file_selected(path: String) -> void:
	if _level_loader != null:
		_level_loader.load_level_path(path)

func _on_level_loaded(level_resource: LevelResource, source_path: String) -> void:
	var display_path := source_path if not source_path.is_empty() else level_resource.resource_path
	_status_label.text = "关卡：%s" % _display_name(display_path)
	_status_label.tooltip_text = display_path

func _on_level_load_failed(source_path: String, reason: String) -> void:
	_status_label.text = "加载失败：%s" % reason
	_status_label.tooltip_text = source_path

func _update_current_level_status() -> void:
	if _status_label == null:
		return
	if _level_loader == null or _level_loader.get_current_level() == null:
		_status_label.text = "关卡：未加载"
		return
	var level_resource := _level_loader.get_current_level()
	_on_level_loaded(level_resource, level_resource.resource_path)

func _display_name(path: String) -> String:
	if path.is_empty():
		return "内存关卡"
	return path.get_file().get_basename()

func _disconnect_loader() -> void:
	if _level_loader == null:
		return
	if _level_loader.level_loaded.is_connected(_on_level_loaded):
		_level_loader.level_loaded.disconnect(_on_level_loaded)
	if _level_loader.level_load_failed.is_connected(_on_level_load_failed):
		_level_loader.level_load_failed.disconnect(_on_level_load_failed)
