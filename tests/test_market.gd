extends SceneTree
## Рынок проверяется через входной обработчик RPC и настоящий файл мира.

class Factors:
	extends RefCounted
	var values := {}
	func factor(pid: int, key: String) -> float:
		return float(values.get(pid, {}).get(key, 1.0))

class Trades:
	extends RefCounted
	var trades := {}

class MarketHost:
	extends Node
	var players := {}
	var sender := 1
	var gifts := Factors.new()
	var trader := Trades.new()
	var eco
	var messages: Array = []
	var responses := {}
	func _sender() -> int:
		return sender
	func can_act(p) -> bool:
		return p != null and int(p.hp) > 0
	func _find(items: Array, uid: String) -> int:
		for i in items.size():
			if items[i].uid == uid:
				return i
		return -1
	func _send_self(_pid: int) -> void:
		pass
	func _to(pid: int, method: StringName, args: Array = []) -> void:
		if method == "c_market":
			responses[pid] = args[0]
		elif method == "c_announce":
			messages.append(args[0])

var host := MarketHost.new()
var market
var failures := 0
var checks := 0
var path := ""
var test_serial := 731


## Дожидается автозагрузок перед компиляцией модулей рынка.
func _initialize() -> void:
	call_deferred("_run")


## Накапливает ошибки, чтобы показать все нарушенные условия.
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr(message)


## Герои стоят у настоящей рыночной доски.
func player(name: String, money: int = 10000) -> Dictionary:
	var world := root.get_node("World")
	var board: Dictionary = world.zones.interact.filter(func(s): return s.kind == "market")[0]
	return {"name": name, "coins": money, "inv": [], "equip": {}, "trade": 0, "hp": 100,
		"pos": Vector2(board.x, board.y), "gifts": []}


## Выполняет запрос тем же способом, что и сетевой фасад.
func act(pid: int, operation: String, args: Dictionary = {}) -> void:
	host.sender = pid
	market.handle(operation, args)


## Создаёт вещь с сохранённым дополнительным полем.
func item(base: String = "sword", rarity: int = 2) -> Dictionary:
	var value: Dictionary = root.get_node("Items").make(base, rarity, "Проверка", false)
	value.serial = 42
	value.market_test = "полный словарь"
	return value


## Подготавливает изолированное состояние для сценария.
func reset() -> void:
	market.lots.clear()
	market.payouts.clear()
	market.returns.clear()
	market.history.clear()
	host.players = {1: player("Продавец"), 2: player("Покупатель"), 3: player("Второй покупатель")}
	host.gifts.values.clear()
	host.trader.trades.clear()
	host.responses.clear()
	host.messages.clear()
	market.persist()


## Проверяет залог, комиссию, офлайн-продавца и защиту от повторной покупки.
func sale() -> void:
	reset()
	var sword := item()
	host.players[1].inv.append(sword)
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.size() == 1 and host.players[1].inv.is_empty(), "Предмет перемещён в рынок")
	check(host.players[1].coins == 9980, "Залог составляет 2%")
	var id: String = market.lots.keys()[0]
	act(1, "buy", {"id": id})
	check(market.lots.has(id) and host.players[1].coins == 9980, "Свой лот купить нельзя")
	host.players[2].coins = 999
	act(2, "buy", {"id": id})
	check(host.players[2].inv.is_empty() and market.lots.has(id), "Покупка без монет отклонена")
	host.players[2].coins = 10000
	var offline: Dictionary = host.players[1]
	host.players.erase(1)
	act(2, "buy", {"id": id})
	check(host.players[2].coins == 9000 and host.players[2].inv.size() == 1 and market.lots.is_empty(), "Покупка списала цену и удалила лот")
	check(host.players[2].inv[0] == sword and host.players[2].inv[0].serial == 42, "Сохранены uid, serial и весь словарь вещи")
	check(market.payouts["Продавец"] == 950, "Комиссия 5% и выплата отсутствующему продавцу")
	act(3, "buy", {"id": id})
	check(host.players[3].coins == 10000 and host.players[3].inv.is_empty(), "Повторная покупка отклонена")
	host.players[1] = offline
	act(1, "collect")
	act(1, "collect")
	check(offline.coins == 10930 and market.payouts["Продавец"] == 0, "Выплату можно получить один раз")
	check(market.history.size() == 1 and market.last_price(sword) == 1000, "Записана последняя цена")
	market.load_state()
	check(market.history.size() == 1 and market.payouts["Продавец"] == 0, "Мир загрузил историю и получение выплаты")
	check(root.get_node("Save").load_world(path).serial == test_serial, "Рыночные записи сохраняют серийный счётчик")


