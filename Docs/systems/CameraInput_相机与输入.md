# 相机与输入 · CameraInput

## 职责
提供 3C 中的相机控制与输入映射，所有键位走 InputMap 可改键。

## 分类 / 做法
- **相机控制**：
  - `WASD` 移动镜头
  - `QE` 旋转镜头
  - `X` 降低俯仰角，`C` 提高俯仰角
  - 仅鼠标滚轮缩放，不保留键盘缩放动作
- **交互输入**：
  - `R` 在建造模式旋转塔虚影；其它模式旋转选中的实际塔。镜子接入后复用同一动作。
  - 鼠标左键：放置 / 选择
  - 鼠标右键：取消
- **M6 正式交互**：`RuntimeInteractionController` 取代 M3DebugPanel 成为模式事实源；选卡后的下一次世界左键无论成功或失败都结束放置。右键由 Main 的 `_input` 在 GUI 分发前全局消费，确保鼠标位于 HUD 上时也能取消。
- **战术慢放相机**：CameraController 将缩放后的 `delta` 除以当前非零 `Engine.time_scale`，因此 0.1x 战术慢放下 WASD/QE/XC 手感仍按真实时间运行；暂停 0x 时不人为放大 delta。
- **模态输入边界**：M6 暂停菜单展开时，`Main` 停止世界拾取/交互并通过 `CameraController.set_input_enabled(false)` 锁定 WASD/QE/XC/滚轮；继续后统一解锁。
- **六机位预设**：数字键 `1`～`6` 读取当前 `LevelResource` 的同号可选机位。已配置槽位按真实时间平滑过渡焦点、yaw、pitch 和缩放距离；空槽、无效槽或未加载关卡无动作。
- **过渡输入边界**：过渡期间 `CameraController` 只抑制手动移动/旋转/俯仰/滚轮；结束或切关后恢复。暂停及后续控制台通过既有 `input_enabled` 总锁冻结过渡，避免模态层背后移动镜头。
- **可改键**：所有键位通过 Godot **InputMap** 定义，玩家可重映射。
- 支持屏幕边缘平移 `edge_pan`（可开关）。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

> 以下默认值与 `CameraController.gd` 实际一致（@export_group 分组）。

| 参数名 | 分组 | 默认值 | 说明 |
|---|---|---|---|
| input_enabled | Feature | true | 运行时相机输入总开关；暂停模态层开启时由 Main 暂时关闭。 |
| move_speed | Move | 8.0 | 镜头平移速度 |
| edge_pan | Move | false | 是否启用屏幕边缘平移 |
| edge_pan_margin | Move | 16.0 | 边缘平移触发像素带宽 |
| rotate_speed | Rotate | 90.0 | 镜头旋转速度(度/秒) |
| zoom_distance | Zoom | 16.0 | 当前缩放距离（相机到焦点） |
| zoom_min / zoom_max | Zoom | 2.0 / 30.0 | 缩放距离范围；最近距离由 5 降至 2，支持更大放大倍率 |
| zoom_wheel_step | Zoom | 1.5 | 滚轮每格步进 |
| pitch_angle | Pitch | 50.0 | 当前俯仰角（度） |
| pitch_min / pitch_max | Pitch | 18.0 / 82.0 | XC 调节时的俯仰角边界，避免水平穿地或垂直奇异点 |
| pitch_speed | Pitch | 55.0 | XC 持续调节俯仰的速度（度/秒） |
| camera_presets_enabled | Main / M6 Camera Presets | true | 六机位运行时总开关；装配时写入 CameraPresetController。 |
| camera_preset_transition_duration | Main / M6 Camera Presets | 0.35 | 镜头切换时长（真实秒）；0 表示立即切换。 |
| camera_preset_transition_curve | Main / M6 Camera Presets | 空 | 可选 0～1 Curve；空时使用 smoothstep。 |
| feature_enabled | CameraPresetController / Feature | true | 预设输入与请求总开关。 |
| transition_duration | CameraPresetController / Transition | 0.35 | 控制器实际使用的切换时长。 |
| transition_curve | CameraPresetController / Transition | 空 | 控制器实际使用的可选缓动曲线。 |

## 关键架构

