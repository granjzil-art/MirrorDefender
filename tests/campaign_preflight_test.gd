extends SceneTree

const FORMAL_LEVEL_PATHS: Array[String] = [
	"res://resources/levels/Level1.tres",
	"res://resources/levels/Level2.tres",
	"res://resources/levels/Level3.tres",
	"res://resources/levels/Level4.tres",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[CampaignPreflight] running")
	for level_path in FORMAL_LEVEL_PATHS:
		_test_formal_level(level_path)
	if _failures == 0:
		print("[CampaignPreflight] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[CampaignPreflight] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_formal_level(level_path: String) -> void:
	var level := ResourceLoader.load(
		level_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as LevelResource
	_expect(level != null, "%s loads" % level_path.get_file())
	if level == null:
		return
	var errors := level.validate_runtime()
	_expect(
		errors.is_empty(),
		"%s passes complete gameplay and shared-asset validation: %s" % [
			level_path.get_file(),
			"; ".join(errors),
		]
	)
	var save_copy := level.duplicate(true) as LevelResource
	_expect(save_copy != null, "%s creates its runtime-save deep copy" % level_path.get_file())
	if save_copy == null:
		return
	var save_errors := save_copy.validate_runtime()
	_expect(
		save_errors.is_empty(),
		"%s runtime-save copy remains valid: %s" % [
			level_path.get_file(),
			"; ".join(save_errors),
		]
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
