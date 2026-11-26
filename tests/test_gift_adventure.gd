extends SceneTree
## Проверяет игровые цепочки новых даров через реальные подсистемы хоста.

const Gifts := preload("res://scripts/gifts.gd")
const Sites := preload("res://scripts/adventure_sites.gd")

class LocalGame:
	extends RefCounted
	var my_id := 1
	var hits := 0
	var elite := false
	var moves := 0
	func c_announce(_message: String, _color: Color) -> void: pass
	func c_self(_data: Dictionary) -> void: pass
	func c_hp(_pid: int, _hp: int, _max_hp: int, _damage: int) -> void: pass
	func c_world_pulse(_point: Vector2, _radius: float, _color: Color) -> void: pass
	func c_enemy_hit(_eid: int, _hp: int, _dmg: int, _crit: bool) -> void: hits += 1
	func c_enemy_elite(_eid: int, _hp: int, _max_hp: int) -> void: elite = true
	func c_teleport(_position: Vector2, _blink: bool) -> void: moves += 1
	func c_enemy_died(_eid: int) -> void: pass

var host
var local := LocalGame.new()
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, detail: String) -> void:
	if not condition:
		printerr(detail)
		failures += 1


## Создаёт персонажа через тот же слой миграции, что и игра.
func player(gifts: Array, pid: int, position: Vector2) -> Dictionary:
	var p: Dictionary = root.get_node("Save").sanitize_char({"name": "Проверка", "gifts": gifts, "coins": 200})
	p.merge({"peer_id": pid, "hp": 100, "max_hp": 100, "pos": position, "buffs": {}, "cds": {}, "res": 100.0, "res_max": 100})
	return p


## Проверяет время работы, прерывание и начисление профильного опыта.
func professions() -> void:
	var craft = host.professions
	var workshop: Dictionary = craft.spots[11]
	var p := player(["miner", "born_miner", "careful", "nimble_fingers", "steady_craft"], 1, Vector2(workshop.x, workshop.y))
	host.players = {1: p}
	expect(craft.near_workshop(p), "Мастерская доступна")
	var materials: Dictionary = p.materials
	craft.start_gather(1, "ore", "sample", 1, p.pos)
	expect(p.work.done - p.work.started < 2200, "Шахтёр уменьшает время добычи")
	p.work.done = 0
	craft.update()
	expect(materials.ore == 1 and is_equal_approx(p.tools.wear, 0.7), "Добыча руды и износ инструмента")
	expect(is_equal_approx(p.professions.mining, 15.0), "Профильный опыт добычи")
	materials.ore = 7
	craft.craft(1, "sword")
	expect(p.work.done - p.work.started < 3000, "Дар ускорил крафт")
	p.work.done = 0
	craft.update()
	expect(p.inv.size() == 1 and p.inv[0].base == "sword" and materials.ore == 4, "Меч создаётся со списанием трёх руд")
	p.gifts = ["transmuter", "recycler"]
	materials.ore = 9
	craft.transmute(1, "ore")
	expect(materials.ore == 4 and materials.rich_ore == 1, "Трансмутация списывает пять ресурсов")
	craft.salvage(1, p.inv[0].uid)
	expect(materials.ore >= 6 and p.inv.is_empty(), "Разбор с даром возвращает удвоенные ресурсы")
	p.gifts = ["endless_tools"]
	p.tools.wear = 10.0
	craft.start_gather(1, "ore", "deep", 2, p.pos)
	expect(p.has("work"), "Вечный инструмент добывает ресурс второго тира")
	p.work.done = 0
	craft.update()
	expect(is_equal_approx(p.tools.wear, 10.0) and materials.rich_ore == 2, "Неуязвимый инструмент не расходуется")
	for spot in craft.spots:
		var world := root.get_node("World")
		expect(not world.blocked(Vector2(spot.x, spot.y), 9.0), "Точка доступна: " + spot.label)


