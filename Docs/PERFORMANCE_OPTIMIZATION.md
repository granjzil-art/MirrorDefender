# 性能优化决策与变更记录

本文档是性能修改的唯一追踪入口。后续每次性能相关变更都应追加记录，至少包含：变更编号、日期、决策依据、修改文件、修改前参数、修改后参数、验证结果和回退方式。不要删除历史记录；若撤销某项修改，应新增一条“回退”记录并引用原编号。

## 目标与约束

- 4K（3840×2160）全屏输出时，默认采用不高于 2560×1440 的 3D 内部分辨率，UI 继续按输出分辨率绘制。
- 目标为稳定 60 FPS；优先消除周期性长帧，再降低平均 GPU 帧时间。
- 景深默认开启，并保留玩家手动关闭选项。
- 降低灯光性能开销时，尽量保持灯光颜色、能量、环境亮度、Glow、SSAO 和阴影关系不变。
- 所有高风险结构优化必须有运行时开关或自动回退路径。

## 优化前基线

记录日期：2026-08-11。

- Godot 4.7，Forward+。
- 项目逻辑视口：1600×900；拉伸模式：`canvas_items`。
- 4K 全屏实测约 4–5 FPS，单帧约 263–301 ms；测试时存在编辑器与游戏两个 Godot 进程，因此最终验收必须使用关闭编辑器后的单独导出版本。
- 普通帧约 1046–1048 个渲染对象；镜面刷新帧约 2160–2161 个，呈近似翻倍的周期峰值。
- 主关卡约 225–255 个地形格；优化前每个平坦地形体素实例化一棵完整模型节点树。

## 变更记录

### PERF-001：4K 输出与 2K 内部渲染

日期：2026-08-11
状态：已实施，待实机性能复测。

决策：保留 `canvas_items`，不把逻辑视口硬改为 2560×1440；仅缩放根 Viewport 的 3D 缓冲区，使 UI 保持清晰。使用 FSR 2.2，并提供三档渲染质量。

| 参数 | 修改前 | 修改后 |
|---|---:|---:|
| `rendering/scaling_3d/mode` | 未显式配置（Bilinear） | `2`（FSR 2.2） |
| `rendering/scaling_3d/scale` | 未显式配置，运行时无控制 | 项目默认 `1.0`，运行时按质量档自动计算 |
| `rendering/scaling_3d/fsr_sharpness` | 未显式配置 | `0.2` |
| 默认质量档 | 无 | 平衡档 |
| 平衡档内部上限 | 无 | 2560×1440；4K 输出比例约 `0.6667` |
| 性能档内部上限 | 无 | 1920×1080；4K 输出比例 `0.5` |
| 原生档 | 无 | `1.0` |
| 游戏运行时帧率上限 | 未设置（无限制） | 非 Headless 环境设置 `Engine.max_fps = 60` |

计算规则：`min(1.0, 目标宽 / 输出宽, 目标高 / 输出高)`，最低限制为 `0.5`。窗口或低于目标上限的屏幕保持原生比例 `1.0`。

修改文件：

- `project.godot`
- `scripts/ui/RuntimeSettings.gd`
- `scripts/ui/PauseMenu.gd`
- `scenes/ui/PauseMenu.tscn`
- `scripts/AppFlowController.gd`
- `tests/runtime_ui_batch3_test.gd`

回退：在设置菜单选择“原生分辨率”可立即回退到 3D 比例 `1.0`。完全代码回退时，删除 `render_quality_preset` 设置链路和菜单行，将 `rendering/scaling_3d/mode` 恢复为 `0`，并删除运行时的 `Engine.max_fps = 60`。Headless 测试保持无限帧率，不受游戏帧率上限影响。

### PERF-002：抗锯齿与阴影采样

日期：2026-08-11
状态：已实施，待画面对比。

决策：FSR2 已提供时间抗锯齿，因此关闭额外的 4× MSAA；仅降低全局软阴影滤波采样，不改变阴影贴图尺寸、灯光阴影开关、颜色、能量、偏移或模糊参数。

| 参数 | 修改前 | 修改后 |
|---|---:|---:|
| `rendering/anti_aliasing/quality/msaa_3d` | `2`（4× MSAA） | `0`（关闭） |
| `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality` | `5`（Soft Ultra） | `3`（Soft Medium） |

修改文件：`project.godot`。

回退：将两个参数分别恢复为 `2` 和 `5`。若只发现阴影边缘质量不足，可仅将软阴影提高到 `4`，无需恢复 MSAA。

### PERF-003：灯光后处理成本

日期：2026-08-11
状态：已实施，待四套灯光档案截图对比。

决策：关闭成本较高的屏幕空间间接光 SSIL；保留 SSAO、Glow、环境色、曝光、灯光颜色、灯光能量和所有现有投影灯。景深不属于本项削减范围，继续默认开启。

