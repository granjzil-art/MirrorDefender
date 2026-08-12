## Manual Forward+ visual-regression capture for Level1's sun and cloud volume.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const OUTPUT_PATH := "res://outputs/level1_sun_cloud_showcase.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var main := MainScene.instantiate() as MainController
	main.realistic_tree_shadow_enabled = false
	main.foliage_shadow_enabled = false
	if not main.configure_startup_level(Level1):
		push_error("Unable to configure Level1 for sky decoration capture")
		quit(1)
		return
	root.add_child(main)
	for _frame in 24:
		await process_frame
	main.cam_rig.apply_view_state(Vector3(7.5, 7.0, 7.3), -25.0, 30.0, 32.0)
	main.get_node("HUD").visible = false
	for _frame in 72:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Unable to save Level1 sky capture: %s" % error_string(error))
		quit(1)
		return
	print("Captured %s" % OUTPUT_PATH)
	main.queue_free()
	await process_frame
	quit(0)
