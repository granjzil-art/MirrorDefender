## LevelReflectionSurface -- 关卡下方的共享世界实时平面倒影。
##
## 节点只创建 MeshInstance3D、SubViewport 与反射 Camera3D，不创建碰撞体，
## 也不向任何玩法管理器注册。反射相机从水平面下方观察共享 World3D，
## 离轴视锥与实体反射面严格对齐，因此主相机移动/旋转/俯仰时倒影实时变化。
class_name LevelReflectionSurface
extends Node3D

const LevelReflectionDefinitionScript := preload("res://scripts/fx/LevelReflectionDefinition.gd")
const LevelReflectionShader := preload("res://resources/fx/LevelReflection.gdshader")
const REFLECTION_VISIBILITY_LAYER := 20
const MIN_SURFACE_SIZE := 0.1
const MIN_CAMERA_DISTANCE := 0.05

var _grid: GridManager
var _tile_manager: TileManager
var _source_camera: Camera3D
var _definition: LevelReflectionDefinitionScript
var _surface: MeshInstance3D
var _fallback_material: StandardMaterial3D
var _viewport: SubViewport
var _reflection_camera: Camera3D
var _surface_size: Vector2 = Vector2.ONE
var _surface_y: float = 0.0
var _refresh_counter: int = 0

func configure(
	grid: GridManager,
	tile_manager: TileManager,
	source_camera: Camera3D,
	definition: LevelReflectionDefinitionScript
) -> void:
	_disconnect_dependencies()
	_grid = grid
	_tile_manager = tile_manager
	_source_camera = source_camera
	_definition = definition
	_connect_dependencies()
	_apply_feature_state()

func _exit_tree() -> void:
	_disconnect_dependencies()

func set_source_camera(camera: Camera3D) -> void:
	_source_camera = camera
	_ensure_render_target()
	refresh_now()

func refresh_now() -> bool:
	if not _can_refresh():
		return false
	_update_reflection_camera()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func get_surface() -> MeshInstance3D:
	return _surface

func get_reflection_viewport() -> SubViewport:
	return _viewport

func get_reflection_camera() -> Camera3D:
	return _reflection_camera

func get_surface_y() -> float:
	return _surface_y

func get_surface_size() -> Vector2:
	return _surface_size

func _process(_delta: float) -> void:
	if _definition == null or not _definition.feature_enabled:
		return
	_refresh_counter += 1
	if _refresh_counter < maxi(1, _definition.update_interval_frames):
		return
	_refresh_counter = 0
	refresh_now()

func _connect_dependencies() -> void:
	if _definition != null and not _definition.changed.is_connected(_on_definition_changed):
		_definition.changed.connect(_on_definition_changed)
	if _grid != null and not _grid.grid_changed.is_connected(_on_grid_changed):
		_grid.grid_changed.connect(_on_grid_changed)
	if _tile_manager == null:
		return
	if not _tile_manager.level_loaded.is_connected(_on_level_loaded):
		_tile_manager.level_loaded.connect(_on_level_loaded)
	if not _tile_manager.tile_changed.is_connected(_on_tile_changed):
		_tile_manager.tile_changed.connect(_on_tile_changed)

func _disconnect_dependencies() -> void:
	if _definition != null and _definition.changed.is_connected(_on_definition_changed):
		_definition.changed.disconnect(_on_definition_changed)
	if _grid != null and _grid.grid_changed.is_connected(_on_grid_changed):
		_grid.grid_changed.disconnect(_on_grid_changed)
	if _tile_manager == null:
		return
	if _tile_manager.level_loaded.is_connected(_on_level_loaded):
		_tile_manager.level_loaded.disconnect(_on_level_loaded)
	if _tile_manager.tile_changed.is_connected(_on_tile_changed):
		_tile_manager.tile_changed.disconnect(_on_tile_changed)

func _apply_feature_state() -> void:
	var enabled := _definition != null and _definition.feature_enabled
	set_process(enabled)
	if not enabled:
		if _surface != null:
			_surface.visible = false
		return
	_ensure_surface()
	_rebuild_surface_bounds()
	_ensure_render_target()
	refresh_now()

func _ensure_surface() -> void:
	if _surface != null:
		_surface.visible = true
		return
	_surface = MeshInstance3D.new()
	_surface.name = "LevelReflectionSurface"
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.set_layer_mask_value(1, false)
	_surface.set_layer_mask_value(REFLECTION_VISIBILITY_LAYER, true)
	_fallback_material = StandardMaterial3D.new()
	_fallback_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fallback_material.albedo_color = _definition.surface_tint
	_fallback_material.metallic = 0.9
	_fallback_material.roughness = 0.08
	_surface.material_override = _fallback_material
	add_child(_surface)

