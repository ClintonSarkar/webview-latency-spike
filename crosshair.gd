extends Node2D

# Marks where Godot saw the pointer this frame (~1 frame behind the finger).
# The on-screen gap between this ring and the page's puck during a drag is the
# webview pipeline's added latency, directly visible and screen-recordable.

var point: Vector2 = Vector2(-100, -100)
var pressed: bool = false

func set_point(p: Vector2, down: bool) -> void:
	point = p
	pressed = down
	queue_redraw()

func _draw() -> void:
	var color = Color(1, 0.25, 0.25, 0.9) if pressed else Color(0.25, 1, 0.25, 0.7)
	draw_arc(point, 18.0, 0.0, TAU, 32, color, 3.0)
	draw_circle(point, 3.0, color)
