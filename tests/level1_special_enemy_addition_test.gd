extends SceneTree

const Level1 := preload("res://resources/levels/Level1.tres")

const EXPECTED_DOUBLE_SHIELD_COUNTS := [
	0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 3, 3,
]
const EXPECTED_ELITE_MAGE_COUNTS := [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2,
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[Level1SpecialEnemyAddition] running")
	var level: LevelResource = Level1
	_expect(level != null, "Level1 loads as a LevelResource")
	if level != null:
		_expect(level.validate_runtime().is_empty(), "Level1 passes runtime validation")
		_expect(level.waves.size() == 15, "Level1 keeps fifteen waves")
		var total_double_shields := 0
		var total_elite_mages := 0
		for wave_index in range(level.waves.size()):
			var double_shields := _enemy_count(level.waves[wave_index], &"double_shield")
			var elite_mages := _enemy_count(level.waves[wave_index], &"elite_mage")
			_expect(
				double_shields == EXPECTED_DOUBLE_SHIELD_COUNTS[wave_index],
				"wave %d keeps the authored double-shield addition" % (wave_index + 1)
			)
			_expect(
				elite_mages == EXPECTED_ELITE_MAGE_COUNTS[wave_index],
				"wave %d keeps the authored elite-mage addition" % (wave_index + 1)
			)
			total_double_shields += double_shields
			total_elite_mages += elite_mages
		_expect(total_double_shields == 18, "Level1 adds eighteen double-shield soldiers")
		_expect(total_elite_mages == 8, "Level1 adds eight elite mages")

	if _failures == 0:
		print("[Level1SpecialEnemyAddition] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[Level1SpecialEnemyAddition] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _enemy_count(wave: WaveDefinition, enemy_id: StringName) -> int:
	var result := 0
	for group: SpawnGroupDefinition in wave.spawn_groups:
		if group != null and group.enemy != null and group.enemy.enemy_id == enemy_id:
			result += group.count
	return result


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
