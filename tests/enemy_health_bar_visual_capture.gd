extends SceneTree

const EnemyHealthBarScript := preload("res://scripts/ui/EnemyHealthBar3D.gd")
const OUTPUT_PATH := "res://outputs/ui/enemy_health_bar_preview.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	RenderingServer.set_default_clear_color(Color(0.055, 0.06, 0.075, 1.0))
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.7
	camera.position = Vector3(0.0, 0.0, 4.0)
	camera.current = true
	scene.add_child(camera)
	_add_bar(scene, Vector3(0.0, 0.42, 0.0), 100.0, 80.0, 68.0)
	_add_bar(scene, Vector3(0.0, -0.42, 0.0), 200.0, 140.0, 110.0)
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/ui"))
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Failed to save enemy health bar preview: %s" % error_string(error))
		quit(1)
		return
	print("[EnemyHealthBarVisualCapture] wrote %s" % OUTPUT_PATH)
	quit(0)


func _add_bar(
	parent: Node3D,
	world_position: Vector3,
	maximum_hp: float,
	previous_hp: float,
	current_hp: float
) -> void:
	var anchor := Node3D.new()
	anchor.position = world_position
	parent.add_child(anchor)
	var bar := EnemyHealthBarScript.new()
	bar.configure(maximum_hp, maximum_hp, 0.0)
	anchor.add_child(bar)
	bar.update_health(previous_hp, maximum_hp)
	bar._process(EnemyHealthBarScript.FLASH_DURATION + 0.01)
	bar.update_health(current_hp, maximum_hp)
