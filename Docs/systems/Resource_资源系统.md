# 资源系统 · Resource

## 职责
管理单一主资源的产出与消耗，建筑与镜子共用该资源并各设数量上限。

## 分类 / 做法
- **单一主资源**：全局唯一经济货币。
- **共用与上限**：建筑与镜子共用主资源；各自有**数量上限** `building_cap` / `mirror_cap`（上限为"可建数量"，非资源存量）。
- **产出来源（全部实现，每种带独立开关）**：
  1. 击杀掉落（Unit.reward）
  2. 占领地块被动产出
  3. 生产建筑（专职产资源的建筑）
  4. 时间自然增长
  5. 破坏地块（破坏障碍/地块获得）
- 每种产出通过开关启用/禁用，并可调速率，方便关卡差异化调参。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| main_resource | 200 | 主资源初始存量 |
| building_cap | 20 | 建筑数量上限 |
| mirror_cap | 6 | 镜子数量上限 |
| kill_drop_enabled | true | 击杀掉落开关 |
| tile_income_enabled / rate | true / 1.0 | 占领地块被动产出开关与速率(每秒) |
| producer_enabled / rate | true / 2.0 | 生产建筑产出开关与速率 |
| time_growth_enabled / rate | true / 0.5 | 时间自然增长开关与速率(每秒) |
| destroy_tile_enabled / amount | true / 20 | 破坏地块产出开关与数量 |

## 关键架构
```
ResourceManager (Node)
 ├─ main_resource: int
 ├─ can_afford(cost) / spend(cost) / gain(amount)
 ├─ building_count / mirror_count 与 cap 校验
 └─ income_sources: [IncomeSource{enabled, rate, tick()}]
IncomeSource: kill_drop / tile_income / producer / time_growth / destroy_tile
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 仅单一主资源，不做多货币/科技点。
- 上限为固定值（可 @export 调），初版不做上限动态扩容建筑。
- 无资源上限溢出返还/利息机制。
