extends RefCounted
## Рынок хоста: залоги, продажи, поиск, возвраты и выплаты отсутствующим героям.

const MAX_LOTS := 8
const MAX_PRICE := 99999999
const PAGE_SIZE := 20
const LIFETIME := 48 * 60 * 60
const WALLET_MAX := 999999999

var host
var lots := {}
var payouts := {}
var returns := {}
var history: Array = []
var world_path := Save.WORLD_PATH
var next_expiry_check := 0.0
var queries := {}


## Время реального мира не зависит от перезапуска игры.
func now() -> int:
	return int(Time.get_unix_time_from_system())


## Проверяет целочисленное число из RPC или JSON.
static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


## Проверяет предмет при чтении сохранённого рынка, сохраняя дополнительные поля.
func valid_item(value: Variant) -> bool:
	return value is Dictionary and not Items.normalize(value).is_empty() and value.get("base") != "coins" and value.get("uid") is String and not value.uid.is_empty()


## Загружает лоты и отложенные награды, включая старый мир без рынка.
func load_state() -> void:
	lots.clear()
	payouts.clear()
	returns.clear()
	history.clear()
	var world := Save.load_world(world_path)
	var saved = world.get("market", {})
	if saved is Dictionary:
		for id in saved:
			var lot = saved[id]
			if not (id is String and lot is Dictionary and lot.get("seller") is String):
				continue
			if not valid_item(lot.get("item")) or not integer(lot.get("price"), 1, MAX_PRICE) or not integer(lot.get("posted_at"), 0, 9007199254740991):
				continue
			var copy: Dictionary = lot.duplicate(true)
			copy.id = id
			copy.price = int(copy.price)
			copy.posted_at = int(copy.posted_at)
			copy.item = restore_item(copy.item)
			var factor = copy.get("seller_factor", 1.0)
			copy.seller_factor = 1.0
			# Доли модификатора сохраняются отдельно от целочисленных денежных сумм.
			if (factor is int or factor is float) and is_finite(float(factor)):
				copy.seller_factor = clampf(float(factor), 0.0, 100.0)
			lots[id] = copy
	var pending = world.get("market_payouts", {})
	if pending is Dictionary:
		for seller in pending:
			if seller is String and integer(pending[seller], 0, 9007199254740991):
				payouts[seller] = int(pending[seller])
	var items = world.get("market_returns", {})
	if items is Dictionary:
		for seller in items:
			if seller is String and items[seller] is Array:
				returns[seller] = []
				for item in items[seller]:
					if valid_item(item):
						returns[seller].append(restore_item(item))
	var log = world.get("market_log", [])
	if log is Array:
		for entry in log:
			if entry is Dictionary and valid_item(entry.get("item")) and integer(entry.get("price"), 1, MAX_PRICE) and integer(entry.get("time"), 0, 9007199254740991):
				var restored: Dictionary = entry.duplicate(true)
				restored.item = restore_item(restored.item)
				history.append(restored)
	history = history.slice(maxi(0, history.size() - 50))
	expire()


## Обновляет только ключи рынка, сохраняя серийный счётчик и прочие данные мира.
func persist() -> bool:
	return Save.store_world(snapshot(), world_path)


## Делает снимок для сохранения и отката неудавшейся записи.
func snapshot() -> Dictionary:
	return {"market": lots.duplicate(true), "market_payouts": payouts.duplicate(true),
		"market_returns": returns.duplicate(true), "market_log": history.duplicate(true)}


## Возвращает предыдущий снимок при ошибке записи.
func restore(state: Dictionary) -> void:
	lots = state.market
	payouts = state.market_payouts
	returns = state.market_returns
	history = state.market_log


## Проверяет истечение срока раз в секунду, включая время отсутствия хоста.
func tick(delta: float) -> void:
	next_expiry_check -= delta
	if next_expiry_check <= 0.0:
		next_expiry_check = 1.0
		expire()


## Перекладывает просроченные вещи в отложенные возвраты.
func expire() -> bool:
	var previous := snapshot()
	var changed := false
	for id in lots.keys():
		var lot: Dictionary = lots[id]
		if now() - int(lot.posted_at) >= LIFETIME:
			var queue: Array = returns.get_or_add(lot.seller, [])
			queue.append(lot.item.duplicate(true))
			lots.erase(id)
			changed = true
	if changed and not persist():
		restore(previous)
		return false
	return true


## Залог округляется вверх, чтобы малые цены тоже имели стоимость размещения.
static func deposit(price: int) -> int:
	return maxi(1, int((price + 49) / 50))


## Комиссия удерживается с продавца и учитывает дары обеих сторон.
static func commission(price: int, seller_factor: float, buyer_factor: float) -> int:
	var rate := maxf(0.01, 0.05 * seller_factor * buyer_factor)
	return mini(price, maxi(1, ceili(price * minf(1.0, rate) - 0.0000001)))


