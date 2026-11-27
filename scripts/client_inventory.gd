extends RefCounted
## Инвентарь, подбор добычи и торговля на клиенте.

const LootView := preload("res://scripts/loot_view.gd")

var game
var full_hint_at := 0


func request_equip(uid: String) -> void:
	game._to_host("h_equip", [uid])


func request_unequip(slot: String) -> void:
	game._to_host("h_unequip", [slot])


func request_trade_nearest() -> void:
	var best := -1
	var best_d = game.TRADE_RANGE
	for pid in game.player_views:
		if pid == game.my_id:
			continue
		var d: float = game.player_views[pid].position.distance_to(game.my_pos)
		if d < best_d:
			best_d = d
			best = pid
	if best == -1:
		game.ui.add_feed("Подойди вплотную к другому игроку и нажми T, чтобы предложить обмен.", game.GREY)
		return
	game._to_host("h_trade_req", [best])


func answer_trade(from: int, accept: bool) -> void:
	game._to_host("h_trade_answer", [from, accept])


func send_trade_offer(uids: Array) -> void:
	game._to_host("h_trade_offer", [uids])


func confirm_trade() -> void:
	game._to_host("h_trade_confirm")


func cancel_trade() -> void:
	game._to_host("h_trade_cancel")


func eco(op: String, arg := "") -> void:
	game._to_host("h_eco", [op, arg])


func _auto_pickup() -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0:
		return
	var now := Time.get_ticks_msec()
	for lid in game.loot_views:
		if game.loot_views[lid].item.get("reserved_other", false):
			continue
		if game.loot_views[lid].position.distance_to(game.my_pos) > game.PICKUP_RADIUS * Rules.Gifts.factor(game.me, "pickup"):
			continue
		if game.me.inv.size() >= Items.bag_capacity(game.me) and not Items.is_stack(game.loot_views[lid].item) and game.loot_views[lid].item.base != "coins":
			if now - full_hint_at > 4000:
				full_hint_at = now
				game.ui.add_feed("Сумка полна! Выкинуть пока нельзя — надень лучшее или обменяй.", game.GREY)
			return
		if now - int(game.pending_pickup.get(lid, -100000)) > 1500:
			game.pending_pickup[lid] = now
			game._to_host("h_pickup", [lid])


func c_equip(pid: int, equip: Dictionary) -> void:
	var v = game.player_views.get(pid)
	if v:
		v.set_equip(equip)
	if pid == game.my_id:
		Sfx.play("equip_metal" if equip.has("weapon") and randf() < 0.5 else "equip_cloth")


func c_loot(lid: int, item: Dictionary, pos: Vector2) -> void:
	_add_loot(lid, item, pos, true)


func _add_loot(lid: int, item: Dictionary, pos: Vector2, fresh: bool) -> void:
	if game.loot_views.has(lid):
		game.loot_views[lid].update_label(item)
		return
	var v = LootView.new()
	v.item = item
	v.position = pos
	game.entities.add_child(v)
	game.loot_views[lid] = v
	if fresh and Items.is_jackpot(item):
		game.fx.drop_appeared(pos, item)
		game.ui.add_feed("Что-то ослепительно сверкнуло на земле!", Items.color(item))
	elif fresh and int(item.rarity) >= 2:
		game.fx.burst(pos, Items.color(item), 16, false)
		Sfx.play_at("shimmer", pos, game.my_pos)


func c_loot_gone(lid: int) -> void:
	if game.loot_views.has(lid):
		if game.pending_pickup.has(lid):
			Sfx.play("pickup")
		game.loot_views[lid].queue_free()
		game.loot_views.erase(lid)
	game.pending_pickup.erase(lid)


func c_jackpot(finder: String, item: Dictionary) -> void:
	game.fx.jackpot(finder, item)
	Sfx.fanfare(int(item.rarity) + 1)
	game.ui.add_feed("⚡ %s нашёл %s [%s]" % [finder, Items.display_name(item),
		Items.RARITY_NAMES[int(item.rarity)]], Items.color(item))


func c_trade_invite(from: int, from_name: String) -> void:
	game.ui.show_invite(from, from_name)


func c_trade_open(other_name: String) -> void:
	game.ui.open_trade(other_name)


func c_trade_state(mine: Array, theirs: Array, my_ok: bool, their_ok: bool) -> void:
	game.ui.set_trade_state(mine, theirs, my_ok, their_ok)


func c_trade_closed(msg: String) -> void:
	game.ui.close_trade(msg)
