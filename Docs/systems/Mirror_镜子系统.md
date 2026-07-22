# 镜子系统 · Mirror（核心）

> 模块职责：管理复制镜、反射镜两类边建筑的放置、朝向、镜像几何与生效逻辑。
> 关键架构、函数索引和参数必须与实现同步维护。
> 状态：M5 复制镜与镜面/虚像表现优化已实现并通过 Godot 4.7.1 回归（2026-07-21）；会改变激光方向的反射镜仍属于 M6。

---

## 一、通用边建筑规则

1. 镜子严格贴合地块边：六边形有 6 种边方向，四边形有 4 种边方向。
2. 一条规范化物理边只能存在一个实体边建筑。复制镜、反射镜、边屏障共享同一边占用表。
3. 只允许放在两个有效地块之间，且两侧地块都必须允许放置边建筑。
4. 放置时需要通过建筑附近敌人、资源和镜子上限校验。
5. 镜子有正反两个生效面。`R` 只在两侧之间翻面，不改变所在物理边。
6. 镜面所在边的直线是所有镜像计算的对称轴；点、方向和攻击线均使用同一套线反射公式。
7. 镜子可被选中、翻面和删除；复制镜不参与升级、耐久、攻击或路径阻挡。
8. 镜子本身永远不可复制，任何其他边建筑也不属于 M5 的整格复制内容。

---

## 二、复制镜 · CopyMirror

### 2.1 严格机制定义

复制镜从当前生效侧相邻格开始，沿镜面法线背离镜子的方向逐格扫描，找到第一格包含“可复制内容”的地块。该地块是唯一源格；一面镜子复制源格内的全部地块绑定内容，并把它们投影到关于镜面轴对称的目标格。

- “最近”只比较法线射线上的格，不做扇形、全图距离或跨方向搜索。
- 普通空地、敌人和镜子不算可复制内容，扫描会继续向外。
- 若最近源格的内容消失或更近处出现内容，镜子动态重算源格与全部投影。
- 一面镜子只选择一个源格，但源格中可同时包含多项内容，必须整格复制，不能只挑其中一个对象。
- 目标格必须在地图内；超出地图时该镜子不生成投影。

### 2.2 M5 可复制内容

源格可包含：

- 实体格建筑：箭塔、激光塔、格屏障及后续实现复制契约的格建筑。
- 关卡地块元素：尖刺、空洞、大石头及后续实现复制契约的陷阱、障碍和机关。
- 既有投影：允许继续被另一面复制镜复制。

以下内容不可复制：

- 复制镜、反射镜、边屏障及所有其他边建筑。
- 敌人、出生点、路径编号、据点、纯地形颜色/高度等非玩法内容。
- 没有实现复制契约的运行时节点。

### 2.3 投影叠加与占位

- 默认 `projection_ignores_occupancy = true`：投影不写入 `TileCellData.occupant`，不占实体建筑格位。
- 同一格可以同时存在多个投影，也可以与实体建筑或地块元素重叠。
- 关闭开关后，目标格存在实体格建筑或先生成的投影时，该镜子的整组投影不生成；地块元素本身不视为实体占位。
- 投影不计入建筑上限、镜子上限，不消耗资源，也不能被独立选中、升级、旋转或删除。
- 源对象或依赖镜链失效时，对应投影立即移除。

### 2.4 递归复制

- 投影可再次作为源内容复制，镜子不可复制。
- `copy_chain_max` 默认 4，表示从实体源到最终投影允许的最大镜链深度。
- 每项投影记录镜子谱系；同一面镜子不能再次出现在自己的谱系中，用于阻断循环。
- 多面镜的计算必须稳定且与帧率无关；同一输入得到相同投影集合。

### 2.5 塔投影

- 无独立 AI、无独立索敌、无独立冷却和动画时钟。
- 原塔发起一次投射物或激光攻击时，所有有效投影在同一逻辑时刻复制该攻击。
- 攻击起点、目标点、固定朝向和激光线段通过投影的复合镜像变换获得。
- 投影不重新校正敌人，因此镜像位置没有敌人时允许打空。
- 投影无独立转向决策；实体建筑因目标追踪或手动逻辑朝向发生任何模型姿态变化时，既有投影在原节点上实时同步完整姿态。
- 投射物投影仍按原塔等级参数使用飞行速度、尺寸、伤害与空中目标开关；飞向镜像后的固定目标点，而不是独立追踪目标。
- 激光投影按镜像线段逐 tick 结算，继承原塔等级的持续伤害和空中目标开关。

### 2.6 屏障投影

