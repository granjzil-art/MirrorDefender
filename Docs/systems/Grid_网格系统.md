# 网格系统 · Grid

## 职责
定义六边形/正方形网格的坐标、邻接、距离与边(Edge)，为地块、路径、镜子挂载提供统一几何基础。

## 分类 / 做法
- 初版**同时支持两种网格**，各做一个示意关卡：
  - **六边形(flat-top)**：使用**立方体坐标(cube coord)** `(q, r, s)`，`q + r + s = 0`。
  - **正方形**：使用**行列坐标** `(row, col)`。
- 网格几何数学抽象为 `IGridShape`，六边形/正方形各为一个实现。当前形状枚举、LevelResource 和编辑器仍显式支持两种形状；新增第三种形状还需同步这些选择/序列化边界，不能只增加一个 Shape 脚本。
- **边(Edge)** 是一等公民：六边形每格 6 条边，正方形每格 4 条边。每条边以 `(cell, edge_index)` 标识，可被镜子挂载（不受地块类型限制）。
- **边共享与唯一键（已确认）**：相邻两格共享同一条物理边。系统需提供**规范化边键** `canonical_edge_id`（两格视角映射到同一 id），供镜子做"**一条边至多一面镜**"的占用校验。
- **拾取与高亮**：Main 以只读 Callable 注入 Tile 世界高度；`pick_cell` / `pick_edge` 与全部地块顶面求交并选择射线最近命中，斜视角下不会穿过高地误选 `Y=0` 的后方格。
- 提供统一 API：`get_neighbors`、`distance`、`cell_to_world`、`world_to_cell`、`get_edges`、`canonical_edge_id`。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| cell_size | 1.0 | 单格尺寸（世界单位），影响格心间距 |
| orientation | flat-top | 六边形朝向；正方形忽略 |
| grid_shape | hex | 网格形状：hex / square（接口切换，预留 triangle） |
| grid_size | (10, 10) | 网格范围（半径或行列数，随 shape 解释） |

## 关键架构

### 文件构成（`scripts/grid/`）
| 文件 | class_name | 基类 | 角色 |
|---|---|---|---|
| `IGridShape.gd` | `IGridShape` | `RefCounted` | 网格形状**接口**（抽象基类，含边/键的通用实现） |
| `HexGridShape.gd` | `HexGridShape` | `IGridShape` | 六边形 flat-top，立方体坐标 |
| `SquareGridShape.gd` | `SquareGridShape` | `IGridShape` | 正方形，行列坐标 |
| `GridManager.gd` | `GridManager` | `Node3D` | **唯一对外入口**：持形状 + 转发 API + 拾取 |
| `GridRenderer.gd` | `GridRenderer` | `Node3D` | 纯表现层：线框 + 格/边高亮（只读 GridManager） |

### 几何标签集成文件

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 以 `grid_shape` 为唯一事实源，派生关卡标签及两类建筑方向数。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | 无 / `Control` | 在关卡编辑器显示只读派生标签，形状切换后同步刷新。 |
| `scripts/Main.gd` | 无 / `Node3D` | 在运行时 HUD 显示当前 GridManager 派生标签。 |

### 依赖与数据流
```
Main（场景装配）
 ├─ GridManager  ──(signal grid_changed)──▶ GridRenderer._rebuild_grid_lines()
│     └─ shape: IGridShape  (HEX / SQUARE，运行时可换)
 ├─ TileManager.get_world_height ──(只读 Callable)──▶ GridManager 顶面拾取
 └─ 每帧: grid.pick_edge/pick_cell(camera, mouse)
          └─▶ renderer.highlight_edge / highlight_cell
其它模块(Tile/Mirror/Path/UI) 一律只依赖 GridManager，不直接 new 具体 shape。
```

### 坐标与边约定（实现事实源，跨模块必读）
- **格坐标 cell**：统一 `Vector3i`。
  - HEX：`(q, r, s)`，约束 `q + r + s = 0`（立方体坐标）；`s` 存于 `.z`。
  - SQUARE：`(col, row, 0)`，`.z` 恒 0。
- **世界坐标**：`Vector3`，XZ 为地平面。Grid 几何本身位于 `Y=0`；M2 的 Tile 以 `height_level * height_step` 生成顶面和崖壁。
- **边(Edge)**：`(cell, edge_index)`。HEX `edge_index ∈ [0,6)`，SQUARE `∈ [0,4)`。
  - 边 i 连接 `corner[i] → corner[(i+1)%n]`（角点序见各 shape 文件头注释）。
  - HEX flat-top 角点角度 `300/0/60/120/180/240°`；每条边外法线与 `_DIRS[edge_index]` 对应。
  - SQUARE 角点顺序 `右下→右上→左上→左下`，边序为右/上/左/下，`_DIRS[edge_index]` 即跨该边的邻格方向。
