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
@onready var _page_name_label: Label = %PageName
@onready var _page_number_label: Label = %PageNumber

var _catalog: LevelSelectCatalogScript
var _current_page_index: int = 0
var _slots: Array[LevelSelectSlotScript] = []


func _ready() -> void:
	_build_slots()
	_previous_button.pressed.connect(_on_previous_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_refresh_page()


func configure(catalog: LevelSelectCatalogScript) -> void:
	_catalog = catalog
	_current_page_index = 0
	if is_node_ready():
		_refresh_page()


func get_catalog() -> LevelSelectCatalogScript:
	return _catalog


func get_current_page_index() -> int:
	return _current_page_index


func get_page_count() -> int:
	return _catalog.get_page_count() if _catalog != null else 0


func get_slot_count() -> int:
	return _slots.size()


func get_slot_level(slot_index: int) -> LevelResource:
	if slot_index < 0 or slot_index >= _slots.size():
		return null
	return _slots[slot_index].get_level()


func is_previous_page_visible() -> bool:
	return _previous_button != null and _previous_button.visible


func is_next_page_visible() -> bool:
	return _next_button != null and _next_button.visible


func _build_slots() -> void:
	if not _slots.is_empty():
		return
	for slot_index in range(SLOT_COUNT):
		var slot := LevelSelectSlotScript.new()
		slot.name = "LevelSlot%d" % (slot_index + 1)
		slot.pressed.connect(_on_slot_pressed.bind(slot_index))
		_level_grid.add_child(slot)
		_slots.append(slot)


func _refresh_page() -> void:
	if _slots.is_empty():
		return
	var page_count := get_page_count()
	if page_count <= 0:
		_current_page_index = 0
		_clear_slots()
		_page_name_label.text = "暂无关卡"
		_page_number_label.text = "0 / 0"
		_refresh_navigation(0)
		return
	_current_page_index = clampi(_current_page_index, 0, page_count - 1)
	var page: LevelSelectPageDefinitionScript = _catalog.get_page(_current_page_index)
	for slot_index in range(SLOT_COUNT):
		_slots[slot_index].set_level(page.get_level(slot_index) if page != null else null)
	_page_name_label.text = _get_page_name(page, _current_page_index)
	_page_number_label.text = "%d / %d" % [_current_page_index + 1, page_count]
	_refresh_navigation(page_count)


func _clear_slots() -> void:
	for slot in _slots:
		slot.clear()


func _get_page_name(page: LevelSelectPageDefinitionScript, page_index: int) -> String:
	if page != null and not page.display_name.strip_edges().is_empty():
		return page.display_name.strip_edges()
	return "第 %d 页" % (page_index + 1)


func _refresh_navigation(page_count: int) -> void:
	_previous_button.visible = page_count > 1 and _current_page_index > 0
	_next_button.visible = page_count > 1 and _current_page_index < page_count - 1


func _on_previous_pressed() -> void:
	if _catalog == null or _current_page_index <= 0:
		return
	_current_page_index -= 1
	_refresh_page()


func _on_next_pressed() -> void:
	if _catalog == null or _current_page_index >= _catalog.get_page_count() - 1:
		return
	_current_page_index += 1
	_refresh_page()


func _on_slot_pressed(slot_index: int) -> void:
	var level := get_slot_level(slot_index)
	if level != null:
		level_selected.emit(level)
