# 关卡与存档 · Level

## 职责
以数据资源描述关卡内容并管理进度存档，与逻辑解耦，加新关卡不改代码。

## 分类 / 做法
- **关卡数据资源**：关卡用 `.tres` / 自定义 `Resource` 描述，包含：
  - 网格形状（hex/square，见 Grid）
  - 地块布局（Tile 数据）
  - 路径（Path 集合）
  - 波次配置（Wave / SpawnGroup）
  - 初始资源（main_resource / cap 等）
- **解耦**：加新关卡只需新增一个 Level Resource 文件，**不改代码**。
- **存档**：记录进度（已通关卡、当前关卡等），独立于关卡定义。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| grid_shape | hex | 该关卡网格形状 |
| tile_layout | - | 地块布局数据（cell → Tile 配置） |
| paths | [] | 路径集合（Path 资源引用） |
| waves | [] | 波次配置（Wave 资源引用） |
| initial_resource | 200 | 初始主资源 |
| building_cap / mirror_cap | 20 / 6 | 该关卡建筑/镜子上限 |

## 关键架构
```
LevelResource (Resource)
 └─ { grid_shape, tile_layout, paths, waves, initial_resource, caps }
LevelLoader (Node)
 ├─ load(level_resource) → 构建 Grid/Tile/Path/Wave/Resource
 └─ 与各 Manager 对接，纯数据驱动
SaveManager
 ├─ save_progress() / load_progress()   # 已通关卡等
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 存档仅记录关卡进度，不做局内实时存档/读档。
- 不做关卡编辑器导出流程（关卡资源手工/编辑器工具生成）。
- 不做云存档、多存档槽。
