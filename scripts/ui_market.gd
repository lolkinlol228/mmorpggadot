extends Control
## Простое окно рынка с поиском, размещением и получением выплат.

const Kit := preload("res://scripts/ui_kit.gd")
const ItemSlot := preload("res://scripts/item_slot.gd")
const Market := preload("res://scripts/host_market.gd")

var game
var window: PanelContainer
var body: VBoxContainer
var tabs: HBoxContainer
var filter_row: HBoxContainer
var search: LineEdit
var slot: OptionButton
var rarity: OptionButton
var sort: OptionButton
var rows: VBoxContainer
var scroll: ScrollContainer
var navigation: HBoxContainer
var page_label: Label
var previous: Button
var next: Button
var status: Label
var sale: VBoxContainer
var selected: Label
var price: SpinBox
var charges: Label
var post_button: Button
var confirmation: PanelContainer
var confirm_text: Label
var confirm_button: Button
var chosen := ""
var pending := ""
var tab := 0
var data := {}
var inventory_key := ""
var posted_request := false


## Создаёт окно в пределах базового экрана 640×360.
func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var built := Kit.window("Рынок", func(): game.ui.shop.close_all())
	window = built[0]
	body = built[1]
	window.position = Vector2(8, 28)
	window.custom_minimum_size = Vector2(624, 0)
	add_child(window)
	tabs = HBoxContainer.new()
	body.add_child(tabs)
	for i in 3:
		tabs.add_child(Kit.button(["Купить", "Продать", "Мои лоты"][i], set_tab.bind(i)))
	status = Kit.label("", 9, Kit.GOLD)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(status)
	build_filters()
	build_sale()
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 172)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	navigation = HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	previous = Kit.button("←", change_page.bind(-1))
	next = Kit.button("→", change_page.bind(1))
	page_label = Kit.label("")
	navigation.add_child(previous)
	navigation.add_child(page_label)
	navigation.add_child(next)
	body.add_child(navigation)
	build_confirmation()
	window.hide()


## Поля поиска передаются хосту и применяются к полной базе лотов.
func build_filters() -> void:
	filter_row = HBoxContainer.new()
	body.add_child(filter_row)
	search = LineEdit.new()
	search.placeholder_text = "Название"
	search.max_length = 80
	search.custom_minimum_size.x = 125
	search.text_submitted.connect(func(_text): find())
	filter_row.add_child(search)
	slot = OptionButton.new()
	for key in ["", "weapon", "head", "body", "feet", "offhand", "use"]:
		slot.add_item("Все слоты" if key == "" else Items.SLOT_NAMES[key])
		slot.set_item_metadata(slot.item_count - 1, key)
	filter_row.add_child(slot)
	rarity = OptionButton.new()
	rarity.add_item("Любая редкость")
	for label in Items.RARITY_NAMES:
		rarity.add_item(label)
	filter_row.add_child(rarity)
	sort = OptionButton.new()
	sort.add_item("Цена ↑")
	sort.add_item("Цена ↓")
	filter_row.add_child(sort)
	filter_row.add_child(Kit.button("Найти", find))


## Поля продажи отображают залог и предварительную комиссию.
func build_sale() -> void:
	sale = VBoxContainer.new()
	body.add_child(sale)
	selected = Kit.label("Выберите вещь из списка или сумки.")
	selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sale.add_child(selected)
	var row := HBoxContainer.new()
	sale.add_child(row)
	row.add_child(Kit.label("Цена в медяках"))
	price = SpinBox.new()
	price.min_value = 1
	price.max_value = Market.MAX_PRICE
	price.step = 1
	price.update_on_text_changed = true
	price.allow_greater = false
	price.custom_minimum_size.x = 130
	price.value_changed.connect(func(_value): update_charges())
	row.add_child(price)
	post_button = Kit.button("Выставить", post)
	row.add_child(post_button)
	charges = Kit.label("", 9, Kit.DIM)
	charges.tooltip_text = "Залог не возвращается. Комиссия удерживается при продаже и учитывает дары продавца и покупателя."
	sale.add_child(charges)


## Подтверждение содержит название, серийный номер и полную цену лота.
func build_confirmation() -> void:
	var built := Kit.window("Подтвердить покупку", func(): confirmation.hide())
	confirmation = built[0]
	confirmation.position = Vector2(100, 100)
	confirmation.custom_minimum_size.x = 440
	add_child(confirmation)
	confirm_text = Kit.label("")
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size.x = 400
	built[1].add_child(confirm_text)
	var buttons := HBoxContainer.new()
	built[1].add_child(buttons)
	confirm_button = Kit.button("Купить", confirm_buy)
	buttons.add_child(confirm_button)
	buttons.add_child(Kit.button("Отмена", func(): confirmation.hide()))
	confirmation.hide()


## Открывает рынок и запрашивает свежую страницу.
func open() -> void:
	window.show()
	chosen = ""
	posted_request = false
	data.clear()
	set_tab(0)
	find()


## Закрывает окно при уходе от доски или по Escape.
func close() -> void:
	window.hide()
	confirmation.hide()
	pending = ""


## Переключает вкладку с сохранением введённых цены и фильтров.
func set_tab(value: int) -> void:
	tab = value
	confirmation.hide()
	filter_row.visible = tab == 0
	sale.visible = tab == 1
	navigation.visible = tab == 0
	scroll.custom_minimum_size.y = 120 if tab == 1 else 172
	render()


## Отправляет поиск с первой страницы.
func find() -> void:
	query(0)


## Повторяет поиск при смене страницы.
func change_page(delta: int) -> void:
	query(maxi(0, int(data.get("page", 0)) + delta))


