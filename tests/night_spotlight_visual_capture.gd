## Forward+ comparison capture for real-tree and procedural foliage shadows.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const LightingTestLevel := preload("res://resources/levels/Level2.tres")
const OUTPUT_DIRECTORY := "res://outputs/lighting_profiles"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	var main: Node = MainScene.instantiate()
	if not bool(main.call("configure_startup_level", LightingTestLevel)):
		push_error("Unable to configure Level2 for night-lighting capture")
		quit(1)
		return
	root.add_child(main)
	await _wait_frames(24)
	var camera_presets: Node = main.get("camera_preset_controller") as Node
	if camera_presets != null:
		camera_presets.set("transition_duration", 0.0)
		camera_presets.call("request_preset", 0)
		await _wait_frames(8)
	var lighting: Node = main.get("lighting_controller") as Node
	if lighting == null or not bool(lighting.call("apply_profile_by_index", 3, 0.0)):
		push_error("Unable to apply night spotlight profile")
		quit(1)
		return
	lighting.call("set_foliage_shadow_enabled", false)
	lighting.call("set_realistic_tree_shadow_enabled", true)
	await _wait_frames(16)
	if not _capture("level_2_night_realistic_tree_shadow.png"):
		quit(1)
		return
	lighting.call("set_realistic_tree_shadow_enabled", false)
	lighting.call("set_foliage_shadow_enabled", true)
	var foliage: Node = lighting.call("get_foliage_shadow") as Node
	if foliage != null:
		foliage.call("advance_motion", 3.0)
	await _wait_frames(12)
	if not _capture("level_2_night_procedural_foliage_shadow.png"):
		quit(1)
		return
	lighting.call("set_foliage_shadow_enabled", false)
	await _wait_frames(8)
	if not _capture("level_2_night_no_tree_shadow.png"):
		quit(1)
		return
	main.queue_free()
	await _wait_frames(6)
	quit(0)


func _capture(filename: String) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	if directory_error != OK:
		push_error("Unable to create capture directory: %s" % error_string(directory_error))
		return false
	var image := root.get_viewport().get_texture().get_image()
	var output_path := "%s/%s" % [OUTPUT_DIRECTORY, filename]
	var save_error := image.save_png(ProjectSettings.globalize_path(output_path))
	if save_error != OK:
		push_error("Unable to save %s: %s" % [output_path, error_string(save_error)])
		return false
	print("Captured %s" % output_path)
	return true


func _wait_frames(frame_count: int) -> void:
	for _frame_index in frame_count:
		await process_frame