func _rebuild_surface_bounds() -> void:
	if _surface == null or _grid == null:
		return
	var cells := _grid.enumerate_cells()
	if cells.is_empty():
		_surface.visible = false
		return
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var minimum_height := 0.0
	for cell in cells:
		if _tile_manager != null:
			minimum_height = minf(minimum_height, _tile_manager.get_world_height(cell))
		for corner in _grid.get_corners(cell):
			minimum.x = minf(minimum.x, corner.x)
			minimum.y = minf(minimum.y, corner.z)
			maximum.x = maxf(maximum.x, corner.x)
			maximum.y = maxf(maximum.y, corner.z)
	var margin := _grid.cell_size * _definition.edge_margin_cells
	minimum -= Vector2.ONE * margin
	maximum += Vector2.ONE * margin
	_surface_size = Vector2(
		maxf(MIN_SURFACE_SIZE, maximum.x - minimum.x),
		maxf(MIN_SURFACE_SIZE, maximum.y - minimum.y)
	)
	_surface_y = minimum_height - _definition.vertical_offset
	var center_2d := (minimum + maximum) * 0.5
	_surface.position = Vector3(center_2d.x, _surface_y, center_2d.y)
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = _surface_size
	_surface.mesh = plane
	_surface.visible = true
	_resize_render_target()

func _ensure_render_target() -> void:
	if (
		_viewport != null
		or _source_camera == null
		or _definition == null
		or not _definition.feature_enabled
		or not is_inside_tree()
	):
		return
	_viewport = SubViewport.new()
	_viewport.name = "LevelReflectionViewport"
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	_reflection_camera = Camera3D.new()
	_reflection_camera.name = "LevelReflectionCamera"
	_reflection_camera.current = true
	_reflection_camera.cull_mask = _source_camera.cull_mask
	_reflection_camera.set_cull_mask_value(REFLECTION_VISIBILITY_LAYER, false)
	_viewport.add_child(_reflection_camera)
	_resize_render_target()
	_surface.material_override = _make_reflection_material(_viewport.get_texture())

func _resize_render_target() -> void:
	if _viewport == null or _definition == null:
		return
	var longest := maxi(128, _definition.reflection_resolution)
	var aspect := _surface_size.x / maxf(MIN_SURFACE_SIZE, _surface_size.y)
	if aspect >= 1.0:
		_viewport.size = Vector2i(longest, maxi(64, roundi(float(longest) / aspect)))
	else:
		_viewport.size = Vector2i(maxi(64, roundi(float(longest) * aspect)), longest)

func _can_refresh() -> bool:
	return (
		_definition != null
		and _definition.feature_enabled
		and _surface != null
		and _surface.visible
		and _viewport != null
		and _reflection_camera != null
		and _source_camera != null
		and is_instance_valid(_source_camera)
		and _source_camera.current
		and _source_camera.global_position.y > _surface_y + MIN_CAMERA_DISTANCE
	)

func _update_reflection_camera() -> void:
	var source_position := _source_camera.global_position
	var virtual_eye := Vector3(
		source_position.x,
		2.0 * _surface_y - source_position.y,
		source_position.z
	)
	var surface_center := _surface.global_position
	var distance := maxf(MIN_CAMERA_DISTANCE, surface_center.y - virtual_eye.y)
	var camera_right := Vector3.RIGHT
	var camera_up := Vector3.BACK
	var camera_back := Vector3.DOWN
	_reflection_camera.global_transform = Transform3D(
		Basis(camera_right, camera_up, camera_back),
		virtual_eye
	)
	var near_plane := maxf(0.02, distance * 0.985)
	var to_center := surface_center - virtual_eye
	var offset := Vector2(
		to_center.dot(camera_right) * near_plane / distance,
		to_center.dot(camera_up) * near_plane / distance
	)
	var frustum_height := _surface_size.y * near_plane / distance
	_reflection_camera.set_frustum(
		maxf(0.01, frustum_height),
		offset,
		near_plane,
		maxf(near_plane + 1.0, _source_camera.far)
	)
	_reflection_camera.environment = _source_camera.environment
	_reflection_camera.attributes = _source_camera.attributes

func _make_reflection_material(texture: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LevelReflectionShader
	material.set_shader_parameter("reflection_texture", texture)
	material.set_shader_parameter("surface_tint", _definition.surface_tint)
	material.set_shader_parameter("reflectivity", _definition.reflectivity)
	material.set_shader_parameter("reflection_brightness", _definition.reflection_brightness)
	material.set_shader_parameter("reflection_blur_pixels", _definition.reflection_blur_pixels)
	material.set_shader_parameter("fresnel_strength", _definition.fresnel_strength)
	material.set_shader_parameter("ripple_enabled", _definition.ripple_enabled)
	material.set_shader_parameter("ripple_strength", _definition.ripple_strength)
	material.set_shader_parameter("ripple_scale", _definition.ripple_scale)
	material.set_shader_parameter("ripple_speed", _definition.ripple_speed)
	material.set_shader_parameter("ripple_highlight_strength", _definition.ripple_highlight_strength)
	return material

func _on_grid_changed() -> void:
	_rebuild_surface_bounds()
	refresh_now()

func _on_level_loaded(_level: LevelResource) -> void:
	_rebuild_surface_bounds()
	refresh_now()

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	_rebuild_surface_bounds()
	refresh_now()

func _on_definition_changed() -> void:
	_apply_feature_state()
	if _definition == null or not _definition.feature_enabled or _surface == null:
		return
	if _viewport != null:
		_surface.material_override = _make_reflection_material(_viewport.get_texture())
