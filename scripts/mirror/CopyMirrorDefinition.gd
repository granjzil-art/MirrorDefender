@tool
## Data-only tuning for the M5 copy mirror and its projection presentation.
class_name CopyMirrorDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

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
@export_range(0.1, 2.0, 0.01) var mirror_height_ratio: float = 1.20
@export var reflection_enabled: bool = true
## 仅影响镜面表现；复制来源和生效方向始终由 active_from_side 决定。
@export var reflection_two_sided_visual: bool = true
## 镜面相对镜体半厚度的外推比例；需大于 0.5，避免远距离深度精度遮挡。
@export_range(0.52, 1.5, 0.01) var reflection_surface_offset_ratio: float = 0.78
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
	ConfigValidator.require_text(errors, "复制镜显示名", display_name)
	ConfigValidator.require_number(errors, "复制镜造价", cost, 0.0)
	ConfigValidator.require_number(errors, "复制镜退款", refund, 0.0)
	ConfigValidator.require_integer_range(errors, "复制链上限", copy_chain_max, 1, 16)
	ConfigValidator.require_color(errors, "镜体颜色", mirror_color)
	ConfigValidator.require_number(errors, "镜体厚度比例", mirror_thickness_ratio, 0.02, 0.5)
	ConfigValidator.require_number(errors, "镜体高度比例", mirror_height_ratio, 0.1, 2.0)
	ConfigValidator.require_number(errors, "镜面外推比例", reflection_surface_offset_ratio, 0.5, 1.5, false)
	ConfigValidator.require_integer_range(errors, "镜面分辨率", reflection_resolution, 64, 1024)
	ConfigValidator.require_integer_range(errors, "预览分辨率", reflection_preview_resolution, 64, 512)
	ConfigValidator.require_integer_range(errors, "镜面更新间隔", reflection_update_interval_frames, 1, 12)
	ConfigValidator.require_integer_range(errors, "每帧镜面更新上限", reflection_max_updates_per_frame, 1, 6)
	ConfigValidator.require_number(errors, "镜面反射率", mirror_reflectivity, 0.0, 1.0)
	ConfigValidator.require_color(errors, "镜面染色", mirror_surface_tint)
	ConfigValidator.require_color(errors, "镜面背面颜色", mirror_back_face_color)
	ConfigValidator.require_color(errors, "虚像染色", projection_tint)
	ConfigValidator.require_number(errors, "虚像透明度", projection_alpha, 0.05, 1.0)
	ConfigValidator.require_number(errors, "虚像染色强度", projection_tint_strength, 0.0, 1.0)
	ConfigValidator.require_number(errors, "虚像发光强度", projection_emission_energy, 0.0, 8.0)
	ConfigValidator.require_number(errors, "虚像轮廓透明度", projection_rim_alpha, 0.0, 1.0)
	ConfigValidator.require_number(errors, "虚像环间距", projection_ring_spacing_ratio, 0.0, 0.2)
	ConfigValidator.require_number(errors, "虚像环宽度", projection_ring_thickness_ratio, 0.01, 0.1)
	return errors
