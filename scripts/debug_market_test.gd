extends RefCounted
## Сетевой сценарий рынка: размещение через окно, подтверждение покупки и выплата.

var game
var tester
var done := {}
var uid := ""
var serial := 0
var seller_before := 0
var buyer_before := 0
var deposited := false
var purchased := false
var collected := false
var next_search := 0.0


## Выполняет шаг один раз.
func once(key: String) -> bool:
	if done.has(key):
		return false
	done[key] = true
	return true


## Находит доску города в общем списке взаимодействий.
func board() -> Dictionary:
	return World.zones.interact.filter(func(spot): return spot.kind == "market")[0]


## Открывает окно тем же способом, что и взаимодействие с доской.
func open_market() -> void:
	var spot := board()
	for i in game.interact.spots.size():
		if game.interact.spots[i].kind == "market":
			game.open_spot = i
			break
	game.ui.shop.open("market", spot)


## Продолжает сценарий после проверки обычного боя.
func step(time: float) -> void:
	if time < 22.0:
		return
	if game.is_host:
		host_step(time)
	else:
		guest_step(time)
	if time > 33.0 and once("deadline"):
		if (game.is_host and not collected) or (not game.is_host and not purchased):
			push_error("[autotest] рынок: сценарий не завершён")


## Хост размещает вещь и забирает заработанные монеты.
func host_step(time: float) -> void:
	var peer := -1
	for pid in game.host.players:
		if pid != game.my_id:
			peer = pid
			break
	if peer == -1:
		return
	var market = game.host.market
	var seller: Dictionary = game.host.players[game.my_id]
	if once("post"):
		var spot := board()
		var point := Vector2(spot.x, spot.y)
		game.my_pos = point + Vector2(-8, 12)
		seller.pos = game.my_pos
		seller.coins = 5000
		seller.gifts = []
		var buyer: Dictionary = game.host.players[peer]
		buyer.coins = 5000
		buyer.gifts = []
		game.host.talents.travel(peer, point + Vector2(8, 12))
		game.host._send_self(peer)
		game.host.serial += 1
		Save.store_world({"serial": game.host.serial})
		var item := Items.make("sword", 4, "Рынок: автотест", false)
		item.serial = game.host.serial
		uid = item.uid
		serial = item.serial
		seller.inv.append(item)
		seller_before = int(seller.coins)
		game.host._send_self(game.my_id)
		open_market()
		game.ui.market.select_item(item)
		game.ui.market.price.get_line_edit().text = "1000"
		game.ui.market.price.get_line_edit().text_changed.emit("1000")
		await game.get_tree().create_timer(0.2).timeout
		tester._shot("13_market_sell")
		game.ui.market.post_button.pressed.emit()
		deposited = market.lots.values().any(func(lot): return lot.item.uid == uid)
		if not deposited or seller.coins != 4980:
			push_error("[autotest] рынок: размещение не состоялось")
		print("[autotest] рынок продавец до %d, после размещения %d, залог 20" % [seller_before, seller.coins])
	if deposited and market.history.any(func(entry): return entry.item.uid == uid) and once("collect"):
		var before := int(seller.coins)
		game.ui.market.set_tab(2)
		game.ui.market.collect()
		collected = int(seller.coins) == before + 950
		if not collected:
			push_error("[autotest] рынок: выплата продавцу не совпала")
		print("[autotest] рынок продавец до выплаты %d, после %d, комиссия 50" % [before, seller.coins])
	if collected and time > 28.0 and once("shot"):
		tester._shot("15_market_payout")


## Гость ищет лот и нажимает подтверждение покупки.
func guest_step(time: float) -> void:
	var spot := board()
	if game.my_pos.distance_to(Vector2(spot.x, spot.y)) > 60.0:
		return
	if once("open"):
		open_market()
	var state: Dictionary = game.client_market.data
	if not purchased and not done.has("buy") and time >= next_search:
		next_search = time + 0.5
		for lot in state.get("lots", []):
			if lot.item.get("finder") == "Рынок: автотест":
				uid = lot.item.uid
				serial = int(lot.item.serial)
				buyer_before = int(game.me.coins)
				game.ui.market.ask_buy(lot)
				if not game.ui.market.confirmation.visible:
					push_error("[autotest] рынок: нет подтверждения покупки")
				done.buy = true
				confirm_after_render()
				break
		if not done.has("buy"):
			game.ui.market.find()
	if done.has("buy") and not purchased:
		for item in game.me.inv:
			if item.uid == uid:
				purchased = int(game.me.coins) == buyer_before - 1000 and int(item.serial) == serial
				if not purchased:
					push_error("[autotest] рынок: монеты или серийный номер не совпали")
				print("[autotest] рынок покупатель до %d, после %d, серийный номер %d" % [buyer_before, game.me.coins, item.serial])
				tester._shot("14_market_buy")
				break


## Даёт кадр окну подтверждения и нажимает настоящую кнопку.
func confirm_after_render() -> void:
	await game.get_tree().create_timer(0.2).timeout
	tester._shot("14_market_confirm")
	game.ui.market.confirm_button.pressed.emit()
