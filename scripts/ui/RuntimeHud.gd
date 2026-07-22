## M6 production HUD composition root. Batches 1-3 own cards, inspection,
## global/economy information, time controls, and the pause modal.
class_name RuntimeHud
extends Control

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const TileInspectionServiceScript := preload("res://scripts/ui/TileInspectionService.gd")
const TileInspectorPanelScript := preload("res://scripts/ui/TileInspectorPanel.gd")

@onready var build_card_bar: BuildCardBarScript = $BuildCardBar
@onready var tile_inspection_service: TileInspectionServiceScript = $TileInspectionService
@onready var tile_inspector_panel: TileInspectorPanelScript = $TileInspectorPanel
@onready var economy_panel: EconomyPanel = $EconomyPanel
@onready var global_info_panel: GlobalInfoPanel = $GlobalInfoPanel
@onready var time_control_panel: TimeControlPanel = $TimeControlPanel
@onready var pause_menu: PauseMenu = $PauseMenu

signal restart_level_requested
signal exit_game_requested
signal modal_state_changed(open: bool)

var _interaction: RuntimeInteractionControllerScript
var _time_controller: GameTimeControllerScript


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_inspection_service.inspection_changed.connect(tile_inspector_panel.display_model)
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.exit_requested.connect(_on_exit_requested)


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
	economy_panel.configure(resource_manager)
	time_control_panel.configure(_time_controller)
	pause_menu.configure(get_window())
	if _interaction != null:
		_interaction.mode_changed.connect(_on_mode_changed)
		_interaction.placement_resolved.connect(_on_placement_resolved)
		_interaction.status_changed.connect(_on_status_changed)
		_interaction.world_selection_changed.connect(_on_world_selection_changed)
	if _time_controller != null:
		_time_controller.paused_changed.connect(_on_paused_changed)
	_on_mode_changed(_interaction.get_mode() if _interaction != null else RuntimeInteractionControllerScript.Mode.SELECT)
	_sync_world_selection()
	_on_paused_changed(_time_controller.is_paused() if _time_controller != null else false)


func configure_global_info(
	resource_manager: ResourceManager,
	wave_manager: WaveManager,
	base_core: BaseCore
) -> void:
	global_info_panel.configure(resource_manager, wave_manager, base_core)


func configure_inspection(
	grid_manager: GridManager,
	tile_manager: TileManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	tile_effect_system: TileEffectSystem
) -> void:
	tile_inspection_service.configure(
		grid_manager,
		tile_manager,
		building_manager,
		mirror_manager,
		tile_effect_system
	)
	_sync_world_selection()


func apply_level_configuration(level: LevelResource, source_path: String = "") -> void:
	if level != null:
		build_card_bar.set_slot_count(level.building_card_slot_count)
	global_info_panel.set_level_context(level, source_path)


func is_modal_open() -> bool:
	return pause_menu != null and pause_menu.is_open()


func close_pause_menu() -> void:
	if _time_controller != null:
		_time_controller.set_paused(false)
	elif pause_menu != null:
		pause_menu.close_menu()
		modal_state_changed.emit(false)


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


func _on_world_selection_changed(has_cell: bool, cell: Vector3i, edge_id: String) -> void:
	tile_inspection_service.set_selected_cell(has_cell, cell, edge_id)


func _sync_world_selection() -> void:
	if _interaction == null:
		tile_inspection_service.clear_selection()
		return
	tile_inspection_service.set_selected_cell(
		_interaction.has_world_selection(),
		_interaction.get_world_selection_cell(),
		_interaction.get_world_selection_edge_id()
	)


func _on_paused_changed(paused: bool) -> void:
	if pause_menu == null:
		return
	if paused:
		pause_menu.open_menu()
	else:
		pause_menu.close_menu()
	modal_state_changed.emit(pause_menu.is_open())


func _on_restart_requested() -> void:
	restart_level_requested.emit()


func _on_exit_requested() -> void:
	exit_game_requested.emit()


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
		if _interaction.world_selection_changed.is_connected(_on_world_selection_changed):
			_interaction.world_selection_changed.disconnect(_on_world_selection_changed)
	if _time_controller != null:
		if _time_controller.paused_changed.is_connected(_on_paused_changed):
			_time_controller.paused_changed.disconnect(_on_paused_changed)
