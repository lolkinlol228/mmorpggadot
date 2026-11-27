extends Node
## Обе роли действуют через игровые RPC. Хост ставит встречи и сокращает здоровье Стража.
const Sites := preload("res://scripts/adventure_sites.gd")
const Relics := preload("res://scripts/relics.gd")
var game
var done := {}
var elapsed := 0.0
var finished_at := -1.0
var seen := {}                # когда гость впервые оказался у цели — камера успевает доехать до снимка


func once(key: String) -> bool:
	if done.has(key):
		return false
	done[key] = true
	return true


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 45:
		printerr("[autotest] Тайм-аут шахты: ", done.keys(), " ", game.me.get("quests"), " ", game.my_pos)
		get_tree().quit(1)
		return
	if game.me.is_empty():
		return
	if game.is_host:
		host_step()
	else:
		guest_step()


func arrived(key: String) -> bool:
	return elapsed - float(seen.get_or_add(key, elapsed)) > 1.0


## Снимок экрана гостя в папку --shots (окно, не headless).
func shot(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots=") and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("%s/mine_%s.png" % [arg.trim_prefix("--shots="), name])


func npc(actor: String) -> Vector2:
	for spot in World.zones.interact:
		if spot.get("actor") == actor:
			return Vector2(spot.x, spot.y) + Vector2(0, 17)
	return Vector2.ZERO


func has_trophies(p: Dictionary) -> bool:
	return Relics.count(p.inv, "bell_tongue") == 1 and Relics.count(p.inv, "recipe_scrap") >= 1


func host_step() -> void:
	var h = game.host
	if once("golem"):
		h.spawn_enemy("golem")
		h.gifts.deal(1, h.next_id, 99999)
		if not h.mine.opened or not Save.load_world().get("mine_open", false) or not game.me.quests.golem:
			get_tree().quit(1)
			return
		print("[autotest] Голем пал. Шахта открыта и сохранена, хост получил осколок.")
	if finished_at >= 0:
		if elapsed > finished_at + 1.5:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.WORLD_PATH))
			get_tree().quit()
		return
	var peers: Array = h.players.keys()
	peers.erase(1)
	if peers.is_empty():
		return
	var guest: int = peers[0]
	var p: Dictionary = h.players[guest]
	if once("invite"):
		game.h_trade_req(guest)
	if game.ui.trading and once("offer"):
		var shards: Array = game.me.inv.filter(func(it): return it.base == "golem_shard")
		game.send_trade_offer([shards[0].uid])
		game.confirm_trade()
	if Relics.count(p.inv, "golem_shard") > 0 and once("fisher"):
		h.talents.travel(guest, npc("fisher"))
	if p.quests.step == 1 and once("smith"):
		h.talents.travel(guest, npc("smith"))
	if p.quests.step == 2 and once("workshop"):
		var spot: Dictionary = h.professions.spots[11]
		h.talents.travel(guest, Vector2(spot.x, spot.y) + Vector2(0, 15))
	if p.equip.weapon.get("forge", "") != "" and once("gate"):
		if p.quests.golem or Relics.count(p.inv, "golem_shard") != 0:
			get_tree().quit(1)
			return
		print("[autotest] Гость без победы над Големом прошёл Рыбака и Горна, перековка: ", p.equip.weapon.forge)
		h.talents.travel(guest, Sites.MINE_GATE)
		print("[autotest] Проход у Пристани: ", p.pos)
	if Sites.MINE.has_point(p.pos) and once("warden"):
		for post in [0, 2, 4]:
			h.gifts.deal(guest, h.mine.occupants[post], 99999)
		for post in [1, 3]:
			var r: Dictionary = h.enemies[h.mine.occupants[post]]
			r.ring_at = 0
			h.mine.brain(r, guest, Items.ENEMIES.ringer, 0.0, Time.get_ticks_msec())
			h.gifts.deal(guest, r.id, 12)
		var boss: Dictionary = h.enemies[h.mine.occupants[5]]
		h.talents.travel(1, boss.pos + Vector2(0, 24))
		boss.stun_until = Time.get_ticks_msec() + 15000
		h.gifts.deal(1, boss.id, 1)
		boss.hp = 1
		h.talents.travel(guest, boss.pos - Vector2(20, 0))
	if has_trophies(p) and has_trophies(h.players[1]) and p.quests.step == 5:
		for pid in [1, guest]:
			print("[autotest] ", h.players[pid].name, " получил лично: Язык колокола и Обрывок рецепта")
		finished_at = elapsed


func guest_step() -> void:
	if game.ui.invite_panel.visible and once("accept"):
		game.ui._answer(true)
	if game.ui.trading and game.ui.their_status.text.contains("готов") and once("confirm"):
		game.confirm_trade()
	var q: Dictionary = game.me.quests
	if q.step == 0 and game.my_pos.distance_to(npc("fisher")) < 36 and once("fisher"):
		game.adventure("talk", "fisher")
	if q.step == 1 and game.my_pos.distance_to(npc("smith")) < 36 and once("smith"):
		game.adventure("talk", "smith")
	if q.step == 2 and game.me.equip.weapon.get("forge", "") == "" and once("forge"):
		var style := Items.style_of(game.me.equip.weapon)
		game.adventure("forge", preload("res://scripts/weapon_forge.gd").OPTIONS[style][0])
	if game.me.equip.weapon.get("forge", "") != "" and game.my_pos.distance_to(Sites.MINE_GATE) < 55 and arrived("gate") and once("enter"):
		shot("gate")
		game.adventure("mine", "enter")
	if q.step == 4 and game.my_pos.distance_to(Vector2(3400, 300)) < 48 and arrived("warden") and once("hit"):
		shot("warden")
		game._to_host("h_attack", [Vector2.RIGHT])
	if q.step == 5 and has_trophies(game.me) and once("loot"):
		print("[autotest] Гость видит обе личные награды в сумке. Цепочка завершена.")
		finished_at = elapsed
	if finished_at >= 0 and elapsed > finished_at + 0.7:
		get_tree().quit()
