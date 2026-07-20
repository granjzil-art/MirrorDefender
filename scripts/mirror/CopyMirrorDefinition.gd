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
@export var reflection_enabled: bool = true
@export_range(64, 1024, 64) var reflection_resolution: int = 256
@export_range(64, 512, 64) var reflection_preview_resolution: int = 128
@export_range(1, 12, 1) var reflection_update_interval_frames: int = 2
@export_range(1, 6, 1) var reflection_max_updates_per_frame: int = 2
@export_range(0.0, 1.0, 0.01) var mirror_reflectivity: float = 0.92
@export var mirror_surface_tint: Color = Color(0.80, 0.94, 1.0, 1.0)
@export var mirror_back_face_color: Color = Color(0.07, 0.10, 0.16, 1.0)

@export_group("Projection Visual")
@export var projection_tint: Color = Color(0.12, 0.85, 1.0, 1.0)
@export_range(0.05, 1.0, 0.01) var projection_alpha: float = 0.76
@export_range(0.0, 1.0, 0.01) var projection_tint_strength: float = 0.24
@export_range(0.0, 8.0, 0.1) var projection_emission_energy: float = 2.8
@export_range(0.0, 1.0, 0.01) var projection_rim_alpha: float = 0.42
@export_range(0.0, 0.20, 0.005) var projection_ring_spacing_ratio: float = 0.045
@export_range(0.01, 0.10, 0.005) var projection_ring_thickness_ratio: float = 0.022

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
	if reflection_resolution < 64 or reflection_preview_resolution < 64:
		errors.append("镜面反射分辨率不得低于 64")
	if reflection_update_interval_frames < 1 or reflection_max_updates_per_frame < 1:
		errors.append("镜面反射更新参数必须为正数")
	return errors
