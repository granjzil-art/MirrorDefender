# 关卡与存档 · Level

> 实现状态：M2 已实现关卡定义资源与编辑器保存/加载；局内存档、路径、波次、资源与上限字段留待各后续模块扩充。

## 职责
用一个数据资源描述关卡的网格与地块布局，使新增关卡无需改运行时代码；为 M3~M7 的路径、波次、资源和通关存档预留唯一扩展载体。

## 分类 / 做法
- **LevelResource**：自定义 `Resource`，当前保存网格形状、格距、范围、高度配置和 TileCellData 列表。
- **布局按 cell 去重**：`tiles` 是为 Godot 序列化保留的 `Array`，但 `store_tile()` 将同 cell 的旧对象替换为新对象。运行期 TileManager 再建立 `Dictionary[Vector3i, TileCellData]` 索引。
- **编辑器保存**：地块编辑器调用 `ResourceSaver.save(level, path)` 写出 `.tres`；仅允许 `res://` 路径，保存后触发文件系统扫描。
- **运行期加载**：Main 先将 LevelResource 的 grid 参数交给 GridManager，再让 TileManager 读取布局；缺失的格自动补默认可建造数据，不要求手写完整数组。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `grid_shape` | 0 | 0=HEX，1=SQUARE；与 `GridManager.Shape` 顺序一致。 |
| `grid_cell_size` | 1.0 | 交给 GridManager 的单格尺寸。 |
| `grid_size` | `(6, 6)` | HEX 取 x 为半径；SQUARE 取 `(列, 行)`。 |
| `height_levels` | 3 | Tile 高度档数，下限 1。 |
| `height_step` | 0.45 | 每个高度档对应的世界 Y 差。 |
| `tiles` | `[]` | `TileCellData` 资源数组；每项持有自己的 `cell`。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | M2 关卡定义及按 cell 的布局覆盖规则。 |
| `resources/levels/M2DemoLevel.tres` | `LevelResource` | 主场景 M2 验收布局，含道路、两处障碍和 0~2 档高度示例。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 关卡资源的新建、读取和保存入口。 |
| `scenes/Main.tscn` | `Node3D` 场景 | 通过根节点 `level` 导出引用装配 M2DemoLevel。 |

### 模块调用关系 / 数据流

```text
LevelResource (.tres)
  ├─ Main._ready -> GridManager.apply_configuration(shape, size, range)
  └─ Main._ready -> TileManager.load_level(level)
       ├─ serialized tiles -> runtime Dictionary[cell, TileCellData]
       └─ level_loaded -> TileRenderer rebuild

Mirror Tile Editor
  -> creates / edits LevelResource
  -> ResourceSaver.save(.../*.tres)
  -> Main can reference that resource through its `level` export
```

后续模块只扩展 LevelResource 字段或新增其持有的子资源，不创建平行的关卡格式。

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_tile` | `(cell: Vector3i) -> Variant` | 返回给定 cell 的 TileCellData 或 null；返回 Variant 是序列化边界，调用方须显式收窄类型。 |
| `store_tile` | `(tile: Resource) -> void` | 以 `tile.cell` 覆盖/插入布局并标记资源已变化。 |
| `clear_tiles` | `() -> void` | 清空布局，供编辑器按新网格参数重建默认格。 |
| `clamp_tile_heights` | `() -> void` | 将所有序列化地块的高度收紧到当前 `height_levels`。 |

## 约定事实源

- `tiles` 的顺序不代表空间顺序；唯一键是每个 TileCellData 的 `cell`。
- 资源中的 TileCellData 是可保存的配置；TileCellData 的 `occupant` 是运行时字段，绝不写入关卡文件。
- `grid_shape` 与 GridManager 枚举的数值顺序必须保持一致；若未来扩展三角形，先扩展 Grid 枚举与迁移策略，再使用新数值。
- 关卡编辑器生成的是可追踪 `.tres`，不是外部表格；符合“配置优先在 Godot 检视面板/资源内完成”的项目规范。

## 已知限制 / 初版不做的部分

- 未实现 `LevelLoader`、`SaveManager` 或局内读档；M2 由 Main 直接装配当前 LevelResource。
- 路径、波次、初始资源、建筑/镜子上限字段将在 M3/M4/M5 的对应系统接入时加入同一资源。
- 不做云存档、多存档槽和关卡包导入。
