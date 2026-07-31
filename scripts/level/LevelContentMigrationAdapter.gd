@tool
## LevelContentMigrationAdapter -- one-way compatibility boundary from legacy
## TileCellData/TileDefinition content to canonical Grid/Ramp/Stuff resources.
class_name LevelContentMigrationAdapter
extends RefCounted

const CANONICAL_CONTENT_VERSION: int = 2

const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")
const TileDefinitionScript := preload("res://scripts/tile/TileDefinition.gd")


## Returns `{content_version, migrated, default_terrain, layer_height,
## grid_cells, ramp_placements, stuff_placements}` without mutating level.
static func build_snapshot(level: Resource) -> Dictionary:
	if level == null:
		return _empty_snapshot()
	if uses_canonical_content(level):
		return _build_canonical_snapshot(level)
	return _build_legacy_snapshot(level)


static func uses_canonical_content(level: Resource) -> bool:
	if level == null:
		return false
	if int(level.get("terrain_content_version")) >= CANONICAL_CONTENT_VERSION:
		return true
	if level.get("default_terrain") is TerrainDefinitionScript:
		return true
	return (
		_not_empty_array(level.get("grid_cells"))
		or _not_empty_array(level.get("ramp_placements"))
		or _not_empty_array(level.get("stuff_placements"))
	)


## Explicit editor/save migration entry. Legacy `tiles` remain serialized until
## the runtime switch is complete, so batch 1 cannot change current gameplay.
static func migrate_in_place(level: Resource) -> bool:
	if level == null or uses_canonical_content(level):
		return false
	var snapshot := _build_legacy_snapshot(level)
	level.set("terrain_content_version", CANONICAL_CONTENT_VERSION)
	level.set("default_terrain", snapshot["default_terrain"])
	level.set("layer_height", snapshot["layer_height"])
	level.set("grid_cells", snapshot["grid_cells"])
	level.set("ramp_placements", snapshot["ramp_placements"])
	level.set("stuff_placements", snapshot["stuff_placements"])
	level.emit_changed()
	return true


static func _build_canonical_snapshot(level: Resource) -> Dictionary:
	var grid_cells: Array[GridCellDataScript] = []
	var ramp_placements: Array[RampPlacementDataScript] = []
	var stuff_placements: Array[StuffPlacementDataScript] = []
	for raw_cell in _as_array(level.get("grid_cells")):
		if raw_cell is GridCellDataScript:
			grid_cells.append(raw_cell)
	for raw_ramp in _as_array(level.get("ramp_placements")):
		if raw_ramp is RampPlacementDataScript:
			ramp_placements.append(raw_ramp)
	for raw_stuff in _as_array(level.get("stuff_placements")):
		if raw_stuff is StuffPlacementDataScript:
			stuff_placements.append(raw_stuff)
	var default_terrain: TerrainDefinitionScript = level.get("default_terrain") as TerrainDefinitionScript
	return {
		"content_version": CANONICAL_CONTENT_VERSION,
		"migrated": false,
		"default_terrain": default_terrain,
		"layer_height": float(level.get("layer_height")),
		"grid_cells": grid_cells,
		"ramp_placements": ramp_placements,
		"stuff_placements": stuff_placements,
	}


static func _build_legacy_snapshot(level: Resource) -> Dictionary:
	var default_terrain := _make_legacy_default_terrain(level)
	var grid_cells: Array[GridCellDataScript] = []
	var ramp_placements: Array[RampPlacementDataScript] = []
	var stuff_placements: Array[StuffPlacementDataScript] = []
	var terrain_variants: Dictionary = {}
	var stuff_variants: Dictionary = {}
	for raw_tile in _as_array(level.get("tiles")):
		if not raw_tile is TileCellDataScript:
			continue
		var tile: TileCellDataScript = raw_tile
		var has_stuff := _legacy_tile_has_active_stuff(tile)
		var permissions := _legacy_base_permissions(tile, has_stuff)
		var terrain := _resolve_legacy_terrain(tile, level, default_terrain, terrain_variants)
		var grid_cell := GridCellDataScript.new()
		grid_cell.configure(
			tile.cell,
			terrain,
			clampi(tile.height_level + 1, GridCellDataScript.MIN_LAYER_COUNT, GridCellDataScript.MAX_LAYER_COUNT),
			bool(permissions["tile"]),
			bool(permissions["edge"])
		)
		grid_cells.append(grid_cell)
		if not has_stuff:
			continue
		var stuff_definition := _resolve_legacy_stuff_definition(tile, stuff_variants)
		if stuff_definition == null:
			continue
		var placement := StuffPlacementDataScript.new()
		placement.configure(
			_make_legacy_placement_id(tile, stuff_definition),
			tile.cell,
			stuff_definition,
			0
		)
		stuff_placements.append(placement)
	return {
		"content_version": CANONICAL_CONTENT_VERSION,
		"migrated": true,
		"default_terrain": default_terrain,
		"layer_height": float(level.get("height_step")),
		"grid_cells": grid_cells,
		"ramp_placements": ramp_placements,
		"stuff_placements": stuff_placements,
	}


static func _make_legacy_default_terrain(level: Resource) -> TerrainDefinitionScript:
	var terrain := TerrainDefinitionScript.new()
	terrain.terrain_id = &"grass"
	terrain.display_name = "草地"
	var low_color: Variant = level.get("height_color_low")
	if low_color is Color:
		terrain.fallback_color = low_color
	var legacy_model: Variant = level.get("tile_model_asset")
	if legacy_model is ModelAssetDefinition:
		terrain.flat_model_asset = legacy_model
	return terrain