| 灯光档案 | `ssil_enabled` 修改前 | 修改后 | 保持不变 |
|---|---:|---:|---|
| WhiteSoft | `true` | `false` | SSAO、Glow、环境与灯光参数 |
| WarmYellow | `true` | `false` | SSAO、Glow、环境与灯光参数 |
| CyanRedContrast | `true` | `false` | SSAO、Glow、环境与灯光参数 |
| NightSpotlight | `true` | `false` | SSAO、Glow、环境与灯光参数 |

Godot 4.7 的 SSAO 半分辨率默认值为 `true`，本次不重复覆盖该全局默认值。

修改文件：

- `resources/lighting/WhiteSoft.tres`
- `resources/lighting/WarmYellow.tres`
- `resources/lighting/CyanRedContrast.tres`
- `resources/lighting/NightSpotlight.tres`

回退：把四个资源中的 `ssil_enabled` 恢复为 `true`。

### PERF-004：实时镜面预算

日期：2026-08-11
状态：已实施，待含多镜面的关卡复测。

决策：镜面已有可见性、视锥与背面候选过滤，保留这些逻辑；降低渲染目标尺寸，并将调度改为每 4 帧最多刷新 1 面镜子。

| 参数 | 修改前实际资源值 | 修改后 |
|---|---:|---:|
| 游戏镜面宽度 | `512` | `256` |
| 预览镜面宽度 | `256` | `128` |
| 更新间隔 | `256`（已超出脚本允许范围，疑似旧资源属性错位） | `4` |
| 单帧更新上限 | `128`（已超出脚本允许范围，疑似旧资源属性错位） | `1` |
| 脚本默认更新间隔 | `2` | `4` |
| 脚本默认单帧上限 | `2` | `1` |

修改文件：

- `scripts/mirror/MirrorDefinition.gd`
- `resources/mirrors/CopyMirror.tres`
- `resources/mirrors/ReflectMirror.tres`

回退：视觉分辨率可恢复为 `512/256`。调度行为若需恢复到原设计意图，应使用 `2/2`；不建议恢复实际发现的异常值 `256/128`，因为它们违反导出范围。

### PERF-005：平坦地形 MultiMesh 批处理

日期：2026-08-11
状态：已实施，具备自动回退。

决策：相同地形资产、相同目标包围盒的平坦体素合并为 `MultiMeshInstance3D`。斜坡仍走原节点路径。带 Skin、表面材质覆盖、粒子、Decal 或其他非 Mesh 可视节点的资产自动回退为逐体素实例化，避免破坏材质和层级表现。

| 项目 | 修改前 | 修改后 |
|---|---|---|
| 平坦地形节点 | 每个体素一棵完整模型节点树 | 每个兼容 Mesh 部件一个 MultiMesh 批次 |
| 体素变换 | Node3D position | MultiMesh instance transform |
| 斜坡 | 独立模型 | 不变 |
| 不兼容模型 | 独立模型 | 自动回退，行为不变 |
| 功能开关 | 无 | `TerrainRenderer.batch_flat_models = true` |

修改文件：

- `scripts/terrain/TerrainRenderer.gd`
- `tests/terrain_runtime_test.gd`
- `tests/performance_optimization_test.gd`

快速回退：将目标 `TerrainRenderer` 的 `batch_flat_models` 设置为 `false`，无需撤销代码。

### PERF-006：地形 4K 贴图导入上限

日期：2026-08-11
状态：已修改导入参数，待 Godot 重导入与显存复测。

决策：仅限制正式关卡当前使用的 4K 地形贴图；源 PNG 不改动。Tsand 与 Water 使用的共享贴图原本为 1024×1024，不做修改。

| 参数 | 修改前 | 修改后 |
|---|---:|---:|
| 源贴图尺寸 | 4096×4096 | 4096×4096（不改源文件） |
| `process/size_limit` | `0` | `2048` |
| 运行时最大导入尺寸 | 4096×4096 | 2048×2048 |

受影响的 20 张贴图：

- `flatstone2_0..3.png`（Mud）
- `GrassMud_0..3.png`（Grass）
- `GrassStone_0..3.png`（Grassstone）
- `greenstone_0..3.png`（Greenstone）
- `mud1_0..3.png`（Sand）

修改文件：对应的 20 个 `assets/blocks/fbx/*.png.import` 文件，以及可重复执行的 `tools/performance/apply_terrain_texture_limits.ps1`。由于仓库当前忽略 `*.import`，新环境导入素材后需要执行一次该脚本，才能重现 2048 上限。

