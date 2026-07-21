## Runtime dispatcher for data-driven tile effects. It only relies on the
## target method contract and never owns enemy lifecycle or movement.
class_name TileEffectSystem
extends Node

const VoidCapacityRuntimeScript := preload("res://scripts/tile/VoidCapacityRuntime.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

signal effect_visual_state_changed(source_cell: Vector3i, fill_ratio: float)

var _tile_manager: TileManager
var _effect_overlay_resolver: Callable
var _effect_overlay_binding_resolver: Callable
var _target_locations: Dictionary = {}
var _void_states: Dictionary = {}

func _process(delta: float) -> void:
	if not feature_enabled or not is_finite(delta) or delta <= 0.0:
		return
	var due_checks: Dictionary = {}
	for raw_key in _void_states.keys():
		var key: String = raw_key
		var state: VoidCapacityRuntime = _void_states[key]
		due_checks[key] = state.advance(delta)
	var candidates := _collect_void_candidates()
	for raw_key in due_checks.keys():
		var key: String = raw_key
		var checks: int = int(due_checks[key])
		if checks <= 0 or not candidates.has(key):
			continue
		var state: VoidCapacityRuntime = _void_states.get(key)
		var keyed_candidates: Dictionary = candidates[key]
		var candidate_checks := mini(checks, keyed_candidates.size())
		for _check_index in range(candidate_checks):
			if not state.can_swallow() or keyed_candidates.is_empty():
				break
			var target := _select_highest_health_target(keyed_candidates)
			if target == null:
				break
			keyed_candidates.erase(target.get_instance_id())
			if _defeat_target(target, state.effect.reward_multiplier):
				state.record_swallow()
				_target_locations.erase(target.get_instance_id())

func configure(tile_manager: TileManager) -> void:
	if _tile_manager != null and _tile_manager.level_loaded.is_connected(_on_level_loaded):
		_tile_manager.level_loaded.disconnect(_on_level_loaded)
	_tile_manager = tile_manager
	_target_locations.clear()
	_clear_void_states()
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)
		_rebuild_void_states()

func set_effect_overlay_resolver(value: Callable) -> void:
	_effect_overlay_resolver = value

func set_effect_overlay_binding_resolver(value: Callable) -> void:
	_effect_overlay_binding_resolver = value

func apply_enter(target: Node, cell: Vector3i) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target):
		return
	_track_target(target, cell)
	for binding in _get_effect_bindings(cell):
		var effect: TileEffect = binding["effect"]
		if not effect.uses_timed_runtime() and effect.affects_target(target):
			effect.apply_enter(target)

func apply_stay(target: Node, cell: Vector3i, duration: float) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target) or duration <= 0.0:
		return
	_track_target(target, cell)
	for binding in _get_effect_bindings(cell):
		var effect: TileEffect = binding["effect"]
		if not effect.uses_timed_runtime() and effect.affects_target(target):
			effect.apply_stay(target, duration)

func get_void_current_fill(source_cell: Vector3i) -> int:
	var state := _get_void_state_for_source_cell(source_cell)
	return state.current_fill if state != null else 0

func get_void_fill_ratio(source_cell: Vector3i) -> float:
	var state := _get_void_state_for_source_cell(source_cell)
	return state.get_fill_ratio() if state != null else 0.0

func _get_effect(cell: Vector3i) -> TileEffect:
	if _tile_manager == null:
		return null
	var tile := _tile_manager.get_tile(cell)
	return tile.get_effect() if tile != null else null

func _get_effect_bindings(cell: Vector3i) -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	var base_effect := _get_effect(cell)
	if base_effect != null:
		bindings.append(_make_effect_binding(base_effect, cell))
	if _effect_overlay_binding_resolver.is_valid():
		var projected_bindings: Variant = _effect_overlay_binding_resolver.call(cell)
		if projected_bindings is Array:
			for raw_binding in projected_bindings:
				if raw_binding is Dictionary and raw_binding.get("effect") is TileEffect:
					bindings.append(raw_binding)
	elif _effect_overlay_resolver.is_valid():
		var projected: Variant = _effect_overlay_resolver.call(cell)
		if projected is Array:
			for raw_effect in projected:
				if raw_effect is TileEffect:
					bindings.append(_make_effect_binding(raw_effect, cell))
	return bindings

