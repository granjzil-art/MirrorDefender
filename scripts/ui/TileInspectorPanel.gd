## Read-only, scrollable M6 panel for every item associated with one cell.
class_name TileInspectorPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Layout")
@export_range(64.0, 160.0, 1.0) var preview_size: float = 82.0
@export_range(88.0, 180.0, 1.0) var entry_minimum_height: float = 112.0
@export_range(40.0, 120.0, 1.0) var compact_entry_minimum_height: float = 54.0
@export_range(0, 24, 1) var entry_separation: int = 8

@export_group("Fallback Visual")
@export var fallback_icon: Texture2D
@export var glass_color: Color = Color(0.055, 0.10, 0.14, 0.94)
@export var frame_color: Color = Color(0.34, 0.61, 0.72, 1.0)
@export var entity_color: Color = Color(0.34, 0.78, 0.94, 1.0)
@export var projection_color: Color = Color(0.16, 0.92, 1.0, 1.0)
@export var element_color: Color = Color(0.95, 0.58, 0.24, 1.0)

var _model: Dictionary = {}
var _outer_panel: PanelContainer
var _title_label: Label
var _summary_label: Label
var _scroll: ScrollContainer
var _entries: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_interface()


func display_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	var raw_entries: Variant = model.get("entries", [])
	var has_content: bool = feature_enabled and bool(model.get("has_content", false)) and raw_entries is Array and not raw_entries.is_empty()
	if not has_content:
		clear_inspection()
		return
	var cell: Vector3i = model.get("cell", Vector3i.ZERO)
	_title_label.text = "地块详情 · %s" % str(cell)
	_summary_label.text = "%s · 高度档 %d\n块建筑 %s · 边建筑 %s" % [
		String(model.get("terrain_name", "地块")),
		int(model.get("height_level", 0)),
		"允许" if bool(model.get("allows_tile_building", false)) else "禁止",
		"允许" if bool(model.get("allows_edge_building", false)) else "禁止",
	]
	_rebuild_entries(raw_entries)
	visible = true


func clear_inspection() -> void:
	_model = {}
	visible = false
	_clear_entries()


func get_entry_count() -> int:
	return _entries.get_child_count() if _entries != null else 0


func get_displayed_model() -> Dictionary:
	return _model.duplicate(true)


func get_scroll_container() -> ScrollContainer:
	return _scroll


func _build_interface() -> void:
	_outer_panel = PanelContainer.new()
	_outer_panel.name = "GlassPanel"
	_outer_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_outer_panel.add_theme_stylebox_override("panel", _make_style(glass_color, frame_color, 3, 12))
	add_child(_outer_panel)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 6)
	_outer_panel.add_child(layout)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
	layout.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.add_theme_font_size_override("font_size", 14)
	_summary_label.add_theme_color_override("font_color", Color(0.69, 0.82, 0.88))
	layout.add_child(_summary_label)

	var separator := HSeparator.new()
	layout.add_child(separator)

	_scroll = ScrollContainer.new()
	_scroll.name = "EntriesScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	layout.add_child(_scroll)

	_entries = VBoxContainer.new()
	_entries.name = "Entries"
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override("separation", entry_separation)
	_scroll.add_child(_entries)


func _rebuild_entries(raw_entries: Array) -> void:
	_clear_entries()
	for raw_entry in raw_entries:
		if raw_entry is Dictionary:
			var card := _make_entry_card(raw_entry)
			card.name = "Entry%d" % _entries.get_child_count()
			_entries.add_child(card)


func _clear_entries() -> void:
	if _entries == null:
		return
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()


func _make_entry_card(entry: Dictionary) -> Control:
	var accent: Color = entry.get("accent", entity_color)
	var state := String(entry.get("state", "实体"))
	var show_icon := bool(entry.get("show_icon", true))
	var show_category := bool(entry.get("show_category", true))
	var show_state := bool(entry.get("show_state", true))
	var show_description := bool(entry.get("show_description", true))
	if state == "虚像":
		accent = projection_color.lerp(accent, 0.32)
	elif StringName(entry.get("kind", &"")) == &"tile_element":
		accent = element_color.lerp(accent, 0.35)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, entry_minimum_height if show_icon else compact_entry_minimum_height)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _make_style(Color(0.10, 0.18, 0.23, 0.93), accent, 2, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	if show_icon:
		var preview := _make_preview(entry, accent)
		preview.name = "Preview"
		row.add_child(preview)

	var text_layout := VBoxContainer.new()
	text_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_layout.add_theme_constant_override("separation", 2)
	row.add_child(text_layout)

	var heading := Label.new()
	heading.name = "Name"
	heading.text = String(entry.get("name", "未知内容"))
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	text_layout.add_child(heading)

	var identity_parts: Array[String] = []
	if show_category:
		identity_parts.append(String(entry.get("category", "内容")))
	if show_state:
		identity_parts.append(state)
	if not identity_parts.is_empty():
		var type_label := Label.new()
		type_label.name = "Type"
		type_label.text = " · ".join(identity_parts)
		type_label.add_theme_font_size_override("font_size", 13)
		type_label.add_theme_color_override("font_color", accent)
		text_layout.add_child(type_label)

	var description := String(entry.get("description", "")).strip_edges()
	if show_description and not description.is_empty():
		var function_label := Label.new()
		function_label.name = "Function"
		function_label.text = "功能：%s" % description
		function_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		function_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		function_label.add_theme_font_size_override("font_size", 13)
		function_label.add_theme_color_override("font_color", Color(0.72, 0.94, 1.0))
		text_layout.add_child(function_label)

	var raw_lines: Variant = entry.get("lines", [])
	if raw_lines is Array and not raw_lines.is_empty():
		var detail := Label.new()
		detail.name = "Details"
		detail.text = "\n".join(raw_lines)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_theme_font_size_override("font_size", 13)
		detail.add_theme_color_override("font_color", Color(0.78, 0.86, 0.90))
		text_layout.add_child(detail)
	return card


func _make_preview(entry: Dictionary, accent: Color) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(preview_size, preview_size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.05, 0.09, 0.12, 1.0), accent, 2, 6))
	var icon: Texture2D = entry.get("icon") as Texture2D
	if icon == null:
		icon = fallback_icon
	if icon != null:
		var texture := TextureRect.new()
		texture.texture = icon
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(texture)
		return frame
	var fallback := Label.new()
	var display_name := String(entry.get("name", "?"))
	fallback.text = display_name.left(2)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override("font_size", 22)
	fallback.add_theme_color_override("font_color", accent)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fallback)
	return frame


func _make_style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
