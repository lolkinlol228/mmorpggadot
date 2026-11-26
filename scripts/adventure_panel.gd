extends Node
## Мастерская и действия даров доступны из игры.

const Kit := preload("res://scripts/ui_kit.gd")
const Sites := preload("res://scripts/adventure_sites.gd")
const Gifts := preload("res://scripts/gifts.gd")
const Professions := preload("res://scripts/host_professions.gd")
const Relics := preload("res://scripts/relics.gd")

var game
var panel: PanelContainer
var rows: VBoxContainer
var workshop := false


## Создаёт окно без изменения основного HUD.
func build(root: Control) -> void:
	var window := Kit.window("Приключения и мастерская", close)
	panel = window[0]
	panel.position = Vector2(12, 94)
	root.add_child(panel)
	var body: VBoxContainer = window[1]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290, 250)
	body.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	panel.hide()


func close() -> void:
	panel.hide()


## Показывает активные действия или рецепты у мастерской.
func show_page(at_workshop: bool) -> void:
	if panel.visible and workshop == at_workshop:
		close()
		return
	workshop = at_workshop
	panel.show()
	refresh()


## Перестраивает список после подтверждённой хостом операции.
func refresh() -> void:
	if not panel.visible or game.me.is_empty():
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var p: Dictionary = game.me
	if workshop:
		_workshop_page(p)
		return
	rows.add_child(Kit.label("E — взаимодействие · R — помощь союзнику", 9, Kit.DIM))
	add_action("Поднять ближайшего павшего союзника", "rescue")
	add_action("Разделать ближайшую тушу", "field")
	if Gifts.has_flag(p, "tame"):
		add_action("Приручить ослабленного волка", "tame")
	if Gifts.has_flag(p, "time_stop"):
		add_action("Замедлить время", "time_stop")
	if Gifts.has_flag(p, "copy_gift"):
		add_action("Скопировать дар ближайшего союзника", "copy")
	if Gifts.has_flag(p, "recall300"):
		for camp in p.get("visited", {}):
			add_action("Переместиться: " + str(Sites.CAMP_NAMES[camp]), "recall", camp)
	if Gifts.has_flag(p, "cross_skill"):
		for id in Rules.SKILLS:
			if id not in Rules.class_of(p).skills:
				var active := " ✓" if p.get("cross_skill", "") == id else ""
				add_action("Вспомнить: " + str(Rules.SKILLS[id].name) + active, "cross", id)


const MAT_ICONS := {"ore": Vector2i(1, 17), "wood": Vector2i(0, 17), "cloth": Vector2i(5, 17), "hide": Vector2i(8, 17),
	"fish": Vector2i(3, 16), "herb": Vector2i(13, 11), "gem": Vector2i(15, 12), "star_iron": Vector2i(3, 17),
	"ancient_wood": Vector2i(0, 17), "moon_silk": Vector2i(6, 17), "prime_hide": Vector2i(8, 17)}
const FINE := {"ore": "star_iron", "wood": "ancient_wood", "cloth": "moon_silk", "hide": "prime_hide"}


