## Runtime projection overlay. It reuses a source building or tile-content
## snapshot, applies the exact composed reflection, and never occupies TileCellData.
class_name MirrorProjection
extends Node3D

static var _shared_rim_shader: Shader

const PathBlockerPolicyScript := preload("res://scripts/path/PathBlockerPolicy.gd")
const ContinuousLaserVisualScript := preload("res://scripts/combat/ContinuousLaserVisual.gd")
const MirrorCopyLinkVisualScript := preload("res://scripts/mirror/MirrorCopyLinkVisual.gd")
const PROJECTION_PRIORITY_BASE := 8
const PROJECTION_PRIORITY_STRIDE := 2
const PREVIEW_PRIORITY_OFFSET := 64

var payload: MirrorCopyPayload
var preview_mode: bool = false
var preview_valid: bool = true

var _grid: GridManager
var _tile_manager: TileManager
var _definition: CopyMirrorDefinition
var _tile_visual_snapshot_resolver: Callable
var _stack_index: int = 0
var _link_curve_index: int = 0
var _accent_color: Color = Color.WHITE
var _visual_snapshot: Node3D
var _copy_link_visual: Node3D
var _laser_visual: Node3D
var _laser_propagation_distance: float = 0.0
var _laser_origin: Vector3 = Vector3.ZERO
var _laser_direction: Vector3 = Vector3.ZERO
var _laser_endpoint_position: Vector3 = Vector3.ZERO
var _laser_segments: Array = []
var _laser_has_basis: bool = false
var _laser_has_endpoint: bool = false
var _laser_reflection_damage_multiplier: float = 1.0
var _laser_burst_position: Vector3 = Vector3.ZERO
var _laser_has_burst_target: bool = false
var _pulse_charge_orb: MeshInstance3D
var _pulse_charge_orb_phase: float = 0.0
var _pulse_overdrive_generation: int = -1
var _pulse_overdrive_propagation_distance: float = 0.0
var _pulse_overdrive_segments: Array = []
var _pulse_overdrive_endpoint: Vector3 = Vector3.ZERO
var _pulse_overdrive_has_endpoint: bool = false
var _pulse_overdrive_visual_color: Color = Color.TRANSPARENT
var _pulse_overdrive_visual_width: float = -1.0
var _pulse_overdrive_visual_configured: bool = false
var _inspection_label: Label3D
var _stack_indicator: MeshInstance3D

func _process(_delta: float) -> void:
	sync_source_visual_pose()

func configure(
	copy_payload: MirrorCopyPayload,
	grid_manager: GridManager,
	tile_manager: TileManager,
	mirror_definition: CopyMirrorDefinition,
	stack_index: int = 0,
	p_preview_mode: bool = false,
	tile_visual_snapshot_resolver: Callable = Callable(),
	p_preview_valid: bool = true,
	p_link_curve_index: int = 0
) -> void:
	payload = copy_payload
	_grid = grid_manager
	_tile_manager = tile_manager
	_definition = mirror_definition
	_stack_index = stack_index
	_link_curve_index = maxi(0, p_link_curve_index)
	preview_mode = p_preview_mode
	preview_valid = p_preview_valid
	_tile_visual_snapshot_resolver = tile_visual_snapshot_resolver
	var base_height := _tile_manager.get_world_height(payload.projected_cell) if _tile_manager != null else 0.0
	position = _grid.cell_to_world(payload.projected_cell) + Vector3(0.0, base_height, 0.0)
	_accent_color = _resolve_accent_color()
	_build_visual()
	_refresh_copy_link_visual()


func can_retarget_preview(next_payload: MirrorCopyPayload) -> bool:
	return (
		preview_mode
		and next_payload != null
		and payload != null
		and payload.root_source == next_payload.root_source
		and payload.tile_effect == next_payload.tile_effect
		and payload.copy_kind == next_payload.copy_kind
	)


