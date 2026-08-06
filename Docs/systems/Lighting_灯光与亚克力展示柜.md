# 灯光与亚克力展示柜 · Lighting

> 实现状态：已实现动态尺寸亚克力展示柜、数据化灯光方案、方案渐变、反射探针和 DemoLevel1 白色柔光/黄色暖光/青红对比三套测试方案。

## 职责

- 在不修改 Blender 原模型材质的前提下，为整个关卡增加“玩具模型/橱窗展示柜”外壳。
- 依据当前 Grid 的 SQUARE/HEX 形状、单格尺寸、单元角点和可视物高度自动计算柜体 AABB，支撑不同尺寸关卡。
- 用可校验 `.tres` 资源表达 Environment、灯源、阴影、透明板色调、反射探针和过渡时间，使后续灯光方案可在 Inspector 中细致调整。
- 保持纯表现边界：柜体不含碰撞，不影响点选、建造、寻路、战斗或镜像。
- 微缩景深属于 CameraInput 最终视口管线，不写入 LightingProfile；三套灯光可以与同一景深资源任意组合，避免色彩方案切换时意外改变焦带。

## 分类 / 做法

- **柜体构造**：`AcrylicDisplayCaseDefinition` 只管动态边距、净高、边条、顶板、底座与密封垫；不携带灯光方案色彩。
- **动态边界**：`AcrylicDisplayCase` 遍历 `GridManager.get_all_cells()` 的单元多边形角点，再合并 Terrain/Stuff 的 `MeshInstance3D` AABB。水平边界扩展 `horizontal_margin_cells`；顶部取实际视觉最高点加边距与最小净高的较大值。
- **亚克力材质**：五个 `QuadMesh` 使用统一 Shader，以低基础 Alpha + Fresnel + UV 边缘 + 对角假反射条纹表达透明板。十二条半透明发光边稳定表达板厚和轮廓。
- **灯光方案**：`LightingProfile` 聚合 `Environment`、任意数量 `LightDefinition`、`DisplayCaseLightingDefinition`、`ReflectionProbeDefinition` 和默认过渡时间。
- **尺寸无关布光**：`LightDefinition.position_space = BOUNDS_NORMALIZED` 时，`position.x/z` 的 -1～1 映射到关卡左右/前后，`position.y` 映射到内容高度；射程、面光源尺寸与影子距离也会按边界放大。`WORLD_ABSOLUTE` 供局部灯使用。
- **切换**：新灯组从 0 能量淡入，旧灯组淡出；Environment 的背景、环境光、色调曝光/对比/饱和度、雾强度连续插值。柜体色调和探针在切换开始时更新。
- **关卡选择**：`LevelResource.lighting_profile` 可为单关指定首选方案；空值沿用控制器默认第一套方案。DemoLevel1 因此无需改写原资源即默认使用白色柔光。

## 关键参数

