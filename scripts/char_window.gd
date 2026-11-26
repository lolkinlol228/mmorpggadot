extends Node
## Окно персонажа (C): компактно, иконками. Название и пояснение каждой цифры — во всплывающей подсказке.
## Сверху класс/раса/уровень и опыт, затем дары, 8 характеристик с «+», ниже сетка итоговых параметров.

const Kit := preload("res://scripts/ui_kit.gd")
const Gifts := preload("res://scripts/gifts.gd")

const W := 214.0
const STAT_ICONS := {"str": Vector2i(4, 1), "agi": Vector2i(12, 3), "vit": Vector2i(0, 1), "spi": Vector2i(0, 21),
	"int": Vector2i(3, 1), "def": Vector2i(2, 6), "luk": Vector2i(13, 13), "spd": Vector2i(13, 3)}
const RES_ICONS := {"mana": Vector2i(1, 18), "rage": Vector2i(0, 18), "energy": Vector2i(3, 18)}

var game
var panel: PanelContainer
var title: Label
var head: Label
var warn: TextureRect
var gifts_box: HFlowContainer
var shown_gifts := ["?"]
var xp_fill: ColorRect
var xp_label: Label
var points_label: Label
var stat_cells := {}         # stat -> [value label, + button, cell]
var grid: GridContainer
var cells := {}              # ключ параметра -> [value label, cell]


func build(parent: Control) -> void:
	var w := Kit.window("Герой", toggle)
	panel = w[0]
	title = w[2]
	var body: VBoxContainer = w[1]
	body.add_theme_constant_override("separation", 3)
	panel.offset_left = 6
	panel.offset_right = 6 + W
	panel.offset_top = 62
	panel.visible = false
	parent.add_child(panel)

	var top := HBoxContainer.new()
	body.add_child(top)
	head = Kit.label("", 9, Kit.GOLD)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(head)
	warn = Kit.icon(Vector2i(0, 0), 12)          # латы мешают колдовать
	warn.mouse_filter = Control.MOUSE_FILTER_PASS
	warn.modulate = Color(1, 0.5, 0.45)
	top.add_child(warn)

	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0.05, 0.05, 0.08)
	xp_bg.custom_minimum_size = Vector2(W - 16, 8)
	body.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.45, 0.55, 0.95)
	xp_fill.size = Vector2(0, 8)
	xp_bg.add_child(xp_fill)
	xp_label = Kit.label("", 9)
	xp_label.size = Vector2(W - 16, 10)
	xp_label.position = Vector2(0, -1)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_bg.add_child(xp_label)

	gifts_box = HFlowContainer.new()
	gifts_box.custom_minimum_size = Vector2(W - 16, 0)
	gifts_box.add_theme_constant_override("h_separation", 6)
	body.add_child(gifts_box)
	body.add_child(Kit.divider())

	# 8 характеристик: 2×4, иконка · число · «+»
	var sh := HBoxContainer.new()
	body.add_child(sh)
	points_label = Kit.label("", 9, Kit.GOLD)
	points_label.mouse_filter = Control.MOUSE_FILTER_PASS
	points_label.tooltip_text = "Свободные очки: +%d за каждый уровень" % Rules.POINTS_PER_LEVEL
	sh.add_child(points_label)
	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 8)
	sgrid.add_theme_constant_override("v_separation", 2)
	body.add_child(sgrid)
	for s in Rules.STATS:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2((W - 24) / 2.0, 0)
		cell.add_theme_constant_override("separation", 3)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(Kit.icon(STAT_ICONS[s], 14))
		var v := Kit.label("", 9, Color.WHITE)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(v)
		var b := Kit.button("+", func(): game.add_stat(s))
		b.custom_minimum_size = Vector2(16, 14)
		cell.add_child(b)
		sgrid.add_child(cell)
		stat_cells[s] = [v, b, cell]
	body.add_child(Kit.divider())

	# итоговые параметры: сетка 3 колонки, иконка + число
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	body.add_child(grid)
	for d in _derived_defs():
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2((W - 24) / 3.0, 0)
		cell.add_theme_constant_override("separation", 2)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := Kit.icon(d[1], 12)
		cell.add_child(ic)
		var v := Kit.label("", 9, Kit.TEXT)
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(v)
		grid.add_child(cell)
		cells[d[0]] = [v, cell, ic]