## Reuses an existing projection snapshot when only its reflected destination
## and chain change during placement movement.
func retarget_preview(
	next_payload: MirrorCopyPayload,
	next_stack_index: int,
	next_preview_valid: bool,
	next_link_curve_index: int = 0
) -> bool:
	if not can_retarget_preview(next_payload):
		return false
	payload = next_payload
	_stack_index = next_stack_index
	_link_curve_index = maxi(0, next_link_curve_index)
	preview_valid = next_preview_valid
	var base_height := _tile_manager.get_world_height(payload.projected_cell) if _tile_manager != null else 0.0
	position = _grid.cell_to_world(payload.projected_cell) + Vector3(0.0, base_height, 0.0)
	_accent_color = _resolve_accent_color()
	_refresh_projection_instance_state(_visual_snapshot)
	_refresh_stack_indicator()
	if _inspection_label != null:
		_inspection_label.text = get_inspection_text()
		_inspection_label.position.y = _grid.cell_size * (1.08 + float(_stack_index) * 0.16)
		_inspection_label.modulate = _accent_color
	_refresh_copy_link_visual()
	sync_source_visual_pose()
	return true

func is_structure_alive() -> bool:
	return payload != null and payload.is_source_valid()


func is_destructible() -> bool:
	if payload == null or not payload.is_source_valid() or payload.root_source == null:
		return false
	if payload.root_source.has_method("is_destructible"):
		return bool(payload.root_source.call("is_destructible"))
	# Legacy TileObstacleRuntime predates the generic durability query. Its
	# obstacle-producing effect still identifies a concrete damageable source.
	return (
		payload.tile_effect != null
		and payload.tile_effect.creates_runtime_obstacle()
		and payload.root_source.has_method("take_structure_damage")
	)


func blocks_enemy_navigation(target: Node = null) -> bool:
	if payload == null or not payload.is_source_valid():
		return false
	if payload.root_source != null and payload.root_source.has_method("blocks_enemy_navigation"):
		return bool(payload.root_source.call("blocks_enemy_navigation", target))
	return payload.tile_effect != null and payload.tile_effect.blocks_enemy_navigation(target)


func blocks_ballistics() -> bool:
	return (
		payload != null
		and payload.is_source_valid()
		and payload.root_source != null
		and payload.root_source.has_method("blocks_ballistics")
		and bool(payload.root_source.call("blocks_ballistics"))
	)

func get_structure_target_position() -> Vector3:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_structure_target_position"):
		var source_position: Vector3 = payload.root_source.call("get_structure_target_position")
		return payload.transform_point(source_position)
	return global_position + Vector3(0.0, _grid.cell_size * 0.42, 0.0)

func get_structure_hit_radius() -> float:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_structure_hit_radius"):
		return float(payload.root_source.call("get_structure_hit_radius"))
	return _grid.cell_size * 0.30 if _grid != null else 0.3

func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not is_structure_alive() or not payload.root_source.has_method("take_structure_damage"):
		return 0.0
	return float(payload.root_source.call("take_structure_damage", amount, attacker))

func get_path_blocker_response() -> int:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_path_blocker_response"):
		return int(payload.root_source.call("get_path_blocker_response"))
	return PathBlockerPolicyScript.Response.DIRECT_ATTACK

func affects_target(target: Node) -> bool:
	if payload == null or not payload.is_source_valid():
		return false
	if payload.root_source != null and payload.root_source.has_method("affects_target"):
		return bool(payload.root_source.call("affects_target", target))
	if payload.tile_effect != null:
		return payload.tile_effect.affects_target(target)
	return true

func get_tile_effect() -> TileEffect:
	return payload.tile_effect if payload != null and payload.is_source_valid() else null

func get_visual_snapshot() -> Node3D:
	return _visual_snapshot


func debug_get_copy_link_curve_index() -> int:
	return int(_copy_link_visual.call("get_curve_index")) if _copy_link_visual != null else -1


func debug_get_copy_link_points() -> PackedVector3Array:
	return (
		_copy_link_visual.call("get_curve_points") as PackedVector3Array
		if _copy_link_visual != null
		else PackedVector3Array()
	)


