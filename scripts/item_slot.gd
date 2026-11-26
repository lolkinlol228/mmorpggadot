extends Control
## Ячейка предмета: вдавленная рамка (ui_kit), подсветка при наведении, иконка,
## уголок и свечение по редкости, искры у сияющих, своя всплывающая подсказка.

signal clicked

const Kit := preload("res://scripts/ui_kit.gd")
const SIZE := 26.0

static var _sb_normal: StyleBox
static var _sb_hover: StyleBox

var item = null              # Dictionary или null
var placeholder: Texture2D   # бледная иконка пустого слота снаряжения
var marked := false          # предмет выложен в обмен
var hovered := false
var t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _sb_normal == null:
		_sb_normal = Kit.box("slot", 0)
		_sb_hover = Kit.box("slot_hover", 0)
	mouse_entered.connect(func():
		hovered = true
		if item != null:
			Sfx.play("hover")
		queue_redraw())
	mouse_exited.connect(func():
		hovered = false
		queue_redraw())


func set_item(it, mark := false) -> void:
	item = it if (it is Dictionary and not it.is_empty()) else null
	marked = mark
	tooltip_text = "item" if item != null else ""
	queue_redraw()


func _process(delta: float) -> void:
	if item != null and (Items.is_jackpot(item) or int(item.rarity) >= 3):
		t += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_sb_hover if hovered else _sb_normal, r)
	if item == null:
		if placeholder:
			draw_texture_rect(placeholder, r.grow(-5), false, Color(1, 1, 1, 0.16))
		return
	var c := Items.color(item)
	var rar := int(item.rarity)
	if rar >= 1 or item.shiny:
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		var a := 0.08 + rar * 0.035 + (pulse * 0.12 if Items.is_jackpot(item) else 0.0)
		draw_rect(r.grow(-2), Color(c, a))
		draw_rect(r.grow(-1), Color(c, 0.9), false, 1.0)
	if marked:
		draw_rect(r.grow(-2), Color(1, 0.85, 0.3, 0.28))
	draw_texture_rect(Items.icon(item), r.grow(-3), false)
	if rar >= 1:
		var n := 3.0 + rar
		draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(1 + n, 1), Vector2(1, 1 + n)]), c)
	if item.shiny:
		for i in 3:
			var a := t * 2.0 + i * TAU / 3.0
			draw_rect(Rect2(size / 2 + Vector2(cos(a), sin(a)) * 10.0 - Vector2.ONE, Vector2(2, 2)), Items.SHINY_COLOR)
	if marked:
		draw_string(get_theme_default_font(), Vector2(size.x - 8, size.y - 2), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.85, 0.3))


func _make_custom_tooltip(_for_text: String) -> Object:
	if item == null:
		return null
	return make_item_tooltip(item)


static func make_item_tooltip(it: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var lines := Items.tooltip(it).split("\n")
	var col := Items.color(it)
	var name := Kit.label(lines[0], 18, col)
	v.add_child(name)
	v.add_child(Kit.label(lines[1], 9, col.darkened(0.15)))
	v.add_child(Kit.divider())
	for i in range(2, lines.size()):
		var c := Kit.TEXT
		if lines[i].begins_with("Урон") or lines[i].begins_with("Броня"):
			c = Color(0.6, 0.9, 0.55)
		elif lines[i].begins_with("★") or lines[i].begins_with("Уникальный"):
			c = Items.SHINY_COLOR
		elif lines[i].begins_with("Найден") or lines[i].begins_with("Серийный"):
			c = Kit.DIM
		elif lines[i].begins_with("Для класса"):
			c = Color(0.6, 0.9, 0.55) if _fits_me(it) else Kit.RED
		v.add_child(Kit.label(lines[i], 9, c))
		if lines[i].begins_with("Для класса") and not _fits_me(it):
			v.add_child(Kit.label("Чужой класс: только %d%% характеристик" % int(Rules.OFF_CLASS * 100), 9, Kit.RED))
	return v


## Свой ли предмет для героя этого игрока (в меню и вне игры — считаем своим).
static func _fits_me(it: Dictionary) -> bool:
	var scene = Engine.get_main_loop().current_scene
	if scene == null or not ("me" in scene) or scene.me.is_empty():
		return true
	return Rules.fits(scene.me, it)
