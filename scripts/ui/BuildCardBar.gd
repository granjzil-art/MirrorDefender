## One-row production build card bar with dedicated physical-mirror cards.
class_name BuildCardBar
extends Control

const CardCooldownSweepScript := preload("res://scripts/ui/CardCooldownSweep.gd")
const CardMirrorSurfaceShader := preload("res://scripts/ui/CardMirrorSurface.gdshader")

enum CardVisualMode {
	PROCEDURAL_MIRROR,
	FULL_ARTWORK,
}

@export_group("Layout")
@export_range(1, 12, 1) var building_slot_count: int = 6
@export var card_size: Vector2 = Vector2(96.0, 126.0)
@export_range(0.0, 32.0, 1.0) var card_separation: float = 6.0
@export_range(0.0, 48.0, 1.0) var mirror_slot_separation: float = 14.0

@export_group("Visual Mode")
@export var card_visual_mode: CardVisualMode = CardVisualMode.PROCEDURAL_MIRROR
@export_range(0.0, 1.0, 0.01) var full_art_cost_top_ratio: float = 0.11
@export var full_art_cost_color: Color = Color(1.0, 0.79, 0.24, 1.0)
@export_range(0.0, 1.0, 0.01) var full_art_alpha_trim_threshold: float = 0.03

@export_group("Card Description")
## The X component defines the fixed wrapping width. Height is content-driven;
## the legacy Y component remains serialized for old scenes but is not used.
@export var card_description_size: Vector2 = Vector2(360.0, 300.0)
@export_range(0.0, 48.0, 1.0) var card_description_gap: float = 10.0

@export_group("Procedural Mirror")
@export var mirror_face_color: Color = Color(0.67, 0.69, 0.70, 0.98)
@export var mirror_upper_color: Color = Color(0.91, 0.92, 0.93, 0.99)
@export var mirror_lower_color: Color = Color(0.42, 0.47, 0.49, 0.98)
@export var mirror_sheen_color: Color = Color(0.99, 0.99, 0.98, 1.0)
@export_range(0.0, 1.0, 0.01) var mirror_sheen_strength: float = 0.36
@export_range(0.0, 0.25, 0.005) var mirror_shimmer_speed: float = 0.035
@export_range(0.0, 0.25, 0.005) var mirror_corner_radius: float = 0.085
@export var frame_color: Color = Color("dea967")
@export var frame_highlight_color: Color = Color("f1d29f")
@export var selected_frame_color: Color = Color(1.0, 0.73, 0.18, 1.0)
@export var unavailable_tint: Color = Color(0.48, 0.48, 0.50, 1.0)
@export var cooldown_overlay_color: Color = Color(0.10, 0.11, 0.12, 0.86)
@export var cooldown_scanline_color: Color = Color(0.96, 0.78, 0.30, 0.95)
@export_range(1.0, 8.0, 0.5) var cooldown_scanline_width: float = 3.0

signal building_card_selected(definition: BuildingDefinition)
signal mirror_card_selected
signal reflect_mirror_card_selected

var _resource_manager: ResourceManager
var _mirror_manager: MirrorManager
var _mirror_definition: CopyMirrorDefinition
var _reflect_mirror_definition: ReflectMirrorDefinition
var _building_definitions: Array[BuildingDefinition] = []
var _building_buttons: Dictionary = {}
var _mirror_button: Button
var _reflect_mirror_button: Button
var _mirror_cooldown_sweep: Node
var _reflect_mirror_cooldown_sweep: Node
var _cards_row: HBoxContainer
var _status_label: Label
var _card_description_panel: PanelContainer
var _card_description_title: Label
var _card_description_text: RichTextLabel
var _hovered_card_button: Button
var _selected_definition: BuildingDefinition
var _mirror_selected: bool = false
var _reflect_mirror_selected: bool = false
var _trimmed_full_art_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()


func _process(_delta: float) -> void:
	if _card_description_panel != null and _card_description_panel.visible:
		_position_card_description()