## Составляет только разрешённые фильтры.
func query(number: int) -> void:
	game.client_market.request("search", {"text": search.text, "slot": slot.get_item_metadata(slot.selected),
		"rarity": rarity.selected - 1, "descending": sort.selected == 1, "page": number})


## Принимает подтверждённые хостом данные после поиска или сделки.
func receive(value: Dictionary) -> void:
	data = value
	posted_request = false
	if window.visible:
		render()


## Перерисовывает список после обновления инвентаря или кошелька.
func refresh_inventory() -> void:
	if not window.visible:
		return
	status.text = "Кошелёк %s" % Items.format_coins(int(game.me.get("coins", 0)))
	var key := JSON.stringify(game.me.get("inv", []))
	if key != inventory_key:
		inventory_key = key
		if tab == 1:
			render()


## Показывает содержимое выбранной вкладки.
func render() -> void:
	if not is_instance_valid(rows):
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	status.text = "Кошелёк %s" % Items.format_coins(int(game.me.get("coins", 0)))
	if tab == 1:
		for item in game.me.get("inv", []):
			if item.base != "coins":
				var last := Market.price_from_history(item, data.get("history", []))
				var detail := "Продаж этой базы и редкости пока нет." if last <= 0 else "Последняя цена " + Items.format_coins(last)
				add_item_row(item, detail, "Выбрать", select_item.bind(item))
		update_charges()
		return
	if data.is_empty():
		rows.add_child(Kit.label("Загрузка…", 9, Kit.DIM))
		return
	var listings: Array = data.get("lots", []) if tab == 0 else data.get("own", [])
	if tab == 2:
		var summary := HBoxContainer.new()
		rows.add_child(summary)
		summary.add_child(Kit.label("Выплаты %s · Возвраты %d" % [Items.format_coins(int(data.payout)), int(data.returns)]))
		summary.add_child(Kit.button("Забрать", collect))
	if listings.is_empty():
		rows.add_child(Kit.label("Лотов нет.", 9, Kit.DIM))
	for lot in listings:
		var last := int(lot.get("last_price", 0))
		var detail := "%s · %s" % [Items.format_coins(int(lot.price)), lot.seller]
		if last > 0:
			detail += " · Последняя цена " + Items.format_coins(last)
		if tab == 2:
			var hours := maxf(0.0, (int(lot.posted_at) + Market.LIFETIME - Time.get_unix_time_from_system()) / 3600.0)
			detail += " · Осталось %.1f ч" % hours
		add_item_row(lot.item, detail, "Купить" if tab == 0 else "Снять",
			ask_buy.bind(lot) if tab == 0 else cancel.bind(lot.id), tab == 0 and lot.seller == Net.player_name)
	page_label.text = "%d / %d" % [int(data.page) + 1, int(data.pages)]
	previous.disabled = int(data.page) <= 0
	next.disabled = int(data.page) + 1 >= int(data.pages)


## Добавляет привычную ячейку с подсказкой Tips и читаемым именем вещи.
func add_item_row(item: Dictionary, detail: String, action: String, callback: Callable, disabled: bool = false) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var cell := ItemSlot.new()
	cell.set_item(item)
	row.add_child(cell)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Kit.label(Items.display_name(item), 9, Items.color(item))
	name_label.tooltip_text = Items.tooltip(item)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	if not detail.is_empty():
		var info := Kit.label(detail, 9, Kit.DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(info)
	var button := Kit.button(action, callback)
	button.disabled = disabled
	row.add_child(button)


## Выбирает только вещь из текущего инвентаря.
func select_item(item: Dictionary) -> void:
	chosen = str(item.uid)
	set_tab(1)


## Пересчитывает залог и комиссию без изменения денег.
func update_charges() -> void:
	var item := {}
	for candidate in game.me.get("inv", []):
		if candidate.uid == chosen:
			item = candidate
			break
	selected.text = "Выберите вещь из списка или сумки." if item.is_empty() else Items.display_name(item)
	var amount := int(price.value)
	var rate := maxf(0.01, 0.05 * float(data.get("seller_factor", 1.0)))
	var fee := Market.commission(amount, float(data.get("seller_factor", 1.0)), 1.0)
	charges.text = "Залог %s · Комиссия %s (%.1f%%) × дары покупателя, минимум 1%%" % [Items.format_coins(Market.deposit(amount)), Items.format_coins(fee), rate * 100.0]
	post_button.disabled = item.is_empty() or posted_request or int(game.me.get("coins", 0)) < Market.deposit(amount)


## Размещает выбранную вещь по введённой цене.
func post() -> void:
	if posted_request or chosen.is_empty():
		return
	price.apply()
	posted_request = true
	update_charges()
	game.client_market.request("post", {"uid": chosen, "price": int(price.value)})


## Запрашивает подтверждение покупки.
func ask_buy(lot: Dictionary) -> void:
	pending = str(lot.id)
	confirm_text.text = "%s\nЦена %s" % [Items.display_name(lot.item), Items.format_coins(int(lot.price))]
	confirm_text.tooltip_text = Items.tooltip(lot.item)
	confirmation.show()


## Отправляет идентификатор лота после явного подтверждения.
func confirm_buy() -> void:
	if pending.is_empty():
		return
	var id := pending
	pending = ""
	confirmation.hide()
	game.client_market.request("buy", {"id": id})


## Снимает собственный лот.
func cancel(id: String) -> void:
	game.client_market.request("cancel", {"id": id})


## Получает доступную выплату и возвраты.
func collect() -> void:
	game.client_market.request("collect")


## Ввод названия и цены не должен двигать героя.
func is_typing() -> bool:
	return window.visible and (search.has_focus() or price.get_line_edit().has_focus())
