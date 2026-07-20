@tool
## Data-only tuning for the M5 copy mirror and its projection presentation.
class_name CopyMirrorDefinition
extends Resource

@export_group("Identity")
@export var display_name: String = "复制镜"

@export_group("Economy")
@export_range(0.0, 100000.0, 1.0, "or_greater") var cost: float = 120.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var refund: float = 60.0

@export_group("Copy Rules")
@export var projection_ignores_occupancy: bool = true
@export_range(1, 16, 1) var copy_chain_max: int = 4
@export var active_from_side_by_default: bool = true

@export_group("Mirror Visual")
@export var mirror_color: Color = Color(0.2, 0.78, 1.0, 0.92)
@export_range(0.02, 0.5, 0.01) var mirror_thickness_ratio: float = 0.08
@export_range(0.1, 2.0, 0.01) var mirror_height_ratio: float = 0.72

@export_group("Projection Visual")
@export var projection_tint: Color = Color(0.12, 0.85, 1.0, 1.0)
@export_range(0.05, 1.0, 0.01) var projection_alpha: float = 0.46
@export_range(0.0, 0.25, 0.005) var projection_layer_offset_ratio: float = 0.035

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if display_name.strip_edges().is_empty():
		errors.append("复制镜显示名不能为空")
	if not is_finite(cost) or cost < 0.0:
		errors.append("复制镜造价必须为有限非负数")
	if not is_finite(refund) or refund < 0.0:
		errors.append("复制镜退款必须为有限非负数")
	if copy_chain_max < 1:
		errors.append("复制链上限至少为 1")
	return errors
