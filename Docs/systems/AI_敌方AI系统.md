# 敌方 AI 系统 · AI

> 实现状态：M4 已完成固定路径移动、屏障攻击状态，以及大石头在前一格触发的“手工路径间动态换路”；大石头无可用路径时会转为共享源耐久的攻击目标。不使用行为树或自由网格寻路。

## 职责

定义敌人的最小决策：平时沿波次指定的手工路径前进；普通屏障受阻后直接攻击；下一格被大石头阻塞时，先在关卡已有手工路径中选择可连接、后缀无阻碍且总边数最短的替代路线，无可用路线才攻击石头。

## 分类 / 做法

- **移动状态**：EnemyUnit 沿 PathManager 解析点逐段移动，大 delta 可跨过多个普通路点。
- **阻挡预判**：每帧按 PathDefinition 的剩余格顺序调用阻挡查询；移动距离会限制在“恰好进入攻击射程”处，避免大帧跨过屏障。
- **攻击状态**：目标屏障进入射程即停步；EnemyAttackStrategy 管理攻速冷却。近战即时伤害，远程生成投射物。
- **恢复移动**：建筑屏障被摧毁或手动删除后，单位沿当前路径继续。
- **受阻换路**：当逻辑上的下一格阻断导航时触发 PathRoutePlanner；判定依据是当前路径段而非必须站在前一格中心，因此同格普通屏障被攻破、石头虚影在帧末重建后仍会重新换路/攻击。候选连接点必须是当前格本身或相邻格，候选路径后缀只排除导航阻碍，空洞仍可被选中并在踏入时生效。
- **无路攻击**：大石头没有合法手工替代路径时，由 PathRoutePlanner 返回具体运行时阻挡目标；敌人复用屏障攻击状态靠近并攻击，石头摧毁后沿原路径继续。
- **策略差异**：普通屏障是 `DIRECT_ATTACK`；大石头是 `REROUTE_THEN_ATTACK`。两者使用相同结构伤害契约，差异只发生在受阻后的决策顺序。
- **无自由选敌**：敌人不攻击路外塔、不选择最近建筑、不绕行；只认路径顺序中的第一个屏障。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/path/PathBlockerPolicy.gd` | `PathBlockerPolicy` / `RefCounted` | 普通直接攻击与大石头先换路后攻击的共享策略枚举。 |
| `scripts/path/PathRoutePlanner.gd` | `PathRoutePlanner` / `Node3D` | 从手工路径选择最短可用后缀，并在失败时返回当前石头攻击代理。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | 编排移动、直接屏障攻击、大石头换路与失败攻击状态。 |
| `scripts/tile/TileObstacleRuntime.gd` | `TileObstacleRuntime` / `Node3D` | 真实石头逐格耐久与结构攻击契约。 |

```text
Main -> WaveManager.configure(..., blocker / route / tile effect Callables)
WaveManager -> EnemyUnit.configure_unit(enemy, authored path + injected queries)

EnemyUnit._process
  -> blocker ahead?
	 ├─ no: move path -> final point -> reached_base
	 ├─ ordinary blocker: attack directly
	 ├─ rock: PathRoutePlanner.find_detour -> install runtime route
	 │    └─ no route: promote returned rock proxy/projection to attack target
	 ├─ outside range: limit movement before range boundary
	 └─ inside range: stop -> EnemyAttackStrategy -> shared-source structure damage

Barrier destroyed -> BuildingManager clears Tile occupant/dictionary
Rock destroyed -> TileManager clears runtime obstacle/effect and restores building permissions
  -> next blocker query returns null/next blocker -> resume movement
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit.configure_unit` | `(enemy_definition, path_points, path_cells = [], grid_cell_size = 1.0, blocker_resolver = Callable(), path_definition = null, route_resolver = Callable(), cell_world_resolver = Callable(), tile_enter_resolver = Callable(), tile_stay_resolver = Callable(), navigation_blocker_resolver = Callable()) -> void` | 装配手工路线、攻击参数、换路和地块效果查询。 |
| `EnemyUnit._process` | `(delta: float) -> void` | 在移动与停止攻击之间切换。 |
| `EnemyUnit._find_first_path_blocker` | `() -> Dictionary` | 先返回前方首个普通可攻击屏障；大石头导航阻碍截断后续扫描并交给换路流程。 |
| `EnemyUnit._get_reroute_attack_blocker_info` | `() -> Dictionary` | 把换路失败返回的大石头代理包装成复用攻击移动所需的路径段信息。 |
| `EnemyUnit._is_blocker_alive` | `(blocker: Variant) -> bool` | 在收窄为结构攻击契约前拦截已释放对象，避免多敌人共享阻挡目标时的帧末生命周期竞态。 |
| `PathRoutePlanner.find_detour` | `(current_path, current_cell, blocked_cell, target = null) -> Dictionary` | 返回 `{triggered, found, path, cells, cost, join_cell, blocker}`；找到最短手工后缀，或在失败时返回具体石头攻击目标。 |
| `EnemyUnit.is_attacking` | `() -> bool` | 当前目标有效且在射程内时返回 true。 |
| `EnemyUnit._move_along_path` | `(remaining_distance: float) -> void` | 按距离预算推进并支持跨段。 |
| `EnemyUnit._reach_base` | `() -> void` | 单次广播据点伤害并释放单位。 |

## 约定事实源

- PathDefinition 的格顺序是敌人“前方/后方”的唯一事实源。
- BuildingManager 是普通屏障存活状态事实源，TileManager 是真实石头运行时耐久事实源，MirrorManager 提供石头投影代理；EnemyUnit 只保存注入的 Callable 和当前攻击目标，不持有这些管理器的类型字段。
- `attack_range` 是进入攻击状态的边界；所有敌人在攻击状态都不移动。

## 已知限制 / 初版不做的部分

- 不做行为树、自由格网/A* 寻路、任意绕障、仇恨、围攻位置分配、攻击路外塔或特殊技能；动态换路严格限制在设计者已有路径。
- 多个敌人可重叠站在同一攻击位置；单位碰撞/排队留到后续群体移动优化。
