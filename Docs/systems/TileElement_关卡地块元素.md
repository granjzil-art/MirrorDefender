# 关卡地块元素 · Tile Element

> 实现状态：已完成尖刺、空洞、大石头障碍，以及基于手工路径的动态换路。支持正方形与六边形关卡。

## 职责

关卡元素是直接写入 `TileCellData` 的地形配置，不是 `Building`，不占用建筑上限，不参与建造/升级/删除事务。本系统提供可复用地块定义、敌人进入/停留效果、灰盒表现和大石头换路。

## 分类 / 玩法

- **尖刺格子**：可通行；敌人占据该格的时间按秒造成持续伤害。默认 20 伤害/秒且忽略护甲。
- **空洞格子**：导航上可通行，初始路径和动态换路都可以经过；敌人进入时立即死亡。默认按 1.0 倍发放该敌人的掉落资源。
- **大石头障碍**：存活时不可通行。敌人到达石头前一格中心时先请求换路；没有可用路径则把石头视为普通可攻击障碍。耐久归零后清除元素与阻挡，并允许块建筑和边建筑。
- **空中适用性**：每个 TileEffect 用 `affects_airborne` 独立决定进入、停留和导航阻挡是否作用于飞行敌人；关闭后飞行敌人沿原手工路径穿过，不触发该效果或换路。
- **建筑权限**：三者默认 `allows_tile_building = false` 且 `allows_edge_building = true`。边建筑所在共享边的两个相邻格都必须允许边建筑。
- **基底/元素分层**：尖刺、空洞和大石头只用 `visual_color` / `visual_scene` 绘制内容层，不覆盖地块基底；因此路径格仍显示 `#FFB93B`，非路径格仍显示自身高度/路面色。
- **复制镜投影**：三类效果通过 `get_copy_kind/display_name/color` 进入统一 payload。投影只复制元素内容几何，不复制地表基底色/高度几何，也不修改目标 TileCellData；石头投影把结构伤害转发到真实源石头，直接/递归投影共享该源的运行时耐久。源石头摧毁后全部关联投影消失，镜子保留。

## 编辑器使用

1. 打开 Godot 主屏的 Mirror 关卡编辑器，进入“地块”页。
2. 在“地块调色板”选择“尖刺格子”、“空洞格子”或“大石头障碍”，左键单击/拖动涂刷；也可拖放预设到单格。
3. 类型刷只替换地块定义，保留该格当前高度；高度刷只改高度。
4. 路径页仍手工绘制全部候选路径。大石头可直接画在初始路径上；候选路径必须与触发格相交或相邻，且从接入格到据点的后缀不含对该敌人有效的导航阻碍。尖刺和空洞仍可被选择。
5. 调色板会自动扫描 `resources/tiles/*.tres`；新增 `TilePreset` 资源后无需修改编辑器脚本。

## 关键参数

