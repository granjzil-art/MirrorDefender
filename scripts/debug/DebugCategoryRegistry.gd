## Runtime-selectable debug categories with optional live providers and toggles.
class_name DebugCategoryRegistry
extends RefCounted

signal category_changed(category_id: StringName, enabled: bool)
signal categories_changed

var _categories: Dictionary = {}
var _category_order: Array[StringName] = []
var _suspended: bool = false


func register_category(
	category_id: StringName,
	display_name: String,
	enabled: bool = false,
	provider: Callable = Callable(),
	toggle_handler: Callable = Callable()
) -> bool:
	var normalized := StringName(String(category_id).strip_edges().to_lower())
	if normalized.is_empty():
		return false
	if not _categories.has(normalized):
		_category_order.append(normalized)
	_categories[normalized] = {
		"id": normalized,
		"display_name": display_name.strip_edges() if not display_name.strip_edges().is_empty() else String(normalized),
		"enabled": enabled,
		"provider": provider,
		"toggle_handler": toggle_handler,
	}
	if toggle_handler.is_valid():
		toggle_handler.call(enabled and not _suspended)
	categories_changed.emit()
	return true


func set_enabled(category_id: StringName, enabled: bool) -> bool:
	var normalized := StringName(String(category_id).strip_edges().to_lower())
	if not _categories.has(normalized):
		return false
	var entry: Dictionary = _categories[normalized]
	if bool(entry.get("enabled", false)) == enabled:
		return true
	entry["enabled"] = enabled
	_categories[normalized] = entry
	var toggle_handler: Callable = entry.get("toggle_handler", Callable())
	if toggle_handler.is_valid():
		toggle_handler.call(enabled and not _suspended)
	category_changed.emit(normalized, enabled)
	return true


func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	for category_id in _category_order:
		if not _categories.has(category_id):
			continue
		var entry: Dictionary = _categories[category_id]
		var toggle_handler: Callable = entry.get("toggle_handler", Callable())
		if toggle_handler.is_valid():
			toggle_handler.call(bool(entry.get("enabled", false)) and not _suspended)
	categories_changed.emit()


func is_suspended() -> bool:
	return _suspended


func is_enabled(category_id: StringName) -> bool:
	var normalized := StringName(String(category_id).strip_edges().to_lower())
	if not _categories.has(normalized):
		return false
	var entry: Dictionary = _categories[normalized]
	return bool(entry.get("enabled", false))


func list_categories() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category_id in _category_order:
		if _categories.has(category_id):
			result.append((_categories[category_id] as Dictionary).duplicate())
	return result


func get_enabled_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _suspended:
		return result
	for category_id in _category_order:
		if not _categories.has(category_id):
			continue
		var entry: Dictionary = _categories[category_id]
		if not bool(entry.get("enabled", false)):
			continue
		var provider: Callable = entry.get("provider", Callable())
		var text := "无可用数据"
		if provider.is_valid():
			var provided: Variant = provider.call()
			if provided is Array:
				text = "\n".join(provided)
			else:
				text = str(provided)
			if text.strip_edges().is_empty():
				text = "无可用数据"
		result.append({
			"id": category_id,
			"display_name": str(entry.get("display_name", category_id)),
			"text": text,
		})
	return result