- 屏障投影在目标格参与路径阻挡和敌人攻击目标解析。
- 投影没有独立耐久池。敌人对投影造成的伤害转发到原屏障；原屏障死亡后全部关联投影消失。
- 最大耐久、回血、脱战时间、反伤比例、等级参数和 `affects_airborne` 均继承原屏障。
- 同格多个屏障投影按稳定顺序提供当前阻挡目标；前一投影失效后才能解析到下一项。

### 2.7 地块元素投影

- 尖刺投影：敌人进入或停留在投影格时，执行与源尖刺相同的持续伤害；多项尖刺投影按独立效果叠加。
- 空洞投影：敌人仅在源空洞的周期检查时刻仍在投影格上才可能被吞噬；真实格、直接投影和递归投影共享根源格的容量、恢复和吞噬检查时钟。
- 大石头投影：目标格加入动态寻路阻挡层；敌人在阻碍前一格对应路径段先触发既有换路逻辑，无可用路径时攻击该投影。同格普通屏障保持更高的直接攻击优先级；屏障摧毁导致投影重建后，敌人必须重新解析新石头代理，不得穿过。投影没有独立耐久，直接/递归投影的伤害都转发给真实源石头；源石头耐久归零后全部关联投影消失，实体镜子保留。
- 所有地块效果继承源资源参数与 `affects_airborne`。空中敌人是否受影响完全由源效果开关决定。
- 投影不修改关卡原始 `TileCellData`，而通过独立覆盖层参与效果、导航和阻挡查询。

### 2.8 放置预览

选择复制镜并悬停合法边时，必须同时显示：

- 镜子本体虚影和当前生效侧。
- 当前扫描得到的源格与目标格。
- 源格内将被复制的内容种类列表。
- 每项投影在目标格的青蓝色半透明虚影。

没有找到源格或目标格越界时仍允许放置镜子，但预览必须显示明确警告。按 `R` 翻面后预览立即重算。

### 2.9 视觉规范

- 复制镜的玩法生效侧仍是唯一事实源，决定最近源格、投影方向和顶部蓝色标识。默认仅在表现层启用双观察侧镜面：同一个反射 Quad 根据主相机所在侧贴到朝向观察者的实体表面，因此拉远视角跨过镜面无限平面时不会退回镜体底色，也不会增加第二个反射视口。可用 `reflection_two_sided_visual` 恢复仅生效侧可见。
- 镜面相机的位置与朝向由主相机关于镜面轴严格反射得到，并复制主相机投影和宽高比；反射相机重建为右手基底后会交换屏幕 X 手性，因此镜面 Shader 用 `vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)` 做一次精确横向补偿。补偿后镜前右侧地块在镜中仍显示为右侧，不改纵向顺序。镜面和实体背板位于独立可见层，反射相机排除该层以同时阻断镜中镜递归与镜体蓝色自遮挡。
- 实际镜面刷新由 `MirrorManager` 轮询调度；镜面中心或任一矩形角点处于主相机视锥时均可刷新，并限制刷新间隔与每帧上限。放置预览使用独立低分辨率。
- 建筑投影创建 `Building._visual_root` 的无行为快照，之后每帧同步源的视觉根变换、子 `Node3D` 姿态、可见性和 `Skeleton3D` 骨骼姿态，不重建投影节点。地块元素投影通过 `TileRenderer.create_tile_content_visual_snapshot()` 只复用石头、尖刺、空洞等地块内容几何。地表顶面、侧壁、高度色、路径色和路面色均属于目标关卡基底，不被复制。
- 所有视觉快照按 payload 的完整镜链做严格仿射反射。不得用圆盘、圆柱、方块等独立几何替代地块/建筑，也不得用位移、缩放或垂直错层拆开重叠虚像。
- 投影保留源内容主色，叠加强度可调的半透明、发光与边缘高光；同格多项投影只通过不同强调色、同心标识环和悬停标签区分，标识不参与玩法也不替代源几何。
- 同格透明投影按稳定的叠放序号分配 `render_priority`，且不写入深度缓冲；重建时先隐藏旧投影再延迟释放，避免新旧几何在同一帧闪烁。
- 悬停投影格时 HUD 与世界标签显示同格虚像数量、类型、序号和复制链深度。
- 投影不播放独立待机或攻击动画；攻击表现由原件事件同步驱动。

---

## 三、反射镜 · ReflectMirror（M6 设计保留）

