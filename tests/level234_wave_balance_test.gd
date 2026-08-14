extends SceneTree

const Level1 := preload("res://resources/levels/Level1.tres")
const Level2 := preload("res://resources/levels/Level2.tres")
const Level3 := preload("res://resources/levels/Level3.tres")
const Level4 := preload("res://resources/levels/Level4.tres")

const ALLOWED_ENEMY_IDS := [
	&"grunt",
	&"runner",
	&"flyer",
	&"single_shield",
	&"double_shield",
	&"elite_mage",
	&"elite_titan",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[Level234WaveBalance] running")
	_test_shared_roster_contract()
	_test_level2_contract()
	_test_level3_contract()
	_test_level4_contract()
	if _failures == 0:
		print("[Level234WaveBalance] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[Level234WaveBalance] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_shared_roster_contract() -> void:
	var seen: Dictionary = {}
	for level: LevelResource in [Level1, Level2, Level3, Level4]:
		for wave: WaveDefinition in level.waves:
			for group: SpawnGroupDefinition in wave.spawn_groups:
				if group != null and group.enemy != null:
					seen[group.enemy.enemy_id] = true
	_expect(seen.size() == ALLOWED_ENEMY_IDS.size(), "Level1-Level4 collectively use exactly seven enemy types")
	for enemy_id: StringName in ALLOWED_ENEMY_IDS:
		_expect(seen.has(enemy_id), "the formal campaign roster includes %s" % enemy_id)
	_expect(not seen.has(&"archer"), "the deprecated archer is absent from all formal waves")


func _test_level2_contract() -> void:
	var level: LevelResource = Level2
	_test_level_contract(
		level,
		"Level2",
		PackedInt32Array([10, 12, 24, 20, 20, 24, 32, 38, 38, 44, 45, 58, 50, 60, 58]),
		PackedInt32Array([1, 2, 4, 3, 3, 3, 6, 8, 8, 6, 6, 10, 8, 10, 12]),
		PackedFloat32Array([1000, 960, 1920, 1560, 1560, 1760, 2640, 3080, 3560, 3600, 3740, 5160, 5000, 5120, 6880]),
		PackedFloat32Array([25.2, 21.0, 20.5, 27.5, 27.5, 26.7, 25.5, 29.5, 29.5, 30.5, 32.5, 34.5, 35.6, 34.8, 44.0]),
		533,
		47540.0,
		3009.0
	)
	_expect(level.paths.size() == 2 and level.paths[0].cells.size() == level.paths[1].cells.size(), "Level2 keeps two equal-length mirrored routes")
	_expect(_first_enemy_wave(level, &"single_shield") == 3, "Level2 wave four recalls the single-shield lesson")
	_expect(_first_enemy_wave(level, &"double_shield") == 5, "Level2 introduces double shields in wave six")
	_expect(_first_enemy_wave(level, &"elite_mage") == -1, "Level2 reserves the mage reveal for Level3")
	_expect(_is_enemy(level.waves[5].spawn_groups[0], &"double_shield"), "Level2 wave six opens on the double-shield reveal")
	_expect(is_equal_approx(level.waves[5].spawn_groups[0].interval_jitter_ratio, 0.0), "the first double-shield reveal is deterministic")
	_expect(_route_base_hp(level.waves[9], level.paths[0]) > _route_base_hp(level.waves[9], level.paths[1]), "Level2 wave ten weights the left route")
	_expect(_route_base_hp(level.waves[10], level.paths[1]) > _route_base_hp(level.waves[10], level.paths[0]), "Level2 wave eleven reverses pressure to the right route")
	for wave_index in range(11, 15):
		_expect(is_equal_approx(_route_base_hp(level.waves[wave_index], level.paths[0]), _route_base_hp(level.waves[wave_index], level.paths[1])), "Level2 wave %d restores exact mirrored HP pressure" % (wave_index + 1))
	_expect(_enemy_count(level.waves[14], &"elite_titan") == 2, "Level2 finale sends one titan down each route")


func _test_level3_contract() -> void:
	var level: LevelResource = Level3
	_test_level_contract(
		level,
		"Level3",
		PackedInt32Array([12, 14, 27, 22, 30, 34, 40, 42, 46, 37, 57, 68, 59, 73, 69]),
		PackedInt32Array([1, 2, 4, 4, 5, 6, 7, 7, 9, 7, 9, 12, 10, 12, 14]),
		PackedFloat32Array([1200, 1040, 2400, 1980, 2640, 3120, 3740, 3860, 4680, 4400, 5500, 6860, 6480, 7420, 8920]),
		PackedFloat32Array([24.2, 23.0, 31.8, 32.0, 36.1, 32.6, 35.5, 37.5, 37.5, 38.5, 40.4, 44.0, 44.4, 48.0, 60.5]),
		630,
		64240.0,
		4218.0
	)
	_expect(level.paths.size() == 2 and level.paths[0].cells.size() == 102 and level.paths[1].cells.size() == 22, "Level3 preserves its 102-cell long route and 22-cell short route")
	_expect(_first_enemy_wave(level, &"elite_mage") == 3, "Level3 introduces the elite mage in wave four")
	_expect(_is_enemy(level.waves[3].spawn_groups[0], &"elite_mage"), "Level3 wave four gives the mage the opening shot")
	_expect(is_equal_approx(level.waves[3].spawn_groups[0].interval_jitter_ratio, 0.0), "the mage reveal is deterministic")
	_expect(_is_enemy(level.waves[1].spawn_groups[1], &"runner") and level.waves[1].spawn_groups[1].path == level.paths[1], "Level3 wave two plants a delayed runner threat on the short route")
	_expect(is_equal_approx(level.waves[1].spawn_groups[1].start_delay, 12.0), "the first short-route strike waits twelve seconds")
	_expect(_is_enemy(level.waves[9].spawn_groups[0], &"elite_titan") and level.waves[9].spawn_groups[0].path == level.paths[0], "Level3 wave ten stages its midpoint titan on the long route")
	var finale_titan_delays := _enemy_start_delays(level.waves[14], &"elite_titan")
	_expect(finale_titan_delays == PackedFloat32Array([0.0, 24.0]), "Level3 finale uses a twenty-four-second long/short titan time bomb")


func _test_level4_contract() -> void:
	var level: LevelResource = Level4
	_test_level_contract(
		level,
		"Level4",
		PackedInt32Array([14, 18, 32, 32, 40, 42, 38, 49, 49, 64, 70, 74, 68, 86, 88]),
		PackedInt32Array([1, 2, 4, 4, 4, 8, 8, 8, 8, 10, 12, 12, 12, 12, 26]),
		PackedFloat32Array([1400, 1440, 2480, 3200, 3040, 3760, 3400, 4540, 4540, 5200, 6280, 7640, 9440, 9120, 12320]),
		PackedFloat32Array([27.3, 26.4, 27.2, 34.3, 33.9, 29.6, 30.0, 33.6, 41.6, 28.0, 35.2, 44.4, 50.4, 54.0, 58.0]),
		764,
		77800.0,
		4856.0
	)
	_expect(level.spawn_points.size() == 4 and level.paths.size() == 8 and level.base_points.size() == 2, "Level4 keeps four fronts, eight routes, and two bases")
	_expect(level.waves[0].spawn_groups[0].path.target_base == level.base_points[0], "Level4 wave one teaches the first base in isolation")
	_expect(level.waves[1].spawn_groups[0].path.target_base == level.base_points[1], "Level4 wave two cuts to the second base")
	_expect(_distinct_spawn_count(level.waves[2]) == 2, "Level4 wave three holds at two spawn fronts")
	_expect(_distinct_spawn_count(level.waves[3]) == 2, "Level4 wave four uses delayed reinforcements without opening extra fronts")
	_expect(
		level.waves[3].spawn_groups[2].start_delay == 12.0 and level.waves[3].spawn_groups[3].start_delay == 14.0,
		"Level4 wave four defers its second group on each active front"
	)
	_expect(_distinct_spawn_count(level.waves[4]) == 4, "Level4 wave five is the first four-front release")
	_expect(
		level.waves[4].spawn_groups[0].path == level.paths[0]
		and level.waves[4].spawn_groups[1].path == level.paths[1]
		and level.waves[4].spawn_groups[2].path == level.paths[2]
		and level.waves[4].spawn_groups[3].path == level.paths[3],
		"Level4 wave five uses all four short routes"
	)
	_expect(level.waves[5].spawn_groups[0].path == level.paths[4] and level.waves[5].spawn_groups[1].path == level.paths[6], "Level4 postpones the paired long flanks until wave six")
	_expect(_enemy_count(level.waves[12], &"elite_titan") == 2, "Level4 wave thirteen begins the two-front titan siege")
	for wave_index in range(9, 15):
		_expect(is_equal_approx(_base_load(level.waves[wave_index], level.base_points[0]), _base_load(level.waves[wave_index], level.base_points[1])), "Level4 wave %d balances authored HP between both bases" % (wave_index + 1))
	_expect(_enemy_count(level.waves[14], &"elite_titan") == 4, "Level4 finale opens with four titans")
	_expect(_enemy_start_delays(level.waves[14], &"elite_titan") == PackedFloat32Array([0.0, 2.0, 4.0, 6.0]), "the four finale titans enter in a six-second clockwise reveal")
	_expect(_distinct_spawn_count(level.waves[14]) == 4, "Level4 finale sustains all four fronts")


func _test_level_contract(
	level: LevelResource,
	label: String,
	expected_counts: PackedInt32Array,
	expected_group_counts: PackedInt32Array,
	expected_base_hp: PackedFloat32Array,
	expected_windows: PackedFloat32Array,
	expected_total_count: int,
	expected_total_base_hp: float,
	expected_total_adjusted_reward: float
) -> void:
	_expect(level != null, "%s loads as a LevelResource" % label)
	var validation_errors := level.validate_runtime()
	_expect(validation_errors.is_empty(), "%s passes runtime validation: %s" % [label, "; ".join(validation_errors)])
	_expect(level.waves.size() == 15, "%s owns exactly fifteen authored waves" % label)
	_expect(is_equal_approx(level.enemy_hp_growth_factor, 1.1), "%s uses the campaign 1.1 HP factor" % label)
	_expect(is_equal_approx(level.enemy_hp_growth_max_multiplier, 5.0), "%s uses the campaign five-times HP cap" % label)
	var total_count := 0
	var total_base_hp := 0.0
	var total_adjusted_reward := 0.0
	for wave_index in range(level.waves.size()):
		var wave: WaveDefinition = level.waves[wave_index]
		_expect(wave != null, "%s wave %d is configured" % [label, wave_index + 1])
		if wave == null:
			continue
		_expect(wave.display_name == "第 %d 波" % (wave_index + 1), "%s wave %d has a stable display name" % [label, wave_index + 1])
		var expected_drop_multiplier := 0.5 if wave_index >= 10 else 1.0
		_expect(is_equal_approx(wave.enemy_drop_multiplier, expected_drop_multiplier), "%s wave %d uses the authored phase drop multiplier" % [label, wave_index + 1])
		_expect(wave.spawn_groups.size() == expected_group_counts[wave_index], "%s wave %d keeps its authored group count" % [label, wave_index + 1])
		var wave_count := 0
		var wave_base_hp := 0.0
		var wave_window := 0.0
		var minimum_delay := INF
		for group: SpawnGroupDefinition in wave.spawn_groups:
			_expect(group != null and group.enemy != null, "%s wave %d configures every enemy group" % [label, wave_index + 1])
			if group == null or group.enemy == null:
				continue
			_expect(ALLOWED_ENEMY_IDS.has(group.enemy.enemy_id), "%s wave %d only uses the seven-enemy campaign roster" % [label, wave_index + 1])
			_expect(group.count > 0 and group.interval > 0.0, "%s wave %d uses positive counts and intervals" % [label, wave_index + 1])
			_expect(group.interval_jitter_ratio >= 0.0 and group.interval_jitter_ratio <= 0.100001, "%s wave %d explicitly limits timing jitter to ten percent" % [label, wave_index + 1])
			_expect(level.paths.has(group.path), "%s wave %d only references an owned route" % [label, wave_index + 1])
			_expect(level.resolve_path_spawn_point(group.path) == group.spawn_point, "%s wave %d keeps route and spawn paired" % [label, wave_index + 1])
			wave_count += group.count
			wave_base_hp += group.enemy.max_hp * group.count
			total_adjusted_reward += group.enemy.reward * group.count * wave.enemy_drop_multiplier
			minimum_delay = minf(minimum_delay, group.start_delay)
			wave_window = maxf(wave_window, group.start_delay + float(group.count - 1) * group.interval)
		_expect(wave_count == expected_counts[wave_index], "%s wave %d keeps its authored enemy count" % [label, wave_index + 1])
		_expect(is_equal_approx(wave_base_hp, expected_base_hp[wave_index]), "%s wave %d keeps its authored base HP load" % [label, wave_index + 1])
		_expect(is_equal_approx(wave_window, expected_windows[wave_index]), "%s wave %d keeps its nominal spawn window" % [label, wave_index + 1])
		_expect(is_equal_approx(minimum_delay, 0.0), "%s wave %d has a zero-delay timing anchor" % [label, wave_index + 1])
		total_count += wave_count
		total_base_hp += wave_base_hp
	_expect(total_count == expected_total_count, "%s keeps its total authored enemy count" % label)
	_expect(is_equal_approx(total_base_hp, expected_total_base_hp), "%s keeps its total authored base HP budget" % label)
	_expect(is_equal_approx(total_adjusted_reward, expected_total_adjusted_reward), "%s keeps its intended phase-adjusted total kill reward" % label)


func _first_enemy_wave(level: LevelResource, enemy_id: StringName) -> int:
	for wave_index in range(level.waves.size()):
		if _enemy_count(level.waves[wave_index], enemy_id) > 0:
			return wave_index
	return -1


func _enemy_count(wave: WaveDefinition, enemy_id: StringName) -> int:
	var result := 0
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if _is_enemy(group, enemy_id):
			result += group.count
	return result


func _is_enemy(group: SpawnGroupDefinition, enemy_id: StringName) -> bool:
	return group != null and group.enemy != null and group.enemy.enemy_id == enemy_id


func _route_base_hp(wave: WaveDefinition, path: PathDefinition) -> float:
	var result := 0.0
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if group.path == path:
			result += group.enemy.max_hp * group.count
	return result


func _base_load(wave: WaveDefinition, base_point: BasePointDefinition) -> float:
	var result := 0.0
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if group.path.target_base == base_point:
			result += group.enemy.max_hp * group.count
	return result


func _enemy_start_delays(wave: WaveDefinition, enemy_id: StringName) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if _is_enemy(group, enemy_id):
			result.append(group.start_delay)
	return result


func _distinct_spawn_count(wave: WaveDefinition) -> int:
	var result: Dictionary = {}
	for group: SpawnGroupDefinition in wave.spawn_groups:
		result[group.spawn_point] = true
	return result.size()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
