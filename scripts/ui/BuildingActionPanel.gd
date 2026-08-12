## Screen-projected contextual actions for the currently selected building.
class_name BuildingActionPanel
extends Control

const INFO_ICON: Texture2D = preload("res://assets/ui/building_actions/exclamation-mark.png")
const UPGRADE_ICON: Texture2D = preload("res://assets/ui/building_actions/upgrade.png")
const SELL_ICON: Texture2D = preload("res://assets/ui/building_actions/dollar.png")

const ACTION_BUTTON_SIZE := Vector2(58.0, 58.0)
const COST_LABEL_SIZE := Vector2(92.0, 24.0)
const COST_LABEL_GAP := 4.0
const COIN_GOLD_COLOR := Color(1.0, 0.82, 0.24, 1.0)
const INFO_PAGE_SIZE := Vector2(360.0, 300.0)
const INFO_BUTTON_OFFSET := Vector2(-70.0, -58.0)
const UPGRADE_BUTTON_OFFSET := Vector2(0.0, -128.0)
const SELL_BUTTON_OFFSET := Vector2(70.0, -58.0)
const INFO_PAGE_OFFSET := Vector2(-INFO_PAGE_SIZE.x * 0.5, -450.0)
## The supplied dollar icon has a 37 px transparent inset on every side.
## Cropping it at display time makes all three visible circles the same size
## without modifying the source artwork.
const SELL_ICON_REGION := Rect2(37.0, 37.0, 406.0, 406.0)

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Projection")
@export var screen_offset: Vector2 = Vector2(0.0, -14.0)

var _building_manager: BuildingManager
var _camera: Camera3D
var _selected_building: Building
var _info_button: Button
var _upgrade_button: Button
var _sell_button: Button
var _upgrade_cost_label: Label
var _sell_refund_label: Label
var _info_page: PanelContainer
var _info_title: Label
var _info_description: Label


func _ready() -> void:
	size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Right-drag may start over these contextual controls without blocking the
	# runtime camera orbit. Their left-click actions remain normal GUI input.
	set_meta(&"allows_camera_orbit", true)
	# CameraController also updates in _process. Run after it so the projection
	# always uses the camera transform that will render this frame.
	process_priority = 1000
	visible = false
	_build_interface()


func _process(_delta: float) -> void:
	_update_projection()


func configure(building_manager: BuildingManager, camera: Camera3D) -> void:
	_disconnect_manager()
	_building_manager = building_manager
	_camera = camera
	if _building_manager != null:
		_building_manager.building_selected.connect(_on_building_selected)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		_building_manager.building_removed.connect(_on_building_removed)
	_refresh_selected_building()


func _build_interface() -> void:
	_build_info_page()
	_info_button = _add_action_button(
		"InfoButton",
		INFO_ICON,
		"说明",
		INFO_BUTTON_OFFSET
	)
	_upgrade_button = _add_action_button(
		"UpgradeButton",
		UPGRADE_ICON,
		"升级",
		UPGRADE_BUTTON_OFFSET
	)
	_sell_button = _add_action_button(
		"SellButton",
		_make_atlas_texture(SELL_ICON, SELL_ICON_REGION),
		"售卖并返还当前等级配置的资源",
		SELL_BUTTON_OFFSET
	)
	_upgrade_cost_label = _add_cost_label("UpgradeCostLabel", UPGRADE_BUTTON_OFFSET)
	_sell_refund_label = _add_cost_label("SellRefundLabel", SELL_BUTTON_OFFSET)
	_info_button.pressed.connect(_on_info_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)


