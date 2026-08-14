## Runtime edge entity. It owns presentation, active-side state, and one
## throttled planar reflection view; MirrorManager owns projection logic.
class_name CopyMirror
extends Node3D

const SelectionHighlightScript := preload("res://scripts/presentation/SelectionHighlight.gd")

const MirrorReflectionViewScript := preload("res://scripts/mirror/MirrorReflectionView.gd")
const MirrorOvalMeshFactory := preload("res://scripts/mirror/MirrorOvalMeshFactory.gd")
const PICK_MARGIN: float = 0.01

signal side_changed(mirror: CopyMirror)

var definition: MirrorDefinition
var from_cell: Vector3i
var to_cell: Vector3i
var edge_index: int = -1
var edge_id: String = ""
var active_from_side: bool = true
var placement_order: int = 0
var level: int = 1
var preview_mode: bool = false
var _invested_resource: float = 0.0

var _grid: GridManager
var _tile_manager: TileManager
var _source_camera: Camera3D
var _body: MeshInstance3D
var _frame_material: StandardMaterial3D
var _reflection_view: Node3D
var _selected: bool = false
var _preview_valid: bool = true

func configure(
	mirror_definition: MirrorDefinition,
	p_from_cell: Vector3i,
	p_to_cell: Vector3i,
	p_edge_index: int,
	p_edge_id: String,
	grid_manager: GridManager,
	tile_manager: TileManager,
	p_active_from_side: bool,
	p_preview_mode: bool = false
) -> void:
	definition = mirror_definition
	from_cell = p_from_cell
	to_cell = p_to_cell
	edge_index = p_edge_index
	edge_id = p_edge_id
	_grid = grid_manager
	_tile_manager = tile_manager
	active_from_side = p_active_from_side
	preview_mode = p_preview_mode
	level = 1
	_invested_resource = 0.0
	_update_transform()
	_build_visual()

func set_reflection_camera(camera: Camera3D) -> void:
	_source_camera = camera
	if _reflection_view != null:
		_reflection_view.set_source_camera(camera)

func request_reflection_refresh() -> bool:
	return _reflection_view != null and _reflection_view.request_refresh()

func refresh_visual() -> void:
	_build_visual()


func set_preview_valid(valid: bool) -> void:
	if not preview_mode or _preview_valid == valid:
		return
	_preview_valid = valid
	_update_frame_material()


func is_preview_valid() -> bool:
	return _preview_valid


## Moves a placement ghost while retaining its mesh, material and reflection
## SubViewport. Runtime mirrors are immutable after placement.
func relocate_preview(
	p_from_cell: Vector3i,
	p_to_cell: Vector3i,
	p_edge_index: int,
	p_edge_id: String
) -> bool:
	if not preview_mode:
		return false
	from_cell = p_from_cell
	to_cell = p_to_cell
	edge_index = p_edge_index
	edge_id = p_edge_id
	_update_transform()
	if _body != null and is_instance_valid(_body):
		_body.rotation.y = -atan2(get_edge_direction().z, get_edge_direction().x)
	_update_active_side_visual()
	return true


## Atomically relocates the live physical mirror while retaining this instance,
## its level, investment ledger, reflection viewport and selection state.
func relocate_runtime(
	p_from_cell: Vector3i,
	p_to_cell: Vector3i,
	p_edge_index: int,
	p_edge_id: String,
	p_active_from_side: bool
) -> bool:
	if preview_mode or p_edge_index < 0 or p_edge_id.is_empty():
		return false
	from_cell = p_from_cell
	to_cell = p_to_cell
	edge_index = p_edge_index
	edge_id = p_edge_id
	active_from_side = p_active_from_side
	_update_transform()
	if _body != null and is_instance_valid(_body):
		_body.rotation.y = -atan2(get_edge_direction().z, get_edge_direction().x)
	_update_active_side_visual()
	return true


func flip_side() -> void:
	active_from_side = not active_from_side
	_update_active_side_visual()
	side_changed.emit(self)

func get_active_cell() -> Vector3i:
	return from_cell if active_from_side else to_cell


func is_copy_mirror() -> bool:
	return true


func is_projectile_reflector() -> bool:
	return false


func can_upgrade() -> bool:
	return definition != null and level < definition.get_max_level()


func get_upgrade_cost() -> float:
	return definition.get_upgrade_cost(level) if definition != null and can_upgrade() else 0.0


func set_level(value: int) -> bool:
	if definition == null or value < 1 or value > definition.get_max_level():
		return false
	level = value
	return true


func get_damage_multiplier() -> float:
	return definition.get_damage_multiplier(level) if definition != null else 1.0


