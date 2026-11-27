extends Node2D
## Предмет на земле. Чем реже — тем выше столб света. Сияющие крутят искры.

var item := {}
var t := 0.0


func _ready() -> void:
	t = randf() * 3.0
	update_label(item)


var caption: Label

func update_label(value: Dictionary) -> void:
	item = value
	var show_name := int(item.rarity) >= 1 or bool(item.shiny) or item.has("reserved_for")
	if not show_name:
		if caption:
			caption.hide()
		return
	if not caption:
		var l := Label.new()
		l.z_index = 50                     # название поверх зданий
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(120, 10)
		l.position = Vector2(-60, -26)
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.add_theme_color_override("font_color", Items.color(item))
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		add_child(l)
		caption = l
	caption.text = Items.display_name(item)
	if item.has("reserved_for"):
		caption.text += " · " + str(item.reserved_for)
	caption.show()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var c := Items.color(item)
	var r := int(item.rarity)
	var bob := sin(t * 3.0) * 3.0 - 6.0
	if r >= 2 or item.shiny:
		var h := 24.0 + r * 26.0 + (50.0 if item.shiny else 0.0)
		var w := 2.0 + r
		draw_rect(Rect2(-w * 1.5, -h, w * 3.0, h), Color(c, 0.07))
		draw_rect(Rect2(-w * 0.5, -h, w, h), Color(c, 0.22 + sin(t * 4.0) * 0.08))
	if r >= 4 or item.shiny:
		draw_circle(Vector2(0, bob), 12.0 + sin(t * 5.0) * 2.0, Color(c, 0.18))
	draw_set_transform(Vector2(0, 8), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 8, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_texture_rect(Items.icon(item), Rect2(-8, -8 + bob, 16, 16), false)
	if item.shiny:
		for i in 4:
			var a := t * 2.0 + i * TAU / 4.0
			draw_rect(Rect2(Vector2(cos(a), sin(a)) * 11.0 + Vector2(-1, bob - 1), Vector2(2, 2)), Items.SHINY_COLOR)
