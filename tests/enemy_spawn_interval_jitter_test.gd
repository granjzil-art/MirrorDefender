extends SceneTree

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[EnemySpawnIntervalJitter] running")
	var manager := WaveManager.new()
	manager._spawn_random.seed = 20260811
	var group := SpawnGroupDefinition.new()
	_expect(
		is_equal_approx(group.interval_jitter_ratio, 0.30),
		"wave groups default to thirty percent interval jitter"
	)
	group.interval = 2.0
	group.interval_jitter_ratio = 0.25

	var saw_shorter := false
	var saw_longer := false
	var stayed_in_range := true
	for _sample_index in range(256):
		var sampled_interval: float = manager._sample_spawn_interval(group)
		stayed_in_range = stayed_in_range and sampled_interval >= 1.5 and sampled_interval <= 2.5
		saw_shorter = saw_shorter or sampled_interval < group.interval
		saw_longer = saw_longer or sampled_interval > group.interval
	_expect(stayed_in_range, "all samples stay inside the configured symmetric jitter range")
	_expect(saw_shorter, "jitter can shorten the fixed base interval")
	_expect(saw_longer, "jitter can lengthen the fixed base interval")

	group.interval_jitter_ratio = 0.0
	_expect(
		is_equal_approx(manager._sample_spawn_interval(group), group.interval),
		"zero jitter preserves exact fixed-interval spawning"
	)
	manager.free()

	var test_spawner := RuntimeTestEnemySpawner.new()
	_expect(
		is_equal_approx(test_spawner._interval_jitter_ratio, 0.30),
		"test batches default to thirty percent interval jitter"
	)
	test_spawner._spawn_random.seed = 20260811
	test_spawner._interval = 2.0
	test_spawner._interval_jitter_ratio = 0.25
	saw_shorter = false
	saw_longer = false
	stayed_in_range = true
	for _sample_index in range(256):
		var sampled_interval: float = test_spawner._sample_spawn_interval()
		stayed_in_range = stayed_in_range and sampled_interval >= 1.5 and sampled_interval <= 2.5
		saw_shorter = saw_shorter or sampled_interval < test_spawner._interval
		saw_longer = saw_longer or sampled_interval > test_spawner._interval
	_expect(stayed_in_range, "test batches use the same bounded jitter range")
	_expect(saw_shorter and saw_longer, "test batches can schedule both shorter and longer gaps")
	test_spawner.free()

	if _failures == 0:
		print("[EnemySpawnIntervalJitter] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[EnemySpawnIntervalJitter] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
