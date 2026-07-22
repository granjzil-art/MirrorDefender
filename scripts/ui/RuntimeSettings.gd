## Persistent M6 runtime presentation settings stored in user://settings.cfg.
class_name RuntimeSettings
extends RefCounted

const SECTION := "runtime"
const KEY_MAIN_VOLUME := "main_volume_percent"
const KEY_FULLSCREEN := "fullscreen"
const KEY_UI_SCALE := "ui_scale"

var main_volume_percent: float = 100.0
var fullscreen: bool = false
var ui_scale: float = 1.0


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
	return OK


func save_to_file(path: String) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_MAIN_VOLUME, main_volume_percent)
	config.set_value(SECTION, KEY_FULLSCREEN, fullscreen)
	config.set_value(SECTION, KEY_UI_SCALE, ui_scale)
	return config.save(path)


func set_values(volume_percent: float, use_fullscreen: bool, scale: float) -> void:
	main_volume_percent = clampf(volume_percent, 0.0, 100.0)
	fullscreen = use_fullscreen
	ui_scale = clampf(scale, 0.75, 1.50)


func apply_to_runtime(root_window: Window) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_linear(master_bus, main_volume_percent / 100.0)
	if root_window != null:
		root_window.content_scale_factor = ui_scale
		if DisplayServer.get_name().to_lower() != "headless":
			root_window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


func to_dictionary() -> Dictionary:
	return {
		"main_volume_percent": main_volume_percent,
		"fullscreen": fullscreen,
		"ui_scale": ui_scale,
	}