func configure(
	resource_manager: ResourceManager,
	mirror_definition: CopyMirrorDefinition,
	building_definitions: Array[BuildingDefinition],
	slot_count: int = 6,
	reflect_mirror_definition: ReflectMirrorDefinition = null,
	mirror_manager: MirrorManager = null
) -> void:
	_disconnect_resource_manager()
	_disconnect_mirror_manager()
	_resource_manager = resource_manager
	_mirror_manager = mirror_manager
	_mirror_definition = mirror_definition
	_reflect_mirror_definition = reflect_mirror_definition
	_building_definitions = building_definitions.duplicate()
	building_slot_count = clampi(slot_count, 1, 12)
	if _resource_manager != null:
		_resource_manager.resource_changed.connect(_on_resource_changed)
		_resource_manager.limits_changed.connect(_on_limits_changed)
	if _mirror_manager != null:
		_mirror_manager.placement_cooldown_changed.connect(_on_mirror_cooldown_changed)
	_rebuild_cards()


func set_slot_count(value: int) -> void:
	var resolved := clampi(value, 1, 12)
	if building_slot_count == resolved:
		return
	building_slot_count = resolved
	_rebuild_cards()


func set_card_visual_mode(value: CardVisualMode) -> void:
	var resolved := clampi(int(value), CardVisualMode.PROCEDURAL_MIRROR, CardVisualMode.FULL_ARTWORK) as CardVisualMode
	if card_visual_mode == resolved:
		return
	card_visual_mode = resolved
	_rebuild_cards()


func get_card_visual_mode() -> CardVisualMode:
	return card_visual_mode


func set_selected_building(definition: BuildingDefinition) -> void:
	_selected_definition = definition
	_mirror_selected = false
	_reflect_mirror_selected = false
	_refresh_card_states()


func set_mirror_selected(selected: bool) -> void:
	_mirror_selected = selected
	if selected:
		_selected_definition = null
		_reflect_mirror_selected = false
	_refresh_card_states()


func set_reflect_mirror_selected(selected: bool) -> void:
	_reflect_mirror_selected = selected
	if selected:
		_selected_definition = null
		_mirror_selected = false
	_refresh_card_states()


func clear_selection() -> void:
	_selected_definition = null
	_mirror_selected = false
	_reflect_mirror_selected = false
	_refresh_card_states()


func show_status(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.modulate = Color(1.0, 0.46, 0.38, 1.0) if is_error else Color(0.82, 0.94, 1.0, 1.0)


func get_building_slot_count() -> int:
	return building_slot_count


func get_filled_building_card_count() -> int:
	var count := 0
	for index in range(mini(building_slot_count, _building_definitions.size())):
		if _building_definitions[index] is BuildingDefinition:
			count += 1
	return count


## Returns the configured building card at a zero-based formal slot index.
func get_building_definition_at(slot_index: int) -> BuildingDefinition:
	if slot_index < 0 or slot_index >= building_slot_count or slot_index >= _building_definitions.size():
		return null
	return _building_definitions[slot_index]


func get_empty_building_card_count() -> int:
	return building_slot_count - get_filled_building_card_count()


func is_building_card_available(definition: BuildingDefinition) -> bool:
	return _is_building_available(definition)


func is_mirror_card_available() -> bool:
	return _is_mirror_available()


func is_reflect_mirror_card_available() -> bool:
	return _is_reflect_mirror_available()


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

	_cards_row = HBoxContainer.new()
	_cards_row.name = "Cards"
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", int(card_separation))
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_cards_row)
	_build_card_description_panel()
	_rebuild_cards()


