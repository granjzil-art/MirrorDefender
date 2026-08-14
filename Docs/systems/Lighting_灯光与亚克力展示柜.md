# 灯光与亚克力展示柜 · Lighting

> 实现状态：已实现按关卡独立配置的动态尺寸亚克力展示柜、四侧板投射物反射、数据化灯光方案、方案渐变、反射探针、独立程序树影层、独立真实树投影对照层和 Level2 白色柔光/黄色暖光/青红对比/夜晚聚光四套测试方案。

## 职责

- 在不修改 Blender 原模型材质的前提下，为整个关卡增加“玩具模型/橱窗展示柜”外壳。
- 依据当前 Grid 的 SQUARE/HEX 形状、单格尺寸、单元角点和可视物高度自动计算柜体 AABB，支撑不同尺寸关卡。
- 用可校验 `.tres` 资源表达 Environment、灯源、阴影、透明板色调、反射探针和过渡时间，使后续灯光方案可在 Inspector 中细致调整。
- 柜体仍不创建物理碰撞，不影响点选、建造或寻路；唯一玩法能力是四侧板通过显式有限平面查询反射我方实体塔/复制塔投射物。
- 微缩景深属于 CameraInput 最终视口管线，不写入 LightingProfile；四套灯光可以与同一景深资源任意组合，避免色彩方案切换时意外改变焦带。

## 分类 / 做法

- **柜体构造**：`AcrylicDisplayCaseDefinition` 管动态边距、净高、边条、顶板、底座、密封垫和侧板投射物反射参数；不携带灯光方案色彩。
- **关卡独立配置**：每个正式 `LevelResource` 都在 `Presentation > Display Case Definition` 内嵌自己的 `AcrylicDisplayCaseDefinition` 子资源。加载/切换关卡时控制器读取当前关卡的定义并重新构建柜体；缺少该定义的正式关卡校验失败。
- **动态边界**：`AcrylicDisplayCase` 遍历 `GridManager.get_all_cells()` 的单元多边形角点，再合并 Terrain/Stuff 的 `MeshInstance3D` AABB。水平边界扩展 `horizontal_margin_cells`；顶部取实际视觉最高点加边距与最小净高的较大值。
- **亚克力材质**：五个 `QuadMesh` 使用统一 Shader，以低基础 Alpha + Fresnel + UV 边缘 + 对角假反射条纹表达透明板。十二条半透明发光边稳定表达板厚和轮廓。
- **灯光方案**：`LightingProfile` 聚合 `Environment`、任意数量 `LightDefinition`、`DisplayCaseLightingDefinition`、`ReflectionProbeDefinition` 和默认过渡时间。
- **尺寸无关布光**：`LightDefinition.position_space = BOUNDS_NORMALIZED` 时，`position.x/z` 的 -1～1 映射到关卡左右/前后，`position.y` 映射到内容高度；射程、面光源尺寸与影子距离也会按边界放大。`WORLD_ABSOLUTE` 供局部灯使用。
- **切换**：新灯组从 0 能量淡入，旧灯组淡出；Environment 的背景、环境光、色调曝光/对比/饱和度、雾强度连续插值。柜体色调和探针在切换开始时更新。
- **关卡选择**：`LevelResource.display_case_definition` 决定该关的柜体构造与材质响应；`LevelResource.lighting_profile` 可为单关指定首选灯光方案，空值沿用控制器默认第一套方案。两类配置彼此独立。
- **投射物反射**：前/后/左/右四块侧板的玩法法线朝向柜内，柜内射出的我方投射物按反射镜公式反弹，柜外射入穿过；侧板范围严格受当前动态宽/深/高度约束，顶板不参与。Main 将柜体查询注册给 MirrorManager，后者与实体反射镜候选比较并返回最近命中。
- **程序化树影**：`FoliageShadowController` 按随机种子生成少量柔边椭圆叶簇，贴图用 Alpha Hash 把局部遮挡降为浅密度，载体网格设为 `SHADOWS_ONLY`，因此不显示树冠模型，只在已启用阴影的现有灯源中留下稀疏浅光斑。遮片尺寸跟随同一份关卡 AABB，每帧只平移 UV 模拟风吹晃动。
- **开关隔离**：`foliage_shadow_enabled` 只切换遮影网格的 `visible` 和自身进程，不重建或改写 Light3D、LightingProfile、Environment、反射探针和亚克力材质；关闭后就是原有灯光方案。
- **真实树投影对照**：`RealisticTreeShadowController` 通过 `ModelAssetDefinition` 实例化 `res://assets/greattree/realistic_tree_gltf/sketchfab_scene.tscn`，保留模型原材质和完整树冠/树干层级，统一等比缩放到配置的单格相对高度，再依据动态内容边界定位与贴地。树干使用原网格投影；原 Alpha Blend 叶片关闭实心投影，另建一个 `SHADOWS_ONLY` Alpha Scissor 副本读取同一叶片 Alpha，并叠加粗细两级镂空噪声，让重叠树冠内部仍保留碎光。系统不创建碰撞体，也不改可见树材质。
- **双开关 A/B**：`realistic_tree_shadow_enabled` 与 `foliage_shadow_enabled` 完全独立。默认关闭程序遮片、开启真实树；“实树”关闭后不会修改灯组，“树影”重新开启后即可在同一相机和同一 LightingProfile 下比较两种方案。
- **夜晚聚光**：深蓝 Environment 压低整体亮度；一盏暖中性 SpotLight3D 形成局部光池并作为唯一阴影灯读取树影遮片；无阴影冷色 AreaLight3D 和弱 DirectionalLight3D 只补水面、背光与模型轮廓，避免整场发灰或叠出多重树影。

