extends RefCounted
## Трофеи → компоненты → реликвии. Три слоя предметов:
##   ремесленное — из добытых ресурсов (host_professions.RECIPES);
##   добыча — падает с врагов со случайной редкостью (Items.roll_drop);
##   реликвии — именное оружие по цепочке: трофеи с врагов → компонент в мастерской → компоненты + редкий
##   материал → реликвия. Реликвия даёт владельцу свои дары (Items.BASES[...].grants, см. Gifts.ids).
## Трофеи и компоненты — обычные предметы-стопки: их можно передавать, обменивать и продавать на рынке.

# вид врага -> [трофей, шанс, от, до]
const DROPS := {"slime": ["slime_gel", 0.18, 1, 2], "wolf": ["wolf_fang", 0.10, 1, 1],
	"golem": ["golem_shard", 1.0, 1, 2], "undead": ["echo_dust", 0.20, 1, 2]}
const ELITE_DROP := "elite_mark"            # каждый элитный враг (не босс) — одна метка

# items — предметы из сумки (трофеи / компоненты), mats — материалы ремёсел (p.materials)
const COMPONENTS := {
	"acid_essence": {"items": {"slime_gel": 20}, "mats": {"herb": 2}},
	"pack_charm": {"items": {"wolf_fang": 15}, "mats": {"prime_hide": 3}},
	"golem_heart": {"items": {"golem_shard": 5}, "mats": {"gem": 1}},
	"lantern_soul": {"items": {"echo_dust": 20}, "mats": {"moon_silk": 2}},
	"champion_seal": {"items": {"elite_mark": 5}, "mats": {"star_iron": 3}},
}
const RELICS := {
	"acid_blade": {"items": {"acid_essence": 2}, "mats": {"star_iron": 5}},
	"moon_bow": {"items": {"pack_charm": 1, "acid_essence": 1}, "mats": {"ancient_wood": 5}},
	"mountain_hammer": {"items": {"golem_heart": 1, "champion_seal": 1}, "mats": {"star_iron": 10}},
	"soul_lantern": {"items": {"lantern_soul": 1, "golem_heart": 1}, "mats": {"moon_silk": 5}},
	"shadow_fang": {"items": {"pack_charm": 2, "champion_seal": 1}, "mats": {"prime_hide": 4}},
	"dawn_scepter": {"items": {"lantern_soul": 1, "champion_seal": 1}, "mats": {"gem": 3}},
}
const RELIC_RARITY := 4                     # легендарный вид оружия


static func recipe(key: String) -> Dictionary:
	return COMPONENTS.get(key, RELICS.get(key, {}))


## Сколько предметов base лежит в сумке (сумма стопок).
static func count(inv: Array, base: String) -> int:
	var n := 0
	for it in inv:
		if it.base == base:
			n += int(it.get("count", 1))
	return n


## Хватает ли всего на рецепт.
static func can_make(p: Dictionary, key: String) -> bool:
	var r := recipe(key)
	if r.is_empty():
		return false
	for base in r.items:
		if count(p.inv, base) < int(r.items[base]):
			return false
	for m in r.mats:
		if int(p.get("materials", {}).get(m, 0)) < int(r.mats[m]):
			return false
	return true


## «Сгусток слизи 7/20 · Травы 1/2» — для кнопки в мастерской.
static func need_text(p: Dictionary, key: String, mat_names: Dictionary) -> String:
	var r := recipe(key)
	var parts := PackedStringArray()
	for base in r.items:
		parts.append("%s %d/%d" % [Items.BASES[base].name, count(p.inv, base), int(r.items[base])])
	for m in r.mats:
		parts.append("%s %d/%d" % [mat_names.get(m, m), int(p.get("materials", {}).get(m, 0)), int(r.mats[m])])
	return " · ".join(parts)


## Во что идёт трофей или компонент (для подсказки предмета).
static func used_in(base: String) -> String:
	var out := PackedStringArray()
	for table in [COMPONENTS, RELICS]:
		for key in table:
			if table[key].items.has(base):
				out.append("%s (%d)" % [Items.BASES[key].name, int(table[key].items[base])])
	return ", ".join(out) if not out.is_empty() else "—"


## Хост: изготовить компонент или реликвию. Возвращает сообщение игроку.
static func craft(host, pid: int, key: String) -> String:
	var p: Dictionary = host.players[pid]
	var r := recipe(key)
	if r.is_empty():
		return ""
	if not can_make(p, key):
		return "Не хватает: " + need_text(p, key, host.professions.NAMES)
	for base in r.items:
		_take(p.inv, base, int(r.items[base]))
	for m in r.mats:
		p.materials[m] = int(p.materials[m]) - int(r.mats[m])
	var item: Dictionary
	if RELICS.has(key):
		item = Items.make(key, RELIC_RARITY, p.name, false)
		host.serial += 1                                      # у каждой реликвии свой номер в мире
		item.serial = host.serial
		Save.store_world({"serial": host.serial})
	else:
		item = Items.make(key, 0, p.name, false)
	if not host.eco.add_item(p, item):
		host.drop(item, p.pos)                                # сумка полна — кладём под ноги
	if RELICS.has(key):
		host._all("c_jackpot", [p.name, item])
		host._all("c_announce", ["%s выковал реликвию: %s!" % [p.name, Items.display_name(item)], Color(1.0, 0.75, 0.35)])
		return ""
	return "Изготовлено: %s." % Items.BASES[key].name


static func _take(inv: Array, base: String, n: int) -> void:
	for i in range(inv.size() - 1, -1, -1):
		if n <= 0:
			return
		var it: Dictionary = inv[i]
		if it.base != base:
			continue
		var c := int(it.get("count", 1))
		if c <= n:
			n -= c
			inv.remove_at(i)
		else:
			it.count = c - n
			n = 0


## Хост, смерть врага: трофей по таблице DROPS, метка чемпиона с элиты. loot — множитель шанса.
static func roll_trophies(e: Dictionary, loot: float) -> Array:
	var out := []
	var d: Array = DROPS.get(e.kind, [])
	if not d.is_empty() and randf() < minf(1.0, float(d[1]) * loot):
		var it := Items.make(str(d[0]), 0, "", false)
		it.count = randi_range(int(d[2]), int(d[3]))
		out.append(it)
	if e.get("elite", false) and e.kind != "golem":
		out.append(Items.make(ELITE_DROP, 0, "", false))
	return out
