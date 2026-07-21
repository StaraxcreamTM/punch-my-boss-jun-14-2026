extends Control

# Punch My Boss — v0.14: core gameplay loop.
# Click/tap the boss anywhere to punch him (A/B/X/Y still work). He has real HP
# that drains with damage numbers, hits chain into combos that multiply damage,
# filling the FRENZY meter triggers a frenzy where everything crits, and emptying his HP
# triggers the K.O. launch. Each round he returns with more HP.
# (Mechanics mirror the browser build in punch-my-boss-2.html.)

const OPENERS := [
	"Hey, yeah... I'm gonna need those reports. And your whole weekend. Mmkay?",
	"So. Your numbers. They're... not great. Let's talk about your 'commitment'.",
	"Quick one — I'm taking credit for your project in the board meeting. Cool? Cool.",
]
const ROUND_LINES := [
	"He's back. And he brought a PIP.",
	"Back from the 'leadership retreat'. Angrier.",
	"New quarter. Same boss. More HP.",
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
# The old flat claymation TextureRects (Body/Head) are hidden at startup; the
# sliced cutout rig in assets/boss2 replaces them. `head` and `torso_spr` are
# the cutout pieces used as hit targets and for expression swaps.
@onready var old_head: TextureRect = $Safe/Boss/Rig/Head
var head: Sprite2D
var torso_spr: Sprite2D
@onready var rage_fill: Panel = $Safe/RageTrack/RageFill
@onready var ko_fill: Panel = $Safe/KoTrack/KoFill
@onready var boss_line: Label = $Safe/Bubble/BossLine
@onready var counter: Label = $Safe/Counter
@onready var ko_banner: Label = $Safe/KoBanner
@onready var safe: Control = $Safe
@onready var overlay: ColorRect = $Overlay
@onready var office: TextureRect = $Office
@onready var body_spr: TextureRect = $Safe/Boss/Rig/Body

# Bone skeleton. _build_cutout_boss() hangs one sliced art piece off each bone,
# so rotating a bone swings that limb and everything below it. Full chain:
# hips -> torso -> head, upper arm -> forearm -> hand, thigh -> shin -> foot.
@onready var skel: Skeleton2D = $Safe/Boss/Rig/Skeleton
@onready var bone_hip: Bone2D = $Safe/Boss/Rig/Skeleton/Hip
@onready var bone_spine: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/Spine
@onready var bone_chest: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/Spine/Chest
@onready var bone_head: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/Spine/Chest/Head
@onready var bone_arm_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL
@onready var bone_arm_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR
@onready var bone_forearm_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL/ForearmL
@onready var bone_forearm_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR/ForearmR
@onready var bone_fist_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmL/ForearmL/FistL
@onready var bone_fist_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ArmR/ForearmR/FistR
@onready var bone_thigh_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighL
@onready var bone_thigh_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighR
@onready var bone_shin_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighL/ShinL
@onready var bone_shin_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighR/ShinR
@onready var bone_foot_l: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighL/ShinL/FootL
@onready var bone_foot_r: Bone2D = $Safe/Boss/Rig/Skeleton/Hip/ThighR/ShinR/FootR

# --- idle / pose state -----------------------------------------------------
# The idle loop writes bone rotations every frame, so impact reactions can't
# tween those same properties directly or they'd fight. Instead the reactions
# tween these offsets and _pose_skeleton() composes idle + reaction each frame.
var _idle_t: float = 0.0
var _jostle_arm: float = 0.0
var _jostle_fore: float = 0.0
var _hip_rest: Vector2 = Vector2.ZERO
var _head_rest: Vector2 = Vector2.ZERO
var _head_hit: Vector2 = Vector2.ZERO

var rage: float = 0.0
var punches: int = 0

# --- HP / rounds / combo / frenzy (the core loop) ---
var round_num: int = 1
var hp_max: float = 120.0
var hp: float = 120.0
var combo: int = 0
var combo_time: float = 0.0
var max_combo: int = 0
var crits: int = 0
var frenzy: float = 0.0
var _combo_label: Label
const COMBO_WINDOW := 0.95
const ROUND_HP_SCALE := 1.4

# typewriter
var _type_full: String = ""
var _type_shown: float = 0.0
const TYPE_CPS: float = 34.0

# Head expressions, cut from the cartoon pose set and all normalised onto one
# 460x500 canvas with the neck at (230,470), so swapping textures never shifts
# the head. Reaction faces run mild -> dazed: black eye, glasses-off, then the
# spiral-eyed dizzy faces.
var _tex_neutral: Texture2D = load("res://assets/boss2/heads/neutral.png")
var _tex_talk: Texture2D = load("res://assets/boss2/heads/talk.png")
const REACT_FACES := ["hurt0", "hurt1", "hurt2", "dizzy0", "dizzy1", "dizzy2", "dizzy3"]
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
# The player's fist: the red boxing glove lifted from the cartoon hit frame, so
# it matches the new boss instead of the old claymation fist.
var _fist_tex: Texture2D = load("res://assets/boss2/parts/glove.png")
var _buttons := {}

func _ready() -> void:
	for face in REACT_FACES:
		_react.append(load("res://assets/boss2/heads/%s.png" % face))
	_react_tex = _react[0]

	rig.resized.connect(_center_pivot)
	_center_pivot()
	# Let clicks pass through the boss Control to _unhandled_input, which
	# resolves them into aimed punches (see _punch_click).
	boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Hang the sliced cutout pieces off the bones. Each piece carries the same
	# outline shader so the whole figure reads as one drawn character.
	_build_cutout_boss(outline_mat)
	# Remember the rest pose so idle motion and hit reactions are offsets from
	# it rather than absolute positions (the head used to snap to Vector2.ZERO
	# after a hit, permanently shifting it off its anchored rest spot).
	_hip_rest = bone_hip.position
	_head_rest = bone_head.position
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
	($Safe/Hint as Label).text = "Click the boss — anywhere.        A · B  =  body        X · Y  =  head"

	# Big combo counter, right side of the screen.
	_combo_label = Label.new()
	_combo_label.add_theme_font_size_override("font_size", 96)
	_combo_label.add_theme_color_override("font_color", Color(1, 0.82, 0.17))
	_combo_label.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.08))
	_combo_label.add_theme_constant_override("outline_size", 16)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.z_index = 60
	_combo_label.position = Vector2(1560, 330)
	_combo_label.rotation = -0.08
	_combo_label.visible = false
	safe.add_child(_combo_label)

	ko_banner.modulate.a = 0.0
	# The meter now fills toward FRENZY as the player lands hits, so it starts
	# empty. (It used to be the boss's standing anger, which started at 12.)
	_set_rage(0.0)
	_set_hp(hp_max)
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

	# Breathing / sway / weight-shift across the whole skeleton.
	_pose_skeleton(delta)

	# Combo decay + frenzy countdown.
	if combo_time > 0.0:
		combo_time -= delta
		if combo_time <= 0.0:
			combo = 0
	if frenzy > 0.0:
		frenzy -= delta
	_combo_label.visible = combo >= 2
	if _combo_label.visible:
		_combo_label.text = "%d\nCOMBO" % combo
		_combo_label.scale = _combo_label.scale.lerp(Vector2.ONE * (1.0 + minf(combo, 30.0) * 0.012), 12.0 * delta)
		var ccol := Color(1, 0.82, 0.17)
		if combo >= 20:
			ccol = Color(1, 0.24, 0.94)
		elif combo >= 10:
			ccol = Color(1, 0.32, 0.21)
		elif combo >= 5:
			ccol = Color(1, 0.62, 0.17)
		_combo_label.add_theme_color_override("font_color", ccol)

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
	elif event is InputEventMouseButton:
		# Touches arrive here too via Godot's emulate_mouse_from_touch.
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_punch_click(get_global_mouse_position())

