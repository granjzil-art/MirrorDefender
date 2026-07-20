## Runtime dispatcher for data-driven tile effects. It only relies on the
## target method contract and never owns enemy lifecycle or movement.
class_name TileEffectSystem
extends Node

@export_group("Feature")
@export var feature_enabled: bool = true

var _tile_manager: TileManager

func configure(tile_manager: TileManager) -> void:
	_tile_manager = tile_manager

func apply_enter(target: Node, cell: Vector3i) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target):
		return
	var effect := _get_effect(cell)
	if effect != null and effect.affects_target(target):
		effect.apply_enter(target)

func apply_stay(target: Node, cell: Vector3i, duration: float) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target) or duration <= 0.0:
		return
	var effect := _get_effect(cell)
	if effect != null and effect.affects_target(target):
		effect.apply_stay(target, duration)

func _get_effect(cell: Vector3i) -> TileEffect:
	if _tile_manager == null:
		return null
	var tile := _tile_manager.get_tile(cell)
	return tile.get_effect() if tile != null else null
