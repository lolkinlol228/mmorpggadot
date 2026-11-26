extends Node
## Окно персонажа (C): раса и её бонус, уровень и опыт, свободные очки, характеристики с «+»
## и итоговые параметры, которые из них получаются (урон, крит, броня, перезарядка…).

const Kit := preload("res://scripts/ui_kit.gd")

var game
var panel: PanelContainer
var title: Label
var race_label: Label
var passive_label: Label
var xp_fill: ColorRect
var xp_label: Label
var points_label: Label
var stat_rows := {}          # stat -> [value label, + button]
var derived: Label


func build(parent: Control) -> void:
	var w := Kit.window("Герой", toggle)
	panel = w[0]
	title = w[2]
	var body: VBoxContainer = w[1]
	panel.offset_left = 6
	panel.offset_right = 206
	panel.offset_top = 62
	panel.visible = false
	parent.add_child(panel)
	race_label = Kit.label("", 9, Kit.GOLD)
	body.add_child(race_label)
	passive_label = Kit.label("", 9, Color(0.6, 0.9, 0.6))
	passive_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	passive_label.custom_minimum_size = Vector2(186, 0)
	body.add_child(passive_label)
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0.05, 0.05, 0.08)
	xp_bg.custom_minimum_size = Vector2(186, 9)
	body.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.45, 0.55, 0.95)
	xp_fill.size = Vector2(0, 9)
	xp_bg.add_child(xp_fill)
	xp_label = Kit.label("", 9)
	xp_label.size = Vector2(186, 9)
	xp_label.position = Vector2(0, -2)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_bg.add_child(xp_label)
	body.add_child(Kit.divider())
	points_label = Kit.label("", 9, Kit.GOLD)
	body.add_child(points_label)
	for s in Rules.STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var n := Kit.label(Rules.STAT_NAMES[s], 9)
		n.custom_minimum_size = Vector2(62, 0)
		n.tooltip_text = Rules.STAT_HELP[s]
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(n)
		var v := Kit.label("", 9, Color.WHITE)
		v.custom_minimum_size = Vector2(70, 0)
		row.add_child(v)
		var b := Kit.button("+", func(): game.add_stat(s))
		b.tooltip_text = Rules.STAT_HELP[s]
		row.add_child(b)
		body.add_child(row)
		stat_rows[s] = [v, b]
	body.add_child(Kit.divider())
	derived = Kit.label("", 9, Kit.TEXT)
	body.add_child(derived)


func toggle() -> void:
	panel.visible = not panel.visible
	Sfx.play("open" if panel.visible else "close")
	refresh(game.me)


func refresh(me: Dictionary) -> void:
	if me.is_empty() or not panel.visible:
		return
	var r: Dictionary = Rules.race_of(me)
	var sex := "мужчина" if str(me.get("look", {}).get("sex", "m")) == "m" else "женщина"
	race_label.text = "%s, %s  ·  уровень %d" % [r.name, sex, int(me.get("level", 1))]
	var sk: Dictionary = Rules.SKILLS[r.skill]
	passive_label.text = "Бонус расы: %s\nУмение расы [R]: %s — %s" % [r.passive, sk.name, sk.desc]
	var need := Rules.xp_to_next(int(me.get("level", 1)))
	xp_fill.size.x = 186.0 * clampf(float(me.get("xp", 0)) / need, 0.0, 1.0)
	xp_label.text = "опыт %d / %d" % [int(me.get("xp", 0)), need]
	var pts := int(me.get("points", 0))
	points_label.text = "Свободных очков: %d" % pts if pts > 0 else "Очки дают уровни (+%d за уровень)" % Rules.POINTS_PER_LEVEL
	for s in Rules.STATS:
		var bonus := int(r.stats.get(s, 0))
		stat_rows[s][0].text = "%d%s" % [Rules.stat(me, s), ("  (раса +%d)" % bonus) if bonus > 0 else ""]
		stat_rows[s][1].visible = pts > 0
	derived.text = "Здоровье  %d\nУрон  %.0f\nКрит  %.0f%%\nСкорость атаки  +%.0f%%\nБроня  %d\nПерезарядка умений  −%.0f%%\nСила лечения  +%.0f%%" % [
		Rules.max_hp(me), Rules.damage(me), Rules.crit_chance(me) * 100.0, (Rules.attack_speed(me) - 1.0) * 100.0,
		Rules.armor(me), (1.0 - Rules.cd_mult(me)) * 100.0, (Rules.heal_power(me) - 1.0) * 100.0]
