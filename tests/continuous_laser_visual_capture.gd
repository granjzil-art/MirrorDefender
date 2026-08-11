## Manual visual-regression capture for the continuous laser's central axis,
## translated travelling sine filaments, and endpoint treatment.
extends SceneTree

const ContinuousLaserVisualScript := preload("res://scripts/combat/ContinuousLaserVisual.gd")
const OUTPUT_PATH := "res://outputs/laser_visual/continuous_laser_wave_preview.png"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	root.size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color(0.012, 0.018, 0.03, 1.0))
	var world := Node3D.new()
	root.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.018, 0.03, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.24, 0.32, 1.0)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	world.add_child(environment_node)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12.0, 7.0)
	ground.mesh = ground_mesh
	ground.position.y = -0.18
	var ground_material := StandardMaterial3D.new()
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_material.albedo_color = Color(0.028, 0.045, 0.07, 1.0)
	ground.material_override = ground_material
	world.add_child(ground)
	var visual := ContinuousLaserVisualScript.new()
	world.add_child(visual)
	visual.configure(Color(0.88, 0.96, 1.0, 0.96), 0.16, 4.5)
	visual.show_path(
		[{
			"start": Vector3(-4.2, 0.0, 0.0),
			"end": Vector3(4.2, 0.0, 0.0),
		}],
		Vector3(4.2, 0.0, 0.0)
	)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, 5.4, 6.6)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.fov = 43.0
	camera.current = true
	for _frame in 24:
		await process_frame
	var output_directory := ProjectSettings.globalize_path("res://outputs/laser_visual")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Unable to create laser capture directory: %s" % error_string(directory_error))
		quit(1)
		return
	var image := root.get_texture().get_image()
	var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		push_error("Unable to save laser capture: %s" % error_string(save_error))
		quit(1)
		return
	print("[ContinuousLaserVisualCapture] wrote %s" % OUTPUT_PATH)
	world.queue_free()
	await process_frame
	quit(0)
