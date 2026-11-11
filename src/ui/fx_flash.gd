class_name FxFlash
extends Node2D
## A flat, hard-edged disc for battle effects: a burst flash that grows and
## fades out (then frees itself), or with `hold` a steady projectile core.

var color := Color.WHITE
var radius := 20.0
var speed := 1.0
## Stay as a steady glowing dot instead of flashing out.
var hold := false
var _t := 0.0

const SECONDS := 0.22


func _process(delta: float) -> void:
	if hold:
		return
	_t += delta * speed
	if _t >= SECONDS:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if hold:
		draw_circle(Vector2.ZERO, radius * 1.8, Color(color, 0.35))
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
		return
	var p := _t / SECONDS
	var r := radius * (0.5 + p * 0.9)
	draw_circle(Vector2.ZERO, r, Color(color, 0.55 * (1.0 - p)))
	draw_circle(Vector2.ZERO, r * 0.55, Color(Color.WHITE, 0.7 * (1.0 - p)))
