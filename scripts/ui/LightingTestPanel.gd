## LightingTestPanel -- visual switcher for profiles and independent foliage shadows.
class_name LightingTestPanel
extends PanelContainer

var _controller: LightingController
var _buttons: Array[Button] = []
var _title: Label
var _foliage_shadow_button: Button
var _realistic_tree_shadow_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 16.0
	offset_right = 790.0
	offset_bottom = 58.0
	_build_content()


func configure(controller: LightingController) -> void:
	_controller = controller
	if _controller != null and not _controller.profile_changed.is_connected(_on_profile_changed):
		_controller.profile_changed.connect(_on_profile_changed)
	if (
		_controller != null
		and not _controller.foliage_shadow_enabled_changed.is_connected(_on_foliage_shadow_enabled_changed)
	):
		_controller.foliage_shadow_enabled_changed.connect(_on_foliage_shadow_enabled_changed)
	if (
		_controller != null
		and not _controller.realistic_tree_shadow_enabled_changed.is_connected(_on_realistic_tree_shadow_enabled_changed)
	):
		_controller.realistic_tree_shadow_enabled_changed.connect(_on_realistic_tree_shadow_enabled_changed)
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
	var labels := ["白色柔光", "黄色暖光", "青红对比", "夜晚聚光"]
	for index in range(labels.size()):
		var button := Button.new()
		button.text = labels[index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_button_pressed.bind(index))
		row.add_child(button)
		_buttons.append(button)
	_foliage_shadow_button = Button.new()
	_foliage_shadow_button.toggle_mode = true
	_foliage_shadow_button.focus_mode = Control.FOCUS_NONE
	_foliage_shadow_button.toggled.connect(_on_foliage_shadow_toggled)
	row.add_child(_foliage_shadow_button)
	_realistic_tree_shadow_button = Button.new()
	_realistic_tree_shadow_button.toggle_mode = true
	_realistic_tree_shadow_button.focus_mode = Control.FOCUS_NONE
	_realistic_tree_shadow_button.toggled.connect(_on_realistic_tree_shadow_toggled)
	row.add_child(_realistic_tree_shadow_button)
	_refresh()


func _on_button_pressed(profile_index: int) -> void:
	if _controller != null:
		_controller.apply_profile_by_index(profile_index)


func _on_profile_changed(_profile: LightingProfile, _profile_index: int) -> void:
	_refresh()


func _on_foliage_shadow_toggled(enabled: bool) -> void:
	if _controller != null:
		_controller.set_foliage_shadow_enabled(enabled)


func _on_foliage_shadow_enabled_changed(_enabled: bool) -> void:
	_refresh()


func _on_realistic_tree_shadow_toggled(enabled: bool) -> void:
	if _controller != null:
		_controller.set_realistic_tree_shadow_enabled(enabled)


func _on_realistic_tree_shadow_enabled_changed(_enabled: bool) -> void:
	_refresh()


func get_foliage_shadow_button() -> Button:
	return _foliage_shadow_button


func get_realistic_tree_shadow_button() -> Button:
	return _realistic_tree_shadow_button


func get_profile_button_count() -> int:
	return _buttons.size()


func get_profile_button(profile_index: int) -> Button:
	if profile_index < 0 or profile_index >= _buttons.size():
		return null
	return _buttons[profile_index]


func _refresh() -> void:
	if _controller == null:
		if _foliage_shadow_button != null:
			_foliage_shadow_button.disabled = true
		if _realistic_tree_shadow_button != null:
			_realistic_tree_shadow_button.disabled = true
		return
	if _foliage_shadow_button != null:
		var foliage_enabled := _controller.is_foliage_shadow_enabled()
		_foliage_shadow_button.disabled = _controller.get_foliage_shadow() == null
		_foliage_shadow_button.set_pressed_no_signal(foliage_enabled)
		_foliage_shadow_button.text = "树影 开" if foliage_enabled else "树影 关"
	if _realistic_tree_shadow_button != null:
		var realistic_enabled := _controller.is_realistic_tree_shadow_enabled()
		_realistic_tree_shadow_button.disabled = _controller.get_realistic_tree_shadow() == null
		_realistic_tree_shadow_button.set_pressed_no_signal(realistic_enabled)
		_realistic_tree_shadow_button.text = "实树 开" if realistic_enabled else "实树 关"
	if _buttons.is_empty():
		return
	var active_index := _controller.get_active_profile_index()
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(index == active_index)
	var profile := _controller.get_active_profile()
	_title.text = profile.display_name if profile != null else "灯光测试"
