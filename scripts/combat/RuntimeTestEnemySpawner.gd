## Timed test-enemy batches. WaveManager owns the combat unit transaction, but
## these units never enter authored wave scheduling or completion bookkeeping.
class_name RuntimeTestEnemySpawner
extends Node

const MIN_SPAWN_INTERVAL: float = 0.01
const DEFAULT_INTERVAL_JITTER_RATIO: float = 0.30

signal state_changed(running: bool, remaining: int, living: int, message: String)

var _wave_manager: WaveManager
var _enemy: EnemyDefinition
var _path: PathDefinition
var _remaining: int = 0
var _interval: float = 1.0
var _interval_jitter_ratio: float = DEFAULT_INTERVAL_JITTER_RATIO
var _next_spawn_interval: float = 1.0
var _elapsed: float = 0.0
var _running: bool = false
var _spawn_random := RandomNumberGenerator.new()


func _init() -> void:
	_spawn_random.randomize()


func configure(wave_manager: WaveManager) -> void:
	_wave_manager = wave_manager


func start_batch(
	enemy: EnemyDefinition,
	path: PathDefinition,
	count: int,
	interval: float,
	interval_jitter_ratio: float = DEFAULT_INTERVAL_JITTER_RATIO
) -> Dictionary:
	if _wave_manager == null:
		return _result(false, "测试敌人生成器尚未配置")
	if enemy == null or path == null:
		return _result(false, "请选择敌人类型和路径")
	if count <= 0:
		return _result(false, "生成数量必须大于 0")
	_enemy = enemy
	_path = path
	_remaining = count
	_interval = maxf(MIN_SPAWN_INTERVAL, interval)
	_interval_jitter_ratio = clampf(interval_jitter_ratio, 0.0, 0.95)
	_next_spawn_interval = _interval
	_elapsed = 0.0
	_running = true
	var first := _spawn_next()
	if not bool(first.get("success", false)):
		stop()
		return first
	if _running:
		_next_spawn_interval = _sample_spawn_interval()
		_emit_state("测试批次已开始")
	return _result(true, "测试批次已开始")


func stop() -> void:
	_running = false
	_remaining = 0
	_elapsed = 0.0
	_emit_state("已停止后续生成")


func clear_test_enemies() -> int:
	_running = false
	_remaining = 0
	_elapsed = 0.0
	var removed := _wave_manager.clear_test_enemies() if _wave_manager != null else 0
	_emit_state("已清理 %d 个测试敌人" % removed)
	return removed


func is_running() -> bool:
	return _running


func get_remaining_count() -> int:
	return _remaining


func get_living_count() -> int:
	return _wave_manager.get_test_enemy_count() if _wave_manager != null else 0


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += maxf(0.0, delta)
	while _running and _remaining > 0 and _elapsed + 0.000001 >= _next_spawn_interval:
		_elapsed -= _next_spawn_interval
		var result := _spawn_next()
		if not bool(result.get("success", false)):
			_running = false
			_remaining = 0
			_emit_state(String(result.get("message", "生成测试敌人失败")))
			return
		if _running:
			_next_spawn_interval = _sample_spawn_interval()


func _sample_spawn_interval() -> float:
	return maxf(
		MIN_SPAWN_INTERVAL,
		_interval * (1.0 + _spawn_random.randf_range(-_interval_jitter_ratio, _interval_jitter_ratio))
	)


func _spawn_next() -> Dictionary:
	if _remaining <= 0:
		_running = false
		_emit_state("测试批次生成完成")
		return _result(true, "测试批次生成完成")
	var result := _wave_manager.spawn_test_enemy(_enemy, _path)
	if not bool(result.get("success", false)):
		return result
	_remaining -= 1
	if _remaining <= 0:
		_running = false
		_emit_state("测试批次生成完成")
	return result


func _emit_state(message: String) -> void:
	var living := _wave_manager.get_test_enemy_count() if _wave_manager != null else 0
	state_changed.emit(_running, _remaining, living, message)


func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message}
