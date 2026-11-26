extends Node
## Автотест (только debug-сборка, аргумент --autotest). Проигрывает сценарий:
## хост роняет мифик под ноги гостю → гость подбирает → хост предлагает обмен →
## оба кладут по предмету и подтверждают. Пишет итог в консоль и делает скриншоты.
## Запуск:  godot --path . -- --host --autotest --shots=C:/tmp   и   godot --path . -- --join --autotest

var game
var shots_dir := ""
var t := 0.0
var done := {}
var offered := false
var confirmed_at := -1.0


func _once(key: String) -> bool:
	if done.has(key):
		return false
	done[key] = true
	return true


func _shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [shots_dir, "host" if game.is_host else "guest", name])


func _guest_id() -> int:
	for pid in game.player_views:
		if pid != game.my_id:
			return pid
	return -1


func _process(delta: float) -> void:
	t += delta
	if game.is_host:
		_host_steps()
	else:
		_guest_steps()
	_economy_steps()
	_hero_steps()
	if t > 22.0 and _once("quit"):
		print("[autotest] %s: кошелёк %s, в хранилище %d" % [Net.player_name, Items.format_coins(int(game.me.coins)), game.me.get("bank", []).size()])
		print("[autotest] %s: предметов %d, в сумке: %s" % [Net.player_name, game.me.inv.size(),
			", ".join(game.me.inv.map(func(it): return Items.display_name(it)))])
		get_tree().quit()


func _host_steps() -> void:
	if t > 1.0 and _once("showcase"):
		# витрина: по мечу каждой редкости + пара топоров/кинжалов, надеваем легендарный топор
		var p: Dictionary = game.host.players[game.my_id]
		for r in 6:
			p.inv.append(Items.make("sword", r, "Витрина", false))
		for r in [2, 3, 5]:
			p.inv.append(Items.make("axe", r, "Витрина", false))
		p.inv.append(Items.make("dagger", 4, "Витрина", true))
		p.equip["weapon"] = Items.make("axe", 4, "Витрина", false)
		p.equip["head"] = Items.make("helm", 3, "Витрина", false)
		p.equip["body"] = Items.make("armor", 4, "Витрина", false)
		p.equip["feet"] = Items.make("boots", 1, "Витрина", false)
		game.host._after_equip(game.my_id)
		game.ui.inv_panel.show()
		# враги рядом — для скриншота
		var offsets := {"slime": Vector2(-90, 40), "wolf": Vector2(-70, -50), "golem": Vector2(110, -10)}
		for kind in offsets:
			game.host.spawn_enemy(kind)
			var eid: int = game.host.next_id
			game.host.enemies[eid].pos = game.my_pos + offsets[kind]
			game.host.enemies[eid].cd = 99.0
	if t > 1.9 and _once("swing"):
		game.my_facing = Vector2.RIGHT
		game.attack()
	if t > 2.0 and _once("shot_showcase"):
		_shot("0_weapons")
		game.ui.inv_panel.hide()
	var gid := _guest_id()
	if gid == -1:
		return
	var guest_pos: Vector2 = game.host.players[gid].pos
	if t > 3.0 and _once("drop"):
		game.my_pos = guest_pos + Vector2(60, 0)
		game.host.drop(Items.make("abyss_blade", 5, "", false), guest_pos)
		print("[autotest] хост уронил Клинок Бездны под ноги гостю")
	if t > 3.6 and _once("shot_drop"):
		_shot("1_jackpot")
	if t > 6.0 and _once("trade"):
		game.my_pos = guest_pos + Vector2(60, 0)
		game.request_trade_nearest()
	_trade_steps()


func _guest_steps() -> void:
	if t > 2.55 and _once("dash"):
		game.my_facing = Vector2.LEFT
		game.dash()
	if t > 2.68 and _once("shot_dash"):
		_shot("1b_dash")
	if t > 2.5 and _once("chat"):
		game.send_chat("Привет! Иду к мосту, кто со мной?")
	if game.ui.invite_panel.visible and _once("accept"):
		print("[autotest] гость принимает обмен")
		game.ui._answer(true)
	if t > 3.6 and _once("shot_drop"):
		_shot("1_jackpot")
	_trade_steps()


func _trade_steps() -> void:
	if not game.ui.trading:
		if done.has("traded_shot") == false and offered and _once("traded_shot"):
			_shot("3_after_trade")
		return
	if not offered and not game.me.inv.is_empty():
		offered = true
		var it: Dictionary = game.me.inv[game.me.inv.size() - 1]   # гость отдаёт свежий мифик
		if game.is_host:
			it = game.me.inv[0]
		game.ui.my_offer = [it.uid]
		game.send_trade_offer(game.ui.my_offer)
		print("[autotest] %s кладёт в обмен: %s" % [Net.player_name, Items.display_name(it)])
		confirmed_at = t + 1.5
	if confirmed_at > 0.0 and t > confirmed_at:
		if _once("trade_shot"):
			_shot("2_trade_window")
		confirmed_at = t + 1.0   # повторяем: изменение чужого предложения сбрасывает подтверждение
		game.confirm_trade()


func _spot(kind: String, label := "") -> Dictionary:
	for s in World.zones.interact:
		if s.kind == kind and (label == "" or s.label == label):
			return s
	return {}


func _go(s: Dictionary) -> void:
	game.my_pos = Vector2(s.x, s.y) + Vector2(0, 18)
	if game.host:
		game.host.players[game.my_id].pos = game.my_pos
	else:
		game.rpc_id(1, "h_pos", game.my_pos, Vector2.DOWN)


