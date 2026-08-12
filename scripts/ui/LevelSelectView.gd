@tool
## Four-face portal-rendered level-selection cube.
class_name LevelSelectView
extends Control

const LevelSelectCatalogScript := preload("res://scripts/level/LevelSelectCatalog.gd")
const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")
const LevelPortalPreviewScript := preload("res://scripts/ui/LevelPortalPreview.gd")

const SLOT_COUNT: int = 4
const CUBE_SIZE: float = 4.0
const CUBE_HALF_SIZE: float = CUBE_SIZE * 0.5
const FACE_COLLISION_LAYER_NUMBER: int = 12
const FACE_COLLISION_MASK: int = 1 << (FACE_COLLISION_LAYER_NUMBER - 1)

signal level_selected(level: LevelResource)

@export_group("Cube Interaction")
@export_range(0.001, 0.02, 0.0005) var drag_sensitivity: float = 0.006
@export_range(0.0, 30.0, 0.1) var inertia_damping: float = 8.0
@export_range(-45.0, 15.0, 0.5) var minimum_pitch_degrees: float = -14.0
@export_range(45.0, 88.0, 0.5) var maximum_pitch_degrees: float = 78.0
@export_range(-180.0, 180.0, 0.5) var initial_yaw_degrees: float = -32.0
@export_range(-20.0, 70.0, 0.5) var initial_pitch_degrees: float = 18.0

@onready var _cube_container: SubViewportContainer = %CubeViewportContainer
@onready var _cube_viewport: SubViewport = %CubeViewport
@onready var _interaction_hint: Label = %InteractionHint

var _catalog: LevelSelectCatalogScript
var _current_page_index: int = 0
var _levels: Array[LevelResource] = []
var _previews: Array[LevelPortalPreviewScript] = []
var _face_roots: Array[Node3D] = []
var _face_meshes: Array[MeshInstance3D] = []
var _face_areas: Array[Area3D] = []
var _face_materials: Array[StandardMaterial3D] = []
var _cube_world_root: Node3D
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _cube_root: Node3D
var _cube_camera: Camera3D
var _title_face: MeshInstance3D
var _base_root: Node3D
var _right_dragging: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _angular_velocity := Vector2.ZERO
var _hovered_face_index: int = -1
var _selection_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_levels.resize(SLOT_COUNT)
	_yaw = deg_to_rad(initial_yaw_degrees)
	_pitch = deg_to_rad(initial_pitch_degrees)
	_cube_viewport.world_3d = World3D.new()
	_cube_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cube_container.gui_input.connect(_on_cube_gui_input)
	_build_portal_previews()
	_build_cube_world()
	_apply_cube_rotation()
	_refresh_levels()
	return


func _exit_tree() -> void:
	_right_dragging = false
	_angular_velocity = Vector2.ZERO
	release_loaded_level_resources()
	return


func _process(delta: float) -> void:
	var moving := _right_dragging
	if not _right_dragging and _angular_velocity.length_squared() > 0.000001:
		_yaw += _angular_velocity.x * delta
		var requested_pitch := _pitch + _angular_velocity.y * delta
		_pitch = clampf(
			requested_pitch,
			deg_to_rad(minimum_pitch_degrees),
			deg_to_rad(maximum_pitch_degrees)
		)
		if not is_equal_approx(requested_pitch, _pitch):
			_angular_velocity.y = 0.0
		_angular_velocity *= exp(-inertia_damping * delta)
		if _angular_velocity.length() < 0.002:
			_angular_velocity = Vector2.ZERO
		moving = true
		_apply_cube_rotation()
	_update_portal_cameras(moving)
	return


func configure(catalog: LevelSelectCatalogScript) -> void:
	_catalog = catalog
	_current_page_index = 0
	_selection_locked = false
	if is_node_ready():
		_refresh_levels()
	return


func get_catalog() -> LevelSelectCatalogScript:
	return _catalog


func get_current_page_index() -> int:
	return _current_page_index


func get_page_count() -> int:
	return _catalog.get_page_count() if _catalog != null else 0


func get_slot_count() -> int:
	return SLOT_COUNT


func get_face_count() -> int:
	return _face_roots.size()


func get_slot_level(slot_index: int) -> LevelResource:
	return get_face_level(slot_index)


func get_face_level(face_index: int) -> LevelResource:
	if face_index < 0 or face_index >= _levels.size():
		return null
	return _levels[face_index]


func get_loaded_level_count() -> int:
	var count := 0
	for level in _levels:
		if level != null:
			count += 1
	return count


