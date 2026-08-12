## LightingController -- applies reusable lighting profiles to runtime levels.
class_name LightingController
extends Node3D

signal profile_changed(profile: LightingProfile, profile_index: int)
signal foliage_shadow_enabled_changed(enabled: bool)
signal realistic_tree_shadow_enabled_changed(enabled: bool)

const LightDefinitionScript := preload("res://scripts/lighting/LightDefinition.gd")
const FoliageShadowControllerScript := preload("res://scripts/lighting/FoliageShadowController.gd")
const RealisticTreeShadowControllerScript := preload("res://scripts/lighting/RealisticTreeShadowController.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Testing")
@export var test_shortcuts_enabled: bool = true

@export_group("Foliage Shadow")
@export var foliage_shadow_enabled: bool = true

@export_group("Realistic Tree Shadow")
@export var realistic_tree_shadow_enabled: bool = true

var _world_environment: WorldEnvironment
var _legacy_light: Light3D
var _grid: GridManager
var _terrain_manager: TerrainManager
var _display_case: AcrylicDisplayCase
var _display_case_visual_roots: Array[Node3D] = []
var _profiles: Array[LightingProfile] = []
var _active_profile: LightingProfile
var _active_profile_index: int = -1
var _active_lights_root: Node3D
var _fading_light_roots: Array[Node3D] = []
var _reflection_probe: ReflectionProbe
var _foliage_shadow: FoliageShadowControllerScript
var _realistic_tree_shadow: RealisticTreeShadowControllerScript
var _level_bounds: AABB = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, 5.0, 10.0))
var _profile_tween: Tween


func configure(
	world_environment: WorldEnvironment,
	legacy_light: Light3D,
	grid: GridManager,
	terrain_manager: TerrainManager,
	profiles: Array[LightingProfile],
	visual_roots: Array[Node3D] = [],
	foliage_shadow_definition: FoliageShadowDefinition = null,
	realistic_tree_shadow_definition: Resource = null
) -> void:
	_world_environment = world_environment
	_legacy_light = legacy_light
	_grid = grid
	_terrain_manager = terrain_manager
	_display_case_visual_roots = visual_roots.duplicate()
	_profiles = profiles.duplicate()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _legacy_light != null:
		_legacy_light.visible = not feature_enabled
	if _display_case == null:
		_display_case = AcrylicDisplayCase.new()
		_display_case.name = "AcrylicDisplayCase"
		add_child(_display_case)
	_display_case.configure(_grid, _terrain_manager, null, _display_case_visual_roots)
	if foliage_shadow_definition != null:
		if _foliage_shadow == null:
			_foliage_shadow = FoliageShadowControllerScript.new()
			_foliage_shadow.name = "FoliageShadowController"
			add_child(_foliage_shadow)
		_foliage_shadow.configure(foliage_shadow_definition)
		_foliage_shadow.set_effect_enabled(foliage_shadow_enabled)
	if realistic_tree_shadow_definition != null:
		if _realistic_tree_shadow == null:
			_realistic_tree_shadow = RealisticTreeShadowControllerScript.new()
			_realistic_tree_shadow.name = "RealisticTreeShadowController"
			add_child(_realistic_tree_shadow)
		_realistic_tree_shadow.configure(_grid, _terrain_manager, realistic_tree_shadow_definition)
		_realistic_tree_shadow.set_effect_enabled(realistic_tree_shadow_enabled)
	if feature_enabled and not _profiles.is_empty():
		apply_profile_by_index(0, 0.0)


func apply_level(level_resource: LevelResource) -> bool:
	if (
		not feature_enabled
		or _display_case == null
		or level_resource == null
		or level_resource.display_case_definition == null
	):
		return false
	_display_case.configure(
		_grid,
		_terrain_manager,
		level_resource.display_case_definition,
		_display_case_visual_roots
	)
	if not _display_case.rebuild_for_level():
		return false
	_level_bounds = _display_case.get_content_bounds()
	if _foliage_shadow != null:
		_foliage_shadow.rebuild(_level_bounds, _grid.cell_size if _grid != null else 1.0)
	if _realistic_tree_shadow != null:
		_realistic_tree_shadow.rebuild(_level_bounds, _grid.cell_size if _grid != null else 1.0)
	if level_resource.lighting_profile != null:
		_active_profile = level_resource.lighting_profile
		_active_profile_index = _profiles.find(_active_profile)
	if _active_profile != null:
		_apply_profile_runtime(_active_profile, 0.0)
	return true


func apply_profile_by_index(profile_index: int, duration: float = -1.0) -> bool:
	if profile_index < 0 or profile_index >= _profiles.size():
		return false
	return apply_profile(_profiles[profile_index], duration, profile_index)


