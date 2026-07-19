## Interface for swappable instant, continuous, and future attack behaviors.
class_name IAttackStrategy
extends RefCounted

func tick(_attacker: Node, _delta: float) -> void:
	push_error("IAttackStrategy.tick() 未实现")

func reset(_attacker: Node) -> void:
	return
