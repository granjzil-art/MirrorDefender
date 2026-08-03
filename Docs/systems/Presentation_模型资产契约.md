# 模型资产契约 · Model Asset

> 实现状态：现运行时已接入 Terrain 平地/斜坡、Stuff、建筑等级、敌人和三类投射物；旧资产直接按本契约解释，不保留手工 Transform 对齐分支。

## 职责

`ModelAssetDefinition` 是运行时三维美术的共享数据契约。玩法模块只持有这一资源，不直接解释 FBX/GLTF 或具体模型层级；未配置资产或实例化失败时，各模块继续使用原有灰盒表现。

## 分类 / 做法

- **统一字段**：每份资产包含 `scene: PackedScene`、`runtime_scale: Vector3` 和可选对齐锚点。
- **统一变换链**：运行时节点树固定为 `玩法放置 -> ModelAssetRoot(runtime_scale) -> ModelAlignment -> 美术场景`。美术场景原 Transform 会被包围盒计算吸收，不再担任世界高度对齐参数。
- **接地模式**：建筑、Stuff 和敌人把模型的“底部中心”对齐到逻辑放置点，保留美术尺寸与 `runtime_scale`。
- **拟合模式**：投射物将完整可视包围盒逐轴精确拟合到玩法 AABB；Terrain 只按目标 XZ 脚印计算一个等比 Scale，Y 轴使用同一倍率，禁止压缩或拉伸模型高度。两种模式的运行时包装节点都归一为 `Vector3.ONE`。
- **独立配置**：多个 `ModelAssetDefinition` 可引用同一个 `PackedScene`，但保存不同 `runtime_scale`。建筑三个等级因此可以共用模型而采用不同尺寸。
- **节点树约束**：模型场景根节点必须继承 `Node3D`，任一父节点下不得存在同名兄弟节点；资源校验会实际实例化并递归检查节点树。GLTF 建议由轻量 `.tscn` Prefab 直接继承，不要在继承场景中再次内嵌同名 Mesh。
- **自动包围盒**：未配置锚点时，递归合并 `MeshInstance3D` / `MultiMeshInstance3D` 的编辑时 AABB，包含节点自身位移、旋转和 Scale。
- **灰盒回退**：资产为空、无法实例化、根类型错误或无有效三维可视包围盒时，运行时返回 null，由所属模块生成原灰盒。
- **旧资源兼容**：建筑等级、敌人和地块元素保留隐藏的旧 `visual_scene` 存储字段；新资源必须使用 `model_asset` / `element_model_asset`。

## 参数入口

| 使用者 | 字段 | 作用 |
|---|---|---|
| `TerrainDefinition` | `flat_model_asset` | 一个体素层的平地模型；1～4层运行时重复堆叠。 |
| `TerrainDefinition` | `ramp_1_to_1_model_asset`～`ramp_1_to_4_model_asset` | 跨1～4格且升高一层的完整斜坡模型。 |
| `StuffDefinition` | `model_asset` | 石头、树、尖刺、黑洞等独立关卡元素模型。 |
| `LevelResource` | `tile_model_asset` | 本关全部地块基底的默认模型。 |
| `TileDefinition` | `terrain_model_asset` | 指定地块定义对关卡默认基底模型的覆盖。 |
| `TileDefinition` | `element_model_asset` | 尖刺、空洞、石头或可破坏内容层模型。 |
| `BuildingLevelStats` | `model_asset` | 本建筑当前等级模型。 |
| `BuildingLevelStats` | `projectile_model_asset` | 本等级建筑投射物模型；复制体投射物沿用同一配置。 |
| `EnemyDefinition` | `model_asset` | 本敌人模型。 |
| `EnemyDefinition` | `projectile_model_asset` | 本敌人的远程投射物模型。 |

每个字段中新建或引用一个 `ModelAssetDefinition`，再设置 `Scene` 与 `Runtime Scale`。例如三级箭塔可让三个等级引用同一场景，用不同 `Runtime Scale` 改变接地模型尺寸。Terrain/投射物不需要用此字段对齐尺寸，保持 `(1,1,1)` 即可。Terrain 模型须按一个体素层的原始比例制作；当前契约固定 `LayerHeight = GridCellSize`。

### Alignment Overrides

