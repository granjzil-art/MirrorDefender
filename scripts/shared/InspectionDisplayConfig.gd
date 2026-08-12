@tool
## Shared presentation policy for one runtime-inspector object type.
class_name InspectionDisplayConfig
extends Resource

const LEVEL_1_LABEL_BBCODE := "[color=#66d17a][b]1级：[/b][/color]"
const LEVEL_2_LABEL_BBCODE := "[color=#ffd34e][b]2级：[/b][/color]"
const LEVEL_3_LABEL_BBCODE := "[color=#ff6666][b]3级：[/b][/color]"
const DESCRIPTION_BBCODE_COLOR := "#f0f5ff"

@export_group("Object")
## First-level switch. Disabled objects are omitted from the inspector list.
@export var visible: bool = true
## Empty text keeps the object's existing runtime display name.
@export var display_name: String = ""
## Empty text uses the built-in description for legacy resources.
@export_multiline var function_description: String = ""

@export_group("Level Descriptions")
## Optional per-level copy appended after the shared base description.
## Buildings and mirrors share these fields and the same formatted layout.
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


func format_level_description(fallback: String) -> String:
	return "\n".join([
		resolve_function_description(fallback),
		"1级： %s" % level_1_description.strip_edges(),
		"2级： %s" % level_2_description.strip_edges(),
		"3级： %s" % level_3_description.strip_edges(),
	])


## Rich-text variant used by card hover and selected-object information pages.
## Only the level label is colored; all authored descriptions remain white.
func format_level_description_bbcode(fallback: String) -> String:
	return "\n".join([
		_as_white_bbcode(resolve_function_description(fallback)),
		"%s %s" % [LEVEL_1_LABEL_BBCODE, _as_white_bbcode(level_1_description.strip_edges())],
		"%s %s" % [LEVEL_2_LABEL_BBCODE, _as_white_bbcode(level_2_description.strip_edges())],
		"%s %s" % [LEVEL_3_LABEL_BBCODE, _as_white_bbcode(level_3_description.strip_edges())],
	])


func _as_white_bbcode(value: String) -> String:
	return "[color=%s]%s[/color]" % [DESCRIPTION_BBCODE_COLOR, _escape_bbcode(value)]


func _escape_bbcode(value: String) -> String:
	# RichTextLabel recognizes a tag only after an opening bracket. Replacing
	# that character preserves author text without allowing it to alter layout.
	return value.replace("[", "[lb]")


## Compatibility entry retained for existing building callers.
func format_building_description(fallback: String) -> String:
	return format_level_description(fallback)


func format_building_description_bbcode(fallback: String) -> String:
	return format_level_description_bbcode(fallback)