func debug_get_copy_link_material() -> ShaderMaterial:
	return (
		_copy_link_visual.call("get_flow_material") as ShaderMaterial
		if _copy_link_visual != null
		else null
	)

func get_inspection_text() -> String:
	if payload == null:
		return ""
	return "%s · 虚像%d · 复制链%d" % [payload.display_name, _stack_index + 1, payload.chain_depth]


func set_pulse_special_inspection_status(status: String) -> void:
	if _inspection_label == null or payload == null:
		return
	_inspection_label.text = "%s · 虚像%d · 复制链%d · %s" % [
		payload.display_name,
		_stack_index + 1,
		payload.chain_depth,
		status,
	]

func set_inspection_active(active: bool) -> void:
	if _inspection_label != null:
		_inspection_label.visible = active or preview_mode

func show_laser(world_start: Vector3, world_end: Vector3) -> void:
	show_laser_path([{"start": world_start, "end": world_end}], world_end)


func show_laser_path(segments: Array, world_endpoint: Vector3) -> void:
	if _laser_visual == null:
		return
	_laser_visual.show_path(segments, world_endpoint)
	_laser_segments = segments.duplicate(true)
	_laser_endpoint_position = world_endpoint
	_laser_has_endpoint = true


func advance_laser_propagation(
	world_start: Vector3,
	direction_value: Vector3,
	delta: float,
	maximum_distance: float,
	propagation_speed: float
) -> float:
	if direction_value.length_squared() <= 0.000001:
		reset_laser_propagation()
		return 0.0
	var direction := direction_value.normalized()
	if (
		_laser_has_basis
		and (
			world_start.distance_squared_to(_laser_origin) > 0.000001
			or direction.dot(_laser_direction) < 0.99999
		)
	):
		reset_laser_propagation()
	_laser_origin = world_start
	_laser_direction = direction
	_laser_has_basis = true
	_laser_propagation_distance = minf(
		maxf(0.0, maximum_distance),
		_laser_propagation_distance + maxf(0.0, propagation_speed) * maxf(0.0, delta)
	)
	return _laser_propagation_distance


func clamp_laser_propagation(maximum_distance: float) -> void:
	_laser_propagation_distance = minf(
		_laser_propagation_distance,
		maxf(0.0, maximum_distance)
	)


func get_laser_endpoint(fallback: Vector3) -> Vector3:
	return _laser_endpoint_position if _laser_has_endpoint else fallback


func set_laser_burst_target(value: Dictionary) -> void:
	_laser_has_burst_target = bool(value.get("hit", false))
	_laser_burst_position = value.get("position", Vector3.ZERO)


func get_laser_burst_target() -> Dictionary:
	return {
		"hit": _laser_has_burst_target,
		"position": _laser_burst_position,
	}


func get_laser_propagation_distance() -> float:
	return _laser_propagation_distance


func set_laser_reflection_damage_multiplier(value: float) -> void:
	_laser_reflection_damage_multiplier = maxf(0.0, value) if is_finite(value) else 1.0


func get_laser_reflection_damage_multiplier() -> float:
	return _laser_reflection_damage_multiplier


func get_laser_propagation_state() -> Dictionary:
	return {
		"distance": _laser_propagation_distance,
		"origin": _laser_origin,
		"direction": _laser_direction,
		"endpoint": _laser_endpoint_position,
		"segments": _laser_segments.duplicate(true),
		"has_basis": _laser_has_basis,
		"has_endpoint": _laser_has_endpoint,
		"reflection_damage_multiplier": _laser_reflection_damage_multiplier,
		"burst_position": _laser_burst_position,
		"has_burst_target": _laser_has_burst_target,
	}


