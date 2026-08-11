## Manual visual-regression capture for the current Level2 display case lighting.
##
## Run without --headless so the viewport uses the project's Forward+ renderer:
## godot --path <project> --script res://tests/lighting_visual_capture.gd
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const LightingTestLevel := preload("res://resources/levels/Level2.tres")
const OUTPUT_DIRECTORY := "res://outputs/lighting_profiles"
const PROFILE_FILENAMES: Array[String] = [
	"level_2_white_soft.png",
	"level_2_warm_yellow.png",
	"level_2_cyan_red.png",
	"level_2_night_spotlight.png",
]


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	var main: Node = MainScene.instantiate()
	if not bool(main.call("configure_startup_level", LightingTestLevel)):
		push_error("Unable to configure Level2 as the startup level")
		quit(1)
		return
	root.add_child(main)
	await _wait_frames(20)
	var camera_presets: Node = main.get("camera_preset_controller") as Node
	if camera_presets != null:
		camera_presets.set("transition_duration", 0.0)
		camera_presets.call("request_preset", 0)
		await _wait_frames(4)

	var controller: Node = main.get("lighting_controller") as Node
	if controller == null:
		push_error("LightingController was not created")
		quit(1)
		return
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		push_error("Unable to create visual capture directory: %s" % error_string(directory_error))
		quit(1)
		return

	for profile_index in PROFILE_FILENAMES.size():
		if not bool(controller.call("apply_profile_by_index", profile_index, 0.0)):
			push_error("Unable to apply lighting profile index %d" % profile_index)
			quit(1)
			return
		await _wait_frames(12)
		var image := root.get_viewport().get_texture().get_image()
		var output_path := "%s/%s" % [OUTPUT_DIRECTORY, PROFILE_FILENAMES[profile_index]]
		var save_error := image.save_png(ProjectSettings.globalize_path(output_path))
		if save_error != OK:
			push_error("Unable to save %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("Captured %s" % output_path)

	main.queue_free()
	await _wait_frames(4)
	quit(0)


func _wait_frames(frame_count: int) -> void:
	for _frame_index in frame_count:
		await process_frame
