## Programmatic flash, pressure ring and smoke shell for a missile explosion.
class_name MissileExplosionEffect
extends Node3D

const FIRE_RED := Color(1.0, 0.045, 0.012, 1.0)
const FIRE_ORANGE := Color(1.0, 0.30, 0.025, 1.0)
const FIRE_YELLOW := Color(1.0, 0.82, 0.10, 1.0)
const FIRE_SMOKE := Color(0.24, 0.045, 0.018, 0.56)

var _duration: float = 0.48
var _elapsed: float = 0.0
var _radius: float = 1.0
var _flash: MeshInstance3D
var _outer_ring: MeshInstance3D
var _middle_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _smoke: MeshInstance3D
var _flash_material: StandardMaterial3D
var _outer_ring_material: StandardMaterial3D
var _middle_ring_material: StandardMaterial3D
var _inner_ring_material: StandardMaterial3D
var _smoke_material: StandardMaterial3D


func configure(
	world_position: Vector3,
	radius: float,
	_projectile_color: Color,
	duration: float
) -> void:
	global_position = world_position
	_radius = maxf(0.05, radius)
	_duration = maxf(0.05, duration)
	_build_visual()
	_apply_factor(0.0)


func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	var factor := clampf(_elapsed / _duration, 0.0, 1.0)
	_apply_factor(factor)
	if factor >= 1.0:
		queue_free()


func _build_visual() -> void:
	_flash = MeshInstance3D.new()
	_flash.name = &"MissileExplosionFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = _radius * 0.32
	flash_mesh.height = flash_mesh.radius * 2.0
	_flash.mesh = flash_mesh
	_flash_material = _make_material(FIRE_YELLOW.lightened(0.12), 5.2)
	_flash.material_override = _flash_material
	add_child(_flash)

	_outer_ring = _make_fire_ring(
		&"MissileExplosionOuterRed",
		_radius * 0.76,
		_radius,
		FIRE_RED,
		3.8,
		0.012
	)
	_outer_ring_material = _outer_ring.material_override as StandardMaterial3D
	add_child(_outer_ring)

	_middle_ring = _make_fire_ring(
		&"MissileExplosionMiddleOrange",
		_radius * 0.51,
		_radius * 0.78,
		FIRE_ORANGE,
		4.4,
		0.024
	)
	_middle_ring_material = _middle_ring.material_override as StandardMaterial3D
	add_child(_middle_ring)

	_inner_ring = _make_fire_ring(
		&"MissileExplosionInnerYellow",
		_radius * 0.28,
		_radius * 0.54,
		FIRE_YELLOW,
		5.0,
		0.036
	)
	_inner_ring_material = _inner_ring.material_override as StandardMaterial3D
	add_child(_inner_ring)

	_smoke = MeshInstance3D.new()
	_smoke.name = &"MissileExplosionSmoke"
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = _radius * 0.46
	smoke_mesh.height = smoke_mesh.radius * 1.5
	_smoke.mesh = smoke_mesh
	_smoke_material = _make_material(FIRE_SMOKE, 0.28)
	_smoke.material_override = _smoke_material
	add_child(_smoke)


func _make_fire_ring(
	node_name: StringName,
	inner_radius: float,
	outer_radius: float,
	color: Color,
	energy: float,
	height_offset: float
) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	ring.mesh = mesh
	ring.position.y = height_offset
	ring.material_override = _make_material(color, energy)
	return ring


func _apply_factor(factor: float) -> void:
	var flash_growth := lerpf(0.18, 1.3, minf(1.0, factor * 2.0))
	_flash.scale = Vector3.ONE * flash_growth * maxf(0.01, 1.0 - factor)
	var outer_growth := lerpf(0.06, 1.0, factor)
	var middle_growth := lerpf(0.08, 0.86, minf(1.0, factor * 1.10))
	var inner_growth := lerpf(0.10, 0.68, minf(1.0, factor * 1.22))
	_outer_ring.scale = Vector3(outer_growth, maxf(0.04, 1.0 - factor), outer_growth)
	_middle_ring.scale = Vector3(middle_growth, maxf(0.05, 1.0 - factor), middle_growth)
	_inner_ring.scale = Vector3(inner_growth, maxf(0.06, 1.0 - factor), inner_growth)
	_smoke.scale = Vector3.ONE * lerpf(0.2, 1.35, factor)
	_update_material(_flash_material, FIRE_YELLOW.lightened(0.12), 1.0 - factor, 5.2)
	_update_material(_outer_ring_material, FIRE_RED, 1.0 - factor, 3.8)
	_update_material(_middle_ring_material, FIRE_ORANGE, 1.0 - factor, 4.4)
	_update_material(_inner_ring_material, FIRE_YELLOW, 1.0 - factor, 5.0)
	_update_material(_smoke_material, FIRE_SMOKE, 1.0 - factor, 0.28)


func _make_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.emission_enabled = true
	_update_material(material, color, 1.0, energy)
	return material


func _update_material(
	material: StandardMaterial3D,
	color: Color,
	alpha: float,
	energy: float
) -> void:
	var resolved := color
	resolved.a *= clampf(alpha, 0.0, 1.0)
	material.albedo_color = resolved
	material.emission = color
	material.emission_energy_multiplier = maxf(0.0, energy) * clampf(alpha, 0.0, 1.0)


func debug_get_fire_wave_colors() -> Array[Color]:
	return [FIRE_RED, FIRE_ORANGE, FIRE_YELLOW]