### gimbal 相机结构（`scripts/camera/CameraController.gd`，`class_name CameraController extends Node3D`）
```
CameraController (本节点 = pivot 焦点)
 ├─ position: 焦点在世界 XZ 平面移动
 ├─ rotation.y: yaw（QE 绕 Y 轴旋转）
 └─ 子节点 Camera3D（在 Main.tscn 中作为 $CameraRig/Camera3D）
      └─ 由 _apply_camera_transform() 依可调 pitch_angle + zoom_distance 放到
         焦点后上方并俯视焦点 (local_pos = (0, sin(p), cos(p)) * zoom)
```
- **移动方向随 yaw 旋转**：WASD 输入向量按当前 `rotation.y` 变换到世界方向，保证"往屏幕上方走"符合视角。
- **场景装配**：`Main.tscn` 中节点名 `CameraRig`（挂本脚本），其下有一个 `Camera3D` 子节点；`Main.gd` 通过 `cam_rig.get_camera()` 拿相机做拾取。

### 六机位数据流

```text
LevelLoader.level_loaded
  -> Main._on_level_loaded
     -> CameraPresetController.load_level(level)

InputMap camera_preset_1 ... camera_preset_6
  -> CameraPresetController.request_preset(slot_index)
     -> LevelResource.get_camera_preset(slot_index)
     -> CameraController.get_view_state()
     -> 真实时间插值（focus Vector3 + shortest yaw + pitch + zoom）
     -> CameraController.apply_view_state(...)
```

- `CameraPresetDefinition` 是纯数据子资源，坐标为世界坐标，角度以度保存，缩放保存 CameraController 的世界距离。
- `CameraPresetController` 是当前关卡和过渡状态的唯一事实源；`CameraController` 只负责应用一个完整视角和屏蔽过渡期间的手动输入。
- Main 只装配控制器、传入 Inspector 参数并在切关信号上转交 LevelResource，不解释槽位或插值规则。
- 编辑器使用独立镜头页；其正交像素缩放按 75° 垂直 FOV 换算为运行时距离，资源中不保存编辑器私有像素比例。
- TabContainer 的隐藏页面在首次布局前尺寸为零；`TileEditorCanvas` 会保持 `reset_view` 待处理，直到页面获得有效尺寸。关卡面板在地块/路径/镜头 Tab 激活时调用 `ensure_view_initialized()`，避免把零尺寸换算成最小缩放。
- Godot 4.7 的 `EditorInterface.get_editor_main_screen()` 将插件页面放入名为 `MainScreen` 的 `VBoxContainer`；锚点在 Container 下不负责分配尺寸，因此 `tile_editor_plugin.gd` 和面板 `_ready()` 都显式设置横纵 `SIZE_EXPAND_FILL`。缺少此契约时根面板高度为 0，子控件即使 `visible=true` 也无法显示。

### 输入现状（M6 批次 1）
- **相机输入**：`CameraController` 用 `Input.get_action_strength` 处理移动、旋转和俯仰；`_unhandled_input` 独占滚轮缩放。关卡编辑画布保持相同的 XC/滚轮语义。
- **Main 场景路由**：`place_select` 把格/边拾取交给 RuntimeInteractionController；`cancel_action` 全局回到选择模式；`rotate_facing` 依次处理镜子预览翻面、选中镜子翻面、建筑预览旋转或选中建筑旋转。
- **世界固定朝向**：建筑与镜子方向只读 Grid 形状及自身 facing/active side；CameraRig yaw 不参与玩法方向计算。独立 InputRouter 尚未拆分。

## 函数索引
> gimbal 结构：本节点=焦点（可平移+yaw），子 Camera3D 使用可调 pitch 俯视。

