extends SceneTree

const Quest := preload("res://scripts/mine_quest.gd")
const Sites := preload("res://scripts/adventure_sites.gd")

class LocalGame:
	extends RefCounted
	var my_id := 1
	var last_crit := false
	func c_enemy_hit(_pid: int, _hp: int, _dmg: int, crit: bool) -> void: last_crit = crit
	func c_parried(_pid: int, _pos: Vector2) -> void: pass
	func c_swing(_pid: int, _dir: Vector2) -> void: pass
	var messages: Array = []
	func c_announce(message: String, _color: Color) -> void: messages.append(message)
	func c_self(_data: Dictionary) -> void: pass
	func c_shot(_from: Vector2, _to: Vector2, _kind: String, _aoe: float) -> void: pass
	func c_hp(_pid: int, _hp: int, _max: int, _damage: int) -> void: pass
	func c_enemy_spawn(_row: Array) -> void: pass
	func c_equip(_pid: int, _equip: Dictionary) -> void: pass
	func c_loot(_id: int, _item: Dictionary, _pos: Vector2) -> void: pass
	func c_loot_gone(_id: int) -> void: pass

var host
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr(label)


func player(id: int, pos: Vector2) -> Dictionary:
	var p: Dictionary = root.get_node("Save").sanitize_char({"name": "Герой%d" % id})
	p.merge({"peer_id": id, "hp": 100, "max_hp": 100, "pos": pos, "trade": 0, "buffs": {}, "cds": {}, "res": 100, "res_max": 100})
	return p


func encounters() -> bool:
	var m = host.mine
	check(m.open_mine() and not m.open_mine(), "Первое открытие")
	m.setup()
	check(m.opened and host.game.messages.size() == 1, "Открытый мир пережил загрузку")
	m.tick()
	check(host.enemies.size() == 6, "Шесть мест встречи")
	var e: Dictionary = host.enemies[m.occupants[0]]
	e.facing = Vector2.RIGHT
	check(m.armor(e, e.pos + Vector2.RIGHT, 100, 10) == 20 and m.armor(e, e.pos + Vector2.LEFT, 100, 10) == 100, "Лицевая броня")
	e.open_until = 1510
	check(m.armor(e, e.pos + Vector2.RIGHT, 100, 1509) == 200 and m.armor(e, e.pos + Vector2.RIGHT, 100, 1510) == 20, "Время уязвимости")
	var r: Dictionary = host.enemies[m.occupants[1]]
	host.players[1].pos = r.pos
	var stats: Dictionary = root.get_node("Items").ENEMIES.ringer
	r.ring_at = 10
	m.brain(r, 1, stats, 0.0, 10)
	m.brain(r, 1, stats, 0.0, 3009)
	check(r.phase == "ring" and host.enemies.size() == 6, "Звон длится три секунды")
	m.brain(r, 1, stats, 0.0, 3010)
	check(host.enemies.size() == 8, "Два подкрепления")
	m.brain(r, 1, stats, 0.0, 15010)
	m.damage(1, r, 7)
	check(r.phase == "ring", "Слабое попадание оставляет звон")
	m.damage(1, r, 8)
	m.brain(r, 1, stats, 0.0, Time.get_ticks_msec())
	check(r.phase == "" and host.enemies.size() == 8, "Прерывание отменило призыв")
	var now := Time.get_ticks_msec()
	r.phase = "ring"
	r.until = now
	host.players[1].parry_until = now + 300
	m.brain(r, 1, stats, 0.0, now)
	check(host.enemies.size() == 8 and r.phase == "" and r.stun_until > now, "Парирование последнего звона")
	var boss: Dictionary = host.enemies[m.occupants[5]]
	m.killed(boss, 1)
	host.enemies.erase(boss.id)
	check(m.next_spawn[5] - now >= 180000, "Три минуты до появления Стража")
	m.next_spawn[5] = 0
	m.tick()
	check(not m.occupants.has(5), "Возрождение ждёт выхода группы")
	host.players[1].pos = Sites.CAMPS.ford
	m.tick()
	check(m.occupants.has(5), "Возрождение в пустой шахте")
	return true