func _make_effect_binding(effect: TileEffect, source_cell: Vector3i) -> Dictionary:
	return {
		"effect": effect,
		"source_cell": source_cell,
		"state_key": effect.get_runtime_state_key(source_cell),
	}

func _track_target(target: Node, cell: Vector3i) -> void:
	_target_locations[target.get_instance_id()] = {
		"reference": weakref(target),
		"cell": cell,
	}

func _collect_void_candidates() -> Dictionary:
	var candidates: Dictionary = {}
	for raw_target_id in _target_locations.keys():
		var target_id: int = int(raw_target_id)
		var record: Dictionary = _target_locations[target_id]
		var reference: WeakRef = record["reference"]
		var target := reference.get_ref() as Node
		if not _is_target_available(target):
			_target_locations.erase(target_id)
			continue
		var cell: Vector3i = record["cell"]
		for binding in _get_effect_bindings(cell):
			var effect: TileEffect = binding["effect"]
			if not effect.uses_timed_runtime() or not effect.affects_target(target):
				continue
			var key: String = str(binding["state_key"])
			var source_cell: Vector3i = binding.get("source_cell", cell)
			var state := _ensure_void_state(key, source_cell, effect as VoidTileEffect)
			if state == null:
				continue
			if not candidates.has(key):
				candidates[key] = {}
			var keyed_candidates: Dictionary = candidates[key]
			keyed_candidates[target_id] = target
	return candidates

func _select_highest_health_target(candidates: Dictionary) -> Node:
	var selected: Node
	var selected_hp := -INF
	var selected_id := 9223372036854775807
	for raw_target_id in candidates.keys():
		var target_id: int = int(raw_target_id)
		var target: Node = candidates[target_id]
		if not _is_target_available(target):
			continue
		var hp := _get_target_health(target)
		if hp > selected_hp or (is_equal_approx(hp, selected_hp) and target_id < selected_id):
			selected = target
			selected_hp = hp
			selected_id = target_id
	return selected

func _get_target_health(target: Node) -> float:
	if target.has_method("get_current_hp"):
		var method_health: float = target.call("get_current_hp")
		return method_health if is_finite(method_health) else 0.0
	return 0.0

func _defeat_target(target: Node, reward_multiplier: float) -> bool:
	return _is_target_available(target) and target.has_method("defeat") and bool(target.call("defeat", reward_multiplier))

func _is_target_available(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	return not target.has_method("is_alive") or bool(target.call("is_alive"))

func _rebuild_void_states() -> void:
	if _tile_manager == null:
		return
	for tile in _tile_manager.get_tiles():
		var effect := tile.get_effect()
		if effect is VoidTileEffect:
			_ensure_void_state(effect.get_runtime_state_key(tile.cell), tile.cell, effect)

func _ensure_void_state(key: String, source_cell: Vector3i, effect: VoidTileEffect) -> VoidCapacityRuntime:
	if effect == null or key.is_empty():
		return null
	if _void_states.has(key):
		return _void_states[key]
	var state: VoidCapacityRuntime = VoidCapacityRuntimeScript.new()
	state.configure(key, source_cell, effect)
	state.fill_changed.connect(_on_void_fill_changed)
	_void_states[key] = state
	return state

func _get_void_state_for_source_cell(source_cell: Vector3i) -> VoidCapacityRuntime:
	var effect := _get_effect(source_cell)
	if not effect is VoidTileEffect:
		return null
	return _ensure_void_state(effect.get_runtime_state_key(source_cell), source_cell, effect)

func _clear_void_states() -> void:
	for raw_state in _void_states.values():
		var state: VoidCapacityRuntime = raw_state
		if state.fill_changed.is_connected(_on_void_fill_changed):
			state.fill_changed.disconnect(_on_void_fill_changed)
	_void_states.clear()

func _on_level_loaded(_level_resource: LevelResource) -> void:
	_target_locations.clear()
	_clear_void_states()
	_rebuild_void_states()

func _on_void_fill_changed(state: VoidCapacityRuntime, _current: int, _maximum: int) -> void:
	effect_visual_state_changed.emit(state.source_cell, state.get_fill_ratio())