## Принимает RPC только от живого героя у рыночной доски.
func handle(op: String, arg: Dictionary) -> void:
	var pid: int = host._sender()
	var p = host.players.get(pid)
	if not host.can_act(p) or not host.eco._near(p, "market"):
		return
	if not expire():
		host._to(pid, "c_announce", ["Рынок временно недоступен: не удалось сохранить мир.", Color.ORANGE])
		return
	if op == "search":
		if valid_query(arg):
			queries[pid] = arg.duplicate()
			host._to(pid, "c_market", [page(pid, arg)])
		return
	if int(p.trade) != 0 or p.has("work"):
		host._to(pid, "c_announce", ["Завершите обмен или работу перед сделкой.", Color.ORANGE])
		return
	var previous := snapshot()
	var inventory: Array = p.inv.duplicate(true)
	var coins := int(p.coins)
	var outcome := {}
	match op:
		"post":
			if arg.get("uid") is String and arg.uid.length() <= 80 and integer(arg.get("price"), 1, MAX_PRICE):
				outcome = post(pid, arg.uid, int(arg.price))
		"buy", "cancel":
			if arg.get("id") is String and arg.id.length() <= 80:
				outcome = buy(pid, arg.id) if op == "buy" else cancel(pid, arg.id)
		"collect": outcome = collect(pid)
	if outcome.is_empty():
		return
	if outcome.ok and not persist():
		restore(previous)
		p.inv = inventory
		p.coins = coins
		outcome = result(false, "Не удалось сохранить сделку. Попробуйте ещё раз.")
	if outcome.ok:
		host._send_self(pid)
		if outcome.has("seller"):
			notify_seller(outcome.seller, outcome.message)
	host._to(pid, "c_announce", [outcome.message, Color.WHEAT if outcome.ok else Color.ORANGE])
	host._to(pid, "c_market", [page(pid, queries.get(pid, {}))])


## Возвращает понятный итог действия для RPC и тестов.
func result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}


## Извлекает вещь из сумки в залог рынка.
func post(pid: int, uid: String, price: int) -> Dictionary:
	var p: Dictionary = host.players[pid]
	if price < 1 or price > MAX_PRICE:
		return result(false, "Недопустимая цена.")
	var index: int = host._find(p.inv, uid)
	if index < 0 or p.inv[index].base == "coins":
		return result(false, "Вещь должна находиться в сумке.")
	for item in p.equip.values():
		if item is Dictionary and item.get("uid") == uid:
			return result(false, "Сначала снимите вещь.")
	for trade in host.trader.trades.values():
		for offered in trade.offer.values():
			if uid in offered:
				return result(false, "Вещь участвует в обмене.")
	for lot in lots.values():
		if lot.item.uid == uid:
			return result(false, "Вещь уже выставлена.")
	var count := 0
	for lot in lots.values():
		count += int(lot.seller == p.name)
	if count >= MAX_LOTS:
		return result(false, "Можно выставить не больше 8 лотов.")
	var pledge := deposit(price)
	if int(p.coins) < pledge:
		return result(false, "Не хватает монет для залога.")
	var id := Items.new_uid()
	var item: Dictionary = p.inv[index].duplicate(true)
	lots[id] = {"id": id, "seller": p.name, "item": item, "price": price, "posted_at": now(),
		"seller_factor": host.gifts.factor(pid, "sell_price")}
	p.inv.remove_at(index)
	p.coins -= pledge
	return result(true, "Выставлено: %s. Залог %s." % [Items.display_name(item), Items.format_coins(pledge)])


## Покупает один актуальный лот без ожиданий между проверками и изменением состояния.
func buy(pid: int, id: String) -> Dictionary:
	var p: Dictionary = host.players[pid]
	if not lots.has(id):
		return result(false, "Лот уже куплен или снят.")
	var lot: Dictionary = lots[id]
	if lot.seller == p.name:
		return result(false, "Нельзя купить свой лот.")
	if now() - int(lot.posted_at) >= LIFETIME:
		return result(false, "Срок лота истёк.")
	if int(p.coins) < int(lot.price):
		return result(false, "Не хватает монет.")
	if p.inv.size() >= Items.bag_capacity(p):
		return result(false, "Сумка полна.")
	var fee := commission(int(lot.price), float(lot.seller_factor), host.gifts.factor(pid, "buy_price"))
	var net := int(lot.price) - fee
	if int(payouts.get(lot.seller, 0)) > 9007199254740991 - net:
		return result(false, "Кошелёк выплат продавца переполнен.")
	p.inv.append(lot.item.duplicate(true))
	p.coins -= int(lot.price)
	payouts[lot.seller] = int(payouts.get(lot.seller, 0)) + net
	lots.erase(id)
	history.append({"item": lot.item.duplicate(true), "price": int(lot.price), "time": now()})
	if history.size() > 50:
		history.pop_front()
	var response := result(true, "Продано: %s за %s" % [Items.display_name(lot.item), Items.format_coins(lot.price)])
	response.seller = lot.seller
	return response


