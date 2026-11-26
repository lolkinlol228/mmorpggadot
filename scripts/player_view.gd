extends Node2D
## Игрок: спрайт собирается из слоёв тела и надетых вещей (char_baker.gd),
## оружие — в руке по точке из скелета. Легендарки дают ауру и искры.

const CharBaker := preload("res://scripts/char_baker.gd")
const C := 48             # клетка листа; ноги на y=38
# стиль удара по оружию: первый кадр в листе и длительность
const STYLES := {"slash": [10, 0.24], "chop": [13, 0.34], "stab": [16, 0.16]}
const RUN_SPEED := 150.0   # быстрее — играем анимацию бега

var pid := 0
var pname := ""
var equip := {}
var look := {}
var facing := Vector2.RIGHT
var target := Vector2.ZERO
var hp := 100
var max_hp := 100
var is_me := false
var npc := false             # житель города: без полоски здоровья, имя голубым
var t := 0.0
var anim_t := 0.0
var moving := false
var move_dir := Vector2.DOWN
var swing_t := 0.0
var swing_dir := Vector2.RIGHT
var swing_len := 0.24
var style := "slash"
var speed := 0.0
var dash_t := 0.0
var trail: Array = []        # силуэты рывка: [позиция, кадр, направление, флип, время]
var use_t := 0.0
var hurt_t := 0.0
var skill_id := ""        # эффект умения: вспышка в момент применения
var skill_t := 0.0
var skill_dir := Vector2.RIGHT
var auras := {}             # усиления, видимые всем: id -> секунд осталось
const SKILL_COLORS := {"whirl": Color(0.85, 0.9, 1.0), "smash": Color(1.0, 0.7, 0.35), "mend": Color(0.45, 1.0, 0.5),
	"second_wind": Color(0.55, 1.0, 0.75), "blink": Color(0.6, 0.75, 1.0), "stoneskin": Color(0.75, 0.7, 0.6),
	"warcry": Color(1.0, 0.35, 0.25), "drain": Color(0.7, 0.2, 0.9), "pounce": Color(1.0, 0.85, 0.3),
	"dirty_trick": Color(0.5, 0.95, 0.3)}
var sheet: Texture2D
var _last_pos := Vector2.ZERO
var label: Label
var overlay: Node2D          # имя и полоска здоровья — всегда поверх зданий и деревьев


func _ready() -> void:
	_last_pos = position
	sheet = CharBaker.bake(equip, look)
	overlay = Node2D.new()
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(120, 10)
	label.position = Vector2(-60, -44)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(label)
	_update_label()


func set_equip(e: Dictionary) -> void:
	equip = e
	sheet = CharBaker.bake(equip, look)
	_update_label()


static func style_for(equip_: Dictionary) -> String:
	var w = equip_.get("weapon")
	if w is Dictionary:
		if w.base == "axe":
			return "chop"
		if w.base == "dagger":
			return "stab"
	return "slash"


func swing(dir: Vector2) -> void:
	swing_dir = dir
	style = style_for(equip)
	swing_len = STYLES[style][1]
	swing_t = swing_len


func dash() -> void:
	dash_t = 0.24


func hurt() -> void:
	hurt_t = 0.22


func use() -> void:
	use_t = 0.35


func skill(id: String, dir: Vector2) -> void:
	skill_id = id
	skill_t = 0.5
	skill_dir = dir
	var dur := float(Rules.SKILLS[id].get("dur", 0.0))
	if dur > 0.5:
		auras[id] = dur
	if id in ["whirl", "smash"]:
		swing(dir)
	elif id in ["mend", "second_wind", "warcry"]:
		use()


func _best() -> Dictionary:
	var best := {}
	var score := -1.0
	for it in equip.values():
		if it is Dictionary:
			var s := float(it.rarity) + (4.5 if it.shiny else 0.0)
			if s > score:
				score = s
				best = it
	return best


func _update_label() -> void:
	if not label:
		return
	label.text = pname
	var best := _best()
	var c := Color(1, 0.92, 0.65) if is_me else Color(0.9, 0.9, 0.95)
	if npc:
		c = Color(0.6, 0.82, 1.0)
	if not best.is_empty() and int(best.rarity) >= 2:
		c = Items.color(best)
	label.add_theme_color_override("font_color", c)