func apply_profile(profile: LightingProfile, duration: float = -1.0, profile_index: int = -1) -> bool:
	if not feature_enabled or profile == null or not profile.validate_configuration().is_empty():
		return false
	_active_profile = profile
	_active_profile_index = profile_index if profile_index >= 0 else _profiles.find(profile)
	var resolved_duration := profile.default_transition_duration if duration < 0.0 else duration
	_apply_profile_runtime(profile, resolved_duration)
	profile_changed.emit(profile, _active_profile_index)
	return true


func get_active_profile() -> LightingProfile:
	return _active_profile


func get_active_profile_index() -> int:
	return _active_profile_index


func get_profiles() -> Array[LightingProfile]:
	return _profiles.duplicate()


func get_display_case() -> AcrylicDisplayCase:
	return _display_case


func get_reflection_probe() -> ReflectionProbe:
	return _reflection_probe


func get_foliage_shadow() -> FoliageShadowControllerScript:
	return _foliage_shadow


func get_realistic_tree_shadow() -> RealisticTreeShadowControllerScript:
	return _realistic_tree_shadow


func set_foliage_shadow_enabled(enabled: bool) -> void:
	foliage_shadow_enabled = enabled
	if _foliage_shadow == null:
		foliage_shadow_enabled_changed.emit(false)
		return
	_foliage_shadow.set_effect_enabled(enabled)
	foliage_shadow_enabled_changed.emit(_foliage_shadow.is_effect_enabled())


func is_foliage_shadow_enabled() -> bool:
	return _foliage_shadow != null and _foliage_shadow.is_effect_enabled()


func set_realistic_tree_shadow_enabled(enabled: bool) -> void:
	realistic_tree_shadow_enabled = enabled
	if _realistic_tree_shadow == null:
		realistic_tree_shadow_enabled_changed.emit(false)
		return
	_realistic_tree_shadow.set_effect_enabled(enabled)
	realistic_tree_shadow_enabled_changed.emit(_realistic_tree_shadow.is_effect_enabled())


func is_realistic_tree_shadow_enabled() -> bool:
	return _realistic_tree_shadow != null and _realistic_tree_shadow.is_effect_enabled()


func get_generated_light_count() -> int:
	return _active_lights_root.get_child_count() if _active_lights_root != null else 0


func _unhandled_input(event: InputEvent) -> void:
	if not feature_enabled or not test_shortcuts_enabled:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var index := -1
	match key_event.keycode:
		KEY_6:
			index = 3
		KEY_7:
			index = 0
		KEY_8:
			index = 1
		KEY_9:
			index = 2
	if index >= 0 and apply_profile_by_index(index):
		get_viewport().set_input_as_handled()


func _apply_profile_runtime(profile: LightingProfile, duration: float) -> void:
	_stop_transition()
	var target_environment := profile.environment_template.duplicate(true) as Environment
	var runtime_environment := target_environment.duplicate(true) as Environment
	var source_environment := (
		_world_environment.environment.duplicate(true) as Environment
		if _world_environment != null and _world_environment.environment != null
		else target_environment.duplicate(true) as Environment
	)
	if _world_environment != null:
		_world_environment.environment = runtime_environment

	var previous_root := _active_lights_root
	_active_lights_root = _build_lights_root(profile, duration > 0.0)
	if previous_root != null:
		_fading_light_roots.append(previous_root)

	_display_case.apply_lighting(profile.display_case_lighting)
	_configure_reflection_probe(profile.reflection_probe)
	if duration <= 0.0:
		if _world_environment != null:
			_world_environment.environment = target_environment
		_free_fading_roots()
		return

	_copy_environment_continuous(source_environment, runtime_environment)
	_profile_tween = create_tween()
	_profile_tween.set_parallel(true)
	_profile_tween.tween_method(
		_blend_environment.bind(source_environment, target_environment, runtime_environment),
		0.0,
		1.0,
		duration
	)
	for child in _active_lights_root.get_children():
		var light := child as Light3D
		if light == null:
			continue
		var target_energy := float(light.get_meta("target_energy", light.light_energy))
		_profile_tween.tween_property(light, "light_energy", target_energy, duration)
	for old_root in _fading_light_roots:
		for child in old_root.get_children():
			var light := child as Light3D
			if light != null:
				_profile_tween.tween_property(light, "light_energy", 0.0, duration)
	_profile_tween.chain().tween_callback(_finish_transition.bind(target_environment))


func _build_lights_root(profile: LightingProfile, start_dark: bool) -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "Lights_%s" % String(profile.profile_id)
	add_child(root_node)
	for definition in profile.lights:
		if definition == null or not definition.feature_enabled:
			continue
		var light := _create_light(definition)
		if light == null:
			continue
		light.name = String(definition.light_id)
		root_node.add_child(light)
		_apply_light_definition(light, definition)
		light.set_meta("target_energy", definition.energy)
		if start_dark:
			light.light_energy = 0.0
	return root_node


