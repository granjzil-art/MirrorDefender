# 单位系统 · Unit

## 职责
定义敌方进攻单位的属性与行为，沿指定路径移动并攻击我方据点。

## 分类 / 做法
- **初版约束**：单位**不可被镜像**；**无中立单位**。
- **兵种分类（数值区分，无独立机制）**：近战 / 远程 / 快速 / 重甲 等，通过参数差异化。
- **移动**：沿关卡**手动指定的路径**移动（见 Path 系统），匀速。
- **到达据点**：触碰我方据点则**消失**，并对据点造成伤害。
- 击杀掉落资源（数值见 reward，接入 Resource 系统）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| max_hp | 100 | 最大生命值 |
| move_speed | 2.0 | 移动速度（格/秒） |
| armor | 0 | 护甲（初版为固定减伤，无克制类型） |
| damage | 10 | 到达据点时对据点造成的伤害 |
| reward | 5 | 被击杀时掉落的主资源数量 |

## 关键架构
```
Unit (Node)
 ├─ stats: max_hp / move_speed / armor / damage / reward
 ├─ path_ref: path_id（由 Wave 指定）
 ├─ on_tick() → move_along_path()
 ├─ on_reach_base() → deal_damage(base); despawn()
 └─ on_death() → drop_reward()
UnitFactory: 按 enemy_type 生成对应数值的单位
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 单位不可被镜像；不做中立/友方单位。
- 无飞行/地面分层机制（can_target_air 由 Combat 预留）。
- 无自动寻路、无绕障、无群体阵型；严格沿手动路径。
- 兵种仅数值区分，不做特殊技能。