func _build_card_description_panel() -> void:
	_card_description_panel = PanelContainer.new()
	_card_description_panel.name = "CardDescriptionPanel"
	_card_description_panel.custom_minimum_size = Vector2(card_description_size.x, 0.0)
	_card_description_panel.size = Vector2(card_description_size.x, 0.0)
	_card_description_panel.z_index = 60
	_card_description_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_description_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.09, 0.96)
	panel_style.border_color = Color(0.32, 0.68, 1.0, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_bottom = 12.0
	_card_description_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_card_description_panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_description_panel.add_child(content)

	_card_description_title = Label.new()
	_card_description_title.name = "Title"
	_card_description_title.add_theme_font_size_override("font_size", 22)
	_card_description_title.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	_card_description_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_card_description_title)

	_card_description_text = RichTextLabel.new()
	_card_description_text.name = "Description"
	_card_description_text.custom_minimum_size = Vector2(card_description_size.x - 28.0, 0.0)
	_card_description_text.bbcode_enabled = true
	_card_description_text.fit_content = true
	_card_description_text.scroll_active = false
	_card_description_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_description_text.add_theme_font_size_override("normal_font_size", 18)
	_card_description_text.add_theme_font_size_override("bold_font_size", 18)
	_card_description_text.add_theme_constant_override("line_separation", -2)
	_card_description_text.add_theme_color_override("default_color", Color(0.94, 0.96, 1.0))
	_card_description_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_card_description_text)


func _rebuild_cards() -> void:
	if _cards_row == null:
		return
	_hide_card_description()
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	_building_buttons.clear()
	_mirror_button = _create_card_button(
		_mirror_definition.display_name if _mirror_definition != null else "复制镜",
		_mirror_definition.card_icon if _mirror_definition != null else null,
		_mirror_definition.placement_cost if _mirror_definition != null else 0.0,
		true
	)
	_mirror_button.name = "MirrorCard"
	_mirror_cooldown_sweep = _mirror_button.get_node("CooldownSweep") as Node
	_mirror_button.pressed.connect(_on_mirror_pressed)
	if _mirror_definition != null:
		_mirror_button.mouse_entered.connect(
			_on_mirror_card_mouse_entered.bind(_mirror_button, _mirror_definition)
		)
		_mirror_button.mouse_exited.connect(_on_card_mouse_exited.bind(_mirror_button))
	_cards_row.add_child(_mirror_button)
	if _reflect_mirror_definition != null:
		_reflect_mirror_button = _create_card_button(
			_reflect_mirror_definition.display_name,
			_reflect_mirror_definition.card_icon,
			_reflect_mirror_definition.placement_cost,
			true
		)
		_reflect_mirror_button.name = "ReflectMirrorCard"
		_reflect_mirror_cooldown_sweep = _reflect_mirror_button.get_node("CooldownSweep") as Node
		_reflect_mirror_button.pressed.connect(_on_reflect_mirror_pressed)
		_reflect_mirror_button.mouse_entered.connect(
			_on_mirror_card_mouse_entered.bind(
				_reflect_mirror_button,
				_reflect_mirror_definition
			)
		)
		_reflect_mirror_button.mouse_exited.connect(
			_on_card_mouse_exited.bind(_reflect_mirror_button)
		)
		_cards_row.add_child(_reflect_mirror_button)
	else:
		_reflect_mirror_button = null
		_reflect_mirror_cooldown_sweep = null

	var spacer := Control.new()
	spacer.custom_minimum_size.x = mirror_slot_separation
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.add_child(spacer)

	for index in range(building_slot_count):
		if index < _building_definitions.size() and _building_definitions[index] != null:
			var definition := _building_definitions[index]
			var stats := definition.get_level_stats(1)
			var cost := stats.cost if stats != null else 0.0
			var button := (
				_create_full_art_card_button(definition.display_name, definition.full_card_art, cost)
				if card_visual_mode == CardVisualMode.FULL_ARTWORK and definition.full_card_art != null
				else _create_card_button(definition.display_name, definition.card_icon, cost, false)
			)
			button.name = "BuildingCard%d" % (index + 1)
			button.pressed.connect(_on_building_pressed.bind(definition))
			button.mouse_entered.connect(_on_building_card_mouse_entered.bind(button, definition))
			button.mouse_exited.connect(_on_card_mouse_exited.bind(button))
			_cards_row.add_child(button)
			_building_buttons[definition] = button
		else:
			_cards_row.add_child(
				_create_invisible_empty_card(index)
				if card_visual_mode == CardVisualMode.FULL_ARTWORK
				else _create_empty_card(index)
			)
	_refresh_card_states()


