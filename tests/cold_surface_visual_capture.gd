## Manual Forward+ comparison of an authored enemy model before and during cold.
extends SceneTree

const OUTPUT_PATH := "res://outputs/laser_visual/cold_surface_shader_preview.png"


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
	environment.ambient_light_color = Color(0.30, 0.36, 0.46, 1.0)
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_color = Color(0.84, 0.90, 1.0, 1.0)
	light.light_energy = 1.4
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(7.0, 4.5)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.045, 0.06, 0.09, 1.0)
	ground_material.roughness = 0.88
	ground.material_override = ground_material
	world.add_child(ground)
	var definition := load("res://resources/enemies/Grunt.tres") as EnemyDefinition
	if definition == null or definition.get_model_asset() == null:
		push_error("Grunt model is unavailable for cold-surface capture")
		quit(1)
		return
	var normal_target := _make_target(definition, Vector3(-0.9, 0.0, 0.0))
	world.add_child(normal_target)
	var cold_target := _make_target(definition, Vector3(0.9, 0.0, 0.0))
	world.add_child(cold_target)
	cold_target.apply_movement_slow(0.4, 30.0)
	var labels := Control.new()
	labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(labels)
	_add_label(labels, "原模型", Vector2(370.0, 158.0), Color.WHITE)
	_add_label(labels, "寒冷 Shader", Vector2(744.0, 158.0), Color(0.34, 0.55, 1.0))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, 2.35, 4.6)
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
	camera.fov = 37.0
	camera.current = true
	for _frame in 24:
		await process_frame
	var output_directory := ProjectSettings.globalize_path("res://outputs/laser_visual")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Unable to create cold capture directory: %s" % error_string(directory_error))
		quit(1)
		return
	var image := root.get_texture().get_image()
	var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		push_error("Unable to save cold capture: %s" % error_string(save_error))
		quit(1)
		return
	print("[ColdSurfaceVisualCapture] wrote %s" % OUTPUT_PATH)
	world.queue_free()
	await process_frame
	quit(0)


func _make_target(definition: EnemyDefinition, position_value: Vector3) -> CombatTarget:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.model_asset = definition.get_model_asset()
	target.debug_height = definition.body_height
	target.hit_radius = definition.hit_radius
	target.position = position_value
	return target


func _add_label(parent: Control, text_value: String, position_value: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", 36)
	label.modulate = color
	parent.add_child(label)