### CameraController.gd
| 函数 | 签名 | 职责 |
|---|---|---|
| `_ready` | `() -> void` | 首次应用相机 transform |
| `_process` | `(delta: float) -> void` | 将非零时间倍率还原为真实 delta，再调用移动、旋转和俯仰处理 |
| `_handle_move` | `(delta) -> void` | WASD（+可选 edge_pan）沿当前 yaw 平移焦点 |
| `_edge_pan_input` | `() -> Vector2` | 屏幕边缘平移输入（edge_pan 开关） |
| `_handle_rotate` | `(delta) -> void` | QE 绕 Y 轴旋转 yaw |
| `_handle_pitch` | `(delta: float) -> void` | X 降低、C 提高俯仰并按参数限位 |
| `_unhandled_input` | `(event: InputEvent) -> void` | 唯一缩放入口；鼠标滚轮 WHEEL_UP/DOWN 缩放 |
| `_set_zoom` | `(v: float) -> void` | `clampf` 到 [zoom_min,zoom_max] 并刷新相机 |
| `_set_pitch` | `(v: float) -> void` | `clampf` 到 [pitch_min,pitch_max] 并刷新相机 |
| `_apply_camera_transform` | `() -> void` | 依 pitch+zoom 放置子相机并俯视焦点 |
| `get_camera` | `() -> Camera3D` | 返回子 Camera3D（供 Main 拾取用） |
| `get_zoom_distance` / `get_pitch_angle` | `() -> float` / `() -> float` | 提供调试 UI 和回归测试所需的只读当前状态 |
| `set_input_enabled` | `(enabled: bool) -> void` | 统一开关所有相机移动、旋转、俯仰和滚轮缩放输入。 |
| `is_input_enabled` | `() -> bool` | 返回暂停/控制台共用的相机输入总锁状态。 |
| `set_preset_transition_active` | `(active: bool) -> void` | 仅抑制预设过渡期间的手动相机输入。 |
| `is_preset_transition_active` | `() -> bool` | 返回是否正由机位控制器接管视角。 |
| `get_view_state` | `() -> Dictionary` | 返回 `{focus_position: Vector3, yaw_degrees: float, pitch_degrees: float, zoom_distance: float}`。 |
| `apply_view_state` | `(focus_position: Vector3, yaw_degrees: float, pitch_degrees: float, distance: float) -> void` | 原子应用完整视角并按 CameraController 范围收紧 pitch/zoom。 |

### CameraPresetDefinition.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `validate_configuration` | `() -> Array[String]` | 只读校验焦点、角度与距离是否有限且落在资源合法域。 |
| `to_camera_state` | `() -> Dictionary` | 返回与 CameraController 相同的四键视角字典。 |

### CameraPresetController.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(camera_controller: CameraController) -> void` | 注入唯一 gimbal 相机并清理旧过渡锁。 |
| `load_level` | `(level: LevelResource) -> void` | 切换当前预设事实源并取消旧关卡过渡。 |
| `request_preset` | `(slot_index: int) -> bool` | 请求零基槽位；已配置且合法时开始/立即完成过渡。 |
| `advance_transition` | `(real_delta: float) -> void` | 以真实秒确定性推进焦点、最短 yaw、pitch 与 zoom 插值。 |
| `cancel_transition` | `() -> void` | 清空状态并解除 CameraController 手动输入抑制。 |
| `is_transition_active` | `() -> bool` | 返回是否存在进行中的机位过渡。 |
| `get_loaded_level` | `() -> LevelResource` | 返回当前预设来源关卡。 |

### tile_editor_canvas.gd（镜头页公开入口）

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_camera_view_state` | `() -> Dictionary` | 返回 `{focus_position, yaw_degrees, pitch_degrees, zoom_distance}`；将编辑器像素比例转换为运行时距离。 |
| `apply_camera_view_state` | `(focus_position: Vector3, yaw_degrees: float, pitch_degrees: float, zoom_distance: float) -> void` | 将运行时视角语义应用到编辑器斜投影画布。 |
| `ensure_view_initialized` | `() -> void` | 仅在尚未以有效页面尺寸初始化时补做地图适配；已操作过的视角不重置。 |

### camera_preset_editor.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(level: LevelResource, canvas: Control) -> void` | 注入当前关卡和独立镜头预览画布，不修改关卡。 |
| `refresh` | `() -> void` | 按六槽实时刷新配置状态及预览/清空按钮可用性。 |
| `capture_slot` | `(slot_index: int) -> bool` | 将当前画布视角写入零基槽位并发出 `level_changed`。 |
| `preview_slot` | `(slot_index: int) -> bool` | 只读跳转到已保存机位，不标记资源变化。 |
| `clear_slot` | `(slot_index: int) -> bool` | 清空已配置槽位并发出 `level_changed`。 |
| `get_slot_status` | `(slot_index: int) -> String` | 返回用户可见的“已配置/未配置”状态文本。 |

**信号**：`level_changed()` 通知关卡面板标记未保存；`status_changed(message: String)` 更新编辑器状态提示。

### tile_editor_panel.gd（镜头页装配）

