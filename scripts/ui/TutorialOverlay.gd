## Player-facing tutorial bubbles and the selectable top-left checklist.
class_name TutorialOverlay
extends Control

const TutorialThoughtBubbleScript := preload("res://scripts/ui/TutorialThoughtBubble.gd")
const TutorialBubbleDefinitionScript := preload("res://scripts/tutorial/TutorialBubbleDefinition.gd")

var _director: TutorialDirector
var _camera: Camera3D
var _grid: GridManager
var _bubble_layer: Control
var _checklist_panel: PanelContainer
var _checklist_box: VBoxContainer
var _bubble_nodes: Dictionary = {}
var _authoring_enabled: bool = false
var _preview_event: TutorialEventDefinition


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 95
	_build_checklist()
	_bubble_layer = Control.new()
	_bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_layer)


func configure(director: TutorialDirector, camera: Camera3D, grid: GridManager) -> void:
	if _director != null and _director.presentation_changed.is_connected(_refresh):
		_director.presentation_changed.disconnect(_refresh)
	_director = director
	_camera = camera
	_grid = grid
	if _director != null:
		_director.presentation_changed.connect(_refresh)
	_refresh()


func set_authoring_enabled(enabled: bool) -> void:
	_authoring_enabled = enabled
	_refresh()


func set_preview_event(event: TutorialEventDefinition) -> void:
	_preview_event = event
	_refresh()


func _process(_delta: float) -> void:
	_update_world_positions()


func _build_checklist() -> void:
	_checklist_panel = PanelContainer.new()
	_checklist_panel.position = Vector2(24.0, 22.0)
	_checklist_panel.custom_minimum_size = Vector2(390.0, 0.0)
	_checklist_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.78)
	style.border_color = Color(1.0, 1.0, 1.0, 0.13)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	_checklist_panel.add_theme_stylebox_override("panel", style)
	add_child(_checklist_panel)
	_checklist_box = VBoxContainer.new()
	_checklist_box.add_theme_constant_override("separation", 7)
	_checklist_panel.add_child(_checklist_box)


func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_checklist()
	_refresh_bubbles()


func _refresh_checklist() -> void:
	for child in _checklist_box.get_children():
		child.free()
	var entries := _director.get_checklist_entries() if _director != null else []
	_checklist_panel.visible = not entries.is_empty()
	if entries.is_empty():
		return
	var title := Label.new()
	title.text = "当前目标"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.46))
	_checklist_box.add_child(title)
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var box := Label.new()
		box.text = "☑" if bool(entry["completed"]) else "□"
		box.custom_minimum_size = Vector2(24.0, 24.0)
		box.add_theme_font_size_override("font_size", 23)
		box.add_theme_color_override(
			"font_color",
			Color(0.39, 1.0, 0.57) if bool(entry["completed"]) else Color.WHITE
		)
		row.add_child(box)
		var description := Label.new()
		description.text = String(entry["description"])
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.add_theme_font_size_override("font_size", 17)
		description.add_theme_color_override(
			"font_color",
			Color(0.72, 0.78, 0.82) if bool(entry["completed"]) else Color(0.96, 0.98, 1.0)
		)
		row.add_child(description)
		_checklist_box.add_child(row)


func _refresh_bubbles() -> void:
	for child in _bubble_layer.get_children():
		child.free()
	_bubble_nodes.clear()
	var entries: Array[Dictionary] = []
	if _authoring_enabled and _preview_event != null:
		for index in range(_preview_event.bubbles.size()):
			var bubble := _preview_event.bubbles[index]
			if bubble != null:
				entries.append({"event": _preview_event, "bubble": bubble, "bubble_index": index})
	elif _director != null:
		entries = _director.get_visible_bubble_entries()
	for entry in entries:
		var event: TutorialEventDefinition = entry["event"]
		var definition: TutorialBubbleDefinition = entry["bubble"]
		var bubble_node := TutorialThoughtBubbleScript.new()
		bubble_node.configure(definition, _authoring_enabled)
		_bubble_layer.add_child(bubble_node)
		_bubble_nodes["%s:%d" % [event.event_id, int(entry["bubble_index"])]] = bubble_node
		_position_bubble(bubble_node, definition)


func _update_world_positions() -> void:
	for node in _bubble_nodes.values():
		var bubble := node as TutorialThoughtBubble
		if bubble != null and bubble.definition != null and (
			bubble.definition.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL
		):
			_position_bubble(bubble, bubble.definition)


func _position_bubble(node: TutorialThoughtBubble, definition: TutorialBubbleDefinition) -> void:
	if definition.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL and _camera != null and _grid != null:
		var world := _grid.cell_to_world(definition.world_cell)
		world.y = _grid.get_cell_world_height(definition.world_cell) + definition.world_height_offset
		node.position = _camera.unproject_position(world) + definition.offset - Vector2(node.size.x * 0.2, node.size.y)
	else:
		node.position = definition.screen_position
