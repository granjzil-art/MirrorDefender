extends Node3D

const TARGETS := [
	{
		"name": "Dalishi block",
		"original": "res://assets/blocks/fbx/dalishi.fbx",
		"reduced": "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/models/blocks/fbx/dalishi_20pct.scn",
		"original_triangles": 9910,
		"reduced_triangles": 1936,
	},
	{
		"name": "Crossbow",
		"original": "res://assets/buildings/crossbow/crossbow.glb",
		"reduced": "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/models/buildings/crossbow/crossbow_20pct.scn",
		"original_triangles": 29998,
		"reduced_triangles": 5931,
	},
	{
		"name": "Nails",
		"original": "res://assets/projections/Nail/nails/scene.gltf",
		"reduced": "res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/models/projections/Nail/nails/scene_20pct.scn",
		"original_triangles": 5112,
		"reduced_triangles": 1018,
	},
]

var _camera: Camera3D
var _info: Label
var _slots: Array[Node3D] = []
var _wireframe_material: ShaderMaterial
var _wireframe := false
var _dragging := false
var _yaw := 0.0


func _ready() -> void:
	_setup_world()
	_setup_ui()
	_show_target(0)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_batch.call_deferred()


func _setup_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171a20")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5def0")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill_light.light_color = Color("9bb9ff")
	fill_light.light_energy = 0.5
	add_child(fill_light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.25, 11.5)
	_camera.fov = 52.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)

	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, wireframe, cull_disabled;\nvoid fragment(){ALBEDO=vec3(0.30,0.86,1.0);}\n"
	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = shader


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(760, 0)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 17)
	margin.add_child(_info)


func _show_target(index: int) -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	var target: Dictionary = TARGETS[posmod(index, TARGETS.size())]
	var entries := [
		["Original / %s tris" % _format_integer(target.original_triangles), target.original],
		["20%% / %s tris" % _format_integer(target.reduced_triangles), target.reduced],
	]
	for slot_index in entries.size():
		var scene := load(str(entries[slot_index][1])) as PackedScene
		var slot := Node3D.new()
		slot.position.x = -3.25 if slot_index == 0 else 3.25
		slot.rotation.y = _yaw
		add_child(slot)
		_slots.append(slot)
		var model := scene.instantiate() as Node3D
		slot.add_child(model)
		var bounds := _bounds(model)
		var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var scale_factor := 5.0 / extent if extent > 0.0001 else 1.0
		model.scale = Vector3.ONE * scale_factor
		model.position = -bounds.get_center() * scale_factor
		_set_wireframe(model, _wireframe)
		var label := Label3D.new()
		label.text = str(entries[slot_index][0])
		label.position.y = -3.0
		label.font_size = 44
		label.outline_size = 8
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot.add_child(label)
	_info.text = "%s   |   [1] Dalishi  [2] Crossbow  [3] Nails  [W] Wireframe   Left-drag: rotate   Wheel: zoom" % target.name


func _bounds(root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var has_bounds := false
	var result := AABB()
	var to_root := root.global_transform.affine_inverse()
	for mesh_instance in meshes:
		var value := (to_root * mesh_instance.global_transform) * mesh_instance.get_aabb()
		result = result.merge(value) if has_bounds else value
		has_bounds = true
	return result if has_bounds else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


func _set_wireframe(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _wireframe_material if enabled else null
	for child in node.get_children():
		_set_wireframe(child, enabled)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _show_target(0)
			KEY_2: _show_target(1)
			KEY_3: _show_target(2)
			KEY_W:
				_wireframe = not _wireframe
				for slot in _slots:
					_set_wireframe(slot, _wireframe)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.position.z = maxf(7.0, _camera.position.z - 0.75)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.position.z = minf(22.0, _camera.position.z + 0.75)
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.008
		for slot in _slots:
			slot.rotation.y = _yaw


func _capture_batch() -> void:
	var names := ["dalishi", "crossbow", "nails"]
	for index in TARGETS.size():
		_show_target(index)
		for frame in 4:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png("res://outputs/model_decimation_20pct/2026-08-16_all_models_20pct/comparison_%s.png" % names[index])
	get_tree().quit()


func _format_integer(value: Variant) -> String:
	var text := str(int(value))
	var output := ""
	while text.length() > 3:
		output = "," + text.right(3) + output
		text = text.left(text.length() - 3)
	return text + output