func get_penetration_bonus() -> int:
	return definition.get_penetration_bonus(level) if definition != null else 0

func get_axis_endpoints() -> Array[Vector3]:
	return _grid.get_edge_endpoints(from_cell, edge_index) if _grid != null else []

func get_edge_direction() -> Vector3:
	var endpoints := get_axis_endpoints()
	return endpoints[1] - endpoints[0] if endpoints.size() == 2 else Vector3.ZERO

func get_active_normal() -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	var normal := _grid.cell_to_world(get_active_cell()) - global_position
	normal.y = 0.0
	return normal.normalized()

func get_mirror_width() -> float:
	return maxf(0.01, get_edge_direction().length())

func get_mirror_height() -> float:
	return _grid.cell_size * definition.mirror_height_ratio if _grid != null and definition != null else 1.20

func get_mirror_thickness() -> float:
	return _grid.cell_size * definition.mirror_thickness_ratio if _grid != null and definition != null else 0.08

func get_reflection_surface() -> MeshInstance3D:
	return _reflection_view.get_surface() if _reflection_view != null else null

func get_reflection_camera() -> Camera3D:
	return _reflection_view.get_reflection_camera() if _reflection_view != null else null

func get_reflection_viewport() -> SubViewport:
	return _reflection_view.get_reflection_viewport() if _reflection_view != null else null

func get_action_anchor() -> Vector3:
	return global_position + Vector3(0.0, get_mirror_height() + 0.2, 0.0)


