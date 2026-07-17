# 敌方AI系统 · AI

> 实现状态：M4 已完成脚本驱动的固定路径移动 AI；不使用行为树、寻路或目标决策。

## 职责

定义敌人的最小行为：由 WaveManager 生成，沿 SpawnGroup 指定路径移动，到终点攻击据点；被建筑击杀时由波次系统处理资源掉落。

## 分类 / 做法

- **直线行为**：EnemyUnit 仅沿 `PackedVector3Array` 路点移动，路点来自 PathManager。
- **无决策**：单位不选择目标、不绕行、不抢占格；建筑通过 CombatManager 进行索敌。
- **到达行为**：移动到最后一点后广播 `reached_base`，自身释放；WaveManager 再调用 BaseCore。
- **战斗协作**：EnemyUnit 是 CombatTarget，支持索敌优先级、投射物和激光，不向战斗系统反向传递波次规则。

## 关键架构

```text
WaveManager -> EnemyUnit.configure_unit(enemy, path_points)
EnemyUnit._process -> move segment by segment
  -> final point -> reached_base -> WaveManager -> BaseCore.take_damage

CombatManager -> EnemyUnit.take_damage
  -> CombatTarget.died -> WaveManager reward handling
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit._process` | `(delta: float) -> void` | 推进固定路径，并支持一帧跨多个路段。 |
| `EnemyUnit.configure_unit` | `(enemy_definition: EnemyDefinition, path_points: PackedVector3Array) -> void` | 装配 AI 的数值和路线。 |
| `EnemyUnit._reach_base` | `() -> void` | 单次广播到达伤害并释放单位。 |

## 已知限制 / 初版不做的部分

- 不做行为树、状态机、自动寻路、仇恨、闪避、攻击建筑或特殊技能。
- 后续仅在行为模式真实分化后再抽出策略接口，M4 不为单一移动行为过度抽象。
