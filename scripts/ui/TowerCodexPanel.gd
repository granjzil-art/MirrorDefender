## Read-only tower codex displayed independently from the constructible card bar.
class_name TowerCodexPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Layout")
@export var codex_position: Vector2 = Vector2(18.0, 218.0)
@export var card_size: Vector2 = Vector2(84.0, 92.0)
@export_range(0.0, 32.0, 1.0) var card_separation: float = 8.0
@export_range(0.0, 48.0, 1.0) var description_gap: float = 12.0
@export_range(240.0, 640.0, 1.0) var description_width: float = 360.0

@export_group("Appearance")
@export var card_color: Color = Color(0.035, 0.09, 0.12, 0.94)
@export var card_hover_color: Color = Color(0.075, 0.18, 0.22, 0.98)
@export var frame_color: Color = Color("dea967")
@export var frame_hover_color: Color = Color(0.95, 0.82, 0.58, 1.0)

var _definitions: Array[BuildingDefinition] = []
var _cards_column: VBoxContainer
var _description_panel: PanelContainer
var _description_title: Label
var _description_text: RichTextLabel
var _hovered_card: PanelContainer
var _suppressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	set_feature_enabled(feature_enabled)


func _process(_delta: float) -> void:
	if _description_panel != null and _description_panel.visible:
		_position_description()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_position_layout.call_deferred()


func configure(definitions: Array[BuildingDefinition]) -> void:
	_definitions = definitions.duplicate()
	_rebuild_cards()


func set_feature_enabled(enabled: bool) -> void:
	feature_enabled = enabled
	_refresh_visibility()


func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	_refresh_visibility()


func get_definition_count() -> int:
	return _definitions.size()


func get_definition_at(index: int) -> BuildingDefinition:
	if index < 0 or index >= _definitions.size():
		return null
	return _definitions[index]


func _refresh_visibility() -> void:
	visible = feature_enabled and not _suppressed
	if not visible:
		_hide_description()


func _build_interface() -> void:
	_cards_column = VBoxContainer.new()
	_cards_column.name = "Cards"
	_cards_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_cards_column.add_theme_constant_override("separation", int(card_separation))
	_cards_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_column)
	_build_description_panel()
	_rebuild_cards()


func _build_description_panel() -> void:
	_description_panel = PanelContainer.new()
	_description_panel.name = "DescriptionPanel"
	_description_panel.custom_minimum_size = Vector2(description_width, 0.0)
	_description_panel.size = Vector2(description_width, 0.0)
	_description_panel.z_index = 65
	_description_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.09, 0.96)
	panel_style.border_color = Color(0.32, 0.68, 1.0, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_bottom = 12.0
	_description_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_description_panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description_panel.add_child(content)

	_description_title = Label.new()
	_description_title.name = "Title"
	_description_title.add_theme_font_size_override("font_size", 22)
	_description_title.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	_description_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_description_title)

	_description_text = RichTextLabel.new()
	_description_text.name = "Description"
	_description_text.custom_minimum_size = Vector2(description_width - 28.0, 0.0)
	_description_text.bbcode_enabled = true
	_description_text.fit_content = true
	_description_text.scroll_active = false
	_description_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_text.add_theme_font_size_override("normal_font_size", 18)
	_description_text.add_theme_font_size_override("bold_font_size", 18)
	_description_text.add_theme_constant_override("line_separation", -2)
	_description_text.add_theme_color_override("default_color", Color(0.94, 0.96, 1.0))
	_description_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_description_text)


func _rebuild_cards() -> void:
	if _cards_column == null:
		return
	_hide_description()
	for child in _cards_column.get_children():
		_cards_column.remove_child(child)
		child.queue_free()
	for index in range(_definitions.size()):
		var definition := _definitions[index]
		if definition == null:
			continue
		var card := _create_codex_card(definition)
		card.name = "TowerCard%d" % (index + 1)
		card.mouse_entered.connect(_on_card_mouse_entered.bind(card, definition))
		card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
		_cards_column.add_child(card)
	_position_layout.call_deferred()


func _create_codex_card(definition: BuildingDefinition) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = card_size
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_HELP
	card.add_theme_stylebox_override("panel", _make_card_style(card_color, frame_color))

	var content := Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = definition.card_icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 7.0
	icon.offset_top = 5.0
	icon.offset_right = -7.0
	icon.offset_bottom = -25.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)

	var title_scrim := ColorRect.new()
	title_scrim.name = "TitleScrim"
	title_scrim.anchor_left = 0.0
	title_scrim.anchor_top = 1.0
	title_scrim.anchor_right = 1.0
	title_scrim.anchor_bottom = 1.0
	title_scrim.offset_top = -25.0
	title_scrim.color = Color(0.015, 0.025, 0.035, 0.72)
	title_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_scrim)

	var title := Label.new()
	title.name = "Title"
	title.anchor_left = 0.0
	title.anchor_top = 1.0
	title.anchor_right = 1.0
	title.anchor_bottom = 1.0
	title.offset_top = -25.0
	title.text = definition.get_resolved_inspection_display_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.96))
	title.add_theme_constant_override("outline_size", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	return card


func _make_card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _on_card_mouse_entered(card: PanelContainer, definition: BuildingDefinition) -> void:
	_hovered_card = card
	card.add_theme_stylebox_override("panel", _make_card_style(card_hover_color, frame_hover_color))
	_description_title.text = definition.get_resolved_inspection_display_name()
	_description_text.text = definition.get_formatted_inspection_description_bbcode()
	_description_panel.visible = true
	_position_description()
	_fit_description.call_deferred()


func _on_card_mouse_exited(card: PanelContainer) -> void:
	card.add_theme_stylebox_override("panel", _make_card_style(card_color, frame_color))
	if _hovered_card == card:
		_hide_description()


func _hide_description() -> void:
	_hovered_card = null
	if _description_panel != null:
		_description_panel.visible = false


func _fit_description() -> void:
	if _description_panel == null or not _description_panel.visible:
		return
	_description_panel.reset_size()
	_position_description()


func _position_layout() -> void:
	if _cards_column == null:
		return
	_cards_column.reset_size()
	_cards_column.position = codex_position


func _position_description() -> void:
	if (
		_description_panel == null
		or _hovered_card == null
		or not is_instance_valid(_hovered_card)
		or not _hovered_card.is_inside_tree()
	):
		_hide_description()
		return
	var card_rect := _hovered_card.get_global_rect()
	var panel_size := _description_panel.size
	var panel_origin := get_global_rect().position
	var layout_size := size
	if layout_size.x <= 0.0 or layout_size.y <= 0.0:
		layout_size = get_viewport_rect().size
	_description_panel.position = Vector2(
		clampf(
			card_rect.end.x - panel_origin.x + description_gap,
			8.0,
			maxf(8.0, layout_size.x - panel_size.x - 8.0)
		),
		clampf(
			card_rect.get_center().y - panel_origin.y - panel_size.y * 0.5,
			8.0,
			maxf(8.0, layout_size.y - panel_size.y - 8.0)
		)
	)