func quest() -> bool:
	var p: Dictionary = host.players[1]
	for actor in ["smith", "fisher", "smith"]:
		var spot: Dictionary = root.get_node("World").zones.interact.filter(func(s): return s.get("actor") == actor)[0]
		p.pos = Vector2(spot.x, spot.y)
		host.mine.action(1, "talk", actor)
	check(p.quests.step == 1, "Кузнец ждёт осколок")
	p.inv.append(root.get_node("Items").make("golem_shard", 0, "", false))
	host.mine.action(1, "talk", "smith")
	check(p.quests.step == 2 and p.inv.size() == 1, "Показ трофея")
	for event in ["warden", "interrupt", "shell", "shell", "shell", "warden", "interrupt", "interrupt", "warden"]:
		Quest.progress(p.quests, event)
	check(p.quests.step == 5 and root.get_node("Save").sanitize_char(p).quests == p.quests, "Порядок и сохранение цепочки")
	return true



func forge() -> bool:
	var p: Dictionary = host.players[1]
	var items := root.get_node("Items")
	var spot: Dictionary = host.professions.spots[11]
	p.pos = Vector2(spot.x, spot.y)
	p.equip.weapon = items.make("sword", 0, "", false)
	p.inv[0].count = 2
	host.adventure("forge", "pierce")
	check(p.inv[0].count == 2 and not p.equip.weapon.has("forge"), "Свойство другого стиля отклонено")
	host.adventure("forge", "riposte")
	host.adventure("forge", "riposte")
	check(p.equip.weapon.forge == "riposte" and p.inv[0].count == 1, "Списание одного осколка")
	host.adventure("forge", "cleave")
	check(p.inv.is_empty() and items.normalize(p.equip.weapon).forge == "cleave", "Перековка хранится в вещи")
	check("50%" in items.tooltip(p.equip.weapon), "Свойство в подсказке")
	return true



func swing(e: Dictionary) -> int:
	e.hp = 10000
	seed(762)
	host.skills.hit_enemy(1, e.id, 1.0, -1.0)
	return 10000 - int(e.hp)


func properties() -> bool:
	var p := player(1, Sites.MINE_EXIT)
	host.players[1] = p
	var items := root.get_node("Items")
	p.pos = Sites.MINE_EXIT
	host.enemies.clear()
	for i in 3:
		host.host_enemies.spawn_at("ringer", p.pos + Vector2(19 + i * 20, 0))
	var targets: Array = host.enemies.values()
	for target in targets:
		target.max_hp = 10000
		target.hp = 10000
	var e: Dictionary = targets[0]
	var w: Dictionary = items.make("sword", 2, "", false)
	p.equip.weapon = w
	w.dmg = 100
	var base := swing(e)
	w.forge = "riposte"
	p.riposte_until = Time.get_ticks_msec() + 1000
	check(absi(swing(e) - base * 2) <= 1, "Удвоенный ответ")
	w.forge = "cleave"
	p.atk_at = -10000
	for target in targets:
		target.hp = 10000
	host.skills.basic_attack(1, Vector2.RIGHT)
	var damage: Array = targets.map(func(target): return 10000 - int(target.hp))
	damage.sort()
	check(damage[0] == 0 and damage[1] > 0 and absi(damage[2] - 2 * damage[1]) <= 1, "Две цели рубящей атаки")
	w.base = "hammer"
	w.forge = "crusher"
	e.stun_until = 0
	base = swing(e)
	e.stun_until = Time.get_ticks_msec() + 1000
	check(absf(swing(e) - base * 1.4) < 1.5, "Усиление по оглушению")
	w.forge = "third"
	e.stun_until = 0
	for i in 2:
		swing(e)
	check(e.stun_until == 0, "Первые два удара без оглушения")
	swing(e)
	check(e.stun_until - Time.get_ticks_msec() > 450, "Третий удар оглушает")
	w.base = "dagger"
	w.forge = "dash_crit"
	var smith := preload("res://scripts/weapon_forge.gd")
	smith.on_dash(p)
	swing(e)
	check(host.game.last_crit, "Первый удар после рывка критический")
	swing(e)
	check(not host.game.last_crit, "Крит рывка потрачен")
	w.forge = "bleed"
	base = swing(e)
	var start: int = e.wounds[0].start
	smith.bleed(host, start + 999)
	check(e.hp == 10000 - base, "Кровотечение не начислено сразу")
	smith.bleed(host, start + 3000)
	check(e.wounds.is_empty() and e.hp == 10000 - base - roundi(base * 0.3), "Кровотечение за три секунды")
	w.base = "bow"
	w.forge = "pierce"
	for target in targets:
		target.hp = 10000
	host.skills.bolt(1, Vector2.RIGHT, 120, 1, 0, 0, "arrow")
	check(targets[0].hp < 10000 and targets[1].hp < 10000 and targets[2].hp == 10000, "Снаряд пробивает одну цель")
	e.phase = "ring"
	w.forge = "silence"
	host.skills.bolt(1, Vector2.RIGHT, 120, 1, 0, 0, "arrow")
	check(e.phase == "", "Слабый снаряд прерывает звон")
	return true


