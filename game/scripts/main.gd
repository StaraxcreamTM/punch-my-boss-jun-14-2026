extends Control

# Punch My Boss — v0.3.
# The boss is now the real claymation character from the prototype: a body with a
# head that swaps expression — neutral, "talk" mouth movement while taunting, and a
# random hurt face on every punch. Meters, dialogue and procedural sound carry over.

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

@onready var boss: Control = $Safe/Boss
@onready var rig: Control = $Safe/Boss/Rig
@onready var head: TextureRect = $Safe/Boss/Rig/Head
@onready var rage_fill: Panel = $Safe/RageTrack/RageFill
@onready var ko_fill: Panel = $Safe/KoTrack/KoFill
@onready var boss_line: Label = $Safe/Bubble/BossLine
@onready var counter: Label = $Safe/Counter
@onready var ko_banner: Label = $Safe/KoBanner
@onready var safe: Control = $Safe
@onready var overlay: ColorRect = $Overlay
@onready var office: TextureRect = $Office
@onready var body_spr: TextureRect = $Safe/Boss/Rig/Body

# Bone skeleton (rest pose over the boss). Not bound to the art yet — these
# handles let future animations rotate the head / arms / fists. See main.tscn.
@onready var skel: Skeleton2D = $Safe/Boss/Rig/Skeleton
@onready var bone_head: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/Spine/Chest/Head
@onready var bone_arm_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL
@onready var bone_arm_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR
@onready var bone_forearm_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL/ForearmL
@onready var bone_forearm_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR/ForearmR
@onready var bone_fist_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL/ForearmL/FistL
@onready var bone_fist_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR/ForearmR/FistR

var rage: float = 0.0
var ko: float = 0.0
var punches: int = 0

# typewriter
var _type_full: String = ""
var _type_shown: float = 0.0
const TYPE_CPS: float = 34.0

# head expressions
var _tex_neutral: Texture2D = load("res://assets/boss/neutral.png")
var _tex_talk: Texture2D = load("res://assets/boss/talk.png")
var _react: Array[Texture2D] = []
var _react_tex: Texture2D
var _react_time: float = 0.0

# idle animation clock
var _clock: float = 0.0

var _punch_player: AudioStreamPlayer
var _ko_player: AudioStreamPlayer

# --- juice / game-feel ---
var _shake_time: float = 0.0
var _shake_mag: float = 0.0
var _flash: ColorRect
const POW_WORDS := ["POW!", "BAM!", "WHAM!", "BOP!", "OOF!", "SMACK!", "KAPOW!"]

# --- fight loop (Big Boy Boxing-style) ---
enum BossState { GUARD, WINDUP, VULNERABLE }
var _state: int = BossState.GUARD
var _state_time: float = 0.0
var _koing: bool = false
var _prompt: Label
var _crit_player: AudioStreamPlayer
const WINDUP_DUR := 0.55
const VULN_DUR := 1.35

# --- controls / attacks ---
var _fist_tex: Texture2D = load("res://assets/boss/fist.png")
var _buttons := {}

