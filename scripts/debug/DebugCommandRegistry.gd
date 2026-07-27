## Extensible command parser and dispatcher for the runtime debug console.
class_name DebugCommandRegistry
extends RefCounted

signal command_executed(input: String, result: Dictionary)

var _commands: Dictionary = {}
var _command_order: Array[StringName] = []


func _init() -> void:
	register_command(&"help", "help [command]", "列出命令或查看单个命令帮助", Callable(self, "_run_help"))
	register_command(&"clear", "clear", "清空控制台历史", Callable(self, "_run_clear"))


func register_command(
	command_name: StringName,
	usage: String,
	description: String,
	handler: Callable
) -> bool:
	var normalized := StringName(String(command_name).strip_edges().to_lower())
	if normalized.is_empty() or not handler.is_valid():
		return false
	if not _commands.has(normalized):
		_command_order.append(normalized)
	_commands[normalized] = {
		"name": normalized,
		"usage": usage.strip_edges(),
		"description": description.strip_edges(),
		"handler": handler,
	}
	return true


func execute(input: String) -> Dictionary:
	var token_result := _tokenize(input)
	if not bool(token_result.get("success", false)):
		var token_error := _result(false, str(token_result.get("message", "命令解析失败")))
		command_executed.emit(input, token_error)
		return token_error
	var tokens: Array[String] = token_result.get("tokens", [])
	if tokens.is_empty():
		var empty_result := _result(false, "请输入命令；使用 help 查看列表")
		command_executed.emit(input, empty_result)
		return empty_result
	var command_name := StringName(tokens[0].to_lower())
	if not _commands.has(command_name):
		var unknown_result := _result(false, "未知命令：%s；使用 help 查看列表" % tokens[0])
		command_executed.emit(input, unknown_result)
		return unknown_result
	var entry: Dictionary = _commands[command_name]
	var handler: Callable = entry.get("handler", Callable())
	var arguments: Array[String] = []
	for index in range(1, tokens.size()):
		arguments.append(tokens[index])
	var raw_result: Variant = handler.call(arguments)
	var result := _normalize_result(raw_result)
	command_executed.emit(input, result)
	return result


func list_commands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for command_name in _command_order:
		if _commands.has(command_name):
			result.append((_commands[command_name] as Dictionary).duplicate())
	return result


func _run_help(arguments: Array[String]) -> Dictionary:
	if arguments.size() > 1:
		return _result(false, "用法：help [command]")
	if arguments.size() == 1:
		var command_name := StringName(arguments[0].to_lower())
		if not _commands.has(command_name):
			return _result(false, "未知命令：%s" % arguments[0])
		var entry: Dictionary = _commands[command_name]
		return _result(true, "%s\n%s" % [str(entry.get("usage", "")), str(entry.get("description", ""))])
	var lines: Array[String] = ["可用命令："]
	for entry in list_commands():
		lines.append("  %-32s %s" % [str(entry.get("usage", "")), str(entry.get("description", ""))])
	return _result(true, "\n".join(lines))


func _run_clear(arguments: Array[String]) -> Dictionary:
	if not arguments.is_empty():
		return _result(false, "用法：clear")
	var result := _result(true, "")
	result["clear"] = true
	return result


func _normalize_result(raw_result: Variant) -> Dictionary:
	if raw_result is Dictionary:
		var result: Dictionary = (raw_result as Dictionary).duplicate()
		if not result.has("success"):
			result["success"] = true
		if not result.has("message"):
			result["message"] = ""
		if not result.has("clear"):
			result["clear"] = false
		return result
	if raw_result is bool:
		return _result(bool(raw_result), "完成" if bool(raw_result) else "命令执行失败")
	return _result(true, str(raw_result))


func _tokenize(input: String) -> Dictionary:
	var tokens: Array[String] = []
	var current := ""
	var quote := ""
	var escaping := false
	for index in range(input.length()):
		var character := input.substr(index, 1)
		if escaping:
			current += character
			escaping = false
			continue
		if character == "\\":
			escaping = true
			continue
		if not quote.is_empty():
			if character == quote:
				quote = ""
			else:
				current += character
			continue
		if character == "\"" or character == "'":
			quote = character
			continue
		if character == " " or character == "\t":
			if not current.is_empty():
				tokens.append(current)
				current = ""
			continue
		current += character
	if escaping:
		current += "\\"
	if not quote.is_empty():
		return {"success": false, "message": "引号未闭合", "tokens": []}
	if not current.is_empty():
		tokens.append(current)
	return {"success": true, "message": "", "tokens": tokens}


func _result(success: bool, message: String) -> Dictionary:
	return {
		"success": success,
		"message": message,
		"clear": false,
	}