func restore_laser_propagation_state(state: Dictionary) -> void:
	_laser_propagation_distance = maxf(0.0, float(state.get("distance", 0.0)))
	_laser_origin = state.get("origin", Vector3.ZERO)
	_laser_direction = state.get("direction", Vector3.ZERO)
	_laser_endpoint_position = state.get("endpoint", Vector3.ZERO)
	_laser_segments = state.get("segments", []).duplicate(true)
	_laser_has_basis = bool(state.get("has_basis", false))
	_laser_has_endpoint = bool(state.get("has_endpoint", false))
	set_laser_reflection_damage_multiplier(float(state.get("reflection_damage_multiplier", 1.0)))
	_laser_burst_position = state.get("burst_position", Vector3.ZERO)
	_laser_has_burst_target = bool(state.get("has_burst_target", false))
	if _laser_has_endpoint and _laser_visual != null:
		_laser_visual.show_path(_laser_segments, _laser_endpoint_position)


func reset_laser_propagation() -> void:
	_laser_propagation_distance = 0.0
	_laser_origin = Vector3.ZERO
	_laser_direction = Vector3.ZERO
	_laser_endpoint_position = Vector3.ZERO
	_laser_segments.clear()
	_laser_has_basis = false
	_laser_has_endpoint = false
	_laser_reflection_damage_multiplier = 1.0
	_laser_burst_position = Vector3.ZERO
	_laser_has_burst_target = false
	if _laser_visual != null:
		_laser_visual.clear_path()


func update_pulse_charge_orb(
	world_position: Vector3,
	color: Color,
	base_radius: float,
	minimum_scale: float,
	maximum_scale: float,
	pulse_speed: float,
	delta: float
) -> void:
	if _pulse_charge_orb == null:
		return
	_pulse_charge_orb_phase += maxf(0.0, delta) * maxf(0.0, pulse_speed)
	var low := maxf(0.01, minimum_scale)
	var high := maxf(low, maximum_scale)
	var factor := lerpf(low, high, sin(_pulse_charge_orb_phase) * 0.5 + 0.5)
	var mesh := _pulse_charge_orb.mesh as SphereMesh
	if mesh != null:
		mesh.radius = maxf(0.001, base_radius)
		mesh.height = mesh.radius * 2.0
	var material := _pulse_charge_orb.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
		material.emission = color
	_pulse_charge_orb.position = to_local(world_position)
	_pulse_charge_orb.scale = Vector3.ONE * factor
	_pulse_charge_orb.visible = true


func hide_pulse_charge_orb() -> void:
	if _pulse_charge_orb != null:
		_pulse_charge_orb.visible = false


func advance_pulse_overdrive_propagation(
	generation: int,
	delta: float,
	maximum_distance: float,
	propagation_speed: float,
	initial_elapsed: float = 0.0
) -> float:
	if _pulse_overdrive_generation != generation:
		_pulse_overdrive_generation = generation
		_pulse_overdrive_propagation_distance = minf(
			maxf(0.0, maximum_distance),
			maxf(0.0, initial_elapsed) * maxf(0.0, propagation_speed)
		)
	_pulse_overdrive_propagation_distance = minf(
		maxf(0.0, maximum_distance),
		_pulse_overdrive_propagation_distance
			+ maxf(0.0, delta) * maxf(0.0, propagation_speed)
	)
	return _pulse_overdrive_propagation_distance


func show_pulse_overdrive_path(
	segments: Array,
	world_endpoint: Vector3,
	base_color: Color,
	base_width: float,
	emission_energy: float,
	sine_tuning: Dictionary = {}
) -> void:
	if _laser_visual == null:
		return
	if (
		not _pulse_overdrive_visual_configured
		or not _pulse_overdrive_visual_color.is_equal_approx(base_color)
		or not is_equal_approx(_pulse_overdrive_visual_width, base_width)
	):
		_laser_visual.configure(base_color, base_width, emission_energy)
		_pulse_overdrive_visual_color = base_color
		_pulse_overdrive_visual_width = base_width
		_pulse_overdrive_visual_configured = true
	_laser_visual.configure_single_sine_tuning(sine_tuning)
	_laser_visual.show_single_sine_path(segments, world_endpoint)
	_pulse_overdrive_segments = segments.duplicate(true)
	_pulse_overdrive_endpoint = world_endpoint
	_pulse_overdrive_has_endpoint = true


