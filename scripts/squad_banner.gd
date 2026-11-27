extends Control

const WORLD_STANDARD := preload("res://scripts/squad_standard.gd")
const HERALDRY := {
	"princely": preload("res://assets/banners/novgorod.svg"),
	"varangian": preload("res://assets/banners/varangians.svg"),
	"khazar": preload("res://assets/banners/khazars.svg"),
	"militia": preload("res://assets/banners/militia.svg"),
	"infantry": preload("res://assets/banners/spearmen.svg"),
	"archer": preload("res://assets/banners/archers.svg"),
	"cavalry": preload("res://assets/banners/cavalry.svg"),
	"light_cavalry": preload("res://assets/banners/light_cavalry.svg"),
}
var squad: Node3D
var world_standard: Node3D
var stats_timer := 0.0
var experience_rank := -1

func _ready() -> void:
	hide()
	world_standard = WORLD_STANDARD.new()
	world_standard.name = "SquadStandard"
	squad.add_child(world_standard)
	var standard: Texture2D = squad.faction_standard if squad.faction_standard else HERALDRY[squad.unit_kind]
	world_standard.configure(standard, squad.uniform_color)
	world_standard.follow(squad)
	refresh_stats()

func _process(delta: float) -> void:
	stats_timer -= delta
	if stats_timer > 0: return
	stats_timer = .25
	refresh_stats()

func refresh_stats() -> void:
	var rank: int = squad.experience_rank
	if rank != experience_rank:
		experience_rank = rank
		world_standard.fabric_material.set_shader_parameter("experience_rank", rank)
	var signal_level := 0
	if squad.surrendered:
		signal_level = 3
	elif squad.routed:
		signal_level = 2
	elif squad.berserk_remaining <= 0 and squad.morale < squad.WAVER_THRESHOLD:
		signal_level = 1
	world_standard.show_morale(signal_level)