func _process(delta: float) -> void:
	t += delta
	swing_t = maxf(0.0, swing_t - delta)
	use_t = maxf(0.0, use_t - delta)
	hurt_t = maxf(0.0, hurt_t - delta)
	skill_t = maxf(0.0, skill_t - delta)
	for id in auras.keys():
		auras[id] -= delta
		if auras[id] <= 0.0 or (id == "dirty_trick" and swing_t > 0.0 and auras[id] < float(Rules.SKILLS[id].dur) - 0.3):
			auras.erase(id)
	if not is_me:
		position = position.lerp(target, minf(1.0, delta * 12.0))
	var d := position - _last_pos
	_last_pos = position
	moving = d.length() > 20.0 * delta
	speed = lerpf(speed, d.length() / maxf(delta, 0.001), minf(1.0, delta * 10.0))
	if moving:
		move_dir = d.normalized()
		anim_t += delta * (1.35 if speed > RUN_SPEED else 1.0)
	if dash_t > 0.0:
		dash_t -= delta
		if int(t * 60.0) % 3 == 0:
			trail.append([position, _frame_col(), _dir_index(), move_dir.x < 0, 0.25])
	for g in trail:
		g[4] -= delta
	trail = trail.filter(func(g): return g[4] > 0.0)
	queue_redraw()
	overlay.queue_redraw()


func _frame_col() -> int:
	if swing_t > 0.0:
		return STYLES[style][0] + mini(2, int((1.0 - swing_t / swing_len) * 3.0))
	if hurt_t > 0.0:
		return 20
	if use_t > 0.0:
		return 19
	if dash_t > 0.0 or (moving and speed > RUN_SPEED):
		return 6 + int(anim_t * 10.0) % 4
	if moving:
		return 2 + int(anim_t * 8.0) % 4
	return int(t * 2.0) % 2


func _dir_index() -> int:
	if absf(move_dir.x) > absf(move_dir.y):
		return 2
	return 1 if move_dir.y < 0 else 0


func _draw() -> void:
	if hp <= 0:
		draw_rect(Rect2(-5, -12, 10, 13), Color(0.35, 0.35, 0.42))
		draw_rect(Rect2(-1, -10, 2, 8), Color(0.2, 0.2, 0.25))
		draw_rect(Rect2(-3, -8, 6, 2), Color(0.2, 0.2, 0.25))
		return
	var best := _best()
	if not best.is_empty() and (int(best.rarity) >= 4 or best.shiny):
		var c := Items.color(best)
		for i in 3:
			draw_circle(Vector2(0, -10), 11.0 + i * 3.0 + sin(t * 3.0 + i), Color(c, 0.08))
		for i in 6:
			var a := t * 1.5 + i * TAU / 6.0
			draw_rect(Rect2(Vector2(cos(a) * 9.0, 0.0 - fmod(t * 14.0 + i * 6.0, 26.0)), Vector2(1, 1)), Color(c, 0.95))
	draw_set_transform(Vector2(0, 0), 0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, 7, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for g in trail:                         # шлейф рывка: полупрозрачные силуэты
		var gp: Vector2 = g[0] - position
		draw_set_transform(gp, 0, Vector2(-1 if (g[2] == 2 and g[3]) else 1, 1))
		draw_texture_rect_region(sheet, Rect2(-C / 2.0, -38, C, C), Rect2(g[1] * C, g[2] * C, C, C),
			Color(0.6, 0.8, 1.0, g[4] * 1.6))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var dir := _dir_index()
	var look := move_dir
	var col := _frame_col()
	if swing_t > 0.0:                       # удар: 3 кадра в сторону атаки
		look = swing_dir
		dir = 2 if absf(look.x) > absf(look.y) else (1 if look.y < 0 else 0)
	var flip := dir == 2 and look.x < 0
	if flip:
		draw_set_transform(Vector2.ZERO, 0, Vector2(-1, 1))
	draw_texture_rect_region(sheet, Rect2(-C / 2.0, -38, C, C), Rect2(col * C, dir * C, C, C))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if swing_t > 0.0:
		_draw_swing_fx()
	_draw_skill_fx()


## Умения: вспышка в момент применения и ауры усилений, пока они действуют.
func _draw_skill_fx() -> void:
	for id in auras:
		var c: Color = SKILL_COLORS[id]
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		match id:
			"stoneskin":                               # каменные пластины вокруг
				for i in 6:
					var a := t * 0.8 + i * TAU / 6.0
					draw_rect(Rect2(Vector2(cos(a) * 12.0 - 1.5, sin(a) * 5.0 - 12.0 - 1.5), Vector2(3, 3)), Color(c, 0.85))
			"warcry", "drain", "pounce":                # огненная / тёмная / золотая аура у ног
				draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.4))
				draw_arc(Vector2.ZERO, 11.0 + pulse * 2.0, 0, TAU, 20, Color(c, 0.55), 1.5)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				for i in 4:
					var a := i * TAU / 4.0 + t
					draw_rect(Rect2(Vector2(cos(a) * 8.0, -fmod(t * 20.0 + i * 7.0, 28.0)), Vector2(1, 2)), Color(c, 0.8))
			"dirty_trick":                             # зелёный блеск на клинке
				draw_circle(Vector2(8, -16), 1.5 + pulse, Color(c, 0.8))
	if skill_t <= 0.0:
		return
	var c: Color = SKILL_COLORS.get(skill_id, Color.WHITE)
	var k := 1.0 - skill_t / 0.5
	match skill_id:
		"whirl":
			draw_set_transform(Vector2(0, -8), 0, Vector2(1, 0.55))
			draw_arc(Vector2.ZERO, 14.0 + k * 34.0, t * 9.0, t * 9.0 + TAU * 0.8, 28, Color(c, 1.0 - k), 2.5)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"smash":
			var hit := skill_dir * 28.0
			draw_set_transform(hit, 0, Vector2(1, 0.45))
			draw_arc(Vector2.ZERO, 6.0 + k * 30.0, 0, TAU, 24, Color(c, 1.0 - k), 2.5)
			draw_arc(Vector2.ZERO, k * 18.0, 0, TAU, 18, Color(1, 1, 1, (1.0 - k) * 0.7), 1.0)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"mend", "second_wind":
			for i in 8:
				var x := -10.0 + i * 3.0
				var y := -6.0 - k * 30.0 - (i % 3) * 5.0
				draw_rect(Rect2(x, y, 1, 3), Color(c, 1.0 - k))
				draw_rect(Rect2(x - 1, y + 1, 3, 1), Color(c, 1.0 - k))
		"blink":
			draw_circle(Vector2(0, -12), 6.0 + k * 14.0, Color(c, (1.0 - k) * 0.5))
		"warcry":
			for r in 3:
				draw_arc(Vector2(0, -20), 8.0 + (k + r * 0.3) * 40.0, 0, TAU, 24, Color(c, maxf(0.0, 0.8 - k - r * 0.2)), 1.5)
		_:
			draw_circle(Vector2(0, -12), 4.0 + k * 16.0, Color(c, (1.0 - k) * 0.6))


