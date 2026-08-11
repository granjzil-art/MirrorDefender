# Level Editor · 关卡编辑器

> 实现状态：体素地块重构批次4已完成地块页迁移。Terrain Grid、斜坡与 Stuff 使用规范数组；波次页、镜头页及其序列化数据未修改。编辑器现支持规范关卡资源的自动保存与外部文件刷新。

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
   - “管理关卡元素库”可新建、复制、排序、禁用和安全移除元素类型；模型、运行时 Scale、图标、互斥、建筑权限、堵路、对空、耐久和高级 Effect 均在窗口内配置。
   - 保存后地块页按 `StuffCatalog.definitions` 顺序刷新。移除类型前会扫描 `resources/levels`，仍被任何关卡引用时拒绝；成功只移出目录，不删除 `.tres`。
5. **斜坡 S1**：选上坡方向、1:N坡度、基础层与“斜坡地形”，再点击“最低坡格”。默认“跟随坡底基底”；也可选一种Terrain作为整条坡的独立模型/颜色。工具仍自动统一坡体底层Grid的基底Terrain/基础层，低端对齐基础层，高端设为基础层+1。
6. **单格检查器**：“选择/检查”模式下点格子，可精确修改 Terrain、层数、两类权限、Stuff 朝向，或单独删除 Stuff/斜坡。坡体的底层Grid Terrain/层数保持锁定，但“斜坡地形”可独立改为任一Terrain或恢复“跟随坡底基底”；此操作不改底层Grid。

## 资源双向同步

- 地块页修改会在当前关卡已有 `resource_path` 时自动合并保存完整 `LevelResource`。保存粒度是整个 `.tres`，因此 `grid_cells`、`ramp_placements`、`stuff_placements`、路径、出生点、据点、波次、镜头、初始建筑和镜子布局一起写入；连续画笔在同一帧内只合并为一次保存请求。
- 新建但尚未保存的内存关卡不会静默写入工具栏中的默认路径；首次点击“保存”建立 `.tres` 后才启用自动同步。
- 编辑器每250ms检查当前 `.tres` 的文件变化。直接在 Godot Inspector 或外部文本编辑器保存关卡后，若编辑器没有本地未保存改动，会重新加载完整资源并刷新地块、路径、波次和镜头页。
- 若检测到外部文件变化时编辑器仍有未保存改动，不会静默覆盖当前编辑；顶部状态栏会提示冲突，需先保存或重新加载。
- 规范资源的唯一可编辑事实源是 `terrain_content_version >= 2` 的 `default_terrain`、`grid_cells`、`ramp_placements` 和 `stuff_placements`。旧 `tiles` 仅在加载旧关卡时作为一次性迁移输入，迁移后会清空并保存为规范数组；之后直接修改旧 `tiles` 不会覆盖规范 Terrain。

更改网格形状或尺寸会弹出确认并重建 Terrain/Ramp/Stuff；路径、出生点、据点、波次、镜头数据保留，但必须重新校验越界端点。

## 旧关卡导入

加载只有 `tiles` 的旧关卡时，`prepare_level()` 先调用 `LevelContentMigrationAdapter`，再物化地图内每个 Grid 格。导入后清空内存作者文档的旧 `tiles`，防止两套事实源分叉，并标记“未保存”；只有点击保存才写入 `.tres`。

