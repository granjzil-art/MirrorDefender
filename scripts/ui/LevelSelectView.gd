@tool
## Standalone fixed 2x3 paged level-selection view.
class_name LevelSelectView
extends Control

const LevelSelectCatalogScript := preload("res://scripts/level/LevelSelectCatalog.gd")
const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")
const LevelSelectSlotScript := preload("res://scripts/ui/LevelSelectSlot.gd")
const SLOT_COUNT: int = 6

signal level_selected(level: LevelResource)

@export_group("Page Transition")
@export_range(0.05, 1.0, 0.01) var page_slide_duration: float = 0.25

@onready var _page_viewport: Control = %PageViewport
@onready var _current_page_control: MarginContainer = %CurrentPage
@onready var _standby_page_control_node: MarginContainer = %StandbyPage
@onready var _current_level_grid: GridContainer = %LevelGrid
@onready var _standby_level_grid: GridContainer = %StandbyLevelGrid
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton

var _catalog: LevelSelectCatalogScript
var _current_page_index: int = 0
var _current_page_slots: Array[LevelSelectSlotScript] = []
var _standby_page_slots: Array[LevelSelectSlotScript] = []
var _active_page: MarginContainer
var _standby_page: MarginContainer
var _active_grid: GridContainer
var _standby_grid: GridContainer
var _active_slots: Array[LevelSelectSlotScript] = []
var _standby_slots: Array[LevelSelectSlotScript] = []
var _slide_tween: Tween
var _slide_target_page_index: int = -1
var _queued_page_delta: int = 0
var _is_sliding: bool = false


