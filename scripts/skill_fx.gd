extends RefCounted
## Как выглядят умения, удары и попадания на клиенте: спрайтовые эффекты (vfx.gd), падающий метеор,
## дождь стрел, ударные волны, тряска камеры. Урон считает хост — здесь только картинка и звук.

const Vfx := preload("res://scripts/vfx.gd")
const Projectile := preload("res://scripts/projectile.gd")
const BUFF_COLORS := {"warcry": Color(1.0, 0.4, 0.3), "stoneskin": Color(0.8, 0.75, 0.65), "barrier": Color(0.5, 0.75, 1.0),
	"divine": Color(1.0, 0.9, 0.5), "pounce": Color(1.0, 0.85, 0.35), "dirty_trick": Color(0.55, 1.0, 0.4)}

var game


## Умение героя v: id и aim (вектор от героя к прицелу, как прислал хост).
func skill(v, id: String, aim: Vector2) -> void:
	var sk: Dictionary = Rules.SKILLS[id]
	var dir := aim.normalized() if aim.length() > 0.01 else Vector2.RIGHT
	var pos: Vector2 = v.position
	var at := Rules.skill_point(sk, pos, dir, aim)
	var mine: bool = v.pid == game.my_id
	match id:
		"meteor":
			_meteor(at, float(sk.r), float(sk.get("delay", 0.5)), mine)
		"arrow_rain":
			_arrow_rain(at, float(sk.r), float(sk.get("delay", 0.35)))
		"frost_nova":
			Vfx.play(game, "frost_nova", pos, {"scale": float(sk.r) / 53.0, "fps": 14.0})
			_shake(mine, 0.12)
		"whirl", "blade_fan":
			for i in 3:
				Vfx.play(game, "slash", pos + Vector2(0, -10), {"rot": dir.angle() + i * TAU / 3.0, "scale": float(sk.r) / 22.0,
					"color": Color(0.8, 1.0, 0.8) if id == "blade_fan" else Color.WHITE, "fps": 20.0})
			Vfx.play(game, "shockwave", pos, {"scale": float(sk.r) / 45.0})
			_shake(mine, 0.12)
		"holy_strike":
			Vfx.play(game, "holy_pillar", at, {"anchor": "bottom", "scale": 0.7, "add": true})
			Vfx.play(game, "slash", pos + dir * 12.0 + Vector2(0, -12), {"rot": dir.angle(), "color": Color(1, 0.92, 0.6)})
		"assassinate":
			Vfx.play(game, "slash", at + Vector2(0, -12), {"rot": dir.angle(), "scale": 1.4, "color": Color(0.6, 1.0, 0.45), "fps": 22.0})
			Vfx.play(game, "hit_spark", at + Vector2(0, -12), {"scale": 1.8, "color": Color(0.7, 1.0, 0.5)})
			_shake(mine, 0.2)
		"blink":
			Vfx.play(game, "ring", pos, {"scale": 0.6, "color": Color(0.6, 0.75, 1.0), "add": true})
		_:
			match str(sk.kind):
				"strike":                                   # тяжёлый удар в точку
					Vfx.play(game, "shockwave", at, {"scale": float(sk.r) / 40.0})
					Vfx.play(game, "hit_spark", at + Vector2(0, -8), {"scale": 1.6})
					Vfx.play(game, "slash", pos + dir * 12.0 + Vector2(0, -12), {"rot": dir.angle(), "scale": 1.2})
					_shake(mine, 0.25 if float(sk.mult) >= 2.0 else 0.1)
				"buff":
					var c: Color = BUFF_COLORS.get(str(sk.buff), Color.WHITE)
					Vfx.play(game, "ring", pos, {"color": c, "add": true, "scale": maxf(0.7, float(sk.allies) / 45.0)})
					if sk.buff == "divine":
						Vfx.play(game, "holy_pillar", pos, {"anchor": "bottom", "add": true})


