extends Node
## Мастерская и действия даров доступны из игры.

const Kit := preload("res://scripts/ui_kit.gd")
const Sites := preload("res://scripts/adventure_sites.gd")
const Gifts := preload("res://scripts/gifts.gd")
const Professions := preload("res://scripts/host_professions.gd")

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
	scroll.custom_minimum_size = Vector2(280, 230)
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
		var tools: Dictionary = p.get("tools", {})
		rows.add_child(Kit.label("Инструмент: тир %d · износ %.1f/10" % [tools.get("tier", 1), tools.get("wear", 0.0)], 9))
		var stock: Dictionary = p.get("materials", {})
		var counts := PackedStringArray()
		for material in stock:
			if stock[material] > 0:
				counts.append("%s ×%d" % [Professions.NAMES[material], stock[material]])
		var inventory := Kit.label("Материалы: " + (", ".join(counts) if not counts.is_empty() else "пусто"), 9)
		inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(inventory)
		var levels: Dictionary = p.get("professions", {})
		for job in levels:
			rows.add_child(Kit.label("%s · ур. %d · %.1f опыта" % [Professions.PROFESSIONS[job], 1 + Professions.proficiency(p, job), levels[job]], 9, Kit.DIM))
		add_action("Починить инструмент (12 мед.)", "repair")
		add_action("Улучшить инструмент (40 мед., 4 руды)", "make", "tool")
		for base in Professions.RECIPES:
			var recipe: Array = Professions.RECIPES[base]
			add_action("%s (%s ×%d)" % [Items.BASES[base].name, Professions.NAMES[recipe[1]], recipe[2]], "make", base)
			if base not in ["meal", "scroll", "book"]:
				add_action(" Из материалов второго тира", "make", base + ":fine")
		for item in p.inv:
			if Items.slot_of(item) in Items.SLOTS:
				add_action("Разобрать: " + Items.display_name(item), "salvage", item.uid)
				if stock.get("gem", 0) > 0 and Items.slot_of(item) == "weapon" and not item.get("socketed", false):
					add_action("Вставить самоцвет: " + Items.display_name(item), "make", "gem:" + str(item.uid))
		if Gifts.has_flag(p, "transmute"):
			for key in stock:
				if int(stock[key]) >= 5 and Professions.NAMES.has("rich_" + str(key)):
					add_action("Преобразовать: " + str(Professions.NAMES[key]), "transmute", key)
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


## Выдаёт кнопку, отправляющую только идентификатор действия.
func add_action(label: String, operation: String, arg: String = "") -> void:
	rows.add_child(Kit.button(label, func(): game.adventure(operation, arg)))