应用：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_terrain_texture_limits.ps1`。

回退：执行 `powershell -ExecutionPolicy Bypass -File tools/performance/apply_terrain_texture_limits.ps1 -Rollback`，然后在 Godot 中重新导入。源 PNG 始终保留，因此回退无损。

### PERF-007：选关目录不再常驻全部关卡

日期：2026-08-11
状态：已实施并通过资源引用回归测试。

决策：保留现有四面体 3D 关卡预览，但选关目录和页面只持久化 `res://` 路径，不再通过 `ext_resource` 长期持有 `LevelResource`。选关界面显示时临时加载预览；玩家确认关卡后，先清空四个预览的 LevelLoader、TerrainManager、StuffManager 和 TileManager 引用，再把唯一选中的关卡交给 Main。返回选关时按路径重新加载预览。

| 项目 | 修改前 | 修改后 |
|---|---|---|
| `LevelSelectPage01.tres` 关卡存储 | 4 个 `LevelResource ext_resource` | 4 个 `PackedStringArray` 路径，完整关卡依赖数为 0 |
| 目录驻留方式 | `levels: Array[LevelResource]` 持久化 | `level_paths` 持久化；`levels` 仅作测试/运行时短期兼容 |
| 进入战斗后的未选关卡对象 | Level2、Level3、Level4 仍被目录强引用 | 3 个未选 `LevelResource` 弱引用全部释放 |
| 确认关卡后的预览加载数 | 释放 LevelSelectView 时才清理 | 发出 `level_selected` 前立即由 4 降为 0 |
| 预览清理 | 仅清理 Terrain/Stuff 部分内容 | LevelLoader 统一清理 Terrain/Stuff/Tile 及当前关卡路径 |

修改文件：

- `resources/level_select/LevelSelectPage01.tres`
- `resources/level_select/LevelSelectPage02.tres`
- `resources/level_select/LevelSelectPage03.tres`
- `scripts/level/LevelSelectPageDefinition.gd`
- `scripts/level/LevelSelectCatalog.gd`
- `scripts/ui/LevelSelectView.gd`
- `scripts/ui/LevelPortalPreview.gd`
- `scripts/level/LevelLoader.gd`
- `scripts/tile/TileManager.gd`
- `tests/level_select_test.gd`
- `tests/manual_wave_and_level_flow_test.gd`

验证：`level_select_test.gd` 53/53 通过；`manual_wave_and_level_flow_test.gd` 28/28 通过。回归测试使用 `WeakRef` 确认进入 Level1 后 Level2～4 的 `LevelResource` 对象均已释放。

回退：将 `LevelSelectPage01.tres` 恢复为四个关卡 `ext_resource` 和 `levels = Array[LevelResource]`，并将 `LevelSelectPageDefinition.levels` 恢复为导出属性。`clear_level()` 公开方法可保留，不影响旧加载流程。

### PERF-008：程序化批量限制 4K 世界纹理

日期：2026-08-12
状态：已实施，已完成 Godot 重导入与压缩缓存验证。

决策：保留所有原始 PNG/JPEG 的分辨率，仅将世界模型使用的 4K 及以上纹理导入上限设为 2048。脚本每次动态扫描图片尺寸，不维护固定文件列表；`assets/ui` 与 `assets/png` 排除，避免降低 UI 清晰度或改动通用原图。每次应用都保留首次修改前的精确参数，可通过清单一键回退。

| 参数 / 指标 | 修改前 | 修改后 |
|---|---:|---:|
| 扫描阈值 | 固定 20 张地形纹理 | 所有源图最大边 `>=4096` 的世界纹理 |
| 命中数量 | 20 | 176 |
| `process/size_limit=0` | 156 | 0 |
| `process/size_limit=2048` | 20 | 176 |
| 源图尺寸 | 不变（3840～8192） | 不变（3840～8192） |
| 本次纹理 S3TC 运行时缓存 | 约 1792.1 MB（依据同格式尺寸比例回算） | 492.9 MB（实测） |
| 大于 6 MB 的目标缓存 | 大量 4K 缓存 | 0 |

分类命中：`buildings=64`、`blocks=44`、`star=21`、`stuffs=20`、`projections=8`、`sun=4`、`Ramp=4`、`enemies=4`、`moon=4`、`greattree=3`。缓存数据仅统计清单中 176 张纹理对应的 S3TC 导入产物，不包含 UI、排除目录或其他已导入资源。修改前的 156 张无限制纹理由 4096 缩小为 2048，同压缩格式的像素面积为原来的 1/4；表中修改前数值据此回算，修改后数值由实际缓存文件汇总，估算下降约 72.5%。

修改文件：

- `tools/performance/apply_world_texture_limits.ps1`
- `tools/performance/world_texture_limit_manifest.json`
- 176 个对应纹理的 `.import` sidecar（Godot 忽略文件，由脚本可重复生成）
- `tests/performance_optimization_test.gd`
- `Docs/PERFORMANCE_OPTIMIZATION.md`

验证：