## Метеор: тень растёт на земле, камень падает из неба, потом взрыв, волна и тряска.
func _meteor(at: Vector2, r: float, delay: float, mine: bool) -> void:
	var start := at + Vector2(-110, -190)
	var rock = Vfx.play(game, "meteor", start, {"loop": delay, "fps": 12.0, "scale": 1.4, "z": 60})
	var tw: Tween = game.create_tween()
	tw.tween_property(rock, "position", at + Vector2(-8, -12), delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var shadow = Vfx.play(game, "ring", at, {"loop": delay, "fps": 0.0, "color": Color(0, 0, 0, 0.5), "scale": r / 45.0})
	shadow.frame = 0
	game.get_tree().create_timer(delay).timeout.connect(func():
		Vfx.play(game, "fire_burst", at + Vector2(0, -14), {"scale": r / 22.0, "fps": 14.0})
		Vfx.play(game, "shockwave", at, {"scale": r / 40.0})
		game.fx.dust(at, 18)
		Sfx.play_at("hit_stone", at, game.my_pos)
		game.fx.shake = maxf(game.fx.shake, 0.4 if mine else 0.15))


## Град стрел: дюжина стрел падает с неба в круг, по приземлении — пыль.
func _arrow_rain(at: Vector2, r: float, delay: float) -> void:
	for i in 12:
		var off := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.5)
		var pr = Projectile.new()
		pr.to = at + off + Vector2(0, 12)
		pr.from = pr.to + Vector2(-30, -150)
		pr.kind = "arrow"
		pr.game = game
		pr.t = -randf() * delay * 0.6                # стрелы падают не все сразу
		game.add_child(pr)
	game.get_tree().create_timer(delay).timeout.connect(func():
		Vfx.play(game, "shockwave", at, {"scale": r / 45.0, "color": Color(0.9, 0.85, 0.7)}))


## Конец полёта снаряда: взрыв, столп света или искры — по виду снаряда.
func impact(kind: String, at: Vector2, boom: float) -> void:
	match kind:
		"fire":
			Vfx.play(game, "fire_burst", at + Vector2(0, -12), {"scale": 0.8 + boom / 26.0})
		"holy":
			Vfx.play(game, "holy_pillar", at, {"anchor": "bottom", "scale": 0.55, "add": true, "fps": 20.0})
		"arcane":
			Vfx.play(game, "hit_spark", at + Vector2(0, -12), {"color": Color(0.8, 0.6, 1.0), "add": true})
		_:
			Vfx.play(game, "hit_spark", at + Vector2(0, -12), {"scale": 0.7})


## Взмах оружием ближнего боя: полумесяц в сторону удара цвета редкости оружия.
func swing(v, dir: Vector2) -> void:
	var style := Items.style_of(v.equip.get("weapon"))
	if style in ["bolt", "shot"]:
		return
	var w = v.equip.get("weapon")
	var col: Color = Items.color(w) if w is Dictionary and int(w.rarity) >= 1 else Color.WHITE
	var sc: float = {"slash": 1.0, "chop": 1.2, "stab": 0.8}.get(style, 1.0)
	Vfx.play(game, "slash", v.position + dir * 12.0 + Vector2(0, -12), {"rot": dir.angle(), "scale": sc, "color": col, "fps": 24.0})


## Попадание по врагу: искры, на крите — крупнее и лёгкая тряска.
func enemy_hit(ev, crit: bool) -> void:
	Vfx.play(game, "hit_spark", ev.position + Vector2(randf_range(-4, 4), -10 + randf_range(-4, 4)),
		{"scale": 1.5 if crit else 1.0, "color": Color(1, 0.9, 0.5) if crit else Color.WHITE})
	if crit:
		game.fx.shake = maxf(game.fx.shake, 0.08)


## Лечение героя: зелёный столб с крестами.
func healed(v) -> void:
	Vfx.play(game, "heal", v.position + Vector2(0, 4), {"anchor": "bottom", "add": true, "fps": 14.0})


func _shake(mine: bool, amount: float) -> void:
	if mine:
		game.fx.shake = maxf(game.fx.shake, amount)