func _build_info_page() -> void:
	_info_page = PanelContainer.new()
	_info_page.name = "InfoPage"
	_info_page.position = INFO_PAGE_OFFSET
	_info_page.custom_minimum_size = INFO_PAGE_SIZE
	_info_page.size = INFO_PAGE_SIZE
	_info_page.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_page.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.09, 0.96)
	panel_style.border_color = Color(0.32, 0.68, 1.0, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_bottom = 12.0
	_info_page.add_theme_stylebox_override("panel", panel_style)
	add_child(_info_page)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_info_page.add_child(content)

	_info_title = Label.new()
	_info_title.name = "InfoTitle"
	_info_title.add_theme_font_size_override("font_size", 18)
	_info_title.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	content.add_child(_info_title)

	_info_description = Label.new()
	_info_description.name = "InfoDescription"
	_info_description.custom_minimum_size = Vector2(INFO_PAGE_SIZE.x - 28.0, 236.0)
	_info_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_description.add_theme_font_size_override("font_size", 15)
	_info_description.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	content.add_child(_info_description)


func _add_action_button(
	node_name: String,
	icon_texture: Texture2D,
	tooltip: String,
	center_position: Vector2
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tooltip
	button.custom_minimum_size = ACTION_BUTTON_SIZE
	button.size = ACTION_BUTTON_SIZE
	button.position = center_position - ACTION_BUTTON_SIZE * 0.5
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)

	# Button.icon contributes the source texture's native dimensions to the
	# control minimum size. A child TextureRect keeps every clickable action at
	# the exact same authored size regardless of the PNG canvas dimensions.
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.texture = icon_texture
	button.add_child(icon_rect)
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button


func _make_atlas_texture(source: Texture2D, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = region
	return texture


func _add_cost_label(node_name: String, button_center: Vector2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.custom_minimum_size = COST_LABEL_SIZE
	label.size = COST_LABEL_SIZE
	label.position = Vector2(
		button_center.x - COST_LABEL_SIZE.x * 0.5,
		button_center.y - ACTION_BUTTON_SIZE.y * 0.5 - COST_LABEL_GAP - COST_LABEL_SIZE.y
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COIN_GOLD_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.035, 0.015, 0.96))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	return label


func _refresh_selected_building() -> void:
	var previous_building := _selected_building
	_selected_building = _building_manager.get_selected_building() if _building_manager != null else null
	if previous_building != _selected_building and _info_page != null:
		_info_page.visible = false
	visible = feature_enabled and _selected_building != null
	_refresh_action_state()
	_refresh_info_content()


func _refresh_action_state() -> void:
	var has_selection := _selected_building != null
	var can_upgrade := has_selection and _selected_building.can_upgrade()
	if _upgrade_button != null:
		_upgrade_button.visible = can_upgrade
		_upgrade_button.disabled = not can_upgrade
	if _upgrade_cost_label != null:
		_upgrade_cost_label.visible = can_upgrade
		_upgrade_cost_label.text = "-%d" % roundi(_selected_building.get_upgrade_cost()) if can_upgrade else ""
	if _info_button != null:
		_info_button.disabled = not has_selection
	if _sell_button != null:
		_sell_button.disabled = not has_selection
	if _sell_refund_label != null:
		_sell_refund_label.visible = has_selection
		_sell_refund_label.text = "+%d" % roundi(_selected_building.get_refund_amount()) if has_selection else ""


func _refresh_info_content() -> void:
	if _info_title == null or _info_description == null:
		return
	if _selected_building == null or _selected_building.definition == null:
		_info_title.text = "建筑说明"
		_info_description.text = ""
		return
	var definition := _selected_building.definition
	_info_title.text = "%s · 说明" % definition.get_resolved_inspection_display_name()
	_info_description.text = definition.get_formatted_inspection_description()


func _update_projection() -> void:
	if not feature_enabled or _selected_building == null or not is_instance_valid(_selected_building):
		visible = false
		return
	if _camera == null or not is_instance_valid(_camera):
		visible = false
		return
	var anchor := _selected_building.get_action_anchor()
	if _camera.is_position_behind(anchor):
		visible = false
		return
	# The panel origin is the building's projected action anchor. Child controls
	# use fixed offsets from this point, so camera movement cannot introduce
	# clamping drift between the building and its contextual actions.
	position = _camera.unproject_position(anchor) + screen_offset
	visible = true


func _disconnect_manager() -> void:
	if _building_manager == null:
		return
	if _building_manager.building_selected.is_connected(_on_building_selected):
		_building_manager.building_selected.disconnect(_on_building_selected)
	if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
		_building_manager.building_upgraded.disconnect(_on_building_upgraded)
	if _building_manager.building_removed.is_connected(_on_building_removed):
		_building_manager.building_removed.disconnect(_on_building_removed)


func _on_info_pressed() -> void:
	if _info_page == null or _selected_building == null:
		return
	_refresh_info_content()
	_info_page.visible = not _info_page.visible


func _on_upgrade_pressed() -> void:
	if _building_manager != null:
		_building_manager.upgrade_selected()


func _on_sell_pressed() -> void:
	if _building_manager != null:
		_building_manager.remove_selected_building()


func _on_building_selected(_building: Building) -> void:
	_refresh_selected_building()


func _on_building_upgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	_refresh_selected_building()


func _on_building_removed(_building: Building) -> void:
	_refresh_selected_building()
