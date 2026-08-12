## Runtime projection overlay. It reuses a source building or tile-content
## snapshot, applies the exact composed reflection, and never occupies TileCellData.
class_name MirrorProjection
extends Node3D

static var _shared_rim_shader: Shader

const PathBlockerPolicyScript := preload("res://scripts/path/PathBlockerPolicy.gd")
const ContinuousLaserVisualScript := preload("res://scripts/combat/ContinuousLaserVisual.gd")
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
var _accent_color: Color = Color.WHITE
var _visual_snapshot: Node3D
var _laser_visual: Node3D
var _laser_propagation_distance: float = 0.0
var _laser_origin: Vector3 = Vector3.ZERO
var _laser_direction: Vector3 = Vector3.ZERO
var _laser_endpoint_position: Vector3 = Vector3.ZERO
var _laser_segments: Array = []
var _laser_has_basis: bool = false
var _laser_has_endpoint: bool = false
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
	p_preview_valid: bool = true
) -> void:
	payload = copy_payload
	_grid = grid_manager
	_tile_manager = tile_manager
	_definition = mirror_definition
	_stack_index = stack_index
	preview_mode = p_preview_mode
	preview_valid = p_preview_valid
	_tile_visual_snapshot_resolver = tile_visual_snapshot_resolver
	var base_height := _tile_manager.get_world_height(payload.projected_cell) if _tile_manager != null else 0.0
	position = _grid.cell_to_world(payload.projected_cell) + Vector3(0.0, base_height, 0.0)
	_accent_color = _resolve_accent_color()
	_build_visual()


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
	next_preview_valid: bool
) -> bool:
	if not can_retarget_preview(next_payload):
		return false
	payload = next_payload
	_stack_index = next_stack_index
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

func get_inspection_text() -> String:
	if payload == null:
		return ""
	return "%s · 虚像%d · 复制链%d" % [payload.display_name, _stack_index + 1, payload.chain_depth]

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


func get_laser_propagation_distance() -> float:
	return _laser_propagation_distance


func get_laser_propagation_state() -> Dictionary:
	return {
		"distance": _laser_propagation_distance,
		"origin": _laser_origin,
		"direction": _laser_direction,
		"endpoint": _laser_endpoint_position,
		"segments": _laser_segments.duplicate(true),
		"has_basis": _laser_has_basis,
		"has_endpoint": _laser_has_endpoint,
	}


func restore_laser_propagation_state(state: Dictionary) -> void:
	_laser_propagation_distance = maxf(0.0, float(state.get("distance", 0.0)))
	_laser_origin = state.get("origin", Vector3.ZERO)
	_laser_direction = state.get("direction", Vector3.ZERO)
	_laser_endpoint_position = state.get("endpoint", Vector3.ZERO)
	_laser_segments = state.get("segments", []).duplicate(true)
	_laser_has_basis = bool(state.get("has_basis", false))
	_laser_has_endpoint = bool(state.get("has_endpoint", false))
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
	if _laser_visual != null:
		_laser_visual.clear_path()

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
	if payload.copy_kind == &"laser_tower":
		_laser_visual = ContinuousLaserVisualScript.new()
		_laser_visual.name = &"ProjectedContinuousLaserVisual"
		add_child(_laser_visual)
		var beam_color := Color(0.88, 0.96, 1.0, 0.96)
		var beam_width := _grid.cell_size * 0.08
		var beam_emission := 3.0
		if payload.root_source != null:
			if payload.root_source.has_method("get_laser_beam_color"):
				beam_color = payload.root_source.call("get_laser_beam_color")
			if payload.root_source.has_method("get_laser_beam_width_world"):
				beam_width = float(payload.root_source.call("get_laser_beam_width_world"))
			if payload.root_source.has_method("get_laser_beam_emission_energy"):
				beam_emission = float(payload.root_source.call("get_laser_beam_emission_energy"))
		_laser_visual.configure(beam_color, beam_width, beam_emission)

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
		_prepare_projection_materials(mesh_instance)
		mesh_instance.transparency = 1.0 - clampf(_definition.projection_alpha, 0.05, 1.0)
		if preview_mode and not preview_valid:
			mesh_instance.material_overlay = _make_invalid_preview_material()
	for child in node.get_children():
		_apply_projection_materials(child)


func _refresh_projection_instance_state(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.transparency = 1.0 - clampf(_definition.projection_alpha, 0.05, 1.0)
		if preview_valid:
			mesh_instance.material_overlay = null
		else:
			var invalid_overlay := mesh_instance.material_overlay as ShaderMaterial
			if invalid_overlay == null or invalid_overlay.shader != _shared_rim_shader:
				invalid_overlay = _make_invalid_preview_material()
				mesh_instance.material_overlay = invalid_overlay
			else:
				invalid_overlay.render_priority = _get_render_priority(true)
				invalid_overlay.set_shader_parameter("accent", _accent_color)
				invalid_overlay.set_shader_parameter("rim_alpha", _definition.projection_rim_alpha)
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
## its material. Per-instance duplicates are used only for deterministic render
## order and mirrored culling, preserving every source color, texture and shader.
func _prepare_projection_materials(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.material_override != null:
		mesh_instance.material_override = _duplicate_source_material(mesh_instance.material_override)
		return
	if mesh_instance.mesh == null:
		return
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source_material := mesh_instance.get_surface_override_material(surface_index)
		if source_material == null:
			source_material = mesh_instance.mesh.surface_get_material(surface_index)
		if source_material != null:
			mesh_instance.set_surface_override_material(
				surface_index,
				_duplicate_source_material(source_material)
			)


func _duplicate_source_material(source_material: Material) -> Material:
	var material := source_material.duplicate() as Material
	material.render_priority = _get_render_priority(false)
	if material is BaseMaterial3D:
		var base_material := material as BaseMaterial3D
		base_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		base_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _make_invalid_preview_material() -> ShaderMaterial:
	if _shared_rim_shader == null:
		_shared_rim_shader = Shader.new()
		_shared_rim_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform vec4 accent : source_color;
uniform float rim_alpha = 0.42;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = accent.rgb;
	EMISSION = accent.rgb * (0.8 + rim * 1.8);
	ALPHA = clamp(rim * rim_alpha, 0.0, 0.78);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _shared_rim_shader
	material.render_priority = _get_render_priority(true)
	material.set_shader_parameter("accent", _accent_color)
	material.set_shader_parameter("rim_alpha", _definition.projection_rim_alpha)
	return material

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
	var stable_hash := absi(payload.stable_key.hash()) if payload != null else 0
	var hue_shift := fmod(float(stable_hash % 997) / 997.0 + float(_stack_index) * 0.173, 1.0)
	var palette_color := Color.from_hsv(hue_shift, 0.58, 1.0, 1.0)
	return _definition.projection_tint.lerp(palette_color, 0.46)
