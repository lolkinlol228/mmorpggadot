extends SceneTree

const Quest := preload("res://scripts/mine_quest.gd")
const Sites := preload("res://scripts/adventure_sites.gd")

class LocalGame:
	extends RefCounted
	var my_id := 1
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


func encounters() -> void:
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


func quest() -> void:
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


func forge() -> void:
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
	encounters()
	quest()
	forge()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save.WORLD_PATH))
	save.WORLD_PATH = original
	host.free()
	if failures == 0:
		print("OK: шахта — %d проверок" % checks)
	quit(int(failures > 0))
