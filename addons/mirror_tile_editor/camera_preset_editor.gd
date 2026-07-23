@tool
## Sidebar component for authoring LevelResource's six optional camera slots.
class_name CameraPresetEditor
extends VBoxContainer

const CameraPresetDefinitionScript := preload("res://scripts/camera/CameraPresetDefinition.gd")

signal level_changed
signal status_changed(message: String)

var _level: LevelResource
var _canvas: Control
var _interface_built: bool = false
var _status_labels: Array[Label] = []
var _preview_buttons: Array[Button] = []
var _clear_buttons: Array[Button] = []


func _ready() -> void:
	_ensure_interface()


func configure(level: LevelResource, canvas: Control) -> void:
	_ensure_interface()
	_level = level
	_canvas = canvas
	refresh()


func refresh() -> void:
	if not _interface_built:
		return
	for slot_index in range(LevelResource.CAMERA_PRESET_SLOT_COUNT):
		var preset := _level.get_camera_preset(slot_index) if _level != null else null
		var configured := preset != null
		_status_labels[slot_index].text = _format_status(slot_index, preset)
		_preview_buttons[slot_index].disabled = not configured
		_clear_buttons[slot_index].disabled = not configured


func capture_slot(slot_index: int) -> bool:
	if _level == null or _canvas == null or not _canvas.has_method("get_camera_view_state"):
		return false
	var state: Dictionary = _canvas.call("get_camera_view_state")
	var focus_position: Vector3 = state.get("focus_position", Vector3.ZERO)
	var preset := CameraPresetDefinitionScript.new()
	preset.focus_position = focus_position
	preset.yaw_degrees = float(state.get("yaw_degrees", 0.0))
	preset.pitch_degrees = float(state.get("pitch_degrees", 50.0))
	preset.zoom_distance = float(state.get("zoom_distance", 16.0))
	if not _level.set_camera_preset(slot_index, preset):
		return false
	level_changed.emit()
	status_changed.emit("已从当前编辑视角写入镜头 %d。" % (slot_index + 1))
	refresh()
	return true


func preview_slot(slot_index: int) -> bool:
	if _level == null or _canvas == null or not _canvas.has_method("apply_camera_view_state"):
		return false
	var preset := _level.get_camera_preset(slot_index)
	if preset == null:
		status_changed.emit("镜头 %d 尚未配置。" % (slot_index + 1))
		return false
	_canvas.call(
		"apply_camera_view_state",
		preset.focus_position,
		preset.yaw_degrees,
		preset.pitch_degrees,
		preset.zoom_distance
	)
	status_changed.emit("正在预览镜头 %d。" % (slot_index + 1))
	return true


func clear_slot(slot_index: int) -> bool:
	if _level == null or not _level.clear_camera_preset(slot_index):
		return false
	level_changed.emit()
	status_changed.emit("已清空镜头 %d。" % (slot_index + 1))
	refresh()
	return true


func get_slot_status(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= _status_labels.size():
		return ""
	return _status_labels[slot_index].text


func _ensure_interface() -> void:
	if _interface_built:
		return
	_interface_built = true
	custom_minimum_size = Vector2(350.0, 0.0)
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "关卡镜头预设"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	var help := Label.new()
	help.text = "在右侧用 WASD / QE / XC / 滚轮调整视角，再写入槽位。运行时按数字键 1～6 平滑切换。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	for slot_index in range(LevelResource.CAMERA_PRESET_SLOT_COUNT):
		_add_slot_row(slot_index)


func _add_slot_row(slot_index: int) -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	_status_labels.append(status)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var capture := Button.new()
	capture.text = "写入当前视角"
	capture.pressed.connect(capture_slot.bind(slot_index))
	actions.add_child(capture)
	var preview := Button.new()
	preview.text = "预览"
	preview.pressed.connect(preview_slot.bind(slot_index))
	actions.add_child(preview)
	_preview_buttons.append(preview)
	var clear := Button.new()
	clear.text = "清空"
	clear.pressed.connect(clear_slot.bind(slot_index))
	actions.add_child(clear)
	_clear_buttons.append(clear)


func _format_status(slot_index: int, preset: CameraPresetDefinitionScript) -> String:
	if preset == null:
		return "镜头 %d · 未配置" % (slot_index + 1)
	return "镜头 %d · 已配置\n焦点 %s | yaw %.1f° | pitch %.1f° | 距离 %.1f" % [
		slot_index + 1,
		str(preset.focus_position),
		preset.yaw_degrees,
		preset.pitch_degrees,
		preset.zoom_distance,
	]
