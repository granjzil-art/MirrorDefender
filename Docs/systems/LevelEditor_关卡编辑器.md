# Level Editor · 关卡编辑器

> 实现状态：体素地块重构批次4已完成地块页迁移。Terrain Grid、斜坡与 Stuff 使用规范数组；波次页、镜头页及其序列化数据未修改。

## 职责与边界

关卡编辑器是 `LevelResource` 的作者工具。地块页只编辑三类事实：

- `GridCellData`：Terrain 种类、1～4层体素、块建筑/边建筑基础权限。
- `RampPlacementData`：1:1～1:4、从最低坡格指向上坡的多格斜坡。
- `StuffPlacementData`：位于 Grid 表面的石头、树、尖刺、黑洞等独立实例。

路径、波次和镜头仍在原分页编辑。地块页不写入路径属性，画布只读用 `path_terrain_color` 显示全路径格并集。

## 使用方式

Godot 主界面选择 `Mirror 关卡编辑器 -> 地块`。

1. **Terrain 地形刷**：选草地/沙地/水/泥土后按住左键连续涂刷。只改 Terrain，不改层数、权限和 Stuff。
2. **层数刷**：选 1～4 层后连续涂刷。顶面高度为 `(层数 - 1) * 体素单层高度`；“体素单层高度”只读并自动等于 `Grid Cell Size`，无需手调适配模型。
3. **Grid 权限刷**：勾选“允许块建筑/允许边建筑”后启用。这是底层 Grid 权限，Stuff 只在运行时叠加否决。
4. **Stuff 刷**：选元素和朝向后点击放置。每次点击新建稳定 `placement_id`；只有同格双方都关闭互斥时才能共存。
5. **斜坡 S1**：选上坡方向、1:N坡度、基础层与“斜坡地形”，再点击“最低坡格”。默认“跟随坡底基底”；也可选一种Terrain作为整条坡的独立模型/颜色。工具仍自动统一坡体底层Grid的基底Terrain/基础层，低端对齐基础层，高端设为基础层+1。
6. **单格检查器**：“选择/检查”模式下点格子，可精确修改 Terrain、层数、两类权限、Stuff 朝向，或单独删除 Stuff/斜坡。坡体的底层Grid Terrain/层数保持锁定，但“斜坡地形”可独立改为任一Terrain或恢复“跟随坡底基底”；此操作不改底层Grid。

更改网格形状或尺寸会弹出确认并重建 Terrain/Ramp/Stuff；路径、出生点、据点、波次、镜头数据保留，但必须重新校验越界端点。

## 旧关卡导入

加载只有 `tiles` 的旧关卡时，`prepare_level()` 先调用 `LevelContentMigrationAdapter`，再物化地图内每个 Grid 格。导入后清空内存作者文档的旧 `tiles`，防止两套事实源分叉，并标记“未保存”；只有点击保存才写入 `.tres`。

## 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `addons/mirror_tile_editor/terrain_stuff_authoring.gd` | `TerrainStuffAuthoring / RefCounted` | 规范 Grid/Ramp/Stuff 唯一编辑写入边界。 |
| `addons/mirror_tile_editor/terrain_stuff_canvas.gd` | `TerrainStuffCanvas / Control` | 体素、真实坡面、权限标记、多 Stuff 和 S1 预览画布。 |
| `addons/mirror_tile_editor/terrain_stuff_editor.gd` | `TerrainStuffEditor / HSplitContainer` | 地块页UI、工具状态、单格检查器和重建确认。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | 无 / `Control` | 组装四分页，负责加载、校验、保存和脏标记。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | 无 / `Control` | 路径/镜头页共用预览，只读显示规范 Terrain/Ramp/Stuff。 |
| `tests/terrain_stuff_editor_test.gd` | 无 / `SceneTree` | 导入、独立工具、多Stuff、S1和分页边界回归。 |

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `TerrainStuffAuthoring.prepare_level` | `(level: Resource, shape: IGridShape) -> Dictionary` | 返回 `{changed, migrated, added_cells}`；导入旧Tile、建立单一事实源、补齐Grid，并把层高规约为模型1:1比例。 |
| `TerrainStuffAuthoring.rebuild_grid` | `(level: Resource, shape: IGridShape, shape_id: int, grid_size: Vector2i) -> void` | 重建 Terrain/Ramp/Stuff，不修改路径/波次/镜头。 |
| `paint_terrain / paint_layer / paint_permissions` | `(level, cell, 工具值) -> bool` | 三种互不污染的 Grid 编辑入口。 |
| `TerrainStuffAuthoring.add_stuff` | `(level: Resource, cell: Vector3i, definition: Resource, facing_index: int) -> Dictionary` | 校验双向互斥并返回 `{success, message, placement}`。 |
| `TerrainStuffAuthoring.remove_stuff` | `(level: Resource, placement_id: StringName) -> bool` | 只删除一个稳定ID的 Stuff。 |
| `TerrainStuffAuthoring.place_ramp` | `(level: Resource, shape: IGridShape, anchor_cell: Vector3i, facing_index: int, run_length: int, base_layer: int, terrain_override: TerrainDefinition = null) -> Dictionary` | S1放置、整坡地形选择与自动高低端整理，返回 `{success, message, ramp}`。 |
| `TerrainStuffAuthoring.set_ramp_terrain_override` | `(level: Resource, ramp_id: StringName, terrain_override: TerrainDefinition) -> bool` | 修改已选斜坡的整坡地形；空值恢复跟随基底。 |
| `TerrainStuffEditor.set_level` | `(value: LevelResource) -> Dictionary` | 准备作者文档、同步UI并返回导入结果。 |
| `TerrainStuffCanvas.reset_view` | `() -> void` | 有有效布局尺寸时立即重置视图；隐藏零尺寸时只记录一次待重置状态。 |

## 数据流

```text
TileEditorPanel.load/new
  -> TerrainStuffEditor.set_level
       -> TerrainStuffAuthoring.prepare_level
            -> LevelContentMigrationAdapter (legacy only)
            -> grid_cells / ramp_placements / stuff_placements
       -> TerrainStuffCanvas + inspector

Author click/drag -> Canvas intent -> Authoring canonical mutation
                  -> level_changed -> dirty flag -> path/camera preview refresh
```

## 已知限制

- 逐笔 Terrain/Stuff 编辑尚未纳入通用 UndoRedo 事务。
- 旧混合格无法推断元素下方曾被覆盖的自定义 Terrain；导入使用关卡默认地形。
- 斜坡存在时不允许逐格改坡体的底层Grid Terrain/层数；须先删除斜坡。整坡表现地形可通过“斜坡地形”独立设置，但不支持同一斜坡逐格混合。

## 编辑器生命周期约定

- 主界面插件在 Godot 启动时先构建、后隐藏，因此画布可能长时间保持 `0×0` 尺寸。
- 零尺寸时禁止递归 `call_deferred()` 等待布局；只保存待处理标记，由 `resized` 或可见性变化触发一次重置。
- `SplitContainer` 的每一层只放两个布局子控件；地块页用嵌套分割容器组成“工具栏 / 画布 / 检查器”。