func _draw_overlay() -> void:
	if npc or hp <= 0:
		return
	var ratio := clampf(float(hp) / max_hp, 0.0, 1.0)
	overlay.draw_rect(Rect2(-10, -34, 20, 2), Color(0, 0, 0, 0.7))
	overlay.draw_rect(Rect2(-10, -34, 20 * ratio, 2), Color(0.4, 0.85, 0.4) if ratio > 0.35 else Color(0.9, 0.3, 0.25))


## След удара: дуга (меч), удар о землю (топор), выпад (кинжал). Цвет — по редкости оружия.
func _draw_swing_fx() -> void:
	var w = equip.get("weapon")
	var col := Items.color(w) if w is Dictionary and int(w.rarity) >= 1 else Color(1, 1, 1)
	var k := 1.0 - swing_t / swing_len
	var a := swing_dir.angle()
	match style:
		"slash":
			if k > 0.25:
				draw_arc(Vector2(0, -12), 19, a - 1.3, a - 1.3 + 2.6 * minf(1.0, (k - 0.25) * 1.6), 14, Color(col, (1.0 - k) * 0.9), 2.0)
		"chop":
			if k > 0.6:
				var hit := swing_dir * 16.0 + Vector2(0, -2)
				var r := 4.0 + (k - 0.6) * 30.0
				draw_set_transform(hit, 0, Vector2(1, 0.45))
				draw_arc(Vector2.ZERO, r, 0, TAU, 18, Color(col, (1.0 - k) * 2.0), 1.5)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"stab":
			if k > 0.2 and k < 0.8:
				var from := swing_dir * 8.0 + Vector2(0, -12)
				draw_line(from, from + swing_dir * 20.0, Color(col, 0.8 * (1.0 - k)), 1.5)
				draw_line(from + Vector2(0, 2), from + swing_dir * 14.0 + Vector2(0, 2), Color(col, 0.4 * (1.0 - k)), 1.0)