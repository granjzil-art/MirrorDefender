## Runtime dispatcher for data-driven tile effects. It only relies on the
## target method contract and never owns enemy lifecycle or movement.
class_name TileEffectSystem
extends Node

@export_group("Feature")
@export var feature_enabled: bool = true

var _tile_manager: TileManager
var _effect_overlay_resolver: Callable

func configure(tile_manager: TileManager) -> void:
	_tile_manager = tile_manager

func set_effect_overlay_resolver(value: Callable) -> void:
	_effect_overlay_resolver = value

func apply_enter(target: Node, cell: Vector3i) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target):
		return
	for effect in _get_effects(cell):
		if effect.affects_target(target):
			effect.apply_enter(target)

func apply_stay(target: Node, cell: Vector3i, duration: float) -> void:
	if not feature_enabled or target == null or not is_instance_valid(target) or duration <= 0.0:
		return
	for effect in _get_effects(cell):
		if effect.affects_target(target):
			effect.apply_stay(target, duration)

func _get_effect(cell: Vector3i) -> TileEffect:
	if _tile_manager == null:
		return null
	var tile := _tile_manager.get_tile(cell)
	return tile.get_effect() if tile != null else null

func _get_effects(cell: Vector3i) -> Array[TileEffect]:
	var effects: Array[TileEffect] = []
	var base_effect := _get_effect(cell)
	if base_effect != null:
		effects.append(base_effect)
	if _effect_overlay_resolver.is_valid():
		var projected: Variant = _effect_overlay_resolver.call(cell)
		if projected is Array:
			for raw_effect in projected:
				if raw_effect is TileEffect:
					effects.append(raw_effect)
	return effects
