## M6 production HUD composition root. It owns cards, global/economy
## information, time controls, pause, wave controls, and debug console.
class_name RuntimeHud
extends Control

@export_group("Victory Rating")
@export_range(0.0, 1000.0, 0.1, "or_greater") var one_star_max_remaining_hp: float = 5.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var two_star_max_remaining_hp: float = 15.0

@export_group("Action Feedback")
@export_range(0.0, 2.0, 0.05, "or_greater") var feedback_hold_duration: float = 0.2
@export_range(0.05, 3.0, 0.05, "or_greater") var feedback_fade_duration: float = 1.0
@export var feedback_offset: Vector2 = Vector2(0.0, -12.0)

@export_group("Building Cards")
@export var building_cards_visible_by_default: bool = false

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const TowerCodexPanelScript := preload("res://scripts/ui/TowerCodexPanel.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const WaveControlPanelScript := preload("res://scripts/ui/WaveControlPanel.gd")
const DebugConsoleScript := preload("res://scripts/ui/DebugConsole.gd")
const DebugOverlayPanelScript := preload("res://scripts/ui/DebugOverlayPanel.gd")
const DebugCommandRegistryScript := preload("res://scripts/debug/DebugCommandRegistry.gd")
const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")
const RuntimeStuffEditorPanelScript := preload("res://scripts/ui/RuntimeStuffEditorPanel.gd")
const TowerArrivalPulseScript := preload("res://scripts/presentation/TowerArrivalPulse.gd")

@onready var build_card_bar: BuildCardBarScript = $BuildCardBar
@onready var tower_codex_panel: TowerCodexPanelScript = $TowerCodexPanel
@onready var card_style_toggle: Button = $CardStyleToggle
@onready var economy_panel: EconomyPanel = $GlobalInfoPanel/StatsGrid/EconomyPanel
@onready var global_info_panel: GlobalInfoPanel = $GlobalInfoPanel
@onready var time_control_panel: TimeControlPanel = $TimeControlPanel
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var defeat_menu: PauseMenu = $DefeatMenu
@onready var victory_menu: PauseMenu = $VictoryMenu
@onready var confirmation_dialog: Control = $ConfirmationDialog
@onready var confirmation_message: Label = $ConfirmationDialog/Shade/ModalPanel/Content/Message
@onready var confirmation_cancel_button: Button = $ConfirmationDialog/Shade/ModalPanel/Content/Buttons/CancelButton
@onready var confirmation_confirm_button: Button = $ConfirmationDialog/Shade/ModalPanel/Content/Buttons/ConfirmButton
@onready var wave_control_panel: WaveControlPanelScript = $WaveControlPanel
@onready var debug_overlay_panel: DebugOverlayPanelScript = $DebugOverlayPanel
@onready var debug_console: DebugConsoleScript = $DebugConsole
@onready var runtime_stuff_editor_panel: RuntimeStuffEditorPanelScript = $RuntimeStuffEditorPanel
@onready var action_feedback: Label = $ActionFeedback
@onready var tower_reward_popup: TowerRewardPopup = $TowerRewardPopup

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
var _base_core: BaseCore
var _defeat_active: bool = false
var _victory_active: bool = false
var _victory_star_count: int = 0
var _debug_tools_enabled: bool = false
var _debug_console_available: bool = true
var _runtime_parameter_editor: Node
var _debug_category_registry: DebugCategoryRegistryScript
var _feedback_tween: Tween
var _pending_confirmation_action: ConfirmationAction = ConfirmationAction.NONE
var _confirmation_restore_paused: bool = false
var _tutorial_director: TutorialDirector
var _tower_reward_queue: Array[Dictionary] = []
var _active_tower_reward_building: Building
var _tower_reward_restore_paused: bool = false

enum ConfirmationAction {
	NONE,
	RESTART_LEVEL,
	EXIT_LEVEL,
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.exit_level_requested.connect(_on_exit_requested)
	pause_menu.settings_changed.connect(_on_pause_settings_changed)
	defeat_menu.restart_requested.connect(_on_restart_requested)
	defeat_menu.exit_level_requested.connect(_on_exit_requested)
	defeat_menu.settings_changed.connect(_on_result_settings_changed)
	victory_menu.restart_requested.connect(_on_restart_requested)
	victory_menu.exit_level_requested.connect(_on_exit_requested)
	confirmation_cancel_button.pressed.connect(_on_confirmation_cancelled)
	confirmation_confirm_button.pressed.connect(_on_confirmation_confirmed)
	tower_reward_popup.confirmed.connect(_on_tower_reward_confirmed)
	wave_control_panel.restart_level_requested.connect(_on_restart_requested)
	wave_control_panel.exit_level_requested.connect(_on_exit_requested)
	wave_control_panel.next_wave_released_by_player.connect(_on_next_wave_released_by_player)
	wave_control_panel.paths_preview_requested.connect(_on_wave_paths_preview_requested)
	wave_control_panel.paths_preview_cleared.connect(_on_wave_paths_preview_cleared)
	debug_console.open_changed.connect(_on_debug_console_open_changed)
	runtime_stuff_editor_panel.debug_console_requested.connect(_on_debug_console_requested)
	runtime_stuff_editor_panel.runtime_parameter_editor_requested.connect(_on_runtime_parameter_editor_requested)
	card_style_toggle.pressed.connect(_on_card_style_toggle_pressed)
	build_card_bar.set_building_cards_visible(building_cards_visible_by_default)
	_refresh_card_style_toggle()
	set_debug_tools_enabled(_debug_tools_enabled)


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
	var codex_cards: Array[BuildingDefinition] = [
		building_manager.arrow_tower,
		building_manager.laser_tower,
		building_manager.crossbow_tower,
		building_manager.pulse_laser_tower,
	]
	tower_codex_panel.configure(codex_cards)
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
	victory_menu.settings_path = pause_menu.settings_path
	victory_menu.apply_runtime_settings = pause_menu.apply_runtime_settings
	victory_menu.configure(get_window(), pause_menu.get_runtime_settings())
	_stuff_editor_controller = stuff_editor_controller
	runtime_stuff_editor_panel.configure(_stuff_editor_controller)
	if _stuff_editor_controller != null and _stuff_editor_controller.has_signal(&"active_changed"):
		_stuff_editor_controller.connect(&"active_changed", _on_stuff_editor_active_changed)
	if _interaction != null:
		_interaction.mode_changed.connect(_on_mode_changed)
	if _time_controller != null:
		_time_controller.paused_changed.connect(_on_paused_changed)
	_on_mode_changed(_interaction.get_mode() if _interaction != null else RuntimeInteractionControllerScript.Mode.SELECT)
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
	_base_core = base_core
	global_info_panel.configure(resource_manager, wave_manager, base_core)


func configure_wave_controls(wave_manager: WaveManager) -> void:
	_disconnect_wave_result_signals()
	_wave_manager = wave_manager
	wave_control_panel.configure(wave_manager)
	if _wave_manager != null:
		_wave_manager.defeat.connect(_on_defeat)
		_wave_manager.victory.connect(_on_victory)


func configure_debug_console(
	command_registry: DebugCommandRegistryScript,
	category_registry: DebugCategoryRegistryScript
) -> void:
	_debug_category_registry = category_registry
	debug_console.configure(command_registry, category_registry)
	debug_overlay_panel.configure(category_registry)
	_debug_category_registry.set_suspended(not _debug_tools_enabled)


func configure_debug_tool_entries(
	debug_console_available: bool,
	runtime_parameter_editor: Node
) -> void:
	_debug_console_available = debug_console_available
	_runtime_parameter_editor = runtime_parameter_editor
	runtime_stuff_editor_panel.configure_debug_entries(
		_debug_console_available,
		_runtime_parameter_editor != null
	)
	set_debug_tools_enabled(_debug_tools_enabled)


func configure_tutorial_rewards(director: TutorialDirector) -> void:
	if (
		_tutorial_director != null
		and _tutorial_director.automatic_tower_placed.is_connected(_on_automatic_tower_placed)
	):
		_tutorial_director.automatic_tower_placed.disconnect(_on_automatic_tower_placed)
	_tutorial_director = director
	if _tutorial_director != null:
		_tutorial_director.automatic_tower_placed.connect(_on_automatic_tower_placed)


func set_debug_tools_enabled(enabled: bool) -> void:
	_debug_tools_enabled = enabled
	debug_console.set_feature_enabled(_debug_console_available and _debug_tools_enabled)
	debug_overlay_panel.feature_enabled = _debug_console_available and _debug_tools_enabled
	if _debug_category_registry != null:
		_debug_category_registry.set_suspended(not _debug_tools_enabled)
	debug_overlay_panel.refresh_now()
	runtime_stuff_editor_panel.set_debug_tools_enabled(_debug_tools_enabled)
	card_style_toggle.visible = _debug_tools_enabled and not (
		_stuff_editor_controller != null
		and _stuff_editor_controller.has_method("is_active")
		and bool(_stuff_editor_controller.call("is_active"))
	)
	if _runtime_parameter_editor != null and _runtime_parameter_editor.has_method("set_feature_enabled"):
		_runtime_parameter_editor.call("set_feature_enabled", _debug_tools_enabled)


func are_debug_tools_enabled() -> bool:
	return _debug_tools_enabled


func set_building_cards_visible(visible: bool) -> void:
	build_card_bar.set_building_cards_visible(visible)


func toggle_building_cards() -> void:
	build_card_bar.toggle_building_cards()


func are_building_cards_visible() -> bool:
	return build_card_bar.are_building_cards_visible()


func apply_level_configuration(level: LevelResource, _source_path: String = "") -> void:
	if level != null:
		build_card_bar.set_slot_count(level.building_card_slot_count)
		tower_codex_panel.set_deployment_waves(build_tower_deployment_schedule(level))
	else:
		tower_codex_panel.set_deployment_waves({})
	wave_control_panel.set_level(level)


static func build_tower_deployment_schedule(level: LevelResource) -> Dictionary:
	var schedule: Dictionary = {}
	if level == null:
		return schedule
	for placement: BuildingPlacementData in level.initial_building_placements:
		if placement != null and placement.definition != null:
			_append_deployment_wave(schedule, placement.definition.kind, 1)
	if level.tutorial != null:
		for event: TutorialEventDefinition in level.tutorial.events:
			if (
				event != null
				and event.automatic_tower_enabled
				and event.automatic_tower_definition != null
				and event.trigger_kind == TutorialEventDefinition.TriggerKind.WAVE_COMPLETED
			):
				_append_deployment_wave(
					schedule,
					event.automatic_tower_definition.kind,
					event.trigger_wave_number + 1
				)
	for kind: Variant in schedule:
		var waves: Array = schedule[kind]
		waves.sort()
	return schedule


static func _append_deployment_wave(schedule: Dictionary, kind: int, wave_number: int) -> void:
	if not schedule.has(kind):
		schedule[kind] = []
	var waves: Array = schedule[kind]
	waves.append(maxi(1, wave_number))
	schedule[kind] = waves


func is_modal_open() -> bool:
	return is_tower_reward_open() or is_confirmation_open() or (
		victory_menu != null and victory_menu.is_open()
	) or (
		defeat_menu != null and defeat_menu.is_open()
	) or (
		pause_menu != null and pause_menu.is_open()
	) or (
		debug_console != null and debug_console.is_open()
	)


func is_confirmation_open() -> bool:
	return confirmation_dialog != null and confirmation_dialog.visible


func is_tower_reward_open() -> bool:
	return tower_reward_popup != null and tower_reward_popup.is_open()


func is_defeat_menu_open() -> bool:
	return defeat_menu != null and defeat_menu.is_open()


func is_victory_menu_open() -> bool:
	return victory_menu != null and victory_menu.is_open()


func get_victory_star_count(remaining_hp: float) -> int:
	if remaining_hp <= 0.0:
		return 0
	if remaining_hp <= one_star_max_remaining_hp:
		return 1
	if remaining_hp <= maxf(one_star_max_remaining_hp, two_star_max_remaining_hp):
		return 2
	return 3


func get_displayed_victory_star_count() -> int:
	return _victory_star_count


func get_settings_snapshot() -> Dictionary:
	return pause_menu.get_settings_snapshot() if pause_menu != null else {}


func is_debug_console_open() -> bool:
	return debug_console != null and debug_console.is_open()


func close_top_modal() -> void:
	if is_tower_reward_open():
		return
	if is_confirmation_open():
		_on_confirmation_cancelled()
		return
	if is_victory_menu_open() or is_defeat_menu_open():
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
	_victory_active = false
	_victory_star_count = 0
	_tower_reward_queue.clear()
	_active_tower_reward_building = null
	_tower_reward_restore_paused = false
	if tower_reward_popup != null:
		tower_reward_popup.dismiss()
	_close_confirmation()
	wave_control_panel.clear_hover_preview()
	if defeat_menu != null:
		defeat_menu.close_menu()
	if victory_menu != null:
		victory_menu.close_menu()
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


func _on_automatic_tower_placed(
	event: TutorialEventDefinition,
	building: Building
) -> void:
	if event == null or building == null or not is_instance_valid(building):
		return
	_tower_reward_queue.append({"event": event, "building": building})
	if not is_tower_reward_open():
		_tower_reward_restore_paused = (
			_time_controller != null and _time_controller.is_paused()
		)
		_show_next_tower_reward()


func _show_next_tower_reward() -> void:
	if _tower_reward_queue.is_empty() or tower_reward_popup == null:
		return
	var reward: Dictionary = _tower_reward_queue.pop_front()
	var event := reward.get("event") as TutorialEventDefinition
	var building := reward.get("building") as Building
	if event == null or building == null or not is_instance_valid(building):
		_show_next_tower_reward()
		return
	_active_tower_reward_building = building
	tower_reward_popup.present(building.definition, event.trigger_wave_number)
	if _time_controller != null:
		_time_controller.set_paused(true)
	_sync_modal_state()


func _on_tower_reward_confirmed() -> void:
	if not is_tower_reward_open():
		return
	tower_reward_popup.dismiss()
	if (
		_active_tower_reward_building != null
		and is_instance_valid(_active_tower_reward_building)
	):
		var pulse := TowerArrivalPulseScript.new()
		pulse.name = "TowerArrivalPulse"
		_active_tower_reward_building.add_child(pulse)
	_active_tower_reward_building = null
	if not _tower_reward_queue.is_empty():
		_show_next_tower_reward()
		return
	if _time_controller != null:
		_time_controller.set_paused(_tower_reward_restore_paused)
	_tower_reward_restore_paused = false
	_sync_modal_state()


## Displays only the player-facing placement failures explicitly approved for
## the production HUD. Manager reasons remain unchanged for logic and tests.
func show_placement_failure(reason: String, screen_position: Vector2) -> void:
	var message := resolve_placement_failure_message(reason)
	if not message.is_empty():
		_show_action_feedback(message, screen_position)


func show_upgrade_failure(screen_position: Vector2) -> void:
	_show_action_feedback("金币不足！", screen_position)


func show_adjustment_failure(is_edge_target: bool, screen_position: Vector2) -> void:
	_show_action_feedback(
		"该边不可放置" if is_edge_target else "该块不可放置",
		screen_position
	)


static func resolve_placement_failure_message(reason: String) -> String:
	var normalized := reason.strip_edges()
	var lowercase := normalized.to_lower()
	if normalized.contains("堵死") or normalized.contains("全部可用路径"):
		return "不能将敌人的路堵死！"
	if normalized.contains("上限"):
		return "该类建筑已经达到上限！"
	for token in [
		"占用",
		"占据",
		"不可建造",
		"不允许放置",
		"敌人路径",
		"出生点",
		"据点格",
		"有效地块之间",
		"障碍",
		"关卡元素",
	]:
		if normalized.contains(token):
			return "该格子不可放置！"
	if lowercase.contains("stuff"):
		return "该格子不可放置！"
	return ""


func _show_action_feedback(message: String, screen_position: Vector2) -> void:
	if action_feedback == null or message.is_empty():
		return
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	action_feedback.text = message
	action_feedback.modulate = Color.WHITE
	action_feedback.show()
	var feedback_size := action_feedback.get_combined_minimum_size() + Vector2(12.0, 6.0)
	action_feedback.size = feedback_size
	var target_position := screen_position + feedback_offset - Vector2(
		feedback_size.x * 0.5,
		feedback_size.y
	)
	var viewport_size := get_viewport_rect().size
	action_feedback.position = Vector2(
		clampf(target_position.x, 6.0, maxf(6.0, viewport_size.x - feedback_size.x - 6.0)),
		clampf(target_position.y, 6.0, maxf(6.0, viewport_size.y - feedback_size.y - 6.0))
	)
	_feedback_tween = create_tween().set_ignore_time_scale(true)
	_feedback_tween.tween_interval(feedback_hold_duration)
	_feedback_tween.tween_property(
		action_feedback,
		"modulate:a",
		0.0,
		feedback_fade_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_feedback_tween.tween_callback(action_feedback.hide)


func _on_paused_changed(paused: bool) -> void:
	if pause_menu == null:
		return
	if _victory_active:
		pause_menu.close_menu()
		defeat_menu.close_menu()
		victory_menu.open_menu()
		_sync_modal_state()
		return
	if _defeat_active:
		pause_menu.close_menu()
		victory_menu.close_menu()
		defeat_menu.open_menu()
		_sync_modal_state()
		return
	if is_confirmation_open():
		if not _confirmation_restore_paused:
			pause_menu.close_menu()
		_sync_modal_state()
		return
	if is_tower_reward_open():
		pause_menu.close_menu()
		_sync_modal_state()
		return
	if paused:
		pause_menu.open_menu()
	else:
		pause_menu.close_menu()
	_sync_modal_state()


func _on_debug_console_open_changed(_open: bool) -> void:
	_sync_modal_state()


func _on_debug_console_requested() -> void:
	if _debug_tools_enabled and _debug_console_available:
		debug_console.open_console()


func _on_runtime_parameter_editor_requested() -> void:
	if (
		_debug_tools_enabled
		and _runtime_parameter_editor != null
		and _runtime_parameter_editor.has_method("toggle_editor")
	):
		_runtime_parameter_editor.call("toggle_editor")


func _on_stuff_editor_active_changed(active: bool) -> void:
	build_card_bar.visible = not active
	tower_codex_panel.set_suppressed(active)
	card_style_toggle.visible = _debug_tools_enabled and not active


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
	_open_confirmation(ConfirmationAction.RESTART_LEVEL, "将重启关卡，确认吗")


func _on_exit_requested() -> void:
	_open_confirmation(ConfirmationAction.EXIT_LEVEL, "将返回标题，确认吗")


func _open_confirmation(action: ConfirmationAction, message: String) -> void:
	if action == ConfirmationAction.NONE or confirmation_dialog == null:
		return
	if _pending_confirmation_action == ConfirmationAction.NONE:
		_confirmation_restore_paused = (
			_time_controller != null and _time_controller.is_paused()
		)
	_pending_confirmation_action = action
	confirmation_message.text = message
	confirmation_dialog.show()
	if _time_controller != null:
		_time_controller.set_paused(true)
	confirmation_confirm_button.grab_focus()
	_sync_modal_state()


func _on_confirmation_cancelled() -> void:
	if _pending_confirmation_action == ConfirmationAction.NONE:
		return
	var restore_paused := _confirmation_restore_paused
	_close_confirmation()
	if _time_controller != null:
		_time_controller.set_paused(restore_paused)
	_sync_modal_state()


func _on_confirmation_confirmed() -> void:
	var action := _pending_confirmation_action
	if action == ConfirmationAction.NONE:
		return
	_close_confirmation()
	match action:
		ConfirmationAction.RESTART_LEVEL:
			restart_level_requested.emit()
		ConfirmationAction.EXIT_LEVEL:
			exit_level_requested.emit()
	_sync_modal_state()


func _close_confirmation() -> void:
	_pending_confirmation_action = ConfirmationAction.NONE
	_confirmation_restore_paused = false
	if confirmation_dialog != null:
		confirmation_dialog.hide()


func _on_defeat() -> void:
	_defeat_active = true
	_victory_active = false
	_victory_star_count = 0
	defeat_menu.open_menu()
	victory_menu.close_menu()
	pause_menu.close_menu()
	if debug_console != null:
		debug_console.close_console()
	wave_control_panel.clear_hover_preview()
	_sync_modal_state()
	if _time_controller != null:
		_time_controller.set_paused(true)


func _on_victory() -> void:
	_victory_active = true
	_defeat_active = false
	var remaining_hp := _base_core.current_hp if _base_core != null else 0.0
	_victory_star_count = get_victory_star_count(remaining_hp)
	victory_menu.set_result_text(
		"本关评价\n%s%s" % [
			"★".repeat(_victory_star_count),
			"☆".repeat(3 - _victory_star_count),
		]
	)
	victory_menu.open_menu()
	defeat_menu.close_menu()
	pause_menu.close_menu()
	if debug_console != null:
		debug_console.close_console()
	wave_control_panel.clear_hover_preview()
	_sync_modal_state()
	if _time_controller != null:
		_time_controller.set_paused(true)


func _on_pause_settings_changed(settings: Dictionary) -> void:
	defeat_menu.sync_settings_controls()
	victory_menu.sync_settings_controls()
	settings_changed.emit(settings)


func _on_result_settings_changed(settings: Dictionary) -> void:
	pause_menu.sync_settings_controls()
	victory_menu.sync_settings_controls()
	settings_changed.emit(settings)


func _on_wave_paths_preview_requested(paths: Array) -> void:
	wave_paths_preview_requested.emit(paths)


func _on_next_wave_released_by_player() -> void:
	if _interaction != null:
		_interaction.cancel_to_select(true)


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
	if _time_controller != null:
		if _time_controller.paused_changed.is_connected(_on_paused_changed):
			_time_controller.paused_changed.disconnect(_on_paused_changed)
	if _stuff_editor_controller != null:
		var callback := Callable(self, "_on_stuff_editor_active_changed")
		if _stuff_editor_controller.is_connected(&"active_changed", callback):
			_stuff_editor_controller.disconnect(&"active_changed", callback)
	_stuff_editor_controller = null
	_disconnect_wave_result_signals()
	_wave_manager = null
	_base_core = null


func _disconnect_wave_result_signals() -> void:
	if _wave_manager == null:
		return
	if _wave_manager.defeat.is_connected(_on_defeat):
		_wave_manager.defeat.disconnect(_on_defeat)
	if _wave_manager.victory.is_connected(_on_victory):
		_wave_manager.victory.disconnect(_on_victory)