| 函数 | 签名 | 职责 |
|---|---|---|
| `_add_camera_tab` | `(tabs: TabContainer) -> void` | 装配独立六槽侧栏、滚动区域和镜头预览画布。 |
| `_on_editor_tab_changed` | `(_tab_index: int) -> void` | 将页面切换延迟到容器完成本帧布局后处理。 |
| `_refresh_active_editor_tab` | `() -> void` | 重新排序当前容器，并为地块/路径/镜头画布补做一次有效尺寸初始化。 |

### tile_editor_plugin.gd（Godot 主屏幕装配）

| 函数 | 签名 | 职责 |
|---|---|---|
| `_enter_tree` | `() -> void` | 创建关卡编辑面板，在加入 Godot 主屏幕 VBox 前设置横纵 `SIZE_EXPAND_FILL`。 |

### Main.gd（M6 正式输入路由）
| 函数 | 签名 | 职责 |
|---|---|---|
| `_input` | `(event: InputEvent) -> void` | 在 GUI 前全局消费右键取消，清除卡片、预览和实体选择。 |
| `_unhandled_input` | `(event: InputEvent) -> void` | 路由 T/左键/R/F 到当前模块入口；GUI 已消费的左键不会到达这里。 |
| `_handle_primary_action` | `() -> void` | 拾取格/边并交给 RuntimeInteractionController 选择或单次放置。 |
| `_lock_current_pick` | `() -> void` | 保存当前格/边选择供 HUD 与建筑选择使用。 |
| `_on_runtime_modal_state_changed` | `(open: bool) -> void` | 同步相机输入锁，开启模态层时清除预览和世界高亮。 |

### InputMap 动作全表（`project.godot`）
| 动作名 | 默认键 | 用途 | M1 消费者 |
|---|---|---|---|
| `cam_move_forward/back/left/right` | W/S/A/D | 平移镜头 | CameraController |
| `cam_rotate_left/right` | Q/E | 旋转镜头 yaw | CameraController |
| `cam_pitch_lower/raise` | X/C | 降低/提高相机俯仰角 | CameraController |
| `camera_preset_1` ... `camera_preset_6` | 1～6 | 切换当前关卡的六个可选镜头预设 | CameraPresetController |
| `toggle_grid_shape` | T | 切 HEX↔SQUARE | Main.gd |
| `rotate_facing` | R | 镜子预览/实体翻面，或建筑预览/实体顺时针旋转 | Main -> MirrorManager / BuildingManager |
| `place_select` | 鼠标左键 | 执行当前选择或一次正式卡片放置 | Main.gd -> RuntimeInteractionController |
| `cancel_action` | 鼠标右键 | 全局回到选择模式并清除选择/预览 | Main.gd -> RuntimeInteractionController |

### 实现文件

| 文件 | class_name / 基类 | 职责 |
|---|---|---|
| `scripts/camera/CameraController.gd` | `CameraController` / `Node3D` | 运行时 gimbal 平移、yaw、pitch 与滚轮缩放。 |
| `scripts/camera/CameraPresetDefinition.gd` | `CameraPresetDefinition` / `Resource` | 一个关卡镜头槽位的焦点、yaw、pitch 和缩放距离。 |
| `scripts/camera/CameraPresetController.gd` | `CameraPresetController` / `Node` | 数字键解析、关卡生命周期和真实时间平滑过渡。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control`（tool） | 关卡编辑器斜投影视角，复用 XC 俯仰与滚轮缩放语义。 |
| `addons/mirror_tile_editor/camera_preset_editor.gd` | `CameraPresetEditor` / `VBoxContainer`（tool） | 六槽写入、预览、清空和配置状态侧栏。 |
| `addons/mirror_tile_editor/tile_editor_plugin.gd` | `EditorPlugin`（tool） | 将关卡编辑器作为 Godot 主屏幕插件挂载并保证 Container 扩展布局。 |
| `tests/camera_input_test.gd` | `SceneTree` | InputMap、俯仰限位、仅滚轮缩放和双端放大倍率回归。 |
| `tests/runtime_ui_batch5_test.gd` | `SceneTree` | 六槽持久化、插值、输入锁、旧关卡兼容和编辑器集成回归。 |

## 已知限制 / 初版不做的部分
- 不做手柄/触屏输入，仅键鼠。
- 相机不做碰撞避让、过肩/自由飞行模式。
- 不做输入宏/连招，单键单动作。
- 镜头预设不保存 Camera3D FOV；编辑器预览换算与当前运行时默认 75° 垂直 FOV 对齐。未来若开放 FOV 调参，需将它提升为两端共享配置。
