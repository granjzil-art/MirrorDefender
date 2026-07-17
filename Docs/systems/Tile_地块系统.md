# 地块系统 · Tile

> 实现状态：M2 已完成。运行时地块逻辑位于 `scripts/tile/`；Godot 主屏地块编辑器位于 `addons/mirror_tile_editor/`。

## 职责
定义每个网格格子的类型、高度、障碍和运行时占用；提供查询、清障、灰盒地形渲染，以及可保存 `.tres` 关卡布局的拖拽式编辑器。

## 分类 / 做法
- **可建造**：`tile_type = 0`，可放建筑，前提是 `occupant == null`。
- **可破坏障碍**：`tile_type = 1`。障碍未清除时不可放置；清除后仍保留类型与高度，但 `obstacle_destroyed = true`，因此转为可建造。
- **不可建造路面**：`tile_type = 2`，不可破坏、不可建造；M4 可作为手动路径的基础数据。
- **离散高度**：`height_level` 必须在 `[0, LevelResource.height_levels - 1]`；世界高度为 `height_level * LevelResource.height_step`。
- **运行时表现**：TileRenderer 以一个带顶点色的 `ImmediateMesh` 批量构建地形；颜色由 LevelResource 的低绿/中黄/高红高度色插值得到，只在高于相邻格的边生成崖壁；未清除障碍仍显示灰色岩石占位。
- **编辑器工作流**：启用的 `Mirror Tile Editor` 主屏插件读取三份 TilePreset `.tres`；点击调色板选择画笔后，可在画布上左键拖动连续覆盖格子，也保留单格拖放；右侧单格面板可改类型/高度或清障；保存产生 `LevelResource` `.tres`。
- **高度配色与观察**：画布以 LevelResource 持久化的下/中/上三色为高度渐变，使用斜俯视投影和台阶崖壁凸显高差；选中画布后用 WASD 平移、QE 旋转、XC 或滚轮缩放观察。
- **编辑器资源执行**：TileCellData、TilePreset 与 LevelResource 都标注 `@tool`；编辑器加载 `.tres` 后可执行地块查询、状态判断与画笔构建，不能退化为 placeholder 实例。

## 关键参数

| 归属 | 参数 | 默认 | 说明 |
|---|---|---:|---|
| TileCellData | `tile_type` | 0 | 0=可建造，1=可破坏障碍，2=路面。 |
| TileCellData | `height_level` | 0 | 离散高度档；资源本身允许 0~15，加载时由 LevelResource 收紧。 |
| TileCellData | `obstacle_destroyed` | false | 仅对类型 1 有效；true 时该格可建造。 |
| LevelResource | `height_levels` | 3 | 本关卡可用的高度档数。 |
| LevelResource | `height_step` | 0.45 | 每档对应的世界 Y 高度。 |
| LevelResource | `height_color_low` / `height_color_middle` / `height_color_high` | 绿 / 黄 / 红 | 编辑器与运行时共用的下/中/上高度色标，保存到关卡 `.tres`。 |
| TileManager | `feature_enabled` | true | 地块模块总开关；关闭时不加载布局。 |
| TileRenderer | `feature_enabled` | true | 地块灰盒表现总开关。 |
| TileRenderer | `obstacle_color` | 灰 | 未清除可破坏障碍的岩石占位色；地块顶面颜色由 LevelResource 高度色决定。 |
| TileRenderer | `obstacle_radius_ratio` / `obstacle_height_ratio` | 0.28 / 0.6 | 岩石占位的相对尺寸。 |

`occupant: Node` 为运行时字段，不序列化；M3 的建筑系统通过 TileManager 调用 `place()` / `clear_occupant()`，不直接保有 TileCellData。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/tile/TileCellData.gd` | `TileCellData` / `Resource` | 单格可序列化状态、占用规则与清障规则。 |
| `scripts/tile/TilePreset.gd` | `TilePreset` / `Resource` | 调色板预制参数，显式预加载 TileCellData 脚本创建地块。 |
| `scripts/tile/TileManager.gd` | `TileManager` / `Node3D` | **运行时唯一 Tile 查询入口**；按 `Vector3i` 索引格子并发信号。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | 只读 TileManager，以高度顶点色生成三维灰盒地形和障碍岩石。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 地块布局的持久化容器；完整说明见 Level 文档。 |
| `resources/tiles/BuildableTile.tres` | `TilePreset` | 可建造调色板预制。 |
| `resources/tiles/DestructibleTile.tres` | `TilePreset` | 可破坏障碍调色板预制。 |
| `resources/tiles/BlockedTile.tres` | `TilePreset` | 不可建造路面调色板预制。 |
| `addons/mirror_tile_editor/tile_editor_plugin.gd` | `EditorPlugin` | 注册 Godot 主屏入口“地块编辑器”。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 工具栏、地图参数、三档高度色、画笔调色板、单格参数与保存/加载工作流。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control` | 可旋转斜俯视地形预览、连续画笔、选格与拖拽落点处理。 |
| `addons/mirror_tile_editor/tile_palette_item.gd` | `Button` | 选择画笔预制并从 TilePreset 路径发起拖拽数据。 |

