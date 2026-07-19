# 单位系统 · Unit

> 实现状态：M4 已完成数值定义、沿手动路径移动、护甲减伤、到达据点伤害、死亡资源掉落和 CombatTarget 接入。

## 职责

定义敌方进攻单位的可编辑数值和运行时行为。单位继承 `CombatTarget`，所以建筑无需了解敌人类型；WaveManager 负责生成，EnemyUnit 只负责沿已解析路径移动并在终点攻击据点。

## 分类 / 做法

- **敌人定义**：`EnemyDefinition` 是资源，可直接在 Inspector 配置生命、移速、护甲、据点伤害、死亡奖励与灰盒颜色。
- **移动**：EnemyUnit 接收 PathManager 转换后的世界点序列，以定义的格/秒速度逐段行走；一帧可跨越多个短段，避免低帧率停顿。
- **受击**：覆盖 `take_damage()`，先以 `max(0, incoming - armor)` 固定减伤，再交给 CombatTarget 扣血。
- **死亡掉落**：WaveManager 只订阅 EnemyUnit 的 `died`，调用 `ResourceManager.grant_enemy_drop(reward)`；M3 调试靶标死亡不会获得资源。
- **据点到达**：路径最后一点触发 `reached_base(unit, damage)`，WaveManager 调 BaseCore 扣血，单位不触发死亡奖励。
- **边界**：单位不可被镜像，无中立/友方、飞行、自动寻路或技能。

## 参数编辑入口

在 `resources/enemies/*.tres` 编辑敌人。例如 M4 示例提供 `Grunt.tres` 与 `Runner.tres`。

| 分组 | 参数 | 说明 |
|---|---|---|
| Identity | `enemy_id` / `display_name` | 稳定标识与编辑器显示名。 |
| Stats | `max_hp` | 最大生命。 |
| Stats | `move_speed` | 沿路径的世界格/秒。 |
| Stats | `armor` | 每次命中的固定减伤。 |
| Stats | `base_damage` | 到达据点时造成的伤害。 |
| Stats | `reward` | 被击杀时获得的主资源。 |
| Stats | `hit_radius` | 激光线段和投射物命中半径。 |
| Presentation | `visual_scene` / `body_color` / `body_height` | 美术替换接口与灰盒表现。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/unit/EnemyDefinition.gd` | `EnemyDefinition` / `Resource` | 每种敌人的完整可编辑数据。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | 移动、护甲、据点到达和正式可受击目标。 |
| `scripts/unit/BaseCore.gd` | `BaseCore` / `Node3D` | 据点生命、地块占用、灰盒和失败信号。 |
| `resources/enemies/Grunt.tres` | `EnemyDefinition` | 步兵示例。 |
| `resources/enemies/Runner.tres` | `EnemyDefinition` | 疾行者示例。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | 生成单位、处理死亡奖励和据点到达。 |

### 数据流

```text
SpawnGroupDefinition.enemy + PathManager world points
  -> WaveManager._spawn_group_unit
  -> EnemyUnit.configure_unit -> CombatManager.register_target

Building / Projectile / Laser -> EnemyUnit.take_damage
  -> armor reduction -> CombatTarget.died
  -> WaveManager -> ResourceManager.grant_enemy_drop

EnemyUnit reaches final path point
  -> reached_base(damage) -> WaveManager -> BaseCore.take_damage
  -> BaseCore.defeated -> WaveManager.DEFEAT
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit.configure_unit` | `(enemy_definition: EnemyDefinition, path_points: PackedVector3Array) -> void` | 在加入场景树前写入数值、表现参数和 Main 局部空间路径起点，供 `_ready()` 构建正确灰盒外观。 |
| `EnemyUnit.take_damage` | `(amount: float) -> float` | 应用固定护甲并返回实际伤害。 |
| `EnemyUnit._process` | `(delta: float) -> void` | 沿世界路径逐段移动。 |
| `BaseCore.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入位置和占用接口。 |
| `BaseCore.load_level` | `(level_resource: LevelResource) -> void` | 放置据点、占用据点格并重置生命。 |
| `BaseCore.take_damage` | `(amount: float) -> float` | 扣据点生命，归零时广播 `defeated`。 |

**信号**：EnemyUnit.`reached_base`；BaseCore.`health_changed` / `defeated`；继承 CombatTarget.`health_changed` / `died`。

## 约定事实源

- EnemyDefinition 是敌人数值事实源；EnemyUnit 是运行时生命、位置和路径进度事实源。
- PathManager 生成的路径点与动态 EnemyUnit 共用 Main 局部坐标空间；生成前设置 `position`，不得在节点尚未入树时访问 `global_position`。
- `reward` 只在敌人被击杀时入账；到达据点消失不掉资源。
- 据点格通过 TileManager 占用，建筑不能建在该格。

## 已知限制 / 初版不做的部分

- 不做自动寻路、绕障、飞行层、技能、群体队形或对象池。
- 护甲为单次固定减伤，不做百分比、穿甲或抗性类型。
