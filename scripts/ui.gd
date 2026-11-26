extends CanvasLayer
## Окна интерфейса: сумка с куклой, обмен, приглашение, меню. HUD — в hud.gd.
## Внешний API (refresh, add_feed, open_trade…) используется из game.gd.

const Kit := preload("res://scripts/ui_kit.gd")
const ItemSlot := preload("res://scripts/item_slot.gd")
const Hud := preload("res://scripts/hud.gd")
const DollView := preload("res://scripts/doll_view.gd")
const UiShop := preload("res://scripts/ui_shop.gd")
const CharWindow := preload("res://scripts/char_window.gd")

var game
var root: Control
var hud
var inv_panel: PanelContainer
var doll
var equip_slots := {}
var inv_slots: Array = []
var stats_label: Label
var trade_panel: PanelContainer
var trade_title: Label
var give_grid: GridContainer
var get_grid: GridContainer
var my_status: Label
var their_status: Label
var invite_panel: PanelContainer
var invite_label: Label
var menu_panel: PanelContainer
var invite_from := -1
var inv_grid: GridContainer
var shop                         # окна хранилища/лавки/доски/разговора
var trading := false
var charwin                      # окно героя (C)
var my_offer: Array = []


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Kit.make_theme()
	add_child(root)
	hud = Hud.new()
	hud.game = game
	hud.ui = self
	root.add_child(hud)
	hud.build()
	_build_inventory()
	_build_trade()
	_build_invite()
	_build_menu()
	shop = UiShop.new()
	shop.game = game
	shop.ui = self
	root.add_child(shop)
	shop.build()
	charwin = CharWindow.new()
	charwin.game = game
	add_child(charwin)
	charwin.build(root)


# ---------- для game.gd ----------

func refresh_hp() -> void:
	if not game.me.is_empty():
		hud.refresh(game.me)


func refresh() -> void:
	var me: Dictionary = game.me
	if me.is_empty():
		return
	hud.refresh(me)
	charwin.refresh(me)
	doll.look = me.get("look", {})
	doll.equip = me.equip
	var jackpots := 0
	for it in me.inv + me.equip.values():
		if it is Dictionary and Items.is_jackpot(it):
			jackpots += 1
	stats_label.text = "Урон   %.0f\nБроня  %d\nМега-находки %d" % [
		Rules.damage(me), Rules.armor(me), jackpots]
	shop.refresh()
	for slot in equip_slots:
		equip_slots[slot].set_item(me.equip.get(slot))
	var capacity := maxi(me.inv.size(), Items.bag_capacity(me))
	_fill_inv_slots(capacity)
	for i in inv_slots.size():
		inv_slots[i].visible = i < capacity
		var it = me.inv[i] if i < me.inv.size() else null
		inv_slots[i].set_item(it, it is Dictionary and my_offer.has(it.uid))


func add_feed(text: String, color: Color) -> void:
	hud.add_line(text, color)


func is_typing() -> bool:
	return hud.is_typing()


func open_chat() -> void:
	hud.open_chat()


func close_panels() -> void:
	if shop.mode != "":
		shop.close_all()
	elif trading:
		game.cancel_trade()
	elif inv_panel.visible:
		toggle_inventory()
	elif charwin.panel.visible:
		charwin.toggle()
	else:
		toggle_menu()


# ---------- сумка ----------

func _build_inventory() -> void:
	var w := Kit.window("Сумка", toggle_inventory)
	inv_panel = w[0]
	var body: VBoxContainer = w[1]
	inv_panel.anchor_left = 1.0
	inv_panel.anchor_right = 1.0
	inv_panel.offset_left = -232
	inv_panel.offset_right = -6
	inv_panel.offset_top = 92
	inv_panel.visible = false
	root.add_child(inv_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	# кукла: слоты вокруг персонажа
	var paper := Control.new()
	paper.custom_minimum_size = Vector2(118, 118)
	top.add_child(paper)
	doll = DollView.new()
	doll.position = Vector2(27, 24)
	paper.add_child(doll)
	var spots := {"head": Vector2(46, 0), "weapon": Vector2(0, 46), "body": Vector2(92, 46), "feet": Vector2(46, 92)}
	for slot in Items.SLOTS:
		var s = ItemSlot.new()
		s.placeholder = Items.icon_at(Items.SLOT_ICONS[slot])
		s.position = spots[slot]
		s.clicked.connect(_on_equip_pressed.bind(slot))
		paper.add_child(s)
		equip_slots[slot] = s
	stats_label = Kit.label("", 9)
	stats_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stats_label)
	body.add_child(Kit.divider())
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	body.add_child(grid)
	inv_grid = grid
	_fill_inv_slots(Items.MAX_INV)
	var hint := Kit.label("клик — надеть / выпить  ·  у хранилища — сдать  ·  у торговки — продать", 9, Kit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)


## Добавляет ячейки сумки на героев с увеличенной вместимостью.
func _fill_inv_slots(capacity: int) -> void:
	while inv_slots.size() < capacity:
		var s = ItemSlot.new()
		s.clicked.connect(_on_inv_pressed.bind(inv_slots.size()))
		inv_grid.add_child(s)
		inv_slots.append(s)