func _create_full_art_card_button(
	display_name: String,
	full_card_art: Texture2D,
	cost: float
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = ""
	_apply_empty_button_styles(button)

	var artwork := TextureRect.new()
	artwork.name = "FullArtwork"
	_set_full_rect(artwork)
	artwork.texture = _get_trimmed_full_art(full_card_art)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(artwork)

	var cost_label := Label.new()
	cost_label.name = "Cost"
	var cost_top := card_size.y * full_art_cost_top_ratio
	_set_control_rect(cost_label, Rect2(6.0, cost_top, card_size.x - 12.0, 26.0))
	cost_label.text = "◆ %d" % ceili(cost)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 17)
	cost_label.add_theme_color_override("font_color", full_art_cost_color)
	cost_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.035, 0.98))
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cost_label)
	button.mouse_entered.connect(_set_full_art_hovered.bind(button, true))
	button.mouse_exited.connect(_set_full_art_hovered.bind(button, false))
	return button


func _create_card_button(
	display_name: String,
	icon: Texture2D,
	cost: float,
	is_mirror: bool
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = ""

	var mirror_surface := _create_mirror_surface()
	button.add_child(mirror_surface)
	var inner_frame := Panel.new()
	inner_frame.name = "InnerFrame"
	_set_full_rect(inner_frame, 4.0)
	inner_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_frame.add_theme_stylebox_override("panel", _make_inner_frame_style(frame_highlight_color))
	button.add_child(inner_frame)

	var content := Control.new()
	content.name = "Content"
	_set_full_rect(content)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var artwork_rect := Rect2(7.0, 17.0, card_size.x - 14.0, card_size.y - 36.0)
	if icon != null:
		var shadow := _create_artwork_rect(icon, "ArtworkShadow", artwork_rect)
		shadow.offset_left += 2.0
		shadow.offset_top += 3.0
		shadow.offset_right += 2.0
		shadow.offset_bottom += 3.0
		shadow.modulate = Color(0.02, 0.04, 0.05, 0.52)
		content.add_child(shadow)
		content.add_child(_create_artwork_rect(icon, "Artwork", artwork_rect))
	else:
		var fallback := Label.new()
		fallback.name = "Fallback"
		_set_control_rect(fallback, artwork_rect)
		fallback.text = "镜" if is_mirror else display_name.left(1)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 38)
		fallback.add_theme_color_override("font_color", Color(0.64, 0.92, 1.0) if is_mirror else Color(0.86, 0.95, 1.0))
		fallback.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.07, 0.82))
		fallback.add_theme_constant_override("outline_size", 4)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(fallback)

	var title_scrim := ColorRect.new()
	title_scrim.name = "TitleScrim"
	_set_control_rect(title_scrim, Rect2(5.0, 5.0, card_size.x - 10.0, 24.0))
	title_scrim.color = Color(0.04, 0.05, 0.055, 0.24)
	title_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_scrim)
	var footer_scrim := ColorRect.new()
	footer_scrim.name = "FooterScrim"
	_set_control_rect(footer_scrim, Rect2(5.0, card_size.y - 29.0, card_size.x - 10.0, 24.0))
	footer_scrim.color = Color(0.04, 0.05, 0.055, 0.32)
	footer_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(footer_scrim)

	var title := Label.new()
	title.name = "Title"
	_set_control_rect(title, Rect2(7.0, 5.0, card_size.x - 14.0, 24.0))
	title.text = display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.04, 0.96))
	title.add_theme_constant_override("outline_size", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var cost_label := Label.new()
	cost_label.name = "Footer"
	_set_control_rect(cost_label, Rect2(7.0, card_size.y - 29.0, card_size.x - 14.0, 24.0))
	cost_label.text = "就绪" if is_mirror else "◆ %d" % ceili(cost)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 16)
	cost_label.add_theme_color_override(
		"font_color",
		Color(0.72, 0.94, 1.0) if is_mirror else full_art_cost_color
	)
	cost_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.04, 0.96))
	cost_label.add_theme_constant_override("outline_size", 3)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_label)
	button.mouse_entered.connect(_set_card_hovered.bind(button, true))
	button.mouse_exited.connect(_set_card_hovered.bind(button, false))
	if is_mirror:
		var sweep := CardCooldownSweepScript.new()
		sweep.name = "CooldownSweep"
		sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sweep.overlay_color = cooldown_overlay_color
		sweep.scanline_color = cooldown_scanline_color
		sweep.scanline_width = cooldown_scanline_width
		button.add_child(sweep)
	return button


