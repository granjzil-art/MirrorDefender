@tool
## Shared presentation policy for one runtime-inspector object type.
class_name InspectionDisplayConfig
extends Resource

const PRIMARY_LABEL_COLOR := "#66d17a"
const SECONDARY_LABEL_COLOR := "#ffd34e"
const TERTIARY_LABEL_COLOR := "#ff6666"
const DESCRIPTION_BBCODE_COLOR := "#f0f5ff"
const MARKUP_BOLD := "b"
const MARKUP_COLOR := "color"
const MARKUP_HIGHLIGHT := "highlight"
const HEX_DIGITS := "0123456789abcdefABCDEF"

@export_group("Object")
## First-level switch. Disabled objects are omitted from the inspector list.
@export var visible: bool = true
## Empty text keeps the object's existing runtime display name.
@export var display_name: String = ""
## Empty text uses the built-in description for legacy resources. Authored text
## accepts [color=#RRGGBB], [highlight=#RRGGBB] and [b] paired tags.
@export_multiline var function_description: String = ""

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
	return _format_authored_plain(_resolve_function_description_source(fallback))


func format_semantic_description(
	fallback: String,
	headings: PackedStringArray,
	descriptions: PackedStringArray
) -> String:
	var sources := _build_semantic_sources(fallback, descriptions)
	var lines: Array[String] = []
	var line_count := mini(headings.size(), sources.size())
	for index in range(line_count):
		lines.append("%s： %s" % [headings[index], _format_authored_plain(sources[index])])
	return "\n".join(lines)


## Rich-text variant used by card hover and selected-object information pages.
## Authored color, background highlight and bold tags may override the default
## white body style; every other BBCode-looking tag stays visible as text.
func format_semantic_description_bbcode(
	fallback: String,
	headings: PackedStringArray,
	descriptions: PackedStringArray
) -> String:
	var sources := _build_semantic_sources(fallback, descriptions)
	var lines: Array[String] = []
	var line_count := mini(headings.size(), sources.size())
	for index in range(line_count):
		lines.append("%s %s" % [
			_format_semantic_heading_bbcode(headings[index], index),
			_as_white_bbcode(sources[index]),
		])
	return "\n".join(lines)


func _build_semantic_sources(fallback: String, descriptions: PackedStringArray) -> PackedStringArray:
	var sources := PackedStringArray([_resolve_function_description_source(fallback)])
	for description in descriptions:
		sources.append(description.strip_edges())
	return sources


func _format_semantic_heading_bbcode(heading: String, index: int) -> String:
	var color := PRIMARY_LABEL_COLOR
	if index == 1:
		color = SECONDARY_LABEL_COLOR
	elif index >= 2:
		color = TERTIARY_LABEL_COLOR
	return "[color=%s][b]%s：[/b][/color]" % [color, _literal_markup(heading, true)]


func _as_white_bbcode(value: String) -> String:
	return "[color=%s]%s[/color]" % [DESCRIPTION_BBCODE_COLOR, _format_authored_bbcode(value)]


func _resolve_function_description_source(fallback: String) -> String:
	var configured := function_description.strip_edges()
	return configured if not configured.is_empty() else fallback


func _format_authored_plain(value: String) -> String:
	return _convert_authored_markup(value, false)


func _format_authored_bbcode(value: String) -> String:
	return _convert_authored_markup(value, true)


func _convert_authored_markup(value: String, rich_text: bool) -> String:
	var output := ""
	var open_tags: Array[String] = []
	var cursor := 0
	while cursor < value.length():
		var opening_bracket := value.find("[", cursor)
		if opening_bracket < 0:
			output += value.substr(cursor)
			break
		output += value.substr(cursor, opening_bracket - cursor)
		var closing_bracket := value.find("]", opening_bracket + 1)
		if closing_bracket < 0:
			output += _literal_markup(value.substr(opening_bracket), rich_text)
			break
		var token := value.substr(opening_bracket, closing_bracket - opening_bracket + 1)
		var opening_tag := _parse_opening_tag(token)
		if not opening_tag.is_empty():
			open_tags.append(String(opening_tag.name))
			if rich_text:
				output += String(opening_tag.bbcode)
		else:
			var closing_name := _parse_closing_tag(token)
			if not closing_name.is_empty() and not open_tags.is_empty() and open_tags.back() == closing_name:
				open_tags.pop_back()
				if rich_text:
					output += _closing_bbcode(closing_name)
			else:
				output += _literal_markup(token, rich_text)
		cursor = closing_bracket + 1
	if rich_text:
		while not open_tags.is_empty():
			output += _closing_bbcode(open_tags.pop_back())
	return output


func _parse_opening_tag(token: String) -> Dictionary:
	if token == "[b]":
		return {"name": MARKUP_BOLD, "bbcode": "[b]"}
	var color := _extract_hex_color(token, "[color=")
	if not color.is_empty():
		return {"name": MARKUP_COLOR, "bbcode": "[color=%s]" % color}
	color = _extract_hex_color(token, "[highlight=")
	if not color.is_empty():
		return {"name": MARKUP_HIGHLIGHT, "bbcode": "[bgcolor=%s]" % color}
	return {}


func _parse_closing_tag(token: String) -> String:
	match token:
		"[/b]":
			return MARKUP_BOLD
		"[/color]":
			return MARKUP_COLOR
		"[/highlight]":
			return MARKUP_HIGHLIGHT
	return ""


func _extract_hex_color(token: String, prefix: String) -> String:
	if not token.begins_with(prefix) or not token.ends_with("]"):
		return ""
	var value := token.substr(prefix.length(), token.length() - prefix.length() - 1)
	if value.length() != 7 and value.length() != 9:
		return ""
	if not value.begins_with("#"):
		return ""
	for index in range(1, value.length()):
		if not HEX_DIGITS.contains(value.substr(index, 1)):
			return ""
	return value


func _closing_bbcode(markup_name: String) -> String:
	if markup_name == MARKUP_HIGHLIGHT:
		return "[/bgcolor]"
	return "[/%s]" % markup_name


func _literal_markup(value: String, rich_text: bool) -> String:
	return value.replace("[", "[lb]") if rich_text else value
