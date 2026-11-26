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
	var counts := PackedStringArray()
	for material in stock:
		if int(stock[material]) > 0:
			counts.append("%s ×%d" % [Professions.NAMES.get(material, material), int(stock[material])])
	var inventory := Kit.label(", ".join(counts) if not counts.is_empty() else "пусто — собирай у отмеченных источников (E)", 9,
		Kit.TEXT if not counts.is_empty() else Kit.DIM)
	inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.custom_minimum_size = Vector2(268, 0)
	rows.add_child(inventory)
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
