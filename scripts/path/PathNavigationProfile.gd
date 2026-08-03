## Lightweight target adapter used to precompute target-dependent path routes.
class_name PathNavigationProfile
extends Node

var airborne: bool = false


func configure(is_airborne: bool) -> void:
	airborne = is_airborne


func is_airborne_unit() -> bool:
	return airborne
