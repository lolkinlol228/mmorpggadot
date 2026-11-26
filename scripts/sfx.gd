extends Node
## Звуки (Kenney RPG/Impact/Interface Audio, CC0). Sfx.play("hit") — случайный вариант из группы,
## с лёгким разбросом высоты, чтобы повторы не звучали одинаково.

const DIR := "res://assets/sfx/"
const GROUPS := {
	"swing": ["drawknife1", "drawknife2", "drawknife3"],
	"hit": ["impactpunch_medium_000", "impactpunch_medium_001", "impactpunch_medium_002"],
	"crit": ["impactpunch_heavy_000", "impactpunch_heavy_001"],
	"hit_stone": ["impactmining_000", "impactmining_001"],
	"hurt": ["impactsoft_heavy_000", "impactsoft_heavy_001"],
	"enemy_die": ["impactsoft_medium_000", "impactsoft_medium_001"],
	"pickup": ["handlesmallleather", "handlesmallleather2"],
	"coins": ["handlecoins", "handlecoins2"],
	"shimmer": ["impactglass_light_000", "impactglass_light_001"],
	"bell": ["impactbell_heavy_000", "impactbell_heavy_001", "impactbell_heavy_002"],
	"equip_metal": ["metalclick", "metallatch"],
	"equip_cloth": ["cloth1", "cloth2", "cloth3", "beltHandle1"],
	"click": ["click_001", "click_002"],
	"hover": ["select_001", "select_002"],
	"open": ["bookopen"],
	"close": ["bookclose"],
	"invite": ["open_001"],
	"confirm": ["confirmation_001", "confirmation_002"],
	"error": ["error_001", "error_004"],
	"toggle": ["toggle_001"],
	"drop": ["drop_002"],
	"step": ["footstep00", "footstep01", "footstep02", "footstep03", "footstep04"],
}
const VOLUME := {"step": -16.0, "hover": -14.0, "swing": -6.0, "click": -6.0, "bell": -4.0}
const POOL := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for g in GROUPS:
		var list: Array = []
		for f in GROUPS[g]:
			var path: String = DIR + f.to_lower() + ".ogg"
			if ResourceLoader.exists(path):
				list.append(load(path))
		_streams[g] = list
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(group: String, volume_db := 0.0, pitch := 1.0, jitter := true) -> void:
	var list: Array = _streams.get(group, [])
	if list.is_empty() or DisplayServer.get_name() == "headless":
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = list.pick_random()
	p.volume_db = VOLUME.get(group, 0.0) + volume_db
	p.pitch_scale = pitch * (randf_range(0.93, 1.07) if jitter else 1.0)
	p.play()


## Звук в мире: тише, если далеко от своего героя; совсем далеко — не слышно.
func play_at(group: String, pos: Vector2, listener: Vector2, pitch := 1.0) -> void:
	var d := pos.distance_to(listener)
	if d > 420.0:
		return
	play(group, -d / 420.0 * 14.0, pitch)


## Мега-дроп: колокола по нотам мажорного аккорда (настоящий звон, а не синтезатор).
func fanfare(rarity: int) -> void:
	var notes := [1.0, 1.26, 1.5, 2.0, 2.52]
	var count := clampi(rarity - 1, 3, notes.size())
	for i in count:
		get_tree().create_timer(i * 0.13).timeout.connect(play.bind("bell", -2.0 - i, notes[i], false))
	get_tree().create_timer(count * 0.13).timeout.connect(play.bind("shimmer", 0.0, 1.2, false))