func clear_pulse_overdrive_path() -> void:
	if _laser_visual != null:
		_laser_visual.clear_path()
	_pulse_overdrive_segments.clear()
	_pulse_overdrive_has_endpoint = false


func get_pulse_special_state() -> Dictionary:
	return {
		"charge_orb_phase": _pulse_charge_orb_phase,
		"overdrive_generation": _pulse_overdrive_generation,
		"propagation_distance": _pulse_overdrive_propagation_distance,
		"segments": _pulse_overdrive_segments.duplicate(true),
		"endpoint": _pulse_overdrive_endpoint,
		"has_endpoint": _pulse_overdrive_has_endpoint,
		"visual_color": _pulse_overdrive_visual_color,
		"visual_width": _pulse_overdrive_visual_width,
	}


func restore_pulse_special_state(state: Dictionary) -> void:
	_pulse_charge_orb_phase = float(state.get("charge_orb_phase", 0.0))
	_pulse_overdrive_generation = int(state.get("overdrive_generation", -1))
	_pulse_overdrive_propagation_distance = maxf(
		0.0,
		float(state.get("propagation_distance", 0.0))
	)
	_pulse_overdrive_segments = state.get("segments", []).duplicate(true)
	_pulse_overdrive_endpoint = state.get("endpoint", Vector3.ZERO)
	_pulse_overdrive_has_endpoint = bool(state.get("has_endpoint", false))
	_pulse_overdrive_visual_color = state.get("visual_color", Color.TRANSPARENT)
	_pulse_overdrive_visual_width = float(state.get("visual_width", -1.0))
	# The projection node owns a newly constructed renderer. Restored values are
	# logical cache data only; force the first runtime update to configure the new
	# materials instead of mistaking the cache for live renderer state.
	_pulse_overdrive_visual_configured = false


func debug_is_pulse_charge_orb_visible() -> bool:
	return _pulse_charge_orb != null and _pulse_charge_orb.visible


func debug_get_pulse_charge_orb_phase() -> float:
	return _pulse_charge_orb_phase


func debug_get_pulse_overdrive_propagation_distance() -> float:
	return _pulse_overdrive_propagation_distance


func debug_get_pulse_overdrive_visual_color() -> Color:
	return _pulse_overdrive_visual_color


func debug_get_laser_base_color() -> Color:
	if _laser_visual == null or not _laser_visual.has_method("debug_get_beam_material"):
		return Color.TRANSPARENT
	var material := _laser_visual.call("debug_get_beam_material") as StandardMaterial3D
	return material.albedo_color if material != null else Color.TRANSPARENT


func debug_get_pulse_overdrive_rendered_color() -> Color:
	return (
		_laser_visual.call("debug_get_single_sine_segment_color", 0) as Color
		if _laser_visual != null and _laser_visual.has_method("debug_get_single_sine_segment_color")
		else Color.TRANSPARENT
	)


func debug_get_pulse_overdrive_wave_pair_count() -> int:
	return (
		int(_laser_visual.call("debug_get_wave_pair_count"))
		if _laser_visual != null and _laser_visual.has_method("debug_get_wave_pair_count")
		else 0
	)


func debug_get_pulse_overdrive_single_sine_count() -> int:
	return (
		int(_laser_visual.call("debug_get_single_sine_segment_count"))
		if _laser_visual != null and _laser_visual.has_method("debug_get_single_sine_segment_count")
		else 0
	)


func debug_get_pulse_overdrive_axis_segment_count() -> int:
	return (
		int(_laser_visual.call("debug_get_visible_axis_segment_count"))
		if _laser_visual != null and _laser_visual.has_method("debug_get_visible_axis_segment_count")
		else 0
	)

