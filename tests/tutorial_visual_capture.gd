## Manual Forward+ captures for the player tutorial overlay and live editor.
extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const ArrowTower := preload("res://resources/buildings/ArrowTower.tres")
const PLAYER_OUTPUT := "res://outputs/ui/tutorial_player_overlay.png"
const EDITOR_OUTPUT := "res://outputs/ui/tutorial_runtime_editor.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var level := Level1.duplicate(true) as LevelResource
	var tutorial := TutorialDefinition.new()
	var event := TutorialEventDefinition.new()
	event.event_id = &"capture"
	event.display_name = "第一次建造"
	event.gated_wave_number = 1
	var bubble := TutorialBubbleDefinition.new()
	bubble.text = "敌人即将出现！\n请在红色格子放置一座箭塔，并调整至箭头所示方向。"
	bubble.screen_position = Vector2(430.0, 210.0)
	bubble.dismiss_condition = TutorialBubbleDefinition.DismissCondition.EVENT_COMPLETED
	event.bubbles.append(bubble)
	var hidden := TutorialGoalDefinition.new()
	hidden.goal_type = TutorialGoalDefinition.GoalType.ACKNOWLEDGE_ALL_BUBBLES
	hidden.show_in_checklist = false
	event.goals.append(hidden)
	var placement := TutorialGoalDefinition.new()
	placement.goal_type = TutorialGoalDefinition.GoalType.PLACE_BUILDING
	placement.description = "在红色格子放置箭塔并对准方向"
	placement.building_definition = ArrowTower
	placement.require_cell = true
	placement.target_cell = Vector3i(0, 0, 0)
	placement.require_facing = true
	placement.target_facing_index = 9
	event.goals.append(placement)
	tutorial.events.append(event)
	level.tutorial = tutorial
	var main := MainScene.instantiate() as MainController
	main.configure_startup_level(level)
	root.add_child(main)
	for _frame in 45:
		await process_frame
	if not _save_viewport(PLAYER_OUTPUT):
		quit(1)
		return
	main.tutorial_runtime_editor.set_active(true)
	for _frame in 4:
		await process_frame
	if not _save_viewport(EDITOR_OUTPUT):
		quit(1)
		return
	print("Captured tutorial overlay and editor")
	main.queue_free()
	await process_frame
	quit(0)


func _save_viewport(path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Unable to save tutorial capture: %s" % error_string(error))
		return false
	return true
