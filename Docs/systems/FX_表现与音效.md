# 表现与音效 · FX

## 职责

提供不改变玩法状态的视觉/音效反馈，强化镜面主题。当前已落地关卡下方实时平面倒影；激光、命中、音效与 BGM 仍由各自功能模块逐步接入。

## 分类 / 做法

- **关卡下方倒影**：在地形基线下创建水平反射面，共享当前 `World3D`，用独立 `SubViewport + Camera3D` 实时渲染完整关卡。
- **水坑质感**：反射材质提供五点柔化、Fresnel、颜色保留和程序化雨滴环形微波纹，不依赖固定投影或预烘焙贴图。
- **激光束 VFX**：激光塔射线的视觉表现（含复制后光路段）。
- **命中特效**：伤害命中单位/据点的粒子反馈。
- **音效 / BGM**：UI、开火、命中、建造、镜子放置和背景音乐。

## 文件构成

| 文件 | class_name / 基类 | 职责 |
|---|---|---|
| `scripts/fx/LevelReflectionDefinition.gd` | `LevelReflectionDefinition / Resource` | 保存关卡倒影的开关、外观与性能预算。 |
| `scripts/fx/LevelReflectionSurface.gd` | `LevelReflectionSurface / Node3D` | 计算关卡水平包围盒，维护反射面、共享世界视口和离轴反射相机。 |
| `resources/fx/LevelReflection.gdshader` | Spatial Shader | 实时反射采样、五点柔化、Fresnel 与稀疏雨滴波纹。 |
| `resources/fx/LevelReflection.tres` | `LevelReflectionDefinition` 数据 | 运行时默认倒影配置，可在 Godot Inspector 中直接编辑。 |
| `scripts/Main.gd` | `Node3D` | 只负责实例化 FX 节点并注入 Grid、TileManager 和主相机。 |

## 可编辑参数

参数入口：Godot FileSystem → `resources/fx/LevelReflection.tres` → Inspector。

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `feature_enabled` | `true` | 总开关；关闭后不创建/刷新倒影视口。 |
| `vertical_offset` | `0.18` | 反射面低于最低地形基线的世界距离。 |
| `edge_margin_cells` | `1.5` | 反射面超出关卡包围盒的格距。 |
| `surface_tint` | `(0.12, 0.24, 0.30)` | 水面暗部颜色。 |
| `reflectivity` | `0.82` | 基础反射占比。 |
| `reflection_brightness` | `0.92` | 反射画面亮度。 |
| `reflection_blur_pixels` | `0.65` | 五点柔化采样半径，单位为反射纹理像素。 |
| `fresnel_strength` | `0.24` | 掠射角反射增强幅度。 |
| `ripple_enabled` | `true` | 程序化雨滴微波纹开关。 |
| `ripple_strength` | `0.0028` | 波纹对倒影 UV 的扰动幅度。 |
| `ripple_scale` | `9.0` | 波纹分布密度。 |
| `ripple_speed` | `0.45` | 波纹动画速度。 |
| `ripple_highlight_strength` | `0.06` | 稀疏环形波纹高光强度。 |
| `reflection_resolution` | `768` | 反射纹理较长边分辨率，短边自动匹配关卡长宽比。 |
| `update_interval_frames` | `1` | 刷新帧间隔；`1` 为每帧实时刷新。 |

## 关键架构与数据流

```text
Main Camera ──位置/视点──> LevelReflectionSurface
GridManager ──grid_changed──> 自动重算四边形/六边形关卡包围盒
TileManager ──level_loaded / tile_changed──> 自动重算最低地形基线
LevelReflectionSurface ──共享 World3D──> SubViewport + 水平镜像 Camera3D
SubViewportTexture ──五点柔化/波纹/Fresnel──> 水平 PlaneMesh
```

- 反射相机位置为主相机位置关于 `y = surface_y` 的严格对称点，并用反射面矩形建立离轴视锥；移动、旋转、俯仰和缩放主视角都会得到实时结果。
- 反射面只在可见层 20；所有反射相机剔除层 20，复制镜和水面不会彼此递归采样。
- FX 节点不创建 `CollisionObject3D`、不注册地块占位，也不被寻路、战斗、建造或镜子复制查询。

## 函数索引

### `LevelReflectionSurface`

- `configure(grid: GridManager, tile_manager: TileManager, source_camera: Camera3D, definition: LevelReflectionDefinition) -> void`：注入只读依赖并创建表现层。
- `set_source_camera(camera: Camera3D) -> void`：替换视点事实源并立即刷新。
- `refresh_now() -> bool`：按当前主相机更新水平镜像视点、离轴视锥并请求视口渲染一帧。
- `get_surface() -> MeshInstance3D`：返回纯表现反射面，供测试/调试检查。
- `get_reflection_viewport() -> SubViewport`：返回共享世界渲染目标。
- `get_reflection_camera() -> Camera3D`：返回虚拟反射相机。
- `get_surface_y() -> float`：返回当前反射面世界高度。
- `get_surface_size() -> Vector2`：返回自动计算的 XZ 平面尺寸。

## 约定与限制

- 这是单平面 Planar Reflection，不是 SSR 或光线追踪；不会反射其它反射面，避免反馈纹理和指数级开销。
- 连续不透明地块会物理遮住其正下方同位置倒影；倒影主要在关卡外缘、高度差、建筑和单位投影区域可见，不通过抬高水面破坏地块可读性。
- 当前每个运行关卡只创建一个反射视口；低端设备优先降低 `reflection_resolution` 或提高 `update_interval_frames`。
- 动态天气、昼夜、后处理调色、音频混音和空间音频尚未实现。
