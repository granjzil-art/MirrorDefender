# Terrain Grid · 体素地块与斜坡

> 实现状态：批次2已完成运行时 Terrain，批次3已完成独立 Stuff 运行时，批次4已将关卡编辑器地块页切换到规范 Grid/Ramp/Stuff。波次页与镜头页未修改。

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
| `LevelResource` | `default_terrain` / `layer_height` | 未逐格覆盖时的地形与单层高度；高度固定由 `grid_cell_size × 1.0` 派生。 |
| `LevelResource` | `grid_cells` / `ramp_placements` | 规范地块覆盖和斜坡数组。 |
| `TerrainManager` | `feature_enabled` | 规范Terrain运行时总开关；Main默认开启。 |
| `TerrainRenderer` | `feature_enabled` | Terrain模型/灰盒渲染总开关。 |
| `TerrainRenderer` | `cliff_darkening` / `layer_band_darkening` | 灰盒崖壁与体素分层色差。 |

预置地形位于 `resources/terrains/Grass.tres`、`Sand.tres`、`Water.tres`、`Mud.tres`。四种预置只配置身份与灰盒颜色，模型槽为空时由后续运行时灰盒回退。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/terrain/TerrainDefinition.gd` | `TerrainDefinition` / `Resource` | 地形身份、平地/四档斜坡模型与配置校验。 |
| `scripts/terrain/TerrainModelMetrics.gd` | `TerrainModelMetrics` / `RefCounted` | 地形模型比例事实源；当前固定单层高度等于单格尺寸。 |
| `scripts/terrain/GridCellData.gd` | `GridCellData` / `Resource` | 一个地形柱的层数与基础建造权限。 |
| `scripts/terrain/RampPlacementData.gd` | `RampPlacementData` / `Resource` | 1:N多格连续斜坡的锚点、方向与占格计算。 |
| `scripts/terrain/TerrainManager.gd` | `TerrainManager` / `Node3D` | 规范Grid/Ramp运行时副本、路径格派生、坡面高度/法线/射线查询。 |
| `scripts/terrain/TerrainRenderer.gd` | `TerrainRenderer` / `Node3D` | 堆叠平地模型、实例化整段斜坡模型，并为缺失资产生成灰盒。 |
| `scripts/level/LevelContentMigrationAdapter.gd` | `LevelContentMigrationAdapter` / `RefCounted` | 把旧Tile内容只读拆成Grid与Stuff，或显式写入规范数组。 |
| `scripts/level/LevelContentValidator.gd` | `LevelContentValidator` / `RefCounted` | 校验层数、斜坡端点/占格/地形一致性和Stuff布局。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 保存规范数组并暴露兼容快照入口。 |
| `scripts/level/LevelLoader.gd` | `LevelLoader` / `Node` | 把Grid、Terrain与旧Tile作为同一运行时装配/回滚事务。 |
| `scripts/grid/GridManager.gd` | `GridManager` / `Node3D` | 接收Terrain高度/坡面/射线Callable并维持形状模块边界。 |
| `scripts/grid/GridRenderer.gd` | `GridRenderer` / `Node3D` | 对每个顶点采样真实表面，绘制坡面线框与高亮。 |
| `scripts/tile/TileManager.gd` | `TileManager` / `Node3D` | 正式 Main 中作为既有模块兼容门面：高度委托 Terrain，关卡元素查询委托 Stuff。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | 仅供旧工具/专项回归兼容；正式 Main 已关闭。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 块建筑取格心高度，边建筑取物理边坡高。 |
| `scripts/mirror/CopyMirror.gd` | `CopyMirror` / `Node3D` | 复制镜实体取物理边坡高，镜像玩法不复制Terrain。 |
| `scripts/Main.gd` | `MainController` / `Node3D` | 装配Terrain服务、兼容Callable和唯一基底渲染器。 |
| `addons/mirror_tile_editor/terrain_stuff_authoring.gd` | `TerrainStuffAuthoring / RefCounted` | 编辑器规范Terrain/斜坡写入事务。 |
| `addons/mirror_tile_editor/terrain_stuff_canvas.gd` | `TerrainStuffCanvas / Control` | 编辑器体素与真实斜坡画布。 |
| `tests/terrain_stuff_contract_test.gd` | 无 / `SceneTree` | 数据分离、四层高度、双网格斜坡、迁移与互斥回归。 |
| `tests/terrain_runtime_test.gd` | 无 / `SceneTree` | 双网格坡面采样、Grid权限桥、平地/整坡模型实例化、灰盒回退、兼容高度与加载回滚回归。 |
| `tests/terrain_stuff_editor_test.gd` | 无 / `SceneTree` | 地块页导入、独立工具、S1斜坡与分页边界回归。 |

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
  -> TerrainManager（批次2已切换运行时Grid/Ramp）

LevelLoader successful transaction
  -> GridManager.apply_configuration
  -> TerrainManager.load_level
  -> StuffManager.load_level（关卡元素、效果与耐久）
  -> TileManager.load_level（建筑 occupant 兼容状态）
  -> Main broadcasts remaining runtime rebuilds

TerrainManager
  -> GridManager height/slope picking Callable
  -> TileManager.get_world_height compatibility Callable
  -> TerrainRenderer model/greybox presentation
  -> Path/Building/Base/old Stuff keep consuming the shared surface height
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `TerrainDefinition.get_ramp_model_asset` | `(run_length: int) -> ModelAssetDefinition` | 按1～4格坡长返回对应模型槽。 |
| `TerrainModelMetrics.get_layer_height` | `(grid_cell_size: float) -> float` | 按固定1:1体素比例返回单层世界高度。 |
| `TerrainDefinition.validate_configuration` | `() -> Array[String]` | 校验身份、颜色和五个模型资产。 |
| `GridCellData.configure` | `(cell: Vector3i, terrain: TerrainDefinition, layer_count: int, allows_tile_building: bool, allows_edge_building: bool) -> void` | 一次设置规范地块配置并将层数限制到1～4。 |
| `GridCellData.get_effective_terrain` | `(fallback: TerrainDefinition = null) -> TerrainDefinition` | 返回逐格地形或关卡默认地形。 |
| `GridCellData.get_surface_height` | `(layer_height: float) -> float` | 返回 `(layer_count - 1) * layer_height`，保持旧低层表面Y=0。 |
| `RampPlacementData.get_footprint_cells` | `(shape: IGridShape) -> Array[Vector3i]` | 从最低坡格沿上坡方向生成N个占格。 |
| `RampPlacementData.get_low_neighbor` | `(shape: IGridShape) -> Vector3i` | 返回坡体外的低端连接格。 |
| `RampPlacementData.get_high_neighbor` | `(shape: IGridShape) -> Vector3i` | 返回坡体外的高端连接格。 |
| `RampPlacementData.get_connection_layer_toward` | `(shape: IGridShape, outside_cell: Vector3i) -> int` | 返回朝指定外部相邻格暴露的高/低端表面层；侧边返回0。 |
| `TerrainManager.load_level` | `(level_resource: LevelResource) -> bool` | 构建隔离的规范运行时副本，全部成功后一次提交。 |
| `TerrainManager.get_grid_cell` | `(cell: Vector3i) -> GridCellData` | 返回当前运行时Terrain格。 |
| `TerrainManager.get_world_height` | `(cell: Vector3i) -> float` | 返回平地或斜坡格中心的表面Y。 |
| `TerrainManager.sample_surface_height` | `(cell: Vector3i, world_position: Vector3) -> float` | 返回任意XZ点的真实平面坡高。 |
| `TerrainManager.get_surface_normal` | `(cell: Vector3i) -> Vector3` | 返回平地向上法线或1:N坡面法线。 |
| `TerrainManager.raycast_surface` | `(origin: Vector3, direction: Vector3) -> Dictionary` | 返回 `{hit, pos, cell}`，用于精确坡面拾取。 |
| `TerrainManager.allows_tile_building` | `(cell: Vector3i) -> bool` | 返回底层Grid的普通块建筑基础权限。 |
| `TerrainManager.allows_edge_building` | `(cell: Vector3i) -> bool` | 返回底层Grid的边建筑基础权限。 |
| `TerrainRenderer.set_grid` | `(value: GridManager) -> void` | 注入几何入口并订阅网格变化。 |
| `TerrainRenderer.set_terrain_manager` | `(value: TerrainManager) -> void` | 注入Terrain事实源并订阅加载/清空事件。 |
| `GridManager.set_cell_surface_height_resolver` | `(resolver: Callable) -> void` | 注入任意点坡面高度查询。 |
| `GridManager.set_surface_raycast_resolver` | `(resolver: Callable) -> void` | 注入精确坡面射线查询。 |
| `GridManager.sample_cell_surface_height` | `(cell: Vector3i, world_position: Vector3) -> float` | 统一提供边、线框与外部表现的表面Y。 |
| `GridRenderer.refresh_surface` | `() -> void` | Terrain成功提交后重建坡面线框。 |
| `TileManager.set_surface_height_resolver` | `(value: Callable) -> void` | 为旧玩法接入Terrain格心高度兼容桥。 |
| `TileManager.set_base_placement_resolvers` | `(tile_building_resolver: Callable, edge_building_resolver: Callable) -> void` | 把Grid基础权限与过渡期旧Tile/Stuff限制合并。 |
| `LevelLoader.configure` | `(grid_manager: GridManager, tile_manager: TileManager, terrain_manager: TerrainManager = null) -> void` | 注入装配事务依赖；第三参数可选以保持独立旧测试兼容。 |
| `LevelResource.get_effective_content_snapshot` | `() -> Dictionary` | 返回 `{content_version, migrated, default_terrain, layer_height, grid_cells, ramp_placements, stuff_placements}`。 |
| `LevelResource.migrate_legacy_content_in_place` | `() -> bool` | 显式物化规范数组；批次1保留旧`tiles`以维持现运行时。 |
| `LevelContentValidator.validate` | `(level: Resource, shape: IGridShape) -> Array[String]` | 对规范内容执行只读完整校验。 |
| `TerrainStuffAuthoring.place_ramp` | `(level: Resource, shape: IGridShape, anchor_cell: Vector3i, facing_index: int, run_length: int, base_layer: int) -> Dictionary` | S1放置；校验占格、连续坡共享边，并自动对齐坡体与平地连接端。 |
| `TerrainStuffAuthoring.normalize_ramp_constraints` | `(level: Resource, shape: IGridShape) -> Dictionary` | 将结构合法且无冲突的斜坡规约回规范Grid；返回`{changed, normalized_ramps, skipped_ramps, skipped_ramp_ids}`。 |
| `TerrainStuffAuthoring.get_ramp_layer_constraint` | `(level: Resource, shape: IGridShape, cell: Vector3i) -> Dictionary` | 优先返回坡体自身所有权；平地连接格返回关联斜坡、期望层及多约束冲突状态。 |

## 约定事实源

- `TerrainDefinition` 不得添加建造权限、路径、效果或Stuff字段。
- `GridCellData.layer_count` 是1起始层数；世界顶面为 `(层数 - 1) × 单层高度`。
- 斜坡是Grid形状，不是Stuff，也不属于复制镜可复制内容。
- `anchor_cell` 是最低坡格，`facing_index` 永远指向上坡；反向坡通过反转方向并改锚点表达。
- 1:N斜坡占N格且只升一层。全部坡格基础层相同、地形ID相同，高低端必须位于图内并分别连接基础层与基础层+1。
- `RampPlacementData` 是斜坡体素约束的事实源：坡体Grid层恒为自身`base_layer`；连接端是平地时，低端规约为`base_layer`、高端规约为`base_layer + 1`。连接端被另一段斜坡占据时，不改写对方坡体层，而是比较双方共享物理边的表面层。
- 连续斜坡仅允许高/低端完整共享边且表面层相同；高接低、低接高、高接高（山脊）或低接低（谷底）均按共享边层判断。接到另一斜坡侧边、共享边层数不一致、坡体重叠或越界仍为非法。
- 创建、载入编辑器和保存前共用上述规约；斜坡坡体和仍为平地的连接格在斜坡存在期间不可手工修改层数。
- 正方形坡向使用4条边，六边形使用6条边。Stuff朝向仍按关卡建筑朝向约定使用正方形8向、六边形6向。
- 平地模型槽表示“一个体素块”。运行时按单格 XZ 脚印求一个统一倍率，XYZ 同比缩放并把模型顶部对齐逻辑地表；不再将模型 Y 压缩或拉伸到目标层高。
- 1:N斜坡模型槽表示横跨N格、从坡底升高一层的完整模型；本地 `+Z` 视为上坡方向。运行时按“一格宽 × N格长”的 XZ 脚印等比缩放，底部对齐逻辑坡底后按 `facing_index` 旋转。
- `TerrainModelMetrics` 是层高唯一事实源，当前固定 `Layer Height = Grid Cell Size`，即一个体素的逻辑宽高比为1:1。所有关卡加载、迁移、新建和编辑都按该比例规约；编辑器层高控件只读。
- Terrain 旧 `runtime_scale` 被拟合吸收，可归一为 `Vector3.ONE`；不得再用 `.tscn` 根 Transform 或非统一 Scale 补偿高度。
- 未配置模型时，TerrainRenderer生成顶面、坡面和逐层深浅崖壁灰盒；StuffRenderer生成独立关卡元素灰盒。正式 Main 不再使用 TileRenderer 的旧混合内容。
- 路径格颜色是由 `LevelResource.paths` 推导的表现覆盖，不改变Terrain种类、层数或建造权限。
- 边建筑与复制镜在坡面上使用物理边中点采样；平地断崖仍取两侧较高表面，保持原有不嵌入地形的表现。
- 普通块建筑和边建筑必须同时通过Grid基础权限与旧Tile/Stuff限制；屏障的路径专用占位继续复用原有专用接口，避免改变旧道路玩法。

## 已知限制 / 后续批次

- 关卡编辑器已提供 Terrain、1～4层、两类权限、S1斜坡和 Stuff 独立工具；用法见 `LevelEditor_关卡编辑器.md`。
- Stuff效果、互斥、摧毁、综合建造权限与镜像快照已由独立 `StuffManager / StuffRuntime / StuffRenderer` 承担。
- 旧资源只读迁移无法推断元素下方曾经被混合格式抹去的特殊地形；默认迁移为关卡草地/默认地形，模型覆盖仍原样引用。
- 运行时仍可只读加载旧 `tiles`；一旦用批次4编辑器导入，作者文档会清空旧数组，只保留规范事实源。
