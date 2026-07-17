# 地块系统 · Tile

## 职责
定义地图基本单元的类型、高度与建造状态，并提供拖拽式地块编辑器用于关卡搭建。

## 分类 / 做法
- **地块类型（3 种）**：
  1. **可建造**：可直接放置建筑。
  2. **可破坏后建造**：初始为占位障碍物（石头等），破坏后转为"可建造"。
  3. **不可破坏不可建造**：如路面，仅供单位通行。
- **高度**：离散档位，档数可配置（默认 3 档），用于地形遮挡（如激光被隆起地形阻挡）。
- **拖拽式地块编辑器**：类似插槽/调色板，可将预制地块**直接拖拽填充**到网格插槽，支持对**单个地块的参数修改**（类型、高度、初始障碍等）。
- **镜子无关**：镜子挂在地块的"边"上，不受地块类型限制（详见 Mirror / Grid）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| tile_type | buildable | 地块类型：buildable / destructible_then_buildable / blocked |
| height_level | 0 | 离散高度档（0 ~ height_max-1），默认 3 档 |
| buildable | true | 当前是否可建造（破坏障碍后可变 true） |
| destructible | false | 是否可破坏（type 2 为 true） |
| occupant | null | 当前占用物引用（建筑 / 障碍物 / 空） |

## 关键架构
```
Tile (Resource / Node)
 ├─ tile_type, height_level, buildable, destructible, occupant
 ├─ on_destroy_obstacle() → buildable = true
 └─ can_place() / place(occupant) / clear()
TileEditor (编辑器工具)
 ├─ palette: 预制地块列表
 ├─ drag_drop(tile_prefab, slot) → 填充网格插槽
 └─ edit_single(tile) → 修改单格参数
TileManager: 按 cell 索引所有 Tile，供建造/破坏/路径查询
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 初版仅 3 种类型；不做连续高度、斜坡、地形形变。
- 编辑器仅支持拖拽填充与单格改参，不做刷子/批量填充/撤销栈。
- 障碍物种类初版仅"石头"一类占位。