func _ready() -> void:
	for i in 15:
		_react.append(load("res://assets/boss/react%d.png" % i))
	_react_tex = _react[0]

	rig.resized.connect(_center_pivot)
	_center_pivot()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	_punch_player = AudioStreamPlayer.new()
	_punch_player.stream = _make_punch()
	add_child(_punch_player)
	_ko_player = AudioStreamPlayer.new()
	_ko_player.stream = _make_ko()
	add_child(_ko_player)

	# Overscan bg + tint so screen-shake never reveals a screen edge.
	for n in [office, overlay]:
		n.offset_left = -90.0
		n.offset_top = -90.0
		n.offset_right = 90.0
		n.offset_bottom = 90.0

	# Full-screen white flash, drawn above everything.
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.offset_left = -90.0
	_flash.offset_top = -90.0
	_flash.offset_right = 90.0
	_flash.offset_bottom = 90.0
	_flash.z_index = 50
	add_child(_flash)

	# --- stylized "animated" art direction (shaders, no new art) ---
	# Cartoon/illustrated backdrop.
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = load("res://shaders/toon_bg.gdshader")
	bg_mat.set_shader_parameter("levels", 9.0)
	bg_mat.set_shader_parameter("saturation", 1.3)
	bg_mat.set_shader_parameter("edge_strength", 1.1)
	bg_mat.set_shader_parameter("edge_width", 1.7)
	office.material = bg_mat
	# Bold outline so the boss reads as a drawn character.
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = load("res://shaders/outline.gdshader")
	outline_mat.set_shader_parameter("width", 4.5)
	body_spr.material = outline_mat
	head.material = outline_mat
	# Skin the boss body to the bone skeleton so hits can deform the art.
	_build_body_mesh()
	# Cinematic vignette over the world (below the boss + UI, which live in Safe).
	var vig := ColorRect.new()
	vig.color = Color(1, 1, 1, 1)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vig_mat := ShaderMaterial.new()
	vig_mat.shader = load("res://shaders/vignette.gdshader")
	vig_mat.set_shader_parameter("strength", 0.6)
	vig_mat.set_shader_parameter("radius", 1.12)
	vig.material = vig_mat
	add_child(vig)
	move_child(vig, 2)  # after Office(0) and Overlay(1), before Safe(2)

	# Camera-style zoom-punch pivots (canvas 1920x1080; bg/tint overscanned +90).
	office.pivot_offset = Vector2(1050, 630)
	overlay.pivot_offset = Vector2(1050, 630)
	safe.pivot_offset = Vector2(960, 540)

	# "HIT HIM!" prompt shown during the boss's vulnerable window.
	_prompt = Label.new()
	_prompt.text = "HIT HIM!"
	_prompt.add_theme_font_size_override("font_size", 54)
	_prompt.add_theme_color_override("font_color", Color(1, 0.92, 0.2))
	_prompt.add_theme_color_override("font_outline_color", Color(0.15, 0.06, 0.0))
	_prompt.add_theme_constant_override("outline_size", 12)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.z_index = 60
	_prompt.visible = false
	add_child(_prompt)

	_crit_player = AudioStreamPlayer.new()
	_crit_player.stream = _make_crit()
	add_child(_crit_player)

	# On-screen A/B/X/Y attack buttons (also work via keyboard A/B/X/Y or a gamepad).
	var cx := 1660.0
	var cy := 815.0
	var rr := 135.0
	_buttons["Y"] = _make_face_button("Y", Color(0.90, 0.75, 0.10), Vector2(cx, cy - rr))
	_buttons["A"] = _make_face_button("A", Color(0.20, 0.70, 0.25), Vector2(cx, cy + rr))
	_buttons["X"] = _make_face_button("X", Color(0.20, 0.45, 0.85), Vector2(cx - rr, cy))
	_buttons["B"] = _make_face_button("B", Color(0.82, 0.22, 0.20), Vector2(cx + rr, cy))
	($Safe/Hint as Label).text = "A · B  =  body        X · Y  =  head"

	ko_banner.modulate.a = 0.0
	_set_rage(12.0)
	_set_ko(0.0)
	_say(OPENERS[randi() % OPENERS.size()])

	var taunt_timer := Timer.new()
	taunt_timer.wait_time = 3.8
	add_child(taunt_timer)
	taunt_timer.timeout.connect(_next_taunt)
	taunt_timer.start()

	_enter_guard()

func _process(delta: float) -> void:
	_clock += delta

	# Typewriter reveal.
	var total := float(_type_full.length())
	if _type_shown < total:
		_type_shown = min(total, _type_shown + TYPE_CPS * delta)
		boss_line.text = _type_full.substr(0, int(_type_shown))

	# Screen shake (decaying) applied to bg, tint and play field together.
	var sh := Vector2.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var d := clampf(_shake_time / 0.32, 0.0, 1.0)
		sh = Vector2(randf_range(-_shake_mag, _shake_mag), randf_range(-_shake_mag, _shake_mag)) * d
		if _shake_time <= 0.0:
			_shake_mag = 0.0
	office.position = sh * 0.5
	overlay.position = sh
	safe.position = sh

	# The boss fight loop (guard -> wind-up tell -> vulnerable window).
	if not _koing:
		_update_fight(delta)

	# Head expression: a recent punch wins, then talking, otherwise neutral.
	var talking := _type_shown < total
	if _react_time > 0.0:
		_react_time -= delta
		head.texture = _react_tex
	elif talking:
		var mouth_open := int(_clock * 8.0) % 2 == 0
		head.texture = _tex_talk if mouth_open else _tex_neutral
	else:
		head.texture = _tex_neutral

