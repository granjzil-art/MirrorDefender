# 相机与输入 · CameraInput

## 职责
提供 3C 中的相机控制与输入映射，所有键位走 InputMap 可改键。

## 分类 / 做法
- **相机控制**：
  - `WASD` 移动镜头
  - `QE` 旋转镜头
  - `XC` 与鼠标滚轮缩放
- **交互输入**：
  - `R` 在建造模式旋转塔虚影；其它模式旋转选中的实际塔。镜子接入后复用同一动作。
  - 鼠标左键：放置 / 选择
  - 鼠标右键：取消
- **可改键**：所有键位通过 Godot **InputMap** 定义，玩家可重映射。
- 支持屏幕边缘平移 `edge_pan`（可开关）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

> 以下默认值与 `CameraController.gd` 实际一致（@export_group 分组）。

| 参数名 | 分组 | 默认值 | 说明 |
|---|---|---|---|
| move_speed | Move | 8.0 | 镜头平移速度 |
| edge_pan | Move | false | 是否启用屏幕边缘平移 |
| edge_pan_margin | Move | 16.0 | 边缘平移触发像素带宽 |
| rotate_speed | Rotate | 90.0 | 镜头旋转速度(度/秒) |
| zoom_distance | Zoom | 16.0 | 当前缩放距离（相机到焦点） |
| zoom_min / zoom_max | Zoom | 5.0 / 30.0 | 缩放距离范围（clamp 上下限） |
| zoom_speed | Zoom | 20.0 | XC 持续缩放速度 |
| zoom_wheel_step | Zoom | 1.5 | 滚轮每格步进 |
| pitch_angle | Zoom | 50.0 | 相机俯仰角(度)，固定 |

## 关键架构

### gimbal 相机结构（`scripts/camera/CameraController.gd`，`class_name CameraController extends Node3D`）
```
CameraController (本节点 = pivot 焦点)
 ├─ position: 焦点在世界 XZ 平面移动
 ├─ rotation.y: yaw（QE 绕 Y 轴旋转）
 └─ 子节点 Camera3D（在 Main.tscn 中作为 $CameraRig/Camera3D）
      └─ 由 _apply_camera_transform() 依 pitch_angle + zoom_distance 放到
         焦点后上方并俯视焦点 (local_pos = (0, sin(p), cos(p)) * zoom)
```
- **移动方向随 yaw 旋转**：WASD 输入向量按当前 `rotation.y` 变换到世界方向，保证"往屏幕上方走"符合视角。
- **场景装配**：`Main.tscn` 中节点名 `CameraRig`（挂本脚本），其下有一个 `Camera3D` 子节点；`Main.gd` 通过 `cam_rig.get_camera()` 拿相机做拾取。

### 输入现状（M3）
- **相机输入**：全部在 `CameraController` 内用 `Input.get_action_strength` + `_unhandled_input`(滚轮) 处理。
- **Main 场景路由**：`place_select` 根据 M3DebugPanel 模式选择建筑、放箭塔/激光塔或生成靶标；`cancel_action` 回到选择模式；`rotate_facing` 在有建造定义时调 `BuildingManager.rotate_preview()`，否则调 `rotate_selected()`。
- **世界固定朝向**：建筑方向只读 Grid 形状与 facing_index；CameraRig yaw 不参与计算。镜子输入在 M5/M6 接入同一动作时再抽出独立 InputRouter。

## 函数索引
> M1 已实现。gimbal 结构：本节点=焦点(可平移+yaw)，子 Camera3D 固定 pitch 俯视。

### CameraController.gd
| 函数 | 签名 | 职责 |
|---|---|---|
| `_ready` | `() -> void` | 首次应用相机 transform |
| `_process` | `(delta) -> void` | 每帧调用移动/旋转/缩放三处理 |
| `_handle_move` | `(delta) -> void` | WASD（+可选 edge_pan）沿当前 yaw 平移焦点 |
| `_edge_pan_input` | `() -> Vector2` | 屏幕边缘平移输入（edge_pan 开关） |
| `_handle_rotate` | `(delta) -> void` | QE 绕 Y 轴旋转 yaw |
| `_handle_zoom_keys` | `(delta) -> void` | XC 持续缩放 |
| `_unhandled_input` | `(event) -> void` | 鼠标滚轮 WHEEL_UP/DOWN 缩放 |
| `_set_zoom` | `(v: float) -> void` | `clampf` 到 [zoom_min,zoom_max] 并刷新相机 |
| `_apply_camera_transform` | `() -> void` | 依 pitch+zoom 放置子相机并俯视焦点 |
| `get_camera` | `() -> Camera3D` | 返回子 Camera3D（供 Main 拾取用） |

### Main.gd（M3 输入路由）
| 函数 | 签名 | 职责 |
|---|---|---|
| `_unhandled_input` | `(event: InputEvent) -> void` | 路由 T/左键/右键/R/F 到当前模块入口。 |
| `_handle_primary_action` | `() -> void` | 拾取格并按 M3DebugPanel 模式执行选择、建塔或靶标生成。 |
| `_lock_current_pick` | `() -> void` | 保存当前格/边选择供 HUD 与建筑选择使用。 |

### InputMap 动作全表（`project.godot`）
| 动作名 | 默认键 | 用途 | M1 消费者 |
|---|---|---|---|
| `cam_move_forward/back/left/right` | W/S/A/D | 平移镜头 | CameraController |
| `cam_rotate_left/right` | Q/E | 旋转镜头 yaw | CameraController |
| `cam_zoom_in/out` | X/C | 缩放（+滚轮） | CameraController |
| `toggle_grid_shape` | T | 切 HEX↔SQUARE | Main.gd |
| `rotate_facing` | R | 建造模式转塔虚影，否则转选中塔；M5/M6 再接镜子 | Main -> BuildingManager |
| `place_select` | 鼠标左键 | 执行当前选择/建塔/靶标模式 | Main.gd（M3） |
| `cancel_action` | 鼠标右键 | 回到选择模式 | Main.gd -> M3DebugPanel |

## 已知限制 / 初版不做的部分
- 不做手柄/触屏输入，仅键鼠。
- 相机不做碰撞避让、过肩/自由飞行模式。
- 不做输入宏/连招，单键单动作。
