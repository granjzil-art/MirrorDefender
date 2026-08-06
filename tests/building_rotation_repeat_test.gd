extends SceneTree

const HoldRepeatGateScript := preload("res://scripts/shared/HoldRepeatGate.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")
	return


func _run() -> void:
	print("[BuildingRotationRepeat] running")
	var gate: HoldRepeatGate = HoldRepeatGateScript.new()
	gate.configure(0.3, 0.1, 3)
	_expect(not gate.is_active(), "repeat gate starts inactive")
	gate.press()
	_expect(gate.is_active(), "press arms the repeat gate")
	_expect(gate.advance(0.29) == 0, "holding before the initial delay does not repeat")
	_expect(gate.advance(0.02) == 1, "crossing the initial delay emits one repeat")
	_expect(gate.advance(0.2) == 2, "continued holding repeats at the configured interval")
	_expect(gate.advance(5.0) == 3, "a stalled frame is capped by the configured burst limit")
	_expect(gate.advance(0.0) == 0, "discarded stall time cannot cause a delayed rotation burst")
	gate.release()
	_expect(not gate.is_active() and gate.advance(1.0) == 0, "release stops rotation immediately")

	var main := MainController.new()
	_expect(is_equal_approx(main.selected_rotation_hold_delay, 0.3), "Main exposes the hold delay")
	_expect(is_equal_approx(main.selected_rotation_repeat_interval, 0.08), "Main exposes the repeat interval")
	var original_time_scale := Engine.time_scale
	Engine.time_scale = 0.1
	_expect(is_equal_approx(main._get_unscaled_input_delta(0.01), 0.1), "building hold cadence ignores tactical slow motion")
	Engine.time_scale = original_time_scale
	main.free()

	if _failures == 0:
		print("[BuildingRotationRepeat] PASS: %d checks" % _checks)
		quit(0)
		return
	printerr("[BuildingRotationRepeat] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)
	return


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	printerr("  FAIL: %s" % message)
	return
