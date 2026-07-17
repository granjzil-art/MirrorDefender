@tool
extends Button

const DRAG_KIND := "mirror_tile_preset"

var preset_path: String = ""

func configure(display_name: String, path: String, group: ButtonGroup) -> void:
	text = display_name
	preset_path = path
	toggle_mode = true
	button_group = group
	tooltip_text = path
	custom_minimum_size = Vector2(0.0, 34.0)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = text
	preview.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	preview.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	preview.add_theme_constant_override("outline_size", 3)
	set_drag_preview(preview)
	return {
		"kind": DRAG_KIND,
		"preset_path": preset_path,
	}
