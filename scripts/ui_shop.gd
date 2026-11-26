extends Control
## Окна взаимодействия: хранилище (банк), лавка, доска заказов, разговор с жителем.
## Пока открыто хранилище или лавка, клик по вещи в сумке кладёт её в хранилище / продаёт.

const Kit := preload("res://scripts/ui_kit.gd")
const ItemSlot := preload("res://scripts/item_slot.gd")

var game
var ui
var mode := ""                 # "", "bank", "shop", "board", "talk"
var bank_win: PanelContainer
var bank_slots: Array = []
var shop_win: PanelContainer
var board_win: PanelContainer
var board_list: VBoxContainer
var talk_win: PanelContainer
var talk_title: Label
var talk_text: Label


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bank()
	_build_shop()
	_build_board()
	_build_talk()


func _place_left(p: PanelContainer) -> void:
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.offset_left = -300
	p.offset_right = -20
	p.offset_top = 60
	p.visible = false
	add_child(p)


func open(kind: String, spot: Dictionary) -> void:
	close_all()
	mode = kind
	match kind:
		"bank":
			bank_win.show()
			ui.inv_panel.show()
			_refresh_bank()
		"shop":
			shop_win.show()
			ui.inv_panel.show()
		"board":
			board_win.show()
			_refresh_board()
		"talk":
			talk_title.text = spot.label
			talk_text.text = "«%s»" % (spot.lines as Array).pick_random()
			talk_win.show()
	Sfx.play("open")
	ui.refresh()


func close_all() -> void:
	if mode != "":
		Sfx.play("close")
	mode = ""
	for w in [bank_win, shop_win, board_win, talk_win]:
		w.hide()


func refresh() -> void:
	if mode == "bank":
		_refresh_bank()
	elif mode == "board":
		_refresh_board()


## Клик по вещи в сумке, пока открыто хранилище/лавка. true — клик обработан здесь.
func bag_click(it: Dictionary) -> bool:
	if mode == "bank":
		game.eco("deposit", it.uid)
		Sfx.play("drop")
		return true
	if mode == "shop":
		game.eco("sell", it.uid)
		return true
	return false


# ---------- хранилище ----------

func _build_bank() -> void:
	var w := Kit.window("Хранилище", close_all)
	bank_win = w[0]
	var body: VBoxContainer = w[1]
	_place_left(bank_win)
	body.add_child(Kit.label("Клик по вещи в сумке — положить, здесь — забрать.", 9, Kit.DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	body.add_child(grid)
	for i in Items.MAX_BANK:
		var s = ItemSlot.new()
		s.clicked.connect(_on_bank_slot.bind(i))
		grid.add_child(s)
		bank_slots.append(s)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	row.add_child(Kit.button("Сложить всё из сумки", func(): game.eco("deposit_all")))


func _refresh_bank() -> void:
	var bank: Array = game.me.get("bank", [])
	for i in bank_slots.size():
		bank_slots[i].set_item(bank[i] if i < bank.size() else null)


func _on_bank_slot(i: int) -> void:
	var bank: Array = game.me.get("bank", [])
	if i < bank.size():
		game.eco("withdraw", bank[i].uid)
		Sfx.play("pickup")


# ---------- лавка ----------

func _build_shop() -> void:
	var w := Kit.window("Лавка Миры", close_all)
	shop_win = w[0]
	var body: VBoxContainer = w[1]
	_place_left(shop_win)
	body.add_child(Kit.label("Клик по товару — купить. Клик по вещи в сумке — продать.", 9, Kit.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	body.add_child(grid)
	for base in Items.SHOP_STOCK:
		var it := Items.make_potion(1) if base == "potion" else Items.make(base, 0, "Лавка Миры", false)
		var cell := HBoxContainer.new()
		var s = ItemSlot.new()
		s.set_item(it)
		s.clicked.connect(func():
			Sfx.play("click")
			game.eco("buy", base))
		cell.add_child(s)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.add_child(Kit.label(Items.BASES[base].name, 9))
		v.add_child(Kit.label(Items.format_coins(Items.value(it) * 3), 9, Kit.GOLD))
		cell.add_child(v)
		grid.add_child(cell)


# ---------- доска заказов ----------

func _build_board() -> void:
	var w := Kit.window("Доска заказов", close_all)
	board_win = w[0]
	_place_left(board_win)
	board_list = w[1]


func _refresh_board() -> void:
	for c in board_list.get_children():
		c.queue_free()
	var prog: Dictionary = game.me.get("bounties", {})
	for b in Items.BOUNTIES:
		var n := int(prog.get(b.id, 0))
		var done := n >= int(b.need)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Kit.label(b.title, 9, Kit.GOLD))
		v.add_child(Kit.label("%s — %d / %d" % [b.text, n, b.need], 9, Color(0.6, 0.95, 0.55) if done else Kit.TEXT))
		v.add_child(Kit.label("Награда: " + Items.format_coins(int(b.reward)), 9, Kit.DIM))
		row.add_child(v)
		var btn := Kit.button("Забрать" if done else "…", func(): game.eco("claim", b.id))
		btn.disabled = not done
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		board_list.add_child(row)
		board_list.add_child(Kit.divider())


# ---------- разговор ----------

func _build_talk() -> void:
	var w := Kit.window("", close_all)
	talk_win = w[0]
	talk_title = w[2]
	var body: VBoxContainer = w[1]
	talk_win.anchor_left = 0.5
	talk_win.anchor_right = 0.5
	talk_win.anchor_top = 1.0
	talk_win.anchor_bottom = 1.0
	talk_win.offset_left = -150
	talk_win.offset_right = 150
	talk_win.offset_top = -120
	talk_win.offset_bottom = -44
	talk_win.visible = false
	add_child(talk_win)
	talk_text = Kit.label("", 9)
	talk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	talk_text.custom_minimum_size = Vector2(280, 0)
	body.add_child(talk_text)
	body.add_child(Kit.button("До встречи", close_all))
