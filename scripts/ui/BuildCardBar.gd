## One-row production build card bar with a dedicated copy-mirror slot.
class_name BuildCardBar
extends Control

@export_group("Layout")
@export_range(1, 12, 1) var building_slot_count: int = 6
@export var card_size: Vector2 = Vector2(96.0, 126.0)
@export_range(0.0, 32.0, 1.0) var card_separation: float = 6.0
@export_range(0.0, 48.0, 1.0) var mirror_slot_separation: float = 14.0

@export_group("Fallback Visual")
@export var mirror_face_color: Color = Color(0.16, 0.29, 0.36, 0.96)
@export var frame_color: Color = Color(0.34, 0.39, 0.43, 1.0)
@export var selected_frame_color: Color = Color(1.0, 0.73, 0.18, 1.0)
@export var unavailable_tint: Color = Color(0.48, 0.48, 0.50, 1.0)

signal building_card_selected(definition: BuildingDefinition)
signal mirror_card_selected
signal cancel_requested

var _resource_manager: ResourceManager
var _mirror_definition: CopyMirrorDefinition
var _building_definitions: Array[BuildingDefinition] = []
var _building_buttons: Dictionary = {}
var _mirror_button: Button
var _cards_row: HBoxContainer
var _status_label: Label
var _selected_definition: BuildingDefinition
var _mirror_selected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()


func configure(
	resource_manager: ResourceManager,
	mirror_definition: CopyMirrorDefinition,
	building_definitions: Array[BuildingDefinition],
	slot_count: int = 6
) -> void:
	_disconnect_resource_manager()
	_resource_manager = resource_manager
	_mirror_definition = mirror_definition
	_building_definitions = building_definitions.duplicate()
	building_slot_count = clampi(slot_count, 1, 12)
	if _resource_manager != null:
		_resource_manager.resource_changed.connect(_on_resource_changed)
		_resource_manager.limits_changed.connect(_on_limits_changed)
	_rebuild_cards()


func set_slot_count(value: int) -> void:
	var resolved := clampi(value, 1, 12)
	if building_slot_count == resolved:
		return
	building_slot_count = resolved
	_rebuild_cards()


func set_selected_building(definition: BuildingDefinition) -> void:
	_selected_definition = definition
	_mirror_selected = false
	_refresh_card_states()


func set_mirror_selected(selected: bool) -> void:
	_mirror_selected = selected
	if selected:
		_selected_definition = null
	_refresh_card_states()


func clear_selection() -> void:
	_selected_definition = null
	_mirror_selected = false
	_refresh_card_states()


func show_status(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.modulate = Color(1.0, 0.46, 0.38, 1.0) if is_error else Color(0.82, 0.94, 1.0, 1.0)


func get_building_slot_count() -> int:
	return building_slot_count


func get_filled_building_card_count() -> int:
	return mini(building_slot_count, _building_definitions.size())


func get_empty_building_card_count() -> int:
	return building_slot_count - get_filled_building_card_count()


func is_building_card_available(definition: BuildingDefinition) -> bool:
	return _is_building_available(definition)


func is_mirror_card_available() -> bool:
	return _is_mirror_available()


func _build_interface() -> void:
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_END
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(0.0, 22.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_status_label)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_theme_stylebox_override("panel", _make_frame_style(Color(0.04, 0.07, 0.09, 0.90), frame_color, 2))
	layout.add_child(frame)

	_cards_row = HBoxContainer.new()
	_cards_row.name = "Cards"
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", int(card_separation))
	_cards_row.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(_cards_row)
	_rebuild_cards()


func _rebuild_cards() -> void:
	if _cards_row == null:
		return
	for child in _cards_row.get_children():
		child.queue_free()
	_building_buttons.clear()
	_mirror_button = _create_card_button(
		_mirror_definition.display_name if _mirror_definition != null else "复制镜",
		_mirror_definition.card_icon if _mirror_definition != null else null,
		_mirror_definition.cost if _mirror_definition != null else 0.0,
		true
	)
	_mirror_button.name = "MirrorCard"
	_mirror_button.pressed.connect(_on_mirror_pressed)
	_cards_row.add_child(_mirror_button)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = mirror_slot_separation
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.add_child(spacer)

	for index in range(building_slot_count):
		if index < _building_definitions.size() and _building_definitions[index] != null:
			var definition := _building_definitions[index]
			var stats := definition.get_level_stats(1)
			var cost := stats.cost if stats != null else 0.0
			var button := _create_card_button(definition.display_name, definition.card_icon, cost, false)
			button.name = "BuildingCard%d" % (index + 1)
			button.pressed.connect(_on_building_pressed.bind(definition))
			_cards_row.add_child(button)
			_building_buttons[definition] = button
		else:
			_cards_row.add_child(_create_empty_card(index))
	_refresh_card_states()


func _create_card_button(
	display_name: String,
	icon: Texture2D,
	cost: float,
	is_mirror: bool
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "%s · 费用 %d" % [display_name, ceili(cost)]
	button.gui_input.connect(_on_card_gui_input)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var title := Label.new()
	title.text = display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	if icon != null:
		var texture := TextureRect.new()
		texture.texture = icon
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(texture)
	else:
		var fallback := Label.new()
		fallback.text = "镜" if is_mirror else display_name.left(1)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fallback.add_theme_font_size_override("font_size", 30)
		fallback.add_theme_color_override("font_color", Color(0.64, 0.92, 1.0) if is_mirror else Color(0.86, 0.95, 1.0))
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(fallback)
	var cost_label := Label.new()
	cost_label.text = "◆ %d" % ceili(cost)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.79, 0.24))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_label)
	return button


