extends Node3D

const TARGETS := [
	{
		"name": "Desert Castle",
		"source": "res://assets/buildings/Castle/fbx/desertcastle.fbx",
		"original_triangles": 999102,
		"variants": [
			["70% / 699,370 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/desert_castle/desert_castle_70.scn"],
			["50% / 499,550 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/desert_castle/desert_castle_50.scn"],
			["30% / 299,730 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/desert_castle/desert_castle_30.scn"],
		],
	},
	{
		"name": "Arrow Tower 3-1",
		"source": "res://assets/buildings/ArrowTower/fbx/arrowtower3_1.fbx",
		"original_triangles": 998471,
		"variants": [
			["70% / 698,929 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/arrow_tower_3_1/arrow_tower_3_1_70.scn"],
			["50% / 499,235 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/arrow_tower_3_1/arrow_tower_3_1_50.scn"],
			["30% / 299,541 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/arrow_tower_3_1/arrow_tower_3_1_30.scn"],
		],
	},
	{
		"name": "Mace 8",
		"source": "res://assets/buildings/mace/mace8.glb",
		"original_triangles": 598066,
		"variants": [
			["70% / 418,646 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/mace_8/mace_8_70.scn"],
			["50% / 299,032 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/mace_8/mace_8_50.scn"],
			["30% / 179,418 tris", "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/mace_8/mace_8_30.scn"],
		],
	},
]

const SLOT_X := [-7.5, -2.5, 2.5, 7.5]
const MODEL_FIT_SIZE := 4.0

var _camera: Camera3D
var _info_label: Label
var _target_index := 0
var _yaw := 0.0
var _dragging := false
var _wireframe_enabled := false
var _wireframe_material: ShaderMaterial
var _display_nodes: Array[Node3D] = []


func _ready() -> void:
	_setup_environment()
	_setup_ui()
	_show_target(0)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_batch.call_deferred()


func _setup_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171a20")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5def0")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_color = Color("fff1d6")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_color = Color("9ab6ff")
	fill_light.light_energy = 0.55
	fill_light.shadow_enabled = false
	add_child(fill_light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.4, 16.5)
	_camera.fov = 55.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

	var wireframe_shader := Shader.new()
	wireframe_shader.code = (
		"shader_type spatial;\n"
		+ "render_mode unshaded, wireframe, cull_disabled;\n"
		+ "void fragment() { ALBEDO = vec3(0.30, 0.86, 1.0); }\n"
	)
	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = wireframe_shader


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(690.0, 0.0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 17)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_info_label)


func _show_target(index: int) -> void:
	_target_index = posmod(index, TARGETS.size())
	for node in _display_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_display_nodes.clear()

	var target: Dictionary = TARGETS[_target_index]
	var entries := [
		["Original / %s tris" % _format_integer(int(target.original_triangles)), str(target.source)],
	]
	entries.append_array(target.variants)

	for slot_index in entries.size():
		var entry: Array = entries[slot_index]
		var packed_scene := load(str(entry[1])) as PackedScene
		if packed_scene == null:
			push_error("Cannot load comparison resource: %s" % entry[1])
			continue

		var slot := Node3D.new()
		slot.position.x = SLOT_X[slot_index]
		slot.rotation.y = _yaw
		add_child(slot)
		_display_nodes.append(slot)

		var model := packed_scene.instantiate() as Node3D
		slot.add_child(model)
		var bounds := _calculate_bounds(model)
		var largest_extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var fit_scale := MODEL_FIT_SIZE / largest_extent if largest_extent > 0.0001 else 1.0
		model.scale = Vector3.ONE * fit_scale
		model.position = -bounds.get_center() * fit_scale
		_set_model_wireframe(model, _wireframe_enabled)

		var label := Label3D.new()
		label.text = str(entry[0])
		label.position = Vector3(0.0, -2.65, 0.0)
		label.font_size = 44
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot.add_child(label)

	_info_label.text = (
		"Programmatic decimation evaluation — %s\n" % target.name
		+ "[1] Castle   [2] Arrow Tower   [3] Mace   [W] Wireframe   |   Left-drag: rotate all   Mouse wheel: zoom\n"
		+ "All four views share source transforms and materials. No production model/import setting is changed."
	)


func _calculate_bounds(root: Node3D) -> AABB:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	var has_bounds := false
	var bounds := AABB()
	var to_root := root.global_transform.affine_inverse()
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue
		var relative_transform := to_root * mesh_instance.global_transform
		var mesh_bounds := relative_transform * mesh_instance.get_aabb()
		if has_bounds:
			bounds = bounds.merge(mesh_bounds)
		else:
			bounds = mesh_bounds
			has_bounds = true
	return bounds if has_bounds else AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, output)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_show_target(0)
			KEY_2:
				_show_target(1)
			KEY_3:
				_show_target(2)
			KEY_W:
				_wireframe_enabled = not _wireframe_enabled
				for slot in _display_nodes:
					_set_model_wireframe(slot, _wireframe_enabled)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.position.z = maxf(9.0, _camera.position.z - 1.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.position.z = minf(28.0, _camera.position.z + 1.0)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.008
		for slot in _display_nodes:
			slot.rotation.y = _yaw


func _format_integer(value: int) -> String:
	var text := str(value)
	var output := ""
	while text.length() > 3:
		output = "," + text.right(3) + output
		text = text.left(text.length() - 3)
	return text + output


func _set_model_wireframe(root: Node, enabled: bool) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = _wireframe_material if enabled else null
	for child in root.get_children():
		_set_model_wireframe(child, enabled)


func _capture_batch() -> void:
	var output_names := ["desert_castle", "arrow_tower_3_1", "mace_8"]
	for index in TARGETS.size():
		_show_target(index)
		for frame in 4:
			await get_tree().process_frame
		var texture := get_viewport().get_texture()
		var image := texture.get_image() if texture != null else null
		var output_path := "res://outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/comparison_%s.png" % output_names[index]
		if image == null:
			push_error("The active display driver does not expose a rendered viewport image")
			break
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("Cannot save comparison capture: %s" % error_string(save_error))
		else:
			print("Saved comparison capture: %s" % output_path)
	get_tree().quit()
