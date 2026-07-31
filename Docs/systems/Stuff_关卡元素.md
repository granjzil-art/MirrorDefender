# Stuff · 关卡元素

> 实现状态：批次1已完成独立定义、实例布局、旧元素转换和配置校验。尖刺、黑洞、石头的现有运行时仍由旧Tile系统驱动，后续批次切换到StuffManager/StuffRenderer。

## 职责

Stuff 是放置在Grid表面之上的关卡对象，与塔相似但不属于玩家建筑：石头、树、尖刺、黑洞都由独立实例表示。Stuff可以携带模型、效果、互斥规则和建造限制，但不能修改底层地形种类、体素层数或手工路径。

## 关键参数

| 资源 | 参数 | 说明 |
|---|---|---|
| `StuffDefinition` | `stuff_id` / `display_name` | 类型稳定标识与显示名。 |
| `StuffDefinition` | `exclusive_with_other_stuff` | 是否排斥同格其它Stuff，默认true。只有双方都为false才可共存。 |
| `StuffDefinition` | `blocks_tile_building` | 存活时是否阻止块建筑。 |
| `StuffDefinition` | `blocks_edge_building` | 存活时是否阻止该格参与边建筑。 |
| `StuffDefinition` | `effect` | 尖刺、黑洞、石头等已有 `TileEffect` 策略；批次1保留策略内容。 |
| `StuffDefinition` | `model_asset` | 独立模型与Runtime Scale；不再占用地块模型槽。 |
| `StuffDefinition` | `fallback_visual_kind` / `fallback_color` | 无正式模型时的灰盒类型与颜色。 |
| `StuffPlacementData` | `placement_id` | 单个实例唯一ID。 |
| `StuffPlacementData` | `cell` / `facing_index` | 所在Grid格和方向；正方形0～7、六边形0～5。 |
| `LevelResource` | `stuff_placements` | 同格可含多个实例的规范数组。 |

预置定义位于 `resources/stuffs/Rock.tres`、`Spike.tres`、`Void.tres`、`Tree.tres`。四者默认互斥并阻止块建筑、不阻止边建筑；模型接口保留为空，由后续美术配置。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/stuff/StuffDefinition.gd` | `StuffDefinition` / `Resource` | Stuff身份、互斥、权限限制、效果和表现资产。 |
| `scripts/stuff/StuffPlacementData.gd` | `StuffPlacementData` / `Resource` | 一个可寻址Stuff实例的位置、朝向和定义。 |
| `scripts/level/LevelContentMigrationAdapter.gd` | `LevelContentMigrationAdapter` / `RefCounted` | 将旧TileDefinition元素转换为独立Stuff定义与实例。 |
| `scripts/level/LevelContentValidator.gd` | `LevelContentValidator` / `RefCounted` | 校验实例ID、边界、朝向和同格互斥。 |
| `tests/terrain_stuff_contract_test.gd` | 无 / `SceneTree` | 默认互斥、双方放开、资源加载和旧元素拆分回归。 |

### 权限合成契约

```text
有效块建筑权限
  = GridCellData.allows_tile_building
  AND 没有存活Stuff.blocks_tile_building
  AND 没有实体建筑占位

有效边建筑权限
  = 两侧GridCellData.allows_edge_building
  AND 两侧均没有存活Stuff.blocks_edge_building
  AND 物理边没有其它边建筑占位
```

石头摧毁只删除/停用对应Stuff实例；底层Grid、地形、层数和基础权限保持不变。旧石头格迁移时底层Grid默认允许两类建筑，因此维持“石头消失后可建造”的现有玩法。

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `StuffDefinition.can_coexist_with` | `(other: Resource) -> bool` | 仅当双方均显式关闭互斥时返回true。 |
| `StuffDefinition.get_model_asset` | `() -> ModelAssetDefinition` | 返回规范模型，或把旧`visual_scene`包装为兼容模型资产。 |
| `StuffDefinition.validate_configuration` | `() -> Array[String]` | 校验身份、灰盒、效果和模型。 |
| `StuffPlacementData.configure` | `(placement_id: StringName, cell: Vector3i, definition: StuffDefinition, facing_index: int = 0) -> void` | 一次配置单个Stuff实例。 |
| `StuffPlacementData.validate_configuration` | `() -> Array[String]` | 校验实例身份、朝向和定义引用是否存在；定义内容由关卡校验器去重校验。 |

## 迁移映射

| 旧混合内容 | 新Grid | 新Stuff |
|---|---|---|
| 可建造地块 | 原坐标、原高度+1层、允许两类建筑 | 无 |
| 不可建造路面 | `allows_tile_building=false`，路径仍由Paths推导 | 无 |
| 石头 | 默认地形、底层允许两类建筑 | 石头效果、模型、颜色和限制 |
| 尖刺/黑洞 | 默认地形、底层允许两类建筑 | 原效果、模型、颜色和限制 |
| 已摧毁石头 | 按效果的摧毁后权限生成Grid | 无 |

## 已知限制 / 后续批次

- 当前生产运行时尚未创建StuffManager/StuffRenderer；本批次只建立可保存、可校验、可迁移的数据事实源。
- 旧混合格式每格最多一个元素，迁移后仍只有一个；新规范数组已支持多个非互斥Stuff。
- 复制镜后续必须按格收集全部Stuff实例，但继续禁止复制Terrain、路径色、层数和斜坡。
