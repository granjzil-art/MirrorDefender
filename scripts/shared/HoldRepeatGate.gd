## HoldRepeatGate —— 与帧率无关的“按住后重复”节拍器。
##
## 首次动作由调用方立即执行；本类只负责初始等待后的连续重复次数。
## 不直接读取 Input，也不持有具体玩法对象，便于建筑旋转及未来 UI 共用。
class_name HoldRepeatGate
extends RefCounted

var _initial_delay: float = 0.3
var _repeat_interval: float = 0.08
var _max_repeats_per_tick: int = 4
var _elapsed: float = 0.0
var _waiting_for_initial_delay: bool = true
var _active: bool = false


func configure(initial_delay: float, repeat_interval: float, max_repeats_per_tick: int = 4) -> void:
	_initial_delay = maxf(0.0, initial_delay)
	_repeat_interval = maxf(0.001, repeat_interval)
	_max_repeats_per_tick = maxi(1, max_repeats_per_tick)
	return


func press() -> void:
	_elapsed = 0.0
	_waiting_for_initial_delay = true
	_active = true
	return


func release() -> void:
	_elapsed = 0.0
	_waiting_for_initial_delay = true
	_active = false
	return


func is_active() -> bool:
	return _active


func advance(unscaled_delta: float) -> int:
	if not _active:
		return 0
	_elapsed += maxf(0.0, unscaled_delta)
	var repeat_count := 0
	var threshold := _initial_delay if _waiting_for_initial_delay else _repeat_interval
	while _elapsed >= threshold and repeat_count < _max_repeats_per_tick:
		_elapsed -= threshold
		repeat_count += 1
		_waiting_for_initial_delay = false
		threshold = _repeat_interval
	# A stalled frame must not produce an unbounded rotation burst later.
	if repeat_count >= _max_repeats_per_tick and _elapsed >= _repeat_interval:
		_elapsed = fmod(_elapsed, _repeat_interval)
	return repeat_count