## Drops every heavyweight preview graph while leaving the lightweight catalog
## paths intact. Returning to level selection reloads the previews on demand.
func release_loaded_level_resources() -> void:
	for preview in _previews:
		if preview != null and is_instance_valid(preview):
			preview.clear()
	for face_index in range(_levels.size()):
		_levels[face_index] = null
	for face_index in range(_face_areas.size()):
		_face_areas[face_index].collision_layer = 0
	for face_index in range(_face_materials.size()):
		_face_materials[face_index].albedo_texture = null
	return


func get_face_root(face_index: int) -> Node3D:
	if face_index < 0 or face_index >= _face_roots.size():
		return null
	return _face_roots[face_index]


func get_face_area(face_index: int) -> Area3D:
	if face_index < 0 or face_index >= _face_areas.size():
		return null
	return _face_areas[face_index]


func get_preview(face_index: int) -> LevelPortalPreviewScript:
	if face_index < 0 or face_index >= _previews.size():
		return null
	return _previews[face_index]


func get_cube_camera() -> Camera3D:
	return _cube_camera


func get_title_face() -> MeshInstance3D:
	return _title_face


func get_base_root() -> Node3D:
	return _base_root


func get_cube_yaw() -> float:
	return _yaw


func get_cube_pitch() -> float:
	return _pitch


func is_dragging_cube() -> bool:
	return _right_dragging


func is_previous_page_visible() -> bool:
	return false


func is_next_page_visible() -> bool:
	return false


## Compatibility no-op: one selection cube owns exactly four authored levels.
func change_page(_delta: int) -> void:
	return


func activate_face_for_test(face_index: int) -> void:
	_select_face(face_index)
	return


func apply_drag_for_test(relative_motion: Vector2) -> void:
	_apply_drag_motion(relative_motion)
	return


func _build_portal_previews() -> void:
	if not _previews.is_empty():
		return
	for face_index in range(SLOT_COUNT):
		var preview := LevelPortalPreviewScript.new()
		preview.name = "LevelPortalPreview%d" % (face_index + 1)
		add_child(preview)
		_previews.append(preview)
	return


func _build_cube_world() -> void:
	_cube_world_root = Node3D.new()
	_cube_world_root.name = "LevelSelectCubeWorld"
	_cube_viewport.add_child(_cube_world_root)
	_build_cube_environment()

	_cube_camera = Camera3D.new()
	_cube_camera.name = "FixedCubeCamera"
	_cube_camera.current = true
	_cube_camera.fov = 38.0
	_cube_camera.near = 0.1
	_cube_camera.far = 60.0
	_cube_camera.position = Vector3(0.0, 2.55, 9.2)
	_cube_world_root.add_child(_cube_camera)
	_cube_camera.look_at(Vector3(0.0, -0.05, 0.0), Vector3.UP)

	_yaw_pivot = Node3D.new()
	_yaw_pivot.name = "YawPivot"
	_cube_world_root.add_child(_yaw_pivot)
	_pitch_pivot = Node3D.new()
	_pitch_pivot.name = "PitchPivot"
	_yaw_pivot.add_child(_pitch_pivot)
	_cube_root = Node3D.new()
	_cube_root.name = "CubeRoot"
	_pitch_pivot.add_child(_cube_root)

	_build_faces()
	_build_frame()
	_build_title_face()
	_build_base()
	return