## 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `addons/mirror_tile_editor/terrain_stuff_authoring.gd` | `TerrainStuffAuthoring / RefCounted` | 规范 Grid/Ramp/Stuff 唯一编辑写入边界。 |
| `addons/mirror_tile_editor/terrain_stuff_canvas.gd` | `TerrainStuffCanvas / Control` | 体素、真实坡面、权限标记、多 Stuff 和 S1 预览画布。 |
| `addons/mirror_tile_editor/terrain_stuff_editor.gd` | `TerrainStuffEditor / HSplitContainer` | 地块页UI、工具状态、单格检查器和重建确认。 |
| `addons/mirror_tile_editor/stuff_catalog_manager.gd` | `StuffCatalogManager / Window` | 元素类型数据管理；作为地块页的惰性弹窗，不占用主分割布局。 |
| `scripts/stuff/StuffCatalogAuthoring.gd` | `StuffCatalogAuthoring / RefCounted` | 元素类型新建、复制、资源保存与关卡引用保护。 |
| `resources/stuffs/StuffCatalog.tres` | `StuffCatalog / Resource` | 关卡编辑器与运行时编辑器共用的显式元素白名单和顺序。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | 无 / `Control` | 组装四分页，负责加载、校验、完整资源自动保存、内存/磁盘双向同步和脏标记。 |
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
| `StuffCatalogManager.open_manager` | `() -> void` | 加载正式目录并打开非模态元素库窗口。 |
| `StuffCatalogAuthoring.create_definition` | `(catalog: StuffCatalog, requested_id: String, display_name: String, model_scene: PackedScene = null, runtime_scale: Vector3 = Vector3.ONE) -> Dictionary` | 新建并注册带安全默认值的独立 StuffDefinition。 |
| `StuffCatalogAuthoring.remove_definition_if_unreferenced` | `(catalog: StuffCatalog, definition: StuffDefinition, level_directory: String) -> Dictionary` | 有关卡引用时拒绝移出目录。 |
| `TerrainStuffCanvas.reset_view` | `() -> void` | 有有效布局尺寸时立即重置视图；隐藏零尺寸时只记录一次待重置状态。 |
| `TileEditorPanel._queue_resource_auto_sync` | `() -> void` | 合并地块页修改并延迟触发完整 `LevelResource` 保存。 |
| `TileEditorPanel._poll_active_resource_file` | `() -> void` | 检查当前关卡文件签名，发现外部修改时按冲突策略重载完整资源。 |
| `TileEditorPanel._refresh_views_from_active_resource` | `() -> void` | 将当前内存 `LevelResource` 的变化同步到地块、路径、波次和镜头页面。 |
| `TileEditorPanel._save_level_to_path` | `(path: String, auto_sync: bool = false) -> void` | 将完整关卡资源保存到指定路径并更新同步签名。 |

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

“管理关卡元素库”
  -> 惰性创建 StuffCatalogManager Window
  -> StuffCatalogAuthoring 保存定义 + 目录
  -> catalog_changed
  -> 仅重建地块页 Stuff 调色板
```

## 已知限制

- 逐笔 Terrain/Stuff 编辑尚未纳入通用 UndoRedo 事务。
- 元素库窗口不删除资源文件；无引用类型移出目录后，如需物理删除 `.tres`，必须由开发者在 Godot FileSystem 中显式处理。
- 旧混合格无法推断元素下方曾被覆盖的自定义 Terrain；导入使用关卡默认地形。
- 斜坡存在时不允许逐格改坡体的底层Grid Terrain/层数；须先删除斜坡。整坡表现地形可通过“斜坡地形”独立设置，但不支持同一斜坡逐格混合。

## 编辑器生命周期约定

- 主界面插件在 Godot 启动时先构建、后隐藏，因此画布可能长时间保持 `0×0` 尺寸。
- 零尺寸时禁止递归 `call_deferred()` 等待布局；只保存待处理标记，由 `resized` 或可见性变化触发一次重置。
- `SplitContainer` 的每一层只放两个布局子控件；地块页用嵌套分割容器组成“工具栏 / 画布 / 检查器”。
- `@tool` 脚本热重载可能保留旧插件实例，但新增成员引用为空；`TerrainStuffEditor` 在刷新 Inspector 或启用斜坡工具前按稳定节点名重新绑定，缺少节点时只补建扩展控件。任何可选扩展控件为空都不得中断既有地形、层数、权限、Stuff 或斜坡 Inspector。