## 关键参数

| 资源 / 参数 | 默认 | 说明 |
|---|---:|---|
| `AcrylicDisplayCaseDefinition.horizontal_margin_cells` | 脚本默认 0.35；Level1–4 当前 0.6 | 柜体比关卡边界每侧多出的单格数。该值属于当前关卡的独立定义。 |
| `minimum_interior_height_cells` | 4.5 | 柜体最小内部净高。 |
| `top_margin_cells` | 0.65 | 实际最高可视物上方余量。 |
| `edge_thickness_cells` | 0.025 | 亚克力高光边条厚度。 |
| `base_thickness_cells` | 0.65 | 木质底座高度。 |
| `projectile_reflection_enabled` | true | 四侧板是否参与我方投射物反射；不影响板面显示。 |
| `collision_epsilon_ratio` | 0.002 格 | 反射后沿新方向推进的防止同面重入距离，计入总射程。 |
| `max_reflections_per_frame` | 8 | 极高速投射物单帧最多处理的反射次数，不是生命周期上限。 |
| `DisplayCaseLightingDefinition.base_alpha` | 0.018 | 正视板面的基础可见度。 |
| `fresnel_alpha / fresnel_power` | 0.11 / 4.0 | 斜视角的边缘增亮与曲线。 |
| `border_alpha / stripe_strength` | 0.11 / 0.035 | 板面边缘和假环境反射条纹。 |
| `LightDefinition.position_space` | `BOUNDS_NORMALIZED` | 关卡尺寸归一化或世界绝对定位。 |
| `shape_scales_with_level` | true | 射程和 AreaLight3D 尺寸是否随关卡扩展。 |
| `LightingProfile.default_transition_duration` | 0.6 s | 方案切换的默认渐变时长。 |
| `ReflectionProbeDefinition.update_always` | false | false 使用 `UPDATE_ONCE`；动态环境可改为每帧更新。 |
| `AcrylicDisplayCaseDefinition.top_panel_specular` | `0.0`（范围 `0.0–1.0`） | 仅控制水平顶板的直接镜面高光；默认关闭以消除随相机滑动的饱和亮斑，四块侧板仍保持原有亚克力高光。 |
| `FoliageShadowDefinition.cluster_count` | 5 | 整张图案的叶簇数；默认刻意保持稀疏。 |
| `leaves_per_cluster_min / max` | 2 / 3 | 每簇模拟叶片数，用于控制复杂度。 |
| `leaf_radius_min_uv / max_uv` | 0.045 / 0.085 | 单片柔边椭圆在遮片 UV 中的半径范围。 |
| `shadow_strength` | 0.36（范围 `0.0–2.0`） | Alpha Hash 占用密度；`0` 关闭程序叶影，`1` 为常规密度，超过 `1` 可继续加密直到遮片饱和，不改灯光能量。 |
| `edge_softness` | 0.35 | 叶片外缘渐隐宽度，避免像硬剪纸。 |
| `motion_speed / sway_uv` | 0.22 / (0.016, 0.011) | 微风速度和两轴 UV 摆幅。 |
| `RealisticTreeShadowDefinition.position_normalized` | `(-0.2, 0.42)` | 真实树根相对内容边界的位置；允许置于关卡外缘，让树冠切入光锥而不遮住主玩法区。 |
| `target_height_cells` | `30.0` | 真实树模型目标高度，最终世界高度为该值乘当前 `cell_size`，保持所有轴等比缩放。 |
| `yaw_degrees / ground_offset_cells` | `18° / 0` | 模型水平朝向与相对采样地表的垂直偏移。 |
| `leaf_shadow_strength` | `1.0`（范围 `0.0–2.0`） | 仅控制实体树 `SHADOWS_ONLY` 叶片副本的覆盖强度；`0` 移除叶片投影，超过 `1` 加密叶影，树干仍按原模型保持不透明投影。 |
| `leaf_alpha_scissor_threshold` | `0.58` | 叶片源贴图 Alpha 的硬裁切阈值；提高会略微收紧单片叶缘。 |
| `leaf_shadow_breakup_scale` | `14.0` | 仅投影材质的碎影频率；越高，叶隙颗粒越细。 |
| `leaf_shadow_gap_threshold` | `0.54` | 树冠二次镂空阈值；越高，大片树影内部的透光缝隙越多。 |
| `leaf_shadow_pattern_seed` | `11.7` | 镂空噪声构图种子，只改变碎影分布。 |
| `NightSpotlight.environment.background / ambient` | `(0.006, 0.012, 0.035)` / `0.46` | 深蓝夜空与低强度环境补光。 |
| `NightSpotlight.night_spot.energy / angle` | `1.3` / `15°` | 为 30 格树影重新标定的暖中性主聚光亮度与光锥范围。 |
| `NightSpotlight.night_spot.position.y / range` | `3.0 / 150` | 灯高按关卡最长边缩放，并用足够射程越过 30 格树冠照向关卡中心。 |
| `NightSpotlight.night_spot.shadow_opacity / blur` | `0.82` / `0.5` | 真实树碎影可见度与阴影柔化；较低 Blur 避免细叶隙被阴影图重新合并。 |
| `NightSpotlight` 冷色填光/轮廓光阴影 | 关闭 | 只做夜色层次，不产生第二套树影。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/lighting/LightingController.gd` | `LightingController` / `Node3D` | 资源方案应用、灯组生成/渐变、Environment、探针和柜体协调。 |
| `scripts/lighting/LightingProfile.gd` | `LightingProfile` / `Resource` | 一整套可校验灯光方案。 |
| `scripts/lighting/LightDefinition.gd` | `LightDefinition` / `Resource` | 单个 Directional/Omni/Spot/Area 灯的定位、颜色、能量、形状和阴影。 |
| `scripts/lighting/DisplayCaseLightingDefinition.gd` | `DisplayCaseLightingDefinition` / `Resource` | 单方案下亚克力板与边条色调。 |
| `scripts/lighting/ReflectionProbeDefinition.gd` | `ReflectionProbeDefinition` / `Resource` | 反射探针强度、边界、混合和更新策略。 |
| `scripts/lighting/AcrylicDisplayCaseDefinition.gd` | `AcrylicDisplayCaseDefinition` / `Resource` | 尺寸无关的柜体构造与侧板反射参数。 |
| `scripts/lighting/AcrylicDisplayCase.gd` | `AcrylicDisplayCase` / `Node3D` | 按当前关卡边界生成底座、五面板和十二边，并查询四块有限侧板。 |
| `scripts/lighting/FoliageShadowDefinition.gd` | `FoliageShadowDefinition` / `Resource` | 稀疏度、强度、柔边、动态尺寸边距与摆动参数。 |
| `scripts/lighting/FoliageShadowController.gd` | `FoliageShadowController` / `Node3D` | 生成贴图与单一遮影面，跟随关卡尺寸重建并驱动 UV 晃动。 |
| `scripts/lighting/RealisticTreeShadowDefinition.gd` | `RealisticTreeShadowDefinition` / `Resource` | 真实树资产、高度、归一化位置、朝向、贴地偏移与投影开关。 |
| `scripts/lighting/RealisticTreeShadowController.gd` | `RealisticTreeShadowController` / `Node3D` | 实例化并等比拟合真实树，按动态关卡边界贴地，并递归启用网格投影。 |
| `scripts/ui/LightingTestPanel.gd` | `LightingTestPanel` / `PanelContainer` | 左上角四方案快捷对比、当前方案标题与独立“树影/实树”开关。 |
| `resources/lighting/AcrylicGlass.gdshader` | Spatial Shader | 亚克力的 Fresnel、边缘、反射条纹与透明度。 |
| `resources/levels/Level1.tres`～`Level4.tres` | `LevelResource` | 各自内嵌独立的 `display_case_definition`，复制关卡资源时参数随关卡一起复制。 |
| `resources/lighting/AcrylicDisplayCase.tres` | `AcrylicDisplayCaseDefinition` | 新建关卡或测试可使用的柜体参数模板；正式关卡运行时不再共享读取它。 |
| `resources/lighting/FoliageShadowDefault.tres` | `FoliageShadowDefinition` | Level2 默认稀疏浅树影参数。 |
| `resources/lighting/RealisticTreeShadow.tres` | `RealisticTreeShadowDefinition` | 真实树资产引用及当前 30 格、叶隙投影对照参数。 |
| `resources/lighting/RealisticLeafShadowCutout.gdshader` | Spatial Shader | 复用叶片 Alpha，并以两级噪声打散重叠树冠的仅投影材质。 |
| `resources/lighting/WhiteSoft.tres` | `LightingProfile` | Level2 默认中性白色柔光。 |
| `resources/lighting/WarmYellow.tres` | `LightingProfile` | 暖黄主光 + 弱冷填光。 |
| `resources/lighting/CyanRedContrast.tres` | `LightingProfile` | 顶部弱轮廓光 + 左青右红面光源。 |
| `resources/lighting/NightSpotlight.tres` | `LightingProfile` | 深蓝环境、暖中性单阴影聚光与无阴影冷色填光组成的夜晚方案。 |
| `tests/lighting_display_case_test.gd` | `SceneTree` | 四方案配置、Level2 动态尺寸、无碰撞、四侧/柜角反射、真实/复制投射物、夜晚单阴影灯与探针回归。 |
| `tests/acrylic_top_highlight_test.gd` | `SceneTree` | Level1–4 柜体定义互相独立、运行时切关替换定义、顶板无镜面亮斑、侧板高光保留以及灯光方案隔离回归。 |
| `tests/lighting_visual_capture.gd` | `SceneTree` | 用真实 Forward+ 视口输出 Level2 四方案 PNG。 |
| `tests/night_spotlight_visual_capture.gd` | `SceneTree` | 输出 Level2 夜晚聚光的真实树、程序树影、无树影三张同机位 A/B PNG。 |
| `tests/foliage_shadow_test.gd` | `SceneTree` | 程序贴图、稀疏/浅密度、动态尺寸、摆动、开关隔离和 Level2 集成回归。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded(level)
  -> Main._on_level_loaded(level, source_path)
  -> LightingController.apply_level(level)
     -> AcrylicDisplayCase.configure(..., level.display_case_definition, ...)
     -> AcrylicDisplayCase.rebuild_for_level()
        -> Grid cells/polygon corners + Terrain/Stuff visual AABB
        -> content bounds -> base + panels + edges
     -> choose level.lighting_profile or current/default profile
     -> build Light3D group from LightDefinition[]
     -> duplicate/apply Environment
     -> resize/configure ReflectionProbe
     -> apply DisplayCaseLightingDefinition
     -> FoliageShadowController.rebuild(content bounds, cell size)
     -> RealisticTreeShadowController.rebuild(content bounds, cell size)

FoliageShadowController
  -> deterministic leaf-cluster ImageTexture
  -> SHADOWS_ONLY PlaneMesh above content bounds
  -> existing shadow-enabled lights project sparse marks
  -> UV offset animation simulates slow canopy sway

RealisticTreeShadowController
  -> ModelAssetDefinition.instantiate_grounded_model()
  -> uniform fit to target_height_cells * cell_size
  -> terrain surface sampling at normalized bounds position
  -> authored meshes cast shadows through the active shadow-enabled light

Main assembly
  -> MirrorManager.register_projectile_reflection_provider(AcrylicDisplayCase, trace Callable)
  -> Projectile segment query
     -> MirrorManager compares ReflectMirror and acrylic candidates
     -> nearest finite active face -> shared reflection formula / distance budget

test panel profile click or raw key 6/7/8/9
  -> LightingController.apply_profile_by_index(index)
  -> new light group fades in + old group fades out
  -> Environment parameters blend
  -> profile_changed(profile, index)
  -> LightingTestPanel refreshes title

test panel "树影 开/关"
  -> LightingController.set_foliage_shadow_enabled(enabled)
  -> caster visibility/process only; current profile and Environment stay untouched

test panel "实树 开/关"
  -> LightingController.set_realistic_tree_shadow_enabled(enabled)
  -> model visibility only; current profile, Environment and generated lights stay untouched
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `LightingController.configure` | `(world_environment, legacy_light, grid, terrain_manager, profiles, visual_roots = [], foliage_shadow_definition = null, realistic_tree_shadow_definition = null) -> void` | 注入环境、旧灯、尺寸事实源、方案以及可选程序/真实树影资源；柜体定义由关卡提供。 |
| `LightingController.apply_level` | `(level_resource: LevelResource) -> bool` | 读取 `level_resource.display_case_definition`，重新配置并构建柜体，再重应用首选/当前灯光方案。 |
| `LightingController.apply_profile_by_index` | `(profile_index: int, duration: float = -1.0) -> bool` | 按注入顺序切换方案。 |
| `LightingController.apply_profile` | `(profile: LightingProfile, duration: float = -1.0, profile_index: int = -1) -> bool` | 校验并应用任意方案。 |
| `LightingController.get_active_profile` | `() -> LightingProfile` | 返回当前方案。 |
| `LightingController.get_display_case` | `() -> AcrylicDisplayCase` | 返回柜体实例，供 Main 注册反射查询及测试/调试读取。 |
| `LightingController.set_foliage_shadow_enabled` | `(enabled: bool) -> void` | 只切换树影层并发出 `foliage_shadow_enabled_changed`。 |
| `LightingController.is_foliage_shadow_enabled` | `() -> bool` | 返回树影层当前有效状态。 |
| `LightingController.set_realistic_tree_shadow_enabled` | `(enabled: bool) -> void` | 只切换真实树对照层并发出 `realistic_tree_shadow_enabled_changed`。 |
| `LightingController.is_realistic_tree_shadow_enabled` | `() -> bool` | 返回真实树投影对照层的当前有效状态。 |
| `FoliageShadowController.configure` | `(definition: FoliageShadowDefinition) -> bool` | 校验并保存树影定义。 |
| `FoliageShadowController.rebuild` | `(bounds: AABB, cell_size: float) -> bool` | 按关卡宽深、模型顶部和单格尺寸重建遮影面。 |
| `FoliageShadowController.advance_motion` | `(delta: float) -> bool` | 在启用时更新可重复 UV 偏移；关闭时不做工作。 |
| `RealisticTreeShadowController.rebuild` | `(bounds: AABB, cell_size: float) -> bool` | 依据动态关卡边界、当前单格尺寸和地表高度重新实例化、等比拟合并放置真实树。 |
| `AcrylicDisplayCase.configure` | `(grid: GridManager, terrain_manager: TerrainManager, definition: AcrylicDisplayCaseDefinition, visual_roots: Array[Node3D] = []) -> void` | 注入尺寸与视觉边界依赖。 |
| `AcrylicDisplayCase.rebuild_for_level` | `() -> bool` | 重算当前关卡边界并替换全部程序化几何。 |
| `AcrylicDisplayCase.apply_lighting` | `(definition: DisplayCaseLightingDefinition) -> void` | 替换所有板面 Shader 参数和边条材质。 |
| `AcrylicDisplayCase.get_definition` | `() -> AcrylicDisplayCaseDefinition` | 返回当前关卡正在使用的柜体定义，供校验和调试读取。 |
| `AcrylicDisplayCase.get_content_bounds` | `() -> AABB` | 返回扩展后的关卡内容边界。 |
| `AcrylicDisplayCase.get_projectile_reflection_surface_count` | `() -> int` | 返回当前启用并已构建的玩法侧板数量；正式为4。 |
| `AcrylicDisplayCase.trace_projectile_reflection` | `(start: Vector3, end: Vector3) -> Dictionary` | 返回四侧板最近内向有限交点；键与 MirrorManager 统一反射结果一致。 |
| `LightingProfile.validate_configuration` | `() -> Array[String]` | 递归校验 ID、Environment、灯、柜体色调与探针。 |
| `LightDefinition.validate_configuration` | `() -> Array[String]` | 校验单灯 ID、定位、能量、射程、形状与阴影参数。 |
| `LightingTestPanel.configure` | `(controller: LightingController) -> void` | 绑定方案列表和 `profile_changed` 信号。 |

## 测试与调整入口

- 运行 Level2 后，点击左上角“白色柔光 / 黄色暖光 / 青红对比 / 夜晚聚光”切换方案；灯光不再占用数字键。“树影”和“实树”是彼此独立且与四套灯光方案平级的 A/B 开关；推荐先保持“树影 关 / 实树 开”观察真实模型，再切换为“树影 开 / 实树 关”观察程序方案，双关即为无额外树影基线。
- 调整单关柜体：打开对应 `resources/levels/Level*.tres`，在 `Presentation > Display Case Definition` 中修改边距、高度、底座、顶板和反射参数。各关子资源实例互不共享。
- 新建灯光方案：复制任一灯光方案 `.tres`，调整 Environment、灯源、亚克力色调和探针子资源，再把新 `LightingProfile` 注入 `Main.gd` 的方案数组；若是关卡专用艺术方案，可设置 `LevelResource.lighting_profile`。灯光方案切换不会覆盖关卡的柜体构造参数。
- 自动回归：`godot --headless --path <project> --script res://tests/lighting_display_case_test.gd`。
- 树影专项回归：`godot --headless --path <project> --script res://tests/foliage_shadow_test.gd`。
- 真实视口捕获（不加 `--headless`）：`godot --path <project> --script res://tests/lighting_visual_capture.gd`；输出 Level2 四方案到 `outputs/lighting_profiles/`，运行时截图不应提交。
- 夜晚三态捕获：`godot --path <project> --script res://tests/night_spotlight_visual_capture.gd`；输出真实树、程序树影和双关基线到 `outputs/lighting_profiles/`。