- 审计：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_limits.ps1 -Mode Audit`
- 应用：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_limits.ps1 -Mode Apply -TargetLimit 2048 -MinimumSourceDimension 4096`
- 应用后审计为 `Candidates=176 Unlimited=0 AtOrBelowTarget=176`。
- Godot 自动重导入后，176 个目标缓存全部存在，大于 6 MB 的目标缓存为 0。

回退：执行 `powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_limits.ps1 -Mode Rollback`，然后等待 Godot 重新导入。清单会精确恢复到本次前的基线：156 张恢复为 `0`，先前 PERF-006 限制的 20 张仍保持 `2048`。若需连 PERF-006 也完全撤销，再执行 `powershell -ExecutionPolicy Bypass -File tools/performance/apply_terrain_texture_limits.ps1 -Rollback`。原始图片始终未修改。

### PERF-009：串行化重型世界切换，消除切关资源重叠峰值

日期：2026-08-12
状态：已实施并通过资源生命周期回归测试；待独立导出版本实测驱动层显存曲线。

决策：切换期间不再同时保留选关预览世界与战斗世界。选关进入战斗时，由协程单独保留已选 `LevelResource`，立即销毁选关界面、4 个 `SubViewport` 及其预览场景；内容根节点保持 2 个完整空帧，再调用 `RenderingServer.force_sync()` 等待渲染线程处理资源删除，之后才实例化 `Main`。战斗返回选关以及战斗启动失败恢复也使用相同顺序。

| 参数 / 时序 | 修改前 | 修改后 |
|---|---|---|
| `serialize_heavy_world_transitions` | 无 | `true` |
| `gpu_release_barrier_frames` | 0 | 2 |
| `force_gpu_sync_after_release` | 无 | `true` |
| 选关 → 战斗 | 新 `Main` 完整加载成功后才释放选关界面 | 释放选关 → 2 空帧 → GPU 同步 → 创建 `Main` |
| 战斗 → 选关 | 释放 `Main` 的同一帧立即创建 4 个预览 | 释放 `Main` → 2 空帧 → GPU 同步 → 创建预览 |
| `Content` 重型子节点峰值 | 2（选关 + 隐藏的 `Main`） | 1 |
| 新世界创建前的空内容区间 | 无 | 至少 2 个完整帧 |
| 60 FPS 下的固定切换延迟 | 0 | 约 33.3 ms，加上一次渲染同步时间 |

此修改的取舍是将切关期间的短暂显存峰值转换为可控的加载等待。常规游戏帧不执行 `force_sync()`，不增加运行时每帧开销。应用层已保证旧世界和新世界不交叉；驱动层实际显存释放速度仍需在真实 Forward+ 渲染器中用单进程导出版验收。

修改文件：

- `scripts/AppFlowController.gd`
- `tests/manual_wave_and_level_flow_test.gd`
- `Docs/PERFORMANCE_OPTIMIZATION.md`

验证：`manual_wave_and_level_flow_test.gd` 37/37 通过，分别确认两个切换方向都经过一次释放屏障，屏障期间 `Content` 子节点数为 0，屏障完成后仅有一个新世界。`level_select_test.gd` 53/53 与 `performance_optimization_test.gd` 45/45 同步通过。Headless Dummy Renderer 中的既有空材质诊断仍存在，本次断言及进程退出码均通过。

回退：将 `AppFlowController.serialize_heavy_world_transitions` 设为 `false` 即可恢复原有的同帧/重叠切换时序，不需回退其他性能优化。如仅需对比渲染同步的影响，可保持串行切换开启，只将 `force_gpu_sync_after_release` 设为 `false`。

### PERF-010：复用塔、镜子与镜像放置预览

日期：2026-08-12
状态：已实施并通过生产 Level1 预览迁移与镜像回归测试；待真实 Forward+ 渲染器帧时曲线验收。

原因：鼠标不动时，管理器命中相同格/边的早退分支，不做重建；判定位置变化后，旧流程会立即 `queue_free()` 旧预览，并在同一帧创建完整新对象。塔会重新实例化模型树和递归生成材质；镜子会重新生成镜体网格、材质和 128px 反射 `SubViewport`；复制镜还会重新复制建筑/Stuff 可视树及表面材质。帧末才回收的旧对象与新 GPU 分配重叠，形成移动一格就卡一帧的现象。

决策：同建筑定义或同镜子类型的预览在位置变化时保持原实例，只更新格/边数据、世界变换、朝向与合法性材质。镜子的反射 `SubViewport` 跨边移动保留。预览镜像按真实源对象匹配；源对象未变时只重定向已有的行为剥离快照，复制来源或模型类型真正变化时才重建。