1. 激光命中反射镜生效面时按 `r = d - 2(d·n)n` 改向。
2. 背面模式可配置为 `PASS`（穿过）或 `BLOCK`（阻挡）。
3. 激光可多次反射，`reflect_max` 默认 8，用于阻断镜间闭环。
4. 镜子长度等于整条地块边；交点必须在线段范围内，端点命中按闭区间处理。
5. 建筑不阻挡激光；障碍、隆起地形、据点、边界及 `BLOCK` 背面可以终止光路。
6. 近垂直入射可用 `perp_offset` 做微小切向偏移，避免入射线和反射线完全重叠。

M5 不实现反射镜。共享边占用和镜像数学必须为 M6 保留接入点。

---

## 四、参数表（均需 `@export` 或资源字段）

| 参数 | 当前正式资源值 | 归属 | 说明 |
|---|---:|---|---|
| `mirror_cap` | 6 | ResourceManager | 实体镜子总上限，投影不计数 |
| `mirror_cost` | 80 | CopyMirrorDefinition | 放置消耗 |
| `mirror_refund` | 60 | CopyMirrorDefinition | 删除返还 |
| `card_icon` | 空 | CopyMirrorDefinition | M6 独立复制镜卡片图；为空时使用“镜”字灰盒。 |
| `mirror_height_ratio` | 2.00 格 | CopyMirrorDefinition | 镜框、实时镜面、标识和操作锚点共用高度 |
| `projection_ignores_occupancy` | true | CopyMirrorDefinition | 投影是否忽略实体/投影占位并允许叠加 |
| `copy_chain_max` | 6 | CopyMirrorDefinition | 最大镜链深度 |
| `reflection_enabled` | true | CopyMirrorDefinition | 是否启用复制镜生效面的实时世界反射 |
| `reflection_two_sided_visual` | false | CopyMirrorDefinition | 是否让同一反射面根据观察者所在侧切换实体表面；当前资源只显示玩法生效侧 |
| `reflection_surface_offset_ratio` | 0.78 | CopyMirrorDefinition | 镜面相对镜体厚度的外推比例；大于半厚度以避免远距离深度遮挡 |
| `reflection_resolution` | 512 | CopyMirrorDefinition | 正式镜面的水平渲染分辨率 |
| `reflection_preview_resolution` | 256 | CopyMirrorDefinition | 放置预览镜面的水平渲染分辨率 |
| `reflection_update_interval_frames` | 2 | CopyMirrorDefinition | 同一调度轮次的帧间隔 |
| `reflection_max_updates_per_frame` | 2 | CopyMirrorDefinition | 每次调度最多刷新的可见镜面数 |
| `mirror_reflectivity` | 1.00 | CopyMirrorDefinition | 反射画面相对镜面底色的混合比例 |
| `mirror_surface_tint` | 淡蓝白 | CopyMirrorDefinition | 生效面反射画面的色调 |
| `mirror_back_face_color` | 深蓝黑 | CopyMirrorDefinition | 非生效镜背颜色 |
| `projection_alpha` | 0.76 | CopyMirrorDefinition | 正式投影透明度；预览在此基础上衰减 |
| `projection_tint` | 青蓝 | CopyMirrorDefinition | 投影颜色叠加 |
| `projection_tint_strength` | 0.24 | CopyMirrorDefinition | 保留源主色时的强调色混合强度 |
| `projection_emission_energy` | 2.8 | CopyMirrorDefinition | 虚像与标识的发光强度 |
| `projection_rim_alpha` | 0.42 | CopyMirrorDefinition | 轮廓边缘高光强度 |
| `projection_ring_spacing_ratio` | 0.045 格 | CopyMirrorDefinition | 同格虚像标识环的半径间隔，不移动源几何 |
| `projection_ring_thickness_ratio` | 0.022 格 | CopyMirrorDefinition | 标识环粗细 |
| `mirror_side_default` | from | CopyMirrorDefinition | 新镜子默认生效侧 |
| `reflect_max` | 8 | ReflectMirror（M6） | 单束激光最大反射次数 |
| `back_face_mode` | PASS | ReflectMirror（M6） | 背面穿过/阻挡 |
| `perp_offset` | 0.05 | ReflectMirror（M6） | 近垂直反射视觉偏移 |

---

## 五、关键架构

```text
EdgeOccupancyRegistry
  └─ 统一登记实体边建筑，供 BuildingManager / MirrorManager 查询

MirrorManager
  ├─ 放置、翻面、删除、选择与预览
  ├─ 沿法线扫描最近源格
  ├─ 固定点迭代生成有限镜链
  └─ 向战斗、阻挡、导航、地块效果暴露只读投影查询

CopyMirror
  ├─ edge_id / from_cell / to_cell / active_side
  └─ MirrorReflectionView（共享世界屏幕对齐反射，单视口按观察侧切换镜面）

MirrorProjection
  ├─ payload / lineage / composed_transform
  ├─ Building 真实视觉快照 / TileRenderer 地块内容快照
  ├─ 不写入地块 occupant
  └─ 屏障/石头共享源伤害转发与玩法代理
```

