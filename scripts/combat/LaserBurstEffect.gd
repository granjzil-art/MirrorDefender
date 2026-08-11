## Short-lived expanding endpoint burst used by real and copied laser towers.
class_name LaserBurstEffect
extends Node3D

@export_group("Timing")
@export_range(0.05, 2.0, 0.01, "or_greater") var duration: float = 0.42

var _elapsed: float = 0.0
var _ring: MeshInstance3D
var _flash: MeshInstance3D
var _ring_material: StandardMaterial3D
var _flash_material: StandardMaterial3D
var _color: Color = Color(0.25, 0.9, 1.0, 1.0)


func configure(world_position: Vector3, radius: float, color: Color) -> void:
	global_position = world_position + Vector3.UP * 0.04
	_color = color
	_build_visual(maxf(0.05, radius))
	_apply_factor(0.0)


func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	var factor := clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
	_apply_factor(factor)
	if factor >= 1.0:
		queue_free()


func _build_visual(radius: float) -> void:
	_ring = MeshInstance3D.new()
	_ring.name = &"ExpansionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.84
	ring_mesh.outer_radius = radius
	_ring.mesh = ring_mesh
	_ring_material = _make_material(_color, 4.0)
	_ring.material_override = _ring_material
	add_child(_ring)

	_flash = MeshInstance3D.new()
	_flash.name = &"EndpointFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = minf(radius * 0.2, 0.24)
	flash_mesh.height = flash_mesh.radius * 2.0
	_flash.mesh = flash_mesh
	_flash_material = _make_material(_color.lightened(0.18), 5.5)
	_flash.material_override = _flash_material
	add_child(_flash)


func _apply_factor(factor: float) -> void:
	var expansion := lerpf(0.08, 1.0, factor)
	if _ring != null:
		_ring.scale = Vector3(expansion, maxf(0.06, 1.0 - factor * 0.7), expansion)
	if _flash != null:
		var flash_scale := maxf(0.02, 1.0 - factor)
		_flash.scale = Vector3.ONE * flash_scale
	var alpha := 1.0 - factor
	_update_material(_ring_material, _color, alpha, 4.0)
	_update_material(_flash_material, _color.lightened(0.18), alpha, 5.5)


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
	if material == null:
		return
	var resolved := color
	resolved.a *= clampf(alpha, 0.0, 1.0)
	material.albedo_color = resolved
	material.emission = resolved
	material.emission_energy_multiplier = energy * clampf(alpha, 0.0, 1.0)