| 项目 | 修改前（每次有效位置变化） | 修改后（同类型/同源） |
|---|---|---|
| `Building` 预览实例 | 销毁 1 + 新建 1 | 新建 0，原地迁移 |
| 建筑模型树 | 重新实例化 | 保留 |
| 建筑合法/非法变色 | 重建完整可视树 | 仅更新已有预览材质参数 |
| `CopyMirror` / `ReflectMirror` 预览 | 销毁 1 + 新建 1 | 新建 0，原地迁移 |
| 预览反射 `SubViewport` | 销毁 1 + 新建 1 | 保留同一实例 |
| 镜像模型/材质快照 | 整组销毁并递归复制 | 同源快照重定向；源变化才新建 |
| 延迟删除队列 | 移动时持续追加 | 同类型/同源移动为 0 |
| `reuse_placement_preview_instances` | 无 | 建筑与镜子管理器均默认 `true` |

修改文件：

- `scripts/building/Building.gd`
- `scripts/building/BuildingManager.gd`
- `scripts/mirror/CopyMirror.gd`
- `scripts/mirror/MirrorManager.gd`
- `scripts/mirror/MirrorProjection.gd`
- `tests/performance_optimization_test.gd`
- `Docs/PERFORMANCE_OPTIMIZATION.md`

验证：

- `performance_optimization_test.gd` 53/53 通过；生产 Level1 中连续迁移塔后 `Building.get_instance_id()` 不变，连续迁移镜子后 `CopyMirror` 与其反射 `SubViewport` 的实例 ID 都不变。
- `path_placement_connectivity_test.gd` 35/35 通过；单路径阻断时塔、镜框和复制阻挡物仍正确切换为红色非法预览。
- `copy_mirror_test.gd` 144/144 通过；直接/递归复制、表面材质、激光状态、阻挡与源生命周期保持。

回退：将 `BuildingManager.reuse_placement_preview_instances` 和 `MirrorManager.reuse_placement_preview_instances` 同时设为 `false`，即可恢复每次位置变化都重建预览及镜像快照的旧路径。两个开关互相独立，也可单独关闭以定位建筑或镜子回归。

### PERF-011：2K+ 世界纹理性能档统一限制为 1K

日期：2026-08-12
状态：已实施，已完成 185 张纹理重导入、缓存实测与回归测试。

决策：在 PERF-008 的 4K+→2K 基线上增加独立“性能纹理档”，对所有最大边不小于 2048 的世界纹理应用 `process/size_limit=1024`。此档为微缩塔防战场和 2K 内部渲染优化，显著降低纹理驻留、首次上传和放置/切关期间的显存压力。`assets/ui` 与 `assets/png` 仍排除；所有源 PNG/JPEG 尺寸和内容不变。

性能档使用独立包装脚本与回退清单，不覆盖 PERF-008 的原始基线。通用扫描脚本新增了应用前运行时缓存路径和字节数记录，重复应用时保留首次基线，不会把 1K 缓存误写为“修改前”。

| 参数 / 指标 | 修改前（PERF-008 后） | 修改后（性能档） |
|---|---:|---:|
| 源图扫描阈值 | 4K+ | 2K+ |
| 导入上限 | 2048 | 1024 |
| 命中数量 | 176 | 185 |
| 应用前 `process/size_limit=2048` | 176 | 0 |
| 应用前 `process/size_limit=0` | 9 | 0 |
| 应用后 `process/size_limit=1024` | 0 | 185 |
| 185 张对应运行时缓存 | 519.2 MB | 135.9 MB |
| 缓存减少 | — | 383.3 MB / 73.8% |
| 缓存缺失 | 0 | 0 |

分类命中：`buildings=64`、`blocks=44`、`star=21`、`stuffs=20`、`enemies=13`、`projections=8`、`sun=4`、`moon=4`、`Ramp=4`、`greattree=3`。相比 PERF-008 新增 9 张 2K 敌人纹理。重导入后 184 个缓存不超过 1.5 MB；`assets/enemies/stone-golem/textures/5_Normal_1.jpeg` 为 1024 上限的法线贴图缓存，因导入格式不同为 1.88 MB，其 sidecar 尺寸上限已确认为 1024。

修改文件：

- `tools/performance/apply_world_texture_limits.ps1`
- `tools/performance/apply_world_texture_performance_tier.ps1`
- `tools/performance/world_texture_performance_tier_manifest.json`
- 185 个对应纹理的 `.import` sidecar（Godot 忽略文件，可由脚本重复生成）
- `tests/performance_optimization_test.gd`
- `Docs/PERFORMANCE_OPTIMIZATION.md`

操作：

- 审计：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_performance_tier.ps1 -Mode Audit`
- 应用：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_performance_tier.ps1 -Mode Apply`
- 回退：`powershell -ExecutionPolicy Bypass -File tools/performance/apply_world_texture_performance_tier.ps1 -Mode Rollback`