func toggle_inventory() -> void:
	if trading:
		inv_panel.show()
		return
	inv_panel.visible = not inv_panel.visible
	Sfx.play("open" if inv_panel.visible else "close")
	refresh()


func _on_inv_pressed(i: int) -> void:
	var me: Dictionary = game.me
	if i >= me.inv.size():
		return
	var uid: String = me.inv[i].uid
	if trading:
		if my_offer.has(uid):
			my_offer.erase(uid)
		elif my_offer.size() < 8:
			my_offer.append(uid)
		Sfx.play("toggle")
		game.send_trade_offer(my_offer)
		refresh()
	elif shop.bag_click(me.inv[i]):
		pass
	elif me.inv[i].base == "potion":
		game.eco("use", uid)
		Sfx.play("pickup")
	else:
		game.request_equip(uid)


func _on_equip_pressed(slot: String) -> void:
	if not trading and game.me.equip.has(slot):
		game.request_unequip(slot)


# ---------- обмен ----------

func _build_trade() -> void:
	var w := Kit.window("Обмен", func(): game.cancel_trade())
	trade_panel = w[0]
	var body: VBoxContainer = w[1]
	trade_title = w[2]
	trade_panel.anchor_left = 0.5
	trade_panel.anchor_right = 0.5
	trade_panel.offset_left = -250
	trade_panel.offset_right = -20
	trade_panel.offset_top = 70
	trade_panel.visible = false
	root.add_child(trade_panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	body.add_child(cols)
	var a := _trade_column(cols, "Ты отдаёшь")
	give_grid = a[0]
	my_status = a[1]
	var b := _trade_column(cols, "Ты получаешь")
	get_grid = b[0]
	their_status = b[1]
	body.add_child(Kit.divider())
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 6)
	body.add_child(btns)
	btns.add_child(Kit.button("Подтвердить", func(): game.confirm_trade()))
	btns.add_child(Kit.button("Отмена", func(): game.cancel_trade()))
	var hint := Kit.label("Клик по вещи в сумке — положить / убрать.\nЛюбое изменение снимает подтверждения.", 9, Kit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)


func _trade_column(parent: Control, title: String) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	col.add_child(Kit.label(title, 9, Kit.DIM))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 0)
	g.add_theme_constant_override("v_separation", 0)
	col.add_child(g)
	for i in 8:
		g.add_child(ItemSlot.new())
	var st := Kit.label("…", 9)
	col.add_child(st)
	return [g, st]


func _fill(grid: GridContainer, items: Array) -> void:
	for i in grid.get_child_count():
		grid.get_child(i).set_item(items[i] if i < items.size() else null)


func open_trade(other_name: String) -> void:
	trading = true
	my_offer = []
	invite_panel.hide()
	trade_title.text = "Обмен · " + other_name
	trade_panel.show()
	inv_panel.show()
	Sfx.play("open")
	set_trade_state([], [], false, false)


func set_trade_state(mine: Array, theirs: Array, my_ok: bool, their_ok: bool) -> void:
	my_offer = []
	for it in mine:
		my_offer.append(it.uid)
	_fill(give_grid, mine)
	_fill(get_grid, theirs)
	my_status.text = "✔ ты готов" if my_ok else "ты думаешь…"
	their_status.text = "✔ партнёр готов" if their_ok else "партнёр думает…"
	my_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5) if my_ok else Kit.DIM)
	their_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5) if their_ok else Kit.DIM)
	refresh()


func close_trade(msg: String) -> void:
	trading = false
	my_offer = []
	trade_panel.hide()
	Sfx.play("confirm" if msg.contains("завершён") else "error")
	add_feed(msg, Kit.GOLD)
	refresh()


# ---------- приглашение и меню ----------

func _build_invite() -> void:
	invite_panel = PanelContainer.new()
	invite_panel.anchor_left = 0.5
	invite_panel.anchor_right = 0.5
	invite_panel.offset_left = -100
	invite_panel.offset_right = 100
	invite_panel.offset_top = 80
	invite_panel.visible = false
	root.add_child(invite_panel)
	var v := VBoxContainer.new()
	invite_panel.add_child(v)
	invite_label = Kit.label("", 9, Kit.GOLD)
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(invite_label)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	h.add_child(Kit.button("Принять", func(): _answer(true)))
	h.add_child(Kit.button("Отклонить", func(): _answer(false)))


func show_invite(from: int, from_name: String) -> void:
	invite_from = from
	invite_label.text = "%s предлагает обмен" % from_name
	invite_panel.show()
	Sfx.play("invite")


func _answer(accept: bool) -> void:
	invite_panel.hide()
	game.answer_trade(invite_from, accept)


func _build_menu() -> void:
	var w := Kit.window("Меню", toggle_menu)
	menu_panel = w[0]
	var body: VBoxContainer = w[1]
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -80
	menu_panel.offset_right = 80
	menu_panel.offset_top = -50
	menu_panel.visible = false
	root.add_child(menu_panel)
	body.add_child(Kit.button("Продолжить", toggle_menu))
	body.add_child(Kit.button("Выйти в главное меню", func(): game.leave_game()))


func toggle_menu() -> void:
	menu_panel.visible = not menu_panel.visible
	Sfx.play("open" if menu_panel.visible else "close")