## Снимает свой лот, возвращая ту же вещь вместе с её uid и серийным номером.
func cancel(pid: int, id: String) -> Dictionary:
	var p: Dictionary = host.players[pid]
	var lot: Dictionary = lots.get(id, {})
	if lot.is_empty() or lot.seller != p.name:
		return result(false, "Лот не найден.")
	if p.inv.size() >= Items.bag_capacity(p):
		return result(false, "Освободите место в сумке.")
	p.inv.append(lot.item.duplicate(true))
	lots.erase(id)
	return result(true, "Лот снят, вещь возвращена в сумку.")


## Забирает доступные монеты и столько возвратов, сколько помещается в сумку.
func collect(pid: int) -> Dictionary:
	var p: Dictionary = host.players[pid]
	var money := mini(int(payouts.get(p.name, 0)), maxi(0, WALLET_MAX - int(p.coins)))
	p.coins += money
	payouts[p.name] = int(payouts.get(p.name, 0)) - money
	var queue: Array = returns.get_or_add(p.name, [])
	var received := 0
	while not queue.is_empty() and p.inv.size() < Items.bag_capacity(p):
		p.inv.append(queue.pop_front())
		received += 1
	return result(true, "Получено: %s и %d вещей. Остальное хранится у доски." % [Items.format_coins(money), received])


## Проверяет фильтры и страницы до преобразования входных данных.
func valid_query(query: Dictionary) -> bool:
	var text = query.get("text", "")
	var slot = query.get("slot", "")
	if not (text is String and text.length() <= 80 and slot is String):
		return false
	if slot not in ["", "weapon", "head", "body", "feet", "offhand", "use"]:
		return false
	return integer(query.get("rarity", -1), -1, 5) and integer(query.get("page", 0), 0, 1000000) and query.get("descending", false) is bool


## Отдаёт только одну страницу поиска, свои лоты и сводку выплат.
func page(pid: int, query: Dictionary) -> Dictionary:
	var p: Dictionary = host.players[pid]
	var found: Array = []
	var own: Array = []
	var text := str(query.get("text", "")).to_lower().strip_edges()
	var slot := str(query.get("slot", ""))
	var rarity := int(query.get("rarity", -1))
	for lot in lots.values():
		var visible: Dictionary = lot.duplicate(true)
		visible.fee = commission(int(lot.price), float(lot.seller_factor), host.gifts.factor(pid, "buy_price"))
		visible.last_price = last_price(lot.item)
		if lot.seller == p.name:
			own.append(visible)
		if (slot == "" or Items.slot_of(lot.item) == slot) and (rarity == -1 or int(lot.item.rarity) == rarity) and (text.is_empty() or text in Items.display_name(lot.item).to_lower()):
			found.append(visible)
	found.sort_custom(func(a, b):
		if int(a.price) == int(b.price):
			return str(a.id) < str(b.id)
		return int(a.price) > int(b.price) if query.get("descending", false) else int(a.price) < int(b.price))
	var pages := maxi(1, ceili(found.size() / float(PAGE_SIZE)))
	var number := mini(int(query.get("page", 0)), pages - 1)
	return {"lots": found.slice(number * PAGE_SIZE, (number + 1) * PAGE_SIZE), "page": number, "pages": pages,
		"own": own, "payout": int(payouts.get(p.name, 0)), "returns": returns.get(p.name, []).size(),
		"seller_factor": host.gifts.factor(pid, "sell_price"), "history": history.duplicate(true), "query": query.duplicate()}


## Последняя продажа той же базы и редкости.
func last_price(item: Dictionary) -> int:
	return price_from_history(item, history)


## Единый поиск последней цены для сервера и окна продажи.
static func price_from_history(item: Dictionary, entries: Array) -> int:
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if entry.item.base == item.base and int(entry.item.rarity) == int(item.rarity):
			return int(entry.price)
	return 0


## Уведомляет продавца, если он сейчас в игре.
func notify_seller(seller: String, message: String) -> void:
	for pid in host.players:
		if host.players[pid].name == seller and host.players[pid].hp > 0:
			host._to(pid, "c_announce", [message, Color.WHEAT])


## Восстанавливает числовые типы JSON без потери дополнительных полей вещи.
func restore_item(raw: Dictionary) -> Dictionary:
	var restored := raw.duplicate(true)
	var normalized := Items.normalize(raw)
	for key in normalized:
		if restored.has(key):
			restored[key] = normalized[key]
	return restored