| 资源 / 参数 | 默认 | 说明 |
|---|---:|---|
| `AcrylicDisplayCaseDefinition.horizontal_margin_cells` | 0.35 | 柜体比关卡边界每侧多出的单格数。 |
| `minimum_interior_height_cells` | 4.5 | 柜体最小内部净高。 |
| `top_margin_cells` | 0.65 | 实际最高可视物上方余量。 |
| `edge_thickness_cells` | 0.025 | 亚克力高光边条厚度。 |
| `base_thickness_cells` | 0.65 | 木质底座高度。 |
| `DisplayCaseLightingDefinition.base_alpha` | 0.018 | 正视板面的基础可见度。 |
| `fresnel_alpha / fresnel_power` | 0.11 / 4.0 | 斜视角的边缘增亮与曲线。 |
| `border_alpha / stripe_strength` | 0.11 / 0.035 | 板面边缘和假环境反射条纹。 |
| `LightDefinition.position_space` | `BOUNDS_NORMALIZED` | 关卡尺寸归一化或世界绝对定位。 |
| `shape_scales_with_level` | true | 射程和 AreaLight3D 尺寸是否随关卡扩展。 |
| `LightingProfile.default_transition_duration` | 0.6 s | 方案切换的默认渐变时长。 |
| `ReflectionProbeDefinition.update_always` | false | false 使用 `UPDATE_ONCE`；动态环境可改为每帧更新。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/lighting/LightingController.gd` | `LightingController` / `Node3D` | 资源方案应用、灯组生成/渐变、Environment、探针和柜体协调。 |
| `scripts/lighting/LightingProfile.gd` | `LightingProfile` / `Resource` | 一整套可校验灯光方案。 |
| `scripts/lighting/LightDefinition.gd` | `LightDefinition` / `Resource` | 单个 Directional/Omni/Spot/Area 灯的定位、颜色、能量、形状和阴影。 |
| `scripts/lighting/DisplayCaseLightingDefinition.gd` | `DisplayCaseLightingDefinition` / `Resource` | 单方案下亚克力板与边条色调。 |
| `scripts/lighting/ReflectionProbeDefinition.gd` | `ReflectionProbeDefinition` / `Resource` | 反射探针强度、边界、混合和更新策略。 |
| `scripts/lighting/AcrylicDisplayCaseDefinition.gd` | `AcrylicDisplayCaseDefinition` / `Resource` | 尺寸无关的柜体构造参数。 |
| `scripts/lighting/AcrylicDisplayCase.gd` | `AcrylicDisplayCase` / `Node3D` | 按当前关卡边界生成底座、五面板和十二边。 |
| `scripts/ui/LightingTestPanel.gd` | `LightingTestPanel` / `PanelContainer` | 左上角三方案快捷对比和当前方案标题。 |
| `resources/lighting/AcrylicGlass.gdshader` | Spatial Shader | 亚克力的 Fresnel、边缘、反射条纹与透明度。 |
| `resources/lighting/AcrylicDisplayCase.tres` | `AcrylicDisplayCaseDefinition` | 项目默认柜体构造。 |
| `resources/lighting/WhiteSoft.tres` | `LightingProfile` | DemoLevel1 默认中性白色柔光。 |
| `resources/lighting/WarmYellow.tres` | `LightingProfile` | 暖黄主光 + 弱冷填光。 |
| `resources/lighting/CyanRedContrast.tres` | `LightingProfile` | 顶部弱轮廓光 + 左青右红面光源。 |
| `tests/lighting_display_case_test.gd` | `SceneTree` | 32 项配置、DemoLevel1、动态尺寸、HEX、无碰撞与探针回归。 |
| `tests/lighting_visual_capture.gd` | `SceneTree` | 用真实 Forward+ 视口输出 DemoLevel1 三方案 PNG。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded(level)
  -> Main._on_level_loaded(level, source_path)
  -> LightingController.apply_level(level)
     -> AcrylicDisplayCase.rebuild_for_level()
        -> Grid cells/polygon corners + Terrain/Stuff visual AABB
        -> content bounds -> base + panels + edges
     -> choose level.lighting_profile or current/default profile
     -> build Light3D group from LightDefinition[]
     -> duplicate/apply Environment
     -> resize/configure ReflectionProbe
     -> apply DisplayCaseLightingDefinition

test panel click or raw key 7/8/9
  -> LightingController.apply_profile_by_index(index)
  -> new light group fades in + old group fades out
  -> Environment parameters blend
  -> profile_changed(profile, index)
  -> LightingTestPanel refreshes title
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `LightingController.configure` | `(world_environment: WorldEnvironment, legacy_light: Light3D, grid: GridManager, terrain_manager: TerrainManager, case_definition: AcrylicDisplayCaseDefinition, profiles: Array[LightingProfile], visual_roots: Array[Node3D] = []) -> void` | 注入环境、旧灯、尺寸事实源、柜体和方案。 |
| `LightingController.apply_level` | `(level_resource: LevelResource) -> bool` | 关卡加载后重建柜体并重应用首选/当前方案。 |
| `LightingController.apply_profile_by_index` | `(profile_index: int, duration: float = -1.0) -> bool` | 按注入顺序切换方案。 |
| `LightingController.apply_profile` | `(profile: LightingProfile, duration: float = -1.0, profile_index: int = -1) -> bool` | 校验并应用任意方案。 |
| `LightingController.get_active_profile` | `() -> LightingProfile` | 返回当前方案。 |
| `LightingController.get_display_case` | `() -> AcrylicDisplayCase` | 返回纯表现柜体，供测试/调试查询。 |
| `AcrylicDisplayCase.configure` | `(grid: GridManager, terrain_manager: TerrainManager, definition: AcrylicDisplayCaseDefinition, visual_roots: Array[Node3D] = []) -> void` | 注入尺寸与视觉边界依赖。 |
| `AcrylicDisplayCase.rebuild_for_level` | `() -> bool` | 重算当前关卡边界并替换全部程序化几何。 |
| `AcrylicDisplayCase.apply_lighting` | `(definition: DisplayCaseLightingDefinition) -> void` | 替换所有板面 Shader 参数和边条材质。 |
| `AcrylicDisplayCase.get_content_bounds` | `() -> AABB` | 返回扩展后的关卡内容边界。 |
| `LightingProfile.validate_configuration` | `() -> Array[String]` | 递归校验 ID、Environment、灯、柜体色调与探针。 |
| `LightDefinition.validate_configuration` | `() -> Array[String]` | 校验单灯 ID、定位、能量、射程、形状与阴影参数。 |
| `LightingTestPanel.configure` | `(controller: LightingController) -> void` | 绑定方案列表和 `profile_changed` 信号。 |

## 测试与调整入口

- 运行 DemoLevel1 后，点击左上角“7 白色柔光 / 8 黄色暖光 / 9 青红对比”，或直接按键盘 7/8/9。这三个是原始键码快捷键，不污染 `project.godot` InputMap。
- 新建方案：复制任一 `resources/lighting/*.tres`，调整 Environment/灯源/柜体/探针子资源，然后把新 `LightingProfile` 注入 `Main.gd` 的方案数组；若是关卡专用艺术方案，可设置 `LevelResource.lighting_profile`。
- 自动回归：`godot --headless --path <project> --script res://tests/lighting_display_case_test.gd`。
- 真实视口捕获（不加 `--headless`）：`godot --path <project> --script res://tests/lighting_visual_capture.gd`；输出到 `outputs/lighting_profiles/`，运行时截图不应提交。

## 已知限制

- 透明板是针对低多边形玩具缩微景观的稳定风格化材质，不模拟实体玻璃厚度、色散、多次折射或精确环境镜像。
- 五个透明面采用 `depth_draw_never`，边缘用显式十二条几何强化；多个其它大面积透明特效穿过柜体时仍需在目标摄像机角度检查排序。
- `ReflectionProbe.UPDATE_ALWAYS` 会显著增加 GPU 开销；静态展示柜应保持默认 `UPDATE_ONCE`。
- 当关卡在运行中动态新增超高可视物时，柜体不会每帧追踪；需在结构变更后显式调用 `rebuild_for_level()`。
- 当前测试面板是开发入口，由 `Main.lighting_test_panel_enabled` 关闭后不影响方案管线。
