## Five-second real-time red ground ripple shown after a tower reward is confirmed.
class_name TowerArrivalPulse
extends Node3D

@export_range(0.1, 30.0, 0.1, "or_greater") var duration_seconds: float = 5.0
@export_range(0.1, 5.0, 0.1, "or_greater") var outer_radius: float = 1.45

const RIPPLE_PERIOD_SECONDS := 1.25
const RIPPLE_COLOR := Color(1.0, 0.035, 0.045, 1.0)

var _started_msec: int = 0
var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position.y = 0.075
	_started_msec = Time.get_ticks_msec()
	_build_ring(0.0)
	_build_ring(0.5)
	_update_ripples(0.0)


func _process(_delta: float) -> void:
	var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	if elapsed >= duration_seconds:
		queue_free()
		return
	_update_ripples(elapsed)


func get_ring_count() -> int:
	return _rings.size()


func _build_ring(phase: float) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "ArrivalRipple%d" % (_rings.size() + 1)
	ring.set_meta(&"phase", phase)
	var mesh := TorusMesh.new()
	mesh.inner_radius = outer_radius * 0.83
	mesh.outer_radius = outer_radius
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.emission_enabled = true
	ring.material_override = material
	add_child(ring)
	_rings.append(ring)
	_materials.append(material)


func _update_ripples(elapsed: float) -> void:
	for index in range(_rings.size()):
		var ring := _rings[index]
		var phase := float(ring.get_meta(&"phase", 0.0))
		var cycle := fposmod(elapsed / RIPPLE_PERIOD_SECONDS + phase, 1.0)
		var expansion := lerpf(0.28, 1.0, cycle)
		var blink := 0.72 + 0.28 * sin(elapsed * TAU * 3.0)
		var alpha := sin(cycle * PI) * blink
		ring.scale = Vector3(expansion, maxf(0.08, 1.0 - cycle * 0.7), expansion)
		var color := RIPPLE_COLOR
		color.a = clampf(alpha, 0.0, 1.0)
		var material := _materials[index]
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 4.5 * color.a