func _create_empty_card(index: int) -> Control:
	var panel := Panel.new()
	panel.name = "EmptyCard%d" % (index + 1)
	panel.custom_minimum_size = card_size
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_frame_style(Color(0.10, 0.18, 0.22, 0.72), Color(0.25, 0.30, 0.33), 3))
	var mirror_surface := _create_mirror_surface()
	_set_surface_state(mirror_surface, 0.0, 0.72)
	panel.add_child(mirror_surface)
	var inner_frame := Panel.new()
	inner_frame.name = "InnerFrame"
	_set_full_rect(inner_frame, 4.0)
	inner_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_frame.add_theme_stylebox_override("panel", _make_inner_frame_style(Color(0.40, 0.45, 0.47, 0.62)))
	panel.add_child(inner_frame)
	var label := Label.new()
	_set_full_rect(label, 8.0)
	label.text = "空镜面"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.60, 0.68, 0.72, 0.75)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


func _create_invisible_empty_card(index: int) -> Control:
	var slot := Control.new()
	slot.name = "EmptyCard%d" % (index + 1)
	slot.custom_minimum_size = card_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _refresh_card_states() -> void:
	if _mirror_button != null:
		_apply_mirror_button_state(
			_mirror_button,
			_mirror_cooldown_sweep,
			MirrorPlacementData.MirrorKind.COPY,
			_mirror_definition,
			_mirror_selected
		)
	if _reflect_mirror_button != null:
		_apply_mirror_button_state(
			_reflect_mirror_button,
			_reflect_mirror_cooldown_sweep,
			MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
			_reflect_mirror_definition,
			_reflect_mirror_selected
		)
	for raw_definition in _building_buttons:
		var definition: BuildingDefinition = raw_definition
		var button: Button = _building_buttons[definition]
		_apply_button_state(button, _is_building_available(definition), _selected_definition == definition)