验证：应用后审计为 `Candidates=185 Unlimited=0 AtOrBelowTarget=185 Target=1024`。重复应用为 `Updated=0 Unchanged=185`，且清单仍保留 176 张 `2048` 和 9 张 `0` 的精确修改前参数。`performance_optimization_test.gd` 64/64 通过，包含双层清单、sidecar、缓存存在性和实测降幅断言。

回退语义：执行性能档 `-Mode Rollback` 后，恢复到 PERF-008 基线：176 张恢复 `2048`，9 张 2K 敌人纹理恢复 `0`。若还需撤销 PERF-008，必须先回退性能档，再执行 `apply_world_texture_limits.ps1 -Mode Rollback`。每次回退后都需等待 Godot 重新导入。

### PERF-012：程序减面隔离评估批次

日期：2026-08-16
状态：已生成并完成资源、画面与源文件完整性校验；仅用于评估，尚未接入任何生产场景或模型配置。

决策：先选择当前三类最高负载的静态建筑模型生成独立减面副本，不覆盖 FBX/GLB，不修改 `.import`、`.tscn`、`.tres` 或运行时引用。使用 Godot 内置 meshoptimizer 简化索引，将 70%、50%、30% 三档简化结果提升为各自基础网格，并压缩未引用顶点，因此三角面与顶点缓冲都真实减少，不是只改变 LOD 切换距离。材质、UV、法线、节点变换和源场景层级沿用原模型。

| 模型 / 参数 | 修改前（原模型） | 70% 评估档 | 50% 评估档 | 30% 评估档 |
|---|---:|---:|---:|---:|
| 沙漠城堡三角面 | 999,102 | 699,370 | 499,550 | 299,730 |
| 沙漠城堡顶点 | 616,061 | 461,328 | 355,061 | 241,756 |
| 三级箭塔三角面 | 998,471 | 698,929 | 499,235 | 299,541 |
| 三级箭塔顶点 | 610,263 | 454,259 | 348,640 | 234,177 |
| 钉锤 8 三角面 | 598,066 | 418,646 | 299,032 | 179,418 |
| 钉锤 8 顶点 | 419,168 | 323,410 | 254,905 | 177,860 |
| `NORMAL_DEVIATION_THRESHOLD` | 无程序减面 | 1.0 | 1.0 | 1.0 |
| 生产资源引用 | 原 FBX/GLB | 未接入 | 未接入 | 未接入 |

输出体积（不含共享纹理）：沙漠城堡为 20.33 / 15.20 / 9.89 MB，三级箭塔为 20.13 / 15.03 / 9.69 MB，钉锤 8 为 13.43 / 10.23 / 6.81 MB。输出 `.scn` 继续引用原材质和纹理，三个档位之间不会复制纹理文件。

新增文件：

- `tools/performance/model_decimation/generate_decimation_preview.gd`
- `tools/performance/model_decimation/inspect_imported_mesh_lods.gd`
- `tools/performance/model_decimation/decimation_comparison_viewer.gd`
- `outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/` 下的 9 个 `.scn`、3 张对比图、`compare_all.tscn`、`manifest.json` 与 `README.md`
- `Docs/PERFORMANCE_OPTIMIZATION.md`

验证：9 个减面场景均可由 Godot 4.7.1 重新加载，并在真实 OpenGL Compatibility / RTX 2060 渲染器下完成原始、70%、50%、30% 四档同屏截图。`manifest.json` 记录的 3 个源模型和对应 `.import` 在每组生成前后 SHA-256 完全一致，`source_integrity_unchanged=true`，错误数为 0。对比场景仅载入评估副本，不写入项目主场景。

评估入口：在 Godot 中运行 `outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/compare_all.tscn`；数字键 `1`/`2`/`3` 切换模型，`W` 切换材质/线框模式，按住鼠标左键同步旋转四档，滚轮缩放。建议先用 50% 档检查近景轮廓、屋顶曲面、旗帜/尖刺、硬边高光和阴影；确认无明显差异后再考虑 30%。

回退：当前没有生产修改需要回退。若放弃本次试验，只删除 `outputs/model_decimation_preview/2026-08-16_meshoptimizer_eval/` 和 `tools/performance/model_decimation/` 即可；源模型、导入参数及现有场景不需要恢复。后续若决定接入，必须另开变更记录逐项替换资源引用，不能直接覆盖原模型。

### PERF-013：全模型 20% 程序减面批次

日期：2026-08-16
状态：已生成并完成 46/46 资源重载、结构、哈希与重点画面对比校验；仍为隔离副本，未接入生产资源引用。

决策：扫描 `res://assets` 下全部 FBX、GLB、GLTF、OBJ 与 DAE。原场景总三角面大于 5,000 时生成不超过 20% 的独立 `.scn`；小于或等于 5,000 时不处理。写实大树 `assets/greattree/realistic_tree_gltf/scene.gltf` 按用户要求明确排除，已确认批次内不存在其减面输出。源模型、`.import`、现有 `.tscn`、`.tres` 与项目配置均不覆盖。

