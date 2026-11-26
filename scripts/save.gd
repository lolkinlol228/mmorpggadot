extends Node
## Сохранения: персонаж хранится у каждого игрока, счётчик серийных номеров — у хоста.

const CHAR_DIR := "user://chars"
const WORLD_PATH := "user://world.json"
const LAST_NAME_PATH := "user://last_name.txt"


func _char_path(pname: String) -> String:
	return "%s/%s.json" % [CHAR_DIR, pname.validate_filename()]


func load_char(pname: String) -> Dictionary:
	var path := _char_path(pname)
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			parsed["name"] = pname
			return sanitize_char(parsed)
	return {
		"name": pname, "coins": 30, "equip": {"weapon": Items.make("sword", 0, pname, false)},
		"inv": [Items.make("hood", 0, pname, false), Items.make_potion(2)], "look": {}, "bank": [], "bounties": {},
	}


func store_char(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	var f := FileAccess.open(_char_path(str(data.name)), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


## Проверка данных персонажа, пришедших по сети или из файла.
func sanitize_char(d) -> Dictionary:
	var out := {"name": "Игрок", "coins": 0, "inv": [], "equip": {}, "look": {}, "bank": [], "bounties": {},
		"level": 1, "xp": 0, "points": 0, "stats": {}}
	if not (d is Dictionary):
		return out
	var n := str(d.get("name", "")).strip_edges().left(16)
	out.name = n if n != "" else "Игрок"
	out.coins = clampi(int(d.get("coins", d.get("gold", 0))), 0, 999999999)   # старые сейвы: gold -> медяки
	out.look = preload("res://scripts/char_baker.gd").sanitize_look(d.get("look", {}))
	out.level = clampi(int(d.get("level", 1)), 1, 99)
	out.xp = clampi(int(d.get("xp", 0)), 0, 99999999)
	out.points = clampi(int(d.get("points", 0)), 0, 999)
	var st = d.get("stats", {})
	if st is Dictionary:
		for k in Rules.STATS:
			out.stats[k] = clampi(int(st.get(k, 0)), 0, 300)
	var inv = d.get("inv", [])
	if inv is Array:
		for raw in inv:
			var item := Items.normalize(raw)
			if not item.is_empty() and item.base != "coins" and out.inv.size() < Items.MAX_INV:
				out.inv.append(item)
	var bank = d.get("bank", [])
	if bank is Array:
		for raw in bank:
			var item := Items.normalize(raw)
			if not item.is_empty() and item.base != "coins" and out.bank.size() < Items.MAX_BANK:
				out.bank.append(item)
	var bq = d.get("bounties", {})
	if bq is Dictionary:
		for k in bq:
			out.bounties[str(k).left(24)] = clampi(int(bq[k]), 0, 999)
	var eq = d.get("equip", {})
	if eq is Dictionary:
		for slot in Items.SLOTS:
			var item := Items.normalize(eq.get(slot))
			if not item.is_empty() and Items.slot_of(item) == slot:
				out.equip[slot] = item
	return out


func load_world() -> Dictionary:
	if FileAccess.file_exists(WORLD_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
		if parsed is Dictionary:
			return parsed
	return {}


func store_world(data: Dictionary) -> void:
	var f := FileAccess.open(WORLD_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_last_name() -> String:
	if FileAccess.file_exists(LAST_NAME_PATH):
		return FileAccess.get_file_as_string(LAST_NAME_PATH).strip_edges()
	return ""


func store_last_name(n: String) -> void:
	var f := FileAccess.open(LAST_NAME_PATH, FileAccess.WRITE)
	if f:
		f.store_string(n)


const LOOK_PATH := "user://last_look.json"


func load_look() -> Dictionary:
	if FileAccess.file_exists(LOOK_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LOOK_PATH))
		if d is Dictionary:
			return d
	return {}


func store_look(look: Dictionary) -> void:
	var f := FileAccess.open(LOOK_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(look))
