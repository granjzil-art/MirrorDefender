# 波次系统 · Wave

## 职责
驱动经典塔防波次进攻，定义每波敌人构成、出怪节奏、出生点与路径，固定波数即胜。

## 分类 / 做法
- **经典波次**：一局由若干波组成，波间有准备期，打完 `total_waves` 即胜利。
- **每波构成（详细参数化）**：每波是一个 **SpawnGroup 列表**，每个 SpawnGroup 描述：
  - 怪物种类 `enemy_type`
  - 数量 `count`
  - 出怪间隔 `interval`
  - 出生点 `spawn_point`
  - 走哪条路径 `path_id`
- 一波内可含多个 SpawnGroup（不同兵种/不同出生点/不同路径并发或串行）。
- **固定波数即胜**：坚持固定波数胜利，不做无限模式。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| wave_list | [] | 波次列表，每波是一组 SpawnGroup |
| SpawnGroup.enemy_type | - | 怪物种类 |
| SpawnGroup.count | 10 | 该组数量 |
| SpawnGroup.interval | 0.8 | 出怪间隔(秒) |
| SpawnGroup.spawn_point | - | 出生点标识 |
| SpawnGroup.path_id | - | 该组所走路径(见 Path) |
| prep_time | 15 | 波间准备期(秒) |
| total_waves | 10 | 胜利所需波数 |

## 关键架构
```
Wave (Resource)
 └─ spawn_groups: [SpawnGroup]
SpawnGroup: { enemy_type, count, interval, spawn_point, path_id }
WaveManager (Node)
 ├─ wave_list, current_wave, prep_timer
 ├─ start_wave() → 遍历 spawn_groups 定时 spawn
 ├─ on_wave_clear() → prep_time 后进入下一波
 └─ on_all_waves_clear() → victory
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 固定波数，不做无限波/动态难度。
- 不做波次内条件触发（如"击杀 X 提前出下一波"）。
- SpawnGroup 初版为串行/并发定时，不做复杂编排 DSL。
