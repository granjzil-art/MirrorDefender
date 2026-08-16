extends SceneTree

const LEVELS := [
	preload("res://resources/levels/Level1.tres"),
	preload("res://resources/levels/Level2.tres"),
	preload("res://resources/levels/Level3.tres"),
	preload("res://resources/levels/Level4.tres"),
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[WaveCompletionReward] running")
	_expect(
		is_equal_approx(WaveDefinition.new().completion_reward, 40.0),
		"new waves default to a forty-resource completion reward"
	)
	for level_index in range(LEVELS.size()):
		var level: LevelResource = LEVELS[level_index]
		var label := "Level%d" % (level_index + 1)
		_expect(level.waves.size() == 15, "%s keeps fifteen authored waves" % label)
		var total_completion_reward := 0.0
		for wave_index in range(level.waves.size()):
			var wave: WaveDefinition = level.waves[wave_index]
			_expect(
				wave != null and is_equal_approx(wave.completion_reward, 40.0),
				"%s wave %d grants forty resources on completion" % [label, wave_index + 1]
			)
			if wave != null:
				total_completion_reward += wave.completion_reward
		_expect(
			is_equal_approx(total_completion_reward, 600.0),
			"%s grants 600 total completion reward" % label
		)
	if _failures == 0:
		print("[WaveCompletionReward] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[WaveCompletionReward] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
