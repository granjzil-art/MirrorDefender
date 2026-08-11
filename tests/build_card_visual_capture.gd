## Manual visual-regression capture for the procedural build-card treatment.
##
## The colored tower silhouettes are generated in memory; production cards only
## need to assign a transparent BuildingDefinition.card_icon texture.
extends SceneTree

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const PROCEDURAL_OUTPUT_PATH := "res://outputs/ui/procedural_build_cards.png"
const FULL_ART_OUTPUT_PATH := "res://outputs/ui/full_art_build_cards.png"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	root.size = Vector2i(1600, 900)
	RenderingServer.set_default_clear_color(Color(0.025, 0.035, 0.045, 1.0))
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var level := LevelResource.new()
	level.initial_resource = 500
	level.building_cap = 12
	level.mirror_cap = 4
	resource_manager.apply_level_configuration(level)

	var arrow := _make_card(BuildingDefinition.Kind.ARROW_TOWER, "箭塔", Color(0.76, 0.54, 0.30))
	var laser := _make_card(BuildingDefinition.Kind.LASER_TOWER, "激光塔", Color(0.25, 0.72, 0.94))
	var barrier := _make_card(BuildingDefinition.Kind.BARRIER, "屏障", Color(0.53, 0.68, 0.78))
	var cards: Array[BuildingDefinition] = [arrow, laser, barrier]
	var card_bar := BuildCardBarScript.new()
	card_bar.position = Vector2(400.0, 300.0)
	card_bar.size = Vector2(800.0, 176.0)
	host.add_child(card_bar)
	await process_frame
	card_bar.configure(
		resource_manager,
		TestDefinitionFactory.make_copy_mirror_definition(),
		cards,
		4
	)
	card_bar.set_selected_building(arrow)
	for _frame in 12:
		await process_frame

	var output_directory := ProjectSettings.globalize_path("res://outputs/ui")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Unable to create UI capture directory: %s" % error_string(directory_error))
		quit(1)
		return
	if not _capture(PROCEDURAL_OUTPUT_PATH):
		quit(1)
		return

	var full_arrow := load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition
	var full_mace := load("res://resources/buildings/MaceTower.tres") as BuildingDefinition
	var full_cards: Array[BuildingDefinition] = [full_arrow, full_mace]
	card_bar.configure(
		resource_manager,
		TestDefinitionFactory.make_copy_mirror_definition(),
		full_cards,
		3
	)
	card_bar.set_card_visual_mode(BuildCardBarScript.CardVisualMode.FULL_ARTWORK)
	card_bar.set_selected_building(full_mace)
	for _frame in 8:
		await process_frame
	if not _capture(FULL_ART_OUTPUT_PATH):
		quit(1)
		return
	host.queue_free()
	await process_frame
	quit(0)


func _make_card(kind: BuildingDefinition.Kind, title: String, color: Color) -> BuildingDefinition:
	var definition := TestDefinitionFactory.make_building_definition(kind)
	definition.display_name = title
	definition.card_icon = _make_tower_icon(color)
	return definition


func _make_tower_icon(color: Color) -> Texture2D:
	var image := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var dark := color.darkened(0.28)
	var light := color.lightened(0.20)
	image.fill_rect(Rect2i(16, 101, 64, 15), dark)
	image.fill_rect(Rect2i(24, 84, 48, 20), color)
	image.fill_rect(Rect2i(31, 38, 34, 49), dark)
	image.fill_rect(Rect2i(24, 31, 48, 14), light)
	image.fill_rect(Rect2i(27, 20, 9, 16), color)
	image.fill_rect(Rect2i(44, 17, 9, 19), color)
	image.fill_rect(Rect2i(61, 20, 9, 16), color)
	image.fill_rect(Rect2i(45, 2, 6, 21), light)
	image.fill_rect(Rect2i(51, 5, 27, 11), color)
	return ImageTexture.create_from_image(image)


func _capture(output_path: String) -> bool:
	var viewport_image := root.get_viewport().get_texture().get_image()
	var image := viewport_image.get_region(Rect2i(480, 325, 640, 170))
	var save_error := image.save_png(ProjectSettings.globalize_path(output_path))
	if save_error != OK:
		push_error("Unable to save card preview: %s" % error_string(save_error))
		return false
	print("Captured %s" % output_path)
	return true
