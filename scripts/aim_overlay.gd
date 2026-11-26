extends Node2D
## Прицел своего героя (рисуется только у себя, в координатах мира):
## - стрелка у ног в сторону курсора;
## - красное кольцо под врагом, на которого наведён курсор;
## - у дальнего оружия — пунктир до конца дальности выстрела;
## - пока зажата клавиша умения — его зона: линия снаряда, круг удара по точке,
##   круг дальности, подсветка союзника для лечения.

const ENEMY_PICK := 18.0
const ALLY_PICK := 24.0
const RED := Color(1.0, 0.35, 0.3)
const GOLD := Color(1.0, 0.85, 0.45)
const GREEN := Color(0.45, 1.0, 0.55)

var game
var t := 0.0


func _ready() -> void:
	z_index = 45


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	if game == null or game.me.is_empty() or int(game.me.hp) <= 0:
		return
	var me_pos: Vector2 = game.my_pos
	var aim: Vector2 = game.client_input.aim_vector()
	var dir := aim.normalized() if aim.length() > 6.0 else Vector2(game.my_facing)
	var cursor := me_pos + aim
	_draw_feet_arrow(me_pos, dir)
	var target = _enemy_under(cursor)
	if target:
		_ellipse(target.position, 13.0 + sin(t * 8.0), Color(RED, 0.9), 1.5)
	var id: String = game.client_input.aiming
	if id != "":
		_draw_skill_aim(id, me_pos, dir, aim)
		return
	var style := Items.style_of(game.me.equip.get("weapon"))
	if style in ["bolt", "shot"]:
		var reach: float = Rules.ATTACKS[style][4]
		_dotted(me_pos + Vector2(0, -12), me_pos + Vector2(0, -12) + dir * minf(reach, maxf(aim.length(), 24.0)), Color(GOLD, 0.35))
		if aim.length() > reach:
			_ellipse(me_pos + dir * reach, 4.0, Color(GOLD, 0.5), 1.0)


func _draw_feet_arrow(pos: Vector2, dir: Vector2) -> void:
	var a := dir.angle()
	var tip := pos + Vector2(cos(a) * 15.0, sin(a) * 15.0 * 0.5)
	var l := pos + Vector2(cos(a + 2.6) * 6.0, sin(a + 2.6) * 6.0 * 0.5) + Vector2(cos(a) * 9.0, sin(a) * 4.5)
	var r := pos + Vector2(cos(a - 2.6) * 6.0, sin(a - 2.6) * 6.0 * 0.5) + Vector2(cos(a) * 9.0, sin(a) * 4.5)
	draw_colored_polygon(PackedVector2Array([tip, l, r]), Color(GOLD, 0.55))


func _draw_skill_aim(id: String, pos: Vector2, dir: Vector2, aim: Vector2) -> void:
	var sk: Dictionary = Rules.SKILLS[id]
	var ok: bool = game.ui.hud.skills.cd_left(id) <= 0.0 and float(game.me.get("res", 0)) >= Rules.skill_cost(game.me, id)
	var col := Color(GOLD, 0.85) if ok else Color(0.6, 0.6, 0.7, 0.6)
	var hand := pos + Vector2(0, -12)
	match str(sk.kind):
		"bolt":
			_beam(hand, hand + dir * float(sk.range), col, 3.0 if float(sk.get("aoe", 0.0)) > 0.0 else 1.5)
			if float(sk.get("aoe", 0.0)) > 0.0:
				_ellipse(pos + dir * float(sk.range), float(sk.aoe), Color(col, 0.5), 1.0)
		"multi":
			var n := int(sk.count)
			for i in n:
				var d := dir.rotated((i - (n - 1) / 2.0) * float(sk.spread))
				_beam(hand, hand + d * float(sk.range), col, 1.2)
		"strike":
			if sk.has("ground"):
				_ellipse(pos, float(sk.ground), Color(col, 0.25), 1.0, true)
			var at := Rules.skill_point(sk, pos, dir, aim)
			var pulse := 1.0 + sin(t * 7.0) * 0.06
			_ellipse_fill(at, float(sk.r) * pulse, Color(col, 0.16))
			_ellipse(at, float(sk.r) * pulse, col, 1.5)
		"heal":
			var radius := float(sk.get("radius", 120.0))
			_ellipse(pos, radius, Color(GREEN, 0.3), 1.0, true)
			var ally = _ally_under(pos + aim, pos, radius)
			if ally:
				_ellipse(ally.position, 12.0 + sin(t * 8.0), Color(GREEN, 0.95), 1.5)


func _enemy_under(point: Vector2):
	var best = null
	var best_d := ENEMY_PICK
	for v in game.enemy_views.values():
		var d: float = (v.position + Vector2(0, -8)).distance_to(point)
		if d < best_d:
			best = v
			best_d = d
	return best


func _ally_under(point: Vector2, origin: Vector2, radius: float):
	var best = null
	var best_d := ALLY_PICK
	for v in game.player_views.values():
		var d: float = (v.position + Vector2(0, -12)).distance_to(point)
		if d < best_d and v.position.distance_to(origin) <= radius:
			best = v
			best_d = d
	return best


## Эллипс «на земле» (сплюснут по вертикали, как тени и круги под героями).
func _ellipse(c: Vector2, r: float, col: Color, w: float, dashed := false) -> void:
	var n := 40
	for i in n:
		if dashed and i % 2 == 1:
			continue
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		draw_line(c + Vector2(cos(a0) * r, sin(a0) * r * 0.5), c + Vector2(cos(a1) * r, sin(a1) * r * 0.5), col, w)


func _ellipse_fill(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.5))
	draw_colored_polygon(pts, col)


func _beam(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, Color(col, col.a * 0.35), w + 2.0)
	draw_line(a, b, col, w)
	draw_circle(b, w + 1.0, col)


func _dotted(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	var d := (b - a).normalized()
	var x := fmod(t * 30.0, 8.0)
	while x < len:
		draw_line(a + d * x, a + d * minf(x + 3.0, len), col, 1.0)
		x += 8.0
