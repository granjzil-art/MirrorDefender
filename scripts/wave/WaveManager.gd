## Wave entry point: per-wave manual release, overlapping schedules, rewards, and victory.
class_name WaveManager
extends Node

const EnemyProjectileScript := preload("res://scripts/combat/EnemyProjectile.gd")

enum State {
	NO_WAVES,
	READY,
	ACTIVE,
	VICTORY,
	DEFEAT,
	CONFIG_ERROR,
}

@export_group("Feature")
@export var feature_enabled: bool = true

signal state_changed(state: State, current_wave: int, total_waves: int, active_enemy_count: int)
signal wave_released(wave_number: int, wave: WaveDefinition)
signal next_wave_changed(wave_number: int, wave: WaveDefinition)
signal wave_started(wave_number: int, wave: WaveDefinition)
signal wave_completed(wave_number: int)
signal enemy_spawned(unit: EnemyUnit)
signal enemy_reached_base(unit: EnemyUnit, damage: float)
signal configuration_failed(reason: String)
signal victory
signal defeat

var _path_manager: PathManager
var _combat_manager: CombatManager
var _resource_manager: ResourceManager
var _base_core: BaseCore
var _level: LevelResource
var _state: State = State.NO_WAVES
var _released_wave_count: int = 0
var _battle_elapsed: float = 0.0
var _spawn_states: Array[Dictionary] = []
var _active_units: Array[EnemyUnit] = []
var _unit_wave_indices: Dictionary = {}
var _started_wave_indices: Dictionary = {}
var _completed_wave_indices: Dictionary = {}
var _path_blocker_resolver: Callable
var _route_resolver: Callable
var _cell_world_resolver: Callable
var _tile_enter_resolver: Callable
var _tile_stay_resolver: Callable
var _navigation_blocker_resolver: Callable
var _configuration_error: String = ""

func _process(delta: float) -> void:
	if not feature_enabled or _state != State.ACTIVE:
		return
	_battle_elapsed += maxf(0.0, delta)
	_process_spawn_states()
	if _state != State.ACTIVE:
		return
	_update_wave_completions()
	_finish_battle_if_complete()
	if _state == State.ACTIVE:
		_emit_state_changed()

func configure(
	path_manager: PathManager,
	combat_manager: CombatManager,
	resource_manager: ResourceManager,
	base_core: BaseCore,
	path_blocker_resolver: Callable = Callable(),
	route_resolver: Callable = Callable(),
	cell_world_resolver: Callable = Callable(),
	tile_enter_resolver: Callable = Callable(),
	tile_stay_resolver: Callable = Callable(),
	navigation_blocker_resolver: Callable = Callable()
) -> void:
	if _base_core != null and _base_core.defeated.is_connected(_on_base_defeated):
		_base_core.defeated.disconnect(_on_base_defeated)
	_path_manager = path_manager
	_combat_manager = combat_manager
	_resource_manager = resource_manager
	_base_core = base_core
	_path_blocker_resolver = path_blocker_resolver
	_route_resolver = route_resolver
	_cell_world_resolver = cell_world_resolver
	_tile_enter_resolver = tile_enter_resolver
	_tile_stay_resolver = tile_stay_resolver
	_navigation_blocker_resolver = navigation_blocker_resolver
	if _base_core != null:
		_base_core.defeated.connect(_on_base_defeated)

func load_level(level_resource: LevelResource) -> void:
	_clear_active_units()
	_level = level_resource
	_configuration_error = ""
	_released_wave_count = 0
	_battle_elapsed = 0.0
	_spawn_states.clear()
	_started_wave_indices.clear()
	_completed_wave_indices.clear()
	if _level != null:
		var validation_errors := _level.validate_runtime()
		if not validation_errors.is_empty():
			_enter_configuration_error("波次关卡配置无效：%s" % "；".join(validation_errors))
			return
	_state = State.NO_WAVES if _level == null or _level.waves.is_empty() else State.READY
	_emit_state_changed()
	_emit_next_wave_changed()

## Compatibility entry retained for callers that start the first wave as a battle.
func start_battle() -> bool:
	if _state != State.READY or _released_wave_count != 0:
		return false
	return start_next_wave()

## Releases exactly one authored wave. Already released waves may still be active.
func start_next_wave() -> bool:
	if not can_start_next_wave():
		return false
	var preflight_error := _validate_spawn_timeline()
	if not preflight_error.is_empty():
		_enter_configuration_error(preflight_error)
		return false
	if _state == State.READY:
		_battle_elapsed = 0.0
		_started_wave_indices.clear()
		_completed_wave_indices.clear()
	var wave_index := _released_wave_count
	_build_wave_spawn_states(wave_index)
	_state = State.ACTIVE
	_process_spawn_states()
	if _state == State.CONFIG_ERROR:
		return false
	_released_wave_count += 1
	var wave: WaveDefinition = _level.waves[wave_index]
	wave_released.emit(wave_index + 1, wave)
	_emit_next_wave_changed()
	_update_wave_completions()
	_finish_battle_if_complete()
	if _state == State.ACTIVE:
		_emit_state_changed()
	return true

