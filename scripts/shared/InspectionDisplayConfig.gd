@tool
## Shared presentation policy for one runtime-inspector object type.
class_name InspectionDisplayConfig
extends Resource

@export_group("Object")
## First-level switch. Disabled objects are omitted from the inspector list.
@export var visible: bool = true
## Empty text keeps the object's existing runtime display name.
@export var display_name: String = ""
## Empty text uses the built-in description for legacy resources.
@export_multiline var function_description: String = ""

@export_group("Building Level Descriptions")
## Optional per-level copy appended after the shared base description.
@export_multiline var level_1_description: String = ""
@export_multiline var level_2_description: String = ""
@export_multiline var level_3_description: String = ""

@export_group("Header Fields")
@export var show_icon: bool = true
@export var show_category: bool = true
@export var show_entity_state: bool = true
@export var show_function_description: bool = true

@export_group("Common Detail Fields")
@export var show_position: bool = true
@export var show_height: bool = true
@export var show_build_permissions: bool = true
@export var show_level: bool = true
@export var show_durability: bool = true
@export var show_orientation: bool = true
@export var show_airborne_effect: bool = true

@export_group("Gameplay Detail Fields")
@export var show_combat: bool = true
@export var show_economy: bool = true
@export var show_capacity: bool = true
@export var show_timing: bool = true

@export_group("Projection Detail Fields")
@export var show_projection_source: bool = true
@export var show_producing_mirror: bool = true
@export var show_copy_chain: bool = true


func resolve_display_name(fallback: String) -> String:
	var configured := display_name.strip_edges()
	return configured if not configured.is_empty() else fallback


func resolve_function_description(fallback: String) -> String:
	var configured := function_description.strip_edges()
	return configured if not configured.is_empty() else fallback


func format_building_description(fallback: String) -> String:
	return "\n".join([
		"基础描述",
		resolve_function_description(fallback),
		"",
		"1级：",
		level_1_description.strip_edges(),
		"",
		"2级：",
		level_2_description.strip_edges(),
		"",
		"3级：",
		level_3_description.strip_edges(),
	])
