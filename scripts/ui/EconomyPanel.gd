## Read-only resource presentation with unscaled rolling numbers and popups.
class_name EconomyPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Animation")
@export_range(0.01, 2.0, 0.01, "or_greater") var number_roll_duration: float = 0.35
@export_range(0.05, 3.0, 0.05, "or_greater") var popup_duration: float = 0.9
@export_range(4.0, 200.0, 1.0, "or_greater") var popup_rise_distance: float = 54.0

@export_group("Visual")
@export var resource_icon: Texture2D
@export var gain_color: Color = Color(1.0, 0.82, 0.24, 1.0)
@export var spend_color: Color = Color(1.0, 0.58, 0.24, 1.0)

@onready var resource_icon_rect: TextureRect = $GlassPanel/Content/ResourceIcon
@onready var fallback_icon_label: Label = $GlassPanel/Content/FallbackIcon
@onready var resource_label: Label = $GlassPanel/Content/ResourceValue
@onready var popup_layer: Control = $PopupLayer

var _resource_manager: ResourceManager
var _displayed_resource: float = 0.0
var _roll_start: float = 0.0
var _target_resource: float = 0.0
var _roll_elapsed: float = 0.0
var _popups: Array[Dictionary] = []
var _popup_serial: int = 0
var _last_ticks_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = feature_enabled
	_last_ticks_usec = Time.get_ticks_usec()
	_apply_icon()
	_update_resource_label()


func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	var real_delta := maxf(0.0, float(now_usec - _last_ticks_usec) / 1000000.0)
	_last_ticks_usec = now_usec
	advance_ui_time(real_delta)


func configure(resource_manager: ResourceManager) -> void:
	_disconnect_resource_manager()
	_resource_manager = resource_manager
	if _resource_manager != null:
		_resource_manager.resource_changed.connect(_on_resource_changed)
		_displayed_resource = _resource_manager.main_resource
		_target_resource = _displayed_resource
		_roll_start = _displayed_resource
		_roll_elapsed = number_roll_duration
	_update_resource_label()


## Advances presentation in real time; production calls this from the wall clock
## and tests may call it directly without depending on Engine.time_scale.
func advance_ui_time(real_delta: float) -> void:
	if not feature_enabled:
		return
	var safe_delta := maxf(0.0, real_delta)
	if not is_equal_approx(_displayed_resource, _target_resource):
		_roll_elapsed += safe_delta
		var progress := clampf(_roll_elapsed / maxf(0.01, number_roll_duration), 0.0, 1.0)
		var smoothed := progress * progress * (3.0 - 2.0 * progress)
		_displayed_resource = lerpf(_roll_start, _target_resource, smoothed)
		if progress >= 1.0:
			_displayed_resource = _target_resource
		_update_resource_label()
	_advance_popups(safe_delta)


func get_displayed_resource() -> float:
	return _displayed_resource


func get_popup_count() -> int:
	return _popups.size()


func _on_resource_changed(current: float, delta: float, _reason: String) -> void:
	_roll_start = _displayed_resource
	_target_resource = current
	_roll_elapsed = 0.0
	if not is_zero_approx(delta):
		_spawn_popup(delta)


func _spawn_popup(delta: float) -> void:
	if popup_layer == null:
		return
	var label := Label.new()
	label.text = "%s%s" % ["+" if delta > 0.0 else "", _format_amount(delta)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", gain_color if delta > 0.0 else spend_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(120.0, 30.0 - float(_popup_serial % 4) * 8.0)
	label.size = Vector2(160.0, 32.0)
	popup_layer.add_child(label)
	_popups.append({"label": label, "elapsed": 0.0, "start_y": label.position.y})
	_popup_serial += 1


func _advance_popups(delta: float) -> void:
	for index in range(_popups.size() - 1, -1, -1):
		var popup: Dictionary = _popups[index]
		var elapsed := float(popup["elapsed"]) + delta
		var progress := clampf(elapsed / maxf(0.01, popup_duration), 0.0, 1.0)
		var label: Label = popup["label"]
		if label == null or not is_instance_valid(label) or progress >= 1.0:
			if label != null and is_instance_valid(label):
				label.queue_free()
			_popups.remove_at(index)
			continue
		popup["elapsed"] = elapsed
		label.position.y = float(popup["start_y"]) - popup_rise_distance * progress
		label.modulate.a = 1.0 - progress


func _format_amount(value: float) -> String:
	var rounded := roundf(value)
	return "%d" % int(rounded) if is_equal_approx(value, rounded) else "%.1f" % value


func _update_resource_label() -> void:
	if resource_label != null:
		resource_label.text = "%d" % roundi(_displayed_resource)


func _apply_icon() -> void:
	if resource_icon_rect == null or fallback_icon_label == null:
		return
	resource_icon_rect.texture = resource_icon
	resource_icon_rect.visible = resource_icon != null
	fallback_icon_label.visible = resource_icon == null


func _disconnect_resource_manager() -> void:
	if _resource_manager != null and _resource_manager.resource_changed.is_connected(_on_resource_changed):
		_resource_manager.resource_changed.disconnect(_on_resource_changed)
