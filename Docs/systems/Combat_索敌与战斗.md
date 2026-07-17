# 索敌与战斗 · Combat

## 职责
定义塔如何选择目标及如何计算伤害，无伤害类型克制。

## 分类 / 做法
- **无克制**：不做伤害类型/属性克制。
- **伤害公式**：
  ```
  伤害 = base_damage(塔种决定) × level_factor(等级增伤) × extra_factor(额外增伤, 某些建筑提供, 后续用)
  ```
  初版 `extra_factor` 默认 1.0（预留给增益类建筑）。
- **索敌策略（可切换）**：最近 / 最远 / 最高血 / 最低血 / 最快 / 首个进入 / 锁定。
  - 策略以接口 `ITargeting` 实现，建筑通过组合选择（见 Building）。
- **伤害结算方式（两类）**：
  - **瞬时伤害**（箭塔）：命中目标一次性结算 `base_damage × level_factor × extra_factor`。
  - **持续伤害**（激光塔，已确认）：只要敌人处于激光路径上，**每 tick** 结算 `laser_dps × level_factor × extra_factor`。敌人离开光路即停止。激光同时对光路上**所有**敌人生效（穿透）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| target_priority | nearest | 索敌策略：nearest/farthest/highest_hp/lowest_hp/fastest/first_in/locked |
| base_damage | 10 | 固定伤害值（由塔种决定） |
| level_factor | 1.0 | 等级增伤因子（随 level 提升） |
| extra_factor | 1.0 | 额外增伤因子（某些建筑提供，后续用） |
| laser_dps | 由塔种定 | 激光塔每 tick 持续伤害（走同一公式，替代 base_damage 项） |
| can_target_air | false | 是否可攻击空中单位（预留，初版无空中单位） |

## 关键架构
```
ITargeting.select(candidates, ctx) -> target
 ├─ Nearest / Farthest / HighestHP / LowestHP / Fastest / FirstIn / Locked
DamageCalc.compute(base, level_factor, extra_factor) -> final_damage
CombatContext: 提供范围内候选单位列表、据点距离等
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 无伤害类型/护甲类型克制（armor 为线性减伤，见 Unit）。
- extra_factor、can_target_air 仅预留，初版不接入实际来源。
- 激光的持续伤害是"在光路上即持续掉血"的简化 DOT，不做叠层/衰减/独立 buff 计时器。
- 不做暴击、闪避等其它衍生战斗机制。