func _apply_mirror_button_state(
	button: Button,
	sweep: Node,
	mirror_kind: MirrorPlacementData.MirrorKind,
	definition: MirrorDefinition,
	selected: bool
) -> void:
	var has_capacity := _resource_manager != null and _resource_manager.can_add_mirror(mirror_kind)
	var uses_cooldown := _mirror_manager != null and _mirror_manager.uses_placement_cooldown()
	var ready := not uses_cooldown or _mirror_manager.is_mirror_kind_ready(mirror_kind)
	var affordable := (
		definition != null
		and _resource_manager != null
		and (uses_cooldown or _resource_manager.can_afford(definition.placement_cost))
	)
	var available := definition != null and has_capacity and ready and affordable
	var blocked_by_cap := definition == null or not has_capacity
	button.disabled = not available
	button.self_modulate = (
		Color.WHITE
		if available or (uses_cooldown and not ready and not blocked_by_cap)
		else unavailable_tint
	)
	var border := selected_frame_color if selected else frame_color
	var width := 5 if selected else 3
	button.add_theme_stylebox_override("normal", _make_frame_style(mirror_face_color, border, width))
	button.add_theme_stylebox_override("hover", _make_frame_style(mirror_face_color.lightened(0.08), selected_frame_color if selected else Color(0.55, 0.78, 0.88), width))
	button.add_theme_stylebox_override("pressed", _make_frame_style(mirror_face_color.darkened(0.08), selected_frame_color, 5))
	button.add_theme_stylebox_override(
		"disabled",
		_make_frame_style(
			Color(0.12, 0.13, 0.14, 0.94) if blocked_by_cap else mirror_face_color,
			Color(0.24, 0.25, 0.26) if blocked_by_cap else border,
			width
		)
	)
	_set_button_surface_state(button, not blocked_by_cap and affordable, selected)
	_set_inner_frame_state(button, border, selected)
	var ready_ratio := (
		_mirror_manager.get_placement_cooldown_ready_ratio(mirror_kind)
		if _mirror_manager != null
		else 1.0
	)
	if sweep != null:
		sweep.set("visible", uses_cooldown)
		if uses_cooldown:
			sweep.call("set_state", ready_ratio, blocked_by_cap)
	var footer := button.get_node_or_null("Content/Footer") as Label
	if footer != null:
		if blocked_by_cap:
			footer.text = "已达上限" if definition != null else "未配置"
		elif uses_cooldown and not ready:
			footer.text = "%.1fs" % _mirror_manager.get_placement_cooldown_remaining(mirror_kind)
		elif uses_cooldown:
			footer.text = "×%d" % _mirror_manager.get_available_mirror_count(mirror_kind)
		elif definition != null:
			footer.text = "◆ %d" % ceili(definition.placement_cost)
		else:
			footer.text = "未配置"
		var displays_coin_cost := not uses_cooldown and definition != null and not blocked_by_cap
		footer.add_theme_color_override(
			"font_color",
			full_art_cost_color if displays_coin_cost else Color(0.72, 0.94, 1.0)
		)


func _apply_button_state(button: Button, available: bool, selected: bool) -> void:
	if button.get_node_or_null("FullArtwork") != null:
		_apply_full_art_button_state(button, available, selected)
		return
	button.disabled = not available and not selected
	button.self_modulate = Color.WHITE if available else unavailable_tint
	var border := selected_frame_color if selected else frame_color
	var width := 5 if selected else 3
	button.add_theme_stylebox_override("normal", _make_frame_style(mirror_face_color, border, width))
	button.add_theme_stylebox_override("hover", _make_frame_style(mirror_face_color.lightened(0.08), selected_frame_color if selected else Color(0.55, 0.78, 0.88), width))
	button.add_theme_stylebox_override("pressed", _make_frame_style(mirror_face_color.darkened(0.08), selected_frame_color, 5))
	button.add_theme_stylebox_override("disabled", _make_frame_style(Color(0.12, 0.13, 0.14, 0.94), Color(0.24, 0.25, 0.26), 3))
	_set_button_surface_state(button, available, selected)
	_set_inner_frame_state(button, border, selected)


func _apply_full_art_button_state(button: Button, available: bool, selected: bool) -> void:
	button.disabled = not available and not selected
	button.set_meta(&"card_available", available)
	button.set_meta(&"card_selected", selected)
	_refresh_full_art_modulate(button)


func _apply_empty_button_styles(button: Button) -> void:
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _set_full_art_hovered(button: Button, hovered: bool) -> void:
	button.set_meta(&"card_hovered", hovered)
	_refresh_full_art_modulate(button)


func _refresh_full_art_modulate(button: Button) -> void:
	var available := bool(button.get_meta(&"card_available", true))
	var selected := bool(button.get_meta(&"card_selected", false))
	var hovered := bool(button.get_meta(&"card_hovered", false))
	if not available:
		button.self_modulate = unavailable_tint
	elif selected:
		button.self_modulate = Color(1.12, 1.05, 0.78, 1.0)
	elif hovered:
		button.self_modulate = Color(1.08, 1.08, 1.08, 1.0)
	else:
		button.self_modulate = Color.WHITE