| 资源 | 参数 | 说明 |
|---|---|---|
| `TileDefinition` | `tile_id` / `display_name` | 稳定标识与编辑器名称。 |
| `TileDefinition` | `surface_kind` | 可建造、可破坏、路面或关卡元素的表面分类。 |
| `TileDefinition` | `allows_tile_building` | 是否允许普通块建筑和路径块建筑。 |
| `TileDefinition` | `allows_edge_building` | 是否允许该格参与的共享边放置边建筑。 |
| `TileDefinition` | `effect` | 敌人遍历效果策略，可替换为新 `TileEffect` 变种。 |
| `TileDefinition` | `override_terrain_color` / `terrain_color` | 非 `ELEMENT` 表面可用的基底覆盖；元素表面始终忽略此覆盖并保留路径/高度基底。 |
| `TileDefinition` | `visual_kind` / `visual_color` / `visual_scene` | 灰盒类型、灰盒颜色与未来正式美术场景接口。 |
| `TileEffect` | `enemy_traversal` | `PASSABLE` 或 `BLOCKED`。 |
| `TileEffect` | `affects_airborne` | 进入/停留效果与导航阻挡是否作用于飞行敌人；默认 true 兼容旧资源。 |
| `SpikeTileEffect` | `damage_per_second` / `ignores_armor` | 每秒伤害与是否绕过 `EnemyUnit.armor`。 |
| `VoidTileEffect` | `reward_multiplier` | 空洞击杀时的敌人掉落倍率。 |
| `RockTileEffect` | `max_durability` | 每个真实石头运行时耐久上限；正式 `Rock.tres` 默认 500。投影不创建独立耐久。 |
| `PathRoutePlanner` | `feature_enabled` | 动态换路功能开关。 |
| `PathRoutePlanner` | `show_selected_detour` / `detour_color` / `line_lift` | 最近选中换路的运行时调试线。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/tile/TileDefinition.gd` | `TileDefinition` / `Resource` | 整合地块表面、建筑权限、效果与表现配置。 |
| `scripts/tile/effects/TileEffect.gd` | `TileEffect` / `Resource` | 敌人遍历策略基类。 |
| `scripts/tile/effects/SpikeTileEffect.gd` | `SpikeTileEffect` / `TileEffect` | 按占格时间结算持续伤害。 |
| `scripts/tile/effects/VoidTileEffect.gd` | `VoidTileEffect` / `TileEffect` | 进格时立即击杀并应用掉落倍率。 |
| `scripts/tile/effects/RockTileEffect.gd` | `RockTileEffect` / `TileEffect` | 声明耐久、导航阻断和摧毁后建筑权限。 |
| `scripts/tile/TileObstacleRuntime.gd` | `TileObstacleRuntime` / `Node3D` | 每个真实石头独立的运行时耐久、攻击位置和结构伤害入口。 |
| `scripts/tile/TileEffectSystem.gd` | `TileEffectSystem` / `Node` | 通过 TileManager 解析地块效果并分发进入/停留事件。 |
| `scripts/mirror/MirrorManager.gd` | `MirrorManager` / `Node3D` | 提供非占位投影效果和导航覆盖查询。 |
| `scripts/path/PathRoutePlanner.gd` | `PathRoutePlanner` / `Node3D` | 在手工路径集中选择确定性最短可用后缀。 |
| `scripts/tile/TileCellData.gd` | `TileCellData` / `Resource` | 引用 TileDefinition，保留旧 `tile_type` 兼容分支。 |
| `scripts/tile/TilePreset.gd` | `TilePreset` / `Resource` | 关卡编辑器画笔预设。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | 绘制地形与三种元素灰盒。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 提供不受护甲伤害和指定掉落倍率的击杀入口。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | 逐格分发效果，在阻碍前一格安装临时路由。 |
| `tests/tile_elements_and_rerouting_test.gd` | 无 / `SceneTree` | 地块权限、双网格换路、高速跨格和资源不变性回归。 |
| `tests/airborne_effects_test.gd` | 无 / `SceneTree` | 地块效果与导航阻挡的空中适用性回归。 |
| `tests/path_terrain_color_test.gd` | 无 / `SceneTree` | 三类元素的基底/内容分层与路径色回归。 |

### 数据流

```text
Level Editor -> TilePreset -> TileCellData.definition -> LevelResource.tiles
  -> TileManager 克隆运行时格
     -> TileObstacleRuntime(real cell) -> independent durability
     -> TileRenderer 路径/高度基底 + 独立元素灰盒
     -> TileEffectSystem -> TileEffect.affects_target -> damage/defeat or ignore
     -> PathRoutePlanner(target) -> 目标可用的 PathDefinition 后缀 -> EnemyUnit 临时路由

MirrorManager projection overlay
  -> TileEffectSystem.set_effect_overlay_resolver -> base + all projected effects
  -> TileManager.set_navigation_overlay_resolver -> projected rock blocks navigation
  -> projected rock.take_structure_damage -> real TileObstacleRuntime

