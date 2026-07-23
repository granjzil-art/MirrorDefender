## Strategy contract for runtime-only automatic routes. Implementations must
## never mutate LevelResource or PathDefinition data.
class_name IAutoRouteStrategy
extends RefCounted


func find_route(
	_grid: GridManager,
	_tile_manager: TileManager,
	_start: Vector3i,
	_goal: Vector3i,
	_allowed_cells: Dictionary,
	_target: Node = null
) -> Array[Vector3i]:
	return []
