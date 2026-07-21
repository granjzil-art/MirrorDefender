# 敌方 AI 系统 · AI

> 实现状态：M4 已完成固定路径移动、屏障攻击状态，以及大石头在前一格触发的“手工路径间动态换路”；不使用行为树或自由网格寻路。

## 职责

定义敌人的最小决策：平时沿波次指定的手工路径前进；遇到建筑屏障时进入射程后停止攻击；下一格被永久地块障碍阻塞时，只在关卡已有手工路径中选择可连接、后缀无阻碍且总边数最短的替代路线。

## 分类 / 做法

- **移动状态**：EnemyUnit 沿 PathManager 解析点逐段移动，大 delta 可跨过多个普通路点。
- **阻挡预判**：每帧按 PathDefinition 的剩余格顺序调用阻挡查询；移动距离会限制在“恰好进入攻击射程”处，避免大帧跨过屏障。
- **攻击状态**：目标屏障进入射程即停步；EnemyAttackStrategy 管理攻速冷却。近战即时伤害，远程生成投射物。
- **恢复移动**：建筑屏障被摧毁或手动删除后，单位沿当前路径继续。
- **受阻换路**：仅当下一格阻断导航时触发 PathRoutePlanner；候选连接点必须是当前格本身或相邻格，候选路径后缀只排除导航阻碍，空洞仍可被选中并在踏入时生效。
- **无路等待**：没有合法手工路径时停在原地；障碍状态变化后可再次尝试。
- **无自由选敌**：敌人不攻击路外塔、不选择最近建筑、不绕行；只认路径顺序中的第一个屏障。

## 关键架构

```text
Main -> WaveManager.configure(..., blocker / route / tile effect Callables)
WaveManager -> EnemyUnit.configure_unit(enemy, authored path + injected queries)

EnemyUnit._process
  -> blocker ahead?
	 ├─ no: move path -> final point -> reached_base
	 ├─ next tile blocked: PathRoutePlanner.find_detour -> install runtime-only route or wait
	 ├─ outside range: limit movement before range boundary
	 └─ inside range: stop -> EnemyAttackStrategy -> barrier damage

Barrier destroyed -> BuildingManager clears Tile occupant/dictionary
  -> next blocker query returns null/next barrier -> resume movement
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit.configure_unit` | `(enemy_definition, path_points, path_cells = [], grid_cell_size = 1.0, blocker_resolver = Callable(), path_definition = null, route_resolver = Callable(), cell_world_resolver = Callable(), tile_enter_resolver = Callable(), tile_stay_resolver = Callable(), navigation_blocker_resolver = Callable()) -> void` | 装配手工路线、攻击参数、换路和地块效果查询。 |
| `EnemyUnit._process` | `(delta: float) -> void` | 在移动与停止攻击之间切换。 |
| `EnemyUnit._find_first_path_blocker` | `() -> Dictionary` | 返回前方首个有效建筑屏障及其路径段/位置；永久导航阻碍截断扫描并交给换路流程。 |
| `PathRoutePlanner.find_detour` | `(current_path, current_cell, blocked_cell, target = null) -> Dictionary` | 在其他手工路径中返回确定性的最短可用后缀，不修改 PathDefinition。 |
| `EnemyUnit.is_attacking` | `() -> bool` | 当前目标有效且在射程内时返回 true。 |
| `EnemyUnit._move_along_path` | `(remaining_distance: float) -> void` | 按距离预算推进并支持跨段。 |
| `EnemyUnit._reach_base` | `() -> void` | 单次广播据点伤害并释放单位。 |

## 约定事实源

- PathDefinition 的格顺序是敌人“前方/后方”的唯一事实源。
- BuildingManager 是路径格屏障存活状态事实源；EnemyUnit 只保存注入的 Callable，不持有 BuildingManager 类型字段。
- `attack_range` 是进入攻击状态的边界；所有敌人在攻击状态都不移动。

## 已知限制 / 初版不做的部分

- 不做行为树、自由格网/A* 寻路、任意绕障、仇恨、围攻位置分配、攻击路外塔或特殊技能；动态换路严格限制在设计者已有路径。
- 多个敌人可重叠站在同一攻击位置；单位碰撞/排队留到后续群体移动优化。
