## Manual Forward+ comparison capture for the procedural foliage shadow layer.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const DemoLevel := preload("res://resources/levels/DemoLevel1.tres")
const OUTPUT_DIRECTORY := "res://outputs/foliage_shadow"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	var main: Node = MainScene.instantiate()
	if not bool(main.call("configure_startup_level", DemoLevel)):
		push_error("Unable to configure DemoLevel1")
		quit(1)
		return
	root.add_child(main)
	await _wait_frames(24)
	var camera_presets: Node = main.get("camera_preset_controller") as Node
	if camera_presets != null:
		camera_presets.set("transition_duration", 0.0)
		camera_presets.call("request_preset", 0)
		await _wait_frames(8)
	var camera_rig: Node = main.get("cam_rig") as Node
	if camera_rig != null:
		camera_rig.call("apply_view_state", Vector3(9.5, 0.0, 4.0), -4.071416, 52.0, 13.0)
	var miniature_dof: Node = main.get("miniature_dof_controller") as Node
	if miniature_dof != null:
		miniature_dof.call("set_effect_enabled", false)
	await _wait_frames(8)
	var lighting: Node = main.get("lighting_controller") as Node
	var foliage: Node = lighting.call("get_foliage_shadow") as Node
	if foliage == null:
		push_error("FoliageShadowController was not created")
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	if directory_error != OK:
		push_error("Unable to create capture directory: %s" % error_string(directory_error))
		quit(1)
		return
	foliage.call("advance_motion", 3.0)
	await _wait_frames(12)
	if not _capture("demo_level_1_foliage_shadow_enabled.png"):
		quit(1)
		return
	lighting.call("set_foliage_shadow_enabled", false)
	await _wait_frames(12)
	if not _capture("demo_level_1_foliage_shadow_disabled.png"):
		quit(1)
		return
	main.queue_free()
	await _wait_frames(6)
	quit(0)


func _capture(filename: String) -> bool:
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
