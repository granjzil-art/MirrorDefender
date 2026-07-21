@tool
## Periodically swallows the highest-health enemy while shared capacity remains.
class_name VoidTileEffect
extends TileEffect

@export_group("Defeat")
@export_range(0.0, 100.0, 0.05, "or_greater") var reward_multiplier: float = 1.0

@export_group("Capacity")
@export_range(1, 1000, 1, "or_greater") var max_capacity: int = 3
@export_range(0.01, 10000.0, 0.01, "or_greater") var recovery_seconds_per_point: float = 5.0
@export_range(0.01, 10000.0, 0.01, "or_greater") var swallow_interval: float = 1.0

@export_group("Presentation")
@export_range(0.02, 1.0, 0.01) var empty_depth_ratio: float = 0.30
@export_range(0.0, 1.0, 0.01) var full_depth_ratio: float = 0.03

func _init() -> void:
	enemy_traversal = EnemyTraversal.PASSABLE

func uses_timed_runtime() -> bool:
	return true

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(reward_multiplier) or reward_multiplier < 0.0:
		errors.append("空洞击杀资源倍率必须为有限非负数")
	if max_capacity <= 0:
		errors.append("黑洞装填上限必须为正整数")
	if not is_finite(recovery_seconds_per_point) or recovery_seconds_per_point <= 0.0:
		errors.append("黑洞恢复一点的时间必须为有限正数")
	if not is_finite(swallow_interval) or swallow_interval <= 0.0:
		errors.append("黑洞吞噬间隔必须为有限正数")
	if not is_finite(empty_depth_ratio) or empty_depth_ratio <= 0.0:
		errors.append("黑洞空载深度比必须为有限正数")
	if not is_finite(full_depth_ratio) or full_depth_ratio < 0.0 or full_depth_ratio >= empty_depth_ratio:
		errors.append("黑洞满载深度比必须为有限非负数且小于空载深度")
	return errors

func get_copy_kind() -> StringName:
	return &"void"

func get_copy_display_name() -> String:
	return "空洞"

func get_copy_color() -> Color:
	return Color(0.08, 0.06, 0.16)
