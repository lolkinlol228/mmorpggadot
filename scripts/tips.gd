extends CanvasLayer
## Свои всплывающие подсказки (автозагрузка Tips) вместо встроенных у курсора.
## Подсказка встаёт ровно под элементом, на который навели мышь; если снизу не помещается —
## над ним; по горизонтали прижимается к краям экрана. Берёт tooltip_text элемента или его
## _make_custom_tooltip() (как у ячеек с вещами). Встроенные подсказки отключены в project.godot
## (gui/timers/tooltip_delay_sec), чтобы не было двух сразу.

const Kit := preload("res://scripts/ui_kit.gd")
const DELAY := 0.3          # сек до появления
const GAP := 2.0            # отступ от элемента
const MAX_W := 220.0        # ширина, после которой длинный текст переносится

var panel: PanelContainer
var source: Control = null  # элемент, чью подсказку показываем
var shown_text := ""
var wait := 0.0


func _ready() -> void:
	layer = 100
	panel = PanelContainer.new()
	panel.theme = Kit.make_theme()
	panel.add_theme_stylebox_override("panel", Kit.box("tooltip", 4))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)


## Ближайший элемент с подсказкой под курсором (поднимаемся по родителям, пока они пропускают мышь).
func _find(c: Control) -> Control:
	while c != null:
		if c.tooltip_text != "" or c.has_method("_make_custom_tooltip"):
			return c
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return null
		c = c.get_parent() as Control
	return null


func _process(delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var found := _find(hovered) if hovered != null and hovered.is_visible_in_tree() else null
	if found != source:
		source = found
		wait = DELAY
		shown_text = ""
		panel.visible = false
	if source == null:
		return
	if wait > 0.0:
		wait -= delta
		if wait > 0.0:
			return
	# содержимое: перестраиваем, только если текст поменялся (значения в окнах обновляются на лету)
	var text := source.tooltip_text
	if not panel.visible or text != shown_text:
		if not _fill(text):
			panel.visible = false
			return
		shown_text = text
		panel.visible = true
	_place()


func _fill(text: String) -> bool:
	for ch in panel.get_children():
		panel.remove_child(ch)
		ch.queue_free()
	var content: Control = null
	if source.has_method("_make_custom_tooltip"):
		content = source._make_custom_tooltip(text)
	if content == null:
		if text == "":
			return false
		var l := Kit.label(text, 9)
		if l.get_minimum_size().x > MAX_W:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = MAX_W
		content = l
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	panel.reset_size()
	return true


## Под элементом → над ним → в пределах экрана.
func _place() -> void:
	var r := source.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, source.size)
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	var view := get_viewport().get_visible_rect().size
	var y := r.end.y + GAP
	if y + sz.y > view.y:
		y = r.position.y - GAP - sz.y
	y = clampf(y, 0.0, maxf(0.0, view.y - sz.y))
	var x := clampf(r.position.x, 0.0, maxf(0.0, view.x - sz.x))
	panel.position = Vector2(x, y).round()
