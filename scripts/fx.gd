extends Node
## Эффекты: вспышки, баннер мега-дропа, тряска камеры, частицы и звук (генерируется кодом).

var game
var layer: CanvasLayer
var flash: ColorRect
var banner: Label
var sub: Label
var shake := 0.0
var _banner_tw: Tween
var _flash_tw: Tween


func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	banner = _big_label(18, 74)            # выше героя: не наезжает на подсказки [E] и имена
	sub = _big_label(9, 98)


func _big_label(size: int, y: float) -> Label:
	var l := Label.new()
	l.anchor_right = 1.0
	l.offset_top = y
	l.offset_bottom = y + size * 1.6
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	layer.add_child(l)
	return l


func _process(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		game.camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 8.0
	elif game.camera.offset != Vector2.ZERO:
		game.camera.offset = Vector2.ZERO


func burst(pos: Vector2, color: Color, amount: int, big: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 5
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 1.4 if big else 0.6
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 150.0 if big else 70.0
	p.gravity = Vector2(0, 140)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0 if big else 2.0
	p.color = color
	game.add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


## Пыль из-под ног (бег, рывок, удар топором).
func dust(pos: Vector2, amount := 4) -> void:
	var p := CPUParticles2D.new()
	p.position = pos + Vector2(0, -1)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.45
	p.direction = Vector2(0, -1)
	p.spread = 70
	p.initial_velocity_min = 8
	p.initial_velocity_max = 22
	p.gravity = Vector2(0, 20)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.62, 0.56, 0.46, 0.75)
	game.entities.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _flash(c: Color, alpha: float, time: float) -> void:
	if _flash_tw:
		_flash_tw.kill()
	flash.color = Color(c, alpha)
	_flash_tw = create_tween()
	_flash_tw.tween_property(flash, "color:a", 0.0, time)


func hurt() -> void:
	_flash(Color(1, 0, 0), 0.18, 0.3)


## Мега-редкий предмет только что выпал на землю.
func drop_appeared(pos: Vector2, item: Dictionary) -> void:
	var c := Items.color(item)
	burst(pos, c, 90, true)
	burst(pos, Color.WHITE, 30, true)
	if game.my_pos.distance_to(pos) < 800.0:
		shake = 0.5
	Sfx.play("bell", -4.0, 1.5, false)
	Sfx.play("shimmer")


## Кто-то подобрал мега-редкий предмет — видят все игроки в мире.
func jackpot(finder: String, item: Dictionary) -> void:
	var c := Items.color(item)
	if item.shiny:
		banner.text = "★ СИЯЮЩИЙ ПРЕДМЕТ ★"
	else:
		banner.text = "⚡ %s ДРОП ⚡" % Items.RARITY_NAMES[int(item.rarity)].to_upper()
	banner.add_theme_color_override("font_color", c)
	sub.text = "%s нашёл: %s" % [finder, Items.display_name(item)]
	_flash(c, 0.55, 1.0)
	if _banner_tw:
		_banner_tw.kill()
	banner.modulate.a = 0.0
	sub.modulate.a = 0.0
	_banner_tw = create_tween()
	_banner_tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	_banner_tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.5)
	_banner_tw.tween_interval(3.5)
	_banner_tw.tween_property(banner, "modulate:a", 0.0, 1.0)
	_banner_tw.parallel().tween_property(sub, "modulate:a", 0.0, 1.0)
	shake = 0.7