func _build_cube_environment() -> void:
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.018, 0.024, 0.032, 1.0)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.48, 0.56, 0.66, 1.0)
	environment_resource.ambient_light_energy = 0.82
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment_resource
	_cube_world_root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
	key_light.light_color = Color(0.88, 0.94, 1.0, 1.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	_cube_world_root.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "WarmFill"
	fill_light.position = Vector3(-4.0, 3.5, 5.0)
	fill_light.light_color = Color(1.0, 0.62, 0.35, 1.0)
	fill_light.light_energy = 2.1
	fill_light.omni_range = 12.0
	_cube_world_root.add_child(fill_light)
	return


func _build_faces() -> void:
	for face_index in range(SLOT_COUNT):
		var face_root := Node3D.new()
		face_root.name = "LevelFace%d" % (face_index + 1)
		_apply_face_transform(face_root, face_index)
		_cube_root.add_child(face_root)
		face_root.set_meta("level_face_index", face_index)

		var quad := QuadMesh.new()
		quad.size = Vector2(CUBE_SIZE, CUBE_SIZE)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "PortalSurface"
		mesh_instance.mesh = quad
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face_root.add_child(mesh_instance)

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		material.albedo_texture = _previews[face_index].get_texture()
		material.emission_enabled = true
		material.emission = Color.BLACK
		material.emission_energy_multiplier = 0.0
		mesh_instance.material_override = material

		var area := Area3D.new()
		area.name = "SelectionArea"
		area.collision_layer = FACE_COLLISION_MASK
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("level_face_index", face_index)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(CUBE_SIZE - 0.16, CUBE_SIZE - 0.16, 0.08)
		collision.shape = shape
		collision.position.z = 0.025
		area.add_child(collision)
		face_root.add_child(area)

		_face_roots.append(face_root)
		_face_meshes.append(mesh_instance)
		_face_materials.append(material)
		_face_areas.append(area)
	return


func _apply_face_transform(face_root: Node3D, face_index: int) -> void:
	match face_index:
		0:
			face_root.position = Vector3(0.0, 0.0, CUBE_HALF_SIZE)
		1:
			face_root.position = Vector3(CUBE_HALF_SIZE, 0.0, 0.0)
			face_root.rotation.y = PI * 0.5
		2:
			face_root.position = Vector3(0.0, 0.0, -CUBE_HALF_SIZE)
			face_root.rotation.y = PI
		3:
			face_root.position = Vector3(-CUBE_HALF_SIZE, 0.0, 0.0)
			face_root.rotation.y = -PI * 0.5
	return


func _build_frame() -> void:
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.075, 0.095, 0.12, 1.0)
	frame_material.metallic = 0.72
	frame_material.roughness = 0.24
	var beam := 0.115
	var length := CUBE_SIZE + beam
	for x in [-CUBE_HALF_SIZE, CUBE_HALF_SIZE]:
		for z in [-CUBE_HALF_SIZE, CUBE_HALF_SIZE]:
			_add_box(_cube_root, Vector3(beam, length, beam), Vector3(x, 0.0, z), frame_material)
	for y in [-CUBE_HALF_SIZE, CUBE_HALF_SIZE]:
		for z in [-CUBE_HALF_SIZE, CUBE_HALF_SIZE]:
			_add_box(_cube_root, Vector3(length, beam, beam), Vector3(0.0, y, z), frame_material)
		for x in [-CUBE_HALF_SIZE, CUBE_HALF_SIZE]:
			_add_box(_cube_root, Vector3(beam, beam, length), Vector3(x, y, 0.0), frame_material)
	return


func _build_title_face() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(CUBE_SIZE, CUBE_SIZE)
	_title_face = MeshInstance3D.new()
	_title_face.name = "TitleFace"
	_title_face.mesh = quad
	_title_face.position = Vector3(0.0, CUBE_HALF_SIZE, 0.0)
	_title_face.rotation.x = -PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.075, 0.105, 1.0)
	material.metallic = 0.42
	material.roughness = 0.32
	_title_face.material_override = material
	_cube_root.add_child(_title_face)

	var title := Label3D.new()
	title.name = "GameTitle"
	title.text = "MIRROR\nDEFENDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.font_size = 72
	title.pixel_size = 0.009
	title.outline_size = 10
	title.modulate = Color(0.74, 0.92, 1.0, 1.0)
	title.outline_modulate = Color(0.015, 0.03, 0.045, 1.0)
	title.position = Vector3(0.0, CUBE_HALF_SIZE + 0.018, 0.0)
	title.rotation.x = -PI * 0.5
	_cube_root.add_child(title)
	return


func _build_base() -> void:
	_base_root = Node3D.new()
	_base_root.name = "DisplayBase"
	_cube_root.add_child(_base_root)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.055, 0.07, 0.085, 1.0)
	material.metallic = 0.55
	material.roughness = 0.28
	_add_box(
		_base_root,
		Vector3(CUBE_SIZE + 0.44, 0.28, CUBE_SIZE + 0.44),
		Vector3(0.0, -CUBE_HALF_SIZE - 0.15, 0.0),
		material
	)
	_add_box(
		_base_root,
		Vector3(CUBE_SIZE + 0.76, 0.22, CUBE_SIZE + 0.76),
		Vector3(0.0, -CUBE_HALF_SIZE - 0.40, 0.0),
		material
	)
	return