## Проверяет ограничения кошелька, сумки, расстояния и входных аргументов.
func restrictions() -> void:
	reset()
	var sword := item()
	host.players[1].inv.append(sword)
	var before: Dictionary = market.snapshot()
	for amount in [0, -1, 100000000, 1.5, "100", NAN, INF, {}, []]:
		act(1, "post", {"uid": sword.uid, "price": amount})
	check(market.snapshot() == before and host.players[1].coins == 10000, "Недопустимые цены отклонены")
	act(1, "post", {"uid": {}, "price": 100})
	act(1, "buy", {"id": []})
	act(1, "unknown", {})
	act(1, "search", {"rarity": "редкая"})
	act(1, "search", {"page": -1})
	act(1, "search", {"descending": 1})
	check(market.snapshot() == before, "Повреждённые op и arg не меняют состояние")
	host.players[1].pos = Vector2.ZERO
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.is_empty(), "Размещение вдали от рынка запрещено")
	host.players[1].pos = player("").pos
	host.players[1].coins = 0
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.is_empty(), "Без залога лот не создаётся")
	host.players[1].coins = 10000
	host.players[1].equip.weapon = sword
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.is_empty(), "Надетая вещь не выставляется")
	host.players[1].equip.clear()
	host.trader.trades[7] = {"offer": {1: [sword.uid], 2: []}}
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.is_empty(), "Вещь из предложения обмена не выставляется")
	host.trader.trades.clear()
	act(1, "post", {"uid": sword.uid, "price": 1000})
	var id: String = market.lots.keys()[0]
	host.players[2].pos = Vector2.ZERO
	act(2, "buy", {"id": id})
	check(market.lots.has(id), "Покупка вдали от доски отклонена")
	host.players[2].pos = player("").pos
	for i in 24:
		host.players[2].inv.append(item())
	act(2, "buy", {"id": id})
	check(market.lots.has(id) and host.players[2].coins == 10000, "Полная сумка не теряет деньги")
	host.players[2].inv.clear()
	host.players[1].pos = Vector2.ZERO
	act(1, "collect")
	check(host.players[1].coins == 9980, "Получение вдали от доски отклонено")
	host.players[1].pos = player("").pos
	act(2, "cancel", {"id": id})
	check(market.lots.has(id), "Чужой лот снять нельзя")
	act(1, "cancel", {"id": id})
	check(market.lots.is_empty() and host.players[1].inv[0] == sword and host.players[1].coins == 9980, "Снятие возвращает вещь без возврата залога")


## Проверяет 48 часов, лимит лотов и частичный возврат в заполненную сумку.
func expiration() -> void:
	reset()
	for i in 9:
		var sword := item()
		host.players[1].inv.append(sword)
		act(1, "post", {"uid": sword.uid, "price": 100})
	check(market.lots.size() == 8 and host.players[1].inv.size() == 1, "Лимит восемь лотов на героя")
	var id: String = market.lots.keys()[0]
	var sword: Dictionary = market.lots[id].item.duplicate(true)
	market.lots[id].posted_at = market.now() - market.LIFETIME
	market.persist()
	market.load_state()
	check(not market.lots.has(id) and market.returns["Продавец"][0] == sword, "Истёкший во время перезапуска лот возвращается")
	for i in 23:
		host.players[1].inv.append(item())
	act(1, "collect")
	check(market.returns["Продавец"].size() == 1, "Возврат ждёт места в сумке")
	host.players[1].inv.pop_back()
	act(1, "collect")
	check(market.returns["Продавец"].is_empty() and host.players[1].inv.back() == sword, "Освобождённое место позволяет забрать возврат")
	market.lots[market.lots.keys()[0]].posted_at = market.now() - market.LIFETIME
	market.tick(1.1)
	check(market.returns["Продавец"].size() == 1, "Срок проверяется в игровом тике")


## Дары применяются к комиссии, даже если продавец отключился.
func fees() -> void:
	reset()
	host.gifts.values = {1: {"sell_price": 1.3}, 2: {"buy_price": 0.8}}
	var sword := item()
	host.players[1].inv.append(sword)
	act(1, "post", {"uid": sword.uid, "price": 1000})
	var id: String = market.lots.keys()[0]
	market.load_state()
	check(is_equal_approx(market.lots[id].seller_factor, 1.3), "Доля комиссии продавца сохраняется")
	host.players.erase(1)
	act(2, "buy", {"id": id})
	check(market.payouts["Продавец"] == 948, "Комиссия учитывает дары обеих сторон")
	check(market.commission(1000, 0.0, 0.0) == 10 and market.deposit(1) == 1, "Нижний предел комиссии 1%, залога один медяк")


## Поиск выполняется по всем лотам с пагинацией и журналом из 50 сделок.
func search_and_history() -> void:
	reset()
	for i in 61:
		var sword := item("sword" if i % 2 == 0 else "robe", i % 6)
		var id := "lot_%02d" % i
		market.lots[id] = {"id": id, "seller": "Мастер%d" % i, "item": sword, "price": 100 + i, "posted_at": market.now(), "seller_factor": 1.0}
	var query := {"text": "меч", "slot": "weapon", "rarity": -1, "page": 0, "descending": true}
	act(2, "search", query)
	var response: Dictionary = host.responses[2]
	check(response.lots.size() == 20 and response.pages == 2 and response.lots[0].price == 160, "Поиск и сортировка до нарезки страницы")
	query.page = 1
	act(2, "search", query)
	check(host.responses[2].lots.size() == 11, "Вторая страница поиска")
	query.rarity = 0
	act(2, "search", query)
	check(host.responses[2].lots.size() == 11 and host.responses[2].page == 0, "Фильтр редкости и корректировка страницы")
	host.players[2].coins = 100000
	for id in market.lots.keys():
		act(2, "buy", {"id": id})
		host.players[2].inv.clear()
	check(market.history.size() == 50, "Журнал ограничен последними 50 сделками")