func _economy_steps() -> void:
	if game.is_host:
		if t > 10.5 and _once("to_bank"):
			_go(_spot("bank"))
		if t > 11.0 and _once("bank"):
			game.ui.shop.open("bank", _spot("bank"))
			game.eco("deposit", game.me.inv[0].uid)
			print("[autotest] хост сдал в хранилище: ", Items.display_name(game.me.inv[0]))
		if t > 11.8 and _once("shot_bank"):
			_shot("4_bank")
		if t > 12.3 and _once("to_shop"):
			_go(_spot("shop"))
		if t > 12.8 and _once("shop"):
			game.ui.shop.open("shop", _spot("shop"))
			game.eco("sell", game.me.inv[0].uid)
			game.eco("buy", "potion")
		if t > 13.6 and _once("shot_shop"):
			_shot("5_shop")
		if t > 14.2 and _once("to_board"):
			_go(_spot("board"))
		if t > 14.7 and _once("board"):
			game.ui.shop.open("board", _spot("board"))
		if t > 15.4 and _once("shot_board"):
			_shot("6_board")
	else:
		if t > 11.0 and _once("to_talk"):
			_go(_spot("talk", "Лина"))
		if t > 11.6 and _once("talk"):
			game.ui.shop.open("talk", _spot("talk", "Лина"))
		if t > 12.2 and _once("shot_talk"):
			_shot("4_talk")

## Классы: хост поднимает себе уровень до 6 (открыты все 4 умения), заполняет ресурс всем,
## ставит двух слизней впереди и по очереди жмёт 1-2-3-4 со снимком после каждого. Гость бьёт базовой атакой
## и жмёт первое умение своего класса.
func _hero_steps() -> void:
	if game.is_host:
		if t > 16.0 and _once("xp"):
			game.my_pos = World.spawn + Vector2(0, 80)
			game.host.skills.give_xp(game.my_id, 900)
			var hp: Dictionary = game.host.players[game.my_id]           # своё оружие класса, без чужих лат
			hp.equip["weapon"] = Items.make(Rules.class_of(hp).kit[0], 3, "тест", false)
			hp.equip.erase("head")
			game.host._after_equip(game.my_id)
			for i in 2:
				game.host.spawn_enemy("slime")
				game.host.enemies[game.host.next_id].pos = game.my_pos + Vector2(40 + i * 14, 4 - i * 10)
				game.host.enemies[game.host.next_id].cd = 99.0
			game.my_facing = Vector2.RIGHT
		if t > 16.3 and _once("res"):
			for pid in game.host.players:
				game.host.players[pid].res = float(game.host.players[pid].res_max)
		if t > 16.6 and _once("stats"):
			game.add_stat("str")
			game.add_stat("vit")
			game.ui.shop.close_all()
			game.ui.inv_panel.hide()
			game.ui.charwin.toggle()
		if t > 17.5 and _once("shot_hero"):
			_shot("7_hero")
			game.ui.charwin.toggle()
		var ids: Array = Rules.class_skills(game.me) if not game.me.is_empty() else []
		for i in ids.size():
			var at := 18.0 + i * 0.6
			if t > at and _once("skill%d" % i):
				game.my_facing = Vector2.RIGHT
				game.use_skill(ids[i])
			if t > at + 0.15 and _once("shot_skill%d" % i):
				_shot("%d_%s" % [8 + i, ids[i]])
		if t > 20.6 and _once("hero_log"):
			print("[autotest] герой: класс %s, уровень %d, %s %d/%d, здоровье %d, перезарядки %s, дары %s" % [
				Rules.class_id(game.me), int(game.me.level), Rules.res_kind(game.me), int(game.me.get("res", 0)),
				int(game.me.get("res_max", 0)), int(game.me.max_hp), str(game.me.cds.keys()), str(game.me.get("gifts", []))])
		if t > 20.8 and _once("parry") and Rules.can_parry(game.me):     # парирование: удар врага в окно гасится
			game.stamina = 100.0
			game.parry()
		if t > 20.9 and _once("parry_hit") and game.host.players[game.my_id].has("parry_until") and not game.host.enemies.is_empty():
			var eid: int = game.host.enemies.keys()[0]
			var hp_before: int = int(game.host.players[game.my_id].hp)
			game.host._hurt_player(game.my_id, 12, eid)
			print("[autotest] парирование: здоровье %d -> %d, враг оглушён: %s" % [hp_before,
				int(game.host.players[game.my_id].hp), str(int(game.host.enemies[eid].get("stun_until", 0)) > Time.get_ticks_msec())])
		if t > 21.0 and _once("shot_parry"):
			_shot("12_parry")
	else:
		if t > 16.5 and _once("basic"):
			game.my_facing = Vector2.RIGHT
			game.attack()
		if t > 16.62 and _once("shot_basic"):
			_shot("7_basic_attack")
		if t > 17.0 and _once("skill0"):
			game.use_skill(Rules.class_skills(game.me)[0])
		if t > 17.15 and _once("shot_skill0"):
			_shot("8_" + Rules.class_skills(game.me)[0])
		if t > 17.6 and _once("guest_log"):
			print("[autotest] гость: класс %s, %s %d, оружие %s, дары %s" % [Rules.class_id(game.me), Rules.res_kind(game.me),
				int(game.me.get("res", 0)), str(game.me.equip.get("weapon", {}).get("base", "-")), str(game.me.get("gifts", []))])