func _say(text: String) -> void:
	_type_full = text
	_type_shown = 0.0
	boss_line.text = ""

func _next_taunt() -> void:
	_say(TAUNTS[randi() % TAUNTS.size()])
	_set_rage(rage + float(randi_range(6, 22)))

func _make_face_button(letter: String, col: Color, center: Vector2) -> Button:
	var b := Button.new()
	b.text = letter
	b.custom_minimum_size = Vector2(118, 118)
	b.size = Vector2(118, 118)
	b.position = center - b.size / 2.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 52)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(59)
	sb.set_border_width_all(5)
	sb.border_color = Color(1, 1, 1, 0.85)
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = col.darkened(0.2)
	b.add_theme_stylebox_override("pressed", sbp)
	b.z_index = 60
	b.pressed.connect(_press.bind(letter))
	safe.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_A: _press("A")
				KEY_B: _press("B")
				KEY_X: _press("X")
				KEY_Y: _press("Y")
	elif event is InputEventJoypadButton:
		if event.pressed:
			match event.button_index:
				JOY_BUTTON_A: _press("A")
				JOY_BUTTON_B: _press("B")
				JOY_BUTTON_X: _press("X")
				JOY_BUTTON_Y: _press("Y")

func _press(letter: String) -> void:
	if _buttons.has(letter):
		var b: Button = _buttons[letter]
		b.pivot_offset = b.size / 2.0
		b.scale = Vector2(0.85, 0.85)
		var tw := create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match letter:
		"A": _punch(true, false)   # left hand -> body
		"B": _punch(false, false)  # right hand -> body
		"X": _punch(true, true)    # left hand -> head
		"Y": _punch(false, true)   # right hand -> head

func _punch(side_left: bool, is_head: bool) -> void:
	if _koing:
		return
	punches += 1
	counter.text = "Punches: %d" % punches
	var t: Control = head if is_head else body_spr
	var fx := 0.30 if side_left else 0.70
	var fy := 0.5 if is_head else 0.4
	var impact: Vector2 = t.get_global_transform() * Vector2(t.size.x * fx, t.size.y * fy)
	_throw_fist(impact, side_left, is_head)

func _throw_fist(impact: Vector2, side_left: bool, is_head: bool) -> void:
	var f := TextureRect.new()
	f.texture = _fist_tex
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.size = Vector2(320, 320)
	f.pivot_offset = f.size / 2.0
	var mirror := 1.0 if side_left else -1.0  # mirror the fist for the other hand
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 80
	add_child(f)
	# First-person punch: the fist thrusts up from the player's side (near the
	# camera, so it starts large) and fully extends to reach the boss, then
	# retracts. No detached "flying fist" arcing in from off-screen.
	var start: Vector2 = Vector2(700.0, 1440.0) if side_left else Vector2(1220.0, 1440.0)
	var start_scale := 1.4   # close to the viewer at the start of the thrust
	var reach_scale := 0.95  # arm fully extended toward the boss
	f.scale = Vector2(mirror * start_scale, start_scale)
	f.position = start - f.size / 2.0
	var tw := create_tween()
	tw.tween_property(f, "position", impact - f.size / 2.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "scale", Vector2(mirror * reach_scale, reach_scale), 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _land(impact, is_head, side_left))
	tw.tween_property(f, "position", start - f.size / 2.0, 0.13).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(f, "scale", Vector2(mirror * start_scale, start_scale), 0.13).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(f, "modulate:a", 0.0, 0.13)
	tw.tween_callback(f.queue_free)

