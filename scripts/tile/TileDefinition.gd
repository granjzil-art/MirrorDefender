@tool
## Reusable, data-driven terrain archetype referenced by serialized cells.
class_name TileDefinition
extends Resource

enum SurfaceKind {
	BUILDABLE,
	DESTRUCTIBLE,
	ROAD,
	ELEMENT,
}

enum VisualKind {
	NONE,
	SPIKES,
	HOLE,
	ROCK,
}

@export_group("Identity")
@export var tile_id: StringName = &"buildable"
@export var display_name: String = "可建造"

@export_group("Surface")
@export_enum("可建造表面", "可破坏障碍", "不可建造路面", "关卡元素") var surface_kind: int = SurfaceKind.BUILDABLE
## Additional permission gate shared by normal tile buildings and path blockers.
@export var allows_tile_building: bool = true
@export var allows_edge_building: bool = true

@export_group("Gameplay")
@export var effect: TileEffect

@export_group("Presentation")
@export var override_terrain_color: bool = false
@export var terrain_color: Color = Color.WHITE
@export_enum("无", "尖刺", "空洞", "岩石") var visual_kind: int = VisualKind.NONE
@export var visual_color: Color = Color(0.2, 0.2, 0.2, 1.0)
## Future art hook. Greybox renderers use visual_kind until a scene is assigned.
@export var visual_scene: PackedScene

func is_buildable(obstacle_destroyed: bool) -> bool:
	return surface_kind == SurfaceKind.BUILDABLE or (
		surface_kind == SurfaceKind.DESTRUCTIBLE and obstacle_destroyed
	)

func is_destructible(obstacle_destroyed: bool) -> bool:
	return surface_kind == SurfaceKind.DESTRUCTIBLE and not obstacle_destroyed

func is_blocked_surface() -> bool:
	return surface_kind == SurfaceKind.ROAD

func blocks_enemy_navigation() -> bool:
	return effect != null and effect.blocks_enemy_navigation()

func can_use_for_reroute() -> bool:
	return effect == null or effect.can_use_for_reroute()

## Stable presentation contract for editor tools that should not depend on
## this runtime Resource's global enum being registered during hot reload.
func get_visual_tag() -> StringName:
	match visual_kind:
		VisualKind.SPIKES:
			return &"spikes"
		VisualKind.HOLE:
			return &"hole"
		VisualKind.ROCK:
			return &"rock"
	return &"none"

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if tile_id.is_empty():
		errors.append("地块定义 ID 不能为空")
	if display_name.strip_edges().is_empty():
		errors.append("地块定义显示名不能为空")
	if effect != null:
		errors.append_array(effect.validate_configuration())
	return errors
