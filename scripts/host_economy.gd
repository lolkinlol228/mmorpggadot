extends Node
## Экономика на стороне хоста: кошелёк (медяки), стопки предметов, хранилище, торговка,
## зелья, доска заказов. Клиент шлёт h_eco(op, arg); хост проверяет, что игрок стоит рядом
## с нужным объектом, и меняет данные. Всё ценное решается только здесь.

const NEAR := 72.0

var host        # host_logic.gd


func _near(p: Dictionary, kind: String) -> bool:
	for it in World.zones.get("interact", []):
		if it.kind == kind and p.pos.distance_to(Vector2(it.x, it.y)) <= NEAR:
			return true
	return false


## Положить предмет в сумку: монеты — в кошелёк, зелья — в стопку. false, если некуда.
func add_item(p: Dictionary, it: Dictionary) -> bool:
	if it.base == "coins":
		p.coins += int(it.get("count", 1))
		return true
	if Items.is_stack(it):
		var cap: int = Items.BASES[it.base].stack
		for other in p.inv:
			if other.base == it.base and int(other.count) < cap:
				var move := mini(cap - int(other.count), int(it.count))
				other.count = int(other.count) + move
				it.count = int(it.count) - move
				if int(it.count) <= 0:
					return true
	if p.inv.size() >= Items.bag_capacity(p):
		return false
	p.inv.append(it)
	return true


func on_kill(pid: int, kind: String) -> void:
	var p: Dictionary = host.players[pid]
	var changed := false
	for b in Items.BOUNTIES:
		if b.kind == kind:
			p.bounties[b.id] = mini(int(b.need), int(p.bounties.get(b.id, 0)) + 1)
			changed = true
	if changed:
		host._send_self(pid)


func handle(op: String, arg: String) -> void:
	var id: int = host._sender()
	var p = host.players.get(id)
	if p == null or int(p.hp) <= 0 or int(p.trade) != 0:
		return
	var msg := ""
	match op:
		"deposit", "withdraw", "deposit_all":
			if not _near(p, "bank"):
				return
			msg = _bank(p, op, arg)
		"sell", "buy":
			if not _near(p, "shop"):
				return
			msg = _shop(p, op, arg)
		"use":
			msg = _use(p, arg)
		"claim":
			if not _near(p, "board"):
				return
			msg = _claim(p, arg)
	host._send_self(id)
	if msg != "":
		host._to(id, "c_announce", [msg, Color(1, 0.84, 0.45)])


func _bank(p: Dictionary, op: String, uid: String) -> String:
	match op:
		"deposit":
			var i: int = host._find(p.inv, uid)
			if i < 0 or p.bank.size() >= Items.bank_capacity(p):
				return "Хранилище полно." if i >= 0 else ""
			p.bank.append(p.inv[i])
			p.inv.remove_at(i)
		"withdraw":
			var i: int = host._find(p.bank, uid)
			if i < 0:
				return ""
			var it: Dictionary = p.bank[i]
			if not add_item(p, it.duplicate()):
				return "Сумка полна."
			p.bank.remove_at(i)
		"deposit_all":
			var moved := 0
			for it in p.inv.duplicate():
				if it.base == "potion" or p.bank.size() >= Items.bank_capacity(p):
					continue
				p.bank.append(it)
				p.inv.erase(it)
				moved += 1
			return "В хранилище: %d предм." % moved if moved > 0 else ""
	return ""


func _shop(p: Dictionary, op: String, arg: String) -> String:
	if op == "sell":
		var i: int = host._find(p.inv, arg)
		if i < 0:
			return ""
		var price := Items.shop_price(p, p.inv[i], false)
		var name := Items.display_name(p.inv[i])
		p.inv.remove_at(i)
		p.coins += price
		return "Продано: %s за %s" % [name, Items.format_coins(price)]
	if arg not in Items.SHOP_STOCK:
		return ""
	var it := Items.make_potion(1) if arg == "potion" else Items.make(arg, 0, "Лавка Миры", false)
	var cost := Items.shop_price(p, it, true)
	if int(p.coins) < cost:
		return "Не хватает денег: нужно %s" % Items.format_coins(cost)
	if not add_item(p, it):
		return "Сумка полна."
	p.coins -= cost
	return "Куплено: %s" % Items.display_name(it)


func _use(p: Dictionary, uid: String) -> String:
	var i: int = host._find(p.inv, uid)
	if i < 0:
		return ""
	var it: Dictionary = p.inv[i]
	if it.base != "potion":
		return ""
	if Rules.Gifts.has_flag(p, "no_heal"):
		return "Дар не позволяет пить зелья."
	if int(p.hp) >= int(p.max_hp) and not Rules.Gifts.has_flag(p, "overheal_shield"):
		return "Здоровье и так полное."
	host.skills._heal(host._sender(), int(Items.BASES.potion.heal))
	it.count = int(it.count) - 1
	if int(it.count) <= 0:
		p.inv.remove_at(i)
	return ""


func _claim(p: Dictionary, bid: String) -> String:
	for b in Items.BOUNTIES:
		if b.id == bid and int(p.bounties.get(bid, 0)) >= int(b.need):
			p.bounties[bid] = 0
			p.coins += int(b.reward)
			return "Заказ «%s» выполнен: +%s" % [b.title, Items.format_coins(int(b.reward))]
	return ""
