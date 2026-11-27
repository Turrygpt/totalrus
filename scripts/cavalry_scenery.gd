extends "res://scripts/terrain.gd"

func _ready() -> void:
	rng.seed = 4319
	make_rocks()
	make_trees()
