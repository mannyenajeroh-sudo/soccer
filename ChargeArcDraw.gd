extends Control

var charge := 0.0

func _draw():
	if charge > 0.01:
		var r := 28.0
		var c := size * 0.5
		draw_arc(c, r, -PI*0.5, -PI*0.5 + TAU*charge, 32, Color.WHITE, 3.0, true)