模块协作规则：

- GridManager 负责四/六边形的边法线射线与镜像格对，Mirror 不读取具体坐标布局。
- BuildingManager 只通过注入的边占用表和投影阻挡查询协作。
- TileManager 与 TileEffectSystem 只通过注入的投影覆盖查询协作，不持有 Mirror 节点。
- 塔只发出“原件攻击事件”；MirrorManager 负责生成同步投影攻击，塔不直接依赖镜子模块。
- 投影内部以稳定 MirrorCopyPayload 描述来源和变换；当前 MirrorManager 仍显式识别 Building 与 TileEffect，统一 `ICopyable`/注册表属于架构治理批次 5，不能把现状描述为已完全开放扩展。
- Main 只注入主相机和 `TileRenderer.create_tile_content_visual_snapshot` Callable；MirrorManager 不持有 TileRenderer 具体类型。

### 实现文件

| 文件 | class_name / 基类 | 职责 |
|---|---|---|
| `scripts/shared/EdgeOccupancyRegistry.gd` | `EdgeOccupancyRegistry` / `RefCounted` | 镜子、边屏障共用的规范化物理边占用表。 |
| `scripts/mirror/CopyMirrorDefinition.gd` | `CopyMirrorDefinition` / `Resource` | 经济、链深、占位开关与虚像表现参数，并通过 `validate_configuration()` 返回完整配置错误。 |
| `scripts/mirror/CopyMirror.gd` | `CopyMirror` / `Node3D` | 实体镜面边节点、生效侧和程序化表现。 |
| `scripts/mirror/MirrorReflectionView.gd` | `MirrorReflectionView` / `Node3D` | 生效面的共享世界 SubViewport、屏幕对齐反射与反射相机横向手性补偿。 |
| `scripts/mirror/MirrorCopyPayload.gd` | `MirrorCopyPayload` / `RefCounted` | 稳定来源、镜子谱系和复合反射变换。 |
| `scripts/mirror/MirrorProjection.gd` | `MirrorProjection` / `Node3D` | 真实源内容快照、源模型实时姿态同步、稳定透明渲染顺序、严格反射、屏障与地块效果代理。 |
| `scripts/mirror/MirrorProjectionProjectile.gd` | `MirrorProjectionProjectile` / `Node3D` | 不追踪的固定镜像落点投射物。 |
| `scripts/mirror/MirrorManager.gd` | `MirrorManager` / `Node3D` | M5 唯一入口，管理放置、预览、固定点镜链和跨模块查询。 |
| `scripts/tile/TileObstacleRuntime.gd` | `TileObstacleRuntime` / `Node3D` | 镜像石头最终转发到的真实逐格耐久源。 |
| `scripts/ui/MirrorActionPanel.gd` | `MirrorActionPanel` / `Control` | 跟随选中镜子的删除/翻面按钮。 |
| `resources/mirrors/CopyMirror.tres` | `CopyMirrorDefinition` | 默认 M5 参数资源。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | `create_copy_visual_snapshot` 创建无行为建筑视觉，`sync_copy_visual_snapshot` 向既有快照同步完整实时姿态。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | `create_tile_content_visual_snapshot` 沿正常渲染几何路径生成不含基底的石头/尖刺/空洞快照。 |
| `tests/copy_mirror_test.gd` | `SceneTree` | 104 项双网格、玩法联调、屏障/石头投影重叠优先级、空洞共享容量/深度、横向镜面顺序、追踪/固定朝向、完整姿态同步、生命周期与远距离反射回归。 |

## 六、函数索引