| 参数 / 指标 | 修改前 | 20% 隔离批次 |
|---|---:|---:|
| 扫描模型文件 | — | 200 |
| `> 5,000` 候选 | — | 47 |
| 用户排除 | — | 1（写实大树） |
| 实际处理 | 0 | 46 |
| 阈值跳过 + 用户排除 | 0 | 154 |
| 失败 | — | 0 |
| 已处理模型总三角面 | 9,000,420 | 1,799,949（19.99850%） |
| 减少三角面 | — | 7,200,471（80.00150%） |
| 已处理模型总顶点 | 5,638,175 | 1,630,780（28.92390%） |
| 减少顶点 | — | 4,007,395 |
| 46 个输出场景体积 | — | 64.20 MB，不含共享纹理 |
| 生产资源引用 | 原 FBX/GLB/GLTF/DAE | 保持原引用，未接入副本 |

分类处理数量：`buildings=17`、`blocks=10`、`star=6`、`stuffs=5`、`projections=3`、`enemies=2`、`Ramp=1`、`moon=1`、`sun=1`。全部 46 个模型的前后面数、顶点数、实际比例和输出路径记录在 `outputs/model_decimation_20pct/2026-08-16_all_models_20pct/REPORT.md`；同目录 `manifest.json` 保存可机器读取的逐表面算法、结构统计和 SHA-256。

算法：43 个模型直接使用 Godot meshoptimizer 达到目标。大理石块、弩和钉子部分表面因断裂拓扑或属性缝导致 meshoptimizer 提前停止，启用第二级策略：大理石块使用保留源属性缝的体素聚类，弩与两个钉子子网格使用 `fast-simplification 0.2.0` QEM，并按源角点拆分 UV/法线缝后重新生成法线与切线。最终每个模型实际比例均不超过 20%。

验证：每个输出保存后立即从磁盘重新加载，节点数、MeshInstance 数、表面数、非空材质槽、Skeleton、AnimationPlayer、三角面和顶点数全部符合预期。46 组源模型及对应 `.import` 的生成前后 SHA-256 一致，独立复查为 46/46、哈希不匹配 0。骨骼模型 Stone Golem 在输出中仍为 1 个 Skeleton 与 1 个 AnimationPlayer。RTX 2060 / OpenGL Compatibility 下完成大理石块、弩、钉子的原版/20% 同屏截图；大理石块和钉子主体保持，弩的严格 20% 档近景轮廓与高光变化较明显，生产接入前需明确接受该取舍。

评估入口：运行 `outputs/model_decimation_20pct/2026-08-16_all_models_20pct/compare_fallback_models.tscn`，数字键 `1`/`2`/`3` 切换，`W` 切换线框，鼠标拖动同步旋转。全部处理与跳过清单见同目录 `REPORT.md`。

回退：当前未替换生产引用，不存在源资产回退动作。删除 `outputs/model_decimation_20pct/2026-08-16_all_models_20pct/` 即可移除全部 20% 派生场景、回退输入和对比图；工具脚本可单独保留或删除。正式接入必须作为后续独立变更记录，逐项替换引用并进行游戏内回归。

## 明确保留的效果

- `RuntimeSettings.depth_of_field_enabled` 默认值保持 `true`。
- 暂停菜单景深开关默认保持选中。
- 四套灯光档案的 SSAO 与 Glow 保持开启。
- 灯光颜色、能量、间接能量、曝光、饱和度、对比度、阴影开关和阴影贴图尺寸均未修改。
- 镜面可见性、视锥和正反面过滤逻辑未修改。

## 验证记录