- **canonical_edge_id**（物理边唯一占位）：取该边两端点世界坐标 → 各自量化到 `1e-3`（`roundi(v*1000)`）→ 字典序排序两端点键 → 拼成 `"x,z|x,z"`。**与从哪一侧格看无关**，故相邻两格的共享边得到同一 id。
- **directed_edge_id**（可选单向玩法段）：以 `from_cell>to_cell` 生成；仅接受相邻格，反向会得到另一键。默认双向边屏障使用 `canonical_edge_id`，仅关闭 `blocks_both_directions` 的变种使用有向匹配。
- **关卡几何标签**：LevelResource 的 `hex/square` 标签由 `grid_shape` 自动派生，不另存第二份可编辑字段。HEX 普通建筑/边建筑方向数为 `6/6`，SQUARE 为 `8/4`。

## 函数索引
> M1 已实现。签名为准，改代码即改此表。

### IGridShape.gd（接口 + 通用实现）
| 函数 | 签名 | 职责 |
|---|---|---|
| `setup` | `(p_cell_size: float) -> void` | 注入格距 |
| `edge_count`✱ | `() -> int` | 每格边数（子类返回 6/4） |
| `cell_to_world`✱ | `(cell: Vector3i) -> Vector3` | 格→世界（格心） |
| `world_to_cell`✱ | `(world: Vector3) -> Vector3i` | 世界→最近格 |
| `get_neighbors`✱ | `(cell) -> Array[Vector3i]` | 邻格列表 |
| `distance`✱ | `(a, b: Vector3i) -> int` | 格距 |
| `get_corners`✱ | `(cell) -> PackedVector3Array` | 角点（世界，序对应边） |
| `get_edge_endpoints` | `(cell, edge_index) -> Array[Vector3]` | 第 i 边两端点（基类通用） |
| `get_edge_midpoint` | `(cell, edge_index) -> Vector3` | 边中点（拾取用，基类通用） |
| `neighbor_across_edge`✱ | `(cell, edge_index) -> Vector3i` | 跨第 i 边的邻格（可能越界） |
| `canonical_edge_id` | `(cell, edge_index) -> String` | 规范化边键（基类通用，见上算法） |
| `enumerate_cells`✱ | `(grid_size: Vector2i) -> Array[Vector3i]` | 枚举范围内所有格 |
| `is_in_bounds`✱ | `(cell, grid_size) -> bool` | 范围判断 |

✱ = 子类必须重写的虚方法；未标者由基类提供通用实现（子类无需重写）。
私有：`_quantize_key(p: Vector3) -> String`（端点量化）。

### HexGridShape.gd（flat-top 立方体坐标）
- 重写全部虚方法；常量 `SQRT3`、`_DIRS`(6 方向，序与边外法线对应)。
- 私有 `_cube_round(qf, rf, sf: float) -> Vector3i`：立方体坐标取整（保持 q+r+s=0）。
- 几何：格心间距水平 `1.5*size`、垂直 `√3*size`（size=cell_size）。

### SquareGridShape.gd（行列坐标）
- 重写全部虚方法；角点起点为右下，以保证 `_DIRS`(右/上/左/下) 与边序一致；曼哈顿距离，无对角。

### GridManager.gd（Node3D · 唯一对外入口）
- **信号**：`grid_changed`（形状/尺寸/格距变化时发，供渲染层重建）。
- **枚举**：`Shape { HEX, SQUARE }`。**成员**：`shape: IGridShape`。
- **@export setter**：`grid_shape` / `cell_size`(下限 0.01) / `grid_size` → 改参即 `_rebuild_shape()` + 发信号。
- **私有**：`_rebuild_shape()`（按 grid_shape new 出 shape 并 setup）。
- **转发 API**（透传当前 shape，参数同接口）：`cell_to_world` / `world_to_cell` / `get_neighbors` / `distance` / `get_corners` / `get_edge_endpoints` / `neighbor_across_edge` / `canonical_edge_id` / `edge_count` / `enumerate_cells()`（用自身 grid_size）/ `is_in_bounds(cell)`（用自身 grid_size）。
- **有向边与方向 API**：`directed_edge_id(from_cell: Vector3i, to_cell: Vector3i) -> String`；`find_edge_index(from_cell: Vector3i, to_cell: Vector3i) -> int`；`get_geometry_tag() -> StringName`；`get_tile_building_facing_count() -> int`；`get_edge_building_facing_count() -> int`。
- **镜像离散几何 API**：`get_mirror_cell_pair(from_cell, edge_index, active_from_side, distance_from_edge) -> Dictionary` 返回 `{valid, source_cell, target_cell}`；方形/六边形坐标步进只存在于 GridManager，Mirror 不读取具体坐标布局。
- **关卡装配 API**：`apply_configuration(p_shape: int, p_cell_size: float, p_grid_size: Vector2i) -> void`。LevelResource 只传数据，仍由 GridManager 自己触发 shape 重建和 `grid_changed`；Tile 模块不直接 new 具体 shape。
- **高度查询注入**：`set_cell_height_resolver(resolver: Callable) -> void`，契约为 `(cell: Vector3i) -> float`；无效返回值安全回退为 0，GridManager 不持有 TileManager。
- **拾取**（供放置/UI）：
  | 函数 | 签名 | 返回 Dictionary 结构 |
  |---|---|---|
  | `raycast_ground` | `(camera: Camera3D, screen_pos: Vector2) -> Dictionary` | `{hit: bool, pos: Vector3}` |
  | `raycast_ground_from_ray` | `(origin: Vector3, direction: Vector3) -> Dictionary` | 兼容/测试用 `Y=0` 平面交点。 |
  | `raycast_grid_surface` | `(origin: Vector3, direction: Vector3) -> Dictionary` | `{hit, cell, pos}`；返回最近地块顶面交点。 |
  | `pick_cell` | `(camera, screen_pos) -> Dictionary` | `{hit, cell: Vector3i, pos: Vector3}`（未命中 hit=false） |
  | `pick_cell_from_ray` | `(origin: Vector3, direction: Vector3) -> Dictionary` | 不依赖 Camera 的同一顶面拾取契约，供测试/工具复用。 |
  | `pick_edge` | `(camera, screen_pos) -> Dictionary` | `{hit, cell, edge_index: int, id: String}`（最近边中点距离 < `edge_pick_threshold` 才 hit） |
  | `pick_edge_from_ray` | `(origin: Vector3, direction: Vector3) -> Dictionary` | 使用命中格真实顶面高度的边拾取。 |

