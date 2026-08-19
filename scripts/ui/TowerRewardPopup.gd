## Mandatory wave-completion reward popup. Content is sourced from the same
## BuildingDefinition fields used by the tower codex and inspection UI.
class_name TowerRewardPopup
extends Control

signal confirmed

const PANEL_SIZE := Vector2(660.0, 430.0)
const WAVE_NUMERALS := [
	"一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
	"十一", "十二", "十三", "十四", "十五",
]

var _wave_label: Label
var _icon: TextureRect
var _title: Label
var _description: RichTextLabel
var _confirm_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	hide()


func present(definition: BuildingDefinition, completed_wave_number: int) -> void:
	if definition == null:
		return
	_wave_label.text = "第%s波结束" % _format_wave_number(maxi(1, completed_wave_number))
	_title.text = "获得新塔 · %s" % definition.get_resolved_inspection_display_name()
	_icon.texture = definition.card_icon if definition.card_icon != null else definition.full_card_art
	_description.text = definition.get_formatted_inspection_description_bbcode()
	show()
	_confirm_button.grab_focus()


func dismiss() -> void:
	hide()


func is_open() -> bool:
	return visible


func get_confirm_button() -> Button:
	return _confirm_button


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.035, 0.045, 0.065, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	shade.add_child(panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "防线增援"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("26313a"))
	content.add_child(heading)

	var wave_tag := PanelContainer.new()
	wave_tag.name = "WaveTag"
	wave_tag.custom_minimum_size = Vector2(170.0, 42.0)
	wave_tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wave_tag.add_theme_stylebox_override(
		"panel",
		_make_flat_style(Color("d8c4f0"), Color("8c7aa3"), 8)
	)
	content.add_child(wave_tag)
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 20)
	_wave_label.add_theme_color_override("font_color", Color("26313a"))
	wave_tag.add_child(_wave_label)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	content.add_child(body)

	var icon_panel := PanelContainer.new()
	icon_panel.name = "IconPanel"
	icon_panel.custom_minimum_size = Vector2(190.0, 190.0)
	icon_panel.add_theme_stylebox_override(
		"panel",
		_make_flat_style(Color("cbd2d9"), Color("879099"), 10)
	)
	body.add_child(icon_panel)
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(_icon)

	var information := VBoxContainer.new()
	information.name = "Information"
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation", 10)
	body.add_child(information)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", Color("26313a"))
	information.add_child(_title)
	_description = RichTextLabel.new()
	_description.name = "Description"
	_description.custom_minimum_size = Vector2(380.0, 135.0)
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_description.bbcode_enabled = true
	_description.fit_content = true
	_description.scroll_active = false
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("normal_font_size", 19)
	_description.add_theme_font_size_override("bold_font_size", 19)
	_description.add_theme_color_override("default_color", Color("34434d"))
	information.add_child(_description)

	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmButton"
	_confirm_button.custom_minimum_size = Vector2(200.0, 58.0)
	_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_confirm_button.text = "确认"
	_confirm_button.add_theme_font_size_override("font_size", 23)
	_confirm_button.add_theme_color_override("font_color", Color("26313a"))
	_confirm_button.add_theme_color_override("font_hover_color", Color("26313a"))
	_confirm_button.add_theme_color_override("font_pressed_color", Color("26313a"))
	_confirm_button.add_theme_stylebox_override(
		"normal",
		_make_flat_style(Color("b9e8c2"), Color("79a983"), 8)
	)
	_confirm_button.add_theme_stylebox_override(
		"hover",
		_make_flat_style(Color("c8f2cf"), Color("699b75"), 8)
	)
	_confirm_button.add_theme_stylebox_override(
		"pressed",
		_make_flat_style(Color("a7d8b1"), Color("5f8d69"), 8)
	)
	_confirm_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_confirm_button.pressed.connect(func() -> void: confirmed.emit())
	content.add_child(_confirm_button)


func _make_panel_style() -> StyleBoxFlat:
	var style := _make_flat_style(Color("e9d9bd"), Color("8e8b86"), 14)
	style.content_margin_left = 30.0
	style.content_margin_top = 24.0
	style.content_margin_right = 30.0
	style.content_margin_bottom = 24.0
	return style


func _format_wave_number(wave_number: int) -> String:
	if wave_number >= 1 and wave_number <= WAVE_NUMERALS.size():
		return WAVE_NUMERALS[wave_number - 1]
	return str(wave_number)


func _make_flat_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	return style
