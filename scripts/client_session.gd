extends RefCounted
## Состояние мира, сообщения и сохранение подтверждённого героя.

var game


func c_self(priv: Dictionary) -> void:
	if not game.me.is_empty() and int(priv.coins) > int(game.me.coins):
		Sfx.play("coins")
	var old_level = int(game.me.get("level", 0))
	game.me = priv
	game.me["_recv"] = Time.get_ticks_msec()
	game.ui.refresh()
	if old_level > 0 and int(game.me.level) > old_level and int(game.me.points) > 0:
		game.ui.add_feed("Новые очки характеристик! Открой окно героя: C", Color(1, 0.85, 0.4))
	Save.store_char({"name": Net.player_name, "coins": game.me.coins, "inv": game.me.inv, "equip": game.me.equip,
		"look": game.me.get("look", {}), "bank": game.me.get("bank", []), "bounties": game.me.get("bounties", {}),
		"level": game.me.get("level", 1), "xp": game.me.get("xp", 0), "points": game.me.get("points", 0), "stats": game.me.get("stats", {}),
		"cls": game.me.get("cls", "warrior"), "gifts": game.me.get("gifts", []), "gift_state": game.me.get("gift_state", {}), "materials": game.me.get("materials", {}), "professions": game.me.get("professions", {}),
		"tools": game.me.get("tools", {}), "visited": game.me.get("visited", {}), "cross_skill": game.me.get("cross_skill", "")})


func c_init(ps: Array, es: Array, ls: Array, priv: Dictionary) -> void:
	for p in ps:
		game.c_player_joined(p)
	for e in es:
		game.c_enemy_spawn(e)
	for l in ls:
		game._add_loot(l[0], l[1], l[2], false)
	game.my_pos = priv.pos
	game.c_self(priv)
	print("[client] в мире: игроков %d, врагов %d" % [game.player_views.size(), game.enemy_views.size()])


func c_player_joined(pub: Dictionary) -> void:
	var pid := int(pub.id)
	if game.player_views.has(pid):
		return
	var v = game.PlayerView.new()
	v.pid = pid
	v.pname = pub.name
	v.equip = pub.equip
	v.look = pub.get("look", {})
	v.hp = pub.hp
	v.max_hp = pub.max_hp
	v.is_me = pid == game.my_id
	v.position = pub.pos
	v.target = pub.pos
	game.entities.add_child(v)
	game.player_views[pid] = v


func c_player_left(pid: int) -> void:
	if game.player_views.has(pid):
		game.player_views[pid].queue_free()
		game.player_views.erase(pid)


func c_state(ps: Array, es: Array) -> void:
	for p in ps:
		var v = game.player_views.get(p[0])
		if v and p[0] != game.my_id:
			v.target = p[1]
			v.facing = p[2]
	for e in es:
		var ev = game.enemy_views.get(e[0])
		if ev:
			ev.target = e[1]


func c_chat(from: String, text: String) -> void:
	game.ui.hud.add_chat(from, text)
	Sfx.play("hover")


func c_announce(text: String, color: Color) -> void:
	game.ui.add_feed(text, color)
