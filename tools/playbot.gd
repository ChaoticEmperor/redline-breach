extends SceneTree
## Play-test bot: plays the real main scene through `controls.override`, logs what happens and saves
## screenshots: a before/after measure for gameplay changes (see the gameplay-craft skill).
## Needs a display (`xvfb-run -a` in the cloud):
##   godot --path . -s tools/playbot.gd -- <out dir> [max seconds]
## Writes <out dir>/playbot_log.txt (kills, deaths and their causes, floor clears) and PNGs.

const Enemy = preload("res://scripts/enemy.gd")

var main
var c
var out := ""
var max_frames := 60 * 150
var frame := 0
var shot_every := 60 * 4
var last_pos := Vector2.ZERO
var stuck_t := 0
var log_lines: PackedStringArray = []
var last_state := ""
var last_kills := 0
var floors_cleared := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://playbot"
	if args.size() > 1:
		max_frames = int(args[1]) * 60
	DirAccess.make_dir_recursive_absolute(out)
	seed(1989)
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	c = main.controls
	c.override = true
	c.touch_mode = false
	_log("start seed=%d enemies=%d pickups=%d" % [main.floor_seed, main.world.enemy_list.size(), main.world.pickups.size()])
	_loop()


func _log(s: String) -> void:
	var line := "[%6.1fs] %s" % [frame / 60.0, s]
	print("playbot: " + line)
	log_lines.append(line)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _nearest_enemy(p: Vector2):
	var best = null
	var bd := 1e9
	for e in main.world.enemy_list:
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_pickup(p: Vector2):
	var best = null
	var bd := 1e9
	for k in main.world.pickups:
		var d: float = k.pos.distance_to(p)
		if d < bd:
			bd = d
			best = k
	return best


## A bloater whose fuse is burning, close enough for its blast to matter.
func _lit_bloater(p: Vector2):
	for e in main.world.enemy_list:
		if e.kind == "bloater" and e.state == Enemy.FUSE and e.global_position.distance_to(p) < Enemy.BLAST + 24.0:
			return e
	return null


func _near_door(p: Vector2):
	for d in main.world.doors:
		if not d.open and not d.locked and d.center.distance_to(p) < 22.0:
			return d
	return null


func _go(p: Vector2, to: Vector2) -> void:
	var route: PackedVector2Array = main.world.path(p, to)
	if route.is_empty() and frame % 60 == 0:
		var w = main.world
		var a: Vector2i = w.cell_of(p)
		var b: Vector2i = w.cell_of(to)
		_log("NO ROUTE %s(code %c, solid %s) -> %s(code %c, solid %s)" % [a, w.code_at(a), w.astar.is_point_solid(a), b, w.code_at(b), w.astar.is_point_solid(b)])
	var next := to
	for pt in route:
		if pt.distance_to(p) > 6.0:
			next = pt
			break
	c.move = (next - p).normalized()


func _loop() -> void:
	var shots := 0
	while frame < max_frames:
		await physics_frame
		frame += 1
		var player = main.player
		var w = main.world
		if main.state != last_state:
			_log("state -> %s %s score=%d kills=%d" % [main.state, main.cause, main.score, main.kills])
			last_state = main.state
			if main.state != "play":
				await _shot("%03d_%s" % [shots, main.state])
				shots += 1
		if main.kills != last_kills:
			_log("kill #%d score=%d combo=%d weapon=%s ammo=%s" % [main.kills, main.score, main.combo, player.weapon, player.ammo])
			last_kills = main.kills
		if frame % shot_every == 0:
			await _shot("%03d_play" % shots)
			shots += 1
		if main.state == "dead":
			c.move = Vector2.ZERO
			c.fire = false
			if main.state_t > 1.0:
				c.press("any")
			continue
		if main.state == "clear":
			floors_cleared += 1
			_log("FLOOR CLEARED in %.1fs" % main.floor_time)
			c.move = Vector2.ZERO
			if floors_cleared >= 2:
				break
			for i in 60:
				await physics_frame
				frame += 1
			c.press("any")
			continue

		var p: Vector2 = player.global_position
		c.fire = false
		c.aim = Vector2.ZERO
		if player.grab_t > 0.0:
			var g = _nearest_enemy(p)
			if g != null:
				c.aim = (g.global_position - p).normalized()
			c.press("kick")
		# Prefer a gun once one is owned and loaded.
		if player.weapon == "pipe" and (player.ammo.pistol > 0 or player.ammo.shotgun > 0) and frame % 20 == 0:
			c.press("swap")

		var e = _nearest_enemy(p)
		var ed: float = e.global_position.distance_to(p) if e != null else 1e9
		var see: bool = e != null and w.los(p, e.global_position)
		var bomb = _lit_bloater(p)
		var bloater: bool = e != null and e.kind == "bloater"
		if bomb != null:
			# A lit fuse in range: get out of the blast, dash if it is close.
			c.move = (p - bomb.global_position).normalized()
			if p.distance_to(bomb.global_position) < Enemy.BLAST:
				c.aim = c.move
				c.press("dash")
		elif bloater and see and player.weapon != "pipe" and ed < 150.0:
			# Shoot it from beyond the blast; back off if it gets near.
			c.aim = (e.global_position - p).normalized()
			c.fire = true
			c.move = -c.aim if ed < Enemy.BLAST + 16.0 else Vector2.ZERO
		elif bloater and ed < 30.0:
			# Pipe only: swing, then step back out of touching range.
			c.aim = (e.global_position - p).normalized()
			c.fire = ed < 24.0
			c.move = -c.aim
		elif e != null and e.state == Enemy.DOWN and ed < 22.0:
			c.press("kick") # EXEC
			_go(p, e.global_position)
		elif e != null and see and ed < (24.0 if player.weapon == "pipe" else 150.0):
			c.aim = (e.global_position - p).normalized()
			c.fire = true
			c.move = Vector2.ZERO if player.weapon != "pipe" else c.aim * 0.4
		elif e != null and see and ed < 70.0:
			_go(p, e.global_position)
		elif not w.pickups.is_empty() and (e == null or ed > 70.0):
			_go(p, _nearest_pickup(p).pos)
		elif e != null:
			_go(p, e.global_position)
		elif w.exit_open:
			_go(p, w.exit_rect.get_center())
		# A closed door in reach: kicks go along the aim, so aim at the door first.
		var door = _near_door(p)
		if door != null and not c.fire:
			c.aim = (door.center - p).normalized()
			if player.kick_cd <= 0.0:
				c.press("kick")
				_log("kick door at %s" % door.center)
		# Stuck on a prop or a locked door: dash along the move, then nudge sideways.
		if p.distance_to(last_pos) < 0.2 and c.move != Vector2.ZERO:
			stuck_t += 1
			if stuck_t > 45:
				c.aim = c.move
				c.press("dash")
				c.move = c.move.orthogonal()
				if stuck_t > 90:
					_log("stuck at %s" % p)
					stuck_t = 0
		else:
			stuck_t = 0
		last_pos = p
	_log("end: state=%s score=%d kills=%d deaths=%d floors_cleared=%d enemies_left=%d" % [main.state, main.score, main.kills, main.deaths, floors_cleared, main.world.enemy_list.size()])
	await _shot("%03d_end" % shots)
	var f := FileAccess.open(out.path_join("playbot_log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	quit(0)