func _land(impact: Vector2, is_head: bool, side_left: bool) -> void:
	if _koing:
		return
	var text_pos := _text_anchor(side_left)
	if _state == BossState.VULNERABLE:
		_crit(impact, text_pos)
	else:
		_chip(impact, text_pos)
	# Directional reaction: the head snaps aside, the body rocks.
	if is_head:
		head.position = Vector2(34.0 if side_left else -34.0, 6.0)
		var kt := create_tween()
		kt.tween_property(head, "position", Vector2.ZERO, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	else:
		rig.position.x = 24.0 if side_left else -24.0
		var lt := create_tween()
		lt.tween_property(rig, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# The bone skeleton deforms the body: arms shudder outward on impact
	# (harder on a critical body blow).
	var crit := _state == BossState.VULNERABLE
	_jostle_arms((1.0 if crit else 0.6) * (0.7 if is_head else 1.0))
	if ko >= 100.0:
		_knockout()

func _chip(impact: Vector2, text_pos: Vector2) -> void:
	# A normal punch while the boss is guarding: small damage, standard juice.
	_punch_player.pitch_scale = randf_range(0.9, 1.15)
	_punch_player.play()
	_react_tex = _react[randi() % _react.size()]
	_react_time = 0.28
	rig.scale = Vector2(1.18, 0.84)
	var tw := create_tween()
	tw.tween_property(rig, "scale", Vector2(0.92, 1.1), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(rig, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash_screen(0.22)
	_shake(9.0, 0.24)
	_spawn_text(text_pos, POW_WORDS[randi() % POW_WORDS.size()], 84, Color(1, 0.86, 0.16))
	_spawn_stars(impact, 5)
	_hitstop(0.05)
	_set_rage(rage - 2.0)
	_set_ko(ko + float(randi_range(4, 7)))

func _crit(impact: Vector2, text_pos: Vector2) -> void:
	# A punch landed in the vulnerable window: big damage + maxed-out juice.
	_crit_player.play()
	_punch_player.pitch_scale = randf_range(1.2, 1.4)
	_punch_player.play()
	_react_tex = _react[_react.size() - 1 - (randi() % 3)]
	_react_time = 0.5
	rig.scale = Vector2(1.35, 0.7)
	var tw := create_tween()
	tw.tween_property(rig, "scale", Vector2(0.82, 1.2), 0.09).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(rig, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_flash_screen(0.55)
	_shake(26.0, 0.45)
	_zoom_punch(0.06)
	_spawn_text(text_pos, "CRITICAL!", 118, Color(1, 0.3, 0.22))
	_spawn_stars(impact, 14)
	_spawn_sweat(impact)
	_hitstop(0.11)
	_set_rage(rage - 8.0)
	_set_ko(ko + float(randi_range(22, 32)))
	# The opening is spent — the boss recovers to guard.
	_enter_guard()

# --- boss fight state machine ---

func _update_fight(delta: float) -> void:
	var lean := 0.0
	var tint := Color(1, 1, 1)
	_state_time -= delta
	match _state:
		BossState.GUARD:
			if _state_time <= 0.0:
				_enter_windup()
		BossState.WINDUP:
			# Lean back + pulse orange so the "tell" is unmistakable.
			var t := 1.0 - clampf(_state_time / WINDUP_DUR, 0.0, 1.0)
			lean = -0.22 * t
			var pw := 0.5 + 0.5 * sin(_clock * 26.0)
			tint = Color(1, 1, 1).lerp(Color(1.5, 0.7, 0.2), pw * t)
			if _state_time <= 0.0:
				_enter_vulnerable()
		BossState.VULNERABLE:
			# Flash yellow + show the prompt: this is the punish window.
			var pv := 0.5 + 0.5 * sin(_clock * 14.0)
			tint = Color(1, 1, 1).lerp(Color(1.6, 1.5, 0.25), pv)
			lean = sin(_clock * 22.0) * 0.03
			_position_prompt(pv)
			if _state_time <= 0.0:
				_enter_guard()
	# Feet stay planted: no vertical bob. Life comes from a gentle sway that
	# pivots around the feet (and the wind-up lean, which also pivots at the feet).
	rig.position.y = 0.0
	rig.rotation = sin(_clock * 1.3) * 0.02 + lean
	boss.modulate = tint

func _position_prompt(p: float) -> void:
	var top: Vector2 = boss.get_global_transform() * Vector2(boss.size.x * 0.5, 0.0)
	_prompt.pivot_offset = _prompt.size / 2.0
	_prompt.global_position = top - Vector2(_prompt.size.x * 0.5, 46.0 + p * 12.0)
	_prompt.scale = Vector2.ONE * (1.0 + p * 0.12)

func _enter_guard() -> void:
	_state = BossState.GUARD
	_state_time = randf_range(2.6, 4.2)
	_prompt.visible = false
	boss.modulate = Color(1, 1, 1)

func _enter_windup() -> void:
	_state = BossState.WINDUP
	_state_time = WINDUP_DUR
	_prompt.visible = false
	_shake(4.0, 0.2)

func _enter_vulnerable() -> void:
	_state = BossState.VULNERABLE
	_state_time = VULN_DUR
	_prompt.visible = true

func _knockout() -> void:
	_koing = true
	_prompt.visible = false
	boss.modulate = Color(1, 1, 1)
	_ko_player.play()
	_flash_screen(0.85)
	_shake(42.0, 0.7)
	_zoom_punch(0.1)

	# Freeze on impact, then drop into slow-mo for the launch.
	Engine.time_scale = 0.001
	await get_tree().create_timer(0.13, true, false, true).timeout
	Engine.time_scale = 0.35

	# Hold the most battered face.
	_react_tex = _react[_react.size() - 1]
	_react_time = 999.0

	ko_banner.text = "K.O.!"
	ko_banner.pivot_offset = ko_banner.size / 2.0
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.5, 0.5)
	var bt := create_tween()
	bt.tween_property(ko_banner, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Launch the boss off-screen with a spin.
	var dir := 1.0 if randf() > 0.5 else -1.0
	var fly := create_tween()
	fly.tween_property(rig, "position", Vector2(dir * 700.0, -1700.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.parallel().tween_property(rig, "rotation", dir * 7.0, 0.55)
	fly.parallel().tween_property(rig, "scale", Vector2(0.7, 0.7), 0.55)
	await fly.finished

	Engine.time_scale = 1.0
	_say("...okay. Let's not put THAT in the performance review.")
	await get_tree().create_timer(1.1).timeout

	# Fade the banner and reset the boss for the next round.
	var ft := create_tween()
	ft.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	_set_rage(0.0)
	_set_ko(0.0)
	_react_time = 0.0
	rig.rotation = 0.0
	rig.scale = Vector2.ONE
	rig.position = Vector2(0.0, 1700.0)  # start below the desk
	var back := create_tween()
	back.tween_property(rig, "position", Vector2.ZERO, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await back.finished

	_koing = false
	_enter_guard()

# --- juice / game-feel helpers ---

func _hitstop(duration: float) -> void:
	# Briefly freeze time for weight, then restore. The timer ignores
	# time_scale so it still fires while everything else is frozen.
	Engine.time_scale = 0.001
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func _shake(mag: float, time: float) -> void:
	_shake_mag = maxf(_shake_mag, mag)
	_shake_time = maxf(_shake_time, time)

func _flash_screen(a: float) -> void:
	_flash.color.a = a
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.18)

func _text_anchor(side_left: bool) -> Vector2:
	# Words pop high and off to the side, in the open office space well clear
	# of the boss's face (left-side hits pop left, right-side hits pop right).
	var head_top: Vector2 = head.get_global_transform() * Vector2(head.size.x * 0.5, 0.0)
	var dx := -380.0 if side_left else 380.0
	return head_top + Vector2(dx, -110.0)

func _spawn_text(pos: Vector2, text: String, size: int, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.14))
	lbl.add_theme_constant_override("outline_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 100
	add_child(lbl)
	await get_tree().process_frame  # let it compute its size
	lbl.pivot_offset = lbl.size / 2.0
	lbl.global_position = pos - lbl.size / 2.0 + Vector2(randf_range(-30, 30), randf_range(-40, -10))
	lbl.rotation = randf_range(-0.22, 0.22)
	lbl.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.06)
	tw.tween_interval(0.22)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(lbl, "position:y", lbl.position.y - 46.0, 0.25)
	tw.tween_callback(lbl.queue_free)

func _spawn_stars(pos: Vector2, count: int = 8) -> void:
	for i in count:
		var s := ColorRect.new()
		var sz := randf_range(10.0, 22.0)
		s.size = Vector2(sz, sz)
		s.color = Color(1, 0.93, 0.45)
		s.pivot_offset = s.size / 2.0
		s.rotation = randf() * TAU
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.z_index = 99
		add_child(s)
		s.global_position = pos - s.size / 2.0
		var ang := randf() * TAU
		var dist := randf_range(70.0, 200.0)
		var dest := s.global_position + Vector2(cos(ang), sin(ang)) * dist
		var tw := create_tween()
		tw.tween_property(s, "global_position", dest, randf_range(0.28, 0.46)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.42)
		tw.parallel().tween_property(s, "rotation", s.rotation + randf_range(-3.0, 3.0), 0.42)
		tw.tween_callback(s.queue_free)

func _spawn_sweat(pos: Vector2) -> void:
	for i in 6:
		var s := ColorRect.new()
		var sz := randf_range(7.0, 13.0)
		s.size = Vector2(sz, sz * 1.6)
		s.color = Color(0.6, 0.85, 1.0, 0.9)
		s.pivot_offset = s.size / 2.0
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.z_index = 98
		add_child(s)
		s.global_position = pos - s.size / 2.0
		var dest := s.global_position + Vector2(randf_range(-150, 150), randf_range(-170, -60))
		var tw := create_tween()
		tw.tween_property(s, "global_position", dest, randf_range(0.3, 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.45)
		tw.tween_callback(s.queue_free)

func _zoom_punch(amount: float) -> void:
	# Fake a camera punch-in by briefly scaling the whole field about its centre.
	for n in [office, overlay, safe]:
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2.ONE * (1.0 + amount), 0.06).set_trans(Tween.TRANS_SINE)
		tw.tween_property(n, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)

# --- meters ---

func _set_rage(v: float) -> void:
	rage = clampf(v, 0.0, 100.0)
	rage_fill.anchor_right = rage / 100.0
	rage_fill.offset_right = 0.0
	# The scene reddens through the overlay as you get angrier.
	var calm := Color(0, 0, 0, 0.22)
	var hot := Color(0.42, 0.0, 0.05, 0.42)
	overlay.color = calm.lerp(hot, rage / 100.0)

func _set_ko(v: float) -> void:
	ko = clampf(v, 0.0, 100.0)
	ko_fill.anchor_right = ko / 100.0
	ko_fill.offset_right = 0.0

# --- layout helpers ---

func _center_pivot() -> void:
	# Scale/squash from the boss's feet (bottom-center).
	rig.pivot_offset = Vector2(rig.size.x / 2.0, rig.size.y)

# --- bone-driven body mesh -------------------------------------------------
# Replaces the flat Body sprite with a Polygon2D grid skinned to the Skeleton,
# so moving a bone actually deforms the boss art. Torso / head-area / legs are
# weighted to bones we leave at rest (they render exactly as the original),
# while the arm bones can jostle on impact.
var _body_mesh: Polygon2D

# Rig-local bone segments used to weight the mesh (path is relative to Skeleton).
const _BONE_SEGS := [
	["Hip", Vector2(260, 780), Vector2(260, 830)],
	["Hip/Spine", Vector2(260, 809), Vector2(260, 486)],
	["Hip/Spine/Chest/Head", Vector2(260, 486), Vector2(260, 150)],
	["Hip/ArmL", Vector2(122, 486), Vector2(83, 717)],
	["Hip/ArmL/ForearmL", Vector2(83, 717), Vector2(87, 924)],
	["Hip/ArmL/ForearmL/FistL", Vector2(87, 924), Vector2(87, 990)],
	["Hip/ArmR", Vector2(398, 486), Vector2(438, 717)],
	["Hip/ArmR/ForearmR", Vector2(438, 717), Vector2(433, 924)],
	["Hip/ArmR/ForearmR/FistR", Vector2(433, 924), Vector2(433, 990)],
	["Hip/LegL", Vector2(230, 830), Vector2(202, 1201)],
	["Hip/LegR", Vector2(290, 830), Vector2(313, 1201)],
]

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 0.0:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _build_body_mesh() -> void:
	if skel == null or body_spr.texture == null:
		return
	var cols := 12
	var rows := 26
	# Body sprite rect in Rig-local space (matches the Body TextureRect area).
	var x0 := 18.0
	var x1 := 502.0
	var y0 := 60.0
	var y1 := 1240.0
	var tex: Texture2D = body_spr.texture
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for r in rows + 1:
		for c in cols + 1:
			var fx := float(c) / float(cols)
			var fy := float(r) / float(rows)
			verts.append(Vector2(lerpf(x0, x1, fx), lerpf(y0, y1, fy)))
			uvs.append(Vector2(fx * tw, fy * th))
	# Triangulate the grid.
	var tris: Array = []
	for r in rows:
		for c in cols:
			var i0 := r * (cols + 1) + c
			var i2 := i0 + (cols + 1)
			tris.append(PackedInt32Array([i0, i2, i0 + 1]))
			tris.append(PackedInt32Array([i0 + 1, i2, i2 + 1]))
	# Per-vertex bone weights: inverse distance to each bone segment, normalized.
	var nbones := _BONE_SEGS.size()
	var weights: Array = []
	for b in nbones:
		var wa := PackedFloat32Array()
		wa.resize(verts.size())
		weights.append(wa)
	for vi in verts.size():
		var p: Vector2 = verts[vi]
		var raw := PackedFloat32Array()
		raw.resize(nbones)
		var total := 0.0
		for b in nbones:
			var seg: Array = _BONE_SEGS[b]
			var d := _seg_dist(p, seg[1], seg[2])
			var w := 1.0 / pow(d + 8.0, 3.2)
			raw[b] = w
			total += w
		if total <= 0.0:
			total = 1.0
		for b in nbones:
			weights[b][vi] = raw[b] / total
	# Build the skinned Polygon2D and slot it where the Body sprite was.
	var poly := Polygon2D.new()
	poly.name = "BodyMesh"
	poly.texture = tex
	poly.polygon = verts
	poly.uv = uvs
	poly.polygons = tris
	poly.internal_vertex_count = 0
	poly.material = body_spr.material  # keep the outline shader
	rig.add_child(poly)
	rig.move_child(poly, body_spr.get_index())
	poly.skeleton = poly.get_path_to(skel)
	for b in nbones:
		poly.add_bone(NodePath(_BONE_SEGS[b][0]), weights[b])
	body_spr.visible = false
	_body_mesh = poly

# A hit makes the boss's arms shudder outward via the arm bones, then spring
# back — the skeleton visibly deforming the body on impact.
func _jostle_arms(intensity: float) -> void:
	if skel == null:
		return
	var la := deg_to_rad(22.0 * intensity)
	var lf := deg_to_rad(30.0 * intensity)
	# Left arm swings out to the boss's left (+), right arm to the right (-).
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bone_arm_l, "rotation", la, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(bone_arm_r, "rotation", -la, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(bone_forearm_l, "rotation", lf, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(bone_forearm_r, "rotation", -lf, 0.05).set_ease(Tween.EASE_OUT)
	var back := create_tween()
	back.set_parallel(true)
	for bone in [bone_arm_l, bone_arm_r, bone_forearm_l, bone_forearm_r]:
		back.tween_property(bone, "rotation", 0.0, 0.42) \
			.set_delay(0.05).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _apply_safe_area() -> void:
	# Safe-area insets only make sense on handhelds. On desktop the "display
	# safe area" is the whole monitor, which would shove the bottom UI (counter,
	# hint) off-screen — so there we just use the full viewport.
	if OS.get_name() not in ["Android", "iOS"]:
		safe.offset_left = 0.0
		safe.offset_top = 0.0
		safe.offset_right = 0.0
		safe.offset_bottom = 0.0
		return
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

func _make_crit() -> AudioStreamWAV:
	# A short bright two-note rising blip for landing a crit.
	var rate := 44100
	var dur := 0.22
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [784.0, 1046.5]  # G5 -> C6
	var seg := dur / 2.0
	for i in n:
		var t := float(i) / rate
		var idx := 0 if t < seg else 1
		var lt := t - float(idx) * seg
		var env := exp(-lt * 12.0)
		var s := sin(TAU * float(notes[idx]) * t) * env * 0.5
		s += sin(TAU * float(notes[idx]) * 2.0 * t) * env * 0.2
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
