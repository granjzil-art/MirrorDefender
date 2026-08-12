@tool
## Isolated normalized 3D level preview rendered through a square portal.
##
## The caller supplies the world-space transform of one cube face and the
## observer position. The observer is mapped into this preview world's portal
## coordinates, then an off-axis frustum is aligned to the portal rectangle.
class_name LevelPortalPreview
extends SubViewport

const GridManagerScript := preload("res://scripts/grid/GridManager.gd")
const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")
const TerrainRendererScript := preload("res://scripts/terrain/TerrainRenderer.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffRendererScript := preload("res://scripts/stuff/StuffRenderer.gd")
const TileManagerScript := preload("res://scripts/tile/TileManager.gd")
const LevelLoaderScript := preload("res://scripts/level/LevelLoader.gd")
const StuffCatalogResource := preload("res://resources/stuffs/StuffCatalog.tres")

const PORTAL_SIZE := Vector2(4.0, 4.0)
const PORTAL_HALF_SIZE: float = 2.0
const CONTENT_PADDING: float = 0.34
const CONTENT_FRONT_Z: float = 1.58
const CONTENT_FLOOR_Y: float = -1.58
const MIN_EXTENT: float = 0.01
const MIN_CAMERA_DISTANCE: float = 0.08
const PREVIEW_RESOLUTION: int = 512

var _level: LevelResource
var _world_root: Node3D
var _content_root: Node3D
var _marker_root: Node3D
var _portal_anchor: Node3D
var _camera: Camera3D
var _environment: WorldEnvironment
var _sun: DirectionalLight3D
var _grid: GridManager
var _terrain_manager: TerrainManager
var _terrain_renderer: TerrainRenderer
var _stuff_manager: StuffManager
var _stuff_renderer: StuffRenderer
var _tile_manager: TileManager
var _level_loader: LevelLoader
var _camera_attributes: CameraAttributesPractical
var _focus_position := Vector3.ZERO
var _content_scale: float = 1.0
var _loaded: bool = false
var _last_facing: float = -1.0
var _last_observer_local := Vector3.ZERO
var _last_camera_transform := Transform3D.IDENTITY
var _was_visible_to_observer: bool = false


func _init() -> void:
	size = Vector2i(PREVIEW_RESOLUTION, PREVIEW_RESOLUTION)
	disable_3d = false
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	msaa_3d = Viewport.MSAA_2X
	world_3d = World3D.new()


func _ready() -> void:
	_build_preview_world()
	if _level != null:
		_load_level_into_preview()
	return


func set_level(value: LevelResource) -> void:
	_level = value
	_loaded = false
	if not is_node_ready():
		return
	if _level == null:
		_clear_level_content()
		return
	_load_level_into_preview()
	return


func clear() -> void:
	_level = null
	_loaded = false
	if is_node_ready():
		_clear_level_content()
	return


func get_level() -> LevelResource:
	return _level


func is_loaded() -> bool:
	return _loaded


func get_portal_anchor() -> Node3D:
	return _portal_anchor


func get_preview_camera() -> Camera3D:
	return _camera


func get_content_scale() -> float:
	return _content_scale


func get_last_facing() -> float:
	return _last_facing


func get_last_observer_local() -> Vector3:
	return _last_observer_local


## Maps the observer through one cube face into this isolated preview world.
func update_portal_camera(
	source_portal_transform: Transform3D,
	observer_position: Vector3,
	moving: bool
) -> bool:
	if not _loaded or _portal_anchor == null or _camera == null:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false
	var source_basis := source_portal_transform.basis.orthonormalized()
	var source_normal := source_basis.z.normalized()
	var to_observer := observer_position - source_portal_transform.origin
	if to_observer.length_squared() <= 0.000001:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false
	_last_facing = source_normal.dot(to_observer.normalized())
	_last_observer_local = source_portal_transform.affine_inverse() * observer_position
	var visible_to_observer := _last_facing > 0.01 and _last_observer_local.z > MIN_CAMERA_DISTANCE
	if not visible_to_observer:
		_was_visible_to_observer = false
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false

	var destination := _portal_anchor.global_transform
	var mapped_position := destination * _last_observer_local
	var destination_basis := destination.basis.orthonormalized()
	var next_transform := Transform3D(destination_basis, mapped_position)
	var transform_changed := not next_transform.is_equal_approx(_last_camera_transform)
	_camera.global_transform = next_transform
	_last_camera_transform = next_transform
	_update_off_axis_frustum()
	_update_depth_of_field()

	if moving:
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif (
		transform_changed
		or not _was_visible_to_observer
		or render_target_update_mode == SubViewport.UPDATE_ALWAYS
	):
		render_target_update_mode = SubViewport.UPDATE_ONCE
	_was_visible_to_observer = true
	return true


func request_refresh() -> void:
	if _loaded:
		render_target_update_mode = SubViewport.UPDATE_ONCE
	return


func _build_preview_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "PreviewWorld"
	add_child(_world_root)

	_build_environment()
	_content_root = Node3D.new()
	_content_root.name = "NormalizedLevelContent"
	_world_root.add_child(_content_root)

	_grid = GridManagerScript.new()
	_grid.name = "GridManager"
	_terrain_manager = TerrainManagerScript.new()
	_terrain_manager.name = "TerrainManager"
	_terrain_renderer = TerrainRendererScript.new()
	_terrain_renderer.name = "TerrainRenderer"
	_stuff_manager = StuffManagerScript.new()
	_stuff_manager.name = "StuffManager"
	_stuff_manager.stuff_catalog = StuffCatalogResource
	_stuff_renderer = StuffRendererScript.new()
	_stuff_renderer.name = "StuffRenderer"
	_tile_manager = TileManagerScript.new()
	_tile_manager.name = "TileManager"
	_tile_manager.legacy_content_runtime_enabled = false
	_level_loader = LevelLoaderScript.new()
	_level_loader.name = "LevelLoader"
	_marker_root = Node3D.new()
	_marker_root.name = "PreviewMarkers"

	for node in [
		_grid,
		_terrain_manager,
		_terrain_renderer,
		_stuff_manager,
		_stuff_renderer,
		_tile_manager,
		_level_loader,
		_marker_root,
	]:
		_content_root.add_child(node)

	_terrain_manager.set_grid(_grid)
	_terrain_renderer.set_grid(_grid)
	_terrain_renderer.set_terrain_manager(_terrain_manager)
	_stuff_manager.configure(_grid, _terrain_manager)
	_stuff_renderer.configure(_grid, _stuff_manager)
	_tile_manager.set_grid(_grid)
	_tile_manager.set_stuff_runtime_provider(_stuff_manager)
	_tile_manager.set_surface_height_resolver(Callable(_terrain_manager, "get_world_height"))
	_tile_manager.set_base_placement_resolvers(
		Callable(_terrain_manager, "allows_tile_building"),
		Callable(_terrain_manager, "allows_edge_building")
	)
	_grid.set_cell_height_resolver(Callable(_terrain_manager, "get_world_height"))
	_grid.set_cell_surface_height_resolver(Callable(_terrain_manager, "sample_surface_height"))
	_grid.set_surface_raycast_resolver(Callable(_terrain_manager, "raycast_surface"))
	_level_loader.configure(_grid, _tile_manager, _terrain_manager, _stuff_manager)

	_portal_anchor = Node3D.new()
	_portal_anchor.name = "PreviewPortal"
	_portal_anchor.position = Vector3(0.0, 0.0, PORTAL_HALF_SIZE)
	_world_root.add_child(_portal_anchor)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.current = true
	_camera.near = 0.05
	_camera.far = 80.0
	_world_root.add_child(_camera)
	_camera_attributes = CameraAttributesPractical.new()
	_camera.attributes = _camera_attributes
	return


func _build_environment() -> void:
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.055, 0.072, 0.09, 1.0)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.76, 0.82, 0.90, 1.0)
	environment_resource.ambient_light_energy = 0.88
	_environment = WorldEnvironment.new()
	_environment.name = "WorldEnvironment"
	_environment.environment = environment_resource
	_world_root.add_child(_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "PreviewSun"
	_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	_sun.light_color = Color(1.0, 0.94, 0.84, 1.0)
	_sun.light_energy = 1.18
	_sun.shadow_enabled = true
	_world_root.add_child(_sun)
	return


func _load_level_into_preview() -> void:
	_clear_marker_nodes()
	_content_root.position = Vector3.ZERO
	_content_root.scale = Vector3.ONE
	_loaded = _level_loader.load_level(_level, _level.resource_path)
	if not _loaded:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_add_point_markers()
	_add_initial_building_visuals()
	var bounds := _calculate_level_bounds()
	_normalize_content(bounds)
	request_refresh()
	return


func _clear_level_content() -> void:
	_clear_marker_nodes()
	if _level_loader != null:
		_level_loader.clear_level()
	else:
		if _terrain_manager != null:
			_terrain_manager.clear_level()
		if _stuff_manager != null:
			_stuff_manager.clear_level()
		if _tile_manager != null:
			_tile_manager.clear_level()
	_content_root.position = Vector3.ZERO
	_content_root.scale = Vector3.ONE
	_content_scale = 1.0
	_last_facing = -1.0
	_was_visible_to_observer = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	return


func _clear_marker_nodes() -> void:
	if _marker_root == null:
		return
	for child in _marker_root.get_children():
		child.free()
	return


func _add_point_markers() -> void:
	for base_point in _level.get_effective_base_points():
		if base_point == null:
			continue
		var root := Node3D.new()
		root.name = "Base_%s" % String(base_point.base_id)
		root.position = base_point.get_footprint_center_world(_grid)
		root.position.y = _terrain_manager.get_world_height(base_point.cell)
		_marker_root.add_child(root)
		var asset := _level.get_base_point_model_asset(base_point)
		var visual: Node3D = asset.instantiate_grounded_model(&"BaseModel") if asset != null else null
		if visual != null:
			root.add_child(visual)
		else:
			_add_fallback_marker(root, Color(0.24, 0.68, 1.0, 1.0), 0.44, 0.72)

	for spawn_point in _level.spawn_points:
		if spawn_point == null:
			continue
		var root := Node3D.new()
		root.name = "Spawn_%s" % String(spawn_point.spawn_id)
		root.position = _grid.cell_to_world(spawn_point.cell)
		root.position.y = _terrain_manager.get_world_height(spawn_point.cell)
		_marker_root.add_child(root)
		var asset := _level.get_spawn_point_model_asset(spawn_point)
		var visual: Node3D = asset.instantiate_grounded_model(&"SpawnModel") if asset != null else null
		if visual != null:
			root.add_child(visual)
		else:
			_add_fallback_marker(root, Color(0.24, 0.95, 0.56, 1.0), 0.28, 0.56)
	return


func _add_initial_building_visuals() -> void:
	for placement in _level.initial_building_placements:
		if placement == null or placement.definition == null:
			continue
		var stats := placement.definition.get_level_stats(placement.level)
		if stats == null:
			continue
		var root := Node3D.new()
		root.name = "InitialBuildingPreview"
		root.position = _grid.cell_to_world(placement.cell)
		root.position.y = _terrain_manager.get_world_height(placement.cell)
		var facing_angle := TAU * float(placement.facing_index) / 36.0
		var facing := Vector3(cos(facing_angle), 0.0, sin(facing_angle))
		root.rotation.y = atan2(-facing.x, -facing.z)
		_marker_root.add_child(root)
		var asset := stats.get_model_asset()
		var visual: Node3D = asset.instantiate_grounded_model(&"BuildingModel") if asset != null else null
		if visual != null:
			root.add_child(visual)
		else:
			_add_fallback_marker(root, stats.tower_color, 0.32, 0.86)
	return


func _add_fallback_marker(
	parent: Node3D,
	color: Color,
	radius: float,
	height: float
) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.72
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.position.y = height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	instance.material_override = material
	parent.add_child(instance)
	return


func _calculate_level_bounds() -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for cell in _grid.enumerate_cells():
		var center := _grid.cell_to_world(cell)
		var top_y := _terrain_manager.sample_surface_height(cell, center)
		minimum.y = minf(minimum.y, -_terrain_manager.get_layer_height())
		maximum.y = maxf(maximum.y, top_y)
		for corner in _grid.get_corners(cell):
			minimum.x = minf(minimum.x, corner.x)
			minimum.z = minf(minimum.z, corner.z)
			maximum.x = maxf(maximum.x, corner.x)
			maximum.z = maxf(maximum.z, corner.z)
	if not minimum.is_finite() or not maximum.is_finite():
		return AABB(Vector3(-1.0, -0.25, -1.0), Vector3(2.0, 1.0, 2.0))
	# Reserve vertical room for trees, bases, and authored initial buildings.
	maximum.y += _grid.cell_size * 2.4
	return AABB(minimum, maximum - minimum)


func _normalize_content(bounds: AABB) -> void:
	var usable := Vector3(
		PORTAL_SIZE.x - CONTENT_PADDING * 2.0,
		PORTAL_SIZE.y - CONTENT_PADDING * 2.0,
		PORTAL_SIZE.x - CONTENT_PADDING * 2.0
	)
	_content_scale = minf(
		usable.x / maxf(MIN_EXTENT, bounds.size.x),
		minf(
			usable.y / maxf(MIN_EXTENT, bounds.size.y),
			usable.z / maxf(MIN_EXTENT, bounds.size.z)
		)
	)
	_content_root.scale = Vector3.ONE * _content_scale
	var center := bounds.get_center()
	_content_root.position = Vector3(
		-center.x * _content_scale,
		CONTENT_FLOOR_Y - bounds.position.y * _content_scale,
		CONTENT_FRONT_Z - bounds.end.z * _content_scale
	)
	var focus_source := Vector3(
		center.x,
		bounds.position.y + bounds.size.y * 0.38,
		lerpf(bounds.end.z, bounds.position.z, 0.56)
	)
	_focus_position = _content_root.transform * focus_source
	return


func _update_off_axis_frustum() -> void:
	var destination := _portal_anchor.global_transform
	var right := destination.basis.x.normalized()
	var up := destination.basis.y.normalized()
	var outward := destination.basis.z.normalized()
	var forward := -outward
	var to_center := destination.origin - _camera.global_position
	var distance := maxf(MIN_CAMERA_DISTANCE, to_center.dot(forward))
	var near_plane := maxf(0.02, distance * 0.985)
	var offset := Vector2(
		to_center.dot(right) * near_plane / distance,
		to_center.dot(up) * near_plane / distance
	)
	var frustum_height := PORTAL_SIZE.y * near_plane / distance
	_camera.set_frustum(
		maxf(0.01, frustum_height),
		offset,
		near_plane,
		maxf(near_plane + 10.0, 80.0)
	)
	return


func _update_depth_of_field() -> void:
	if _camera_attributes == null:
		return
	var forward := -_camera.global_basis.z.normalized()
	var focus_depth := maxf(
		_camera.near + 0.05,
		forward.dot(_focus_position - _camera.global_position)
	)
	var clear_margin := 0.56
	_camera_attributes.dof_blur_near_enabled = true
	_camera_attributes.dof_blur_far_enabled = true
	_camera_attributes.dof_blur_amount = 0.055
	_camera_attributes.dof_blur_near_distance = maxf(_camera.near + 0.025, focus_depth - clear_margin)
	_camera_attributes.dof_blur_far_distance = focus_depth + clear_margin * 1.25
	_camera_attributes.dof_blur_near_transition = 0.82
	_camera_attributes.dof_blur_far_transition = 1.0
	return
