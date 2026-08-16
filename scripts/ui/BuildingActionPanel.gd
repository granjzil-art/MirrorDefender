## Screen-projected contextual actions for the currently selected building.
class_name BuildingActionPanel
extends Control

signal upgrade_feedback_requested(screen_position: Vector2)

const DOWNGRADE_ICON_PATH := "res://assets/ui/building_actions/downgrade.png"
const UPGRADE_ICON: Texture2D = preload("res://assets/ui/building_actions/upgrade.png")

const ACTION_BUTTON_SIZE := Vector2(58.0, 58.0)
const COST_LABEL_SIZE := Vector2(92.0, 24.0)
const COST_LABEL_GAP := 4.0
const COIN_GOLD_COLOR := Color(1.0, 0.82, 0.24, 1.0)
const DOWNGRADE_BUTTON_OFFSET := Vector2(-70.0, -58.0)
const UPGRADE_BUTTON_OFFSET := Vector2(70.0, -58.0)

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Projection")
@export var screen_offset: Vector2 = Vector2(0.0, -14.0)

var _building_manager: BuildingManager
var _camera: Camera3D
var _selected_building: Building
var _downgrade_button: Button
var _upgrade_button: Button
var _downgrade_refund_label: Label
var _upgrade_cost_label: Label


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
		_building_manager.building_downgraded.connect(_on_building_downgraded)
		_building_manager.building_removed.connect(_on_building_removed)
	_refresh_selected_building()


func _build_interface() -> void:
	_downgrade_button = _add_action_button(
		"DowngradeButton",
		_load_icon_texture(DOWNGRADE_ICON_PATH),
		"降级并返还升到当前等级时支付的金币",
		DOWNGRADE_BUTTON_OFFSET
	)
	_upgrade_button = _add_action_button(
		"UpgradeButton",
		UPGRADE_ICON,
		"升级",
		UPGRADE_BUTTON_OFFSET
	)
	_downgrade_refund_label = _add_cost_label("DowngradeRefundLabel", DOWNGRADE_BUTTON_OFFSET)
	_upgrade_cost_label = _add_cost_label("UpgradeCostLabel", UPGRADE_BUTTON_OFFSET)
	_downgrade_button.pressed.connect(_on_downgrade_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)


func _load_icon_texture(path: String) -> Texture2D:
	var can_load_imported := not OS.has_feature("editor")
	if not can_load_imported:
		var import_config := ConfigFile.new()
		if import_config.load(path + ".import") == OK:
			var imported_path := String(import_config.get_value("remap", "path", ""))
			can_load_imported = not imported_path.is_empty() and FileAccess.file_exists(imported_path)
	if can_load_imported:
		var imported_texture := load(path) as Texture2D
		if imported_texture != null:
			return imported_texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


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
	_selected_building = _building_manager.get_selected_building() if _building_manager != null else null
	visible = feature_enabled and _selected_building != null
	_refresh_action_state()


func _refresh_action_state() -> void:
	var has_selection := _selected_building != null
	var can_upgrade := has_selection and _selected_building.can_upgrade()
	var can_downgrade := has_selection and _selected_building.can_downgrade()
	if _downgrade_button != null:
		_downgrade_button.visible = can_downgrade
		_downgrade_button.disabled = not can_downgrade
	if _downgrade_refund_label != null:
		_downgrade_refund_label.visible = can_downgrade
		_downgrade_refund_label.text = (
			"+%d" % roundi(_selected_building.get_downgrade_refund())
			if can_downgrade
			else ""
		)
	if _upgrade_button != null:
		_upgrade_button.visible = can_upgrade
		_upgrade_button.disabled = not can_upgrade
	if _upgrade_cost_label != null:
		_upgrade_cost_label.visible = can_upgrade
		_upgrade_cost_label.text = "-%d" % roundi(_selected_building.get_upgrade_cost()) if can_upgrade else ""


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
	if _building_manager.building_downgraded.is_connected(_on_building_downgraded):
		_building_manager.building_downgraded.disconnect(_on_building_downgraded)
	if _building_manager.building_removed.is_connected(_on_building_removed):
		_building_manager.building_removed.disconnect(_on_building_removed)


func _on_downgrade_pressed() -> void:
	if _building_manager != null:
		_building_manager.downgrade_selected()


func _on_upgrade_pressed() -> void:
	if _building_manager != null and not _building_manager.upgrade_selected():
		upgrade_feedback_requested.emit(get_viewport().get_mouse_position())


func _on_building_selected(_building: Building) -> void:
	_refresh_selected_building()


func _on_building_upgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	_refresh_selected_building()


func _on_building_downgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	_refresh_selected_building()


func _on_building_removed(_building: Building) -> void:
	_refresh_selected_building()
