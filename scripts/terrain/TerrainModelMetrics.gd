## TerrainModelMetrics -- shared model-space proportions for authored voxels.
##
## One authored terrain voxel is a 1:1 block: its logical layer height equals
## one Grid cell size. Levels may use another world cell size, but cannot
## independently squash or stretch the vertical layer spacing.
class_name TerrainModelMetrics
extends RefCounted

const LAYER_HEIGHT_TO_CELL_SIZE: float = 1.0
const DEFAULT_LAYER_HEIGHT: float = 1.0


static func get_layer_height(grid_cell_size: float) -> float:
	if not is_finite(grid_cell_size) or grid_cell_size <= 0.0:
		return DEFAULT_LAYER_HEIGHT
	return grid_cell_size * LAYER_HEIGHT_TO_CELL_SIZE
