## LevelReflectionDefinition -- 关卡下方环境倒影的纯表现参数。
##
## 资源只描述渲染质量与水面观感，不参与地块、寻路、建造或战斗数据。
class_name LevelReflectionDefinition
extends Resource

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Surface")
## 反射面位于最低地形基线下方的距离（世界单位）。
@export_range(0.02, 20.0, 0.01) var vertical_offset: float = 0.18
## 反射面超出关卡包围盒的格距，保证斜视角下仍能看到边缘倒影。
@export_range(0.0, 8.0, 0.1) var edge_margin_cells: float = 1.5
@export_color_no_alpha var surface_tint: Color = Color(0.12, 0.24, 0.30, 1.0)
@export_range(0.0, 1.0, 0.01) var reflectivity: float = 0.82
@export_range(0.1, 2.0, 0.01) var reflection_brightness: float = 0.92
## 以反射纹理像素为单位的五点柔化半径。
@export_range(0.0, 4.0, 0.05) var reflection_blur_pixels: float = 0.65
@export_range(0.0, 1.0, 0.01) var fresnel_strength: float = 0.24

@export_group("Rain Ripple")
@export var ripple_enabled: bool = true
## UV 扰动幅度；数值过大会产生不自然的折射拉伸。
@export_range(0.0, 0.02, 0.0001) var ripple_strength: float = 0.0028
@export_range(2.0, 40.0, 0.5) var ripple_scale: float = 9.0
@export_range(0.0, 4.0, 0.05) var ripple_speed: float = 0.45
@export_range(0.0, 0.5, 0.01) var ripple_highlight_strength: float = 0.06

@export_group("Render Budget")
## 反射纹理较长边分辨率，另一边按关卡长宽比计算。
@export_range(128, 2048, 64) var reflection_resolution: int = 768
## 1 表示每帧刷新；可提高此值换取性能。
@export_range(1, 12, 1) var update_interval_frames: int = 1
