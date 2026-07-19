# 敌方 AI 系统 · AI

> 实现状态：M4 已完成固定路径移动，以及由路径屏障触发的移动/攻击双状态；不使用行为树或动态寻路。

## 职责

定义敌人的最小决策：沿指定路径前进，查询尚未经过路径上的第一个屏障；进入射程后停止攻击，屏障消失后继续移动，最终抵达据点。

## 分类 / 做法

- **移动状态**：EnemyUnit 沿 PathManager 解析点逐段移动，大 delta 可跨过多个普通路点。
- **阻挡预判**：每帧按 PathDefinition 的剩余格顺序调用阻挡查询；移动距离会限制在“恰好进入攻击射程”处，避免大帧跨过屏障。
- **攻击状态**：目标屏障进入射程即停步；EnemyAttackStrategy 管理攻速冷却。近战即时伤害，远程生成投射物。
- **恢复移动**：屏障被摧毁或手动删除后，查询返回下一个屏障或 null，单位沿原路径继续，不重算路线。
- **无自由选敌**：敌人不攻击路外塔、不选择最近建筑、不绕行；只认路径顺序中的第一个屏障。

## 关键架构

```text
Main -> WaveManager.configure(..., BuildingManager.get_path_blocker Callable)
WaveManager -> EnemyUnit.configure_unit(enemy, world_points, path_cells, cell_size, blocker_resolver)

EnemyUnit._process
  -> blocker ahead?
     ├─ no: move path -> final point -> reached_base
     ├─ outside range: limit movement before range boundary
     └─ inside range: stop -> EnemyAttackStrategy -> barrier damage

Barrier destroyed -> BuildingManager clears Tile occupant/dictionary
  -> next blocker query returns null/next barrier -> resume movement
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit.configure_unit` | `(enemy_definition: EnemyDefinition, path_points: PackedVector3Array, path_cells: Array[Vector3i] = [], grid_cell_size: float = 1.0, blocker_resolver: Callable = Callable()) -> void` | 装配移动路线、攻击参数和阻挡接口。 |
| `EnemyUnit._process` | `(delta: float) -> void` | 在移动与停止攻击之间切换。 |
| `EnemyUnit._find_first_path_blocker` | `() -> Node` | 从下一路径格向终点返回第一个有效屏障。 |
| `EnemyUnit.is_attacking` | `() -> bool` | 当前目标有效且在射程内时返回 true。 |
| `EnemyUnit._move_along_path` | `(remaining_distance: float) -> void` | 按距离预算推进并支持跨段。 |
| `EnemyUnit._reach_base` | `() -> void` | 单次广播据点伤害并释放单位。 |

## 约定事实源

- PathDefinition 的格顺序是敌人“前方/后方”的唯一事实源。
- BuildingManager 是路径格屏障存活状态事实源；EnemyUnit 只保存注入的 Callable，不持有 BuildingManager 类型字段。
- `attack_range` 是进入攻击状态的边界；所有敌人在攻击状态都不移动。

## 已知限制 / 初版不做的部分

- 不做行为树、动态寻路、绕障、仇恨、围攻位置分配、攻击路外塔或特殊技能。
- 多个敌人可重叠站在同一攻击位置；单位碰撞/排队留到后续群体移动优化。