## Tracks the mirror's refundable lifetime value. Runtime coin placements add
## actual spending; authored initial mirrors seed the equivalent configured
## construction/upgrade value; free cooldown placements remain at zero.
func _record_investment(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0:
		return false
	var updated_total := _invested_resource + amount
	if not is_finite(updated_total):
		return false
	_invested_resource = updated_total
	return true


func _rollback_investment(amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or amount > _invested_resource:
		return false
	_invested_resource -= amount
	return true


func get_refund_amount() -> float:
	return maxf(0.0, _invested_resource) if is_finite(_invested_resource) else 0.0


## Returns the ray distance to the visible mirror body, or INF on a miss.
## Both body shapes are geometric rather than front-face culled, so the
## reflective face and the back face remain directly selectable.
func get_pick_distance(ray_origin: Vector3, ray_direction: Vector3) -> float:
	if preview_mode or _body == null or not is_instance_valid(_body):
		return INF
	if ray_direction.length_squared() <= 0.000001:
		return INF
	var inverse := _body.global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := inverse.basis * ray_direction.normalized()
	var half_extents := Vector3(
		get_mirror_width(),
		get_mirror_height(),
		get_mirror_thickness()
	) * 0.5 + Vector3.ONE * PICK_MARGIN
	if is_copy_mirror():
		return _get_oval_pick_distance(local_origin, local_direction, half_extents)
	return _get_box_pick_distance(local_origin, local_direction, half_extents)


func _get_box_pick_distance(
	local_origin: Vector3,
	local_direction: Vector3,
	half_extents: Vector3
) -> float:
	var near_distance := 0.0
	var far_distance := INF
	for axis in range(3):
		var origin_axis: float = local_origin[axis]
		var direction_axis: float = local_direction[axis]
		var extent: float = half_extents[axis]
		if absf(direction_axis) <= 0.000001:
			if origin_axis < -extent or origin_axis > extent:
				return INF
			continue
		var first := (-extent - origin_axis) / direction_axis
		var second := (extent - origin_axis) / direction_axis
		if first > second:
			var swap := first
			first = second
			second = swap
		near_distance = maxf(near_distance, first)
		far_distance = minf(far_distance, second)
		if near_distance > far_distance:
			return INF
	return near_distance if far_distance >= 0.0 else INF


func _get_oval_pick_distance(
	local_origin: Vector3,
	local_direction: Vector3,
	half_extents: Vector3
) -> float:
	var radius_x_squared := half_extents.x * half_extents.x
	var radius_y_squared := half_extents.y * half_extents.y
	var quadratic_a := (
		local_direction.x * local_direction.x / radius_x_squared
		+ local_direction.y * local_direction.y / radius_y_squared
	)
	var quadratic_b := 2.0 * (
		local_origin.x * local_direction.x / radius_x_squared
		+ local_origin.y * local_direction.y / radius_y_squared
	)
	var quadratic_c := (
		local_origin.x * local_origin.x / radius_x_squared
		+ local_origin.y * local_origin.y / radius_y_squared
		- 1.0
	)
	var oval_near := -INF
	var oval_far := INF
	if quadratic_a <= 0.000001:
		if quadratic_c > 0.0:
			return INF
	else:
		var discriminant := quadratic_b * quadratic_b - 4.0 * quadratic_a * quadratic_c
		if discriminant < 0.0:
			return INF
		var root := sqrt(discriminant)
		oval_near = (-quadratic_b - root) / (2.0 * quadratic_a)
		oval_far = (-quadratic_b + root) / (2.0 * quadratic_a)
	var depth_near := -INF
	var depth_far := INF
	if absf(local_direction.z) <= 0.000001:
		if absf(local_origin.z) > half_extents.z:
			return INF
	else:
		depth_near = (-half_extents.z - local_origin.z) / local_direction.z
		depth_far = (half_extents.z - local_origin.z) / local_direction.z
		if depth_near > depth_far:
			var swap := depth_near
			depth_near = depth_far
			depth_far = swap
	var near_distance := maxf(0.0, maxf(oval_near, depth_near))
	var far_distance := minf(oval_far, depth_far)
	return near_distance if far_distance >= near_distance else INF

func set_selected(selected: bool) -> void:
	_selected = selected
	if _frame_material != null:
		_frame_material.emission_energy_multiplier = (
			3.6 if selected or (preview_mode and not _preview_valid) else 1.5
		)
	if _body != null and is_instance_valid(_body):
		SelectionHighlightScript.apply_recursive(_body, _selected and not preview_mode)
	# The copy mirror's large oval reflection surface visually covers almost the
	# entire body from its active side. Highlight it as well, otherwise the red
	# body overlay remains hidden behind a bright reflection.
	var reflection_surface := get_reflection_surface()
	if reflection_surface != null and is_instance_valid(reflection_surface):
		SelectionHighlightScript.apply_recursive(
			reflection_surface,
			_selected and not preview_mode
		)

func _update_transform() -> void:
	if _grid == null or _tile_manager == null:
		return
	var endpoints := _grid.get_edge_endpoints(from_cell, edge_index)
	var midpoint := _grid.cell_to_world(from_cell)
	if endpoints.size() == 2:
		midpoint = (endpoints[0] + endpoints[1]) * 0.5
	var height := maxf(
		_grid.sample_cell_surface_height(from_cell, midpoint),
		_grid.sample_cell_surface_height(to_cell, midpoint)
	)
	position = midpoint + Vector3(0.0, height, 0.0)


## Re-samples both edge cells after a runtime terrain edit.
func refresh_world_transform() -> void:
	_update_transform()

func _build_visual() -> void:
	for child in get_children():
		child.queue_free()
	_body = null
	_reflection_view = null
	if _grid == null or definition == null or get_axis_endpoints().size() != 2:
		return
	var body := MeshInstance3D.new()
	body.name = "MirrorBody"
	var body_size := Vector3(get_mirror_width(), get_mirror_height(), get_mirror_thickness())
	var body_mesh: Mesh
	if is_copy_mirror():
		body_mesh = MirrorOvalMeshFactory.create_prism(body_size)
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = body_size
		body_mesh = box_mesh
	body.mesh = body_mesh
	body.set_layer_mask_value(1, false)
	body.set_layer_mask_value(MirrorReflectionViewScript.REFLECTION_VISIBILITY_LAYER, true)
	body.position.y = get_mirror_height() * 0.5
	body.rotation.y = -atan2(get_edge_direction().z, get_edge_direction().x)
	_frame_material = StandardMaterial3D.new()
	_frame_material.metallic = 0.82
	_frame_material.roughness = 0.22
	_frame_material.emission_enabled = true
	_update_frame_material()
	body.material_override = _frame_material
	add_child(body)
	_body = body
	_reflection_view = MirrorReflectionViewScript.new()
	add_child(_reflection_view)
	_reflection_view.configure(self, definition, _source_camera, preview_mode)
	_update_active_side_visual()
	set_selected(_selected)


func _update_frame_material() -> void:
	if _frame_material == null or definition == null:
		return
	var invalid_color := definition.invalid_preview_color
	_frame_material.albedo_color = invalid_color if preview_mode and not _preview_valid else definition.mirror_back_face_color
	_frame_material.emission = invalid_color if preview_mode and not _preview_valid else definition.mirror_back_face_color.darkened(0.38)
	_frame_material.emission_energy_multiplier = 3.2 if preview_mode and not _preview_valid else 1.5
	if preview_mode:
		var preview_color := _frame_material.albedo_color
		preview_color.a = 0.72
		_frame_material.albedo_color = preview_color
		_frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	set_selected(_selected)

func _update_active_side_visual() -> void:
	if _reflection_view != null:
		_reflection_view.update_active_side()