static func _resolve_legacy_terrain(
	tile: Resource,
	_level: Resource,
	default_terrain: TerrainDefinitionScript,
	cache: Dictionary
) -> TerrainDefinitionScript:
	var definition: TileDefinitionScript = tile.definition as TileDefinitionScript
	var override_asset: ModelAssetDefinition = null
	if definition != null:
		override_asset = definition.terrain_model_asset
	if override_asset == null:
		return default_terrain
	var cache_key := definition.get_instance_id()
	if cache.has(cache_key):
		return cache[cache_key]
	var terrain := TerrainDefinitionScript.new()
	terrain.terrain_id = StringName("legacy_terrain_%d" % cache.size())
	terrain.display_name = default_terrain.display_name
	terrain.fallback_color = (
		definition.terrain_color
		if definition.override_terrain_color
		else default_terrain.fallback_color
	)
	terrain.flat_model_asset = override_asset
	cache[cache_key] = terrain
	return terrain


static func _legacy_tile_has_active_stuff(tile: Resource) -> bool:
	if tile.obstacle_destroyed:
		return false
	var definition: TileDefinitionScript = tile.definition as TileDefinitionScript
	if definition == null:
		return tile.tile_type == TileCellDataScript.TileType.DESTRUCTIBLE
	return (
		definition.surface_kind == TileDefinitionScript.SurfaceKind.DESTRUCTIBLE
		or definition.surface_kind == TileDefinitionScript.SurfaceKind.ELEMENT
		or definition.effect != null
		or definition.visual_kind != TileDefinitionScript.VisualKind.NONE
		or definition.get_element_model_asset() != null
	)


static func _legacy_base_permissions(tile: Resource, has_stuff: bool) -> Dictionary:
	if has_stuff:
		return {"tile": true, "edge": true}
	var definition: TileDefinitionScript = tile.definition as TileDefinitionScript
	if tile.obstacle_destroyed and definition != null and definition.effect != null:
		return {
			"tile": definition.effect.allows_tile_building_after_destroyed(),
			"edge": definition.effect.allows_edge_building_after_destroyed(),
		}
	if definition != null:
		if definition.surface_kind == TileDefinitionScript.SurfaceKind.ROAD:
			return {"tile": false, "edge": definition.allows_edge_building}
		return {
			"tile": definition.allows_tile_building,
			"edge": definition.allows_edge_building,
		}
	return {
		"tile": tile.tile_type != TileCellDataScript.TileType.BLOCKED,
		"edge": true,
	}


static func _resolve_legacy_stuff_definition(
	tile: Resource,
	cache: Dictionary
) -> StuffDefinitionScript:
	var definition: TileDefinitionScript = tile.definition as TileDefinitionScript
	var cache_key: Variant = definition.get_instance_id() if definition != null else &"legacy_destructible"
	if cache.has(cache_key):
		return cache[cache_key]
	var stuff := StuffDefinitionScript.new()
	if definition == null:
		stuff.stuff_id = &"legacy_destructible"
		stuff.display_name = "可破坏障碍"
		stuff.fallback_visual_kind = StuffDefinitionScript.FallbackVisualKind.GENERIC_OBSTACLE
		stuff.fallback_color = Color(0.45, 0.48, 0.48, 1.0)
	else:
		stuff.stuff_id = definition.tile_id
		stuff.display_name = definition.display_name
		stuff.inspection_display = definition.inspection_display
		stuff.blocks_tile_building = not definition.allows_tile_building
		stuff.blocks_edge_building = not definition.allows_edge_building
		stuff.effect = definition.effect
		stuff.ui_icon = definition.ui_icon
		stuff.fallback_visual_kind = _convert_legacy_visual_kind(definition)
		stuff.fallback_color = definition.visual_color
		stuff.model_asset = definition.get_element_model_asset()
	cache[cache_key] = stuff
	return stuff


static func _convert_legacy_visual_kind(definition: Resource) -> int:
	match int(definition.visual_kind):
		TileDefinitionScript.VisualKind.SPIKES:
			return StuffDefinitionScript.FallbackVisualKind.SPIKES
		TileDefinitionScript.VisualKind.HOLE:
			return StuffDefinitionScript.FallbackVisualKind.HOLE
		TileDefinitionScript.VisualKind.ROCK:
			return StuffDefinitionScript.FallbackVisualKind.ROCK
	if int(definition.surface_kind) == TileDefinitionScript.SurfaceKind.DESTRUCTIBLE:
		return StuffDefinitionScript.FallbackVisualKind.GENERIC_OBSTACLE
	return StuffDefinitionScript.FallbackVisualKind.NONE


static func _make_legacy_placement_id(
	tile: Resource,
	definition: StuffDefinitionScript
) -> StringName:
	return StringName("legacy_%s_%d_%d_%d" % [
		String(definition.stuff_id),
		tile.cell.x,
		tile.cell.y,
		tile.cell.z,
	])


static func _not_empty_array(value: Variant) -> bool:
	return value is Array and not value.is_empty()


static func _as_array(value: Variant) -> Array:
	return value if value is Array else []


static func _empty_snapshot() -> Dictionary:
	var grid_cells: Array[GridCellDataScript] = []
	var ramp_placements: Array[RampPlacementDataScript] = []
	var stuff_placements: Array[StuffPlacementDataScript] = []
	return {
		"content_version": CANONICAL_CONTENT_VERSION,
		"migrated": false,
		"default_terrain": null,
		"layer_height": 0.0,
		"grid_cells": grid_cells,
		"ramp_placements": ramp_placements,
		"stuff_placements": stuff_placements,
	}