BuildingPlacementRules
  -> TileManager.allows_edge_building(边两侧)
  -> TileManager.can_place / can_place_path_occupant(块建筑)
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `TileDefinition.blocks_enemy_navigation` | `(target: Node = null) -> bool` | 委托效果策略判断是否阻断指定敌人；null 保留旧的无分类查询。 |
| `TileDefinition.can_use_for_reroute` | `(target: Node = null) -> bool` | 判断该格是否可用于指定敌人的候选路径后缀。 |
| `TileDefinition.get_base_terrain_color` | `(fallback: Color) -> Color` | 元素表面返回外部解析的路径/路面/高度基底，非元素才能应用自定义覆盖。 |
| `TileEffect.affects_target` | `(target: Node) -> bool` | 依据 `affects_airborne` 与目标分类返回效果是否适用。 |
| `TileEffect.can_use_for_reroute` | `(target: Node = null) -> bool` | 仅返回该效果是否未对指定目标阻断导航；不评估尖刺/空洞等危害。 |
| `TileDefinition.get_visual_tag` / `TileCellData.get_visual_tag` | `() -> StringName` | 向编辑器工具提供稳定的灰盒类型标签，避免 tool 脚本热重载直接依赖运行时全局枚举。 |
| `TileCellData.allows_tile_building` / `allows_edge_building` | `() -> bool` | 返回当前格的两类建筑权限。 |
| `TileEffect.apply_enter` | `(target: Node) -> void` | 敌人进入格子时的策略入口。 |
| `TileEffect.apply_stay` | `(target: Node, duration: float) -> void` | 敌人占格持续时间的策略入口。 |
| `TileEffect.get_copy_kind/get_copy_display_name/get_copy_color` | `() -> StringName/String/Color` | 以可扩展契约描述镜子复制语义与灰盒表现。 |
| `TileEffect.creates_runtime_obstacle` | `() -> bool` | 声明该效果是否需要逐格运行时耐久；默认 false。 |
| `TileEffect.get_max_durability` | `() -> float` | 返回运行时障碍初始/最大耐久；无耐久效果默认 0。 |
| `TileObstacleRuntime.take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 扣减单个真实石头耐久，归零时通知 TileManager 清除障碍。 |
| `TileManager.resolve_navigation_blocker` | `(cell: Vector3i, target: Node = null) -> Node` | 返回真实石头或注入的石头投影攻击目标，真实地块内容优先。 |
| `TileEffectSystem.set_effect_overlay_resolver` | `(value: Callable) -> void` | 注入非占位效果覆盖层，不依赖 Mirror 类型。 |
| `TileEffectSystem.apply_enter` | `(target: Node, cell: Vector3i) -> void` | 解析指定格并分发进入效果。 |
| `TileEffectSystem.apply_stay` | `(target: Node, cell: Vector3i, duration: float) -> void` | 解析指定格并分发持续效果。 |
| `PathRoutePlanner.find_detour` | `(current_path: PathDefinition, current_cell: Vector3i, blocked_cell: Vector3i, target: Node = null) -> Dictionary` | 返回 `{triggered, found, path, cells, cost, join_cell, blocker}`；无替代路线时携带当前可攻击石头代理。 |
| `CombatTarget.take_unmitigated_damage` | `(amount: float) -> float` | 不经 EnemyUnit 护甲覆写的环境伤害入口。 |
| `CombatTarget.take_damage_over_time` | `(damage_per_second: float, duration: float) -> float` | 帧率无关的持续伤害入口；EnemyUnit 以护甲扣减每秒伤害率。 |
| `CombatTarget.defeat` | `(reward_multiplier: float = 1.0) -> bool` | 立即击杀并按倍率发出掉落值。 |
| `EnemyUnit.configure_unit` | `(..., path_definition: PathDefinition, route_resolver: Callable, cell_world_resolver: Callable, tile_enter_resolver: Callable, tile_stay_resolver: Callable, navigation_blocker_resolver: Callable) -> void` | 注入路径、换路、坐标和地块效果接口；旧参数保持兼容。 |

## 换路事实源

- 敌人出生时仍使用波次组中原始 `PathDefinition`，不预先重算。
- 只在敌人位于当前格中心且下一格为导航阻碍时安装临时路由。
- 候选只是其他手工 `PathDefinition`；必须包含当前格（接入代价 0）或有一格与当前格相邻（代价 1）。线条在二维投影中相交不算路径相交。
- 选择分数为“接入边 + 候选路径后缀边数”；最低分优先，平分时按 `LevelResource.paths` 的序列化顺序稳定决胜。
- 候选后缀每格必须在边界内、路径相邻且不对当前敌人阻断导航。地块过滤的唯一规则是 `blocks_enemy_navigation(target) == false`；空洞和尖刺均可选。建筑屏障仍是可攻击目标，不会使候选路径失效。
- 换路只替换单个敌人的运行时数组，不修改 `LevelResource` 或 `PathDefinition`。后续再遇石头可再次选路。
- 没有候选路径时不修改当前路径；敌人攻击当前石头。源耐久归零后 TileManager 把该运行时格标为已清障，隐藏元素、解除阻挡并开放两类建筑权限；重新加载关卡会从未修改的配置快照恢复石头。

## 已知限制

- 当前不做自由格网 A*，也不同时串联多条路径；每次阻挡事件只选一条候选路径的一个后缀。
- `visual_scene` 为正式美术资产预留接口，当前编辑器与运行时使用 `visual_kind` 灰盒绘制。
- 编辑器画布通过 `get_visual_tag()` 读取灰盒类型；新增可视类型时需同步扩展标签映射与画布图形。
- 大石头虽然可被敌人攻击，但仍是关卡元素而不是 Building：不参与建筑上限、升级、退款和玩家删除事务。
