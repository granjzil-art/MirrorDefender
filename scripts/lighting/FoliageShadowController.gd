## FoliageShadowController -- generates and animates an invisible shadow-only canopy card.
class_name FoliageShadowController
extends Node3D

signal effect_enabled_changed(enabled: bool)

@export_group("Feature")
@export var feature_enabled: bool = true

var _definition: FoliageShadowDefinition
var _caster: MeshInstance3D
var _material: StandardMaterial3D
var _pattern_texture: ImageTexture
var _effect_enabled: bool = true
var _elapsed: float = 0.0
var _last_bounds: AABB = AABB()
var _last_cell_size: float = 1.0
var _pattern_statistics: Dictionary = {
	"coverage_ratio": 0.0,
	"mean_opacity": 0.0,
}


func configure(definition: FoliageShadowDefinition) -> bool:
	_definition = definition
	_elapsed = 0.0
	if _definition == null or not _definition.validate_configuration().is_empty():
		_effect_enabled = false
		set_process(false)
		return false
	_effect_enabled = feature_enabled and _definition.feature_enabled
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(_effect_enabled and _definition.motion_enabled)
	return true


func _process(delta: float) -> void:
	advance_motion(delta)


func rebuild(bounds: AABB, cell_size: float) -> bool:
	if _definition == null or not _definition.validate_configuration().is_empty():
		_hide_caster()
		return false
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		_hide_caster()
		return false
	_last_bounds = bounds
	_last_cell_size = maxf(0.01, cell_size)
	_ensure_caster()
	_pattern_texture = _generate_pattern_texture()
	_material.albedo_texture = _pattern_texture
	_material.albedo_color = Color.WHITE
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	_material.alpha_hash_scale = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_material.uv1_scale = Vector3(_definition.pattern_tiles.x, _definition.pattern_tiles.y, 1.0)
	var margin := _definition.horizontal_margin_cells * _last_cell_size
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size.x + margin * 2.0, bounds.size.z + margin * 2.0)
	_caster.mesh = plane
	_caster.position = Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.end.y + _definition.height_above_content_cells * _last_cell_size,
		bounds.position.z + bounds.size.z * 0.5
	)
	_caster.extra_cull_margin = maxf(32.0, plane.size.length() * 2.0)
	_caster.ignore_occlusion_culling = true
	_caster.visible = _effect_enabled
	_elapsed = 0.0
	_apply_motion()
	return true


func set_effect_enabled(enabled: bool) -> void:
	var resolved := enabled and feature_enabled and _definition != null and _definition.feature_enabled
	if resolved == _effect_enabled and (_caster == null or _caster.visible == resolved):
		return
	_effect_enabled = resolved
	if _caster != null:
		_caster.visible = _effect_enabled
	set_process(_effect_enabled and _definition != null and _definition.motion_enabled)
	effect_enabled_changed.emit(_effect_enabled)


func is_effect_enabled() -> bool:
	return _effect_enabled


func advance_motion(delta: float) -> bool:
	if not _effect_enabled or _definition == null or not _definition.motion_enabled or _material == null:
		return false
	_elapsed += maxf(0.0, delta)
	_apply_motion()
	return true


func get_caster() -> MeshInstance3D:
	return _caster


func get_pattern_texture() -> ImageTexture:
	return _pattern_texture


func get_pattern_statistics() -> Dictionary:
	return _pattern_statistics.duplicate()


func get_definition() -> FoliageShadowDefinition:
	return _definition


func _ensure_caster() -> void:
	if _caster != null:
		return
	_caster = MeshInstance3D.new()
	_caster.name = "ProceduralFoliageShadowCaster"
	_caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_material = StandardMaterial3D.new()
	_caster.material_override = _material
	add_child(_caster)


func _hide_caster() -> void:
	if _caster != null:
		_caster.visible = false


func _apply_motion() -> void:
	if _material == null or _definition == null:
		return
	var x_offset := sin(_elapsed * _definition.motion_speed + _definition.phase) * _definition.sway_uv.x
	var y_offset := sin(
		_elapsed * _definition.motion_speed * 0.73 + _definition.phase * 1.71
	) * _definition.sway_uv.y
	_material.uv1_offset = Vector3(x_offset, y_offset, 0.0)


func _generate_pattern_texture() -> ImageTexture:
	var resolution := _definition.texture_resolution
	var random := RandomNumberGenerator.new()
	random.seed = _definition.pattern_seed
	var leaves: Array[Dictionary] = []
	for _cluster_index in range(_definition.cluster_count):
		var cluster_center := Vector2(random.randf(), random.randf())
		var leaf_count := random.randi_range(
			_definition.leaves_per_cluster_min,
			_definition.leaves_per_cluster_max
		)
		for _leaf_index in range(leaf_count):
			var angle := random.randf_range(0.0, TAU)
			var distance := random.randf_range(0.0, _definition.cluster_spread_uv)
			var center := cluster_center + Vector2(cos(angle), sin(angle)) * distance
			center.x = fposmod(center.x, 1.0)
			center.y = fposmod(center.y, 1.0)
			var radius_x := random.randf_range(
				_definition.leaf_radius_min_uv,
				_definition.leaf_radius_max_uv
			)
			var radius_y := radius_x * random.randf_range(0.45, 0.75)
			leaves.append({
				"center": center,
				"radius": Vector2(radius_x, radius_y),
				"rotation": random.randf_range(0.0, TAU),
			})
	var image := Image.create(resolution, resolution, true, Image.FORMAT_RGBA8)
	var covered_pixels := 0
	var opacity_sum := 0.0
	var feather_start := 1.0 - _definition.edge_softness
	for y in range(resolution):
		for x in range(resolution):
			var uv := Vector2(
				(float(x) + 0.5) / float(resolution),
				(float(y) + 0.5) / float(resolution)
			)
			var mask := 0.0
			for leaf in leaves:
				var center: Vector2 = leaf.get("center", Vector2.ZERO)
				var radius: Vector2 = leaf.get("radius", Vector2.ONE)
				var rotation: float = float(leaf.get("rotation", 0.0))
				var delta := uv - center
				delta.x -= roundf(delta.x)
				delta.y -= roundf(delta.y)
				var local := delta.rotated(-rotation)
				var normalized_distance := Vector2(
					local.x / maxf(radius.x, 0.0001),
					local.y / maxf(radius.y, 0.0001)
				).length()
				var leaf_mask := 1.0 - smoothstep(feather_start, 1.0, normalized_distance)
				mask = maxf(mask, leaf_mask)
			var opacity := clampf(mask * _definition.shadow_strength, 0.0, 1.0)
			if opacity > 0.01:
				covered_pixels += 1
			opacity_sum += opacity
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, opacity))
	image.generate_mipmaps()
	var pixel_count := float(resolution * resolution)
	_pattern_statistics = {
		"coverage_ratio": float(covered_pixels) / pixel_count,
		"mean_opacity": opacity_sum / pixel_count,
		"leaf_count": leaves.size(),
	}
	return ImageTexture.create_from_image(image)
