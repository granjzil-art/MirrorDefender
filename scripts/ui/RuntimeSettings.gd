## Persistent M6 runtime presentation settings stored in user://settings.cfg.
class_name RuntimeSettings
extends RefCounted

const SECTION := "runtime"
const KEY_MAIN_VOLUME := "main_volume_percent"
const KEY_FULLSCREEN := "fullscreen"
const KEY_UI_SCALE := "ui_scale"
const KEY_DEPTH_OF_FIELD_ENABLED := "depth_of_field_enabled"
const KEY_RENDER_QUALITY_PRESET := "render_quality_preset"

const RENDER_QUALITY_PERFORMANCE := 0
const RENDER_QUALITY_BALANCED := 1
const RENDER_QUALITY_NATIVE := 2
const RENDER_QUALITY_MIN := RENDER_QUALITY_PERFORMANCE
const RENDER_QUALITY_MAX := RENDER_QUALITY_NATIVE
const PERFORMANCE_RENDER_CAP := Vector2i(1920, 1080)
const BALANCED_RENDER_CAP := Vector2i(2560, 1440)

var main_volume_percent: float = 100.0
var fullscreen: bool = false
var ui_scale: float = 1.0
var depth_of_field_enabled: bool = true
var render_quality_preset: int = RENDER_QUALITY_BALANCED


func load_from_file(path: String) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	main_volume_percent = clampf(float(config.get_value(SECTION, KEY_MAIN_VOLUME, 100.0)), 0.0, 100.0)
	fullscreen = bool(config.get_value(SECTION, KEY_FULLSCREEN, false))
	ui_scale = clampf(float(config.get_value(SECTION, KEY_UI_SCALE, 1.0)), 0.75, 1.50)
	depth_of_field_enabled = bool(config.get_value(SECTION, KEY_DEPTH_OF_FIELD_ENABLED, true))
	render_quality_preset = clampi(
		int(config.get_value(SECTION, KEY_RENDER_QUALITY_PRESET, RENDER_QUALITY_BALANCED)),
		RENDER_QUALITY_MIN,
		RENDER_QUALITY_MAX
	)
	return OK


func save_to_file(path: String) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_MAIN_VOLUME, main_volume_percent)
	config.set_value(SECTION, KEY_FULLSCREEN, fullscreen)
	config.set_value(SECTION, KEY_UI_SCALE, ui_scale)
	config.set_value(SECTION, KEY_DEPTH_OF_FIELD_ENABLED, depth_of_field_enabled)
	config.set_value(SECTION, KEY_RENDER_QUALITY_PRESET, render_quality_preset)
	return config.save(path)


func set_values(
	volume_percent: float,
	use_fullscreen: bool,
	scale: float,
	enable_depth_of_field: bool = true,
	p_render_quality_preset: int = RENDER_QUALITY_BALANCED
) -> void:
	main_volume_percent = clampf(volume_percent, 0.0, 100.0)
	fullscreen = use_fullscreen
	ui_scale = clampf(scale, 0.75, 1.50)
	depth_of_field_enabled = enable_depth_of_field
	render_quality_preset = clampi(
		p_render_quality_preset,
		RENDER_QUALITY_MIN,
		RENDER_QUALITY_MAX
	)


func apply_to_runtime(root_window: Window) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_linear(master_bus, main_volume_percent / 100.0)
	if root_window != null:
		root_window.content_scale_factor = ui_scale
		if DisplayServer.get_name().to_lower() != "headless":
			Engine.max_fps = 60
			root_window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		root_window.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root_window.scaling_3d_scale = get_effective_3d_scale(root_window)


func get_effective_3d_scale(root_window: Window) -> float:
	if render_quality_preset == RENDER_QUALITY_NATIVE:
		return 1.0
	var output_size := _get_output_size(root_window)
	if output_size.x <= 0 or output_size.y <= 0:
		return 1.0
	var render_cap := (
		PERFORMANCE_RENDER_CAP
		if render_quality_preset == RENDER_QUALITY_PERFORMANCE
		else BALANCED_RENDER_CAP
	)
	return clampf(
		minf(
			float(render_cap.x) / float(output_size.x),
			float(render_cap.y) / float(output_size.y)
		),
		0.5,
		1.0
	)


func _get_output_size(root_window: Window) -> Vector2i:
	if root_window == null:
		return Vector2i.ZERO
	if fullscreen and DisplayServer.get_name().to_lower() != "headless":
		return DisplayServer.screen_get_size(root_window.current_screen)
	return root_window.size


func to_dictionary() -> Dictionary:
	return {
		"main_volume_percent": main_volume_percent,
		"fullscreen": fullscreen,
		"ui_scale": ui_scale,
		"depth_of_field_enabled": depth_of_field_enabled,
		"render_quality_preset": render_quality_preset,
	}
