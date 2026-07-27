@tool
## Standalone fixed 2x3 paged level-selection view.
class_name LevelSelectView
extends Control

const LevelSelectCatalogScript := preload("res://scripts/level/LevelSelectCatalog.gd")
const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")
const LevelSelectSlotScript := preload("res://scripts/ui/LevelSelectSlot.gd")
const SLOT_COUNT: int = 6

signal level_selected(level: LevelResource)

@onready var _level_grid: GridContainer = %LevelGrid
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton

var _catalog: LevelSelectCatalogScript
var _current_page_index: int = 0
var _slots: Array[LevelSelectSlotScript] = []


func _ready() -> void:
	_build_slots()
	_previous_button.pressed.connect(_on_previous_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_refresh_page()
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
	if is_node_ready():
		_refresh_page()
	return


func get_catalog() -> LevelSelectCatalogScript:
	return _catalog


func get_current_page_index() -> int:
	return _current_page_index


func get_page_count() -> int:
	return _catalog.get_page_count() if _catalog != null else 0


func get_slot_count() -> int:
	return _slots.size()


func get_slot_control(slot_index: int) -> LevelSelectSlotScript:
	if slot_index < 0 or slot_index >= _slots.size():
		return null
	return _slots[slot_index]


func get_slot_level(slot_index: int) -> LevelResource:
	var slot := get_slot_control(slot_index)
	return slot.get_level() if slot != null else null


func is_previous_page_visible() -> bool:
	return _previous_button != null and _previous_button.visible


func is_next_page_visible() -> bool:
	return _next_button != null and _next_button.visible


func change_page(delta: int) -> void:
	var page_count := get_page_count()
	if page_count <= 0:
		return
	var next_page_index := clampi(_current_page_index + delta, 0, page_count - 1)
	if next_page_index == _current_page_index:
		return
	_current_page_index = next_page_index
	_refresh_page()
	return


func _build_slots() -> void:
	if not _slots.is_empty():
		return
	for slot_index in range(SLOT_COUNT):
		var slot := LevelSelectSlotScript.new()
		slot.name = "LevelSlot%d" % (slot_index + 1)
		slot.pressed.connect(_on_slot_pressed.bind(slot_index))
		_level_grid.add_child(slot)
		_slots.append(slot)
	return


func _refresh_page() -> void:
	if _slots.is_empty():
		return
	var page_count := get_page_count()
	if page_count <= 0:
		_current_page_index = 0
		_clear_slots()
		_refresh_navigation(0)
		return
	_current_page_index = clampi(_current_page_index, 0, page_count - 1)
	var page: LevelSelectPageDefinitionScript = _catalog.get_page(_current_page_index)
	for slot_index in range(SLOT_COUNT):
		_slots[slot_index].set_level(page.get_level(slot_index) if page != null else null)
	_refresh_navigation(page_count)
	return


func _clear_slots() -> void:
	for slot in _slots:
		slot.clear()
	return


func _refresh_navigation(page_count: int) -> void:
	_previous_button.visible = page_count > 1 and _current_page_index > 0
	_next_button.visible = page_count > 1 and _current_page_index < page_count - 1
	return


func _on_previous_pressed() -> void:
	change_page(-1)
	return


func _on_next_pressed() -> void:
	change_page(1)
	return


func _on_slot_pressed(slot_index: int) -> void:
	var level := get_slot_level(slot_index)
	if level == null:
		return
	level_selected.emit(level)
	return