| 字段 | 用法 |
|---|---|
| `ground_anchor_path` | 可选接地点 `Node3D` 路径。适用于底部包含影子、特效或不应计入接地面的模型。 |
| `fit_min_anchor_path` / `fit_max_anchor_path` | 可选的拟合最小/最大点，必须成对配置。适用于斜坡模型带外伸装饰、但只希望主体对齐逻辑尺寸的情况。 |
| 节点 Meta `exclude_from_model_bounds = true` | 自动包围盒忽略该节点自身 Mesh；子节点仍会递归检查。 |

锚点全部留空是默认且推荐的资产迁移方式：旧场景在不改 `.tscn` Transform 的情况下直接进入自动对齐链。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/presentation/ModelAssetDefinition.gd` | `ModelAssetDefinition` / `Resource` | 模型场景、附加运行时 Scale、实例化和配置校验的共享契约。 |
| `scripts/presentation/ModelFitTransform.gd` | `ModelFitTransform` / `RefCounted` | 提供逐轴精确拟合和保持模型比例的等比拟合变换。 |
| `scripts/terrain/TerrainDefinition.gd` | `TerrainDefinition` / `Resource` | 平地体素与四档多格斜坡模型槽。 |
| `scripts/stuff/StuffDefinition.gd` | `StuffDefinition` / `Resource` | 独立Stuff模型槽和旧`visual_scene`兼容包装。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | 基底/内容资产实例化、灰盒批次回退和镜像快照。 |
| `scripts/terrain/TerrainRenderer.gd` | `TerrainRenderer` / `Node3D` | 按层实例化单体素平地模型、按坡长实例化整段斜坡模型及灰盒回退。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 读取当前等级建筑模型和建筑投射物模型。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 实例化 EnemyUnit 注入的敌人模型，失败时生成胶囊灰盒。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 建筑投射物模型或短方块回退。 |
| `scripts/combat/EnemyProjectile.gd` | `EnemyProjectile` / `Node3D` | 敌人投射物模型或短方块回退。 |
| `scripts/mirror/MirrorProjectionProjectile.gd` | `MirrorProjectionProjectile` / `Node3D` | 复用源建筑投射物模型，并叠加虚像发光层。 |
| `tests/model_asset_contract_test.gd` | 无 / `SceneTree` | 共享契约、所有接入链路、Scale 相乘和生产箭塔迁移回归。 |

### 数据流

```text
*.tres owner
  -> ModelAssetDefinition(scene, runtime_scale)
  -> grounded owner: instantiate_grounded_model()
       -> bottom-center -> gameplay surface origin
       -> preserves runtime_scale
  -> fitted owner: instantiate_fitted_model(target_bounds, preserve_proportions)
       -> projectile: complete authored bounds -> exact gameplay AABB
       -> Terrain: XZ footprint -> uniform XYZ scale; align top/bottom in Y
       -> normalizes runtime wrapper to Vector3.ONE
  -> runtime owner adds wrapper
  -> null/invalid -> owner-specific greybox fallback

LevelResource legacy tile model / TerrainDefinition flat+ramp assets
  -> LevelContentMigrationAdapter effective Terrain snapshot
  -> TerrainRenderer per-layer flat model / one full-width ramp model

TileDefinition.element_model_asset
  -> TileRenderer content model
  -> create_tile_content_visual_snapshot
  -> MirrorProjection exact reflected snapshot

TerrainDefinition.flat_model_asset + ramp_1_to_N_model_asset
  -> TerrainRenderer 体素堆叠/整段斜坡实例化

StuffDefinition.model_asset
  -> 后续 StuffRenderer 实例化
  -> 按格内容快照 -> MirrorProjection（不包含Terrain/Ramp）