func _build_visual() -> void:
	if payload == null or _grid == null or _definition == null:
		return
	_visual_snapshot = _create_source_snapshot()
	if _visual_snapshot != null:
		add_child(_visual_snapshot)
		_visual_snapshot.top_level = true
		_apply_projection_materials(_visual_snapshot)
		sync_source_visual_pose()
	_build_stack_indicator()
	_build_inspection_label()
	if payload.copy_kind in [&"laser_tower", &"pulse_laser_tower"]:
		_laser_visual = ContinuousLaserVisualScript.new()
		_laser_visual.name = (
			&"ProjectedPulseOverdriveVisual"
			if payload.copy_kind == &"pulse_laser_tower"
			else &"ProjectedContinuousLaserVisual"
		)
		add_child(_laser_visual)
		var beam_color := Color(0.88, 0.96, 1.0, 0.96)
		var beam_width := _grid.cell_size * 0.08
		var beam_emission := 3.0
		if payload.root_source != null and payload.copy_kind == &"laser_tower":
			if payload.root_source.has_method("get_laser_beam_color"):
				beam_color = payload.root_source.call("get_laser_beam_color")
			if payload.root_source.has_method("get_laser_beam_width_world"):
				beam_width = float(payload.root_source.call("get_laser_beam_width_world"))
			if payload.root_source.has_method("get_laser_beam_emission_energy"):
				beam_emission = float(payload.root_source.call("get_laser_beam_emission_energy"))
		var ice_copy_effect := payload.attack_effects.get_effect_resource(&"ice_copy_burst")
		if ice_copy_effect != null and ice_copy_effect.has_method("get_copy_beam_color"):
			beam_color = ice_copy_effect.call("get_copy_beam_color") as Color
		_laser_visual.configure(beam_color, beam_width, beam_emission)
	if payload.copy_kind == &"pulse_laser_tower":
		_build_pulse_charge_orb()


func _refresh_copy_link_visual() -> void:
	if payload == null or _grid == null or _definition == null:
		return
	if _copy_link_visual == null:
		_copy_link_visual = MirrorCopyLinkVisualScript.new() as Node3D
		_copy_link_visual.name = &"CopySourceLink"
		add_child(_copy_link_visual)
	var endpoint_height := _grid.cell_size * _definition.copy_link_endpoint_height_ratio
	var source_height := (
		_tile_manager.get_world_height(payload.source_cell)
		if _tile_manager != null
		else 0.0
	)
	var target_height := (
		_tile_manager.get_world_height(payload.projected_cell)
		if _tile_manager != null
		else 0.0
	)
	var world_start := (
		_grid.cell_to_world(payload.source_cell)
		+ Vector3(0.0, source_height + endpoint_height, 0.0)
	)
	var world_end := (
		_grid.cell_to_world(payload.projected_cell)
		+ Vector3(0.0, target_height + endpoint_height, 0.0)
	)
	_copy_link_visual.call(
		"configure",
		to_local(world_start),
		to_local(world_end),
		_link_curve_index,
		_grid.cell_size,
		_definition.copy_link_color,
		_definition.copy_link_width_ratio,
		_definition.copy_link_arch_height_ratio,
		_definition.copy_link_sample_count,
		_definition.copy_link_flow_speed,
		_definition.copy_link_flow_repeat,
		_definition.copy_link_emission_energy
	)


func _build_pulse_charge_orb() -> void:
	_pulse_charge_orb = MeshInstance3D.new()
	_pulse_charge_orb.name = &"PulseMirrorChargeOrb"
	_pulse_charge_orb.mesh = SphereMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.025, 0.01, 0.92)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 5.0
	_pulse_charge_orb.material_override = material
	_pulse_charge_orb.visible = false
	add_child(_pulse_charge_orb)

func _create_source_snapshot() -> Node3D:
	if payload.root_source != null and payload.root_source.has_method("create_copy_visual_snapshot"):
		return payload.root_source.call("create_copy_visual_snapshot") as Node3D
	if payload.tile_effect != null and _tile_visual_snapshot_resolver.is_valid():
		return _tile_visual_snapshot_resolver.call(payload.root_source_cell) as Node3D
	return null