| 日期 | 环境 | 检查项 | 结果 |
|---|---|---|---|
| 2026-08-11 | Godot 4.7.1 Headless | `performance_optimization_test.gd` | 35/35 通过；四套灯光档案、镜面预算、景深默认值和项目参数均符合本记录 |
| 2026-08-11 | Godot 4.7.1 Headless，生产 Level1 | 真实地形 MultiMesh | 3 个批次覆盖 255 个地形体素，逐体素旧节点为 0 |
| 2026-08-11 | Godot 4.7.1 Headless | `terrain_runtime_test.gd` | 47/47 通过，包含批处理变换与旧路径回退测试 |
| 2026-08-11 | Godot 4.7.1 Headless | `runtime_ui_batch3_test.gd` | 104/104 通过；4K→1440p、4K→1080p、原生比例和设置持久化均通过 |
| 2026-08-11 | Godot 4.7.1 Headless | `copy_mirror_test.gd` | 143/143 通过 |
| 2026-08-11 | Godot 4.7.1 Headless | `miniature_dof_test.gd` | 27/27 通过；景深默认开启、关闭与重新开启均通过 |
| 2026-08-11 | Godot 4.7.1 Headless | 项目主场景启动 | 退出码 0，无脚本解析或资源加载失败 |
| 2026-08-11 | Godot 4.7.1 Headless | 20 个地形导入 sidecar | 全部确认 `process/size_limit=2048` |
| 2026-08-12 | PowerShell 审计 + Godot 4.7.1 自动重导入 | 176 张 4K+ 世界纹理 | 176/176 导入上限为 2048；缓存无缺失且无单个超过 6 MB；S3TC 合计约 492.9 MB |
| 2026-08-12 | Godot 4.7.1 Headless | `performance_optimization_test.gd` | 45/45 通过；含批处理脚本、回退清单、排除目录与 176 个导入上限断言 |
| 2026-08-12 | Godot 4.7.1 Headless，完整选关/战斗往返 | `manual_wave_and_level_flow_test.gd` | 37/37 通过；两个方向都存在 2 帧空内容释放屏障，新旧重型世界不同时驻留 |
| 2026-08-12 | Godot 4.7.1 Headless，生产 Level1 | 塔/镜子放置预览迁移 | `performance_optimization_test.gd` 53/53；塔、镜子与反射 `SubViewport` 跨位置保持同一实例 |
| 2026-08-12 | Godot 4.7.1 Headless | 预览合法性与复制镜回归 | `path_placement_connectivity_test.gd` 35/35；`copy_mirror_test.gd` 144/144 通过 |
| 2026-08-12 | PowerShell + Godot 4.7.1 Headless 导入 | 185 张 2K+ 世界纹理性能档 | 185/185 上限为 1024；缓存 519.2→135.9 MB，减少 73.8% |
| 2026-08-12 | Godot 4.7.1 Headless | `performance_optimization_test.gd` | 64/64 通过；性能档参数、独立回退基线、sidecar 和压缩缓存断言均通过 |
| 2026-08-16 | Godot 4.7.1 Headless + OpenGL Compatibility / RTX 2060 | 程序减面隔离评估 | 3 个代表模型 × 3 档共 9 个场景可加载；三角面精确为 70%/50%/30%；源模型及 `.import` 前后 SHA-256 一致；完成 3 张四档同屏截图 |
| 2026-08-16 | Godot 4.7.1 Headless + OpenGL Compatibility / RTX 2060 | 全模型 20% 程序减面 | 扫描 200，处理 46，跳过 154，失败 0；总三角面 9,000,420→1,799,949；46/46 输出重载及源/.import 哈希通过；写实大树排除；3 个受约束模型完成同屏截图 |
| 2026-08-11 | Headless 全量回归（新增性能专项加入列表前） | 54 个测试套件 | 48 个通过；6 个因当前工作区既有战斗参数、树叶阴影素材、镜面表面偏移或模型空材质诊断失败，见下方说明 |
| 2026-08-11 | 待执行 | 4K 全屏输出、2K 内部渲染、UI 清晰度 | 需要关闭编辑器后以单独导出版本验证 |
| 2026-08-11 | 待执行 | 四套灯光档案截图对比 | 需要在真实渲染器中验证 SSIL 关闭后的差异 |
| 2026-08-11 | 待执行 | 含 3 面及以上镜面的平均/P95/P99 帧时间与显存 | 需要在单独导出版本中验证 |

全量回归中的非性能基线问题：

- `crossbow_tower_test.gd`、`missile_tower_test.gd`：当前箭塔等级的 airborne-first 索敌参数与测试期望不同。
- `mace_tower_test.gd`：当前三级钉头锤额外穿透参数与测试期望不同。
- `lighting_display_case_test.gd`：当前真实树模型缺少测试期望的叶片 Alpha Scissor 阴影材质。
- `mirror_placement_cooldown_test.gd`：两个正式镜面资源的 `reflection_surface_offset_ratio=1.0`，测试仍期望 `0.78`；本次新增的 256/128、4 帧、单帧 1 面四组性能断言均通过。
- `manual_wave_and_level_flow_test.gd`：业务断言 26/26 通过，但 Headless Dummy Renderer 在既有 `ModelAssetDefinition.validate_configuration()` 释放导入模型时报告空材质。隔离测试中关闭和开启 MultiMesh 都产生相同的 17 条诊断，确认不是 PERF-005 引入。

## 后续变更模板

```markdown
### PERF-XXX：标题

日期：YYYY-MM-DD
状态：计划中 / 已实施 / 已验证 / 已回退。

决策：说明为什么修改，以及明确不修改什么。

| 参数 | 修改前 | 修改后 |
|---|---:|---:|
| 示例 | 旧值 | 新值 |

修改文件：列出精确路径。

验证：记录测试环境、场景、平均/P95/P99 帧时间、显存和画面对比。

回退：给出参数回退值、功能开关或提交引用。
```
