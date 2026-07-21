## Shared, side-effect-free helpers for validating editable configuration.
class_name ConfigurationValidator
extends RefCounted


static func require_text(errors: Array[String], label: String, value: String) -> void:
	if value.strip_edges().is_empty():
		errors.append("%s不能为空" % label)


static func require_number(
	errors: Array[String],
	label: String,
	value: float,
	minimum: float,
	maximum: float = INF,
	minimum_inclusive: bool = true,
	maximum_inclusive: bool = true
) -> void:
	if not is_finite(value):
		errors.append("%s必须为有限数" % label)
		return
	var below_minimum := value < minimum if minimum_inclusive else value <= minimum
	var above_maximum := value > maximum if maximum_inclusive else value >= maximum
	if below_minimum or above_maximum:
		var minimum_operator := "≥" if minimum_inclusive else ">"
		if is_inf(maximum):
			errors.append("%s必须%s%s" % [label, minimum_operator, str(minimum)])
			return
		var maximum_operator := "≤" if maximum_inclusive else "<"
		errors.append("%s必须%s%s 且%s%s" % [
			label,
			minimum_operator,
			str(minimum),
			maximum_operator,
			str(maximum),
		])


static func require_integer_range(
	errors: Array[String],
	label: String,
	value: int,
	minimum: int,
	maximum: int
) -> void:
	if value < minimum or value > maximum:
		errors.append("%s必须在 %d..%d 范围内" % [label, minimum, maximum])


static func require_color(errors: Array[String], label: String, value: Color) -> void:
	if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a):
		errors.append("%s的 RGBA 分量必须为有限数" % label)


static func append_prefixed(
	errors: Array[String],
	prefix: String,
	nested_errors: Array[String]
) -> void:
	for error in nested_errors:
		errors.append("%s：%s" % [prefix, error])