func _get_snapshot_transform() -> Transform3D:
	if payload.root_source != null and payload.root_source.has_method("get_copy_visual_transform"):
		var source_transform: Transform3D = payload.root_source.call("get_copy_visual_transform")
		return payload.transform_transform(source_transform)
	return payload.get_composed_transform()

## Synchronizes the existing behaviorless snapshot without rebuilding the
## projection node. Dynamic source pose is copied first, then the complete
## source transform receives every reflection in the payload chain.
func sync_source_visual_pose() -> bool:
	if is_queued_for_deletion():
		return false
	if _visual_snapshot == null or not is_instance_valid(_visual_snapshot):
		return false
	if payload == null or not payload.is_source_valid():
		visible = false
		return false
	visible = true
	if payload.root_source != null and payload.root_source.has_method("sync_copy_visual_snapshot"):
		payload.root_source.call("sync_copy_visual_snapshot", _visual_snapshot)
	_visual_snapshot.global_transform = _get_snapshot_transform()
	return true

func _apply_projection_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			_prepare_projection_materials(mesh_instance)
			mesh_instance.transparency = 1.0 - _get_projection_alpha()
	for child in node.get_children():
		_apply_projection_materials(child)


func _refresh_projection_instance_state(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			for child in node.get_children():
				_refresh_projection_instance_state(child)
			return
		mesh_instance.transparency = 1.0 - _get_projection_alpha()
		_refresh_projection_overlay_materials(mesh_instance)
		if mesh_instance.material_override != null:
			mesh_instance.material_override.render_priority = _get_render_priority(false)
		elif mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material != null:
					material.render_priority = _get_render_priority(false)
	for child in node.get_children():
		_refresh_projection_instance_state(child)

## GeometryInstance3D.transparency fades every source surface without replacing
## its material. A blue overlay makes the whole model unmistakably virtual while
## per-instance source duplicates preserve textures and mirrored culling.
func _prepare_projection_materials(mesh_instance: MeshInstance3D) -> void:
	# A selected source snapshot may carry its green live-selection overlay. Copies
	# always replace that state with their own blue next pass.
	mesh_instance.material_overlay = null
	if mesh_instance.material_override != null:
		mesh_instance.material_override = _duplicate_source_material(
			mesh_instance.material_override,
			_make_projection_overlay_material()
		)
		return
	if mesh_instance.mesh == null:
		return
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source_material := mesh_instance.get_surface_override_material(surface_index)
		if source_material == null:
			source_material = mesh_instance.mesh.surface_get_material(surface_index)
		if source_material == null:
			var fallback_material := StandardMaterial3D.new()
			fallback_material.albedo_color = Color.WHITE
			source_material = fallback_material
		mesh_instance.set_surface_override_material(
			surface_index,
			_duplicate_source_material(
				source_material,
				_make_projection_overlay_material()
			)
		)


func _duplicate_source_material(
	source_material: Material,
	projection_overlay: ShaderMaterial
) -> Material:
	var material := source_material.duplicate() as Material
	material.render_priority = _get_render_priority(false)
	material.next_pass = projection_overlay
	if material is BaseMaterial3D:
		var base_material := material as BaseMaterial3D
		if (
			preview_mode
			and preview_valid
			and payload != null
			and payload.root_source is Building
			and base_material.has_meta(&"preview_source_color")
		):
			var source_color: Color = base_material.get_meta(
				&"preview_source_color",
				Color.WHITE
			)
			source_color.a = (payload.root_source as Building).preview_alpha
			base_material.albedo_color = source_color
			var emissive := bool(base_material.get_meta(&"preview_emissive", false))
			base_material.emission_enabled = emissive
			if emissive:
				base_material.emission = source_color
				base_material.emission_energy_multiplier = 2.0
		base_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		base_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _refresh_projection_overlay_materials(mesh_instance: MeshInstance3D) -> void:
	var materials: Array[Material] = []
	if mesh_instance.material_override != null:
		materials.append(mesh_instance.material_override)
	elif mesh_instance.mesh != null:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_surface_override_material(surface_index)
			if material != null:
				materials.append(material)
	for material in materials:
		var projection_overlay := material.next_pass as ShaderMaterial
		if projection_overlay == null or projection_overlay.shader != _shared_rim_shader:
			projection_overlay = _make_projection_overlay_material()
			material.next_pass = projection_overlay
		else:
			projection_overlay.render_priority = _get_render_priority(true)
			projection_overlay.set_shader_parameter("accent", _accent_color)
			projection_overlay.set_shader_parameter("rim_alpha", _definition.projection_rim_alpha)
			projection_overlay.set_shader_parameter("body_alpha", 0.32 if not preview_valid else 0.18)


func _make_projection_overlay_material() -> ShaderMaterial:
	if _shared_rim_shader == null:
		_shared_rim_shader = Shader.new()
		_shared_rim_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform vec4 accent : source_color;
uniform float rim_alpha = 0.42;
uniform float body_alpha = 0.18;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.65);
	ALBEDO = accent.rgb;
	EMISSION = accent.rgb * (0.72 + rim * 2.8);
	ALPHA = clamp(body_alpha + rim * rim_alpha, 0.0, 0.72);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _shared_rim_shader
	material.render_priority = _get_render_priority(true)
	material.set_shader_parameter("accent", _accent_color)
	material.set_shader_parameter("rim_alpha", _definition.projection_rim_alpha)
	material.set_shader_parameter("body_alpha", 0.32 if not preview_valid else 0.18)
	return material