## 已知限制

- 透明板是针对低多边形玩具缩微景观的稳定风格化材质，不模拟实体玻璃厚度、色散、多次折射或精确环境镜像。
- 五个透明面采用 `depth_draw_never`，边缘用显式十二条几何强化；多个其它大面积透明特效穿过柜体时仍需在目标摄像机角度检查排序。
- `ReflectionProbe.UPDATE_ALWAYS` 会显著增加 GPU 开销；静态展示柜应保持默认 `UPDATE_ONCE`。
- 当关卡在运行中动态新增超高可视物时，柜体不会每帧追踪；需在结构变更后显式调用 `rebuild_for_level()`。
- 当前测试面板是开发入口，由 `Main.lighting_test_panel_enabled` 关闭后不影响方案管线。
- 树影层只能被 `shadow_enabled=true` 且能覆盖关卡的 Light3D 投影；纯环境光或关闭阴影的方案不会显示该效果。
- Alpha Hash 在阴影图中表达独立浅密度；最终柔软程度仍会受当前灯的 `angular_distance` / `shadow_blur` 和阴影图质量影响。
- 30 格真实树仍会形成比程序遮片更具方向性的树冠阴影；当前叶片 Alpha Scissor、`leaf_shadow_strength` 和二次镂空只作用于投影副本。继续提高 `leaf_shadow_gap_threshold` 会增加透光，但过高会让树冠阴影断裂或几乎消失；`leaf_shadow_strength=0` 时树干阴影仍会保留。
- 侧板只复用当前反射镜已支持的我方实体塔/复制塔投射物；敌方投射物和持续激光尚不读取该查询。
