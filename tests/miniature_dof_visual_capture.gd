## Manual visual-regression capture for DemoLevel1 miniature depth of field.
##
## Run without --headless so the viewport uses the project's Forward+ renderer:
## godot --path <project> --script res://tests/miniature_dof_visual_capture.gd
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const DemoLevel := preload("res://resources/levels/DemoLevel1.tres")
const OUTPUT_DIRECTORY := "res://outputs/miniature_dof"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	var main: Node = MainScene.instantiate()
	if not bool(main.call("configure_startup_level", DemoLevel)):
		push_error("Unable to configure DemoLevel1 as the startup level")
		quit(1)
		return
	root.add_child(main)
	await _wait_frames(20)
	var camera_presets: Node = main.get("camera_preset_controller") as Node
	if camera_presets != null:
		camera_presets.set("transition_duration", 0.0)
		camera_presets.call("request_preset", 0)
		await _wait_frames(8)

	var controller: Node = main.get("miniature_dof_controller") as Node
	if controller == null:
		push_error("MiniatureDofController was not created")
		quit(1)
		return
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		push_error("Unable to create visual capture directory: %s" % error_string(directory_error))
		quit(1)
		return

	if not await _capture("demo_level_1_dof_enabled.png"):
		quit(1)
		return
	controller.call("set_effect_enabled", false)
	await _wait_frames(12)
	if not await _capture("demo_level_1_dof_disabled.png"):
		quit(1)
		return

	main.queue_free()
	await _wait_frames(4)
	quit(0)


func _capture(filename: String) -> bool:
	await process_frame
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
