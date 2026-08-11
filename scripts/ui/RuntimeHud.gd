## M6 production HUD composition root. It owns cards, inspection, global and
## economy information, time controls, pause, wave controls, and debug console.
class_name RuntimeHud
extends Control

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const TileInspectionServiceScript := preload("res://scripts/ui/TileInspectionService.gd")
const TileInspectorPanelScript := preload("res://scripts/ui/TileInspectorPanel.gd")
const WaveControlPanelScript := preload("res://scripts/ui/WaveControlPanel.gd")
const DebugConsoleScript := preload("res://scripts/ui/DebugConsole.gd")
const DebugOverlayPanelScript := preload("res://scripts/ui/DebugOverlayPanel.gd")
const DebugCommandRegistryScript := preload("res://scripts/debug/DebugCommandRegistry.gd")
const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")
const RuntimeStuffEditorPanelScript := preload("res://scripts/ui/RuntimeStuffEditorPanel.gd")

@onready var build_card_bar: BuildCardBarScript = $BuildCardBar
@onready var card_style_toggle: Button = $CardStyleToggle
@onready var tile_inspection_service: TileInspectionServiceScript = $TileInspectionService
@onready var tile_inspector_panel: TileInspectorPanelScript = $TileInspectorPanel
@onready var economy_panel: EconomyPanel = $EconomyPanel
@onready var global_info_panel: GlobalInfoPanel = $GlobalInfoPanel
@onready var time_control_panel: TimeControlPanel = $TimeControlPanel
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var defeat_menu: PauseMenu = $DefeatMenu
@onready var wave_control_panel: WaveControlPanelScript = $WaveControlPanel
@onready var debug_overlay_panel: DebugOverlayPanelScript = $DebugOverlayPanel
@onready var debug_console: DebugConsoleScript = $DebugConsole
@onready var runtime_stuff_editor_panel: RuntimeStuffEditorPanelScript = $RuntimeStuffEditorPanel

signal restart_level_requested
signal exit_level_requested
signal settings_changed(settings: Dictionary)
signal modal_state_changed(open: bool)
signal wave_paths_preview_requested(paths: Array)
signal wave_paths_preview_cleared

var _interaction: RuntimeInteractionControllerScript
var _time_controller: GameTimeControllerScript
var _last_modal_state: bool = false
var _stuff_editor_controller: Node
var _wave_manager: WaveManager
var _defeat_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_inspection_service.inspection_changed.connect(tile_inspector_panel.display_model)
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.exit_level_requested.connect(_on_exit_requested)
	pause_menu.settings_changed.connect(_on_pause_settings_changed)
	defeat_menu.restart_requested.connect(_on_restart_requested)
	defeat_menu.exit_level_requested.connect(_on_exit_requested)
	defeat_menu.settings_changed.connect(_on_defeat_settings_changed)
	wave_control_panel.restart_level_requested.connect(_on_restart_requested)
	wave_control_panel.exit_level_requested.connect(_on_exit_requested)
	wave_control_panel.paths_preview_requested.connect(_on_wave_paths_preview_requested)
	wave_control_panel.paths_preview_cleared.connect(_on_wave_paths_preview_cleared)
	debug_console.open_changed.connect(_on_debug_console_open_changed)
	card_style_toggle.pressed.connect(_on_card_style_toggle_pressed)
	_refresh_card_style_toggle()


func configure(
	interaction: RuntimeInteractionControllerScript,
	time_controller: GameTimeControllerScript,
	resource_manager: ResourceManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	slot_count: int = 6,
	stuff_editor_controller: Node = null
) -> void:
	_disconnect_sources()
	_interaction = interaction
	_time_controller = time_controller
	var cards: Array[BuildingDefinition] = [
		building_manager.arrow_tower,
		building_manager.laser_tower,
		building_manager.pulse_laser_tower,
		building_manager.crossbow_tower,
		building_manager.mace_tower,
		null,
		null,
	]
	build_card_bar.configure(
		resource_manager,
		mirror_manager.copy_mirror_definition,
		cards,
		slot_count,
		mirror_manager.reflect_mirror_definition,
		mirror_manager
	)
	build_card_bar.building_card_selected.connect(_on_building_card_selected)
	build_card_bar.mirror_card_selected.connect(_on_mirror_card_selected)
	build_card_bar.reflect_mirror_card_selected.connect(_on_reflect_mirror_card_selected)
	economy_panel.configure(resource_manager)
	time_control_panel.configure(_time_controller)
	pause_menu.configure(get_window())
	defeat_menu.settings_path = pause_menu.settings_path
	defeat_menu.apply_runtime_settings = pause_menu.apply_runtime_settings
	defeat_menu.configure(get_window(), pause_menu.get_runtime_settings())
	_stuff_editor_controller = stuff_editor_controller
	runtime_stuff_editor_panel.configure(_stuff_editor_controller)
	if _stuff_editor_controller != null and _stuff_editor_controller.has_signal(&"active_changed"):
		_stuff_editor_controller.connect(&"active_changed", _on_stuff_editor_active_changed)
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
	_on_stuff_editor_active_changed(
		bool(stuff_editor_controller.call("is_active"))
		if stuff_editor_controller != null and stuff_editor_controller.has_method("is_active")
		else false
	)


