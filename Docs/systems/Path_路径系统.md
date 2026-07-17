# 路径系统 · Path

## 职责
提供由设计者在编辑器手动指定的单位行进路径，不做自动寻路。

## 分类 / 做法
- **手动指定**：路径由设计者在编辑器绘制/指定为**一串格子/点**（有序序列），不做 A*/自动寻路。
- **双网格支持**：兼容六边形与正方形网格（基于 Grid 的 cell 序列）。
- **多路径**：一个关卡可有多条路径，供不同波次/SpawnGroup 使用（通过 `path_id` 引用）。
- **移动**：单位沿 path 匀速移动（速度取自 Unit.move_speed）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| path_list | [] | 路径集合，每条为有序格子序列 |
| path_id | - | 路径标识，供 Wave/Unit 引用 |
| Path.cells | [] | 该路径的有序 cell 序列（起点→据点） |

## 关键架构
```
Path (Resource)
 ├─ path_id: String
 └─ cells: [cell]   # 有序，起点 → 我方据点
PathManager (Node)
 ├─ paths: { path_id: Path }
 ├─ get_path(path_id) -> Path
 └─ sample_position(path, t) -> world_pos   # 匀速插值供 Unit 移动
PathEditor (编辑器工具): 点选格子生成有序序列
```

## 函数索引
> 实现阶段填充：函数名 → 一句话职责。

## 已知限制 / 初版不做的部分
- 不做自动寻路、动态避障、路径重算。
- 路径为静态数据，运行时不可变。
- 不做分叉/合流的图状路径，仅线性有序序列（多条独立 path 表达多样性）。
