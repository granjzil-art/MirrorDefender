# Stuff · 关卡元素

> 实现状态：独立 Stuff 运行时、显式元素目录、运行时元素编辑器与 Godot 元素库管理器均已完成。旧 `TileDefinition` 只保留为只读迁移输入；波次页与镜头页未修改。

## 职责与边界

Stuff 是放在 Grid 表面上的关卡对象，不是地形，也不是玩家建筑。它可以携带效果、耐久、互斥规则、建造限制和模型，但不得修改 Terrain 身份、体素层数、斜坡或手工路径。

运行时事实源分为三层：

- `StuffManager`：装配、索引、权限合成、效果绑定、导航阻挡与移除事务。
- `StuffRuntime`：单个实例的格位置、朝向、耐久和镜像共享源身份。
- `StuffRenderer`：模型/灰盒、同格错位显示、黑洞填充深度和复制快照；不修改玩法状态。

`TileManager` 在正式 `Main` 中仅作为既有建筑、寻路模块的兼容门面。`legacy_content_runtime_enabled=false` 时，它不再创建旧 Tile 元素或旧石头耐久，只把查询转发给 `StuffManager`。

## 配置参数

| 资源 | 参数 | 说明 |
|---|---|---|
| `StuffDefinition` | `stuff_id` / `display_name` | 稳定类型 ID 与显示名称。 |
| `StuffDefinition` | `description` / `authoring_enabled` | 创作工具说明；禁用后从新建调色板隐藏，但已有实例和资源引用仍有效。 |
| `StuffDefinition` | `exclusive_with_other_stuff` | 默认 `true`；只有同格双方都为 `false` 才能共存。 |
| `StuffDefinition` | `blocks_tile_building` | 存活时否决块建筑放置。 |
| `StuffDefinition` | `blocks_edge_building` | 存活时否决该格参与的边建筑放置。 |
| `StuffDefinition` | `enemy_navigation` | `FOLLOW_EFFECT / PASSABLE / BLOCKED`；新元素必须显式选择是否堵路，旧资源可继续跟随效果策略。 |
| `StuffDefinition` | `navigation_affects_airborne` | 显式堵路时是否也阻挡空中敌人。 |
| `StuffDefinition` | `durability_mode` / `max_durability` | `FOLLOW_EFFECT / INDESTRUCTIBLE / DESTRUCTIBLE`；允许无自定义 Effect 的新元素直接配置耐久。 |
| `StuffDefinition` | `effect` | 尖刺、黑洞、石头等复用的 `TileEffect` 策略。 |
| `StuffDefinition` | `model_asset` | `ModelAssetDefinition`；运行时自动把可视底部中心对齐到 Grid 表面，`runtime_scale` 仅作为接地后的附加缩放。 |
| `StuffDefinition` | `fallback_visual_kind` / `fallback_color` | 未配置模型时的灰盒类型与颜色。 |
| `StuffPlacementData` | `placement_id` | 单个实例的关卡内唯一 ID，也是状态型效果和镜像共享的根身份。 |
| `StuffPlacementData` | `cell` / `facing_index` | 所在 Grid 格与朝向。 |
| `LevelResource` | `stuff_placements` | 规范关卡的 Stuff 实例数组；允许同格多个合法实例。 |
| `StuffCatalog` | `definitions` | 显式白名单；数组顺序是关卡编辑器和运行时编辑器的调色板顺序。 |

预设定义位于 `resources/stuffs/`。旧关卡无需立即改写；`LevelContentMigrationAdapter` 会临时生成等价的规范快照。