func configure_global_info(
	resource_manager: ResourceManager,
	wave_manager: WaveManager,
	base_core: BaseCore
) -> void:
	global_info_panel.configure(resource_manager, wave_manager, base_core)


func configure_wave_controls(wave_manager: WaveManager) -> void:
	if _wave_manager != null and _wave_manager.defeat.is_connected(_on_defeat):
		_wave_manager.defeat.disconnect(_on_defeat)
	_wave_manager = wave_manager
	wave_control_panel.configure(wave_manager)
	if _wave_manager != null:
		_wave_manager.defeat.connect(_on_defeat)


func configure_debug_console(
	command_registry: DebugCommandRegistryScript,
	category_registry: DebugCategoryRegistryScript
) -> void:
	debug_console.configure(command_registry, category_registry)
	debug_overlay_panel.configure(category_registry)


func configure_inspection(
	grid_manager: GridManager,
	tile_manager: TileManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	tile_effect_system: TileEffectSystem,
	stuff_manager: Node = null,
	terrain_manager: Node = null
) -> void:
	tile_inspection_service.configure(
		grid_manager,
		tile_manager,
		building_manager,
		mirror_manager,
		tile_effect_system,
		stuff_manager,
		terrain_manager
	)
	_sync_world_selection()


func apply_level_configuration(level: LevelResource, source_path: String = "") -> void:
	if level != null:
		build_card_bar.set_slot_count(level.building_card_slot_count)
	global_info_panel.set_level_context(level, source_path)
	wave_control_panel.set_level(level)


func is_modal_open() -> bool:
	return (defeat_menu != null and defeat_menu.is_open()) or (
		pause_menu != null and pause_menu.is_open()
	) or (
		debug_console != null and debug_console.is_open()
	)


func is_defeat_menu_open() -> bool:
	return defeat_menu != null and defeat_menu.is_open()


func get_settings_snapshot() -> Dictionary:
	return pause_menu.get_settings_snapshot() if pause_menu != null else {}


func is_debug_console_open() -> bool:
	return debug_console != null and debug_console.is_open()


func close_top_modal() -> void:
	if is_defeat_menu_open():
		return
	if debug_console != null and debug_console.is_open():
		debug_console.close_console()
		return
	close_pause_menu()


func close_pause_menu() -> void:
	if _time_controller != null:
		_time_controller.set_paused(false)
	elif pause_menu != null:
		pause_menu.close_menu()
		_sync_modal_state()


func prepare_for_level_transition() -> void:
	_defeat_active = false
	wave_control_panel.clear_hover_preview()
	if defeat_menu != null:
		defeat_menu.close_menu()
	if debug_console != null:
		debug_console.close_console()
	if _time_controller != null:
		_time_controller.reset_runtime_state()
	elif pause_menu != null:
		pause_menu.close_menu()
	_sync_modal_state()


func _on_building_card_selected(definition: BuildingDefinition) -> void:
	if _interaction != null and _interaction.select_building_card(definition):
		build_card_bar.set_selected_building(definition)


func _on_mirror_card_selected() -> void:
	if _interaction != null and _interaction.select_copy_mirror_card():
		build_card_bar.set_mirror_selected(true)


func _on_reflect_mirror_card_selected() -> void:
	if _interaction != null and _interaction.select_reflect_mirror_card():
		build_card_bar.set_reflect_mirror_selected(true)


