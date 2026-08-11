## Shared deterministic geometry helpers for projectile, beam, and Stuff hits.
class_name BallisticGeometry
extends RefCounted

const MIN_SEGMENT_LENGTH := 0.000001


static func ray_sphere_entry_distance(
	start: Vector3,
	end: Vector3,
	center: Vector3,
	radius: float
) -> float:
	var segment := end - start
	var length := segment.length()
	var resolved_radius := maxf(0.0, radius)
	if length <= MIN_SEGMENT_LENGTH:
		return (
			0.0
			if start.distance_squared_to(center) <= resolved_radius * resolved_radius
			else -1.0
		)
	var direction := segment / length
	var to_center := center - start
	var projected := to_center.dot(direction)
	var closest_squared := to_center.length_squared() - projected * projected
	var radius_squared := resolved_radius * resolved_radius
	if closest_squared > radius_squared:
		return -1.0
	var half_chord := sqrt(maxf(0.0, radius_squared - closest_squared))
	var entry := projected - half_chord
	if entry < 0.0:
		entry = 0.0 if start.distance_squared_to(center) <= radius_squared else projected + half_chord
	return entry if entry >= 0.0 and entry <= length else -1.0
