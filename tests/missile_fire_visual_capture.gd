## Manual visual-regression capture for cached flame sprites and the layered
## red/orange/yellow missile pressure wave.
extends SceneTree

const OUTPUT_PATH := "res://outputs/missile_visual/missile_fire_preview.png"


func _initialize() -> void:
	_run_capture.call_deferred()


func _run_capture() -> void:
	root.size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color(0.012, 0.014, 0.022, 1.0))
	var world := Node3D.new()
	root.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.014, 0.022, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.30, 0.36, 1.0)
	environment.ambient_light_energy = 0.72
	environment.glow_enabled = true
	environment.glow_intensity = 0.78
	environment_node.environment = environment
	world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_color = Color(1.0, 0.74, 0.50, 1.0)
	light.light_energy = 1.35
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(8.0, 5.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.055, 0.045, 0.052, 1.0)
	ground_material.roughness = 0.86
	ground.material_override = ground_material
	world.add_child(ground)
	var definition := load("res://resources/enemies/Grunt.tres") as EnemyDefinition
	if definition == null or definition.get_model_asset() == null:
		push_error("Grunt model is unavailable for missile-fire capture")
		quit(1)
		return
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.model_asset = definition.get_model_asset()
	target.debug_height = definition.body_height
	target.hit_radius = definition.hit_radius
	target.position = Vector3(-1.25, 0.0, 0.0)
	world.add_child(target)
	target.apply_burning(12.0, 30.0)
	var explosion := MissileExplosionEffect.new()
	world.add_child(explosion)
	explosion.configure(Vector3(1.35, 0.06, 0.0), 1.15, Color.SKY_BLUE, 1.0)
	explosion.set_process(false)
	explosion._process(0.28)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, 3.65, 6.2)
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
	camera.fov = 39.0
	camera.current = true
	var labels := Control.new()
	labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(labels)
	_add_label(labels, "燃烧状态 GPU 火焰", Vector2(245.0, 145.0), Color(1.0, 0.46, 0.10))
	_add_label(labels, "导弹爆炸 红 / 橙 / 黄", Vector2(700.0, 145.0), Color(1.0, 0.72, 0.16))
	for _frame in 24:
		await process_frame
	var output_directory := ProjectSettings.globalize_path("res://outputs/missile_visual")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Unable to create missile capture directory: %s" % error_string(directory_error))
		quit(1)
		return
	var image := root.get_texture().get_image()
	var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		push_error("Unable to save missile-fire capture: %s" % error_string(save_error))
		quit(1)
		return
	print("[MissileFireVisualCapture] wrote %s" % OUTPUT_PATH)
	world.queue_free()
	await process_frame
	quit(0)


func _add_label(parent: Control, text_value: String, position_value: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", 32)
	label.modulate = color
	parent.add_child(label)