func get_state() -> State:
	return _state

func get_state_name() -> String:
	match _state:
		State.READY:
			return "等待释放第 1 波"
		State.ACTIVE:
			if are_all_waves_released():
				return "全部 %d 波已释放，进攻中 %.1fs" % [get_total_wave_count(), _battle_elapsed]
			return "第 %d 波已释放，等待释放第 %d 波（进攻中 %.1fs）" % [
				get_current_wave_number(),
				get_next_wave_number(),
				_battle_elapsed,
			]
		State.VICTORY:
			return "胜利"
		State.DEFEAT:
			return "失败"
		State.CONFIG_ERROR:
			return "配置错误：%s" % _configuration_error
		_:
			return "未配置波次"

## The latest manually released wave, or 0 before the first release.
func get_current_wave_number() -> int:
	return _released_wave_count

func get_total_wave_count() -> int:
	return _level.waves.size() if _level != null else 0

func get_released_wave_count() -> int:
	return _released_wave_count

## The next releasable wave number, or 0 when no authored wave remains.
func get_next_wave_number() -> int:
	if _level == null or _released_wave_count >= _level.waves.size():
		return 0
	return _released_wave_count + 1

func get_next_wave() -> WaveDefinition:
	if _level == null or _released_wave_count >= _level.waves.size():
		return null
	return _level.waves[_released_wave_count]

func can_start_next_wave() -> bool:
	return feature_enabled and _level != null and (
		_state == State.READY or _state == State.ACTIVE
	) and _released_wave_count < _level.waves.size()

func are_all_waves_released() -> bool:
	return _level != null and not _level.waves.is_empty() and _released_wave_count >= _level.waves.size()

func get_active_enemy_count() -> int:
	_cleanup_units()
	return _active_units.size()

func get_battle_elapsed() -> float:
	return _battle_elapsed

func get_configuration_error() -> String:
	return _configuration_error


## Debug-only public entry. It reuses the exact runtime spawn transaction but
## does not alter or release any authored wave.
func spawn_debug_enemy(enemy: EnemyDefinition, path: PathDefinition) -> Dictionary:
	if not feature_enabled:
		return {"success": false, "message": "WaveManager 已关闭"}
	if _state == State.VICTORY or _state == State.DEFEAT or _state == State.CONFIG_ERROR:
		return {"success": false, "message": "终局状态下不能生成敌人"}
	if _level == null:
		return {"success": false, "message": "波次系统未加载关卡"}
	if enemy == null or path == null:
		return {"success": false, "message": "敌人或路径为空"}
	if not _level.paths.has(path):
		return {"success": false, "message": "路径不属于当前关卡"}
	var group := SpawnGroupDefinition.new()
	group.enemy = enemy
	group.path = path
	group.count = 1
	var error := _spawn_group_unit(group, -1)
	if not error.is_empty():
		return {"success": false, "message": error}
	return {
		"success": true,
		"message": "已生成 %s，路径 %s" % [enemy.display_name, path.display_name],
	}

func _build_wave_spawn_states(wave_index: int) -> void:
	if _level == null or wave_index < 0 or wave_index >= _level.waves.size():
		return
	var wave: WaveDefinition = _level.waves[wave_index]
	var earliest_start_delay: float = INF
	for group: SpawnGroupDefinition in wave.spawn_groups:
		earliest_start_delay = minf(earliest_start_delay, group.start_delay)
	for group: SpawnGroupDefinition in wave.spawn_groups:
		var relative_delay: float = maxf(0.0, group.start_delay - earliest_start_delay)
		_spawn_states.append({
			"wave_index": wave_index,
			"group": group,
			"remaining": group.count,
			"next_spawn_time": _battle_elapsed + relative_delay,
		})

func _process_spawn_states() -> void:
	for state in _spawn_states:
		var remaining: int = int(state["remaining"])
		if remaining <= 0:
			continue
		var wave_index: int = int(state["wave_index"])
		var group: SpawnGroupDefinition = state["group"]
		var next_spawn_time: float = float(state["next_spawn_time"])
		while remaining > 0 and _battle_elapsed + 0.000001 >= next_spawn_time:
			var spawn_error := _spawn_group_unit(group, wave_index)
			if not spawn_error.is_empty():
				_enter_configuration_error(spawn_error)
				return
			_mark_wave_started(wave_index)
			remaining -= 1
			next_spawn_time += maxf(0.01, group.interval)
		state["remaining"] = remaining
		state["next_spawn_time"] = next_spawn_time

func _mark_wave_started(wave_index: int) -> void:
	if _started_wave_indices.has(wave_index) or _level == null:
		return
	_started_wave_indices[wave_index] = true
	var wave: WaveDefinition = _level.waves[wave_index]
	wave_started.emit(wave_index + 1, wave)

