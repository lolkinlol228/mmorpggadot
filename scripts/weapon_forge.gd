extends RefCounted

const OPTIONS := {"slash": ["riposte", "cleave"], "chop": ["crusher", "third"],
	"stab": ["dash_crit", "bleed"], "shot": ["pierce", "silence"], "bolt": ["pierce", "silence"]}
const NAMES := {"riposte": "Ответ после парирования ×2", "cleave": "Второй враг рядом · 50% урона",
	"crusher": "По оглушённой цели +40%", "third": "Третий удар оглушает на 0,5 с",
	"dash_crit": "После рывка — крит", "bleed": "Кровотечение · 30% за 3 с",
	"pierce": "Пробить вторую цель", "silence": "Снаряд прерывает звон"}

static func apply(p: Dictionary, style: String, choice: String) -> String:
	var weapon: Dictionary = p.equip.get("weapon", {})
	if weapon.is_empty() or p.quests.step < 2 or choice not in OPTIONS.get(style, []):
		return "Покажите Горну осколок и наденьте подходящее оружие."
	if p.has("work") or p.has("rescue") or p.trade != 0:
		return "Сначала завершите текущее действие."
	if weapon.get("forge") == choice:
		return "Это свойство уже выковано."
	for i in p.inv.size():
		var item: Dictionary = p.inv[i]
		if item.base != "golem_shard":
			continue
		if int(item.get("count", 1)) == 1:
			p.inv.remove_at(i)
		else:
			item.count -= 1
		weapon.forge = choice
		p.erase("forge_hits")
		return "Горн выковал свойство: " + NAMES[choice]
	return "За перековку нужен осколок ядра голема."


static func on_dash(p: Dictionary) -> void:
	var w: Dictionary = p.equip.get("weapon", {})
	p.dash_critical_uid = w.get("uid", "") if w.get("forge") == "dash_crit" else ""


static func consume_critical(p: Dictionary, w: Dictionary) -> bool:
	if w.get("forge") != "dash_crit" or p.get("dash_critical_uid") != w.uid:
		return false
	p.erase("dash_critical_uid")
	return true


static func third_hit(p: Dictionary, w: Dictionary) -> bool:
	if w.get("forge") != "third":
		return false
	var counter: Dictionary = p.get("forge_hits", {})
	var n := int(counter.get("n", 0)) if counter.get("uid") == w.uid else 0
	p.forge_hits = {"uid": w.uid, "n": (n + 1) % 3}
	return p.forge_hits.n == 0


static func bleed(host, now: int) -> void:
	for eid in host.enemies.keys():
		var e: Dictionary = host.enemies.get(eid, {})
		for wound in e.get("wounds", []).duplicate():
			while wound.tick < 3 and now >= wound.start + (wound.tick + 1) * 1000:
				var before := roundi(wound.amount * wound.tick * 0.1)
				wound.tick += 1
				var dmg := roundi(wound.amount * wound.tick * 0.1) - before
				if host.players.get(wound.pid, {}).get("hid") == wound.hid:
					host.gifts.deal(wound.pid, eid, dmg, true)
			if wound.tick == 3:
				e.wounds.erase(wound)
