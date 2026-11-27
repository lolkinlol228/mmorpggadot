extends Node2D
## Враг: спрайты из tools/art (assets/custom). Позицию присылает хост, здесь — плавность и анимация.

const SPRITES := {
	"slime": {"tex": preload("res://assets/custom/slime.png"), "w": 30, "h": 26, "frames": 2, "fps": 3.0},
	"wolf": {"tex": preload("res://assets/custom/wolf.png"), "w": 40, "h": 26, "frames": 4, "fps": 10.0},
	"golem": {"tex": preload("res://assets/custom/golem.png"), "w": 58, "h": 58, "frames": 2, "fps": 1.5},
	"shell": {"tex": preload("res://assets/custom/shell.png"), "w": 42, "h": 32, "frames": 2, "fps": 3.0},
	"ringer": {"tex": preload("res://assets/custom/ringer.png"), "w": 34, "h": 38, "frames": 2, "fps": 2.0},
	"warden": {"tex": preload("res://assets/custom/warden.png"), "w": 62, "h": 64, "frames": 2, "fps": 1.5},
}

const MINE_KINDS := ["shell", "ringer", "warden"]
const FACES_LEFT := ["wolf", "shell", "ringer", "warden"]   # в листах эти враги смотрят влево
var phase := ""
var heading := Vector2.LEFT
var elite := false
var kind := "slime"
var data: Dictionary = {}
var hp := 1
var max_hp := 1
var target := Vector2.ZERO
var t := 0.0
var hit_t := 0.0
var face := -1.0
var moving := false


func setup(k: String, pos: Vector2, h: int, mh: int) -> void:
	kind = k
	data = Items.ENEMIES[k]
	position = pos
	target = pos
	hp = h
	max_hp = mh


var overlay: Node2D          # имя босса и полоска здоровья — поверх зданий


func _ready() -> void:
	t = randf() * 5.0
	overlay = Node2D.new()
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	if kind in ["golem", "warden"]:
		var l := Label.new()
		l.text = data.name
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(160, 10)
		l.position = Vector2(-80, -66)
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color(1, 0.6, 0.35))
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		overlay.add_child(l)


func flash() -> void:
	hit_t = 0.12


func _process(delta: float) -> void:
	t += delta
	hit_t = maxf(0.0, hit_t - delta)
	var dx := target.x - position.x
	if absf(dx) > 0.5:
		face = signf(dx)
	moving = position.distance_to(target) > 0.6
	position = position.lerp(target, minf(1.0, delta * 10.0))
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	var s: Dictionary = SPRITES.get(kind, SPRITES.slime)
	var w: int = s.w
	var h: int = s.h
	var fps: float = s.fps if (moving or kind != "wolf") else 0.0
	var frame := int(t * fps) % int(s.frames)
	var foot := 12.0 if kind in ["golem", "warden"] else 6.0
	draw_set_transform(Vector2(0, foot), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, w * 0.42, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var tint := Color(1, 0.45, 0.45) if hit_t > 0.0 else (Color.PLUM if elite else (Color.PALE_GREEN if kind == "undead" else Color.WHITE))
	if kind in MINE_KINDS and hit_t <= 0.0 and phase == "open":
		tint = Color(0.6, 1.0, 0.9)          # окно уязвимости после замаха
	var right := heading.x > 0.0 if kind in ["shell", "warden"] else face > 0.0   # щит панцирника смотрит туда же, куда его броня
	if kind in FACES_LEFT and right:
		draw_set_transform(Vector2.ZERO, 0, Vector2(-1, 1))
	draw_texture_rect_region(s.tex, Rect2(-w / 2.0, foot - h + 3, w, h), Rect2(frame * w, 0, w, h), tint)   # +3: запас холста
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_overlay() -> void:
	if phase == "ring":
		var at := Vector2(0, -51)
		overlay.draw_circle(at, 5, Color.GOLD)
		overlay.draw_rect(Rect2(at + Vector2(-7, 0), Vector2(14, 3)), Color.GOLD)
		overlay.draw_circle(at + Vector2(0, 5), 2, Color.ORANGE)
	if kind in ["shell", "warden"] and phase != "open":
		var angle := heading.angle()
		var windup := phase == "windup"
		overlay.draw_arc(Vector2.ZERO, data.radius + (24 if windup else 4), angle - 1, angle + 1, 16, Color.ORANGE_RED if windup else Color.LIGHT_STEEL_BLUE, 3)
	if hp < max_hp or kind in ["golem", "warden"]:
		var s: Dictionary = SPRITES.get(kind, SPRITES.slime)
		var bw: float = s.w * 0.9
		var ratio := clampf(float(hp) / max_hp, 0.0, 1.0)
		var y: float = (12.0 if kind in ["golem", "warden"] else 6.0) - s.h - 5.0
		overlay.draw_rect(Rect2(-bw / 2, y, bw, 3), Color(0, 0, 0, 0.7))
		overlay.draw_rect(Rect2(-bw / 2, y, bw * ratio, 3), Color(0.85, 0.22, 0.2))
