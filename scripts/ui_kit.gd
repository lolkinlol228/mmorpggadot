extends RefCounted
## Общий стиль интерфейса: текстуры из tools/art/ui_kit.py, шрифт Silver (9 / 18 px в базе 640×360).

const DIR := "res://assets/custom/ui/"
const TEXT := Color(0.88, 0.85, 0.8)
const DIM := Color(0.58, 0.56, 0.62)
const GOLD := Color(0.95, 0.78, 0.42)
const RED := Color(0.9, 0.32, 0.3)
const MARGINS := {
	"panel": [8, 8, 8, 8], "title": [8, 8, 8, 8], "button": [4, 4, 4, 4], "button_hover": [4, 4, 4, 4],
	"button_pressed": [4, 4, 4, 4], "slot": [4, 4, 4, 4], "slot_hover": [4, 4, 4, 4],
	"tooltip": [4, 4, 4, 4], "bar_frame": [4, 3, 4, 3], "chat": [4, 4, 4, 4],
}

static var _cache := {}


static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".png")
	return _cache[name]


static func box(name: String, pad := -1.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	var m: Array = MARGINS.get(name, [4, 4, 4, 4])
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	var p := pad if pad >= 0.0 else float(m[0]) + 2.0
	sb.set_content_margin_all(p)
	return sb


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 9
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	th.set_constant("line_spacing", "Label", -2)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		var name: String = {"hover": "button_hover", "pressed": "button_pressed"}.get(s, "button")
		var sb := box(name)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 3
		th.set_stylebox(s, "Button", sb if s != "focus" else StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", GOLD)
	th.set_color("font_pressed_color", "Button", DIM)
	th.set_stylebox("normal", "LineEdit", box("chat", 3))
	th.set_stylebox("focus", "LineEdit", box("chat", 3))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_stylebox("panel", "TooltipPanel", box("tooltip", 4))
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font_size("font_size", "TooltipLabel", 9)
	th.set_stylebox("panel", "PanelContainer", box("panel"))
	return th


static func label(text: String, size := 9, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	if size != 9:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_entered.connect(func(): Sfx.play("hover"))
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


static func icon(cell: Vector2i, size := 16) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Items.icon_at(cell)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func divider() -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex("divider")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(0, 3)
	return t


## Окно: рамка + строка заголовка с крестиком. Возвращает [окно, контейнер содержимого].
static func window(title: String, on_close: Callable) -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", box("title", 3))
	v.add_child(head)
	var hb := HBoxContainer.new()
	head.add_child(hb)
	var t := label(title, 18, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(t)
	if on_close.is_valid():
		var x := TextureButton.new()
		x.texture_normal = tex("close")
		x.focus_mode = Control.FOCUS_NONE
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x.pressed.connect(func():
			Sfx.play("close")
			on_close.call())
		hb.add_child(x)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	v.add_child(body)
	return [p, body, t]
