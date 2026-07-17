## Compact M4 wave control and base status panel for runtime greybox validation.
class_name WaveStatusPanel
extends Control

@export_group("Feature")
@export var feature_enabled: bool = true

var _wave_manager: WaveManager
var _base_core: BaseCore
var _summary_label: Label
var _start_button: Button

func _ready() -> void:
	visible = feature_enabled
	_build_interface()

func configure(wave_manager: WaveManager, base_core: BaseCore) -> void:
	_disconnect_sources()
	_wave_manager = wave_manager
	_base_core = base_core
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_wave_state_changed)
		_wave_manager.victory.connect(_refresh)
		_wave_manager.defeat.connect(_refresh)
	if _base_core != null:
		_base_core.health_changed.connect(_on_base_health_changed)
	_refresh()

func _build_interface() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var title := Label.new()
	title.text = "M4 波次"
	title.add_theme_font_size_override("font_size", 16)
	content.add_child(title)
	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary_label)
	_start_button = Button.new()
	_start_button.text = "开始下一波"
	_start_button.tooltip_text = "在准备完成后开始下一波"
	_start_button.pressed.connect(_on_start_pressed)
	content.add_child(_start_button)

func _disconnect_sources() -> void:
	if _wave_manager != null:
		if _wave_manager.state_changed.is_connected(_on_wave_state_changed):
			_wave_manager.state_changed.disconnect(_on_wave_state_changed)
		if _wave_manager.victory.is_connected(_refresh):
			_wave_manager.victory.disconnect(_refresh)
		if _wave_manager.defeat.is_connected(_refresh):
			_wave_manager.defeat.disconnect(_refresh)
	if _base_core != null and _base_core.health_changed.is_connected(_on_base_health_changed):
		_base_core.health_changed.disconnect(_on_base_health_changed)

func _on_start_pressed() -> void:
	if _wave_manager != null:
		_wave_manager.start_next_wave()
	_refresh()

func _on_wave_state_changed(
	_state: WaveManager.State,
	_current_wave: int,
	_total_waves: int,
	_active_enemy_count: int
) -> void:
	_refresh()

func _on_base_health_changed(_current_hp: float, _maximum_hp: float) -> void:
	_refresh()

func _refresh() -> void:
	if _summary_label == null:
		return
	if _wave_manager == null or _base_core == null:
		_summary_label.text = "波次系统未连接"
		if _start_button != null:
			_start_button.disabled = true
		return
	_summary_label.text = "据点 %d/%d\n波次 %d/%d | 敌人 %d\n%s" % [
		ceili(_base_core.current_hp),
		ceili(_base_core.max_hp),
		_wave_manager.get_current_wave_number(),
		_wave_manager.get_total_wave_count(),
		_wave_manager.get_active_enemy_count(),
		_wave_manager.get_state_name(),
	]
	_start_button.disabled = _wave_manager.get_state() != WaveManager.State.READY