## 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/stuff/StuffDefinition.gd` | `StuffDefinition / Resource` | 身份、互斥、权限、效果和美术资产。 |
| `scripts/stuff/StuffCatalog.gd` | `StuffCatalog / Resource` | 元素类型白名单、启用状态、顺序、查找与重复 ID 校验。 |
| `scripts/stuff/StuffCatalogAuthoring.gd` | `StuffCatalogAuthoring / RefCounted` | 新建、复制、持久化、ID 规约与关卡引用保护事务。 |
| `scripts/stuff/StuffPlacementData.gd` | `StuffPlacementData / Resource` | 单个作者配置实例。 |
| `scripts/stuff/StuffRuntime.gd` | `StuffRuntime / Node3D` | 独立耐久、效果身份、攻击目标和复制源。 |
| `scripts/stuff/StuffManager.gd` | `StuffManager / Node3D` | 运行时唯一状态/查询入口。 |
| `scripts/stuff/StuffRenderer.gd` | `StuffRenderer / Node3D` | 独立模型与灰盒渲染、复制快照。 |
| `scripts/stuff/StuffPlacementValidator.gd` | `StuffPlacementValidator / RefCounted` | 运行时预览与提交共用的边界、互斥、占位、方向和路径校验。 |
| `scripts/stuff/RuntimeStuffEditSession.gd` | `RuntimeStuffEditSession / Node` | Stuff 快照、撤销/重做、普通保存、可选全量初始陈列保存与放弃恢复事务。 |
| `scripts/stuff/RuntimeStuffEditorController.gd` | `RuntimeStuffEditorController / Node3D` | 运行时创作状态机、真实模型预览、选择、旋转和时间冻结。 |
| `scripts/ui/RuntimeStuffEditorPanel.gd` | `RuntimeStuffEditorPanel / Control` | 局内元素目录、单实例删除、历史、保存/退出和不可达作者开关。 |
| `addons/mirror_tile_editor/stuff_catalog_manager.gd` | `StuffCatalogManager / Window` | Godot 编辑器内的数据化元素类型管理窗口。 |
| `scripts/level/LevelContentMigrationAdapter.gd` | `LevelContentMigrationAdapter / RefCounted` | 旧 Tile 元素到规范 Stuff 的只读映射。 |
| `scripts/tile/TileEffectSystem.gd` | `TileEffectSystem / Node` | 调度 Stuff 与镜像的进入、停留、黑洞容量效果。 |
| `scripts/mirror/MirrorManager.gd` | `MirrorManager / Node3D` | 从最近非空格收集全部 Building 与 Stuff，明确排除 Terrain。 |
| `addons/mirror_tile_editor/terrain_stuff_authoring.gd` | `TerrainStuffAuthoring / RefCounted` | 编辑器互斥校验、稳定ID、朝向和单实例删除。 |
| `addons/mirror_tile_editor/terrain_stuff_editor.gd` | `TerrainStuffEditor / HSplitContainer` | Stuff 调色板与同格多实例检查器。 |
| `tests/stuff_runtime_test.gd` | `SceneTree` | 多 Stuff、权限、耐久、镜像、迁移与回滚回归。 |
| `tests/stuff_catalog_test.gd` | `SceneTree` | 正式目录、启用状态、重复 ID 与导航契约回归。 |
| `tests/stuff_catalog_authoring_test.gd` | `SceneTree` | 新建、复制、保存与关卡引用保护回归。 |
| `tests/stuff_catalog_manager_editor_test.gd` | `SceneTree` | 编辑器态窗口和目录列表烟测；普通运行态跳过 UI 实例化。 |
| `tests/runtime_stuff_edit_session_test.gd` | `SceneTree` | 放置、旋转、删除、历史、回滚和保存事务回归。 |
| `tests/runtime_stuff_editor_test.gd` | `SceneTree` | 运行时入口、目录、预览颜色、重叠实例选择/显式删除和时间冻结回归。 |
| `tests/terrain_stuff_editor_test.gd` | `SceneTree` | 多 Stuff 作者数据、互斥、朝向与单实例删除回归。 |

## 核心 API