func _create_light(definition: LightDefinitionScript) -> Light3D:
	match definition.kind:
		LightDefinitionScript.Kind.DIRECTIONAL:
			return DirectionalLight3D.new()
		LightDefinitionScript.Kind.OMNI:
			return OmniLight3D.new()
		LightDefinitionScript.Kind.SPOT:
			return SpotLight3D.new()
		LightDefinitionScript.Kind.AREA:
			return AreaLight3D.new()
	return null


func _apply_light_definition(light: Light3D, definition: LightDefinitionScript) -> void:
	light.light_color = definition.color
	light.light_energy = definition.energy
	light.light_indirect_energy = definition.indirect_energy
	light.light_specular = definition.specular
	light.light_volumetric_fog_energy = definition.volumetric_fog_energy
	light.light_angular_distance = definition.angular_distance
	light.shadow_enabled = definition.shadow_enabled
	light.shadow_opacity = definition.shadow_opacity
	light.shadow_bias = definition.shadow_bias
	light.shadow_normal_bias = definition.shadow_normal_bias
	light.shadow_blur = definition.shadow_blur
	var level_span := maxf(_level_bounds.size.x, _level_bounds.size.z)
	if light is DirectionalLight3D:
		(light as DirectionalLight3D).directional_shadow_max_distance = maxf(
			definition.directional_shadow_max_distance,
			level_span * 2.0
		)
	elif light is OmniLight3D:
		var omni := light as OmniLight3D
		omni.omni_range = maxf(definition.range, level_span * 1.25 if definition.shape_scales_with_level else definition.range)
		omni.omni_attenuation = definition.attenuation
	elif light is SpotLight3D:
		var spot := light as SpotLight3D
		spot.spot_range = maxf(definition.range, level_span * 1.25 if definition.shape_scales_with_level else definition.range)
		spot.spot_attenuation = definition.attenuation
		spot.spot_angle = definition.spot_angle
		spot.spot_angle_attenuation = definition.spot_angle_attenuation
	elif light is AreaLight3D:
		var area := light as AreaLight3D
		area.area_range = maxf(definition.range, level_span * 1.25 if definition.shape_scales_with_level else definition.range)
		area.area_attenuation = definition.attenuation
		area.area_normalize_energy = definition.normalize_area_energy
		area.area_size = (
			Vector2(
				maxf(0.1, _level_bounds.size.x * definition.area_size.x),
				maxf(0.1, _level_bounds.size.z * definition.area_size.y)
			)
			if definition.shape_scales_with_level
			else definition.area_size
		)
	var resolved_position := _resolve_light_position(definition)
	light.global_position = resolved_position
	if definition.aim_at_level_center:
		var target := _get_level_target() + definition.target_offset
		if not resolved_position.is_equal_approx(target):
			light.look_at(target, Vector3.UP)
	else:
		light.rotation_degrees = definition.rotation_degrees


func _resolve_light_position(definition: LightDefinitionScript) -> Vector3:
	var center := _get_level_target()
	if definition.position_space == LightDefinitionScript.PositionSpace.LEVEL_UNITS:
		return to_global(definition.position)
	var half_extents := Vector3(_level_bounds.size.x * 0.5, 0.0, _level_bounds.size.z * 0.5)
	var span := maxf(_level_bounds.size.x, _level_bounds.size.z)
	var local_position := center + Vector3(
		definition.position.x * half_extents.x,
		definition.position.y * span,
		definition.position.z * half_extents.z
	)
	return to_global(local_position)


func _get_level_target() -> Vector3:
	return _level_bounds.position + Vector3(
		_level_bounds.size.x * 0.5,
		_level_bounds.size.y * 0.35,
		_level_bounds.size.z * 0.5
	)


func _configure_reflection_probe(definition: ReflectionProbeDefinition) -> void:
	if definition == null or not definition.feature_enabled:
		if _reflection_probe != null:
			_reflection_probe.visible = false
		return
	if _reflection_probe == null:
		_reflection_probe = ReflectionProbe.new()
		_reflection_probe.name = "DisplayCaseReflectionProbe"
		add_child(_reflection_probe)
	_reflection_probe.visible = true
	var margin := definition.bounds_margin_cells * (_grid.cell_size if _grid != null else 1.0)
	var probe_size := _level_bounds.size + Vector3.ONE * margin * 2.0
	_reflection_probe.position = _level_bounds.position + _level_bounds.size * 0.5
	_reflection_probe.size = probe_size
	_reflection_probe.blend_distance = definition.blend_distance_cells * (_grid.cell_size if _grid != null else 1.0)
	_reflection_probe.max_distance = maxf(probe_size.x, maxf(probe_size.y, probe_size.z)) * definition.max_distance_multiplier
	_reflection_probe.intensity = definition.intensity
	_reflection_probe.box_projection = definition.box_projection
	_reflection_probe.enable_shadows = definition.enable_shadows
	_reflection_probe.update_mode = (
		ReflectionProbe.UPDATE_ALWAYS if definition.update_always else ReflectionProbe.UPDATE_ONCE
	)


