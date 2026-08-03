# Stuff · 关卡元素

> 实现状态：批次3已完成独立 Stuff 运行时，批次4已完成规范 Stuff 编辑工具。旧 `TileDefinition` 只保留为只读迁移输入；波次页与镜头页未修改。

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
| `StuffDefinition` | `exclusive_with_other_stuff` | 默认 `true`；只有同格双方都为 `false` 才能共存。 |
| `StuffDefinition` | `blocks_tile_building` | 存活时否决块建筑放置。 |
| `StuffDefinition` | `blocks_edge_building` | 存活时否决该格参与的边建筑放置。 |
| `StuffDefinition` | `effect` | 尖刺、黑洞、石头等复用的 `TileEffect` 策略。 |
| `StuffDefinition` | `model_asset` | `ModelAssetDefinition`；运行时自动把可视底部中心对齐到 Grid 表面，`runtime_scale` 仅作为接地后的附加缩放。 |
| `StuffDefinition` | `fallback_visual_kind` / `fallback_color` | 未配置模型时的灰盒类型与颜色。 |
| `StuffPlacementData` | `placement_id` | 单个实例的关卡内唯一 ID，也是状态型效果和镜像共享的根身份。 |
| `StuffPlacementData` | `cell` / `facing_index` | 所在 Grid 格与朝向。 |
| `LevelResource` | `stuff_placements` | 规范关卡的 Stuff 实例数组；允许同格多个合法实例。 |

预设定义位于 `resources/stuffs/`。旧关卡无需立即改写；`LevelContentMigrationAdapter` 会临时生成等价的规范快照。

## 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/stuff/StuffDefinition.gd` | `StuffDefinition / Resource` | 身份、互斥、权限、效果和美术资产。 |
| `scripts/stuff/StuffPlacementData.gd` | `StuffPlacementData / Resource` | 单个作者配置实例。 |
| `scripts/stuff/StuffRuntime.gd` | `StuffRuntime / Node3D` | 独立耐久、效果身份、攻击目标和复制源。 |
| `scripts/stuff/StuffManager.gd` | `StuffManager / Node3D` | 运行时唯一状态/查询入口。 |
| `scripts/stuff/StuffRenderer.gd` | `StuffRenderer / Node3D` | 独立模型与灰盒渲染、复制快照。 |
| `scripts/level/LevelContentMigrationAdapter.gd` | `LevelContentMigrationAdapter / RefCounted` | 旧 Tile 元素到规范 Stuff 的只读映射。 |
| `scripts/tile/TileEffectSystem.gd` | `TileEffectSystem / Node` | 调度 Stuff 与镜像的进入、停留、黑洞容量效果。 |
| `scripts/mirror/MirrorManager.gd` | `MirrorManager / Node3D` | 从最近非空格收集全部 Building 与 Stuff，明确排除 Terrain。 |
| `addons/mirror_tile_editor/terrain_stuff_authoring.gd` | `TerrainStuffAuthoring / RefCounted` | 编辑器互斥校验、稳定ID、朝向和单实例删除。 |
| `addons/mirror_tile_editor/terrain_stuff_editor.gd` | `TerrainStuffEditor / HSplitContainer` | Stuff 调色板与同格多实例检查器。 |
| `tests/stuff_runtime_test.gd` | `SceneTree` | 多 Stuff、权限、耐久、镜像、迁移与回滚回归。 |
| `tests/terrain_stuff_editor_test.gd` | `SceneTree` | 多 Stuff 作者数据、互斥、朝向与单实例删除回归。 |

## 核心 API

| 函数 | 签名 | 职责 |
|---|---|---|
| `StuffManager.load_level` | `(level_resource: LevelResource) -> bool` | 先验证并构造完整下一状态，再一次提交；失败不污染旧状态。 |
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
