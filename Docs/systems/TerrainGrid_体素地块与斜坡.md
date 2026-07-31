# Terrain Grid · 体素地块与斜坡

> 实现状态：批次1已完成规范数据契约、旧资源只读转换与配置校验。运行时渲染、寻路和关卡编辑器尚未切换，列入后续批次。

## 职责

Terrain Grid 只描述关卡的地表事实：格坐标、草地/沙地/水/泥土地形、1～4层体素高度、块建筑基础权限和边建筑基础权限。手工路径由 `LevelResource.paths` 单独保存并推导路径格属性；Stuff、建筑和占位不属于地形种类。

## 分类与关键参数

| 资源 | 参数 | 说明 |
|---|---|---|
| `TerrainDefinition` | `terrain_id` / `display_name` | 地形稳定标识与显示名。 |
| `TerrainDefinition` | `fallback_color` / `ui_icon` | 灰盒颜色与可选UI资产。 |
| `TerrainDefinition` | `flat_model_asset` | 单个体素地块模型；堆叠由运行时负责。 |
| `TerrainDefinition` | `ramp_1_to_1_model_asset`～`ramp_1_to_4_model_asset` | 分别跨1～4格、升高一层的完整斜坡模型。 |
| `GridCellData` | `cell` / `terrain` | 地块坐标及可覆盖默认值的地形引用。 |
| `GridCellData` | `layer_count` | 固定为1～4层；不再使用0起始高度语义。 |
| `GridCellData` | `allows_tile_building` / `allows_edge_building` | 底层Grid自身权限；Stuff与实体占位只在运行时叠加限制。 |
| `RampPlacementData` | `anchor_cell` / `facing_index` | 最低坡格与上坡方向。 |
| `RampPlacementData` | `run_length` | 1～4，对应1:1、1:2、1:3、1:4。 |
| `RampPlacementData` | `base_layer` | 坡底层数1～3；坡顶固定为 `base_layer + 1`。 |
| `LevelResource` | `default_terrain` / `layer_height` | 未逐格覆盖时的地形与每个体素层的世界高度。 |
| `LevelResource` | `grid_cells` / `ramp_placements` | 规范地块覆盖和斜坡数组。 |

预置地形位于 `resources/terrains/Grass.tres`、`Sand.tres`、`Water.tres`、`Mud.tres`。四种预置只配置身份与灰盒颜色，模型槽为空时由后续运行时灰盒回退。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/terrain/TerrainDefinition.gd` | `TerrainDefinition` / `Resource` | 地形身份、平地/四档斜坡模型与配置校验。 |
| `scripts/terrain/GridCellData.gd` | `GridCellData` / `Resource` | 一个地形柱的层数与基础建造权限。 |
| `scripts/terrain/RampPlacementData.gd` | `RampPlacementData` / `Resource` | 1:N多格连续斜坡的锚点、方向与占格计算。 |
| `scripts/level/LevelContentMigrationAdapter.gd` | `LevelContentMigrationAdapter` / `RefCounted` | 把旧Tile内容只读拆成Grid与Stuff，或显式写入规范数组。 |
| `scripts/level/LevelContentValidator.gd` | `LevelContentValidator` / `RefCounted` | 校验层数、斜坡端点/占格/地形一致性和Stuff布局。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 保存规范数组并暴露兼容快照入口。 |
| `tests/terrain_stuff_contract_test.gd` | 无 / `SceneTree` | 数据分离、四层高度、双网格斜坡、迁移与互斥回归。 |

### 数据流

```text
LevelResource
  ├─ default_terrain + grid_cells -> Terrain/Grid唯一事实源
  ├─ ramp_placements              -> Grid形状覆盖
  ├─ paths                        -> 只读推导“路径格”属性
  └─ stuff_placements             -> 独立Stuff事实源

旧 LevelResource.tiles
  -> LevelContentMigrationAdapter.build_snapshot（只读）
       -> height_level 0/1/2... 映射 layer_count 1/2/3...，最高4
       -> 旧元素定义拆成底层Grid + StuffPlacementData
  -> 后续运行时/编辑器逐批切换
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `TerrainDefinition.get_ramp_model_asset` | `(run_length: int) -> ModelAssetDefinition` | 按1～4格坡长返回对应模型槽。 |
| `TerrainDefinition.validate_configuration` | `() -> Array[String]` | 校验身份、颜色和五个模型资产。 |
| `GridCellData.configure` | `(cell: Vector3i, terrain: TerrainDefinition, layer_count: int, allows_tile_building: bool, allows_edge_building: bool) -> void` | 一次设置规范地块配置并将层数限制到1～4。 |
| `GridCellData.get_effective_terrain` | `(fallback: TerrainDefinition = null) -> TerrainDefinition` | 返回逐格地形或关卡默认地形。 |
| `GridCellData.get_surface_height` | `(layer_height: float) -> float` | 返回 `(layer_count - 1) * layer_height`，保持旧低层表面Y=0。 |
| `RampPlacementData.get_footprint_cells` | `(shape: IGridShape) -> Array[Vector3i]` | 从最低坡格沿上坡方向生成N个占格。 |
| `RampPlacementData.get_low_neighbor` | `(shape: IGridShape) -> Vector3i` | 返回坡体外的低端连接格。 |
| `RampPlacementData.get_high_neighbor` | `(shape: IGridShape) -> Vector3i` | 返回坡体外的高端连接格。 |
| `LevelResource.get_effective_content_snapshot` | `() -> Dictionary` | 返回 `{content_version, migrated, default_terrain, layer_height, grid_cells, ramp_placements, stuff_placements}`。 |
| `LevelResource.migrate_legacy_content_in_place` | `() -> bool` | 显式物化规范数组；批次1保留旧`tiles`以维持现运行时。 |
| `LevelContentValidator.validate` | `(level: Resource, shape: IGridShape) -> Array[String]` | 对规范内容执行只读完整校验。 |

## 约定事实源

- `TerrainDefinition` 不得添加建造权限、路径、效果或Stuff字段。
- `GridCellData.layer_count` 是1起始层数；世界顶面为 `(层数 - 1) × 单层高度`。
- 斜坡是Grid形状，不是Stuff，也不属于复制镜可复制内容。
- `anchor_cell` 是最低坡格，`facing_index` 永远指向上坡；反向坡通过反转方向并改锚点表达。
- 1:N斜坡占N格且只升一层。全部坡格基础层相同、地形ID相同，高低端必须位于图内并分别连接基础层与基础层+1。
- 正方形坡向使用4条边，六边形使用6条边。Stuff朝向仍按关卡建筑朝向约定使用正方形8向、六边形6向。

## 已知限制 / 后续批次

- 批次1尚未让运行时Manager、Renderer、路径移动和动态寻路读取规范数组。
- 关卡编辑器尚未提供地形、层数、属性、斜坡和Stuff独立工具；波次页与镜头页明确不在改动范围。
- 旧资源只读迁移无法推断元素下方曾经被混合格式抹去的特殊地形；默认迁移为关卡草地/默认地形，模型覆盖仍原样引用。
- 规范数组和旧`tiles`暂时并存是过渡措施；运行时切换完成后旧字段只保留导入兼容，不再形成事实源。
