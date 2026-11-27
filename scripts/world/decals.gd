extends Node2D
## Persistent blood on the floor, under every actor and body. Drawn as hard-edged blobs in three
## reds (no alpha), splattered along the blow; a pool spreads under a settled body.

const REDS := [Color("5a0810"), Color("8a1018"), Color("b8141e")]
const MAX := 600

var blobs: Array = [] # [pos, radius, colour index]


func _ready() -> void:
	z_index = 0


func splat(at: Vector2, dir: Vector2, size: float, rng: RandomNumberGenerator) -> void:
	for i in int(10 * size):
		var along := rng.randf_range(0.0, 26.0 * size)
		var p := at + dir * along + dir.orthogonal() * rng.randf_range(-6, 6) * size
		blobs.append([p.floor(), rng.randf_range(1.0, 4.0) * size, rng.randi_range(0, 2)])
	if blobs.size() > MAX:
		blobs = blobs.slice(blobs.size() - MAX)
	queue_redraw()


func _draw() -> void:
	for b in blobs:
		draw_circle(b[0], b[1], REDS[b[2]])