func _create_empty_card(index: int) -> Control:
	var panel := PanelContainer.new()
	panel.name = "EmptyCard%d" % (index + 1)
	panel.custom_minimum_size = card_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_frame_style(Color(0.10, 0.18, 0.22, 0.72), Color(0.25, 0.30, 0.33), 3))
	var label := Label.new()
	label.text = "空镜面"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.60, 0.68, 0.72, 0.75)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.gui_input.connect(_on_card_gui_input)
	return panel


func _refresh_card_states() -> void:
	if _mirror_button != null:
		_apply_button_state(_mirror_button, _is_mirror_available(), _mirror_selected)
	for raw_definition in _building_buttons:
		var definition: BuildingDefinition = raw_definition
		var button: Button = _building_buttons[definition]
		_apply_button_state(button, _is_building_available(definition), _selected_definition == definition)


func _apply_button_state(button: Button, available: bool, selected: bool) -> void:
	button.disabled = not available and not selected
	button.self_modulate = Color.WHITE if available else unavailable_tint
	var border := selected_frame_color if selected else frame_color
	var width := 5 if selected else 3
	button.add_theme_stylebox_override("normal", _make_frame_style(mirror_face_color, border, width))
	button.add_theme_stylebox_override("hover", _make_frame_style(mirror_face_color.lightened(0.08), selected_frame_color if selected else Color(0.55, 0.78, 0.88), width))
	button.add_theme_stylebox_override("pressed", _make_frame_style(mirror_face_color.darkened(0.08), selected_frame_color, 5))
	button.add_theme_stylebox_override("disabled", _make_frame_style(Color(0.12, 0.13, 0.14, 0.94), Color(0.24, 0.25, 0.26), 3))


func _make_frame_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _is_building_available(definition: BuildingDefinition) -> bool:
	if definition == null or _resource_manager == null:
		return false
	var stats := definition.get_level_stats(1)
	return (
		stats != null
		and _resource_manager.can_add_building()
		and _resource_manager.can_afford(stats.cost)
	)


func _is_mirror_available() -> bool:
	return (
		_mirror_definition != null
		and _resource_manager != null
		and _resource_manager.can_add_mirror()
		and _resource_manager.can_afford(_mirror_definition.cost)
	)


func _on_building_pressed(definition: BuildingDefinition) -> void:
	if _is_building_available(definition):
		building_card_selected.emit(definition)


func _on_mirror_pressed() -> void:
	if _is_mirror_available():
		mirror_card_selected.emit()


func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()


func _on_resource_changed(_current: float, _delta: float, _reason: String) -> void:
	_refresh_card_states()


func _on_limits_changed(
	_building_count: int,
	_building_limit: int,
	_mirror_count: int,
	_mirror_limit: int
) -> void:
	_refresh_card_states()


func _disconnect_resource_manager() -> void:
	if _resource_manager == null:
		return
	if _resource_manager.resource_changed.is_connected(_on_resource_changed):
		_resource_manager.resource_changed.disconnect(_on_resource_changed)
	if _resource_manager.limits_changed.is_connected(_on_limits_changed):
		_resource_manager.limits_changed.disconnect(_on_limits_changed)
