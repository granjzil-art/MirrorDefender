## Test double that simulates an unexpected assembly rejection after preflight.
extends TileManager

var reject_next_load: bool = false


func load_level(level_resource: LevelResource) -> bool:
	if reject_next_load:
		reject_next_load = false
		return false
	return super.load_level(level_resource)