### 模块调用关系 / 数据流

```text
Main (scene composition)
  ├─ LevelResource -> GridManager.apply_configuration(...)
  ├─ TileManager.set_grid(GridManager) -> load_level(LevelResource)
  │     └─ Dictionary[Vector3i, TileCellData]
  └─ TileRenderer <- level_loaded / tile_changed - TileManager
        └─ height-color ImmediateMesh terrain + obstacle marker

Mirror Tile Editor (Godot editor)
  TilePreset .tres click / drag path -> TileEditorCanvas
  -> left-drag brush or drop -> new TileCellData -> LevelResource.store_tile(cell-keyed)
  -> LevelResource height_color_low / middle / high -> oblique editor projection
  -> ResourceSaver.save(LevelResource, res://.../*.tres)
```

其它玩法模块只能通过 `TileManager` 读取/改变运行时地块。编辑器只编辑 `LevelResource`，不会持有场景中的 TileManager。

### 约定事实源

- `cell` 一律是 Grid 的 `Vector3i`：HEX `(q, r, s)`、且 `q+r+s=0`；SQUARE `(col, row, 0)`。
- 同一个 `cell` 在 `LevelResource.tiles` 中至多一条记录。`store_tile()` 以 cell 覆盖旧资源，编辑器拖到同格不产生重复记录。
- `TileCellData.TileType` 的数值固定为 `0/1/2`；TilePreset `.tres` 与编辑器 OptionButton 使用同一顺序。
- 地块高度只改变 Tile 顶面与崖壁的 Y；Grid 几何仍定义在 Y=0 平面，M6 的低层激光可据 `TileManager.get_world_height()` 判定遮挡。
- `height_color_low`、`height_color_middle`、`height_color_high` 是关卡资源的一部分；当高度档数多于 3 时，编辑器在下→中与中→上两个区间线性插值。
- 同一组高度色同时驱动编辑器和运行时地形；`TileRenderer` 经 TileManager 查询颜色，避免渲染层直接读取关卡资源。
- 地块编辑画布的键盘控制只在画布获得焦点后生效：WASD 沿当前视角平移、QE 绕关卡焦点旋转、X 放大、C 缩小，滚轮同样可缩放。
- 镜子挂在 Grid Edge，不占 Tile；地块类型不限制 M5/M6 的边镜放置。

## 函数索引

### TileCellData.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(p_cell: Vector3i, p_tile_type: int, p_height_level: int) -> void` | 初始化单格并重置清障状态。 |
| `is_buildable` | `() -> bool` | 判断当前状态是否可建造。 |
| `is_destructible` | `() -> bool` | 判断是否存在未清除的可破坏障碍。 |
| `is_blocked` | `() -> bool` | 判断是否为不可建造路面。 |
| `can_place` | `() -> bool` | 判断可建造且无运行时占用。 |
| `place` | `(new_occupant: Node) -> bool` | 放入运行时占用物；失败不改变状态。 |
| `clear_occupant` | `() -> void` | 清空运行时占用物。 |
| `destroy_obstacle` | `() -> bool` | 清除类型 1 的障碍，保留高度。 |
| `set_height_level` | `(value: int, height_levels: int) -> void` | 按关卡档数钳制高度。 |
| `set_tile_type` | `(value: int) -> void` | 切换类型并恢复未清障状态。 |
| `get_display_name` | `() -> String` | 返回 HUD 用中文状态文本。 |

### TilePreset.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `make_tile` | `(cell: Vector3i, height_levels: int) -> Variant` | 从预制参数创建 TileCellData；返回值在 TileManager 中收窄为 TileCellData。 |

### TileManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `set_grid` | `(value: GridManager) -> void` | 注入唯一 Grid 入口；节点就绪后自动加载已配置关卡。 |
| `load_level` | `(level_resource: LevelResource) -> void` | 清空索引、加载有效序列化格并为遗漏格补默认可建造数据。 |
| `get_tile` | `(cell: Vector3i) -> TileCellData` | 按格坐标返回运行时单格，界外/未索引返回 null。 |
| `get_tiles` | `() -> Array[TileCellData]` | 按当前 Grid 枚举顺序返回完整布局。 |
| `get_world_height` | `(cell: Vector3i) -> float` | 返回该格顶面世界 Y。 |
| `get_height_color` | `(cell: Vector3i) -> Color` | 按关卡的下/中/上色标返回该格运行时高度色。 |
| `can_place` | `(cell: Vector3i) -> bool` | M3 建筑放置入口。 |
| `is_blocked` | `(cell: Vector3i) -> bool` | M4 路径 / M6 光路的地形阻挡查询入口。 |
| `apply_preset` | `(cell: Vector3i, preset: TilePreset) -> bool` | 运行时用预制覆盖一格并发 tile_changed。 |
| `update_tile_type` | `(cell: Vector3i, tile_type: int) -> bool` | 修改运行时类型并通知表现层。 |
| `update_tile_height` | `(cell: Vector3i, height_level: int) -> bool` | 修改运行时高度并按关卡档数钳制。 |
| `destroy_obstacle_at` | `(cell: Vector3i) -> bool` | 清障成功后发 `tile_changed` 和 `obstacle_destroyed`。 |