BuildingLevelStats.projectile_model_asset
  -> CombatManager -> Projectile
  -> Building copy_attack_triggered
  -> MirrorManager -> MirrorProjectionProjectile (same asset)
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `ModelAssetDefinition.is_configured` | `() -> bool` | 返回是否配置了 PackedScene。 |
| `ModelAssetDefinition.instantiate_model` | `(instance_name: StringName = &"ModelAssetRoot") -> Node3D` | 仅包装原始模型；供没有逻辑对齐语义的通用表现使用。 |
| `ModelAssetDefinition.instantiate_grounded_model` | `(instance_name: StringName = &"ModelAssetRoot") -> Node3D` | 将指定锚点或自动底部中心对齐到逻辑原点。 |
| `ModelAssetDefinition.instantiate_fitted_model` | `(instance_name: StringName, target_bounds: AABB, preserve_proportions: bool = false, vertical_alignment: int = CENTER) -> Node3D` | 投射物默认逐轴精确拟合；Terrain 可请求等比缩放及顶部/底部垂直对齐。 |
| `ModelFitTransform.exact` | `(source: AABB, target: AABB) -> Transform3D` | 逐轴缩放，使源包围盒精确覆盖目标。 |
| `ModelFitTransform.proportional` | `(source: AABB, target: AABB, vertical_alignment: int) -> Transform3D` | 仅从XZ脚印求统一倍率，保持模型三轴比例并按指定Y锚点对齐。 |
| `ModelAssetDefinition.get_authored_visual_bounds` | `() -> Dictionary` | 返回 `{valid, bounds}` 资产诊断快照，不包含运行时 Scale 与玩法放置。 |
| `ModelAssetDefinition.validate_configuration` | `() -> Array[String]` | 校验 Scale、场景、节点树、锚点成对关系和有效三维包围盒。 |
| `BuildingLevelStats.get_model_asset` | `() -> ModelAssetDefinition` | 返回新契约资产，或把旧 `visual_scene` 临时包装为兼容资产。 |
| `EnemyDefinition.get_model_asset` | `() -> ModelAssetDefinition` | 返回敌人有效模型资产并兼容旧字段。 |
| `TileDefinition.get_element_model_asset` | `() -> ModelAssetDefinition` | 返回内容层有效模型资产并兼容旧字段。 |
| `TileCellData.get_terrain_model_asset` | `(fallback: ModelAssetDefinition = null) -> ModelAssetDefinition` | 返回定义覆盖或关卡默认地块模型。 |
| `TileCellData.get_element_model_asset` | `() -> ModelAssetDefinition` | 返回未被摧毁内容的元素模型。 |
| `TerrainDefinition.get_ramp_model_asset` | `(run_length: int) -> ModelAssetDefinition` | 返回1:1～1:4斜坡模型槽。 |
| `StuffDefinition.get_model_asset` | `() -> ModelAssetDefinition` | 返回Stuff规范模型并兼容旧`visual_scene`。 |

## 约定事实源

- `PackedScene` 内保存的 Transform 属于美术资产；世界高度、格尺寸和子弹尺寸必须来自玩法上下文，禁止用根 Transform 补齐。
- GLTF 的 `.tscn` 封装只保存根 Transform 与必要覆盖；禁止同时保留导入子节点和再次内嵌同名 Mesh，否则编辑器资源重扫会触发“引入节点名称冲突”。
- `runtime_scale` 三轴必须都是有限正数；镜像翻转由 Mirror 的反射矩阵负责，不能用负 Scale 冒充。
- 地块基底和地块内容是两个独立槽。复制镜只请求内容快照，不复制基底资产。
- 新规范进一步固定为Terrain与Stuff两个资源域：Terrain平地/斜坡永不进入镜像内容，Stuff模型可被按格复制。
- 自定义模型成功实例化后替换对应灰盒；对齐只改表现节点，不改碰撞、命中点、占位或寻路。
- 投射物的速度、长度和宽度仍是玩法参数；自定义模型精确拟合为该长度和宽度。
- Terrain 的 XZ 脚印来自 Grid；模型高度来自美术原始比例。平地顶部对齐逻辑表面，斜坡底部对齐逻辑坡底，绝不单独缩放 Y。

## 已知限制

- 自动对齐基于轴对齐 AABB，不识别“主体/装饰/特效”语义；不规则资产需用锚点或 `exclude_from_model_bounds` 明确取样范围。
- Terrain 等比拟合要求资产主体的 XZ 包围盒代表完整地块脚印；超出脚印的装饰应排除或使用 Fit 锚点，否则会影响统一倍率。
- 动画骨骼在运行时伸出编辑时包围盒时不会重新拟合；拟合只在实例创建时执行一次。
- 正式模型不会自动继承路径色、高度色或 `attack_color`；这些颜色只用于灰盒和复制体投射物叠加层。
- 模型契约只负责三维场景与缩放，不定义动画状态机、骨骼插槽、命中特效或声音接口。
