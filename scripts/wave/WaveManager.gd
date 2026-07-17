## M4 wave entry point: timed spawning, base damage, enemy rewards, and victory state.
class_name WaveManager
extends Node

enum State {
	NO_WAVES,
	READY,
	ACTIVE,
	PREPARING,
	VICTORY,
	DEFEAT,
}

@export_group("Feature")
@export var feature_enabled: bool = true

signal state_changed(state: State, current_wave: int, total_waves: int, active_enemy_count: int)
signal wave_started(wave_number: int, wave: WaveDefinition)
signal wave_completed(wave_number: int)
signal enemy_spawned(unit: EnemyUnit)
signal enemy_reached_base(unit: EnemyUnit, damage: float)
signal victory
signal defeat

var _path_manager: PathManager
var _combat_manager: CombatManager
var _resource_manager: ResourceManager
var _base_core: BaseCore
var _level: LevelResource
var _state: State = State.NO_WAVES
var _current_wave_index: int = -1
var _preparation_remaining: float = 0.0
var _spawn_states: Array[Dictionary] = []
var _active_units: Array[EnemyUnit] = []

func _process(delta: float) -> void:
	if not feature_enabled:
		return
	if _state == State.PREPARING:
		_preparation_remaining = maxf(0.0, _preparation_remaining - delta)
		if _preparation_remaining <= 0.0:
			_state = State.READY
			_emit_state_changed()
			if _level != null and _level.waves_auto_start:
				start_next_wave()
	elif _state == State.ACTIVE:
		_process_spawn_states(delta)
		if _all_groups_spawned() and _active_units.is_empty():
			_complete_wave()

func configure(
	path_manager: PathManager,
	combat_manager: CombatManager,
	resource_manager: ResourceManager,
	base_core: BaseCore
) -> void:
	if _base_core != null and _base_core.defeated.is_connected(_on_base_defeated):
		_base_core.defeated.disconnect(_on_base_defeated)
	_path_manager = path_manager
	_combat_manager = combat_manager
	_resource_manager = resource_manager
	_base_core = base_core
	if _base_core != null:
		_base_core.defeated.connect(_on_base_defeated)

func load_level(level_resource: LevelResource) -> void:
	_clear_active_units()
	_level = level_resource
	_current_wave_index = -1
	_spawn_states.clear()
	_preparation_remaining = 0.0
	_state = State.NO_WAVES if _level == null or _level.waves.is_empty() else State.READY
	_emit_state_changed()

func start_next_wave() -> bool:
	if not feature_enabled or _state != State.READY or _level == null:
		return false
	if _current_wave_index + 1 >= _level.waves.size():
		_state = State.VICTORY
		victory.emit()
		_emit_state_changed()
		return false
	_current_wave_index += 1
	var wave := _level.waves[_current_wave_index]
	if wave == null:
		_complete_wave()
		return false
	_spawn_states.clear()
	for group in wave.spawn_groups:
		if group == null:
			continue
		_spawn_states.append({
			"group": group,
			"remaining": group.count,
			"delay": group.start_delay,
			"cooldown": 0.0,
		})
	_state = State.ACTIVE
	wave_started.emit(_current_wave_index + 1, wave)
	_emit_state_changed()
	return true

func get_state() -> State:
	return _state

func get_state_name() -> String:
	match _state:
		State.READY:
			return "待开始"
		State.ACTIVE:
			return "进攻中"
		State.PREPARING:
			return "准备中 %.1fs" % _preparation_remaining
		State.VICTORY:
			return "胜利"
		State.DEFEAT:
			return "失败"
		_:
			return "未配置波次"

func get_current_wave_number() -> int:
	return _current_wave_index + 1 if _current_wave_index >= 0 else 0

func get_total_wave_count() -> int:
	return _level.waves.size() if _level != null else 0

func get_active_enemy_count() -> int:
	_cleanup_units()
	return _active_units.size()

func _process_spawn_states(delta: float) -> void:
	for state in _spawn_states:
		var remaining: int = int(state["remaining"])
		if remaining <= 0:
			continue
		var delay: float = float(state["delay"])
		if delay > 0.0:
			delay -= delta
			state["delay"] = delay
			if delay > 0.0:
				continue
		var cooldown: float = float(state["cooldown"]) - delta
		var group: SpawnGroupDefinition = state["group"]
		while cooldown <= 0.0 and remaining > 0:
			_spawn_group_unit(group)
			remaining -= 1
			cooldown += maxf(0.01, group.interval)
		state["remaining"] = remaining
		state["cooldown"] = cooldown
	_emit_state_changed()

func _spawn_group_unit(group: SpawnGroupDefinition) -> void:
	if group == null or group.enemy == null or group.path == null or _path_manager == null:
		return
	var points := _path_manager.get_world_points(group.path)
	if points.size() < 2:
		return
	var unit := EnemyUnit.new()
	unit.configure_unit(group.enemy, points)
	add_child(unit)
	unit.died.connect(_on_enemy_died)
	unit.reached_base.connect(_on_enemy_reached_base)
	unit.tree_exited.connect(_on_enemy_tree_exited.bind(unit))
	_active_units.append(unit)
	if _combat_manager != null:
		_combat_manager.register_target(unit)
	enemy_spawned.emit(unit)

func _all_groups_spawned() -> bool:
	for state in _spawn_states:
		if int(state["remaining"]) > 0:
			return false
	return true

func _complete_wave() -> void:
	if _state != State.ACTIVE:
		return
	wave_completed.emit(_current_wave_index + 1)
	if _level != null and _current_wave_index + 1 >= _level.waves.size():
		_state = State.VICTORY
		victory.emit()
	else:
		_state = State.PREPARING
		_preparation_remaining = _level.wave_prep_time if _level != null else 0.0
	_emit_state_changed()

func _clear_active_units() -> void:
	var units := _active_units.duplicate()
	_active_units.clear()
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()

func _cleanup_units() -> void:
	for index in range(_active_units.size() - 1, -1, -1):
		var unit := _active_units[index]
		if unit == null or not is_instance_valid(unit):
			_active_units.remove_at(index)

func _on_enemy_died(target: CombatTarget, reward_amount: float) -> void:
	if target is EnemyUnit and _resource_manager != null:
		_resource_manager.grant_enemy_drop(reward_amount)

func _on_enemy_reached_base(unit: EnemyUnit, damage: float) -> void:
	if _base_core != null:
		_base_core.take_damage(damage)
	enemy_reached_base.emit(unit, damage)

func _on_enemy_tree_exited(unit: EnemyUnit) -> void:
	_active_units.erase(unit)

func _on_base_defeated() -> void:
	if _state == State.DEFEAT:
		return
	_state = State.DEFEAT
	_spawn_states.clear()
	_clear_active_units()
	defeat.emit()
	_emit_state_changed()

func _emit_state_changed() -> void:
	state_changed.emit(_state, get_current_wave_number(), get_total_wave_count(), get_active_enemy_count())
