extends RefCounted

var host
var turn := 0
var reservations := {}


func participants(e: Dictionary, killer: int) -> Array:
	var result := []
	var radius: float = host.get_node("/root/Rules").SHARE_XP_RADIUS
	var now := Time.get_ticks_msec()
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		var rescue: Dictionary = p.get("rescue", {})
		var ally: Dictionary = host.players.get(rescue.get("pid", -1), {})
		var helping: bool = not ally.is_empty() and ally.hp <= 0 and p.hp > 0 and p.pos.distance_to(ally.pos) < 65 and rescue.until >= now and p.get("hurt_at", 0) <= rescue.started
		if pid == killer or e.get("contributors", {}).has(p.hid) or p.pos.distance_to(e.pos) <= radius or helping:
			result.append(pid)
	result.sort_custom(func(a, b): return host.players[a].hid < host.players[b].hid)
	return result


func distribute(e: Dictionary, party: Array) -> void:
	var items: Node = host.get_node("/root/Items")
	for pid in party:
		var p: Dictionary = host.players[pid]
		var bases := ["bell_tongue", "recipe_scrap"]
		if e.kind == "golem":
			p.quests.golem = true
			bases = ["golem_shard"]
		else:
			preload("res://scripts/mine_quest.gd").progress(p.quests, "warden")
		for base in bases:
			var item: Dictionary = items.make(base, 0, p.name, false)
			var message := "В сумке: " + str(items.BASES[base].name)
			if not host.eco.add_item(p, item):
				reserve(item, p.pos, pid, 60, true)
				message = "%s у ваших ног. Первые 60 с видите и подбираете только вы." % items.BASES[base].name
			host._to(pid, "c_announce", [message, Color.WHEAT])
		host._send_self(pid)


func equipment(item: Dictionary, pos: Vector2, party: Array) -> void:
	if party.is_empty() or (item.rarity < 2 and not host.get_node("/root/Items").is_jackpot(item)):
		host.drop(item, pos)
		return
	var pid: int = party[turn % party.size()]
	turn += 1
	reserve(item, pos, pid, 30, false)


func reserve(item: Dictionary, pos: Vector2, pid: int, seconds: int, hidden: bool) -> int:
	var lid: int = host._nid()
	var p: Dictionary = host.players[pid]
	host.loots[lid] = {"item": item, "pos": pos}
	reservations[lid] = {"hid": p.hid, "name": p.name, "hidden": hidden, "until": Time.get_ticks_msec() + seconds * 1000}
	for peer in host.players:
		var row := visible(lid, peer)
		if not row.is_empty():
			host._to(peer, "c_loot", row)
	return lid


func allowed(lid: int, pid: int, now: int) -> bool:
	var lock: Dictionary = reservations.get(lid, {})
	return lock.is_empty() or now >= int(lock.until) or host.players[pid].hid == lock.hid


func visible(lid: int, pid: int) -> Array:
	var loot: Dictionary = host.loots[lid]
	var lock: Dictionary = reservations.get(lid, {})
	var item: Dictionary = loot.item
	if not lock.is_empty() and Time.get_ticks_msec() < int(lock.until):
		var owner: bool = host.players[pid].hid == lock.hid
		if lock.hidden and not owner:
			return []
		item = item.duplicate()
		item.reserved_for = lock.name
		item.reserved_other = not owner
	return [lid, item, loot.pos]


func tick(now: int) -> void:
	for lid in reservations.keys():
		if now >= int(reservations[lid].until):
			reservations.erase(lid)
			var loot: Dictionary = host.loots[lid]
			host._all("c_loot", [lid, loot.item, loot.pos])
