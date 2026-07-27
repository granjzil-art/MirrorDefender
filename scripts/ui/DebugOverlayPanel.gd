## Persistent read-only debug summary shown independently from the F1 console.
class_name DebugOverlayPanel
extends Control

const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Refresh")
@export_range(0.05, 2.0, 0.05, "or_greater") var refresh_interval: float = 0.2

@export_group("Art")
@export var panel_texture: Texture2D

@onready var frame_texture: TextureRect = $Frame/FrameTexture
@onready var output: RichTextLabel = $Frame/Margin/Content/Output

var _category_registry: DebugCategoryRegistryScript
var _next_refresh_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if panel_texture != null:
		frame_texture.texture = panel_texture
		frame_texture.visible = true


func _process(_delta: float) -> void:
	if not feature_enabled or _category_registry == null:
		visible = false
		return
	var now := Time.get_ticks_msec()
	if now < _next_refresh_msec:
		return
	_next_refresh_msec = now + maxi(1, roundi(refresh_interval * 1000.0))
	refresh_now()


func configure(category_registry: DebugCategoryRegistryScript) -> void:
	_disconnect_registry()
	_category_registry = category_registry
	if _category_registry != null:
		_category_registry.category_changed.connect(_on_category_changed)
		_category_registry.categories_changed.connect(refresh_now)
	_next_refresh_msec = 0
	refresh_now()


func refresh_now() -> void:
	if output == null:
		return
	if not feature_enabled or _category_registry == null:
		output.text = ""
		visible = false
		return
	var sections: Array[String] = []
	for snapshot in _category_registry.get_enabled_snapshot():
		sections.append("[%s]\n%s" % [
			str(snapshot.get("display_name", "")),
			str(snapshot.get("text", "")),
		])
	output.text = "\n\n".join(sections)
	visible = not sections.is_empty()


func get_display_text() -> String:
	return output.text if output != null else ""


func _on_category_changed(_category_id: StringName, _enabled: bool) -> void:
	_next_refresh_msec = 0
	refresh_now()


func _disconnect_registry() -> void:
	if _category_registry == null:
		return
	if _category_registry.category_changed.is_connected(_on_category_changed):
		_category_registry.category_changed.disconnect(_on_category_changed)
	if _category_registry.categories_changed.is_connected(refresh_now):
		_category_registry.categories_changed.disconnect(refresh_now)


func _exit_tree() -> void:
	_disconnect_registry()
