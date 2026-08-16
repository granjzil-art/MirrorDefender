extends SceneTree

const Level1 := preload("res://resources/levels/Level1.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[Level1WaveBalance] running")
	_test_level1_wave_contract()
	if _failures == 0:
		print("[Level1WaveBalance] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[Level1WaveBalance] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_level1_wave_contract() -> void:
	var level: LevelResource = Level1
	var expected_counts := PackedInt32Array([10, 12, 16, 21, 24, 29, 34, 36, 38, 42, 46, 50, 48, 52, 43])
	var expected_group_counts := PackedInt32Array([1, 1, 2, 2, 3, 4, 5, 6, 6, 7, 8, 8, 6, 8, 8])
	var expected_base_hp := PackedFloat32Array([
		1000.0, 1200.0, 1240.0, 1500.0, 1800.0,
		2120.0, 2480.0, 3000.0, 3400.0, 3600.0,
		3880.0, 4120.0, 4320.0, 4400.0, 4520.0,
	])
	var expected_windows := PackedFloat32Array([
		18.9, 22.0, 21.6, 22.0, 21.6,
		23.0, 25.6, 30.0, 35.0, 37.0,
		40.6, 43.0, 46.5, 48.0, 50.4,
	])
	_expect(level != null, "Level1 loads as a LevelResource")
	var validation_errors := level.validate_runtime()
	_expect(validation_errors.is_empty(), "Level1 passes runtime validation: %s" % "; ".join(validation_errors))
	_expect(level.waves.size() == 15, "Level1 owns exactly fifteen authored waves")
	_expect(is_equal_approx(level.enemy_hp_growth_factor, 1.1), "Level1 uses the 1.1 HP growth factor")
	_expect(is_equal_approx(level.enemy_hp_growth_max_multiplier, 5.0), "Level1 keeps the five-times HP cap")
	_expect(is_equal_approx(level.get_enemy_hp_multiplier(14), pow(1.1, 14.0)), "wave fifteen resolves to the expected uncapped HP multiplier")

	var total_count := 0
	var total_base_hp := 0.0
	var total_adjusted_reward := 0.0
	var total_completion_reward := 0.0
	for wave_index in range(level.waves.size()):
		var wave: WaveDefinition = level.waves[wave_index]
		_expect(wave != null, "wave %d is configured" % (wave_index + 1))
		if wave == null:
			continue
		_expect(wave.display_name == "第 %d 波" % (wave_index + 1), "wave %d has a stable display name" % (wave_index + 1))
		var expected_drop_multiplier := 0.5 if wave_index >= 10 else 1.0
		_expect(is_equal_approx(wave.enemy_drop_multiplier, expected_drop_multiplier), "wave %d uses the authored phase drop multiplier" % (wave_index + 1))
		_expect(is_equal_approx(wave.completion_reward, 40.0), "wave %d grants the standard forty-resource completion reward" % (wave_index + 1))
		total_completion_reward += wave.completion_reward
		_expect(wave.spawn_groups.size() == expected_group_counts[wave_index], "wave %d keeps its authored group count" % (wave_index + 1))
		var wave_count := 0
		var wave_base_hp := 0.0
		var wave_window := 0.0
		var minimum_delay := INF
		var route_hp := [0.0, 0.0]
		for group: SpawnGroupDefinition in wave.spawn_groups:
			_expect(group != null and group.enemy != null, "wave %d has a valid enemy in every group" % (wave_index + 1))
			if group == null or group.enemy == null:
				continue
			_expect(group.count > 0, "wave %d uses positive group counts" % (wave_index + 1))
			_expect(group.interval > 0.0, "wave %d uses positive group intervals" % (wave_index + 1))
			_expect(group.interval_jitter_ratio >= 0.0 and group.interval_jitter_ratio <= 0.150001, "wave %d explicitly limits interval jitter to fifteen percent" % (wave_index + 1))
			_expect(level.paths.has(group.path), "wave %d only references a Level1 path" % (wave_index + 1))
			_expect(level.resolve_path_spawn_point(group.path) == group.spawn_point, "wave %d keeps each path and spawn point paired" % (wave_index + 1))
			wave_count += group.count
			wave_base_hp += group.enemy.max_hp * group.count
			total_adjusted_reward += group.enemy.reward * group.count * wave.enemy_drop_multiplier
			minimum_delay = minf(minimum_delay, group.start_delay)
			wave_window = maxf(wave_window, group.start_delay + float(group.count - 1) * group.interval)
			var route_index := level.paths.find(group.path)
			if route_index >= 0 and route_index < route_hp.size():
				route_hp[route_index] += group.enemy.max_hp * group.count
		_expect(wave_count == expected_counts[wave_index], "wave %d keeps its authored enemy count" % (wave_index + 1))
		_expect(is_equal_approx(wave_base_hp, expected_base_hp[wave_index]), "wave %d keeps its authored base HP load" % (wave_index + 1))
		_expect(is_equal_approx(wave_window, expected_windows[wave_index]), "wave %d keeps its nominal spawn window" % (wave_index + 1))
		_expect(is_equal_approx(minimum_delay, 0.0), "wave %d has a zero-delay timing anchor" % (wave_index + 1))
		if wave_index >= 7:
			var larger_route_share: float = maxf(route_hp[0], route_hp[1]) / wave_base_hp
			_expect(larger_route_share <= 0.525, "wave %d keeps route HP within the intended balance band" % (wave_index + 1))
		total_count += wave_count
		total_base_hp += wave_base_hp

	_expect(total_count == 501, "the full fifteen-wave sequence contains 501 enemies")
	_expect(is_equal_approx(total_base_hp, 42580.0), "the full sequence keeps its authored base HP budget")
	_expect(is_equal_approx(total_adjusted_reward, 2590.0), "the phase multipliers produce the intended 2590 total kill reward")
	_expect(is_equal_approx(total_completion_reward, 600.0), "fifteen completed waves grant 600 total completion reward")
	_expect(_is_enemy(level.waves[2].spawn_groups[1], &"runner") and level.waves[2].spawn_groups[1].path == level.paths[0], "wave three teaches runners before opening the second route")
	_expect(level.waves[3].spawn_groups[1].path == level.paths[1], "wave four opens the second route")
	_expect(_is_enemy(level.waves[6].spawn_groups[0], &"single_shield") and is_equal_approx(level.waves[6].spawn_groups[0].interval_jitter_ratio, 0.0), "wave seven starts with the deterministic shield showcase")
	_expect(_is_enemy(level.waves[9].spawn_groups[0], &"flyer") and is_equal_approx(level.waves[9].spawn_groups[0].interval_jitter_ratio, 0.0), "wave ten starts with the deterministic flyer showcase")
	_expect(not _wave_has_enemy(level.waves[12], &"flyer"), "wave thirteen creates the intended ground-only breathing change")
	_expect(_is_enemy(level.waves[14].spawn_groups[0], &"elite_titan") and is_equal_approx(level.waves[14].spawn_groups[0].start_delay, 0.0), "wave fifteen opens with the titan")
	_expect(is_equal_approx(_earliest_non_titan_delay(level.waves[14]), 4.0), "the titan receives a four-second solo presentation window")


func _is_enemy(group: SpawnGroupDefinition, enemy_id: StringName) -> bool:
	return group != null and group.enemy != null and group.enemy.enemy_id == enemy_id


func _wave_has_enemy(wave: WaveDefinition, enemy_id: StringName) -> bool:
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if _is_enemy(group, enemy_id):
			return true
	return false


func _earliest_non_titan_delay(wave: WaveDefinition) -> float:
	var result := INF
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if not _is_enemy(group, &"elite_titan"):
			result = minf(result, group.start_delay)
	return result


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
