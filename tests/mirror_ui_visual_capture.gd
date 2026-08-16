## Manual Forward+ captures for mirror card descriptions, actions, and upgraded presentation.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const HOVER_OUTPUT_PATH := "res://outputs/ui/mirror_card_hover_description.png"
const ACTION_OUTPUT_PATH := "res://outputs/ui/mirror_context_actions.png"
const UPGRADED_FRAME_OUTPUT_PATH := "res://outputs/ui/mirror_upgraded_frame_glow.png"


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
	main.mirror_manager.select_mirror(null)
	var upgraded_mirror := mirrors[0]
	if not upgraded_mirror.set_level(2):
		push_error("Unable to upgrade the mirror for frame-glow capture")
		quit(1)
		return
	var mirror_center := (
		upgraded_mirror.global_position
		+ Vector3.UP * upgraded_mirror.get_mirror_height() * 0.5
	)
	var close_camera := Camera3D.new()
	main.add_child(close_camera)
	close_camera.global_position = (
		mirror_center
		+ upgraded_mirror.get_active_normal() * 2.2
		+ upgraded_mirror.get_edge_direction().normalized() * 1.2
		+ Vector3.UP * 1.1
	)
	close_camera.look_at(mirror_center)
	close_camera.fov = 32.0
	close_camera.make_current()
	var hud_layer := main.get_node_or_null("HUD") as CanvasLayer
	if hud_layer != null:
		hud_layer.visible = false
	for _frame in 4:
		await process_frame
	if not _save_viewport(UPGRADED_FRAME_OUTPUT_PATH):
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