### LevelResource.gd（几何标签 API）

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_geometry_tag` | `() -> StringName` | 从 `grid_shape` 派生 `hex` 或 `square`。 |
| `get_tile_building_facing_count` | `() -> int` | 返回普通地块建筑方向数（HEX=6，SQUARE=8）。 |
| `get_edge_building_facing_count` | `() -> int` | 返回边建筑方向数（HEX=6，SQUARE=4）。 |

### GridRenderer.gd（Node3D · 纯表现层）
- **@export**：`grid: GridManager`（引用）、颜色(line/cell_highlight/edge_highlight)、抬升(line_lift/edge_highlight_lift 防 z-fighting)。
- `set_grid(value: GridManager) -> void`：由 Main 在子节点就绪后注入网格，解除旧订阅、建立新订阅并首次绘制。
- `_ready()` → 建材质/实例；若编辑器已提供 `grid`，调用私有 `_connect_grid()` 完成订阅与首次重建。
- `_rebuild_grid_lines() -> void`：遍历 `enumerate_cells` 用 `ImmediateMesh`(PRIMITIVE_LINES) 画所有格边线；空网格直接令 mesh 为 null，不调用零顶点 `surface_end()`。
- `highlight_cell(cell: Vector3i, has: bool) -> void`：填充多边形高亮格（has=false 隐藏）。
- `highlight_edge(cell: Vector3i, edge_index: int, has: bool) -> void`：画抬高线段高亮边。
- 私有：`_setup_materials` / `_make_unshaded(c) -> StandardMaterial3D` / `_setup_instances` / `_connect_grid() -> void`。

### Main.gd（M2 验收入口，`scripts/Main.gd`，挂 `scenes/Main.tscn` 根）
- `@onready`：`grid` / `renderer` / `tile_manager` / `tile_renderer` / `level_loader` / `level_debug_panel` / `cam_rig` / HUD。
- `_ready()`：先注入 Grid 到各表现/数据模块，再配置 LevelLoader 并通过 `load_initial_level()` 统一装配初始关卡；运行时切关同样由 LevelLoader 调用 `GridManager.apply_configuration()`。
- `_process()` → `_update_pick()`：每帧拾取，**边优先**高亮，否则高亮格；调 `_update_hud`。
- `_update_hud(cell, edge: Dictionary)`：HUD 显示网格类型/格距/悬停与已锁定的格边信息；命中格额外显示 Tile 类型/高度与清障提示。
- `_unhandled_input()`：`toggle_grid_shape`(T) 切 HEX↔SQUARE（通过 `grid_changed` 重建）；`place_select`(左键)锁定当前格/边；`KEY_F` 调用 TileManager 清除锁定格的障碍。
- `_lock_current_pick() -> void`：读取当前鼠标位置并保存格/边拾取结果，供 HUD 验收显示。
- `_on_level_loaded(level_resource: LevelResource, source_path: String) -> void`：切关后清空旧关卡的锁定格/边和高亮。

## 已知限制 / 初版不做的部分
- 初版仅实现 hex(flat-top) 与 square；三角形仅预留接口，不实现。
- 不做无限滚动网格 / 运行时动态改变网格拓扑；M1 已支持以 T 切换 HEX/SQUARE 作验收观察。
- 拾取以地块水平顶面为选择面，不单独选择竖直崖壁；路径与换路由 Path 系统负责。
