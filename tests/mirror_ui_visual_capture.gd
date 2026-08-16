## Manual Forward+ captures for mirror card descriptions and contextual actions.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const HOVER_OUTPUT_PATH := "res://outputs/ui/mirror_card_hover_description.png"
const ACTION_OUTPUT_PATH := "res://outputs/ui/mirror_context_actions.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var main := MainScene.instantiate() as MainController
	if not main.configure_startup_level(Level1):
		push_error("Unable to configure Level1 for mirror UI capture")
		quit(1)
		return
	root.add_child(main)
	for _frame in 40:
		await process_frame

	var card := main.get_node_or_null(
		"HUD/RuntimeHud/BuildCardBar/Layout/MirrorCards/ReflectMirrorCard"
	) as Button
	if card == null:
		push_error("Unable to find the formal reflect-mirror card")
		quit(1)
		return
	card.mouse_entered.emit()
	for _frame in 3:
		await process_frame
	if not _save_viewport(HOVER_OUTPUT_PATH):
		quit(1)
		return
	card.mouse_exited.emit()

	var mirrors := main.mirror_manager.get_mirrors()
	if mirrors.is_empty():
		push_error("Level1 has no physical mirror for contextual-action capture")
		quit(1)
		return
	main.mirror_manager.select_mirror(mirrors[0])
	for _frame in 4:
		await process_frame
	if not _save_viewport(ACTION_OUTPUT_PATH):
		quit(1)
		return
	main.queue_free()
	await process_frame
	quit(0)


func _save_viewport(output_path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Unable to save mirror UI capture: %s" % error_string(error))
		return false
	print("Captured %s" % output_path)
	return true
