extends Control

# Punch My Boss — v0.2 gameplay slice.
# Ports three things from the HTML prototype:
#   * meters   — RAGE (yours) and K.O. (the boss's)
#   * dialogue — the boss's taunt lines, typed out in a speech bubble
#   * sound    — procedurally generated punch + K.O. effects (no audio files)
# Everything stays sized for any phone (see project.godot + _apply_safe_area).

# --- the boss's real lines, lifted from the prototype ---
const OPENERS := [
	"Hey, yeah... I'm gonna need those reports. And your whole weekend. Mmkay?",
	"So. Your numbers. They're... not great. Let's talk about your 'commitment'.",
	"Quick one — I'm taking credit for your project in the board meeting. Cool? Cool.",
]
const TAUNTS := [
	"Mmyeah, I'm gonna have to disagree with you there, champ.",
	"Let's put a pin in your 'feelings' and circle back never.",
	"I don't hear a team player. I hear excuses.",
	"Have you tried just... working harder? For free?",
	"That's a 'you' problem. Take it to HR. Oh wait, I'm HR.",
	"Per my last email — which you clearly ignored.",
	"We're a FAMILY here. And you're the disappointing one.",
]

@onready var rage_fill: ColorRect = $Safe/RageTrack/RageFill
@onready var ko_fill: ColorRect = $Safe/KoTrack/KoFill
@onready var boss_line: Label = $Safe/Bubble/BossLine
@onready var boss: Button = $Safe/Boss
@onready var counter: Label = $Safe/Counter
@onready var ko_banner: Label = $Safe/KoBanner
@onready var safe: Control = $Safe
@onready var background: ColorRect = $Background

var rage: float = 0.0
var ko: float = 0.0
var punches: int = 0

# typewriter state
var _type_full: String = ""
var _type_shown: float = 0.0
const TYPE_CPS: float = 34.0

var _punch_player: AudioStreamPlayer
var _ko_player: AudioStreamPlayer

func _ready() -> void:
	boss.resized.connect(_center_pivot)
	_center_pivot()
	boss.pressed.connect(_on_punch)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	# Procedural sound effects (built in code, no files needed).
	_punch_player = AudioStreamPlayer.new()
	_punch_player.stream = _make_punch()
	add_child(_punch_player)
	_ko_player = AudioStreamPlayer.new()
	_ko_player.stream = _make_ko()
	add_child(_ko_player)

	ko_banner.modulate.a = 0.0
	_set_rage(12.0)
	_set_ko(0.0)
	_say(OPENERS[randi() % OPENERS.size()])

	# The boss keeps taunting you on a timer, which stokes your RAGE.
	var taunt_timer := Timer.new()
	taunt_timer.wait_time = 3.8
	add_child(taunt_timer)
	taunt_timer.timeout.connect(_next_taunt)
	taunt_timer.start()

func _process(delta: float) -> void:
	# Typewriter reveal of the current boss line.
	var total := float(_type_full.length())
	if _type_shown < total:
		_type_shown = min(total, _type_shown + TYPE_CPS * delta)
		boss_line.text = _type_full.substr(0, int(_type_shown))

func _say(text: String) -> void:
	_type_full = text
	_type_shown = 0.0
	boss_line.text = ""

func _next_taunt() -> void:
	_say(TAUNTS[randi() % TAUNTS.size()])
	_set_rage(rage + float(randi_range(6, 22)))

func _on_punch() -> void:
	punches += 1
	counter.text = "Punches: %d" % punches
	_punch_player.pitch_scale = randf_range(0.9, 1.15)
	_punch_player.play()

	# Squash-and-spring for a satisfying hit.
	var tw := create_tween()
	boss.scale = Vector2(0.86, 0.86)
	tw.tween_property(boss, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Punching vents your rage and builds the boss toward a knockout.
	_set_rage(rage - 4.0)
	_set_ko(ko + float(randi_range(11, 17)))
	if ko >= 100.0:
		_knockout()

func _knockout() -> void:
	_ko_player.play()
	_set_ko(0.0)
	_set_rage(0.0)
	ko_banner.text = "K.O.!"
	ko_banner.pivot_offset = ko_banner.size / 2.0
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(ko_banner, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	_say("...okay. Let's not put THAT in the performance review.")

# --- meters ---

func _set_rage(v: float) -> void:
	rage = clampf(v, 0.0, 100.0)
	rage_fill.anchor_right = rage / 100.0
	rage_fill.offset_right = 0.0
	# The room simmers redder as you get angrier.
	var base := Color(0.101961, 0.078431, 0.141176)
	var hot := Color(0.28, 0.06, 0.10)
	background.color = base.lerp(hot, rage / 100.0)

func _set_ko(v: float) -> void:
	ko = clampf(v, 0.0, 100.0)
	ko_fill.anchor_right = ko / 100.0
	ko_fill.offset_right = 0.0

# --- layout helpers ---

func _center_pivot() -> void:
	boss.pivot_offset = boss.size / 2.0

func _apply_safe_area() -> void:
	var screen := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var vis := get_viewport().get_visible_rect().size
	safe.offset_left = sa.position.x / screen.x * vis.x
	safe.offset_top = sa.position.y / screen.y * vis.y
	safe.offset_right = -((screen.x - (sa.position.x + sa.size.x)) / screen.x * vis.x)
	safe.offset_bottom = -((screen.y - (sa.position.y + sa.size.y)) / screen.y * vis.y)

# --- procedural audio ---

func _make_punch() -> AudioStreamWAV:
	# A short, punchy thud: a fast downward pitch sweep plus a little noise.
	var rate := 44100
	var dur := 0.16
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 26.0)
		var freq := lerpf(200.0, 45.0, t / dur)
		var s := sin(TAU * freq * t) * env
		s += (randf() * 2.0 - 1.0) * env * 0.35
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _make_ko() -> AudioStreamWAV:
	# A little three-note "ta-da" (C-E-G) for the knockout.
	var rate := 44100
	var dur := 0.5
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [523.25, 659.25, 783.99]
	var seg_len := dur / float(notes.size())
	for i in n:
		var t := float(i) / rate
		var seg := clampi(int(t / seg_len), 0, notes.size() - 1)
		var lt := t - float(seg) * seg_len
		var env := exp(-lt * 8.0)
		var s := sin(TAU * float(notes[seg]) * t) * env * 0.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