## Ошибка записи отменяет все изменения конкретной сделки.
func disk_failure() -> void:
	reset()
	var sword := item()
	host.players[1].inv.append(sword)
	var saved_path: String = market.world_path
	market.world_path = "user://missing-market-%d/world.json" % Time.get_ticks_usec()
	act(1, "post", {"uid": sword.uid, "price": 1000})
	check(market.lots.is_empty() and host.players[1].coins == 10000 and host.players[1].inv[0] == sword, "Сбой записи отменяет размещение и залог")
	market.world_path = saved_path
	act(1, "post", {"uid": sword.uid, "price": 1000})
	var id: String = market.lots.keys()[0]
	var before: Dictionary = market.snapshot()
	market.world_path = "user://missing-market-%d/world.json" % Time.get_ticks_usec()
	act(2, "buy", {"id": id})
	check(host.players[2].coins == 10000 and host.players[2].inv.is_empty() and market.snapshot() == before, "Сбой записи отменяет покупку и выплату")
	act(1, "cancel", {"id": id})
	check(host.players[1].inv.is_empty() and market.lots.has(id), "Сбой записи отменяет снятие")
	market.payouts["Продавец"] = 950
	market.returns["Продавец"] = [item()]
	before = market.snapshot()
	act(1, "collect")
	check(host.players[1].coins == 9980 and host.players[1].inv.is_empty() and market.snapshot() == before, "Сбой записи отменяет получение монет и возвратов")
	market.lots[id].posted_at = market.now() - market.LIFETIME
	before = market.snapshot()
	check(not market.expire() and market.snapshot() == before, "Сбой записи не теряет истекающий лот")
	market.world_path = saved_path
	market.persist()


## Кошелёк выплат сохраняет непоместившуюся часть и состояние переживает обновление serial.
func persistence() -> void:
	reset()
	var sword := item()
	host.players[1].inv.append(sword)
	act(1, "post", {"uid": sword.uid, "price": 1000})
	var id: String = market.lots.keys()[0]
	var save := root.get_node("Save")
	save.store_world({"serial": test_serial + 1}, path)
	market.load_state()
	check(market.lots.has(id) and market.lots[id].item == sword, "Запись serial сохраняет активные лоты и полную вещь")
	market.payouts["Продавец"] = 950
	host.players[1].coins = market.WALLET_MAX - 10
	act(1, "collect")
	check(host.players[1].coins == market.WALLET_MAX and market.payouts["Продавец"] == 940, "Переполнение кошелька оставляет остаток у доски")
	market.load_state()
	check(market.payouts["Продавец"] == 940 and market.lots.has(id), "Лоты и остаток выплаты переживают перезапуск")
	var world := root.get_node("World")
	var boards: Array = world.zones.interact.filter(func(spot): return spot.kind == "market")
	check(boards.size() == 2, "Есть две доски рынка")
	host.players[1].pos = Vector2(boards[1].x, boards[1].y)
	host.players[1].coins -= 1000
	act(1, "collect")
	check(market.payouts["Продавец"] == 0, "Выплату можно забрать на Пристани")


## Запускает тесты в отдельном файле, сохраняя пользовательский мир.
func _run() -> void:
	root.add_child(host)
	var script := load("res://scripts/host_market.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("Рынок не компилируется")
		quit(1)
		return
	host.eco = load("res://scripts/host_economy.gd").new()
	host.eco.host = host
	host.add_child(host.eco)
	market = script.new()
	market.host = host
	path = "user://test-market-%d.json" % Time.get_ticks_usec()
	market.world_path = path
	root.get_node("Save").store_world({"serial": test_serial}, path)
	market.load_state()
	check(market.lots.is_empty(), "Старый мир без рынка загружается")
	sale()
	restrictions()
	expiration()
	fees()
	search_and_history()
	disk_failure()
	persistence()
	var world := root.get_node("Save")
	world.store_world({"serial": test_serial + 1}, path)
	market.load_state()
	check(world.load_world(path).serial == test_serial + 1 and market.lots.size() == 1, "Обновление серийного счётчика сохраняет рынок")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.free()
	if failures == 0:
		print("OK: рынок — %d проверок, сделки, залог, комиссии, офлайн-выплаты, сроки, поиск и сохранение." % checks)
	else:
		printerr("Ошибок рынка: %d" % failures)
	quit(0 if failures == 0 else 1)