func _ready() -> void:
	_reset_page_roles()
	_build_slots()
	_previous_button.pressed.connect(_on_previous_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_page_viewport.resized.connect(_on_page_viewport_resized)
	_reset_page_positions()
	_refresh_page()
	return


func _exit_tree() -> void:
	_stop_slide_and_reset()
	return


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	var page_delta := 0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		page_delta = 1
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		page_delta = -1
	else:
		return
	change_page(page_delta)
	accept_event()
	return


func configure(catalog: LevelSelectCatalogScript) -> void:
	_catalog = catalog
	_current_page_index = 0
	_queued_page_delta = 0
	_slide_target_page_index = -1
	if is_node_ready():
		_stop_slide_and_reset()
		_refresh_page()
	return


func get_catalog() -> LevelSelectCatalogScript:
	return _catalog


func get_current_page_index() -> int:
	return _current_page_index


func get_page_count() -> int:
	return _catalog.get_page_count() if _catalog != null else 0


func get_slot_count() -> int:
	return _active_slots.size()


func get_slot_control(slot_index: int) -> LevelSelectSlotScript:
	if slot_index < 0 or slot_index >= _active_slots.size():
		return null
	return _active_slots[slot_index]


func get_slot_level(slot_index: int) -> LevelResource:
	var slot := get_slot_control(slot_index)
	return slot.get_level() if slot != null else null


func is_previous_page_visible() -> bool:
	return _previous_button != null and _previous_button.visible


func is_next_page_visible() -> bool:
	return _next_button != null and _next_button.visible


func is_sliding_for_test() -> bool:
	return _is_sliding


func get_active_page_position_for_test() -> Vector2:
	return _active_page.position if _active_page != null else Vector2.ZERO


func get_standby_page_position_for_test() -> Vector2:
	return _standby_page.position if _standby_page != null else Vector2.ZERO


func complete_slide_for_test() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.custom_step(page_slide_duration + 1.0)
	return


func change_page(delta: int) -> void:
	if delta != -1 and delta != 1:
		return
	var page_count := get_page_count()
	if page_count <= 0:
		return
	if _is_sliding:
		var queued_target := _slide_target_page_index + delta
		if queued_target >= 0 and queued_target < page_count:
			_queued_page_delta = delta
		return
	var target_page_index := _current_page_index + delta
	if target_page_index < 0 or target_page_index >= page_count:
		return
	_start_page_slide(target_page_index, delta)
	return


func _reset_page_roles() -> void:
	_active_page = _current_page_control
	_standby_page = _standby_page_control_node
	_active_grid = _current_level_grid
	_standby_grid = _standby_level_grid
	_active_slots = _current_page_slots
	_standby_slots = _standby_page_slots
	return


func _build_slots() -> void:
	if not _current_page_slots.is_empty():
		return
	_build_slots_for_grid(_current_level_grid, _current_page_slots, "LevelSlot")
	_build_slots_for_grid(_standby_level_grid, _standby_page_slots, "StandbyLevelSlot")
	_reset_page_roles()
	return


func _build_slots_for_grid(grid: GridContainer, slots: Array[LevelSelectSlotScript], slot_name_prefix: String) -> void:
	for slot_index in range(SLOT_COUNT):
		var slot := LevelSelectSlotScript.new()
		slot.name = "%s%d" % [slot_name_prefix, slot_index + 1]
		slot.pressed.connect(_on_slot_pressed.bind(slot))
		grid.add_child(slot)
		slots.append(slot)
	return


func _refresh_page() -> void:
	if _active_slots.is_empty():
		return
	var page_count := get_page_count()
	if page_count <= 0:
		_current_page_index = 0
		_clear_slots(_active_slots)
		_clear_slots(_standby_slots)
		_refresh_navigation(0, 0)
		_set_slots_interaction_locked(false)
		return
	_current_page_index = clampi(_current_page_index, 0, page_count - 1)
	_populate_slots(_active_slots, _current_page_index)
	_clear_slots(_standby_slots)
	_refresh_navigation(page_count, _current_page_index)
	_set_slots_interaction_locked(false)
	return


func _populate_slots(slots: Array[LevelSelectSlotScript], page_index: int) -> void:
	var page: LevelSelectPageDefinitionScript = _catalog.get_page(page_index)
	for slot_index in range(SLOT_COUNT):
		slots[slot_index].set_level(page.get_level(slot_index) if page != null else null)
	return


func _clear_slots(slots: Array[LevelSelectSlotScript]) -> void:
	for slot in slots:
		slot.clear()
	return


func _set_slots_interaction_locked(value: bool) -> void:
	for slot in _current_page_slots:
		slot.set_interaction_locked(value)
	for slot in _standby_page_slots:
		slot.set_interaction_locked(value)
	return


func _refresh_navigation(page_count: int, page_index: int) -> void:
	_previous_button.visible = page_count > 1 and page_index > 0
	_next_button.visible = page_count > 1 and page_index < page_count - 1
	return


func _start_page_slide(target_page_index: int, delta: int) -> void:
	var page_width := _page_viewport.size.x
	_populate_slots(_standby_slots, target_page_index)
	_active_page.position = Vector2.ZERO
	_standby_page.position = Vector2(page_width * float(delta), 0.0)
	_set_slots_interaction_locked(true)
	_slide_target_page_index = target_page_index
	_is_sliding = true
	_refresh_navigation(get_page_count(), target_page_index)

	_slide_tween = create_tween()
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.set_ignore_time_scale(true)
	_slide_tween.set_trans(Tween.TRANS_QUAD)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(_active_page, "position", Vector2(-page_width * float(delta), 0.0), page_slide_duration)
	_slide_tween.tween_property(_standby_page, "position", Vector2.ZERO, page_slide_duration)
	_slide_tween.finished.connect(_on_slide_finished)
	return


func _on_slide_finished() -> void:
	if not _is_sliding:
		return
	_current_page_index = _slide_target_page_index
	var previous_active_page := _active_page
	_active_page = _standby_page
	_standby_page = previous_active_page
	var previous_active_grid := _active_grid
	_active_grid = _standby_grid
	_standby_grid = previous_active_grid
	var previous_active_slots := _active_slots
	_active_slots = _standby_slots
	_standby_slots = previous_active_slots
	_slide_tween = null
	_slide_target_page_index = -1
	_is_sliding = false
	_active_page.position = Vector2.ZERO
	_standby_page.position = Vector2(_page_viewport.size.x, 0.0)
	_refresh_navigation(get_page_count(), _current_page_index)

	var queued_delta := _queued_page_delta
	_queued_page_delta = 0
	if queued_delta != 0:
		change_page(queued_delta)
	if not _is_sliding:
		_set_slots_interaction_locked(false)
	return


func _stop_slide_and_reset() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null
	_slide_target_page_index = -1
	_queued_page_delta = 0
	_is_sliding = false
	if _current_page_control == null or _standby_page_control_node == null:
		return
	_reset_page_roles()
	_reset_page_positions()
	_set_slots_interaction_locked(false)
	return


func _reset_page_positions() -> void:
	_active_page.position = Vector2.ZERO
	_standby_page.position = Vector2(_page_viewport.size.x, 0.0)
	return


func _on_page_viewport_resized() -> void:
	if _is_sliding:
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.custom_step(page_slide_duration + 1.0)
		return
	_reset_page_positions()
	return


func _on_previous_pressed() -> void:
	change_page(-1)
	return


func _on_next_pressed() -> void:
	change_page(1)
	return


func _on_slot_pressed(slot: LevelSelectSlotScript) -> void:
	if _is_sliding or not _active_slots.has(slot):
		return
	var level := slot.get_level()
	if level == null:
		return
	level_selected.emit(level)
	return