# Click/tap anywhere: throw a fist at that exact point. Hits on the boss deal
# damage; clicks in open air still swing (and whiff).
func _punch_click(pos: Vector2) -> void:
	if _koing:
		return
	var boss_rect := (boss as Control).get_global_rect().grow(20.0)
	var head_rect := _part_global_rect(head).grow(10.0)
	var boss_cx := boss_rect.position.x + boss_rect.size.x * 0.5
	var side_left := pos.x < boss_cx
	if not boss_rect.has_point(pos):
		_throw_whiff(pos, side_left)
		return
	punches += 1
	counter.text = "Punches: %d" % punches
	_throw_fist(pos, side_left, head_rect.has_point(pos))

func _throw_whiff(pos: Vector2, side_left: bool) -> void:
	var f := TextureRect.new()
	f.texture = _fist_tex
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.size = Vector2(320, 320)
	f.pivot_offset = f.size / 2.0
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 80
	add_child(f)
	var mirror := 1.0 if side_left else -1.0
	var start: Vector2 = Vector2(700.0, 1440.0) if side_left else Vector2(1220.0, 1440.0)
	f.scale = Vector2(mirror * 1.4, 1.4)
	f.position = start - f.size / 2.0
	var tw := create_tween()
	tw.tween_property(f, "position", pos - f.size / 2.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "scale", Vector2(mirror * 0.95, 0.95), 0.09)
	tw.tween_property(f, "modulate:a", 0.0, 0.14)
	tw.tween_callback(f.queue_free)
	_spawn_text(pos + Vector2(0, -60), "whiff", 34, Color(0.82, 0.84, 0.9))

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
	# Aim at the head or the torso cutout, biased to the struck side.
	var r := _part_global_rect(head if is_head else torso_spr)
	var fx := 0.30 if side_left else 0.70
	var fy := 0.5 if is_head else 0.4
	var impact: Vector2 = r.position + Vector2(r.size.x * fx, r.size.y * fy)
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
	if _state == BossState.VULNERABLE or frenzy > 0.0:
		_crit(impact, text_pos)
	else:
		_chip(impact, text_pos)
	# Directional reaction: the head snaps aside, the body rocks.
	if is_head:
		# Offset only — _pose_skeleton adds this to the rest pose. (This used
		# to write head.position and spring back to Vector2.ZERO, which parked
		# the head off its anchored rest spot after the very first head hit.)
		_head_hit = Vector2(34.0 if side_left else -34.0, 6.0)
		var kt := create_tween()
		kt.tween_property(self, "_head_hit", Vector2.ZERO, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	else:
		rig.position.x = 24.0 if side_left else -24.0
		var lt := create_tween()
		lt.tween_property(rig, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# The bone skeleton deforms the body: arms shudder outward on impact
	# (harder on a critical body blow).
	var crit := _state == BossState.VULNERABLE or frenzy > 0.0
	_jostle_arms((1.0 if crit else 0.6) * (0.7 if is_head else 1.0))
	if hp <= 0.0:
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
	_apply_damage(impact, float(randi_range(3, 6)), false)

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
	_apply_damage(impact, float(randi_range(9, 14)), true)
	# The opening is spent — the boss recovers to guard.
	if _state == BossState.VULNERABLE:
		_enter_guard()

# Every landed hit funnels through here: combos multiply damage, rage builds
# toward FRENZY, HP drains, and a damage number pops off the impact point.
func _apply_damage(impact: Vector2, base: float, crit: bool) -> void:
	combo += 1
	combo_time = COMBO_WINDOW
	max_combo = maxi(max_combo, combo)
	if _combo_label != null:
		_combo_label.pivot_offset = _combo_label.size / 2.0
		_combo_label.scale = Vector2.ONE * 1.45
	if crit:
		crits += 1
	var combo_mul := 1.0 + minf(float(combo) * 0.05, 0.8)
	var dmg := maxf(1.0, roundf(base * combo_mul * (1.35 if frenzy > 0.0 else 1.0)))
	_set_hp(hp - dmg)
	_spawn_text(impact + Vector2(randf_range(-20.0, 20.0), -50.0), str(int(dmg)),
		64 if crit else 44, Color(1, 0.32, 0.21) if crit else Color(1, 1, 1))
	if frenzy <= 0.0:
		_set_rage(rage + (13.0 if crit else 5.0))
		if rage >= 100.0:
			frenzy = 6.0
			_set_rage(0.0)
			_flash_screen(0.5)
			_shake(18.0, 0.4)
			_spawn_text(Vector2(960.0, 300.0), "FRENZY!!", 130, Color(1, 0.24, 0.94))

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

	# Fade the banner and reset the boss for the next round: more HP, back for more.
	var ft := create_tween()
	ft.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	round_num += 1
	hp_max = roundf(hp_max * ROUND_HP_SCALE)
	_set_hp(hp_max)
	_set_rage(0.0)
	combo = 0
	frenzy = 0.0
	_react_time = 0.0
	# Clear pose offsets so he comes back standing straight.
	_head_hit = Vector2.ZERO
	_jostle_arm = 0.0
	_jostle_fore = 0.0
	rig.rotation = 0.0
	rig.scale = Vector2.ONE
	rig.position = Vector2(0.0, 1700.0)  # start below the desk
	var back := create_tween()
	back.tween_property(rig, "position", Vector2.ZERO, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await back.finished

	# Round banner.
	ko_banner.text = "ROUND %d" % round_num
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.6, 0.6)
	var rt := create_tween()
	rt.tween_property(ko_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rt.tween_interval(0.9)
	rt.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	_say(ROUND_LINES[randi() % ROUND_LINES.size()])

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
	var hr := _part_global_rect(head)
	var head_top: Vector2 = hr.position + Vector2(hr.size.x * 0.5, 0.0)
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

func _set_hp(v: float) -> void:
	# The old K.O. meter is now the boss's health bar: full = healthy, empty = launch him.
	hp = clampf(v, 0.0, hp_max)
	ko_fill.anchor_right = hp / hp_max
	ko_fill.offset_right = 0.0

# --- layout helpers ---

func _center_pivot() -> void:
	# Scale/squash from the boss's feet (bottom-center).
	rig.pivot_offset = Vector2(rig.size.x / 2.0, rig.size.y)


# --- cutout boss rig -------------------------------------------------------
# The cartoon boss is sliced into 15 pieces (assets/boss2/parts). Each piece
# hangs off its bone as a Sprite2D, so rotating a bone swings that limb and
# everything below it. Pieces overlap at the joints so rotation never opens a
# gap. Slice space is base.png (354x1152-crop); it maps into Rig-local space
# with PART_SCALE about the origin below.
const PART_SCALE := 1.23431
const PART_OX := 41.55
const PART_OY := 60.0

# name, bone path under Skeleton, slice-space bbox origin, slice-space pivot, z
const _PARTS := [
	["foot_l",  "Hip/ThighL/ShinL/FootL", Vector2(0, 892),   Vector2(106, 905), 0],
	["foot_r",  "Hip/ThighR/ShinR/FootR", Vector2(199, 892), Vector2(248, 905), 0],
	["shin_l",  "Hip/ThighL/ShinL",       Vector2(10, 782),  Vector2(112, 790), 1],
	["shin_r",  "Hip/ThighR/ShinR",       Vector2(199, 782), Vector2(242, 790), 1],
	["thigh_l", "Hip/ThighL",             Vector2(77, 598),  Vector2(140, 620), 2],
	["thigh_r", "Hip/ThighR",             Vector2(177, 598), Vector2(212, 620), 2],
	["hips",    "Hip",                    Vector2(86, 524),  Vector2(176, 560), 3],
	# Pivot must be the bone's own position in slice space - Spine sits at
	# slice y470, not at the waist, or the torso detaches and the belt doubles.
	["torso",   "Hip/Spine",              Vector2(51, 296),  Vector2(176, 470), 4],
	["uarm_l",  "Hip/ArmL",               Vector2(27, 418),  Vector2(108, 405), 5],
	["uarm_r",  "Hip/ArmR",               Vector2(248, 418), Vector2(246, 405), 5],
	["farm_l",  "Hip/ArmL/ForearmL",      Vector2(9, 516),   Vector2(46, 522),  6],
	["farm_r",  "Hip/ArmR/ForearmR",      Vector2(296, 516), Vector2(306, 522), 6],
	["hand_l",  "Hip/ArmL/ForearmL/FistL", Vector2(5, 626),  Vector2(28, 634),  7],
	["hand_r",  "Hip/ArmR/ForearmR/FistR", Vector2(285, 626), Vector2(324, 634), 7],
]
# The head is built separately: its texture is swapped for expressions, so it
# uses the normalised head canvas (neck anchored at 230,470) rather than a
# slice bbox.
const HEAD_ANCHOR := Vector2(230, 470)
const HEAD_Z := 8

func _make_part(tex: Texture2D, origin: Vector2, pivot: Vector2, z: int,
		bone: Node, mat: Material) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(PART_SCALE, PART_SCALE)
	# Place the piece so its slice-space pivot lands on the bone's origin.
	s.position = (origin - pivot) * PART_SCALE
	s.z_index = z
	s.material = mat
	bone.add_child(s)
	return s

func _build_cutout_boss(mat: Material) -> void:
	if skel == null:
		return
	for entry in _PARTS:
		var bone := skel.get_node_or_null(NodePath(entry[1]))
		if bone == null:
			push_warning("cutout: missing bone %s" % entry[1])
			continue
		var tex: Texture2D = load("res://assets/boss2/parts/%s.png" % entry[0])
		var spr := _make_part(tex, entry[2], entry[3], entry[4], bone, mat)
		if entry[0] == "torso":
			torso_spr = spr
	# Head last, on the Head bone, pivoting at the neck.
	var hb := skel.get_node_or_null(NodePath("Hip/Spine/Chest/Head"))
	if hb != null:
		head = _make_part(_tex_neutral, Vector2.ZERO, HEAD_ANCHOR, HEAD_Z, hb, mat)
	# The old flat claymation art is superseded by the cutout pieces.
	body_spr.visible = false
	old_head.visible = false

# Global-space rect of a cutout piece, for aiming clicks and impact points.
func _part_global_rect(s: Sprite2D) -> Rect2:
	if s == null or s.texture == null:
		return Rect2()
	var sz: Vector2 = s.texture.get_size() * PART_SCALE
	return Rect2(s.get_global_transform() * Vector2.ZERO, sz * boss.scale)


# Idle life: the boss breathes, shifts his weight and lets his arms hang and
# swing. Runs every frame and owns every bone rotation, so impact reactions
# feed in through _jostle_arm / _jostle_fore rather than tweening bones directly.
func _pose_skeleton(delta: float) -> void:
	if skel == null:
		return
	_idle_t += delta
	# Two waves: a breath, and a slower weight shift from foot to foot.
	var breath := sin(_idle_t * 1.9)
	var sway := sin(_idle_t * 0.72)
	var trail := sin(_idle_t * 0.72 + 0.9)   # limbs lag the torso slightly
	# He gets visibly more agitated as he winds up and while he's open.
	var amp := 1.0
	if _state == BossState.WINDUP:
		amp = 1.7
	elif _state == BossState.VULNERABLE:
		amp = 2.2

	# Hips carry the weight shift; the torso counter-rotates so it reads as
	# shifting weight rather than the whole figure sliding sideways.
	bone_hip.position = _hip_rest + Vector2(sway * 5.0 * amp, -breath * 2.0)
	bone_hip.rotation = sway * 0.018 * amp
	bone_spine.rotation = -sway * 0.026 * amp + breath * 0.008
	bone_chest.rotation = -sway * 0.014 * amp + breath * 0.012
	bone_head.rotation = sway * 0.030 * amp - breath * 0.010

	# Arms hang and swing, opposite phase per side, with the impact shudder
	# layered on top. Hands trail the forearms by a beat.
	bone_arm_l.rotation = sway * 0.055 * amp + _jostle_arm
	bone_arm_r.rotation = -sway * 0.055 * amp - _jostle_arm
	bone_forearm_l.rotation = trail * 0.045 * amp + _jostle_fore
	bone_forearm_r.rotation = -trail * 0.045 * amp - _jostle_fore
	bone_fist_l.rotation = sin(_idle_t * 0.72 + 1.6) * 0.05 * amp
	bone_fist_r.rotation = -sin(_idle_t * 0.72 + 1.6) * 0.05 * amp

	# The weight shift travels down the legs; knees and ankles absorb it.
	bone_thigh_l.rotation = -sway * 0.020 * amp
	bone_thigh_r.rotation = -sway * 0.020 * amp
	bone_shin_l.rotation = sway * 0.014 * amp
	bone_shin_r.rotation = sway * 0.014 * amp
	bone_foot_l.rotation = -sway * 0.010 * amp
	bone_foot_r.rotation = -sway * 0.010 * amp

	# The head cutout hangs off the Head bone, so moving the bone moves it. The
	# knock from a head hit is layered on as a bone offset.
	bone_head.position = _head_rest + _head_hit + Vector2(sway * 3.0 * amp, -breath * 2.0)

# A hit makes the boss's arms shudder outward, then spring back. These feed
# _pose_skeleton as offsets rather than writing bone rotations directly.
func _jostle_arms(intensity: float) -> void:
	if skel == null:
		return
	var la := deg_to_rad(22.0 * intensity)
	var lf := deg_to_rad(30.0 * intensity)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_jostle_arm", la, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_jostle_fore", lf, 0.05).set_ease(Tween.EASE_OUT)
	var back := create_tween()
	back.set_parallel(true)
	back.tween_property(self, "_jostle_arm", 0.0, 0.42) \
		.set_delay(0.05).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	back.tween_property(self, "_jostle_fore", 0.0, 0.42) \
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
