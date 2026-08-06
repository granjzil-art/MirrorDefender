## Physical edge mirror that reflects friendly tower projectiles.
class_name ReflectMirror
extends CopyMirror


func is_copy_mirror() -> bool:
	return false


func is_projectile_reflector() -> bool:
	return true