func _get_projection_alpha() -> float:
	if payload != null:
		return clampf(payload.projection_alpha, 0.05, 0.75)
	return clampf(_definition.projection_alpha, 0.05, 0.75)

func _build_stack_indicator() -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	var ring_spacing := _grid.cell_size * _definition.projection_ring_spacing_ratio
	mesh.inner_radius = _grid.cell_size * 0.29 + ring_spacing * float(_stack_index)
	mesh.outer_radius = mesh.inner_radius + _grid.cell_size * _definition.projection_ring_thickness_ratio
	ring.mesh = mesh
	ring.position.y = _grid.cell_size * 0.025
	ring.material_override = _make_line_material(_accent_color)
	add_child(ring)
	_stack_indicator = ring


func _refresh_stack_indicator() -> void:
	if _stack_indicator == null or not is_instance_valid(_stack_indicator):
		return
	var mesh := _stack_indicator.mesh as TorusMesh
	if mesh != null:
		var ring_spacing := _grid.cell_size * _definition.projection_ring_spacing_ratio
		mesh.inner_radius = _grid.cell_size * 0.29 + ring_spacing * float(_stack_index)
		mesh.outer_radius = mesh.inner_radius + _grid.cell_size * _definition.projection_ring_thickness_ratio
	var material := _stack_indicator.material_override as StandardMaterial3D
	if material == null:
		_stack_indicator.material_override = _make_line_material(_accent_color)
	else:
		material.albedo_color = _accent_color
		material.emission = _accent_color
		material.render_priority = _get_render_priority(true)

func _build_inspection_label() -> void:
	_inspection_label = Label3D.new()
	_inspection_label.text = get_inspection_text()
	_inspection_label.position.y = _grid.cell_size * (1.08 + float(_stack_index) * 0.16)
	_inspection_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_inspection_label.no_depth_test = true
	_inspection_label.font_size = 24
	_inspection_label.modulate = _accent_color
	_inspection_label.outline_size = 6
	_inspection_label.visible = preview_mode
	add_child(_inspection_label)

func _make_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = _definition.projection_emission_energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = _get_render_priority(true)
	return material

func _get_render_priority(overlay_pass: bool) -> int:
	var preview_offset := PREVIEW_PRIORITY_OFFSET if preview_mode else 0
	var priority := PROJECTION_PRIORITY_BASE + preview_offset + _stack_index * PROJECTION_PRIORITY_STRIDE
	if overlay_pass:
		priority += 1
	return clampi(priority, Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)

func _resolve_accent_color() -> Color:
	if preview_mode and not preview_valid:
		return _definition.invalid_preview_color
	return _definition.projection_tint
