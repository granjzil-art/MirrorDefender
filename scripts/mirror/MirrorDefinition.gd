@tool
## Shared data contract for every physical edge mirror.
class_name MirrorDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

@export_group("Identity")
@export var display_name: String = "镜子"
## Optional transparent mirror artwork. BuildCardBar generates the card surface,
## frame, title and cooldown presentation around it.
@export var card_icon: Texture2D

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Placement Cooldown")
@export_range(0.0, 300.0, 0.1, "or_greater") var placement_cooldown_seconds: float = 15.0

@export_group("Placement Economy")
## Used when MirrorManager.placement_cooldown_enabled is false.
@export_range(0.0, 100000.0, 1.0, "or_greater") var placement_cost: float = 100.0

@export_group("Placement")
@export var active_from_side_by_default: bool = true

@export_group("Mirror Visual")
@export var mirror_color: Color = Color(0.2, 0.78, 1.0, 0.92)
@export_range(0.02, 0.5, 0.01) var mirror_thickness_ratio: float = 0.08
@export_range(0.1, 2.0, 0.01) var mirror_height_ratio: float = 1.20
@export var reflection_enabled: bool = true
## Presentation-only two-sided observation. Gameplay always uses active_from_side.
@export var reflection_two_sided_visual: bool = true
@export_range(0.52, 1.5, 0.01) var reflection_surface_offset_ratio: float = 0.78
@export_range(64, 1024, 64) var reflection_resolution: int = 256
@export_range(64, 512, 64) var reflection_preview_resolution: int = 128
@export_range(1, 12, 1) var reflection_update_interval_frames: int = 4
@export_range(1, 6, 1) var reflection_max_updates_per_frame: int = 1
@export_range(0.0, 1.0, 0.01) var mirror_reflectivity: float = 0.92
@export var mirror_surface_tint: Color = Color(0.80, 0.94, 1.0, 1.0)
@export var mirror_back_face_color: Color = Color(0.24, 0.25, 0.27, 1.0)
@export var invalid_preview_color: Color = Color(1.0, 0.06, 0.06, 0.92)


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "镜子显示名", display_name)
	ConfigValidator.require_number(errors, "镜子放置冷却", placement_cooldown_seconds, 0.0)
	ConfigValidator.require_number(errors, "镜子放置费用", placement_cost, 0.0)
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
	ConfigValidator.require_color(errors, "无效放置预览颜色", invalid_preview_color)
	return errors