**信号**：`level_loaded(level_resource: LevelResource)`、`tile_changed(cell: Vector3i, tile: TileCellData)`、`obstacle_destroyed(cell: Vector3i)`。

### TileRenderer.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `set_grid` | `(value: GridManager) -> void` | 订阅 Grid 的 `grid_changed` 并重建表现。 |
| `set_tile_manager` | `(value: TileManager) -> void` | 订阅 TileManager 的布局/单格变化。 |
| `_rebuild` | `() -> void` | 使用 TileManager 高度色重建一组顶点色 terrain mesh 与一组障碍 mesh；无顶点批次清空实例，不调用 `surface_end()`。 |
| `_add_tile_geometry` | `(mesh: ImmediateMesh, tile: TileCellData, terrain_color: Color) -> bool` | 添加指定高度色的顶面；只向更低相邻格或边界生成崖壁，并返回是否实际写入顶点。 |
| `_add_triangle` | `(mesh: ImmediateMesh, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void` | 为三角形的每个顶点写入同一高度色。 |
| `_add_obstacle_geometry` | `(mesh: ImmediateMesh, tile: TileCellData) -> void` | 添加一个四面岩石占位。 |

### Godot 编辑器插件

| 入口 | 关键方法 | 职责 |
|---|---|---|
| `tile_editor_plugin.gd` | `_has_main_screen() -> bool` | 将“地块编辑器”注册为主屏工具。 |
| `tile_palette_item.gd` | `configure(display_name: String, path: String, group: ButtonGroup) -> void` / `_get_drag_data(at_position: Vector2) -> Variant` | 注册互斥画笔按钮并返回 `{kind, preset_path}`。 |
| `tile_editor_canvas.gd` | `set_brush_preset(value: String) -> void` / `_paint_between(from: Vector2, to: Vector2) -> void` | 设置当前画笔；按固定像素采样补齐鼠标路径，连续覆盖经过的格子。 |
| `tile_editor_canvas.gd` | `set_height_brush(value: int) -> void` / `_apply_height_to_cell(cell: Vector3i, height_level: int) -> bool` | 进入独立高度刷模式；仅调用 TileCellData 的高度更新，不改地块类型或清障状态。 |
| `tile_editor_canvas.gd` | `reset_view() -> void` / `_process(delta: float) -> void` | 复位斜俯视投影；在画布焦点内消费 WASD/QE/XC 控制视角。 |
| `tile_editor_canvas.gd` | `_height_color(tile: Resource) -> Color` / `_draw_cell(cell: Vector3i) -> void` | 以三色高度插值绘制顶面，并只对更低邻格绘制加深的台阶墙面。 |
| `tile_editor_canvas.gd` | `_can_drop_data` / `_drop_data` | 判定目标格，读取 TilePreset 参数并覆盖该格，同时将预制设为后续画笔。 |
| `tile_editor_panel.gd` | `_on_brush_selected(preset_path: String) -> void` / `_on_height_brush_changed(index: int) -> void` | 切换类型画笔或独立高度刷，两个模式互斥。 |
| `tile_editor_panel.gd` | `_refresh_height_brush_options() -> void` / `_on_height_color_changed(color: Color, color_stop: int) -> void` | 按关卡档数生成高度刷选项，并同步三档关卡颜色。 |
| `tile_editor_panel.gd` | `_on_cell_selected` / `_on_tile_type_changed` / `_on_tile_height_changed` / `_destroy_selected_obstacle` | 单格参数编辑。 |
| `tile_editor_panel.gd` | `_save_level() -> void` / `_load_level_file(path: String) -> void` | 资源保存/加载；加载使用 `CACHE_MODE_REPLACE_DEEP` 刷新当前会话中的关卡与子资源，保存路径必须在 `res://`。 |

## 使用入口

在 Godot 的 `项目 > 项目设置 > 插件` 确认 `Mirror Tile Editor` 启用后，顶部主屏点击“地块编辑器”。选择网格参数和下/中/上高度色；点击左侧预制按钮选择类型画笔，或从“高度刷”选择目标高度，两者互斥。随后在中间地图左键拖动涂刷；高度刷只改高度，不改类型或障碍状态。右侧仍可修改选中格。点击地图后可用 WASD/QE/XC 或滚轮改变观察视角，工具栏的复位图标返回默认视角。保存路径默认为 `res://resources/levels/CustomLevel.tres`。项目启动时，`scenes/Main.tscn` 引用 `resources/levels/M2DemoLevel.tres` 作为 M2 灰盒验收关卡。

## 已知限制 / 初版不做的部分

- 编辑器支持连续画笔，但不做框选、撤销栈、选区填充或图案刷。
- 障碍只有灰盒岩石占位；不做耐久、掉落或破坏特效。
- 高度为离散台阶，不做斜坡、连续地形和地形变形。
- `occupant` 仅为 M3 预留；M2 不产生建筑占用物。
