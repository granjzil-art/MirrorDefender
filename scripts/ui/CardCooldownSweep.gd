## Draws the mirror-card cooldown mask without modifying the configured artwork.
class_name CardCooldownSweep
extends Control

@export var overlay_color: Color = Color(0.10, 0.11, 0.12, 0.86)
@export var scanline_color: Color = Color(0.96, 0.78, 0.30, 0.95)
@export_range(1.0, 8.0, 0.5) var scanline_width: float = 3.0

var _ready_ratio: float = 1.0
var _blocked: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_state(ready_ratio: float, blocked: bool) -> void:
	_ready_ratio = clampf(ready_ratio, 0.0, 1.0) if is_finite(ready_ratio) else 0.0
	_blocked = blocked
	visible = _blocked or _ready_ratio < 0.999999
	queue_redraw()


func get_ready_ratio() -> float:
	return _ready_ratio


func is_blocked() -> bool:
	return _blocked


func debug_get_scanline_y() -> float:
	return size.y * _ready_ratio


func _draw() -> void:
	if _blocked:
		draw_rect(Rect2(Vector2.ZERO, size), overlay_color)
		return
	if _ready_ratio >= 0.999999:
		return
	var scanline_y := clampf(debug_get_scanline_y(), 0.0, size.y)
	draw_rect(
		Rect2(Vector2(0.0, scanline_y), Vector2(size.x, size.y - scanline_y)),
		overlay_color
	)
	draw_line(
		Vector2(0.0, scanline_y),
		Vector2(size.x, scanline_y),
		scanline_color,
		scanline_width,
		true
	)
