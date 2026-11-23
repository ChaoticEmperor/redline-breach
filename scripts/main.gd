extends Node2D
## Run lifecycle: builds a floor from a seed, tracks score/combo, and handles
## death -> instant restart (same seed) and clear -> next floor (seed + 1).

const Layout = preload("res://scripts/layout.gd")
const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Fx = preload("res://scripts/fx.gd")
const Controls = preload("res://scripts/controls.gd")
const Hud = preload("res://scripts/hud.gd")

const COMBO_TIME := 2.5

var floor_seed := 1989
var world
var player
var controls
var hud
var state := "play" # play | dead | clear
var cause := ""
var score := 0
var combo := 0
var combo_t := 0.0
var kills := 0
var shots := 0
var deaths := 0
var floor_time := 0.0
var state_t := 0.0
var restart_usec := 0 # how long the last floor (re)build took


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("0a0612"))
	Fx.warm()
	controls = Controls.new()
	add_child(controls)
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	var music := AudioStreamPlayer.new()
	music.stream = Fx.music()
	music.volume_db = -16.0
	add_child(music)
	music.play()
	start_floor()


func start_floor() -> void:
	var t0 := Time.get_ticks_usec()
	if world != null:
		remove_child(world)
		world.queue_free()
	var layout := Layout.generate(floor_seed)
	world = World.new()
	world.main = self
	add_child(world)
	move_child(world, 0)
	world.build(layout)
	player = Player.new()
	player.setup(self, world, controls)
	player.position = world.center(layout.start)
	world.add_child(player)
	for z in layout.zombies:
		var e := Enemy.new()
		e.setup(self, world, player, z.kind)
		e.position = world.center(z.cell)
		world.add_child(e)
	world.move_child(world.fx, -1)
	controls.player = player
	controls.clear()
	state = "play"
	cause = ""
	score = 0
	combo = 0
	combo_t = 0.0
	kills = 0
	shots = 0
	floor_time = 0.0
	restart_usec = Time.get_ticks_usec() - t0


func _process(delta: float) -> void:
	state_t += delta
	combo_t = maxf(0.0, combo_t - delta)
	if state == "play":
		floor_time += delta
		if controls.take("restart"):
			start_floor()
	elif state == "dead":
		var again: bool = controls.take("any")
		if again or controls.take("restart"):
			start_floor()
	elif state == "clear" and state_t > 0.6 and controls.take("any"):
		floor_seed += 1
		deaths = 0
		start_floor()


func on_kill(e, executed: bool) -> void:
	kills += 1
	combo = combo + 1 if combo_t > 0.0 else 1
	combo_t = COMBO_TIME
	var pts: int = e.STATS[e.kind].score * combo * (2 if executed else 1)
	score += pts
	world.fx.popup(e.global_position + Vector2(0, -10), "+%d" % pts, Fx.CYAN if not executed else Color("f9f002"))
	if world.enemy_list.is_empty():
		world.open_exit()


func player_died(why: String) -> void:
	state = "dead"
	state_t = 0.0
	cause = why
	deaths += 1
	controls.clear()


func floor_cleared() -> void:
	if state != "play":
		return
	state = "clear"
	state_t = 0.0
	controls.clear()
	world.fx.play("clear", 1.5)