| 函数 | 签名 | 职责 |
|---|---|---|
| `StuffManager.load_level` | `(level_resource: LevelResource) -> bool` | 先验证并构造完整下一状态，再一次提交；失败不污染旧状态。 |
| `StuffManager.export_placements` | `() -> Array[StuffPlacementData]` | 导出与运行时节点隔离的规范作者快照。 |
| `StuffManager.add_stuff` | `(cell: Vector3i, definition: StuffDefinition, facing_index: int = 0, placement_id: StringName = &"") -> StuffRuntime` | 原子新增一个运行时实例，不直接写回 LevelResource。 |
| `StuffManager.rotate_stuff` | `(placement_id: StringName, step: int = 1) -> bool` | 按当前网格方向数旋转实例并广播刷新。 |
| `StuffManager.replace_runtime_placements` | `(placements: Array) -> bool` | 完整预构造成功后替换 Stuff 集合；供撤销、重做与放弃使用。 |
| `StuffManager.get_stuff_at` | `(cell: Vector3i) -> Array[StuffRuntime]` | 按 `placement_id` 稳定排序返回同格全部实例。 |
| `StuffManager.get_effect_bindings` | `(cell: Vector3i) -> Array[Dictionary]` | 返回 `{effect, source_cell, state_key, source}`；`state_key=stuff:<placement_id>`。 |
| `StuffManager.allows_tile_building` | `(cell: Vector3i) -> bool` | 汇总同格全部 Stuff 的块建筑否决。 |
| `StuffManager.allows_edge_building` | `(cell: Vector3i) -> bool` | 汇总同格全部 Stuff 的边建筑否决。 |
| `StuffManager.resolve_navigation_blocker` | `(cell: Vector3i, target: Node = null) -> Node` | 返回敌人可攻击的具体 Stuff 阻挡体。 |
| `StuffManager.remove_stuff` | `(placement_id: StringName) -> bool` | 只移除一个实例及其限制，并发出刷新信号。 |
| `StuffRuntime.take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 修改独立运行时耐久；归零后通知 Manager 删除自身。 |
| `StuffRenderer.create_stuff_visual_snapshot` | `(placement_id: StringName) -> Node3D` | 为复制镜生成与实体模型/灰盒一致的无行为快照。 |
| `TerrainStuffAuthoring.add_stuff` | `(level: Resource, cell: Vector3i, definition: Resource, facing_index: int) -> Dictionary` | 返回 `{success, message, placement}`；双向校验互斥并生成稳定ID。 |
| `TerrainStuffAuthoring.remove_stuff` | `(level: Resource, placement_id: StringName) -> bool` | 编辑器只删除一个 Stuff 作者实例。 |
| `StuffCatalog.get_enabled_definitions` | `() -> Array[StuffDefinition]` | 按目录顺序返回可用于新建的定义。 |
| `StuffCatalogAuthoring.create_definition` | `(catalog: StuffCatalog, requested_id: String, display_name: String, model_scene: PackedScene = null, runtime_scale: Vector3 = Vector3.ONE) -> Dictionary` | 返回 `{success, message, definition}`；建立显式导航、耐久和放置默认值并注册目录。 |
| `StuffCatalogAuthoring.save_definition` | `(catalog: StuffCatalog, definition: StuffDefinition, definition_directory: String = "res://resources/stuffs", catalog_path: String = "") -> Dictionary` | 校验并依次保存独立定义与目录，返回 `{success, message, definition, path}`。 |
| `StuffCatalogAuthoring.save_catalog` | `(catalog: StuffCatalog, definition_directory: String = "res://resources/stuffs", catalog_path: String = "") -> Dictionary` | 一次校验并保存目录内全部已修改/新建定义，最后保存目录；避免切换选择后漏存早先修改。 |
| `StuffCatalogAuthoring.remove_definition_if_unreferenced` | `(catalog: StuffCatalog, definition: StuffDefinition, level_directory: String) -> Dictionary` | 扫描 LevelResource；有引用时拒绝，成功仅移出目录、不删除文件。 |
| `StuffPlacementValidator.validate_placement` | `(cell: Vector3i, definition: StuffDefinition, facing_index: int = 0, placement_id: StringName = &"") -> Dictionary` | 返回 `{valid, warning, reason, placement_id}`；硬错误与可覆盖的断路作者警告分离。 |
| `StuffManager.refresh_world_transforms` | `() -> void` | Terrain变化后让全部现有 Stuff 重新采样表面高度，保留耐久与效果状态。 |
| `RuntimeStuffEditSession.preview_terrain_change` | `(operation: StringName, parameters: Dictionary) -> Dictionary` | 构建并临时装配通过完整校验的 Terrain/Ramp 候选；只影响可视预览，不进入历史。 |
| `RuntimeStuffEditSession.commit_terrain_preview` | `() -> Dictionary` | 把当前可视候选作为一个原子操作写入 Terrain/Stuff 共用历史。 |
| `RuntimeStuffEditSession.apply_terrain_change` | `(operation: StringName, parameters: Dictionary) -> Dictionary` | 提交选中斜坡旋转、移除或覆盖地形等非悬停操作。 |
| `RuntimeStuffEditSession.save` | `(destination_path: String = "", include_initial_layout: bool = false) -> Dictionary` | 返回 `{success, path, message}`；默认只更新 Stuff；全量模式同时写入 Grid、Ramp、Stuff、实体建筑和复制镜初始陈列。编辑器内保存原 `res://`，导出运行时默认保存到 `user://levels/`。 |
| `RuntimeStuffEditSession.can_save_full_layout` | `() -> bool` | 两个只读快照 Provider 均有效时返回 true。 |
| `RuntimeStuffEditorController.save_full_layout` | `() -> Dictionary` | UI 全量保存入口并统一广播成功/失败状态。 |
| `RuntimeStuffEditorController.set_active` | `(value: bool) -> bool` | 开关统一运行时关卡创作会话；脏会话禁止静默关闭。 |
| `RuntimeStuffEditorController.handle_primary` | `(cell_pick: Dictionary) -> Dictionary` | 按当前工具提交地形、高度、斜坡或Stuff；选择工具可选择同格Stuff或斜坡。 |
| `RuntimeStuffEditorController.remove_selected` | `() -> bool` | 删除当前选中的一个 Stuff 或整段斜坡；面板按钮与 `Delete` 共用事务入口。 |

