@tool
## LightDefinition -- one data-driven light inside a LightingProfile.
class_name LightDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

enum Kind { DIRECTIONAL, OMNI, SPOT, AREA }
enum PositionSpace { LEVEL_UNITS, BOUNDS_NORMALIZED }

@export_group("Identity")
@export var light_id: StringName = &"light"
@export var feature_enabled: bool = true
@export var kind: Kind = Kind.DIRECTIONAL

@export_group("Placement")
@export var position_space: PositionSpace = PositionSpace.BOUNDS_NORMALIZED
## BOUNDS_NORMALIZED uses X/Z in half-extent units and Y in longest-side units.
@export var position: Vector3 = Vector3(-0.35, 0.65, 0.35)
@export var aim_at_level_center: bool = true
@export var target_offset: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3(-55.0, -35.0, 0.0)

@export_group("Light")
@export_color_no_alpha var color: Color = Color.WHITE
@export_range(0.0, 64.0, 0.01, "or_greater") var energy: float = 1.0
@export_range(0.0, 16.0, 0.01, "or_greater") var indirect_energy: float = 1.0
@export_range(0.0, 1.0, 0.01) var specular: float = 0.7
@export_range(0.0, 8.0, 0.01, "or_greater") var volumetric_fog_energy: float = 1.0

@export_group("Range And Shape")
@export_range(0.1, 256.0, 0.1, "or_greater") var range: float = 24.0
@export_range(0.0, 10.0, 0.01) var attenuation: float = 1.0
@export_range(1.0, 89.0, 0.1) var spot_angle: float = 65.0
@export_range(0.0, 8.0, 0.01) var spot_angle_attenuation: float = 0.7
## For AreaLight3D. When shape_scales_with_level is enabled these are level-size ratios.
@export var area_size: Vector2 = Vector2(0.65, 0.45)
@export var shape_scales_with_level: bool = true
@export var normalize_area_energy: bool = true
@export_range(0.0, 45.0, 0.1) var angular_distance: float = 3.0

@export_group("Shadow")
@export var shadow_enabled: bool = false
@export_range(0.0, 1.0, 0.01) var shadow_opacity: float = 0.82
@export_range(0.0, 10.0, 0.001) var shadow_bias: float = 0.06
@export_range(0.0, 10.0, 0.01) var shadow_normal_bias: float = 1.0
@export_range(0.1, 8.0, 0.1) var shadow_blur: float = 1.8
@export_range(1.0, 512.0, 1.0, "or_greater") var directional_shadow_max_distance: float = 64.0


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "灯光 ID", String(light_id))
	ConfigValidator.require_color(errors, "灯光颜色", color)
	ConfigValidator.require_number(errors, "灯光能量", energy, 0.0)
	ConfigValidator.require_number(errors, "间接光能量", indirect_energy, 0.0)
	ConfigValidator.require_number(errors, "高光强度", specular, 0.0, 1.0)
	ConfigValidator.require_number(errors, "照射范围", range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "衰减", attenuation, 0.0, 10.0)
	if area_size.x <= 0.0 or area_size.y <= 0.0:
		errors.append("区域灯尺寸必须为正数")
	return errors
