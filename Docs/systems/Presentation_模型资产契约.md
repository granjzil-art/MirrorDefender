# 模型资产契约 · Model Asset

> 实现状态：已统一接入地块基底、建筑等级、地块元素、敌人、建筑投射物、敌人投射物和复制体投射物。

## 职责

`ModelAssetDefinition` 是运行时三维美术的共享数据契约。玩法模块只持有这一资源，不直接解释 FBX/GLTF 或具体模型层级；未配置资产或实例化失败时，各模块继续使用原有灰盒表现。

## 分类 / 做法

- **统一字段**：每份资产包含 `scene: PackedScene` 和 `runtime_scale: Vector3`。
- **附加缩放**：实例化时创建 `ModelAssetRoot` 包装节点，把 `runtime_scale` 写在包装节点；美术场景根节点原有位置、旋转和 Scale 保持不变。最终世界变换为运行时包装变换乘美术场景原始变换。
- **独立配置**：多个 `ModelAssetDefinition` 可引用同一个 `PackedScene`，但保存不同 `runtime_scale`。建筑三个等级因此可以共用模型而采用不同尺寸。
- **根节点约束**：模型场景根节点必须继承 `Node3D`；资源校验会实际实例化一次确认根类型。
- **灰盒回退**：资产为空、无法实例化或根类型错误时，运行时返回 null，由地块、建筑、敌人或投射物模块生成原灰盒。
- **旧资源兼容**：建筑等级、敌人和地块元素保留隐藏的旧 `visual_scene` 存储字段；新资源必须使用 `model_asset` / `element_model_asset`。

## 参数入口

| 使用者 | 字段 | 作用 |
|---|---|---|
| `LevelResource` | `tile_model_asset` | 本关全部地块基底的默认模型。 |
| `TileDefinition` | `terrain_model_asset` | 指定地块定义对关卡默认基底模型的覆盖。 |
| `TileDefinition` | `element_model_asset` | 尖刺、空洞、石头或可破坏内容层模型。 |
| `BuildingLevelStats` | `model_asset` | 本建筑当前等级模型。 |
| `BuildingLevelStats` | `projectile_model_asset` | 本等级建筑投射物模型；复制体投射物沿用同一配置。 |
| `EnemyDefinition` | `model_asset` | 本敌人模型。 |
| `EnemyDefinition` | `projectile_model_asset` | 本敌人的远程投射物模型。 |

每个字段中新建或引用一个 `ModelAssetDefinition`，再设置 `Scene` 与 `Runtime Scale`。例如三级箭塔可让三个等级资产都引用同一个 `arrow_tower.tscn`，分别设置 `(1,1,1)`、`(1.1,1.1,1.1)`、`(1.2,1.2,1.2)`。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/presentation/ModelAssetDefinition.gd` | `ModelAssetDefinition` / `Resource` | 模型场景、附加运行时 Scale、实例化和配置校验的共享契约。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | 基底/内容资产实例化、灰盒批次回退和镜像快照。 |
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
  -> instantiate_model()
       -> runtime wrapper.scale = runtime_scale
       -> authored Node3D keeps original Transform
  -> runtime owner adds wrapper
  -> null/invalid -> owner-specific greybox fallback

LevelResource.tile_model_asset
  -> TileDefinition.terrain_model_asset optional override
  -> TileRenderer per-cell base model

TileDefinition.element_model_asset
  -> TileRenderer content model
  -> create_tile_content_visual_snapshot
  -> MirrorProjection exact reflected snapshot

BuildingLevelStats.projectile_model_asset
  -> CombatManager -> Projectile
  -> Building copy_attack_triggered
  -> MirrorManager -> MirrorProjectionProjectile (same asset)
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `ModelAssetDefinition.is_configured` | `() -> bool` | 返回是否配置了 PackedScene。 |
| `ModelAssetDefinition.instantiate_model` | `(instance_name: StringName = &"ModelAssetRoot") -> Node3D` | 创建附加 Scale 包装节点并实例化 Node3D 美术场景；失败返回 null。 |
| `ModelAssetDefinition.validate_configuration` | `() -> Array[String]` | 校验 Scale 为有限正数、场景可实例化且根节点继承 Node3D。 |
| `BuildingLevelStats.get_model_asset` | `() -> ModelAssetDefinition` | 返回新契约资产，或把旧 `visual_scene` 临时包装为兼容资产。 |
| `EnemyDefinition.get_model_asset` | `() -> ModelAssetDefinition` | 返回敌人有效模型资产并兼容旧字段。 |
| `TileDefinition.get_element_model_asset` | `() -> ModelAssetDefinition` | 返回内容层有效模型资产并兼容旧字段。 |
| `TileCellData.get_terrain_model_asset` | `(fallback: ModelAssetDefinition = null) -> ModelAssetDefinition` | 返回定义覆盖或关卡默认地块模型。 |
| `TileCellData.get_element_model_asset` | `() -> ModelAssetDefinition` | 返回未被摧毁内容的元素模型。 |

## 约定事实源

- `PackedScene` 内保存的 Transform 属于美术资产；`runtime_scale` 属于玩法项目配置，两者禁止互相覆盖。
- `runtime_scale` 三轴必须都是有限正数；镜像翻转由 Mirror 的反射矩阵负责，不能用负 Scale 冒充。
- 地块基底和地块内容是两个独立槽。复制镜只请求内容快照，不复制基底资产。
- 自定义模型成功实例化后替换对应灰盒；未配置时不改变现有画面、玩法、碰撞、命中点或寻路。
- 投射物的速度、长度和宽度仍是玩法/灰盒参数；自定义模型尺寸只由场景自身 Transform 与 `runtime_scale` 决定。

## 已知限制

- 自定义地块基底模型成功实例化后不再自动生成该格程序化崖壁；资产需自行包含所需侧面。
- 正式模型不会自动继承路径色、高度色或 `attack_color`；这些颜色只用于灰盒和复制体投射物叠加层。
- 模型契约只负责三维场景与缩放，不定义动画状态机、骨骼插槽、命中特效或声音接口。