## Проверяет немедленные, периодические и постоянные эффекты в бою.
func battle() -> void:
	var p := player(["last_stand", "arrow_catcher", "beast_friend", "vampire_curse", "devourer"], 1, Sites.CAVE.position + Vector2(70, 20))
	host.players = {1: p}
	var e := {"id": 7, "kind": "undead", "hp": 58, "max_hp": 58, "pos": p.pos + Vector2(42, 0)}
	host.enemies = {7: e}
	host._hurt_player(1, 20, 7, "ranged")
	expect(p.hp == 82, "Ловец стрел уменьшает дальний урон")
	p.hp = 30
	host.gifts.health_events(1, {})
	expect(not p.has("invuln_until"), "Последний рубеж не срабатывает на 30% HP")
	p.hp = 19
	host.gifts.health_events(1, {})
	expect(p.invuln_until > host.gifts.now() and p.gift_last_stand_at - host.gifts.now() > 89000, "Последний рубеж срабатывает ниже 20% и уходит на 90 с")
	p.gifts = ["undead_bane", "cave_dweller", "cursed_chosen", "second_heart", "devourer"]
	expect(is_equal_approx(host.gifts.mod(1, "dmg", {"enemy": e}), 0.38), "Условия пещеры и нежити складываются")
	var items := root.get_node("Items")
	host.enemy_gift_ai.target(e, items.ENEMIES.undead)
	expect(e.elite and local.elite and e.max_hp == 87, "Проклятие создаёт элитного противника")
	var item: Dictionary = items.make("sword", 1, "", false)
	host.gifts.effect(1, "golden_item", 1.0, {"item": item})
	expect(items.normalize(item).golden and items.value(item) == 108, "Золотой предмет сохраняет повышенную стоимость")
	p.hp = 0
	host.gifts.health_events(1, {})
	expect(p.hp == 40 and p.gift_dungeon_revived, "Второе сердце воскрешает на месте")
	p.hp = 0
	host.gifts.health_events(1, {})
	expect(p.hp == 0, "Второе сердце срабатывает раз за посещение")
	var ctx := {}
	host.talents.killed(1, {"kind": "golem"}, ctx)
	var save := root.get_node("Save")
	expect(save.sanitize_char(p).gift_state.devourer == 1, "Пожиратель сохраняет победу над боссом")


## Проверяет парное действие, выбор умения и копирование дара.
func party() -> void:
	var camp: Vector2 = Sites.CAMPS.ford
	var p := player(["medic", "reborn", "copycat", "world_wanderer"], 1, camp)
	var ally := player(["inspiring", "healing_aura"], 2, camp + Vector2(20, 0))
	host.players = {1: p, 2: ally}
	p.hp = 80
	host.talents.tick(2, host.gifts.now())
	expect(p.hp == 81 and is_equal_approx(host.gifts.mod(1, "dmg"), 0.08), "Групповые ауры лечат и усиливают союзника")
	host.talents.action(1, "cross", "fireball")
	expect("fireball" in root.get_node("Rules").class_skills(p), "Чужое умение добавлено на панель")
	host.talents.action(1, "copy", "")
	expect("inspiring" in Gifts.ids(p) and "inspiring" not in p.gifts, "Дар копируется временно")
	ally.hp = 0
	host.talents.begin_revive(1)
	expect(p.rescue.until - p.rescue.started == 2000, "Медик поднимает союзника за две секунды")
	p.rescue.until = 0
	host.talents.update_revive(1)
	expect(ally.hp == 40, "Союзник поднят на месте")
	host.talents.action(1, "recall", "east")
	expect(local.moves == 0, "Переход в непосещённый город отклонён")
	p.visited.east = true
	host.talents.action(1, "recall", "east")
	expect(local.moves == 1 and p.pos.distance_to(Sites.CAMPS.east) < 50.0, "Переход в посещённое поселение")


func _run() -> void:
	var script := load("res://scripts/host_logic.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("Хост не компилируется")
		quit(1)
		return
	host = script.new()
	host.game = local
	host.set_process(false)
	root.add_child(host)
	host.set_process(false)
	host.eco = load("res://scripts/host_economy.gd").new()
	host.eco.host = host
	host.add_child(host.eco)
	professions()
	battle()
	party()
	host.free()
	if failures == 0:
		print("OK: добыча, ремёсла, пещера, редкие эффекты, спасение союзников и переходы.")
	else:
		printerr("Ошибок: %d" % failures)
	quit(0 if failures == 0 else 1)
