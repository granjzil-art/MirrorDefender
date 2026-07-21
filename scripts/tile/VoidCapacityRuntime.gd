## Stateful fill, recovery, and periodic-consumption clock shared by one source
## void tile and all of its direct/recursive mirror projections.
class_name VoidCapacityRuntime
extends RefCounted

signal fill_changed(runtime: VoidCapacityRuntime, current: int, maximum: int)

var state_key: String = ""
var source_cell: Vector3i = Vector3i.ZERO
var effect: VoidTileEffect
var current_fill: int = 0

var _recovery_elapsed: float = 0.0
var _swallow_elapsed: float = 0.0

func configure(p_state_key: String, p_source_cell: Vector3i, p_effect: VoidTileEffect) -> void:
	state_key = p_state_key
	source_cell = p_source_cell
	effect = p_effect
	current_fill = 0
	_recovery_elapsed = 0.0
	_swallow_elapsed = 0.0

## Advances both clocks and returns 1 when one swallow check became due. Missed
## checks are not replayed in a burst because one update must never swallow a
## crowd at once after a long frame.
func advance(delta: float) -> int:
	if effect == null or not is_finite(delta) or delta <= 0.0:
		return 0
	_sync_capacity()
	_advance_recovery(delta)
	var interval := maxf(0.01, effect.swallow_interval)
	_swallow_elapsed += delta
	if _swallow_elapsed < interval:
		return 0
	_swallow_elapsed = fmod(_swallow_elapsed, interval)
	return 1

func can_swallow() -> bool:
	return effect != null and current_fill < maxi(1, effect.max_capacity)

func record_swallow() -> bool:
	if not can_swallow():
		return false
	var was_empty := current_fill == 0
	current_fill += 1
	if was_empty:
		_recovery_elapsed = 0.0
	fill_changed.emit(self, current_fill, maxi(1, effect.max_capacity))
	return true

func get_fill_ratio() -> float:
	if effect == null:
		return 0.0
	return clampf(float(current_fill) / float(maxi(1, effect.max_capacity)), 0.0, 1.0)

func _advance_recovery(delta: float) -> void:
	if current_fill <= 0:
		_recovery_elapsed = 0.0
		return
	var seconds_per_point := maxf(0.01, effect.recovery_seconds_per_point)
	_recovery_elapsed += delta
	var recovered := mini(current_fill, floori(_recovery_elapsed / seconds_per_point))
	if recovered <= 0:
		return
	current_fill -= recovered
	_recovery_elapsed -= float(recovered) * seconds_per_point
	if current_fill == 0:
		_recovery_elapsed = 0.0
	fill_changed.emit(self, current_fill, maxi(1, effect.max_capacity))

func _sync_capacity() -> void:
	var maximum := maxi(1, effect.max_capacity)
	if current_fill <= maximum:
		return
	current_fill = maximum
	fill_changed.emit(self, current_fill, maximum)
