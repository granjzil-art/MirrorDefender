## A combat target that advances along a fixed M4 path and damages BaseCore at its end.
class_name EnemyUnit
extends CombatTarget

signal reached_base(unit: EnemyUnit, damage_to_base: float)

var definition: EnemyDefinition
var armor: float = 0.0
var damage_to_base: float = 10.0
var _path_points := PackedVector3Array()
var _path_index: int = 0
var _reached_base: bool = false

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if not feature_enabled or not is_alive() or _reached_base or _path_points.size() < 2:
		return
	var remaining_distance := move_speed * delta
	while remaining_distance > 0.0 and _path_index < _path_points.size() - 1:
		var destination := _path_points[_path_index + 1]
		var to_destination := destination - global_position
		var distance_to_destination := to_destination.length()
		if distance_to_destination <= 0.0001:
			_path_index += 1
			continue
		if distance_to_destination <= remaining_distance:
			global_position = destination
			remaining_distance -= distance_to_destination
			_path_index += 1
		else:
			var direction := to_destination / distance_to_destination
			global_position += direction * remaining_distance
			look_at(global_position + Vector3(direction.x, 0.0, direction.z), Vector3.UP)
			remaining_distance = 0.0
	if _path_index >= _path_points.size() - 1:
		_reach_base()

func configure_unit(enemy_definition: EnemyDefinition, path_points: PackedVector3Array) -> void:
	definition = enemy_definition
	_path_points = path_points
	_path_index = 0
	_reached_base = false
	if definition != null:
		max_hp = maxf(1.0, definition.max_hp)
		current_hp = max_hp
		move_speed = maxf(0.1, definition.move_speed)
		armor = maxf(0.0, definition.armor)
		damage_to_base = maxf(1.0, definition.base_damage)
		reward = maxf(0.0, definition.reward)
		hit_radius = definition.hit_radius
		debug_color = definition.body_color
		debug_height = definition.body_height
	if not _path_points.is_empty():
		# WaveManager configures the unit before add_child() so _ready() can build
		# visuals from the definition. Path points share the Main-local space.
		position = _path_points[0]

func take_damage(amount: float) -> float:
	return super.take_damage(maxf(0.0, amount - armor))

func _reach_base() -> void:
	if _reached_base:
		return
	_reached_base = true
	feature_enabled = false
	reached_base.emit(self, damage_to_base)
	queue_free()