func _make_frame_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _make_inner_frame_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = color
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _create_mirror_surface() -> ColorRect:
	var surface := ColorRect.new()
	surface.name = "MirrorSurface"
	_set_full_rect(surface, 5.0)
	surface.color = Color.WHITE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = CardMirrorSurfaceShader
	shader_material.set_shader_parameter("upper_color", mirror_upper_color)
	shader_material.set_shader_parameter("middle_color", mirror_face_color)
	shader_material.set_shader_parameter("lower_color", mirror_lower_color)
	shader_material.set_shader_parameter("sheen_color", mirror_sheen_color)
	shader_material.set_shader_parameter("sheen_strength", mirror_sheen_strength)
	shader_material.set_shader_parameter("shimmer_speed", mirror_shimmer_speed)
	shader_material.set_shader_parameter("corner_radius", mirror_corner_radius)
	surface.material = shader_material
	return surface


func _create_artwork_rect(icon: Texture2D, node_name: String, rect: Rect2) -> TextureRect:
	var artwork := TextureRect.new()
	artwork.name = node_name
	_set_control_rect(artwork, rect)
	artwork.texture = icon
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return artwork


func _get_trimmed_full_art(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := texture.get_instance_id()
	if _trimmed_full_art_cache.has(cache_key):
		return _trimmed_full_art_cache[cache_key] as Texture2D
	var image := texture.get_image()
	if image == null or image.is_empty():
		_trimmed_full_art_cache[cache_key] = texture
		return texture
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= full_art_alpha_trim_threshold:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		_trimmed_full_art_cache[cache_key] = texture
		return texture
	var region := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	if region.position == Vector2i.ZERO and region.size == image.get_size():
		_trimmed_full_art_cache[cache_key] = texture
		return texture
	var trimmed := AtlasTexture.new()
	trimmed.atlas = texture
	trimmed.region = Rect2(region)
	_trimmed_full_art_cache[cache_key] = trimmed
	return trimmed


func _set_full_rect(control: Control, inset: float = 0.0) -> void:
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = inset
	control.offset_top = inset
	control.offset_right = -inset
	control.offset_bottom = -inset


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _set_card_hovered(button: Button, hovered: bool) -> void:
	var surface := button.get_node_or_null("MirrorSurface") as ColorRect
	if surface == null or not surface.material is ShaderMaterial:
		return
	(surface.material as ShaderMaterial).set_shader_parameter("hover_strength", 1.0 if hovered else 0.0)


func _on_building_card_mouse_entered(
	button: Button,
	definition: BuildingDefinition
) -> void:
	if button == null or definition == null or _card_description_panel == null:
		return
	_show_card_description(
		button,
		definition.get_resolved_inspection_display_name(),
		definition.get_formatted_inspection_description_bbcode()
	)


func _on_mirror_card_mouse_entered(
	button: Button,
	definition: MirrorDefinition
) -> void:
	if button == null or definition == null or _card_description_panel == null:
		return
	_show_card_description(
		button,
		definition.get_resolved_inspection_display_name(),
		definition.get_formatted_inspection_description_bbcode()
	)


func _show_card_description(
	button: Button,
	display_name: String,
	formatted_description: String
) -> void:
	_hovered_card_button = button
	_card_description_title.text = display_name
	_card_description_text.text = formatted_description
	_card_description_panel.visible = true
	_position_card_description()
	_fit_card_description.call_deferred()


func _fit_card_description() -> void:
	if _card_description_panel == null or not _card_description_panel.visible:
		return
	_card_description_panel.reset_size()
	_position_card_description()


func _on_card_mouse_exited(button: Button) -> void:
	if _hovered_card_button == button:
		_hide_card_description()


func _hide_card_description() -> void:
	_hovered_card_button = null
	if _card_description_panel != null:
		_card_description_panel.visible = false


func _position_card_description() -> void:
	if (
		_card_description_panel == null
		or _hovered_card_button == null
		or not is_instance_valid(_hovered_card_button)
		or not _hovered_card_button.is_inside_tree()
	):
		_hide_card_description()
		return
	var button_rect := _hovered_card_button.get_global_rect()
	var bar_origin := get_global_rect().position
	var panel_size := _card_description_panel.size
	_card_description_panel.position = Vector2(
		button_rect.get_center().x - bar_origin.x - panel_size.x * 0.5,
		button_rect.position.y - bar_origin.y - panel_size.y - card_description_gap
	)


func _set_button_surface_state(button: Button, available: bool, selected: bool) -> void:
	var surface := button.get_node_or_null("MirrorSurface") as ColorRect
	_set_surface_state(surface, 1.0 if selected else 0.0, 0.0 if available else 0.42)


func _set_surface_state(
	surface: ColorRect,
	selected_strength: float,
	disabled_strength: float
) -> void:
	if surface == null or not surface.material is ShaderMaterial:
		return
	var shader_material := surface.material as ShaderMaterial
	shader_material.set_shader_parameter("selected_strength", selected_strength)
	shader_material.set_shader_parameter("disabled_strength", disabled_strength)


func _set_inner_frame_state(button: Button, border: Color, selected: bool) -> void:
	var inner_frame := button.get_node_or_null("InnerFrame") as Panel
	if inner_frame == null:
		return
	var color := selected_frame_color.lightened(0.28) if selected else frame_highlight_color
	color = color.lerp(border, 0.18)
	inner_frame.add_theme_stylebox_override("panel", _make_inner_frame_style(color))


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
	var uses_cooldown := _mirror_manager != null and _mirror_manager.uses_placement_cooldown()
	return (
		_mirror_definition != null
		and _resource_manager != null
		and _resource_manager.can_add_mirror(MirrorPlacementData.MirrorKind.COPY)
		and (uses_cooldown or _resource_manager.can_afford(_mirror_definition.placement_cost))
		and (
			not uses_cooldown
			or _mirror_manager.is_mirror_kind_ready(MirrorPlacementData.MirrorKind.COPY)
		)
	)


func _is_reflect_mirror_available() -> bool:
	var uses_cooldown := _mirror_manager != null and _mirror_manager.uses_placement_cooldown()
	return (
		_reflect_mirror_definition != null
		and _resource_manager != null
		and _resource_manager.can_add_mirror(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT)
		and (uses_cooldown or _resource_manager.can_afford(_reflect_mirror_definition.placement_cost))
		and (
			not uses_cooldown
			or _mirror_manager.is_mirror_kind_ready(
				MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
			)
		)
	)


func _on_building_pressed(definition: BuildingDefinition) -> void:
	if _is_building_available(definition):
		building_card_selected.emit(definition)


func _on_mirror_pressed() -> void:
	if _is_mirror_available():
		mirror_card_selected.emit()


func _on_reflect_mirror_pressed() -> void:
	if _is_reflect_mirror_available():
		reflect_mirror_card_selected.emit()


func _on_resource_changed(_current: float, _delta: float, _reason: String) -> void:
	_refresh_card_states()


func _on_limits_changed(
	_building_count: int,
	_building_limit: int,
	_copy_mirror_count: int,
	_copy_mirror_limit: int,
	_reflect_mirror_count: int,
	_reflect_mirror_limit: int
) -> void:
	_refresh_card_states()


func _on_mirror_cooldown_changed(
	_mirror_kind: MirrorPlacementData.MirrorKind,
	_remaining: float,
	_duration: float,
	_ready_ratio: float
) -> void:
	_refresh_card_states()


func _disconnect_resource_manager() -> void:
	if _resource_manager == null:
		return
	if _resource_manager.resource_changed.is_connected(_on_resource_changed):
		_resource_manager.resource_changed.disconnect(_on_resource_changed)
	if _resource_manager.limits_changed.is_connected(_on_limits_changed):
		_resource_manager.limits_changed.disconnect(_on_limits_changed)


func _disconnect_mirror_manager() -> void:
	if _mirror_manager == null:
		return
	if _mirror_manager.placement_cooldown_changed.is_connected(_on_mirror_cooldown_changed):
		_mirror_manager.placement_cooldown_changed.disconnect(_on_mirror_cooldown_changed)