func _spawn_group_unit(group: SpawnGroupDefinition, wave_index: int) -> String:
	if group == null or group.enemy == null or group.path == null or _path_manager == null:
		return "出怪组依赖未完整配置"
	var points := _path_manager.get_world_points(group.path)
	if points.size() < 2:
		return "路径 %s 无法生成至少两个世界点" % group.path.display_name
	var unit := EnemyUnit.new()
	unit.configure_unit(
		group.enemy,
		points,
		group.path.cells,
		_level.grid_cell_size if _level != null else 1.0,
		_path_blocker_resolver,
		group.path,
		_route_resolver,
		_cell_world_resolver,
		_tile_enter_resolver,
		_tile_stay_resolver,
		_navigation_blocker_resolver
	)
	add_child(unit)
	if _combat_manager == null or not _combat_manager.register_target(unit):
		unit.queue_free()
		return "敌人 %s 无法注册到 CombatManager" % group.enemy.display_name
	unit.died.connect(_on_enemy_died)
	unit.reached_base.connect(_on_enemy_reached_base)
	unit.tree_exited.connect(_on_enemy_tree_exited.bind(unit))
	_active_units.append(unit)
	_unit_wave_indices[unit] = wave_index
	enemy_spawned.emit(unit)
	return ""

func _validate_spawn_timeline() -> String:
	if _level == null:
		return "波次系统未加载关卡"
	var validation_errors := _level.validate_runtime()
	if not validation_errors.is_empty():
		return "波次关卡配置无效：%s" % "；".join(validation_errors)
	if _path_manager == null or _combat_manager == null or _resource_manager == null or _base_core == null:
		return "波次系统依赖尚未完整注入"
	if not _path_manager.feature_enabled:
		return "PathManager 已关闭"
	if not _combat_manager.feature_enabled:
		return "CombatManager 已关闭"
	if not _resource_manager.feature_enabled:
		return "ResourceManager 已关闭"
	if not _base_core.feature_enabled:
		return "BaseCore 已关闭"
	for wave in _level.waves:
		if wave == null:
			return "关卡包含空波次"
		for group in wave.spawn_groups:
			if group == null or group.enemy == null or group.path == null:
				return "波次 %s 包含未完整配置的出怪组" % wave.display_name
			if _level.resolve_group_spawn_point(group) == null or _level.resolve_path_target_base(group.path) == null:
				return "波次 %s 的路径端点配置无效" % wave.display_name
			if not _path_manager.is_path_valid(group.path):
				return "波次 %s 引用的路径 %s 无效" % [wave.display_name, group.path.display_name]
	return ""

func _update_wave_completions() -> void:
	if _level == null:
		return
	_cleanup_units()
	for wave_index in range(_level.waves.size()):
		if not _started_wave_indices.has(wave_index) or _completed_wave_indices.has(wave_index):
			continue
		if not _all_wave_groups_spawned(wave_index) or _has_active_unit_for_wave(wave_index):
			continue
		_completed_wave_indices[wave_index] = true
		wave_completed.emit(wave_index + 1)

func _all_wave_groups_spawned(wave_index: int) -> bool:
	for state in _spawn_states:
		if int(state["wave_index"]) == wave_index and int(state["remaining"]) > 0:
			return false
	return true

func _has_active_unit_for_wave(wave_index: int) -> bool:
	for unit in _active_units:
		if int(_unit_wave_indices.get(unit, -1)) == wave_index:
			return true
	return false

func _all_groups_spawned() -> bool:
	for state in _spawn_states:
		if int(state["remaining"]) > 0:
			return false
	return true

func _finish_battle_if_complete() -> void:
	if _state != State.ACTIVE or not are_all_waves_released():
		return
	if not _all_groups_spawned() or not _active_units.is_empty():
		return
	_state = State.VICTORY
	victory.emit()
	_emit_state_changed()

func _clear_active_units() -> void:
	var units := _active_units.duplicate()
	_active_units.clear()
	_unit_wave_indices.clear()
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()
	_clear_enemy_projectiles()

func _clear_enemy_projectiles() -> void:
	for child in get_children():
		if child.get_script() == EnemyProjectileScript:
			child.queue_free()

func _cleanup_units() -> void:
	for index in range(_active_units.size() - 1, -1, -1):
		var unit := _active_units[index]
		if unit == null or not is_instance_valid(unit):
			_unit_wave_indices.erase(unit)
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
	_unit_wave_indices.erase(unit)

func _on_base_defeated() -> void:
	if _state == State.VICTORY or _state == State.DEFEAT or _state == State.CONFIG_ERROR:
		return
	_state = State.DEFEAT
	_spawn_states.clear()
	_clear_active_units()
	defeat.emit()
	_emit_state_changed()

func _enter_configuration_error(reason: String) -> void:
	_configuration_error = reason
	_state = State.CONFIG_ERROR
	_spawn_states.clear()
	_clear_active_units()
	configuration_failed.emit(reason)
	_emit_state_changed()

func _emit_state_changed() -> void:
	state_changed.emit(_state, get_current_wave_number(), get_total_wave_count(), get_active_enemy_count())

func _emit_next_wave_changed() -> void:
	next_wave_changed.emit(get_next_wave_number(), get_next_wave())