## [ключ, иконка, название, пояснение]
func _derived_defs() -> Array:
	return [
		["hp", Vector2i(6, 0), "Здоровье", "максимум здоровья"],
		["res", Vector2i(1, 18), "Ресурс", "максимум ресурса класса"],
		["res_regen", Vector2i(10, 0), "Восстановление ресурса", "в секунду"],
		["dmg", Vector2i(1, 5), "Урон", "урон обычной атаки"],
		["skill", Vector2i(8, 0), "Сила умений", "прибавка к урону умений (Интеллект и дары)"],
		["crit", Vector2i(11, 3), "Крит", "шанс критического удара (потолок %d%%)" % int(Gifts.CAPS.crit * 100)],
		["crit_dmg", Vector2i(9, 0), "Сила крита", "множитель урона крита"],
		["aspd", Vector2i(9, 5), "Скорость атаки", "прибавка к скорости атаки"],
		["armor", Vector2i(1, 6), "Броня", "каждое очко снимает 0,5 урона с удара врага"],
		["dodge", Vector2i(12, 3), "Уклонение", "шанс полностью избежать удара (потолок %d%%)" % int(Gifts.CAPS.dodge * 100)],
		["cd", Vector2i(15, 10), "Перезарядка", "умения перезаряжаются быстрее на столько"],
		["heal", Vector2i(5, 3), "Лечение", "прибавка к силе лечения"],
		["leech", Vector2i(0, 3), "Вампиризм", "доля урона, возвращаемая здоровьем"],
		["speed", Vector2i(13, 3), "Скорость бега", "прибавка к скорости бега"],
		["stam", Vector2i(3, 9), "Выносливость", "скорость восстановления выносливости"],
		["thorns", Vector2i(9, 8), "Шипы", "доля урона, возвращаемая врагу"],
		["loot", Vector2i(11, 11), "Добыча", "шанс выпадения вещей"],
		["find", Vector2i(15, 12), "Редкие находки", "сдвиг выпадения к редким вещам (Удача и дары, потолок %d%%)" % int(Gifts.CAPS.rare_find * 100)],
		["coin", Vector2i(6, 12), "Монеты", "монет с врагов"],
		["xp", Vector2i(5, 0), "Опыт", "опыта за убийства"],
	]


func toggle() -> void:
	panel.visible = not panel.visible
	Sfx.play("open" if panel.visible else "close")
	refresh(game.me)


func _show_gifts(list: Array) -> void:
	if list == shown_gifts:
		return
	shown_gifts = list.duplicate()
	for ch in gifts_box.get_children():
		ch.queue_free()
	if list.is_empty():
		gifts_box.add_child(Kit.label("без даров", 9, Kit.DIM))
		return
	for id in list:
		var g := Gifts.get_gift(str(id))
		var l := Kit.label("◆ " + str(g.get("name", id)), 9, Gifts.color(str(id)))
		l.tooltip_text = Gifts.tooltip(str(id))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		gifts_box.add_child(l)


## Ключевые итоговые числа героя: [название, значение, доля (true) или число (false)].
func _snapshot(p: Dictionary) -> Array:
	return [
		["здоровье", float(Rules.max_hp(p)), false],
		["урон", Rules.damage(p), false],
		["урон умений", Rules.skill_power(p), true],
		["крит", Rules.crit_chance(p), true],
		["сила крита", Rules.crit_mult(p) * Gifts.factor(p, "crit_dmg"), false],
		["скорость атаки", Rules.attack_speed(p), true],
		["броня", float(Rules.armor(p)), false],
		["уклонение", clampf(Gifts.mod(p, "dodge") + Rules.dodge_bonus(p), 0.0, Gifts.CAPS.dodge), true],
		[Rules.RES_NAMES[Rules.res_kind(p)].to_lower(), float(Rules.res_max(p)), false],
		["перезарядка", 1.0 - Rules.cd_mult(p), true],
		["лечение", Rules.heal_power(p), true],
		["скорость бега", Rules.speed_mult(p), true],
		["выносливость", Rules.stamina_regen(p), true],
		["редкие находки", minf(Gifts.CAPS.rare_find, Gifts.mod(p, "rare_find") + Rules.luck_find(p)), true],
	]


## Что изменится от ещё одного очка в характеристике s (те же формулы, что у хоста).
func _preview(me: Dictionary, s: String) -> String:
	var after := me.duplicate(true)
	var st: Dictionary = after.get("stats", {})
	st[s] = int(st.get(s, 0)) + 1
	after["stats"] = st
	var a := _snapshot(me)
	var b := _snapshot(after)
	var lines := PackedStringArray()
	for i in a.size():
		var d: float = float(b[i][1]) - float(a[i][1])
		if absf(d) < 0.0005:
			continue
		if a[i][2]:
			lines.append("  %s +%.1f%%" % [a[i][0], d * 100.0])
		else:
			var rel := d / maxf(0.001, float(a[i][1])) * 100.0
			lines.append("  %s +%s (+%.1f%%)" % [a[i][0], ("%.2f" % d) if d < 1.0 else ("%.1f" % d), rel])
	return "\n".join(lines) if not lines.is_empty() else "  упирается в потолок"


func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


func _signed(x: float) -> String:
	return ("+" if x >= 0.0 else "") + _pct(x)


