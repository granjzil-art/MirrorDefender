## M6 production HUD composition root. Batch 1 owns cards and tactical slow.
class_name RuntimeHud
extends Control

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")

@onready var build_card_bar: BuildCardBarScript = $BuildCardBar
@onready var tactical_slow_button: Button = $TacticalSlowButton

var _interaction: RuntimeInteractionControllerScript
var _time_controller: GameTimeControllerScript


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tactical_slow_button.gui_input.connect(_on_button_gui_input)
	tactical_slow_button.pressed.connect(_on_tactical_slow_pressed)


func configure(
	interaction: RuntimeInteractionControllerScript,
	time_controller: GameTimeControllerScript,
	resource_manager: ResourceManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	slot_count: int = 6
) -> void:
	_disconnect_sources()
	_interaction = interaction
	_time_controller = time_controller
	var cards: Array[BuildingDefinition] = []
	for definition in [building_manager.arrow_tower, building_manager.laser_tower, building_manager.barrier]:
		if definition is BuildingDefinition:
			cards.append(definition)
	build_card_bar.configure(
		resource_manager,
		mirror_manager.copy_mirror_definition,
		cards,
		slot_count
	)
	build_card_bar.building_card_selected.connect(_on_building_card_selected)
	build_card_bar.mirror_card_selected.connect(_on_mirror_card_selected)
	build_card_bar.cancel_requested.connect(_on_cancel_requested)
	if _interaction != null:
		_interaction.mode_changed.connect(_on_mode_changed)
		_interaction.placement_resolved.connect(_on_placement_resolved)
		_interaction.status_changed.connect(_on_status_changed)
	if _time_controller != null:
		_time_controller.tactical_slow_enabled_changed.connect(_on_slow_enabled_changed)
		_time_controller.time_scale_changed.connect(_on_time_scale_changed)
	_refresh_slow_button()
	_on_mode_changed(_interaction.get_mode() if _interaction != null else RuntimeInteractionControllerScript.Mode.SELECT)


func apply_level_configuration(level: LevelResource) -> void:
	if level != null:
		build_card_bar.set_slot_count(level.building_card_slot_count)


func _on_building_card_selected(definition: BuildingDefinition) -> void:
	if _interaction != null and _interaction.select_building_card(definition):
		build_card_bar.set_selected_building(definition)


func _on_mirror_card_selected() -> void:
	if _interaction != null and _interaction.select_copy_mirror_card():
		build_card_bar.set_mirror_selected(true)


func _on_cancel_requested() -> void:
	if _interaction != null:
		_interaction.cancel_to_select(true)
	build_card_bar.show_status("已取消")


func _on_mode_changed(mode: RuntimeInteractionControllerScript.Mode) -> void:
	if mode == RuntimeInteractionControllerScript.Mode.SELECT:
		build_card_bar.clear_selection()
	elif mode == RuntimeInteractionControllerScript.Mode.PLACE_COPY_MIRROR:
		build_card_bar.set_mirror_selected(true)
	elif _interaction != null:
		build_card_bar.set_selected_building(_interaction.get_selected_definition())


func _on_placement_resolved(success: bool, reason: String) -> void:
	build_card_bar.show_status(reason, not success)


func _on_status_changed(message: String) -> void:
	if not message.is_empty():
		build_card_bar.show_status(message)


func _on_tactical_slow_pressed() -> void:
	if _time_controller != null:
		_time_controller.set_tactical_slow_enabled(tactical_slow_button.button_pressed)


func _on_slow_enabled_changed(_enabled: bool) -> void:
	_refresh_slow_button()


func _on_time_scale_changed(_scale: float) -> void:
	_refresh_slow_button()


func _refresh_slow_button() -> void:
	if tactical_slow_button == null:
		return
	var enabled: bool = _time_controller != null and _time_controller.tactical_slow_enabled
	tactical_slow_button.set_pressed_no_signal(enabled)
	var scale: float = _time_controller.get_effective_scale() if _time_controller != null else 1.0
	tactical_slow_button.text = "战术慢放 开 · %.1fx" % scale if enabled else "战术慢放 关"


func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel_requested()
		get_viewport().set_input_as_handled()


func _disconnect_sources() -> void:
	if build_card_bar != null:
		if build_card_bar.building_card_selected.is_connected(_on_building_card_selected):
			build_card_bar.building_card_selected.disconnect(_on_building_card_selected)
		if build_card_bar.mirror_card_selected.is_connected(_on_mirror_card_selected):
			build_card_bar.mirror_card_selected.disconnect(_on_mirror_card_selected)
		if build_card_bar.cancel_requested.is_connected(_on_cancel_requested):
			build_card_bar.cancel_requested.disconnect(_on_cancel_requested)
	if _interaction != null:
		if _interaction.mode_changed.is_connected(_on_mode_changed):
			_interaction.mode_changed.disconnect(_on_mode_changed)
		if _interaction.placement_resolved.is_connected(_on_placement_resolved):
			_interaction.placement_resolved.disconnect(_on_placement_resolved)
		if _interaction.status_changed.is_connected(_on_status_changed):
			_interaction.status_changed.disconnect(_on_status_changed)
	if _time_controller != null:
		if _time_controller.tactical_slow_enabled_changed.is_connected(_on_slow_enabled_changed):
			_time_controller.tactical_slow_enabled_changed.disconnect(_on_slow_enabled_changed)
		if _time_controller.time_scale_changed.is_connected(_on_time_scale_changed):
			_time_controller.time_scale_changed.disconnect(_on_time_scale_changed)
