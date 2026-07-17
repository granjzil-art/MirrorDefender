# 敌方AI系统 · AI

## 职责
敌方完全由脚本波次驱动，敌人生成后按行为模式沿指定路径行走，无复杂决策。

## 分类 / 做法
- **波次驱动**：敌人由 Wave 系统在出生点生成，不做全局决策 AI。
- **行为模式**：敌人生成后按自身 `behavior_mode` 沿 `path_id` 指定路径行走。
- **到达据点**：碰到我方据点则**消失**并对据点造成 `damage_to_base` 伤害。
- 行为模式为简单枚举（如 straight 直行），预留扩展位。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| behavior_mode | straight | 行为模式（沿路径直行，预留扩展） |
| path_id | - | 所走路径（引用 Path 系统） |
| damage_to_base | 10 | 到达据点时对据点造成的伤害 |

## 关键架构
```
EnemyBehavior (组件)
 ├─ behavior_mode: enum(straight, ...)
 ├─ path_id → PathManager.get_path()
 └─ tick() → 沿路径推进; on_reach_base() → despawn + base.take_damage(damage_to_base)
（无 BehaviorTree / 无状态机决策，初版仅路径推进）
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 无复杂决策 AI、无目标选择、无仇恨、无绕障。
- behavior_mode 初版仅"沿路径直行"，其余为预留枚举。
- 不与镜子/建筑交互（单位不可被镜像，仅受伤害）。