## 数据流

```text
LevelResource
  -> validate_runtime()
  -> get_effective_content_snapshot()
  -> TerrainManager.load_level()
  -> StuffManager.load_level()
  -> TileManager.load_level()

StuffManager
  -> TileManager 兼容查询 -> Building / Path / Enemy
  -> TileEffectSystem      -> 进入、停留、黑洞容量
  -> StuffRenderer         -> 实体模型与动态深度
  -> MirrorManager         -> 同格全部 Stuff 的投影 payload
  -> TileInspectionService -> 右侧对象详情

Runtime HUD 运行时关卡编辑
  -> RuntimeStuffEditorController
     -> RuntimeTerrainEditService -> 隔离 LevelResource 候选
     -> TerrainManager.replace_runtime_content -> 真实平地/斜坡预览
     -> StuffPlacementValidator -> PathPlacementConnectivityGuard（只产生作者警告）
     -> RuntimeStuffEditSession -> Terrain/Ramp/Stuff 统一快照、历史与回滚
     -> StuffRenderer.create_preview_visual -> 真实模型绿/红预览
     -> 显式保存 -> LevelResource 深副本 -> res:// 或 user://levels

Godot 元素库管理器
  -> StuffCatalogAuthoring
     -> StuffDefinition 独立 .tres
     -> StuffCatalog.tres 顺序白名单
     -> 删除前扫描 resources/levels 的引用
  -> catalog_changed -> TerrainStuffEditor 仅重建 Stuff 调色板
```

`LevelLoader` 把 Grid、Terrain、Stuff、Tile 作为一个装配事务：如果后续 Tile 装配失败，会恢复旧 Grid 配置，并重新装配旧 Terrain 与旧 Stuff。运行时资源副本不写回 `.tres`。

## 权限合成

```text
有效块建筑权限
  = GridCellData.allows_tile_building
  AND 全部存活 Stuff 均不 blocks_tile_building
  AND 没有实体块建筑 occupant

有效边建筑权限
  = 物理边两侧 GridCellData.allows_edge_building
  AND 两侧全部存活 Stuff 均不 blocks_edge_building
  AND 物理边未被其它边建筑占用
```

石头摧毁只删除石头 `StuffRuntime`。底层 Terrain、层数、路径和 `GridCellData` 不变，因此权限自然恢复为 Grid 原配置；旧石头格迁移时的底层 Grid 默认允许两类建筑，以保持既有玩法。

## 效果与镜像

- 同格每个 Stuff 都有独立效果绑定；即使两个黑洞共用同一个 `VoidTileEffect` 资源，也使用不同 `state_key` 保存容量和冷却。
- 镜像 payload 保留根 `StuffRuntime`，直接与递归虚像共享根效果状态和可破坏耐久；销毁根石头会使相关虚像失效。
- 一面镜子命中最近非空格后，会复制该格全部可复制 Building 与全部可复制 Stuff。
- Terrain 基底、路径色、体素层数和斜坡不会进入 `MirrorManager` 的内容图，也不会出现在 Stuff 快照中。

## 兼容与后续边界

- 旧 `TileCellData / TileDefinition` 仍可加载，但只作为迁移输入；正式 Main 中旧元素渲染和旧耐久已关闭。
- 独立 `TileManager` 测试与旧工具默认保留 `legacy_content_runtime_enabled=true`，防止一次切换破坏旧模块回归。
- 关卡编辑器已可按定义的双向互斥规则放置同格多 Stuff，并逐实例编辑朝向/删除；波次页、镜头页及它们的序列化数据未修改。
- 运行时编辑器可修改 Terrain 类型、1～4层高度、1:1～1:4斜坡与 Stuff；不修改路径、波次、镜头或经济。进入编辑时冻结玩法时间；UI 与输入仍可工作。地形预览只刷新高度相关表现，不重建建筑/Stuff战斗状态或耐久。
- 断路放置默认以红色预览和警告拒绝；“允许不可达布局”是作者工具显式覆盖，不改变正式玩家障碍放置的强制连通性守卫。
- 运行时保存没有覆盖权限时写入 `user://levels/<原文件名>.tres`；该文件不会自动加入正式选关目录。
