## Manual Forward+ capture for the right-top icon-only runtime statistics.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const OUTPUT_PATH := "res://outputs/ui/global_info_icons.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var main := MainScene.instantiate() as MainController
	if not main.configure_startup_level(Level1):
		push_error("Unable to configure Level1 for global-info capture")
		quit(1)
		return
	root.add_child(main)
	for _frame in 36:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Unable to save global-info capture: %s" % error_string(error))
		quit(1)
		return
	print("Captured %s" % OUTPUT_PATH)
	main.queue_free()
	await process_frame
	quit(0)
