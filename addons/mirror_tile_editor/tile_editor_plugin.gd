@tool
extends EditorPlugin

const TileEditorPanel := preload("res://addons/mirror_tile_editor/tile_editor_panel.gd")

var _panel: Control

func _enter_tree() -> void:
	_panel = TileEditorPanel.new()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)

func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible

func _get_plugin_name() -> String:
	return "关卡编辑器"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")
