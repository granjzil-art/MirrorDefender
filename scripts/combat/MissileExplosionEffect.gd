## Programmatic flash, pressure ring and smoke shell for a missile explosion.
class_name MissileExplosionEffect
extends Node3D

var _duration: float = 0.48
var _elapsed: float = 0.0
var _radius: float = 1.0
var _color: Color = Color(1.0, 0.35, 0.04, 1.0)
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _smoke: MeshInstance3D
var _flash_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _smoke_material: StandardMaterial3D


func configure(
	world_position: Vector3,
	radius: float,
	color: Color,
	duration: float
) -> void:
	global_position = world_position
	_radius = maxf(0.05, radius)
	_color = color
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
	_flash_material = _make_material(_color.lightened(0.32), 6.0)
	_flash.material_override = _flash_material
	add_child(_flash)

	_ring = MeshInstance3D.new()
	_ring.name = &"MissileExplosionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = _radius * 0.78
	ring_mesh.outer_radius = _radius
	_ring.mesh = ring_mesh
	_ring_material = _make_material(_color, 4.2)
	_ring.material_override = _ring_material
	add_child(_ring)

	_smoke = MeshInstance3D.new()
	_smoke.name = &"MissileExplosionSmoke"
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = _radius * 0.46
	smoke_mesh.height = smoke_mesh.radius * 1.5
	_smoke.mesh = smoke_mesh
	_smoke_material = _make_material(Color(0.18, 0.12, 0.10, 0.58), 0.35)
	_smoke.material_override = _smoke_material
	add_child(_smoke)


func _apply_factor(factor: float) -> void:
	var flash_growth := lerpf(0.18, 1.3, minf(1.0, factor * 2.0))
	_flash.scale = Vector3.ONE * flash_growth * maxf(0.01, 1.0 - factor)
	var ring_growth := lerpf(0.08, 1.0, factor)
	_ring.scale = Vector3(ring_growth, maxf(0.04, 1.0 - factor), ring_growth)
	_smoke.scale = Vector3.ONE * lerpf(0.2, 1.35, factor)
	_update_material(_flash_material, _color.lightened(0.32), 1.0 - factor, 6.0)
	_update_material(_ring_material, _color, 1.0 - factor, 4.2)
	_update_material(_smoke_material, Color(0.18, 0.12, 0.10, 0.58), 1.0 - factor, 0.35)


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
