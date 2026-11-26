extends RefCounted
## Обработчики боя и визуальных эффектов клиента.

const EnemyView := preload("res://scripts/enemy_view.gd")

var game
var skill_fx := preload("res://scripts/skill_fx.gd").new()


func c_parry(pid: int) -> void:
	var v = game.player_views.get(pid)
	if v:
		v.parry()


func c_parried(pid: int, enemy_pos: Vector2) -> void:
	var v = game.player_views.get(pid)
	if v == null:
		return
	var mid: Vector2 = v.position.lerp(enemy_pos, 0.45) + Vector2(0, -14)
	game.fx.burst(mid, Color(1.0, 0.9, 0.55), 18, false)
	float_text(v.position + Vector2(0, -46), "Парировано!", Color(1.0, 0.9, 0.55))
	Sfx.play_at("bell", v.position, game.my_pos)
	if pid == game.my_id:
		game.client_input.parry_ready_at = Time.get_ticks_msec() + 600
		game.fx.shake = 0.12


func c_dash(pid: int) -> void:
	var v = game.player_views.get(pid)
	if v:
		v.dash()


func c_skill_fx(pid: int, id: String, dir: Vector2) -> void:
	var v = game.player_views.get(pid)
	if v:
		skill_fx.game = game
		skill_fx.skill(v, id, dir)                    # dir — вектор прицела от хоста
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
		v.skill(id, dir)
		Sfx.play_at({"heal": "shimmer", "buff": "bell", "blink": "swing", "bolt": "swing", "multi": "swing"}.get(str(Rules.SKILLS[id].kind), "swing"), v.position, game.my_pos)
		var sk: Dictionary = Rules.SKILLS[id]
		if sk.kind == "strike" and float(sk.mult) >= 2.0 and not sk.has("ground"):   # пыль от тяжёлого удара
			game.fx.dust(v.position + dir * float(sk.off), 12)


func c_res(value: int, max_value: int) -> void:
	if game.me.is_empty():
		return
	game.me.res = value
	game.me.res_max = max_value
	game.ui.hud.set_res(game.me)


func c_shot(from: Vector2, to: Vector2, kind: String, boom: float) -> void:
	var pr = preload("res://scripts/projectile.gd").new()
	pr.from = from
	pr.to = to
	pr.kind = kind
	pr.boom = boom
	pr.game = game
	game.add_child(pr)


func c_levelup(pid: int, level: int) -> void:
	var v = game.player_views.get(pid)
	if v:
		game.fx.burst(v.position + Vector2(0, -14), Color(1, 0.85, 0.4), 40, true)
		float_text(v.position + Vector2(0, -52), "УРОВЕНЬ %d!" % level, Color(1, 0.85, 0.4))
		game.ui.add_feed("%s достиг %d уровня!" % [v.pname, level], Color(1, 0.85, 0.4))
	if pid == game.my_id:
		Sfx.fanfare(2)


func c_enemy_spawn(d: Array) -> void:
	var v = EnemyView.new()
	v.setup(d[1], d[2], d[3], d[4])
	v.elite = d.size() > 5 and bool(d[5])
	game.entities.add_child(v)
	game.enemy_views[d[0]] = v


func c_enemy_hit(eid: int, hp: int, dmg: int, crit: bool) -> void:
	var v = game.enemy_views.get(eid)
	if v:
		v.hp = hp
		v.flash()
		skill_fx.game = game
		skill_fx.enemy_hit(v, crit)
		Sfx.play_at("hit_stone" if v.kind == "golem" else ("crit" if crit else "hit"), v.position, game.my_pos)
		float_text(v.position + Vector2(0, -30), ("%d!" % dmg) if crit else str(dmg),
			Color(1, 0.85, 0.2) if crit else Color.WHITE)


func c_enemy_died(eid: int) -> void:
	var v = game.enemy_views.get(eid)
	if v:
		game.fx.burst(v.position, v.data.color, 24, false)
		Sfx.play_at("enemy_die", v.position, game.my_pos)
		v.queue_free()
		game.enemy_views.erase(eid)


func c_swing(pid: int, dir: Vector2) -> void:
	var v = game.player_views.get(pid)
	if v:
		v.swing(dir)
		skill_fx.game = game
		skill_fx.swing(v, dir)
		Sfx.play_at("swing", v.position, game.my_pos)


func c_hp(pid: int, hp: int, max_hp: int, dealt: int) -> void:
	var v = game.player_views.get(pid)
	if v:
		if dealt == 0 and hp > v.hp and v.hp > 0:     # лечение
			skill_fx.game = game
			skill_fx.healed(v)
		v.hp = hp
		v.max_hp = max_hp
		if dealt > 0:
			v.hurt()
			float_text(v.position + Vector2(0, -44), "-%d" % dealt, Color(1, 0.35, 0.3))
	if pid == game.my_id and not game.me.is_empty():
		game.me.hp = hp
		game.me.max_hp = max_hp
		game.ui.refresh_hp()
		if dealt > 0:
			game.fx.hurt()
			Sfx.play("hurt")


func c_teleport(pos: Vector2, blink: bool) -> void:
	if blink:
		game.fx.burst(game.my_pos + Vector2(0, -12), Color(0.6, 0.75, 1.0), 14, false)
		game.fx.burst(pos + Vector2(0, -12), Color(0.8, 0.9, 1.0), 14, false)
	game.my_pos = pos


func float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 20
	l.position = pos + Vector2(-30, 0)
	l.size = Vector2(60, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	game.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y - 20, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)


func c_shield(amount: int) -> void:
	game.me.shield = amount
	game.ui.refresh_hp()


func c_gift_motion(values: Dictionary) -> void:
	game.me.gift_motion = values


func c_parry_reset() -> void:
	game.client_input.parry_ready_at = 0


func c_enemy_elite(eid: int, hp: int, maximum: int) -> void:
	var view = game.enemy_views.get(eid)
	if view:
		view.hp = hp
		view.max_hp = maximum
		view.elite = true


func c_dash_reset() -> void:
	game.client_input.dash_charges.used.clear()