func _stop_transition() -> void:
	if _profile_tween != null and _profile_tween.is_valid():
		_profile_tween.kill()
	_profile_tween = null
	_free_fading_roots()


func _finish_transition(target_environment: Environment) -> void:
	if _world_environment != null:
		_world_environment.environment = target_environment
	_free_fading_roots()
	_profile_tween = null


func _free_fading_roots() -> void:
	for root_node in _fading_light_roots:
		if root_node != null and is_instance_valid(root_node):
			root_node.free()
	_fading_light_roots.clear()


func _copy_environment_continuous(source: Environment, target: Environment) -> void:
	target.background_color = source.background_color
	target.background_energy_multiplier = source.background_energy_multiplier
	target.ambient_light_color = source.ambient_light_color
	target.ambient_light_energy = source.ambient_light_energy
	target.ambient_light_sky_contribution = source.ambient_light_sky_contribution
	target.tonemap_exposure = source.tonemap_exposure
	target.tonemap_white = source.tonemap_white
	target.tonemap_agx_contrast = source.tonemap_agx_contrast
	target.tonemap_agx_white = source.tonemap_agx_white
	target.adjustment_brightness = source.adjustment_brightness
	target.adjustment_contrast = source.adjustment_contrast
	target.adjustment_saturation = source.adjustment_saturation
	target.ssao_intensity = source.ssao_intensity
	target.ssao_power = source.ssao_power
	target.ssao_radius = source.ssao_radius
	target.ssil_intensity = source.ssil_intensity
	target.ssil_radius = source.ssil_radius
	target.glow_intensity = source.glow_intensity
	target.glow_bloom = source.glow_bloom
	target.glow_strength = source.glow_strength
	target.fog_light_color = source.fog_light_color
	target.fog_light_energy = source.fog_light_energy
	target.fog_density = source.fog_density


func _blend_environment(
	weight: float,
	source: Environment,
	target: Environment,
	runtime: Environment
) -> void:
	runtime.background_color = source.background_color.lerp(target.background_color, weight)
	runtime.background_energy_multiplier = lerpf(source.background_energy_multiplier, target.background_energy_multiplier, weight)
	runtime.ambient_light_color = source.ambient_light_color.lerp(target.ambient_light_color, weight)
	runtime.ambient_light_energy = lerpf(source.ambient_light_energy, target.ambient_light_energy, weight)
	runtime.ambient_light_sky_contribution = lerpf(source.ambient_light_sky_contribution, target.ambient_light_sky_contribution, weight)
	runtime.tonemap_exposure = lerpf(source.tonemap_exposure, target.tonemap_exposure, weight)
	runtime.tonemap_white = lerpf(source.tonemap_white, target.tonemap_white, weight)
	runtime.tonemap_agx_contrast = lerpf(source.tonemap_agx_contrast, target.tonemap_agx_contrast, weight)
	runtime.tonemap_agx_white = lerpf(source.tonemap_agx_white, target.tonemap_agx_white, weight)
	runtime.adjustment_brightness = lerpf(source.adjustment_brightness, target.adjustment_brightness, weight)
	runtime.adjustment_contrast = lerpf(source.adjustment_contrast, target.adjustment_contrast, weight)
	runtime.adjustment_saturation = lerpf(source.adjustment_saturation, target.adjustment_saturation, weight)
	runtime.ssao_intensity = lerpf(source.ssao_intensity, target.ssao_intensity, weight)
	runtime.ssao_power = lerpf(source.ssao_power, target.ssao_power, weight)
	runtime.ssao_radius = lerpf(source.ssao_radius, target.ssao_radius, weight)
	runtime.ssil_intensity = lerpf(source.ssil_intensity, target.ssil_intensity, weight)
	runtime.ssil_radius = lerpf(source.ssil_radius, target.ssil_radius, weight)
	runtime.glow_intensity = lerpf(source.glow_intensity, target.glow_intensity, weight)
	runtime.glow_bloom = lerpf(source.glow_bloom, target.glow_bloom, weight)
	runtime.glow_strength = lerpf(source.glow_strength, target.glow_strength, weight)
	runtime.fog_light_color = source.fog_light_color.lerp(target.fog_light_color, weight)
	runtime.fog_light_energy = lerpf(source.fog_light_energy, target.fog_light_energy, weight)
	runtime.fog_density = lerpf(source.fog_density, target.fog_density, weight)
