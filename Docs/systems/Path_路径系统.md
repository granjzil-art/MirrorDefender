# 路径系统 · Path

> 实现状态：M4 已完成线性格子路径、出生点、运行时世界点解析、可视调试线和关卡编辑器路径页。

## 职责

保存设计者手工给出的有序格子序列，并将其转换为带地形高度的世界点供 EnemyUnit 移动。路径不做寻路、避障或运行时修改。

## 分类 / 做法

- **线性路线**：每个 PathDefinition 是从出生点到据点的一串连续格子，至少两个格。
- **双网格**：连续性由当前 GridManager 的 `get_neighbors()` 判断，支持 HEX 与 SQUARE。
- **出生点**：SpawnPointDefinition 保存可复用入口格；SpawnGroup 直接引用出生点和路径资源，而非手填字符串。
- **世界点**：PathManager 读取每格 Tile 高度，生成格心加抬升量的 `PackedVector3Array`，敌人贴合台阶路线移动。
- **表现**：PathManager 绘制黄色线路与绿色出生点标记；BaseCore 绘制据点标记。可通过 `show_paths` 关闭。
- **编辑**：关卡编辑器“路径”页点击画布连续记录格，可删除尾格、清空、设据点、从路径起点添加入口并做校验。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| PathDefinition | `path_id` / `display_name` | 稳定标识与编辑器显示名。 |
| PathDefinition | `cells` | 起点到据点的有序 `Array[Vector3i]`。 |
| SpawnPointDefinition | `spawn_id` / `display_name` | 出生点标识与显示名。 |
| SpawnPointDefinition | `cell` | 入口所在格，校验时必须在地图内。 |
| PathManager | `show_paths` | 路线和出生点调试表现开关。 |
| PathManager | `path_color` / `spawn_color` / `line_lift` | 运行时灰盒颜色和抬升高度。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/path/PathDefinition.gd` | `PathDefinition` / `Resource` | 路径 ID、名称和有序格子。 |
| `scripts/path/SpawnPointDefinition.gd` | `SpawnPointDefinition` / `Resource` | 出生点 ID、名称和格坐标。 |
| `scripts/path/PathManager.gd` | `PathManager` / `Node3D` | **路径唯一运行时入口**；索引、世界点解析、校验和调试绘制。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control` | 复用地形斜俯视投影绘制 M4 路线/入口/据点。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 路径编辑页和统一关卡保存。 |

### 数据流

```text
LevelResource.paths / spawn_points
  -> PathManager.load_level -> path_id index + runtime line markers
  -> WaveManager SpawnGroupDefinition.path
  -> PathManager.get_world_points -> EnemyUnit

Level Editor path page
  -> click cells -> PathDefinition.cells
  -> add spawn / set base -> LevelResource
  -> validate_m4 -> bounds + neighbor continuity + references
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `PathDefinition.has_minimum_cells` | `() -> bool` | 至少有两个格时返回 true。 |
| `PathDefinition.get_start_cell` / `get_end_cell` | `() -> Vector3i` | 返回首/末格；空路径返回 ZERO。 |
| `PathManager.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入网格和地形高度接口。 |
| `PathManager.load_level` | `(level_resource: LevelResource) -> void` | 重建 ID 索引和路径表现。 |
| `PathManager.get_path_definition` | `(path_id: StringName) -> PathDefinition` | 通过稳定 ID 返回路径定义。 |
| `PathManager.get_world_points` | `(path: PathDefinition) -> PackedVector3Array` | 把路径格转为带高度世界点。 |
| `PathManager.is_path_valid` | `(path: PathDefinition) -> bool` | 校验边界、长度和相邻连续性。 |

## 约定事实源

- 路径顺序是出生点到据点，敌人不可反向解释。
- PathDefinition / SpawnPointDefinition 必须由 LevelResource 持有；SpawnGroup 只能引用本关对象。
- 运行时名称不能使用 `get_path()`，该名称被 Godot Node 保留；统一使用 `get_path_definition()`。

## 已知限制 / 初版不做的部分

- 不做分叉、合流、图寻路、动态路径重算或路径共享导航网格。
- 出生点工具当前按路径起点创建；单独移动入口格可后续扩展。
