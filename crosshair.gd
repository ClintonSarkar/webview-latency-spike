extends Node2D

# Marks where Godot saw each pointer this frame (~1 frame behind the finger).
# The on-screen gap between a ring and the page's puck during a drag is the
# webview pipeline's added latency, directly visible and screen-recordable.

# finger id -> {pos: Vector2, down: bool}; mouse uses id -1 and keeps its hover point
var fingers: Dictionary = {}

func set_finger(id: int, p: Vector2, down: bool) -> void:
	if !down && id >= 0:
		fingers.erase(id)
	else:
		fingers[id] = {"pos": p, "down": down}
	queue_redraw()

func down_count() -> int:
	var n = 0
	for id in fingers:
		if id >= 0 && fingers[id].down:
			n += 1
	return n

func clear_touches() -> void:
	for id in fingers.keys():
		if id >= 0:
			fingers.erase(id)
	queue_redraw()

func _draw() -> void:
	for id in fingers:
		var f = fingers[id]
		var color = Color(1, 0.25, 0.25, 0.9) if f.down else Color(0.25, 1, 0.25, 0.7)
		draw_arc(f.pos, 18.0, 0.0, TAU, 32, color, 3.0)
		draw_circle(f.pos, 3.0, color)
