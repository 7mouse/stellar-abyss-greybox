class_name DamageNumber
extends Label
## 伤害飘字 0.5 秒

static func spawn(parent: Node, pos: Vector2, amount: int, color := Color.WHITE, life := 0.5) -> DamageNumber:
	var l := DamageNumber.new()
	l.text = str(amount)
	l.position = pos + Vector2(-20, -60)
	l.z_index = 50
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 50, life)
	tw.parallel().tween_property(l, "modulate:a", 0.0, life)
	tw.tween_callback(l.queue_free)
	return l
