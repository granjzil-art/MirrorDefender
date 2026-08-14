## Procedural, content-sized thought bubble with a gently flowing cloud edge.
class_name TutorialThoughtBubble
extends Control

const TutorialBubbleDefinitionScript := preload("res://scripts/tutorial/TutorialBubbleDefinition.gd")

const PADDING := Vector2(30.0, 22.0)
const TAIL_HEIGHT := 34.0
const MINIMUM_BODY_WIDTH := 170.0

var definition: TutorialBubbleDefinition
var _label: Label
var _flow_phase: float = 0.0
var _authoring_enabled: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", Color("20242b"))
	_label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.55))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_font_size_override("font_size", 20)
	add_child(_label)
	_refresh_layout()


func configure(value: TutorialBubbleDefinition, authoring_enabled: bool = false) -> void:
	definition = value
	set_authoring_enabled(authoring_enabled)
	if is_node_ready():
		_refresh_layout()


func set_authoring_enabled(enabled: bool) -> void:
	_authoring_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func refresh_content() -> void:
	_refresh_layout()


func _process(delta: float) -> void:
	if definition == null or definition.flow_strength == TutorialBubbleDefinitionScript.FlowStrength.OFF:
		return
	_flow_phase += maxf(0.0, delta) * (
		0.9 if definition.flow_strength == TutorialBubbleDefinitionScript.FlowStrength.LIGHT else 1.45
	)
	queue_redraw()


func _refresh_layout() -> void:
	if not is_node_ready() or _label == null:
		return
	var text := definition.text if definition != null else "教学气泡"
	var maximum_width := definition.maximum_width if definition != null else 420.0
	var font := ThemeDB.fallback_font
	var font_size := 20
	var maximum_text_width := maxf(120.0, maximum_width - PADDING.x * 2.0)
	var natural := font.get_string_size(text.replace("\n", " "), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_width := clampf(natural.x, MINIMUM_BODY_WIDTH - PADDING.x * 2.0, maximum_text_width)
	var measured := font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		text_width,
		font_size
	)
	var body_width := clampf(measured.x + PADDING.x * 2.0, MINIMUM_BODY_WIDTH, maximum_width)
	var body_height := maxf(72.0, measured.y + PADDING.y * 2.0)
	size = Vector2(body_width, body_height + TAIL_HEIGHT)
	_label.position = Vector2(PADDING.x, PADDING.y - 1.0)
	_label.size = Vector2(body_width - PADDING.x * 2.0, body_height - PADDING.y * 2.0)
	_label.text = text
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= TAIL_HEIGHT:
		return
	var body_height := size.y - TAIL_HEIGHT
	var center := Vector2(size.x * 0.5, body_height * 0.5)
	var radii := Vector2(maxf(1.0, size.x * 0.5 - 4.0), maxf(1.0, body_height * 0.5 - 4.0))
	var amplitude := 0.0
	if definition != null:
		if definition.flow_strength == TutorialBubbleDefinitionScript.FlowStrength.LIGHT:
			amplitude = 0.018
		elif definition.flow_strength == TutorialBubbleDefinitionScript.FlowStrength.STRONG:
			amplitude = 0.034
	var points := PackedVector2Array()
	var outline := PackedVector2Array()
	var point_count := 80
	for index in range(point_count):
		var angle := TAU * float(index) / float(point_count)
		var cosine := cos(angle)
		var sine := sin(angle)
		var exponent := 0.58
		var base := Vector2(
			signf(cosine) * pow(absf(cosine), exponent) * radii.x,
			signf(sine) * pow(absf(sine), exponent) * radii.y
		)
		var cloud_lobes := (
			sin(angle * 7.0 + 0.45) * 0.038
			+ sin(angle * 11.0 - 0.75) * 0.022
		)
		var flow := 1.0 + cloud_lobes + amplitude * (
			sin(angle * 7.0 + _flow_phase) * 0.65
			+ sin(angle * 11.0 - _flow_phase * 0.73) * 0.35
		)
		var point := center + base * flow
		points.append(point)
		outline.append(point)
	draw_colored_polygon(points, Color.WHITE)
	outline.append(outline[0])
	draw_polyline(outline, Color(0.19, 0.22, 0.28, 0.48), 2.0, true)
	var tail_origin := Vector2(size.x * 0.23, body_height - 2.0)
	var tail_points := [
		{"offset": Vector2(-4.0, 9.0), "radius": 10.0},
		{"offset": Vector2(-15.0, 23.0), "radius": 6.5},
		{"offset": Vector2(-24.0, 33.0), "radius": 3.8},
	]
	for item in tail_points:
		var tail_center: Vector2 = tail_origin + item["offset"]
		var radius: float = item["radius"]
		draw_circle(tail_center, radius, Color.WHITE)
		draw_arc(tail_center, radius, 0.0, TAU, 24, Color(0.19, 0.22, 0.28, 0.48), 1.5, true)
	if _authoring_enabled:
		draw_dashed_line(Vector2(8.0, 8.0), Vector2(size.x - 8.0, 8.0), Color(0.2, 0.65, 1.0, 0.8), 1.5, 5.0)