func rewards() -> bool:
	var at := Sites.MINE_EXIT
	var away := at + Vector2(500, 0)
	host.players = {1: player(1, at), 2: player(2, away), 3: player(3, away),
		4: player(4, away + Vector2(10, 0)), 5: player(5, away + Vector2(95, 0))}
	var e := {"kind": "warden", "pos": at, "max_hp": 1600}
	host.players[4].hp = 0
	host.talents.begin_revive(3)
	host.mine.damage(2, e, 12)
	var reward = host.rewards
	var party: Array = reward.participants(e, 1)
	check(party.size() == 3 and 1 in party and 2 in party and 3 in party, "В радиусе, удалённый боец и поднятие союзника")
	var items := root.get_node("Items")
	var helper: Dictionary = host.players[3]
	for i in items.bag_capacity(helper):
		helper.inv.append(items.make("sword", 0, "", false))
	reward.distribute(e, party)
	for pid in [1, 2]:
		check(host.players[pid].inv.map(func(it): return it.base) == ["bell_tongue", "recipe_scrap"], "Два личных предмета")
	check(reward.reservations.size() == 2 and host.players[5].inv.is_empty(), "Полная сумка и посторонний герой")
	for lid in reward.reservations:
		var lock: Dictionary = reward.reservations[lid]
		check(reward.visible(lid, 2).is_empty() and reward.visible(lid, 3).size() == 3, "Личный предмет видит только владелец")
		check(host.loots[lid].pos == helper.pos and lock.until - Time.get_ticks_msec() > 59000, "60 секунд у ног спасателя")
		host.players[1].pos = helper.pos
		host.pickup(lid)
		check(host.loots.has(lid), "Хост отклонил чужой подбор")
	reward.equipment(items.make("sword", 2, "", false), away, party)
	var rare_id: int = host.next_id
	var first: Dictionary = reward.reservations[rare_id]
	reward.equipment(items.make("bow", 2, "", false), away, party)
	check(first.hid != reward.reservations[host.next_id].hid, "Редкие вещи идут по очереди")
	var other: int = party[1]
	check(reward.visible(rare_id, other)[1].reserved_for == host.players[party[0]].name, "Над вещью имя владельца")
	check(not reward.allowed(rare_id, other, first.until - 1) and reward.allowed(rare_id, other, first.until), "Граница 30 секунд")
	check(first.until - Time.get_ticks_msec() > 29000, "Редкая вещь защищена 30 секунд")
	reward.tick(first.until + 60000)
	check(reward.reservations.is_empty() and not reward.visible(rare_id, other)[1].has("reserved_for"), "После срока вещь общая")
	return true



func _run() -> void:
	var save := root.get_node("Save")
	var original: String = save.WORLD_PATH
	save.WORLD_PATH = save.ROOT + "test-mine-%d.json" % Time.get_ticks_usec()
	host = load("res://scripts/host_logic.gd").new()
	host.game = LocalGame.new()
	root.add_child(host)
	host.set_process(false)
	host.eco = load("res://scripts/host_economy.gd").new()
	host.eco.host = host
	host.add_child(host.eco)
	host.players[1] = player(1, Sites.CAMPS.ford)
	check(encounters(), "Сценарий encounters завершён")
	check(quest(), "Сценарий quest завершён")
	check(forge(), "Сценарий forge завершён")
	check(properties(), "Боевые свойства проверены")
	check(rewards(), "Сценарий rewards завершён")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save.WORLD_PATH))
	save.WORLD_PATH = original
	host.free()
	if failures == 0:
		print("OK: шахта — %d проверок" % checks)
	quit(int(failures > 0))