## Мастерская: инструмент, материалы, рецепты (есть/нужно), разборка и самоцветы.
func _workshop_page(p: Dictionary) -> void:
	var tools: Dictionary = p.get("tools", {})
	var stock: Dictionary = p.get("materials", {})
	var coins := int(p.get("coins", 0))
	_header("Инструмент")
	var wear := float(tools.get("wear", 0.0))
	rows.add_child(Kit.label("Тир %d · износ %.1f / %d" % [int(tools.get("tier", 1)), wear, int(Professions.MAX_WEAR)], 9,
		Color(1.0, 0.55, 0.45) if wear >= Professions.MAX_WEAR * 0.7 else Kit.TEXT))
	add_action("Починить · 12 мед.", "repair", "", coins >= 12 and wear > 0.0)
	if int(tools.get("tier", 1)) < 2:
		add_action("Улучшить до тира 2 · 40 мед., руда %d/4" % int(stock.get("ore", 0)), "make", "tool",
			coins >= 40 and int(stock.get("ore", 0)) >= 4)
	_header("Материалы")
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(268, 0)
	flow.add_theme_constant_override("h_separation", 8)
	rows.add_child(flow)
	for material in stock:
		if int(stock[material]) > 0:
			flow.add_child(_chip(MAT_ICONS.get(str(material).trim_prefix("rich_"), Vector2i(1, 17)), "%d" % int(stock[material]),
				Professions.NAMES.get(material, material), str(material).begins_with("rich_") or material in FINE.values()))
	if flow.get_child_count() == 0:
		flow.add_child(Kit.label("пусто — собирай у источников (E)", 9, Kit.DIM))
	var levels: Dictionary = p.get("professions", {})
	for job in levels:
		rows.add_child(Kit.label("%s · ур. %d" % [Professions.PROFESSIONS[job], 1 + Professions.proficiency(p, job)], 9, Kit.DIM))
	_header("Рецепты")
	for base in Professions.RECIPES:
		var recipe: Array = Professions.RECIPES[base]
		var need := int(recipe[2])
		var have := int(stock.get(recipe[1], 0))
		add_action("%s · %s %d/%d" % [Items.BASES[base].name, Professions.NAMES[recipe[1]], have, need], "make", base, have >= need)
		if FINE.has(recipe[1]):
			var top := int(stock.get(FINE[recipe[1]], 0))
			var rich := int(stock.get("rich_" + str(recipe[1]), 0))
			if top >= need or rich >= need:
				var mat: String = FINE[recipe[1]] if top >= need else "rich_" + str(recipe[1])
				add_action("   ↳ из: %s (%d)" % [Professions.NAMES[mat], maxi(top, rich)], "make", base + ":fine")
	_relic_section(p, "Компоненты (из трофеев)", Relics.COMPONENTS)
	_relic_section(p, "Реликвии", Relics.RELICS)
	if Relics.count(p.inv, "recipe_scrap") > 0:
		_header("Рецепты")
		add_action("Собрать рецепт реликвии (случайный)", "relic", "scrap", Relics.can_make(p, "scrap"))
		var need := Kit.label("   " + Relics.need_text(p, "scrap", Professions.NAMES), 9, Kit.DIM)
		rows.add_child(need)
	var known: Array = p.get("recipes", [])
	if not known.is_empty():
		var names := PackedStringArray()
		for key in known:
			names.append(Items.BASES[key].name)
		var kl := Kit.label("Изучено: " + ", ".join(names), 9, Color(1.0, 0.8, 0.45))
		kl.autowrap_mode = TextServer.AUTOWRAP_WORD
		kl.custom_minimum_size = Vector2(268, 0)
		rows.add_child(kl)
	var gear: Array = []
	for item in p.inv:
		if Items.slot_of(item) in Items.SLOTS:
			gear.append(item)
	if not gear.is_empty():
		_header("Разобрать на материалы")
		for item in gear:
			add_action(Items.display_name(item), "salvage", item.uid)
	if int(stock.get("gem", 0)) > 0:
		for item in gear:
			if Items.slot_of(item) == "weapon" and not item.get("socketed", false):
				add_action("Вставить самоцвет: " + Items.display_name(item), "make", "gem:" + str(item.uid))
	if Gifts.has_flag(p, "transmute"):
		_header("Преобразование (дар)")
		for key in stock:
			if Professions.NAMES.has("rich_" + str(key)):
				add_action("5 × %s → %s" % [Professions.NAMES[key], Professions.NAMES["rich_" + str(key)]], "transmute", key,
					int(stock[key]) >= 5)


## Цепочка реликвий: по строке на рецепт — название, есть/нужно; кнопка активна, когда всего хватает.
## Компонент показывается, только если у героя есть хоть один нужный трофей, — чтобы не пугать списком.
func _relic_section(p: Dictionary, title: String, table: Dictionary) -> void:
	var shown := false
	for key in table:
		var started := table == Relics.RELICS
		for base in table[key].items:
			if Relics.count(p.inv, base) > 0:
				started = true
		if not started:
			continue
		if not shown:
			_header(title)
			shown = true
		var b: Dictionary = Items.BASES[key]
		var lock := "" if Relics.knows(p, key) else " [нет рецепта]"
		add_action("%s%s%s" % ["★ " if b.get("relic", false) else "", b.name, lock], "relic", key, Relics.can_make(p, key))
		var need := Kit.label("   " + Relics.need_text(p, key, Professions.NAMES), 9, Kit.DIM)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD
		need.custom_minimum_size = Vector2(268, 0)
		rows.add_child(need)


## Иконка материала с числом; название — во всплывающей подсказке. Редкие материалы подсвечены.
func _chip(cell: Vector2i, count: String, tip: String, rare: bool) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := Kit.icon(cell, 14)
	if rare:
		ic.modulate = Color(1.25, 1.15, 1.6)
	box.add_child(ic)
	box.add_child(Kit.label(count, 9, Kit.GOLD if rare else Kit.TEXT))
	return box


func _header(text: String) -> void:
	if rows.get_child_count() > 0:
		rows.add_child(Kit.divider())
	rows.add_child(Kit.label(text, 9, Kit.GOLD))


## Выдаёт кнопку, отправляющую только идентификатор действия. Неактивна, если не хватает ресурсов.
func add_action(label: String, operation: String, arg: String = "", enabled: bool = true) -> void:
	var b := Kit.button(label, func(): game.adventure(operation, arg))
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.add_child(b)
