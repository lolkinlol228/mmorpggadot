extends HBoxContainer
## Панель умений: R — умение расы, 1 / 2 / 3 — общие (открываются с уровнем).
## Затемнение сверху вниз — перезарядка, замок — ещё не открыто. Время считается по своим часам,
## а хост присылает остаток в c_self, так что расхождение не накапливается.

const Kit := preload("res://scripts/ui_kit.gd")
const ItemSlot := preload("res://scripts/item_slot.gd")

var game
var ids: Array = []
var slots := {}             # id -> {slot, shade, timer, lock}
var cd_until := {}          # id -> мс (свои часы)
var cd_total := {}
var buff_until := {}
var race := ""


func build() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 56
	offset_right = 196
	offset_top = -38
	offset_bottom = -6
	add_theme_constant_override("separation", 4)


func _keys() -> Array:
	return ["R", "1", "2", "3"]


func sync(me: Dictionary) -> void:
	var r := str(me.get("look", {}).get("race", "human"))
	if r != race:
		race = r
		_rebuild(me)
	var now := int(me.get("_recv", Time.get_ticks_msec()))     # когда пришли остатки от хоста
	cd_until.clear()
	for id in me.get("cds", {}):
		cd_until[id] = now + int(float(me.cds[id]) * 1000.0)
	buff_until.clear()
	for id in me.get("buffs", {}):
		buff_until[id] = now + int(float(me.buffs[id]) * 1000.0)
	for id in ids:
		cd_total[id] = float(Rules.SKILLS[id].cd) * Rules.cd_mult(me)
		slots[id].lock.visible = not Rules.skill_unlocked(me, id)
		slots[id].slot.tooltip_text = _tip(id, me)


func _rebuild(me: Dictionary) -> void:
	for ch in get_children():
		ch.queue_free()
	slots.clear()
	ids = [Rules.race_skill(me)] + Rules.COMMON_SKILLS
	for i in ids.size():
		var id: String = ids[i]
		var s = ItemSlot.new()
		s.custom_minimum_size = Vector2(30, 30)
		s.clicked.connect(func(): game.use_skill(id))
		var ic := Kit.icon(Rules.SKILLS[id].icon, 22)
		ic.position = Vector2(4, 3)
		ic.size = Vector2(22, 22)
		s.add_child(ic)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.62)
		shade.position = Vector2(3, 3)
		shade.size = Vector2(24, 0)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(shade)
		var timer := Kit.label("", 9, Color.WHITE)
		timer.position = Vector2(0, 8)
		timer.size = Vector2(30, 10)
		timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_child(timer)
		var lock := Kit.label("ур.%d" % int(Rules.SKILLS[id].get("lvl", 1)), 9, Kit.DIM)
		lock.position = Vector2(0, 8)
		lock.size = Vector2(30, 10)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_child(lock)
		var k := Kit.label(_keys()[i], 9, Kit.GOLD)
		k.position = Vector2(2, 18)
		s.add_child(k)
		add_child(s)
		slots[id] = {"slot": s, "shade": shade, "timer": timer, "lock": lock, "icon": ic}


func _tip(id: String, me: Dictionary) -> String:
	var sk: Dictionary = Rules.SKILLS[id]
	var head := "%s  —  перезарядка %.0f с" % [sk.name, float(sk.cd) * Rules.cd_mult(me)]
	if id == Rules.race_skill(me):
		head += "\nУмение расы: %s" % Rules.race_of(me).name
	elif not Rules.skill_unlocked(me, id):
		head += "\nОткроется на %d уровне" % int(sk.lvl)
	return head + "\n" + str(sk.desc)


func cd_left(id: String) -> float:
	return maxf(0.0, (int(cd_until.get(id, 0)) - Time.get_ticks_msec()) / 1000.0)


func has_buff(id: String) -> bool:
	return int(buff_until.get(id, 0)) > Time.get_ticks_msec()


func start_cd(id: String) -> void:
	cd_until[id] = Time.get_ticks_msec() + int(float(cd_total.get(id, 1.0)) * 1000.0)


func _process(_delta: float) -> void:
	for id in slots:
		var left := cd_left(id)
		var total: float = maxf(0.1, float(cd_total.get(id, 1.0)))
		var s: Dictionary = slots[id]
		s.shade.size.y = 24.0 * clampf(left / total, 0.0, 1.0)
		s.timer.text = ("%d" % ceili(left)) if left > 0.0 and not s.lock.visible else ""
		s.icon.modulate = Color(0.45, 0.45, 0.5) if s.lock.visible else (Color(1.4, 1.3, 1.0) if has_buff(id) else Color.WHITE)
