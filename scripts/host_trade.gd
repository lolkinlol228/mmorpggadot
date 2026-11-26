extends RefCounted
## Предложения и атомарный обмен предметами между игроками.

const MAX_OFFER := 8
var host
var trades := {}

# ---------- обмен ----------

func trade_request(target: int) -> void:
	var id: int = host._sender()
	if id == target or not host.players.has(id) or not host.players.has(target):
		return
	if int(host.players[id].trade) != 0 or int(host.players[target].trade) != 0:
		host._to(id, "c_announce", ["Этот игрок сейчас занят другим обменом.", host.game.GREY])
		return
	if host.players[id].pos.distance_to(host.players[target].pos) > host.game.TRADE_RANGE:
		host._to(id, "c_announce", ["Подойди ближе, чтобы обменяться.", host.game.GREY])
		return
	host.players[target].invite = id
	host._to(target, "c_trade_invite", [id, host.players[id].name])
	host._to(id, "c_announce", ["Предложение обмена отправлено: %s" % host.players[target].name, host.game.GREY])


func trade_answer(from: int, accept: bool) -> void:
	var id: int = host._sender()
	if not host.players.has(id) or int(host.players[id].invite) != from or not host.players.has(from):
		return
	host.players[id].invite = -1
	if not accept:
		host._to(from, "c_announce", ["%s отказался от обмена." % host.players[id].name, host.game.GREY])
		return
	if int(host.players[id].trade) != 0 or int(host.players[from].trade) != 0:
		return
	var tid: int = host._nid()
	trades[tid] = {"a": from, "b": id, "offer": {from: [], id: []}, "ok": {from: false, id: false}}
	host.players[from].trade = tid
	host.players[id].trade = tid
	host._to(from, "c_trade_open", [host.players[id].name])
	host._to(id, "c_trade_open", [host.players[from].name])
	_push_trade(tid)


func _my_trade(id: int):
	if not host.players.has(id):
		return null
	return trades.get(int(host.players[id].trade))


func trade_offer(uids: Array) -> void:
	var id: int = host._sender()
	var t = _my_trade(id)
	if t == null:
		return
	var valid := []
	for u in uids:
		if u is String and not valid.has(u) and valid.size() < MAX_OFFER and host._find(host.players[id].inv, u) >= 0:
			valid.append(u)
	t.offer[id] = valid
	for k in t.ok:
		t.ok[k] = false      # любое изменение сбрасывает подтверждения — защита от подмены
	_push_trade(host.players[id].trade)


func trade_confirm() -> void:
	var id: int = host._sender()
	var t = _my_trade(id)
	if t == null:
		return
	t.ok[id] = true
	if t.ok[t.a] and t.ok[t.b]:
		_execute_trade(host.players[id].trade)
	else:
		_push_trade(host.players[id].trade)


func trade_cancel() -> void:
	var id: int = host._sender()
	if _my_trade(id) != null:
		close_trade(host.players[id].trade, "Обмен отменён.")


func _items_of(pid: int, uids: Array) -> Array:
	var out := []
	for u in uids:
		var i: int = host._find(host.players[pid].inv, u)
		if i >= 0:
			out.append(host.players[pid].inv[i])
	return out


func _push_trade(tid: int) -> void:
	var t: Dictionary = trades[tid]
	for side in [t.a, t.b]:
		var other: int = t.b if side == t.a else t.a
		host._to(side, "c_trade_state", [_items_of(side, t.offer[side]), _items_of(other, t.offer[other]),
			t.ok[side], t.ok[other]])


## Обмен происходит целиком или не происходит вообще.
func _execute_trade(tid: int) -> void:
	var t: Dictionary = trades[tid]
	var a: Dictionary = host.players[t.a]
	var b: Dictionary = host.players[t.b]
	var give_a := _items_of(t.a, t.offer[t.a])
	var give_b := _items_of(t.b, t.offer[t.b])
	if give_a.size() != t.offer[t.a].size() or give_b.size() != t.offer[t.b].size():
		close_trade(tid, "Обмен не удался: предметы изменились.")
		return
	if a.inv.size() - give_a.size() + give_b.size() > Items.bag_capacity(a) \
			or b.inv.size() - give_b.size() + give_a.size() > Items.bag_capacity(b):
		close_trade(tid, "Обмен не удался: у кого-то не хватает места в сумке.")
		return
	for it in give_a:
		a.inv.remove_at(host._find(a.inv, it.uid))
	for it in give_b:
		b.inv.remove_at(host._find(b.inv, it.uid))
	a.inv.append_array(give_b)
	b.inv.append_array(give_a)
	close_trade(tid, "Обмен завершён!")


func close_trade(tid: int, msg: String) -> void:
	var t: Dictionary = trades[tid]
	trades.erase(tid)
	for side in [t.a, t.b]:
		if host.players.has(side):
			host.players[side].trade = 0
			host._to(side, "c_trade_closed", [msg])
			host._send_self(side)
