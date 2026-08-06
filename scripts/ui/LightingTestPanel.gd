## LightingTestPanel -- temporary visual switcher for the three lighting profiles.
class_name LightingTestPanel
extends PanelContainer

var _controller: LightingController
var _buttons: Array[Button] = []
var _title: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 16.0
	offset_right = 438.0
	offset_bottom = 58.0
	_build_content()


func configure(controller: LightingController) -> void:
	_controller = controller
	if _controller != null and not _controller.profile_changed.is_connected(_on_profile_changed):
		_controller.profile_changed.connect(_on_profile_changed)
	_refresh()


func _build_content() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_title = Label.new()
	_title.custom_minimum_size.x = 96.0
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.text = "灯光测试"
	row.add_child(_title)
	var labels := ["7 白色柔光", "8 黄色暖光", "9 青红对比"]
	for index in range(labels.size()):
		var button := Button.new()
		button.text = labels[index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_button_pressed.bind(index))
		row.add_child(button)
		_buttons.append(button)
	_refresh()


func _on_button_pressed(profile_index: int) -> void:
	if _controller != null:
		_controller.apply_profile_by_index(profile_index)


func _on_profile_changed(_profile: LightingProfile, _profile_index: int) -> void:
	_refresh()


func _refresh() -> void:
	if _controller == null or _buttons.is_empty():
		return
	var active_index := _controller.get_active_profile_index()
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(index == active_index)
	var profile := _controller.get_active_profile()
	_title.text = profile.display_name if profile != null else "灯光测试"