| 入口 | 签名 | 职责 |
|---|---|---|
| `GridManager.get_mirror_cell_pair` | `(from_cell, edge_index, active_from_side, distance_from_edge) -> Dictionary` | 在 Grid 内封装四/六边形法线源格/目标格对。 |
| `MirrorManager.place_copy_mirror` | `(from_cell, edge_index, active_from_side = null) -> CopyMirror` | 完成校验、扣费、共享边登记和投影重建。 |
| `MirrorManager.validate_placement` | `(from_cell, edge_index, check_economy = true) -> Dictionary` | 返回边界、权限、占用、敌人和经济校验结果。 |
| `CopyMirrorDefinition.validate_configuration` | `() -> Array[String]` | 校验身份、经济、链深、镜面预算、颜色与全部虚像表现范围。 |
| `MirrorManager.rebuild_now` | `() -> void` | 从实体来源计算稳定有限镜链并重建投影覆盖层。 |
| `MirrorManager.get_projected_effects` | `(cell) -> Array[TileEffect]` | 向 TileEffectSystem 提供同格可叠加效果。 |
| `MirrorManager.get_projected_effect_bindings` | `(cell: Vector3i) -> Array[Dictionary]` | 返回 `{effect, source_cell, state_key}` 列表，使有状态地块投影归并到真实根源。 |
| `MirrorManager.blocks_enemy_navigation` | `(cell, target = null) -> bool` | 向 TileManager 提供投影岩石阻断。 |
| `MirrorManager.resolve_projected_blocker` | `(cell, target = null) -> Node` | 向 BuildingManager 提供投影屏障代理。 |
| `MirrorManager.resolve_projected_navigation_blocker` | `(cell, target = null) -> Node` | 向 TileManager 提供可攻击的投影石头代理，保持石头“先换路”与屏障“直接攻击”的入口分离。 |
| `MirrorManager.update_preview` / `flip_preview` | `(from_cell, edge_index) -> bool` / `() -> bool` | 构建镜面、源格/目标格信息和投影虚影，翻面后重算。 |
| `MirrorManager.set_reflection_camera` | `(camera: Camera3D) -> void` | 注入主相机并为已有/预览镜面建立共享世界反射。 |
| `MirrorManager.set_tile_visual_snapshot_resolver` | `(resolver: Callable) -> void` | 注入不含地形基底的地块内容快照工厂，保持 Mirror/Tile 模块边界。 |
| `MirrorManager.set_inspected_cell` | `(cell: Variant = null) -> void` | 切换同格虚像悬停标签，不移动任何虚像几何。 |
| `MirrorCopyPayload.copy_through` | `(mirror_id, target_cell, axis_start, axis_end) -> MirrorCopyPayload` | 追加谱系与镜像轴，产生下一层不可变语义 payload。 |
| `MirrorCopyPayload.transform_point` | `(point) -> Vector3` | 按谱系顺序应用复合镜像，供同步攻击使用。 |
| `MirrorCopyPayload.get_composed_transform` / `transform_transform` | `() -> Transform3D` / `(source_transform: Transform3D) -> Transform3D` | 把点反射谱系组合为仿射变换，并严格作用到源视觉姿态。 |
| `Building.create_copy_visual_snapshot` | `() -> Node3D` | 复制当前真实视觉，剥离标签、音频、脚本和独立动画节点。 |
| `Building.sync_copy_visual_snapshot` | `(snapshot: Node3D) -> bool` | 把当前子节点与骨骼姿态同步到既有无行为快照，不启动独立动画时钟。 |
| `MirrorProjection.sync_source_visual_pose` | `() -> bool` | 不重建投影，先同步源模型姿态，再将 payload 的全部镜轴组合变换作用于视觉根。 |
| `MirrorProjection.take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 把屏障或石头投影承伤转发到 payload 的真实根源耐久。 |
| `TileRenderer.create_tile_content_visual_snapshot` | `(cell: Vector3i) -> Node3D` | 复用正常地块内容几何函数，只生成障碍与元素快照，不含地表基底。 |
| `MirrorReflectionView.request_refresh` | `() -> bool` | 镜面矩形进入视锥时按当前观察侧更新实体表面与反射相机，并请求 SubViewport 单帧刷新。 |
| `CopyMirror.get_reflection_viewport` | `() -> SubViewport` | 返回屏幕对齐反射目标，供调试与回归检查宽高比。 |
| `CopyMirror.refresh_visual` | `() -> void` | Definition 表现参数变化时重建镜框、镜面目标与当前生效面。 |
| `EdgeOccupancyRegistry.try_register` / `unregister` | `(edge_id, occupant) -> bool` / `(edge_id, expected = null) -> bool` | 原子登记/释放物理边。 |

## 七、已知限制

- M5 只实现复制镜；反射镜及反射激光在 M6 实现。
- 最近源格仅沿镜面法线离散扫描，不支持任意角度射线穿格。
- 投影攻击忠实复制原攻击，允许因镜像空间无目标而打空。
- 屏幕对齐方案不提供任意形状镜面的逐像素斜裁面；当前复制镜均为矩形边建筑，镜面外区域由实体 Quad 自身裁切。
- 为阻止递归和镜体自遮挡，所有反射相机不渲染镜面与镜体背板；镜中不会出现其它镜子的反射画面或蓝色背板，也不会出现无限镜廊。