func refresh(me: Dictionary) -> void:
	if me.is_empty() or not panel.visible:
		return
	var r: Dictionary = Rules.race_of(me)
	var c: Dictionary = Rules.class_of(me)
	var lvl := int(me.get("level", 1))
	head.text = "%s · %s · ур. %d" % [c.name, r.name, lvl]
	var wn := PackedStringArray()
	for b in c.weapons:
		wn.append(Items.BASES[b].name.to_lower())
	var an := PackedStringArray()
	for k in c.armor:
		an.append(Items.KIND_NAMES[k])
	head.tooltip_text = "%s\nОружие: %s\nБроня: %s\nРаса: %s" % [c.role, ", ".join(wn), ", ".join(an), r.passive]
	warn.visible = Rules.heavy_caster(me)
	warn.tooltip_text = "Латы мешают колдовать: умения дороже на 30%, мана восстанавливается вдвое медленнее"
	_show_gifts(Gifts.ids(me))
	var need := Rules.xp_to_next(lvl)
	xp_fill.size.x = (W - 16) * clampf(float(me.get("xp", 0)) / need, 0.0, 1.0)
	xp_label.text = "%d / %d" % [int(me.get("xp", 0)), need]
	xp_label.tooltip_text = "Опыт до следующего уровня"

	var pts := int(me.get("points", 0))
	points_label.text = "Очки: %d" % pts if pts > 0 else "Характеристики"
	for s in Rules.STATS:
		var bonus := int(r.stats.get(s, 0)) + int(c.stats.get(s, 0))
		var cell: Array = stat_cells[s]
		cell[0].text = str(Rules.stat(me, s)) + ("  (+%d)" % bonus if bonus > 0 else "")
		cell[0].add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if bonus > 0 else Color.WHITE)
		cell[1].visible = pts > 0
		var tip := "%s — %s" % [Rules.STAT_NAMES[s], Rules.STAT_HELP[s]]
		if bonus > 0:
			tip += "\nРаса и класс: +%d" % bonus
		tip += "\nСледующее очко:\n" + _preview(me, s)
		cell[2].tooltip_text = tip
		cell[0].tooltip_text = tip

	var rk := Rules.res_kind(me)
	var vals := {
		"hp": str(Rules.max_hp(me)),
		"res": str(int(me.get("res_max", Rules.res_max(me)))),
		"res_regen": ("%.1f" % Rules.res_regen(me)) if rk != "rage" else "бой",
		"dmg": "%.0f" % Rules.damage(me),
		"skill": _signed(Rules.skill_power(me) + Gifts.mod(me, "skill_dmg")),
		"crit": _pct(Rules.crit_chance(me)),
		"crit_dmg": "×%.2f" % (Rules.crit_mult(me) * Gifts.factor(me, "crit_dmg")),
		"aspd": _signed(Rules.attack_speed(me) - 1.0),
		"armor": str(Rules.armor(me)),
		"dodge": _pct(clampf(Gifts.mod(me, "dodge") + Rules.dodge_bonus(me), 0.0, Gifts.CAPS.dodge)),
		"cd": "−" + _pct(1.0 - Rules.cd_mult(me)),
		"heal": _signed(Rules.heal_power(me) - 1.0),
		"leech": _pct(clampf(Gifts.mod(me, "lifesteal"), 0.0, Gifts.CAPS.lifesteal)),
		"speed": _signed(Rules.speed_mult(me) - 1.0),
		"stam": "×%.2f" % Rules.stamina_regen(me),
		"thorns": _pct(clampf(Gifts.mod(me, "thorns"), 0.0, Gifts.CAPS.thorns)),
		"loot": "×%.2f" % Gifts.factor(me, "loot"),
		"find": _signed(minf(Gifts.CAPS.rare_find, Gifts.mod(me, "rare_find") + Rules.luck_find(me))),
		"coin": "×%.2f" % (Gifts.factor(me, "coin") * float(r.get("coin_mult", 1.0))),
		"xp": "×%.2f" % Gifts.factor(me, "xp"),
	}
	for d in _derived_defs():
		var cell: Array = cells[d[0]]
		var v: String = vals[d[0]]
		cell[0].text = v
		var name: String = d[2]
		if d[0] == "res" or d[0] == "res_regen":
			name = Rules.RES_NAMES[rk] + ("" if d[0] == "res" else " — восстановление")
		if d[0] == "res":
			cell[2].texture = Items.icon_at(RES_ICONS.get(rk, RES_ICONS.mana))
		# нулевые и единичные бонусы — приглушённо, чтобы глаз цеплялся за то, что есть
		var idle: bool = v in ["0%", "+0%", "−0%", "×1.00", "0"]
		cell[0].add_theme_color_override("font_color", Kit.DIM if idle else Kit.TEXT)
		cell[1].tooltip_text = "%s: %s\n%s" % [name, v, d[3]]
		cell[0].tooltip_text = cell[1].tooltip_text