func _on_mode_changed(mode: RuntimeInteractionControllerScript.Mode) -> void:
	if mode == RuntimeInteractionControllerScript.Mode.SELECT:
		build_card_bar.clear_selection()
	elif mode == RuntimeInteractionControllerScript.Mode.PLACE_COPY_MIRROR:
		build_card_bar.set_mirror_selected(true)
	elif mode == RuntimeInteractionControllerScript.Mode.PLACE_REFLECT_MIRROR:
		build_card_bar.set_reflect_mirror_selected(true)
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
	if _defeat_active:
		pause_menu.close_menu()
		defeat_menu.open_menu()
		_sync_modal_state()
		return
	if paused:
		pause_menu.open_menu()
	else:
		pause_menu.close_menu()
	_sync_modal_state()


func _on_debug_console_open_changed(_open: bool) -> void:
	_sync_modal_state()


func _on_stuff_editor_active_changed(active: bool) -> void:
	build_card_bar.visible = not active
	card_style_toggle.visible = not active


func _on_card_style_toggle_pressed() -> void:
	var next_mode := (
		BuildCardBarScript.CardVisualMode.FULL_ARTWORK
		if build_card_bar.get_card_visual_mode() == BuildCardBarScript.CardVisualMode.PROCEDURAL_MIRROR
		else BuildCardBarScript.CardVisualMode.PROCEDURAL_MIRROR
	)
	build_card_bar.set_card_visual_mode(next_mode)
	_refresh_card_style_toggle()


func _refresh_card_style_toggle() -> void:
	if card_style_toggle == null or build_card_bar == null:
		return
	var uses_full_art := (
		build_card_bar.get_card_visual_mode() == BuildCardBarScript.CardVisualMode.FULL_ARTWORK
	)
	card_style_toggle.text = "卡槽：原画卡面" if uses_full_art else "卡槽：程序镜面"
	card_style_toggle.tooltip_text = (
		"当前使用完整卡面素材；点击切换到程序镜面"
		if uses_full_art
		else "当前使用程序镜面；点击切换到完整卡面素材"
	)


func _sync_modal_state() -> void:
	var open := is_modal_open()
	wave_control_panel.set_preview_suppressed(open)
	if _last_modal_state == open:
		return
	_last_modal_state = open
	modal_state_changed.emit(open)


func _on_restart_requested() -> void:
	restart_level_requested.emit()


func _on_exit_requested() -> void:
	exit_level_requested.emit()


func _on_defeat() -> void:
	_defeat_active = true
	defeat_menu.open_menu()
	pause_menu.close_menu()
	if debug_console != null:
		debug_console.close_console()
	wave_control_panel.clear_hover_preview()
	_sync_modal_state()
	if _time_controller != null:
		_time_controller.set_paused(true)


func _on_pause_settings_changed(settings: Dictionary) -> void:
	defeat_menu.sync_settings_controls()
	settings_changed.emit(settings)


func _on_defeat_settings_changed(settings: Dictionary) -> void:
	pause_menu.sync_settings_controls()
	settings_changed.emit(settings)


func _on_wave_paths_preview_requested(paths: Array) -> void:
	wave_paths_preview_requested.emit(paths)


func _on_wave_paths_preview_cleared() -> void:
	wave_paths_preview_cleared.emit()


func _disconnect_sources() -> void:
	if build_card_bar != null:
		if build_card_bar.building_card_selected.is_connected(_on_building_card_selected):
			build_card_bar.building_card_selected.disconnect(_on_building_card_selected)
		if build_card_bar.mirror_card_selected.is_connected(_on_mirror_card_selected):
			build_card_bar.mirror_card_selected.disconnect(_on_mirror_card_selected)
		if build_card_bar.reflect_mirror_card_selected.is_connected(_on_reflect_mirror_card_selected):
			build_card_bar.reflect_mirror_card_selected.disconnect(_on_reflect_mirror_card_selected)
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
	if _stuff_editor_controller != null:
		var callback := Callable(self, "_on_stuff_editor_active_changed")
		if _stuff_editor_controller.is_connected(&"active_changed", callback):
			_stuff_editor_controller.disconnect(&"active_changed", callback)
	_stuff_editor_controller = null
	if _wave_manager != null and _wave_manager.defeat.is_connected(_on_defeat):
		_wave_manager.defeat.disconnect(_on_defeat)
	_wave_manager = null