func _add_box(parent: Node3D, box_size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _refresh_levels() -> void:
	if _previews.size() != SLOT_COUNT or _face_materials.size() != SLOT_COUNT:
		return
	var page: LevelSelectPageDefinitionScript = null
	if _catalog != null and _catalog.get_page_count() > 0:
		page = _catalog.get_page(0)
	for face_index in range(SLOT_COUNT):
		var level: LevelResource = page.get_level(face_index) if page != null else null
		_levels[face_index] = level
		_previews[face_index].set_level(level)
		var available := level != null and level.validate_runtime().is_empty()
		_face_areas[face_index].collision_layer = FACE_COLLISION_MASK if available else 0
		_face_materials[face_index].albedo_texture = _previews[face_index].get_texture() if available else null
		_face_materials[face_index].albedo_color = (
			Color.WHITE if available else Color(0.035, 0.045, 0.055, 1.0)
		)
	_update_portal_cameras(false)
	return


func _on_cube_gui_input(event: InputEvent) -> void:
	var button_event := event as InputEventMouseButton
	if button_event != null:
		if button_event.button_index == MOUSE_BUTTON_RIGHT:
			_right_dragging = button_event.pressed and not _selection_locked
			if not button_event.pressed:
				_set_hovered_face(-1)
			_cube_container.accept_event()
			return
		if (
			button_event.button_index == MOUSE_BUTTON_LEFT
			and button_event.pressed
			and not _right_dragging
			and not _selection_locked
		):
			_try_select_face_at(button_event.position)
			_cube_container.accept_event()
			return

	var motion_event := event as InputEventMouseMotion
	if motion_event == null:
		return
	if _right_dragging:
		_apply_drag_motion(motion_event.relative)
		_cube_container.accept_event()
		return
	_update_hover_at(motion_event.position)
	return


func _apply_drag_motion(relative_motion: Vector2) -> void:
	if _selection_locked:
		return
	var yaw_delta := -relative_motion.x * drag_sensitivity
	var pitch_delta := -relative_motion.y * drag_sensitivity
	_yaw += yaw_delta
	_pitch = clampf(
		_pitch + pitch_delta,
		deg_to_rad(minimum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)
	_angular_velocity = Vector2(yaw_delta, pitch_delta) * 60.0
	_apply_cube_rotation()
	_update_portal_cameras(true)
	return


func _apply_cube_rotation() -> void:
	if _yaw_pivot == null or _pitch_pivot == null:
		return
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch
	return


func _update_portal_cameras(moving: bool) -> void:
	if _cube_camera == null:
		return
	for face_index in range(mini(_face_roots.size(), _previews.size())):
		_previews[face_index].update_portal_camera(
			_face_roots[face_index].global_transform,
			_cube_camera.global_position,
			moving
		)
	return


func _viewport_position_from_control(control_position: Vector2) -> Vector2:
	if _cube_container.size.x <= 0.0 or _cube_container.size.y <= 0.0:
		return control_position
	return control_position / _cube_container.size * Vector2(_cube_viewport.size)


func _raycast_face(control_position: Vector2) -> int:
	if _cube_camera == null or _cube_viewport.world_3d == null:
		return -1
	var viewport_position := _viewport_position_from_control(control_position)
	var origin := _cube_camera.project_ray_origin(viewport_position)
	var direction := _cube_camera.project_ray_normal(viewport_position)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * 100.0,
		FACE_COLLISION_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := _cube_viewport.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_meta("level_face_index"):
		return -1
	return int(collider.get_meta("level_face_index"))


func _try_select_face_at(control_position: Vector2) -> void:
	_select_face(_raycast_face(control_position))
	return


func _select_face(face_index: int) -> void:
	if _selection_locked:
		return
	var level := get_face_level(face_index)
	if level == null or not level.validate_runtime().is_empty():
		return
	_selection_locked = true
	_right_dragging = false
	_angular_velocity = Vector2.ZERO
	_set_hovered_face(face_index)
	release_loaded_level_resources()
	level_selected.emit(level)
	return


func _update_hover_at(control_position: Vector2) -> void:
	_set_hovered_face(_raycast_face(control_position))
	return


func _set_hovered_face(face_index: int) -> void:
	if face_index == _hovered_face_index:
		return
	_hovered_face_index = face_index
	for index in range(_face_materials.size()):
		var highlighted := index == _hovered_face_index and get_face_level(index) != null
		_face_materials[index].emission = Color(0.18, 0.58, 0.82, 1.0) if highlighted else Color.BLACK
		_face_materials[index].emission_energy_multiplier = 0.24 if highlighted else 0.0
	if _interaction_hint != null:
		_interaction_hint.text = (
			"左键进入关卡 · 右键拖动旋转"
			if _hovered_face_index >= 0
			else "右键拖动旋转立方体 · 左键选择关卡"
		)
	return
