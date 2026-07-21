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

# --- animation rig ---------------------------------------------------------
# BossRig owns every bone transform: it composes idle life (breathing, weight
# shift, blinking, fidgets) with additive offsets from whatever animations are
# in flight, so a stagger can play on top of breathing without them fighting.
# Preloaded rather than referenced by class_name: the global class registry
# lives in .godot/ which is gitignored, so a fresh clone would fail to parse
# until someone opened the editor.
const BossRigScript := preload("res://scripts/boss_rig.gd")
# 346 hand-written boss lines. Preloaded as a plain data script.
const Dia := preload("res://scripts/dialogue.gd")
# Anti-repeat selection state: category -> remaining shuffled indices.
var _line_bag: Dictionary = {}
var rig_anim  # BossRig

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

# --- screens / phases ------------------------------------------------------
enum Phase { TITLE, MENU, LEVELS, CUSTOMIZE, OPTIONS, PREFIGHT, FIGHT, GAMEOVER, VICTORY }
var phase: int = Phase.TITLE
var _screen: Control
var _screen_dim: ColorRect
var _screen_title: Label
var _screen_sub: Label
var _screen_hint: Label
var _hud_nodes: Array = []      # fight HUD, hidden on menu screens

# --- arcade scoring --------------------------------------------------------
var score: int = 0
var best_score: int = 0
# Lifetime stats. Cheap to keep and they feed the stress-relief fantasy
# directly - "you have thrown 4,812 punches at this man" is the payoff.
var stat_punches: int = 0
var stat_damage: int = 0
var stat_kos: int = 0
var stat_fired: int = 0
var stat_best_combo: int = 0
var _score_shown: float = 0.0     # eased toward `score` so the readout rolls up
# Gate on how fast punches can be thrown. Without it, mashing (or an
# autoclicker) farmed unlimited combo and made the guard/tell/dodge loop
# pointless - the whole game is meant to be timing, not DPS.
const PUNCH_COOLDOWN := 0.17
var _punch_cd: float = 0.0

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
var _react: Array[Texture2D] = []
var _react_tex: Texture2D
var _react_time: float = 0.0

# idle animation clock
var _clock: float = 0.0

var _punch_player: AudioStreamPlayer
var _ko_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _music_btn: Button
var music_on: bool = true
# Haptics. MAKE-IT-SELLABLE calls this the single biggest feel gap on mobile:
# on a phone the buzz is half of what sells a punch. No-op on desktop, so it
# costs nothing to leave on.
var haptics_on: bool = true

func _buzz(ms: int) -> void:
	if not haptics_on:
		return
	if OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(ms)

# --- juice / game-feel ---
var _shake_time: float = 0.0
var _shake_mag: float = 0.0
var _flash: ColorRect
const POW_WORDS := ["POW!", "BAM!", "WHAM!", "BOP!", "OOF!", "SMACK!", "KAPOW!"]

# --- fight loop (Punch-Out style) ---
enum BossState { GUARD, WINDUP, ATTACK, RECOVER, VULNERABLE, STUNNED }
var _state: int = BossState.GUARD
var _state_time: float = 0.0
var _koing: bool = false
var _prompt: Label
var _crit_player: AudioStreamPlayer
const WINDUP_DUR := 0.55
const VULN_DUR := 1.35
const ATTACK_DUR := 0.42

# How hard he fights back. BAG never attacks (pure stress relief), DEFENSIVE
# guards and dodges but won't swing, BRAWLER runs the full exchange.
enum Difficulty { BAG, DEFENSIVE, BRAWLER }
var difficulty: int = Difficulty.BRAWLER

# In-flight attack bookkeeping.
var _atk_side: bool = true
var _atk_kind: int = 0        # 0 jab, 1 hook, 2 uppercut
var _atk_resolved: bool = false
var _atk_whiffed: bool = false
var _is_feint: bool = false

# Player side of the exchange.
var player_hp_max: float = 100.0
var player_hp: float = 100.0
var _dodge_time: float = 0.0
var _dodge_dir: int = 0       # -1 left, +1 right, 0 duck
const DODGE_WINDOW := 0.40
var _player_bar: Panel

# --- levels ----------------------------------------------------------------
# Each level is a distinct fight. `pace` scales the gap between attacks, `dmg`
# is what a landed boss punch costs, `hp` is his health pool. Later entries add
# their own mechanics on top (see LEVELS[].gimmick).
var level: int = 1
const LEVELS := [
	{"name": "The 1:1", "hp": 120.0, "pace": 1.35, "dmg": 8.0, "gimmick": "basic",
	 "line": "So. Your numbers. They're... not great."},
	{"name": "Performance Review", "hp": 170.0, "pace": 1.1, "dmg": 11.0, "gimmick": "feint",
	 "line": "I've prepared some feedback. It's mostly negative."},
	{"name": "The Reorg", "hp": 230.0, "pace": 0.9, "dmg": 14.0, "gimmick": "double",
	 "line": "We're restructuring. You're the structure being restructured."},
	{"name": "Crunch Season", "hp": 300.0, "pace": 0.75, "dmg": 17.0, "gimmick": "rage",
	 "line": "Weekend's cancelled. So is your lunch. And your dignity."},
	{"name": "Team Building", "hp": 260.0, "pace": 1.2, "dmg": 0.0, "gimmick": "throw",
	 "line": "Trust fall! You catch me, right? ...Right?"},
	{"name": "Open Plan", "hp": 240.0, "pace": 1.2, "dmg": 0.0, "gimmick": "objects",
	 "line": "No walls means no place to hide. For YOU, obviously."},
	{"name": "The Offsite", "hp": 200.0, "pace": 1.2, "dmg": 0.0, "gimmick": "bridge",
	 "line": "Careful. It's a long way down and I've read the insurance policy."},
	{"name": "Company Car", "hp": 280.0, "pace": 1.2, "dmg": 0.0, "gimmick": "car",
	 "line": "I got the company car. You got the company newsletter."},
	{"name": "Moonshot", "hp": 320.0, "pace": 1.2, "dmg": 0.0, "gimmick": "moon",
	 "bg": "res://assets/scenes/sky.png", "bg_toon": false,
	 "line": "They said reach for the stars. I meant it as a metaphor. STOP—"},
]

# Bag-shuffle picker: a category works through every line before any repeats,
# so a 40-line pool never feels like 5. Beats plain randf(), which clusters.
func _line(cat: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	if not _line_bag.has(cat) or (_line_bag[cat] as Array).is_empty():
		var idx: Array = range(pool.size())
		idx.shuffle()
		_line_bag[cat] = idx
	var i: int = (_line_bag[cat] as Array).pop_back()
	return String(pool[i])

# Say a line from a category, unless something more important is still typing.
func _say_line(cat: String, pool: Array, force: bool = false) -> void:
	if pool.is_empty():
		return
	if not force and _type_shown < float(_type_full.length()):
		return   # let the current line finish
	_say(_line(cat, pool))

# Which attacks each level's boss actually throws. Later levels don't just
# telegraph faster - they bring different attacks, so the read changes too.
# 0 jab, 1 hook, 2 uppercut, 3 overhead, 4 double jab, 5 haymaker, 6 barge
const LEVEL_ATTACKS := {
	1: [0, 0, 1],
	2: [0, 1, 1, 2],
	3: [0, 1, 2, 4, 6],
	4: [1, 2, 3, 4, 5, 6],
}

# Opponent roster. A boss is a name + a look + a timing profile - the cutout
# rig and the look layers mean this is content, not engineering. Levels without
# a "look" use YOUR boss, i.e. whatever the player customised, so the
# customisation stays meaningful instead of being overwritten.
const ROSTER := {
	2: {"who": "Deborah, Regional", "skin": 1, "hair": 2, "moustache": 0},
	3: {"who": "Big Terry, Ops", "char": "big"},
	5: {"who": "The Facilitator", "skin": 2, "hair": 3, "moustache": 2},
	6: {"who": "Priya, Head of Pods", "skin": 4, "hair": 2, "moustache": 0},
	7: {"who": "Gareth, Offsite Lead", "skin": 1, "hair": 1, "moustache": 2},
	8: {"who": "Big Terry, Ops", "char": "big"},
	9: {"who": "Chief Vision Officer", "skin": 2, "hair": 2, "moustache": 2},
}

# Swap in this level's opponent. Levels absent from ROSTER restore the player's
# own saved look - those are the fights against YOUR boss.
func _apply_opponent() -> void:
	var r: Dictionary = ROSTER.get(level, {})
	# Swap the whole figure if this opponent is a different character.
	var want := String(r.get("char", "suit"))
	if want != character and _outline_mat != null:
		set_character(want, _outline_mat)
	if not has_expressions():
		return          # look layers are authored into that character's art
	if r.is_empty():
		look_skin = _own_skin
		look_hair = _own_hair
		look_moustache = _own_moustache
	else:
		look_skin = int(r.get("skin", 0))
		look_hair = int(r.get("hair", 0))
		look_moustache = int(r.get("moustache", 0))
	_apply_look_no_save()

func opponent_name() -> String:
	var r: Dictionary = ROSTER.get(level, {})
	return String(r.get("who", "Your Boss"))

func _attack_set() -> Array:
	return LEVEL_ATTACKS.get(level, [0, 1, 2])

func _level_cfg() -> Dictionary:
	return LEVELS[clampi(level - 1, 0, LEVELS.size() - 1)]

# --- controls / attacks ---
# The player's fist: the red boxing glove lifted from the cartoon hit frame, so
# it matches the new boss instead of the old claymation fist.
var _fist_tex: Texture2D = load("res://assets/boss2/parts/glove.png")
var _buttons := {}

func _ready() -> void:
	# Face sets are per-character now and loaded by _load_faces() during
	# set_character(); this used to pre-load boss2's sheet unconditionally.
	rig.resized.connect(_center_pivot)
	_center_pivot()
	# Let clicks pass through the boss Control to _unhandled_input, which
	# resolves them into aimed punches (see _punch_click).
	boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	_load_prefs()
	_setup_shots()

	_punch_player = AudioStreamPlayer.new()
	_punch_player.stream = _make_punch()
	add_child(_punch_player)
	_ko_player = AudioStreamPlayer.new()
	_ko_player.stream = _make_ko()
	add_child(_ko_player)
	_setup_music()

	# Music toggle, top-right. Also on the M key.
	_music_btn = Button.new()
	_music_btn.text = "|| PAUSE"
	_music_btn.focus_mode = Control.FOCUS_NONE
	_music_btn.add_theme_font_size_override("font_size", 22)
	_music_btn.anchor_left = 1.0
	_music_btn.anchor_right = 1.0
	_music_btn.offset_left = -180.0
	_music_btn.offset_right = -20.0
	# Below the dialogue bubble (which ends at y=336) - at y=152 it sat on top
	# of the bubble's corner.
	_music_btn.offset_top = 350.0
	_music_btn.offset_bottom = 398.0
	_music_btn.z_index = 60
	_music_btn.pressed.connect(_on_pause)
	safe.add_child(_music_btn)

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
	_capture_bone_home()
	_outline_mat = outline_mat
	set_character("suit", outline_mat)
	# Remember the rest pose so idle motion and hit reactions are offsets from
	# it rather than absolute positions (the head used to snap to Vector2.ZERO
	# after a hit, permanently shifting it off its anchored rest spot).
	# The animation rig: owns every bone transform and composes idle motion
	# with additive animation offsets (see boss_rig.gd).
	rig_anim = BossRigScript.new()
	add_child(rig_anim)
	rig_anim.setup(skel, rig, head)
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
	# Sized and centre-aligned inside its own box: at font size 96 the word
	# "COMBO" is ~380px wide, so anchoring by top-left at x=1560 ran it off the
	# 1920 edge. Right-anchored so mobile safe-area insets can't clip it either.
	_combo_label.size = Vector2(420, 230)
	_combo_label.anchor_left = 1.0
	_combo_label.anchor_right = 1.0
	_combo_label.offset_left = -450.0
	_combo_label.offset_right = -30.0
	_combo_label.offset_top = 300.0
	_combo_label.offset_bottom = 530.0
	_combo_label.rotation = -0.08
	_combo_label.visible = false
	safe.add_child(_combo_label)

	# Player health bar: third row under FRENZY and BOSS, styled to match them.
	# (First attempt put it bottom-left, where it collided with the hint text
	# and the punch counter, and an unstyled Panel rendered near-black.)
	var track_sb := (ko_fill.get_parent() as Panel).get_theme_stylebox("panel")
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.30, 0.72, 1.0)
	fill_sb.set_corner_radius_all(13)
	var ptrack := Panel.new()
	ptrack.anchor_right = 1.0
	ptrack.offset_left = 118.0
	ptrack.offset_top = 106.0
	ptrack.offset_right = -16.0
	ptrack.offset_bottom = 140.0
	ptrack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ptrack.add_theme_stylebox_override("panel", track_sb)
	safe.add_child(ptrack)
	_player_bar = Panel.new()
	_player_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_bar.anchor_right = 1.0
	_player_bar.anchor_bottom = 1.0
	_player_bar.add_theme_stylebox_override("panel", fill_sb)
	ptrack.add_child(_player_bar)
	var plabel := Label.new()
	plabel.text = "YOU"
	plabel.add_theme_font_size_override("font_size", 28)
	plabel.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	plabel.add_theme_constant_override("outline_size", 10)
	plabel.position = Vector2(16, 106)
	plabel.size = Vector2(94, 34)
	plabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	safe.add_child(plabel)

	ko_banner.modulate.a = 0.0
	# The meter now fills toward FRENZY as the player lands hits, so it starts
	# empty. (It used to be the boss's standing anger, which started at 12.)
	_set_rage(0.0)
	# Level 1 config drives the opening fight.
	hp_max = float(_level_cfg().get("hp", 120.0))
	_set_hp(hp_max)
	_set_player_hp(player_hp_max)
	_say(String(_level_cfg().get("line", OPENERS[randi() % OPENERS.size()])))
	_hud_nodes = [
		$Safe/RageLabel, $Safe/RageTrack, $Safe/KoLabel, $Safe/KoTrack,
		$Safe/Hint, counter, ptrack, plabel, _combo_label, _music_btn,
	]
	for b in _buttons.values():
		_hud_nodes.append(b)
	counter.text = "SCORE  0"
	# CLI is a SESSION override, never written to the save. Setting `portrait`
	# directly here leaked a test-only flag into the user's saved settings and
	# every later run came up portrait.
	if "--portrait" in OS.get_cmdline_user_args():
		_force_portrait = true
	_apply_portrait()
	apply_look()
	_build_screens()
	_build_menu_ui()
	_show_title()

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

	# The boss fight loop, only while an actual fight is running. Gimmick
	# levels swap it out for their own mechanic.
	if not _koing and phase == Phase.FIGHT:
		if _gimmick() in ["throw", "objects", "bridge", "car", "moon"]:
			_update_gimmick(delta)
		else:
			_update_fight(delta)

	# Idle life + any in-flight animation offsets, composed onto the bones.
	if rig_anim != null:
		rig_anim.update(delta)

	_update_pose(delta)
	_update_anim(delta)
	if _punch_cd > 0.0:
		_punch_cd -= delta
	# Roll the score readout up toward the real value rather than snapping.
	if absf(_score_shown - float(score)) > 0.5:
		_score_shown = lerpf(_score_shown, float(score), clampf(delta * 9.0, 0.0, 1.0))
		counter.text = "SCORE  %d" % int(round(_score_shown))
	elif counter.text == "":
		counter.text = "SCORE  0"

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
	if not has_expressions():
		# No face set for this character - reactions play on the head bone
		# instead. Still tick the timer so the state doesn't stick.
		_react_time = maxf(0.0, _react_time - delta)
	elif _react_time > 0.0:
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
	_say(_line("taunt", Dia.TAUNT))
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
	if event is InputEventKey or event is InputEventMouseButton 			or event is InputEventScreenTouch or event is InputEventJoypadButton:
		_kick_music()
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_A: _press("A")
				KEY_B: _press("B")
				KEY_X: _press("X")
				KEY_Y: _press("Y")
				# Dodging: arrows / WSD. Left and right slip the punch, down
				# ducks (which the uppercut punishes).
				KEY_M: toggle_music()
				# Customisation: skin / hair / moustache.
				KEY_K: cycle_look("skin")
				KEY_H: cycle_look("hair")
				KEY_J: cycle_look("moustache")
				KEY_1: _pick_difficulty(Difficulty.BAG)
				KEY_2: _pick_difficulty(Difficulty.DEFENSIVE)
				KEY_3: _pick_difficulty(Difficulty.BRAWLER)
				KEY_SPACE, KEY_ENTER: _advance_screen()
				KEY_LEFT: _dodge(-1)
				KEY_RIGHT: _dodge(1)
				KEY_DOWN: _dodge(0)
	elif event is InputEventJoypadButton:
		if event.pressed:
			match event.button_index:
				JOY_BUTTON_A: _press("A")
				JOY_BUTTON_B: _press("B")
				JOY_BUTTON_X: _press("X")
				JOY_BUTTON_Y: _press("Y")
				JOY_BUTTON_DPAD_LEFT: _dodge(-1)
				JOY_BUTTON_DPAD_RIGHT: _dodge(1)
				JOY_BUTTON_DPAD_DOWN: _dodge(0)
	elif event is InputEventMouseButton:
		# Touches arrive here too via Godot's emulate_mouse_from_touch.
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mp := get_global_mouse_position()
			if phase in [Phase.MENU, Phase.LEVELS, Phase.CUSTOMIZE, Phase.OPTIONS]:
				pass          # menu buttons handle their own taps
			elif phase != Phase.FIGHT:
				if event.pressed:
					_advance_screen()
			elif _gimmick() == "throw":
				if event.pressed:
					var r := (boss as Control).get_global_rect().grow(60.0)
					if r.has_point(mp):
						_grab = true
						_grab_off = mp - _boss_at
				else:
					_grab = false
			elif _gimmick() == "objects":
				if event.pressed:
					_throw_prop(mp)
			elif _gimmick() == "bridge":
				if event.pressed:
					_bridge_push(mp)
			elif _gimmick() == "car":
				if event.pressed:
					_car_run(mp)
			elif _gimmick() == "moon":
				if event.pressed:
					_moon_tap()
			elif event.pressed:
				_punch_click(mp)

# Click/tap anywhere: throw a fist at that exact point. Hits on the boss deal
# damage; clicks in open air still swing (and whiff).
func _punch_click(pos: Vector2) -> void:
	if phase != Phase.FIGHT or _koing or _punch_cd > 0.0:
		return
	_punch_cd = PUNCH_COOLDOWN
	var boss_rect := (boss as Control).get_global_rect().grow(20.0)
	var head_rect := _part_global_rect(head).grow(10.0)
	var boss_cx := boss_rect.position.x + boss_rect.size.x * 0.5
	var side_left := pos.x < boss_cx
	if not boss_rect.has_point(pos):
		_throw_whiff(pos, side_left)
		return
	punches += 1
	stat_punches += 1
	_throw_fist(pos, side_left, head_rect.has_point(pos))

func _throw_whiff(pos: Vector2, side_left: bool) -> void:
	var f := TextureRect.new()
	f.texture = _fist_tex
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.size = Vector2(250, 250)
	f.pivot_offset = f.size / 2.0
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 80
	add_child(f)
	var mirror := 1.0 if side_left else -1.0
	var start: Vector2 = Vector2(700.0, 1440.0) if side_left else Vector2(1220.0, 1440.0)
	f.scale = Vector2(mirror * 1.15, 1.15)
	f.position = start - f.size / 2.0
	var tw := create_tween()
	tw.tween_property(f, "position", pos - f.size / 2.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "scale", Vector2(mirror * 0.82, 0.82), 0.09)
	tw.tween_property(f, "modulate:a", 0.0, 0.14)
	tw.tween_callback(f.queue_free)
	_spawn_text(pos + Vector2(0, -60), "whiff", 34, Color(0.82, 0.84, 0.9))
	if randf() < 0.35:
		_say_line("miss", Dia.MISS)

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
	if phase != Phase.FIGHT or _koing or _punch_cd > 0.0:
		return
	_punch_cd = PUNCH_COOLDOWN
	punches += 1
	stat_punches += 1
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
	f.size = Vector2(250, 250)
	f.pivot_offset = f.size / 2.0
	var mirror := 1.0 if side_left else -1.0  # mirror the fist for the other hand
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 80
	add_child(f)
	# First-person punch: the fist thrusts up from the player's side (near the
	# camera, so it starts large) and fully extends to reach the boss, then
	# retracts. No detached "flying fist" arcing in from off-screen.
	var start: Vector2 = Vector2(700.0, 1440.0) if side_left else Vector2(1220.0, 1440.0)
	# Kept modest on purpose: at 320px/1.4 the glove filled enough of the frame
	# to hide the boss's reaction, which is the thing worth watching.
	var start_scale := 1.15  # close to the viewer at the start of the thrust
	var reach_scale := 0.82  # arm fully extended toward the boss
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
	var crit := _state == BossState.VULNERABLE or frenzy > 0.0
	_react_hit(is_head, side_left, crit)
	_hit_banter()
	if hp <= 0.0:
		_knockout()

# Banter on hits: sparse on purpose, and it escalates. Low HP switches to the
# desperation bank, and a running combo gets its own reactions.
func _hit_banter() -> void:
	if hp <= hp_max * 0.28 and randf() < 0.5:
		_say_line("lowhp", Dia.LOWHP)
	elif combo >= 4 and randf() < 0.3:
		_say_line("combo", Dia.COMBO_LINES)
	elif randf() < 0.22:
		_say_line("hit", Dia.HIT)

# Cartoon hit reactions. Chip hits just flinch; criticals roll a big Looney
# Tunes gag — the head spinning right around, the neck stretching like rubber,
# or a dazed metronome wobble.
func _react_hit(is_head: bool, side_left: bool, crit: bool) -> void:
	# A drawn pose can't flinch - drop back to the rig for the reaction.
	set_pose("")
	if rig_anim == null:
		return
	rig_anim.squash(1.0 if crit else 0.55)
	if is_head:
		if crit:
			# Big head hits roll one of the cartoon gags.
			match randi() % 6:
				0:
					rig_anim.head_spin(randi_range(2, 4))
				1:
					rig_anim.neck_stretch(side_left, 1.0)
				2:
					rig_anim.wobble_stun(1.3)
				3:
					rig_anim.rubber_neck(randi_range(3, 5))
				4:
					rig_anim.spin_body(randi_range(1, 2))
				_:
					rig_anim.stretch_up(1.0)
		else:
			if randf() < 0.25:
				rig_anim.rubber_neck(2)
			else:
				rig_anim.stagger(side_left, 0.7)
	else:
		rig_anim.stagger(side_left, 1.0 if crit else 0.55)
		if crit:
			match randi() % 4:
				0:
					rig_anim.flatten(1.0)
				1:
					rig_anim.jelly_legs(0.9)
				2:
					rig_anim.shock_hop(1.0)
				_:
					rig_anim.knees_buckle(0.9)

func _chip(impact: Vector2, text_pos: Vector2) -> void:
	# A normal punch while the boss is guarding: small damage, standard juice.
	# Pitch climbs with the combo - the classic arcade cue that a run is
	# building. Capped so it never turns into a squeak.
	_punch_player.pitch_scale = clampf(0.92 + float(combo) * 0.045, 0.9, 1.9) 		* randf_range(0.97, 1.04)
	_punch_player.play()
	_react_tex = _react[randi() % _react.size()]
	_react_time = 0.28
	# (The impact squash now comes from BossRig.squash via _react_hit.)
	_flash_screen(0.22)
	_shake(9.0, 0.24)
	_spawn_text(text_pos, POW_WORDS[randi() % POW_WORDS.size()], 84, Color(1, 0.86, 0.16))
	_spawn_stars(impact, 5)
	_hitstop(0.05)
	_buzz(18)
	_apply_damage(impact, float(randi_range(3, 6)), false)

func _crit(impact: Vector2, text_pos: Vector2) -> void:
	# A punch landed in the vulnerable window: big damage + maxed-out juice.
	_crit_player.play()
	_punch_player.pitch_scale = clampf(1.15 + float(combo) * 0.05, 1.1, 2.1) 		* randf_range(0.97, 1.04)
	_punch_player.play()
	_react_tex = _react[_react.size() - 1 - (randi() % 3)]
	_react_time = 0.5
	# (The impact squash now comes from BossRig.squash via _react_hit.)
	_flash_screen(0.55)
	_shake(26.0, 0.45)
	_zoom_punch(0.06)
	_spawn_text(text_pos, "CRITICAL!", 118, Color(1, 0.3, 0.22))
	_spawn_stars(impact, 14)
	_spawn_sweat(impact)
	_hitstop(0.11)
	_buzz(45)
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
	# Multiplier climbs to 4x. It can go this high because the punch cooldown
	# means a long combo has to be *earned* on timing rather than farmed by
	# mashing - which is what the old 1.8x ceiling was compensating for.
	var combo_mul := 1.0 + minf(float(combo) * 0.14, 3.0)
	var dmg := maxf(1.0, roundf(base * combo_mul * (1.35 if frenzy > 0.0 else 1.0)))
	_set_hp(hp - dmg)
	stat_damage += int(dmg)
	stat_best_combo = maxi(stat_best_combo, combo)
	_spawn_text(impact + Vector2(randf_range(-20.0, 20.0), -50.0), str(int(dmg)),
		64 if crit else 44, Color(1, 0.32, 0.21) if crit else Color(1, 1, 1))
	# Score: damage scaled by the multiplier, bonus for criticals and frenzy.
	var gained := int(roundf(dmg * 10.0 * combo_mul * (2.0 if crit else 1.0)))
	_add_score(gained, impact)
	if frenzy <= 0.0:
		_set_rage(rage + (13.0 if crit else 5.0))
		if rage >= 100.0:
			frenzy = 6.0
			_set_rage(0.0)
			_flash_screen(0.5)
			_shake(18.0, 0.4)
			_spawn_text(Vector2(960.0, 300.0), "FRENZY!!", 130, Color(1, 0.24, 0.94))

# Award points and pop a floating "+N" at the impact. Big gains read louder.
func _add_score(amount: int, at: Vector2) -> void:
	if amount <= 0:
		return
	score += amount
	best_score = maxi(best_score, score)
	var big := amount >= 300
	_spawn_text(at + Vector2(randf_range(-30.0, 30.0), -120.0), "+%d" % amount,
		54 if big else 38, Color(1, 0.86, 0.20) if big else Color(0.95, 0.95, 0.7))

# --- boss fight state machine ---
#
# The Punch-Out exchange: GUARD -> WINDUP (readable tell) -> ATTACK (the player
# must dodge on time) -> RECOVER. A dodged attack leaves him wide open, which is
# the punish window; a landed one costs the player health. Timing is the game,
# not mashing.

func _update_fight(delta: float) -> void:
	var lean := 0.0
	var tint := Color(1, 1, 1)
	_state_time -= delta
	if _dodge_time > 0.0:
		_dodge_time -= delta
	match _state:
		BossState.GUARD:
			if _state_time <= 0.0:
				if difficulty == Difficulty.BAG:
					_enter_vulnerable()   # punching bag: always an opening
				else:
					_enter_windup()
		BossState.WINDUP:
			if _is_feint and _state_time <= 0.0:
				# Aborted swing - straight back to guard, no attack.
				_spawn_text(_text_anchor(_atk_side), "FEINT!", 60, Color(1, 0.62, 0.2))
				_enter_guard()
				return
			# Lean back + pulse orange so the "tell" is unmistakable.
			var t := 1.0 - clampf(_state_time / _windup_dur(), 0.0, 1.0)
			lean = -0.22 * t
			var pw := 0.5 + 0.5 * sin(_clock * 26.0)
			tint = Color(1, 1, 1).lerp(Color(1.5, 0.7, 0.2), pw * t)
			if _state_time <= 0.0:
				_enter_attack()
		BossState.ATTACK:
			# Resolve at the strike frame, partway through the swing.
			if not _atk_resolved and _state_time <= ATTACK_DUR * 0.55:
				_atk_resolved = true
				_resolve_attack()
			if _state_time <= 0.0:
				if _atk_whiffed:
					_enter_vulnerable()
				else:
					_enter_guard()
		BossState.RECOVER:
			if _state_time <= 0.0:
				_enter_guard()
		BossState.VULNERABLE:
			# Flash yellow + show the prompt: this is the punish window.
			var pv := 0.5 + 0.5 * sin(_clock * 14.0)
			tint = Color(1, 1, 1).lerp(Color(1.6, 1.5, 0.25), pv)
			lean = sin(_clock * 22.0) * 0.03
			_position_prompt(pv)
			if _state_time <= 0.0:
				_enter_guard()
		BossState.STUNNED:
			var ps := 0.5 + 0.5 * sin(_clock * 9.0)
			tint = Color(1, 1, 1).lerp(Color(1.3, 1.3, 1.7), ps * 0.6)
			_position_prompt(ps)
			if _state_time <= 0.0:
				_enter_guard()
	# The wind-up lean feeds BossRig as a body offset — writing rig.rotation
	# here directly would be overwritten by the rig's own compose pass.
	if rig_anim != null:
		rig_anim.lean = lean
	boss.modulate = tint

func _windup_dur() -> float:
	# Later levels telegraph faster, so the dodge window tightens.
	return maxf(0.22, WINDUP_DUR - float(level - 1) * 0.05)

func _enter_guard() -> void:
	_state = BossState.GUARD
	_state_time = randf_range(2.6, 4.2) * _level_cfg().get("pace", 1.0)
	_prompt.visible = false
	boss.modulate = Color(1, 1, 1)
	if has_pose("guard"):
		set_pose("guard")
	elif rig_anim != null and difficulty != Difficulty.BAG:
		rig_anim.block()

func _enter_windup() -> void:
	_state = BossState.WINDUP
	_state_time = _windup_dur()
	_prompt.visible = false
	_shake(4.0, 0.2)
	# Pick the attack now so the tell can match the side it comes from.
	_atk_side = randf() < 0.5
	var set_: Array = _attack_set()
	_atk_kind = int(set_[randi() % set_.size()])
	# Feints appear from level 2 on: he starts the tell then aborts, baiting a
	# panic dodge. The dodge window is short enough that wasting one hurts.
	_is_feint = level >= 2 and randf() < 0.18
	_atk_resolved = false
	_atk_whiffed = false
	# The tell and the swing need articulated arms.
	set_pose("palm" if (_is_feint and has_pose("palm")) else "")
	# He scowls through the wind-up where that art exists.
	if not _angry_faces.is_empty():
		_react_tex = _angry_faces[randi() % _angry_faces.size()]
		_react_time = _windup_dur() + ATTACK_DUR
	if rig_anim != null:
		rig_anim.unblock()
		if _is_feint:
			rig_anim.feint(_atk_side)
		else:
			rig_anim.tell(_atk_side, _windup_dur())

func _enter_attack() -> void:
	set_pose("")
	_state = BossState.ATTACK
	_state_time = ATTACK_DUR
	if rig_anim != null:
		match _atk_kind:
			0:
				rig_anim.jab(_atk_side)
			1:
				rig_anim.hook(_atk_side)
			2:
				rig_anim.uppercut(_atk_side)
			3:
				rig_anim.overhead(_atk_side)
			4:
				rig_anim.double_jab(_atk_side)
			5:
				rig_anim.haymaker(_atk_side)
			_:
				rig_anim.barge(_atk_side)

# Did the player dodge in time? A dodge in any direction beats a jab/hook; the
# uppercut has to be dodged sideways (ducking into it is exactly wrong).
func _resolve_attack() -> void:
	var dodged := _dodge_time > 0.0
	# Attack-specific dodge rules, so reading WHICH attack matters:
	#   uppercut  - ducking into it is exactly wrong
	#   overhead  - must be ducked; stepping aside won't clear it
	#   barge     - must be sidestepped; ducking gets you run over
	if dodged:
		if _atk_kind == 2 and _dodge_dir == 0:
			dodged = false
		elif _atk_kind == 3 and _dodge_dir != 0:
			dodged = false
		elif _atk_kind == 6 and _dodge_dir == 0:
			dodged = false
	if dodged:
		_atk_whiffed = true
		_spawn_text(_text_anchor(not _atk_side), "MISS!", 72, Color(0.6, 1.0, 0.7))
		_shake(6.0, 0.18)
		if rig_anim != null:
			rig_anim.body_pos = Vector2(0, 0)
	else:
		_hit_player()

func _hit_player() -> void:
	_buzz(80)
	player_hp = maxf(0.0, player_hp - _level_cfg().get("dmg", 10.0))
	_flash_screen(0.42)
	_shake(30.0, 0.4)
	_hitstop(0.08)
	_spawn_text(Vector2(960.0, 420.0), "OUCH!", 96, Color(1, 0.3, 0.25))
	combo = 0
	_set_player_hp(player_hp)
	if player_hp <= 0.0:
		_game_over()

func _enter_vulnerable() -> void:
	set_pose("")
	_state = BossState.VULNERABLE
	_state_time = VULN_DUR
	_prompt.visible = true
	if rig_anim != null:
		rig_anim.unblock()

# Player dodge. Brief invulnerability window; direction matters against the
# uppercut, which punishes ducking.
func _dodge(dir: int) -> void:
	if _koing:
		return
	_dodge_time = DODGE_WINDOW
	_dodge_dir = dir
	# The camera leans opposite the dodge so it reads as the player moving.
	var shift := Vector2(-90.0 * float(dir), 30.0 if dir == 0 else 0.0)
	var tw := create_tween()
	tw.tween_property(safe, "position", shift, 0.10).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(safe, "position", Vector2.ZERO, 0.24).set_trans(Tween.TRANS_BACK)

func _set_player_hp(v: float) -> void:
	player_hp = clampf(v, 0.0, player_hp_max)
	if _player_bar != null:
		_player_bar.anchor_right = player_hp / player_hp_max
		_player_bar.offset_right = 0.0

func _game_over() -> void:
	if _koing:
		return
	_koing = true
	stat_fired += 1
	best_score = maxi(best_score, score)
	_save_prefs()
	_say(_line("down", Dia.PLAYER_DOWN))
	ko_banner.text = "YOU'RE FIRED"
	ko_banner.pivot_offset = ko_banner.size / 2.0
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.5, 0.5)
	var bt := create_tween()
	bt.tween_property(ko_banner, "scale", Vector2(1.1, 1.1), 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if rig_anim != null:
		rig_anim.laugh()
	_flash_screen(0.5)
	_shake(24.0, 0.5)
	await get_tree().create_timer(2.0).timeout
	_show_gameover(false)

# Restart the current level with everything reset.
func _restart_level() -> void:
	var cfg := _level_cfg()
	hp_max = float(cfg.get("hp", 120.0))
	_set_hp(hp_max)
	_set_player_hp(player_hp_max)
	_set_rage(0.0)
	combo = 0
	frenzy = 0.0
	_react_time = 0.0
	if rig_anim != null:
		rig_anim.revive()
		rig_anim.lean = 0.0
		rig_anim.own_body = true
	var ft := create_tween()
	ft.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	_koing = false
	_say(String(cfg.get("line", "")))
	_enter_guard()

# Heavy punish: he's dazed and wide open for a while.
func _enter_stunned(duration: float) -> void:
	_state = BossState.STUNNED
	_state_time = duration
	_prompt.visible = true
	if rig_anim != null:
		rig_anim.unblock()
		rig_anim.wobble_stun(duration)

func _position_prompt(p: float) -> void:
	var top: Vector2 = boss.get_global_transform() * Vector2(boss.size.x * 0.5, 0.0)
	_prompt.pivot_offset = _prompt.size / 2.0
	_prompt.global_position = top - Vector2(_prompt.size.x * 0.5, 46.0 + p * 12.0)
	_prompt.scale = Vector2.ONE * (1.0 + p * 0.12)

func _knockout() -> void:
	_koing = true
	_prompt.visible = false
	boss.modulate = Color(1, 1, 1)
	_ko_player.play()
	_flash_screen(0.85)
	_shake(42.0, 0.7)
	_zoom_punch(0.1)
	# The launch cutscene drives the rig Control itself, so take the body away
	# from BossRig for the duration or the two will fight over the transform.
	if rig_anim != null:
		rig_anim.own_body = false
		rig_anim.idle_enabled = false

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
	_say(_line("ko", Dia.KO))
	await get_tree().create_timer(1.1).timeout

	# Fade the banner and stand him back up, then hand off to the win screen.
	# (The old behaviour looped straight into another round with 1.4x HP, which
	# compounded to ~100k HP by round 20 and never let the player finish.)
	var ft := create_tween()
	ft.tween_property(ko_banner, "modulate:a", 0.0, 0.4)
	_react_time = 0.0
	if rig_anim != null:
		rig_anim.revive()
		rig_anim.lean = 0.0
	rig.rotation = 0.0
	rig.scale = Vector2.ONE
	rig.position = Vector2(0.0, 1700.0)  # start below the desk
	var back := create_tween()
	back.tween_property(rig, "position", Vector2.ZERO, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await back.finished
	# Hand the body transform back to the rig now the cutscene is done.
	if rig_anim != null:
		rig_anim.own_body = true
	stat_kos += 1
	_save_prefs()
	_koing = false
	if _shot_mode:
		# Keep the filmstrip demo fighting instead of parking on a screen.
		_start_fight()
		return
	_show_gameover(true)

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
	["foot_l",  "Hip/ThighL/ShinL/FootL", Vector2(0, 866),   Vector2(106, 905), 0],
	["foot_r",  "Hip/ThighR/ShinR/FootR", Vector2(199, 866), Vector2(248, 905), 0],
	["shin_l",  "Hip/ThighL/ShinL",       Vector2(3, 752),  Vector2(112, 790), 1],
	["shin_r",  "Hip/ThighR/ShinR",       Vector2(199, 752), Vector2(242, 790), 1],
	["thigh_l", "Hip/ThighL",             Vector2(77, 582),  Vector2(140, 620), 2],
	["thigh_r", "Hip/ThighR",             Vector2(177, 582), Vector2(212, 620), 2],
	["hips",    "Hip",                    Vector2(84, 505),  Vector2(176, 560), 3],
	# Pivot must be the bone's own position in slice space - Spine sits at
	# slice y470, not at the waist, or the torso detaches and the belt doubles.
	["torso",   "Hip/Spine",              Vector2(51, 290),  Vector2(176, 470), 4],
	["uarm_l",  "Hip/ArmL",               Vector2(23, 418),  Vector2(108, 405), 5],
	["uarm_r",  "Hip/ArmR",               Vector2(248, 418), Vector2(246, 405), 5],
	["farm_l",  "Hip/ArmL/ForearmL",      Vector2(5, 486),   Vector2(46, 522),  6],
	["farm_r",  "Hip/ArmR/ForearmR",      Vector2(292, 486), Vector2(306, 522), 6],
	["hand_l",  "Hip/ArmL/ForearmL/FistL", Vector2(5, 596),  Vector2(28, 634),  7],
	["hand_r",  "Hip/ArmR/ForearmR/FistR", Vector2(285, 596), Vector2(324, 634), 7],
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

func _build_parts_suit(mat: Material) -> void:
	if skel == null:
		return
	var skin_parts := ["uarm_l", "uarm_r", "farm_l", "farm_r", "hand_l", "hand_r"]
	for entry in _PARTS:
		var bone := skel.get_node_or_null(NodePath(entry[1]))
		if bone == null:
			push_warning("cutout: missing bone %s" % entry[1])
			continue
		var tex: Texture2D = load("res://assets/boss2/parts/%s.png" % entry[0])
		# Skin pieces need their OWN material instance: shader uniforms live on
		# the material, so a shared one would recolour every piece at once.
		var pm: Material = mat
		if entry[0] in skin_parts:
			pm = mat.duplicate()
		var spr := _make_part(tex, entry[2], entry[3], entry[4], bone, pm)
		_char_sprites.append(spr)
		if entry[0] in skin_parts:
			_skin_sprites.append(spr)
		if entry[0] == "torso":
			torso_spr = spr
	# Head last, on the Head bone, pivoting at the neck.
	var hb := skel.get_node_or_null(NodePath("Hip/Spine/Chest/Head"))
	if hb != null:
		head = _make_part(_tex_neutral, Vector2.ZERO, HEAD_ANCHOR, HEAD_Z, hb, mat.duplicate())
		_skin_sprites.append(head)
		_char_sprites.append(head)
	# The old flat claymation art is superseded by the cutout pieces.
	body_spr.visible = false
	old_head.visible = false

# Global-space rect of a cutout piece, for aiming clicks and impact points.
func _part_global_rect(s: Sprite2D) -> Rect2:
	if s == null or s.texture == null:
		return Rect2()
	var sz: Vector2 = s.texture.get_size() * PART_SCALE
	return Rect2(s.get_global_transform() * Vector2.ZERO, sz * boss.scale)


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
	# K.O. sting: a low impact boom under a rising five-note fanfare, with a
	# little vibrato and a noise transient so it lands like a hit rather than a
	# menu beep. (The old version was three plain sine notes.)
	var rate := 44100
	var dur := 1.15
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]   # C5 E5 G5 C6 E6
	var seg_len := 0.16
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		# Impact boom: fast pitch drop plus a noise burst.
		if t < 0.30:
			var benv := exp(-t * 11.0)
			s += sin(TAU * lerpf(150.0, 42.0, t / 0.30) * t) * benv * 0.75
			s += (randf() * 2.0 - 1.0) * exp(-t * 34.0) * 0.30
		# Fanfare over the top.
		var seg := int(t / seg_len)
		if seg < notes.size():
			var lt := t - float(seg) * seg_len
			var env := exp(-lt * 5.5)
			var f: float = notes[seg] * (1.0 + sin(TAU * 5.5 * t) * 0.006)
			s += sin(TAU * f * t) * env * 0.34
			s += sin(TAU * f * 2.0 * t) * env * 0.12
		# Final note rings on.
		if t > float(notes.size()) * seg_len:
			var rt := t - float(notes.size()) * seg_len
			var renv := exp(-rt * 3.4)
			s += sin(TAU * 1318.5 * (1.0 + sin(TAU * 5.0 * t) * 0.008) * t) * renv * 0.30
			s += sin(TAU * 659.25 * t) * renv * 0.14
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

# --- debug: self-serve visual verification ----------------------------------
# Run with:  Godot --path game -- --shots
# Dumps a filmstrip of viewport PNGs to user://shots and drives a scripted
# demo (punches, dodges, criticals) so the frames capture the game in motion
# rather than a static idle pose. Lets the build be checked visually without a
# human watching the window. Exits on its own when the strip is complete.
const SHOT_COUNT := 48
const SHOT_INTERVAL := 0.30

var _shot_interval: float = SHOT_INTERVAL
var _demo_period: float = 0.60
var _shot_mode: bool = false
var _shot_i: int = 0
var _demo_step: int = 0

func _setup_shots() -> void:
	if not ("--shots" in OS.get_cmdline_user_args()):
		return
	_shot_mode = true
	# --shots-fast samples densely enough to catch short-lived effects (the
	# thrown glove is only on screen ~0.22s, so the default 0.30s cadence can
	# skip every single one).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--winsize="):
			var wh := a.get_slice("=", 1).split("x")
			if wh.size() == 2:
				get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		if a.begins_with("--level="):
			level = clampi(int(a.get_slice("=", 1)), 1, LEVELS.size())
			print("[shots] level %d (%s)" % [level, _level_cfg().get("gimmick", "punch")])
	if "--shots-fast" in OS.get_cmdline_user_args():
		_shot_interval = 0.09
		_demo_period = 0.45
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	# Clear any previous strip so old frames can't be mistaken for new ones.
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".png"):
				d.remove(f)
			f = d.get_next()
		d.list_dir_end()
	print("[shots] writing to ", ProjectSettings.globalize_path(dir))
	_kick_music()   # no real input in the demo, so start it explicitly
	var t := Timer.new()
	t.wait_time = _shot_interval
	t.autostart = true
	t.timeout.connect(_take_shot)
	add_child(t)
	var dm := Timer.new()
	dm.wait_time = _demo_period
	dm.autostart = true
	dm.timeout.connect(_demo_tick)
	add_child(dm)

var _tour: int = 0

func _demo_tour() -> void:
	match phase:
		Phase.TITLE:
			open_menu(Phase.MENU)
		Phase.MENU:
			_tour += 1
			match _tour:
				1:
					open_menu(Phase.LEVELS)
				2:
					open_menu(Phase.CUSTOMIZE)
				3:
					open_menu(Phase.OPTIONS)
				_:
					_on_play()
		Phase.LEVELS, Phase.OPTIONS:
			open_menu(Phase.MENU)
		Phase.CUSTOMIZE:
			# Exercise the cycle buttons before moving on.
			cycle_look("hair")
			cycle_look("moustache")
			open_menu(Phase.MENU)
		_:
			_advance_screen()

func _take_shot() -> void:
	# Guard: the timer can fire again during the await below, which produced a
	# stray extra frame and a duplicate "done" line.
	if _shot_i >= SHOT_COUNT:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/shot_%03d.png" % _shot_i)
	_shot_i += 1
	if _shot_i >= SHOT_COUNT:
		print("[shots] done: %d frames" % _shot_i)
		_release_music()
		get_tree().quit()

# Scripted play so the filmstrip exercises real states: body and head punches,
# dodges in each direction, and a spell of doing nothing so the boss's own
# attack cycle and idle life get captured too.
func _demo_tick() -> void:
	if _koing:
		return
	# Walk the whole front end so the filmstrip covers every screen, not just
	# combat: title -> menu -> levels -> customise -> options -> play.
	if phase != Phase.FIGHT:
		_demo_tour()
		return
	_demo_step += 1
	# Exercise PAUSE once mid-fight so the filmstrip proves it returns to the
	# menu, rather than trusting the signal connection.
	if _demo_step == 16 and phase == Phase.FIGHT:
		_on_pause()
		return
	# Gimmick levels need their own scripted play.
	match _gimmick():
		"throw":
			# Fling him: grab, whip the velocity, release.
			_grab = false
			_boss_vel = Vector2(randf_range(-1100.0, 1100.0), randf_range(-1250.0, -650.0))
			return
		"objects":
			var r := (boss as Control).get_global_rect()
			_throw_prop(r.position + Vector2(r.size.x * randf_range(0.2, 0.8),
				r.size.y * randf_range(0.1, 0.7)))
			return
		"bridge":
			var rb := (boss as Control).get_global_rect()
			_bridge_push(rb.position + Vector2(rb.size.x * (0.1 if randf() < 0.5 else 0.9),
				rb.size.y * 0.4))
			return
		"car":
			_car_run(Vector2.ZERO)
			return
		"moon":
			_moon_tap()
			return
		_:
			pass
	match _demo_step % 8:
		1, 2:
			_punch(_demo_step % 2 == 0, true)    # head
		3:
			_punch(true, false)                  # body
		4:
			_dodge(-1)
		5:
			_punch(false, false)
		6:
			_dodge(1)
		7:
			_dodge(0)
			cycle_look("skin")
			cycle_look("hair")
			cycle_look("moustache")
		_:
			# Exercise the music toggle (and therefore the save path) once per
			# demo run, so persistence is verified rather than assumed.
			if _demo_step == 8:
				toggle_music()
				toggle_music()

# --- fight music ------------------------------------------------------------
# A short procedural chiptune loop, generated the same way as the punch/K.O.
# hits so the game still ships with zero audio assets. Square-wave bass on the
# downbeats plus a triangle arpeggio; the whole bar loops seamlessly.
const MUSIC_BPM := 132.0

func _make_music() -> AudioStreamWAV:
	var rate := 44100
	var beat := 60.0 / MUSIC_BPM
	var bars := 4
	var dur := beat * 4.0 * float(bars)
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	# i-vi-III-VII in A minor: brooding but bouncy, fits the office-brawl tone.
	var roots := [55.00, 43.65, 65.41, 49.00]   # A1, F1, C2, G1
	var arp := [0.0, 3.0, 7.0, 12.0, 7.0, 3.0]  # minor triad up and back
	for i in n:
		var t := float(i) / rate
		var bar := int(t / (beat * 4.0)) % bars
		var root: float = roots[bar]
		var tb := fmod(t, beat)                 # position inside the beat
		# Bass: square wave, plucked envelope on every beat.
		var benv := exp(-tb * 7.0)
		var bs := (1.0 if sin(TAU * root * t) >= 0.0 else -1.0) * benv * 0.30
		# Arpeggio: triangle, six steps per bar.
		var step := int(t / (beat * 4.0 / float(arp.size()))) % arp.size()
		var af: float = root * 4.0 * pow(2.0, float(arp[step]) / 12.0)
		var aenv := exp(-fmod(t, beat * 4.0 / float(arp.size())) * 9.0)
		var ph := fmod(af * t, 1.0)
		var tri := 4.0 * absf(ph - 0.5) - 1.0
		var as_ := tri * aenv * 0.16
		data.encode_s16(i * 2, int(clampf(bs + as_, -1.0, 1.0) * 32767.0))
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

func _notification(what: int) -> void:
	# --quit-after and a window close take different teardown paths, so cover
	# both plus the plain tree exit.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE 			or what == NOTIFICATION_EXIT_TREE:
		_release_music()

func _exit_tree() -> void:
	_release_music()

# A looping AudioStreamWAV left playing survives teardown - its stream and
# playback show up as 2 leaked ObjectDB instances at exit. Confirmed by
# disabling the music entirely, which cleared the warning. Stopping and
# detaching the stream before the tree goes away releases both.
func _release_music() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null

func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = _make_music()
	_music_player.volume_db = -12.0
	add_child(_music_player)
	# Deliberately NOT started here. Browsers refuse audio until the user has
	# interacted with the page, so a web build that calls play() during _ready
	# stays silent for the whole session. Started on the first input instead
	# (see _kick_music), which costs nothing on desktop or mobile.

# Start the music on the first real user interaction. Required for web audio
# autoplay policy; a harmless no-op everywhere else.
var _music_started: bool = false

func _kick_music() -> void:
	if _music_started or _music_player == null:
		return
	_music_started = true
	if music_on:
		_music_player.play()

# Leave a fight and go back to the menu. Progress in the fight is abandoned;
# the level itself stays unlocked.
func _on_pause() -> void:
	if phase != Phase.FIGHT:
		return
	set_pose("")
	open_menu(Phase.MENU)

func toggle_music() -> void:
	_music_started = true
	music_on = not music_on
	if _music_player != null:
		if music_on:
			_music_player.play()
		else:
			_music_player.stop()
	_save_prefs()

# --- save data --------------------------------------------------------------
# Best score and settings, in a plain ConfigFile under user://.
const SAVE_PATH := "user://punchmyboss.cfg"

func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = int(cfg.get_value("score", "best", 0))
	unlocked = maxi(1, int(cfg.get_value("score", "unlocked", 1)))
	stat_punches = int(cfg.get_value("stats", "punches", 0))
	stat_damage = int(cfg.get_value("stats", "damage", 0))
	stat_kos = int(cfg.get_value("stats", "kos", 0))
	stat_fired = int(cfg.get_value("stats", "fired", 0))
	stat_best_combo = int(cfg.get_value("stats", "best_combo", 0))
	haptics_on = bool(cfg.get_value("settings", "haptics", true))
	music_on = bool(cfg.get_value("settings", "music", true))
	difficulty = int(cfg.get_value("settings", "difficulty", Difficulty.BRAWLER))
	look_skin = int(cfg.get_value("look", "skin", 0))
	look_hair = int(cfg.get_value("look", "hair", 0))
	look_moustache = int(cfg.get_value("look", "moustache", 0))
	_own_skin = look_skin
	_own_hair = look_hair
	_own_moustache = look_moustache
	portrait = bool(cfg.get_value("settings", "portrait", false))

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.set_value("score", "unlocked", unlocked)
	cfg.set_value("stats", "punches", stat_punches)
	cfg.set_value("stats", "damage", stat_damage)
	cfg.set_value("stats", "kos", stat_kos)
	cfg.set_value("stats", "fired", stat_fired)
	cfg.set_value("stats", "best_combo", stat_best_combo)
	cfg.set_value("settings", "haptics", haptics_on)
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("look", "skin", _own_skin)
	cfg.set_value("look", "hair", _own_hair)
	cfg.set_value("look", "moustache", _own_moustache)
	cfg.set_value("settings", "portrait", portrait)
	cfg.save(SAVE_PATH)

# --- screens / game phases --------------------------------------------------
# TITLE -> PREFIGHT (boss talks) -> FIGHT -> GAMEOVER or VICTORY -> TITLE.
# Everything lives on one overlay Control that's shown/hidden; the fight loop
# and player input are gated on phase == FIGHT.

func _build_screens() -> void:
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.z_index = 90
	add_child(_screen)

	_screen_dim = ColorRect.new()
	_screen_dim.color = Color(0.05, 0.03, 0.08, 0.82)
	_screen_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_screen_dim)

	_screen_title = _big_label(120, Color(1, 0.86, 0.16), -0.03)
	_screen_title.offset_top = 220.0
	_screen_title.offset_bottom = 400.0
	_screen.add_child(_screen_title)

	_screen_sub = _big_label(46, Color(1, 1, 1), 0.0)
	_screen_sub.offset_top = 430.0
	_screen_sub.offset_bottom = 520.0
	_screen.add_child(_screen_sub)

	_screen_hint = _big_label(38, Color(0.85, 0.9, 1.0), 0.0)
	_screen_hint.offset_top = 700.0
	_screen_hint.offset_bottom = 780.0
	_screen.add_child(_screen_hint)

func _big_label(size: int, col: Color, rot: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	l.add_theme_constant_override("outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.rotation = rot
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _set_hud_visible(v: bool) -> void:
	for n in _hud_nodes:
		if n != null and is_instance_valid(n):
			n.visible = v
	# The combo counter has its own show/hide rule in _process.
	if _combo_label != null:
		_combo_label.visible = v and combo >= 2

func _show_title() -> void:
	phase = Phase.TITLE
	_set_hud_visible(false)
	boss_line.get_parent().visible = false
	_screen.visible = true
	_screen_title.text = "PUNCH\nMY BOSS"
	_screen_title.offset_top = 140.0
	_screen_title.offset_bottom = 420.0
	_screen_sub.text = "BEST  %d" % best_score
	if stat_punches > 0 or stat_damage > 0:
		_screen_sub.text += "
%d punches thrown   ·   %d damage   ·   %d K.O.s" % [
			stat_punches, stat_damage, stat_kos]
	_screen_hint.text = "tap to continue"
	if rig_anim != null:
		rig_anim.taunt()

func _pick_difficulty(d: int) -> void:
	if phase != Phase.TITLE:
		return
	difficulty = d
	_save_prefs()
	_show_title()

func _difficulty_name() -> String:
	match difficulty:
		Difficulty.BAG:
			return "1  PUNCHING BAG   (he never fights back)"
		Difficulty.DEFENSIVE:
			return "2  DEFENSIVE   (he guards, but won't swing)"
		_:
			return "3  BRAWLER   (he hits back - dodge!)"

# The pre-fight beat: he gets a line in before the bell.
func _start_prefight() -> void:
	close_menu()
	phase = Phase.PREFIGHT
	_set_hud_visible(false)
	boss_line.get_parent().visible = true      # he gets a line in first
	_screen.visible = true
	_screen_dim.color = Color(0.05, 0.03, 0.08, 0.45)
	var cfg := _level_cfg()
	_apply_opponent()
	_screen_title.text = "LEVEL %d" % level
	_screen_title.offset_top = 150.0
	_screen_title.offset_bottom = 300.0
	_screen_sub.text = "%s
%s" % [String(cfg.get("name", "")), opponent_name()]
	_screen_hint.text = "tap to begin"
	var pre: Array = Dia.PREFIGHT.get(level, [])
	if pre.is_empty():
		pre = [String(cfg.get("line", ""))]
	_say(_line("prefight%d" % level, pre))
	if rig_anim != null:
		rig_anim.point_at_player()

func _start_fight() -> void:
	close_menu()
	phase = Phase.FIGHT
	_set_hud_visible(true)
	boss_line.get_parent().visible = true
	_screen.visible = false
	_screen_dim.color = Color(0.05, 0.03, 0.08, 0.82)
	var cfg := _level_cfg()
	hp_max = float(cfg.get("hp", 120.0))
	_set_hp(hp_max)
	_set_player_hp(player_hp_max)
	_set_rage(0.0)
	combo = 0
	frenzy = 0.0
	_koing = false
	if rig_anim != null:
		rig_anim.revive()
	_start_gimmick()
	ko_banner.text = "FIGHT!"
	ko_banner.pivot_offset = ko_banner.size / 2.0
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(ko_banner, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_BACK)
	t.tween_interval(0.5)
	t.tween_property(ko_banner, "modulate:a", 0.0, 0.35)
	if _gimmick() in ["throw", "objects", "bridge", "car", "moon"]:
		set_pose("")
		_prompt.visible = false
		_say(String(_level_cfg().get("line", "")))
	else:
		if has_anim("charge"):
			# Hand-drawn charge intro (from the uploaded video). It plays once,
			# then the fight begins on the callback.
			play_anim("charge", 12.0, _enter_guard)
		elif has_pose("walk"):
			play_entrance()
			_enter_guard()
		else:
			_enter_guard()

func _show_gameover(won: bool) -> void:
	close_menu()
	phase = Phase.VICTORY if won else Phase.GAMEOVER
	best_score = maxi(best_score, score)
	_save_prefs()
	_set_hud_visible(false)
	boss_line.get_parent().visible = false
	_screen.visible = true
	_screen_title.text = "YOU WIN" if won else "YOU'RE FIRED"
	_screen_title.offset_top = 180.0
	_screen_title.offset_bottom = 340.0
	_screen_sub.text = "SCORE %d      BEST %d\nmax combo %d      crits %d" % [score, best_score, max_combo, crits]
	_screen_hint.text = "tap to continue" if won else "tap to try again"

# Any tap / key advances whichever screen is up.
func _advance_screen() -> void:
	match phase:
		Phase.TITLE:
			open_menu(Phase.MENU)
		Phase.PREFIGHT:
			_start_fight()
		Phase.VICTORY:
			level = mini(level + 1, LEVELS.size())
			unlocked = maxi(unlocked, level)
			_save_prefs()
			score = 0
			_score_shown = 0.0
			open_menu(Phase.MENU)
		Phase.GAMEOVER:
			score = 0
			_score_shown = 0.0
			open_menu(Phase.MENU)
		_:
			pass

# --- character look / customisation -----------------------------------------
# The generic-character architecture. The boss is ONE rigged body plus a look
# config: a skin tone applied through the outline shader's recolour path, and
# accessory sprites parented to the head bone. Adding a new character means a
# new LOOK entry (or a new art set slotted into the same rig), not a new rig.
#
# Accessory textures are authored on the same 460x500 canvas as the head, so
# they share the head's anchor offset exactly - no per-accessory alignment.
const SKIN_TONES := [
	Color(0.804, 0.620, 0.455),   # the art's own tone
	Color(0.949, 0.812, 0.694),
	Color(0.878, 0.694, 0.525),
	Color(0.639, 0.451, 0.318),
	Color(0.435, 0.290, 0.204),
	Color(0.278, 0.184, 0.133),
]
const HAIR_OPTS := ["", "hair_swoop", "hair_puff", "hair_toupee"]
const MOUSTACHE_OPTS := ["", "mustache", "mustache_handlebar"]

var look_skin: int = 0
var look_hair: int = 0
var look_moustache: int = 0

var _skin_sprites: Array = []     # pieces that carry visible skin
var _hair_spr: Sprite2D
var _moustache_spr: Sprite2D

func _build_look_layers(mat: Material) -> void:
	var hb = skel.get_node_or_null(NodePath("Hip/Spine/Chest/Head"))
	if hb == null:
		return
	for old in [_hair_spr, _moustache_spr]:
		if old != null and is_instance_valid(old):
			old.queue_free()
	# Accessories sit above the head sprite (HEAD_Z) so they read as worn.
	_hair_spr = _make_part(null, Vector2.ZERO, HEAD_ANCHOR, HEAD_Z + 1, hb, mat)
	_moustache_spr = _make_part(null, Vector2.ZERO, HEAD_ANCHOR, HEAD_Z + 2, hb, mat)
	_hair_spr.visible = false
	_moustache_spr.visible = false

# The player's own saved look, kept separate from whatever opponent is on
# screen so a roster fight never overwrites their customisation.
var _own_skin: int = 0
var _own_hair: int = 0
var _own_moustache: int = 0

func apply_look() -> void:
	_own_skin = look_skin
	_own_hair = look_hair
	_own_moustache = look_moustache
	_apply_look_no_save()
	_save_prefs()

func _apply_look_no_save() -> void:
	# Only the default character has separable skin and a normalised head sheet.
	# Tinting a character whose art bakes its own palette, or hanging the hair
	# and moustache layers on it, just paints slabs over the artwork.
	if not is_customisable():
		for s2 in _skin_sprites:
			if s2 != null and is_instance_valid(s2):
				var mm := s2.material as ShaderMaterial
				if mm != null:
					mm.set_shader_parameter("skin_enabled", false)
		if _hair_spr != null and is_instance_valid(_hair_spr):
			_hair_spr.visible = false
		if _moustache_spr != null and is_instance_valid(_moustache_spr):
			_moustache_spr.visible = false
		return
	# Skin: only the pieces that actually show skin get the recolour path
	# switched on, so the shirt and trousers can never be caught by it.
	var tone: Color = SKIN_TONES[posmod(look_skin, SKIN_TONES.size())]
	for s in _skin_sprites:
		if s == null or not is_instance_valid(s):
			continue
		var m := s.material as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("skin_enabled", look_skin != 0)
		m.set_shader_parameter("skin_base", Vector3(0.804, 0.620, 0.455))
		m.set_shader_parameter("skin_target", Vector3(tone.r, tone.g, tone.b))
	_set_accessory(_hair_spr, HAIR_OPTS[posmod(look_hair, HAIR_OPTS.size())])
	_set_accessory(_moustache_spr, MOUSTACHE_OPTS[posmod(look_moustache, MOUSTACHE_OPTS.size())])

func _set_accessory(spr: Sprite2D, name: String) -> void:
	if spr == null:
		return
	if name == "":
		spr.visible = false
		return
	var path := "res://assets/boss2/look/%s.png" % name
	if not ResourceLoader.exists(path):
		spr.visible = false
		return
	spr.texture = load(path)
	spr.visible = true

func cycle_look(what: String, dir: int = 1) -> void:
	match what:
		"skin":
			look_skin = posmod(look_skin + dir, SKIN_TONES.size())
		"hair":
			look_hair = posmod(look_hair + dir, HAIR_OPTS.size())
		"moustache":
			look_moustache = posmod(look_moustache + dir, MOUSTACHE_OPTS.size())
	apply_look()

# --- gimmick levels ---------------------------------------------------------
# Each level plugs in a mechanic by name. "punch" is the Punch-Out fight; the
# rest replace player input and the boss's behaviour while reusing the same
# rig, damage funnel, scoring and reactions. A new gimmick is a couple of
# functions here plus a LEVELS entry - it does not touch the fight code.
const PROPS := ["stapler", "mug", "keyboard", "plant"]

# THROW: grab the boss and fling him around the room. He bounces, and every
# impact costs him health.
var _grab: bool = false
var _grab_off: Vector2 = Vector2.ZERO
var _boss_vel: Vector2 = Vector2.ZERO
var _boss_at: Vector2 = Vector2.ZERO
var _last_mouse: Vector2 = Vector2.ZERO
var _spin: float = 0.0
const THROW_GRAV := 2600.0
const THROW_DAMP := 0.62

func _gimmick() -> String:
	return String(_level_cfg().get("gimmick", "punch"))

func _gimmick_uses_rig_body() -> bool:
	# Modes that drive rig.position themselves must take the body from BossRig.
	return _gimmick() in ["throw", "bridge", "moon"]

# Per-level backdrop. The moon shot needs sky, not a cubicle wall - without it
# the launch reads as "he jumped" rather than "he left the building".
var _office_tex: Texture2D
var _office_mat: Material
var _office_fit: int = 0

# Per-level backdrop, driven entirely by the LEVELS entry.
#
# Dropping in new scene art is CONTENT, not code: put the image under
# assets/scenes/ and add "bg" to the level. Two optional keys go with it:
#
#   "bg"      path to the image. Omit for the default office.
#   "bg_toon" run the posterise/ink shader over it. Defaults to TRUE for the
#             photographic office and FALSE for flat/painted art, because that
#             pass is tuned for photos and muddies flat colour.
#   "bg_fit"  stretch mode override, if a piece of art needs a different fit.
#
# A missing file falls back to the office with a warning rather than showing a
# blank screen, so a typo in a path can never black out the level.
func _apply_level_scene() -> void:
	if _office_tex == null:
		_office_tex = office.texture
		_office_mat = office.material
		_office_fit = office.stretch_mode
	var cfg := _level_cfg()
	var path := String(cfg.get("bg", ""))
	if path == "":
		office.texture = _office_tex
		office.material = _office_mat
		office.stretch_mode = _office_fit
		return
	if not ResourceLoader.exists(path):
		push_warning("level %d: background not found, using the office: %s" % [level, path])
		office.texture = _office_tex
		office.material = _office_mat
		office.stretch_mode = _office_fit
		return
	office.texture = load(path)
	office.material = _office_mat if bool(cfg.get("bg_toon", false)) else null
	office.stretch_mode = int(cfg.get("bg_fit", _office_fit))

func _start_gimmick() -> void:
	set_pose("")
	_apply_level_scene()
	_boss_at = Vector2.ZERO
	_boss_vel = Vector2.ZERO
	_spin = 0.0
	_grab = false
	_teeter = 0.0
	_teeter_vel = 0.0
	_fallen = false
	_moon_stage = 0
	_moon_flying = false
	_moon_sweep = 0.0
	_car_busy = false
	if rig_anim != null:
		rig_anim.own_body = not _gimmick_uses_rig_body()

# Called every frame while a gimmick level is running.
func _update_gimmick(delta: float) -> void:
	match _gimmick():
		"throw":
			_update_throw(delta)
		"bridge":
			_update_bridge(delta)
		"moon":
			_update_moon(delta)
		_:
			pass

func _update_throw(delta: float) -> void:
	if rig_anim == null:
		return
	if _grab:
		# Held: follow the pointer, and remember the motion for release velocity.
		var m := get_global_mouse_position()
		var target := m - _grab_off
		_boss_vel = (target - _boss_at) / maxf(delta, 0.0001)
		_boss_at = target
		_spin = lerpf(_spin, clampf(_boss_vel.x * 0.0006, -1.2, 1.2), 8.0 * delta)
	else:
		_boss_vel.y += THROW_GRAV * delta
		_boss_at += _boss_vel * delta
		_spin += _boss_vel.x * 0.00025
		# Bounce off floor, ceiling and side walls. The ceiling matters: with
		# only a floor he sailed clean out of the top of the frame and the
		# player lost sight of him for seconds at a time.
		var floor_y := 0.0
		var ceil_y := -430.0
		var wall := 470.0
		if _boss_at.y < ceil_y:
			_boss_at.y = ceil_y
			if absf(_boss_vel.y) > 240.0:
				_impact_throw(absf(_boss_vel.y))
			_boss_vel.y = -_boss_vel.y * THROW_DAMP
			_boss_vel.x *= 0.86
		if _boss_at.y > floor_y:
			_boss_at.y = floor_y
			if absf(_boss_vel.y) > 240.0:
				_impact_throw(absf(_boss_vel.y))
			_boss_vel.y = -_boss_vel.y * THROW_DAMP
			_boss_vel.x *= 0.80
		if absf(_boss_at.x) > wall:
			_boss_at.x = clampf(_boss_at.x, -wall, wall)
			if absf(_boss_vel.x) > 240.0:
				_impact_throw(absf(_boss_vel.x))
			_boss_vel.x = -_boss_vel.x * THROW_DAMP
		_spin = lerpf(_spin, 0.0, 1.4 * delta)
	rig.position = _boss_at
	rig.rotation = _spin

func _impact_throw(speed: float) -> void:
	var power := clampf(speed / 1400.0, 0.25, 1.6)
	var at: Vector2 = boss.get_global_transform() * (boss.size * 0.5)
	_punch_player.pitch_scale = randf_range(0.7, 1.0)
	_punch_player.play()
	_shake(10.0 + 16.0 * power, 0.22)
	_spawn_stars(at, int(4 + 8 * power))
	_spawn_text(at + Vector2(0, -140), POW_WORDS[randi() % POW_WORDS.size()],
		int(56 + 40 * power), Color(1, 0.86, 0.16))
	_react_tex = _react[randi() % _react.size()]
	_react_time = 0.35
	rig_anim.squash(power)
	if randf() < 0.4:
		_say_line("thrown", Dia.THROWN)
	_apply_damage(at, 4.0 + 9.0 * power, power > 1.0)
	if hp <= 0.0:
		_knockout()

# OBJECTS: hurl office supplies. Tap anywhere to throw the next prop at that
# point; it arcs in from the bottom of the screen and detonates on arrival.
func _throw_prop(at: Vector2) -> void:
	var name: String = PROPS[randi() % PROPS.size()]
	var path := "res://assets/boss2/props/%s.png" % name
	if not ResourceLoader.exists(path):
		return
	var s := Sprite2D.new()
	s.texture = load(path)
	s.z_index = 80
	var from := Vector2(randf_range(300.0, 1620.0), 1250.0)
	s.global_position = from
	s.scale = Vector2(1.6, 1.6)
	add_child(s)
	var spin := randf_range(-10.0, 10.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "global_position", at, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(s, "rotation", spin, 0.30)
	tw.tween_property(s, "scale", Vector2(0.9, 0.9), 0.30)
	await tw.finished
	s.queue_free()
	_prop_hit(at)

func _prop_hit(at: Vector2) -> void:
	var r := (boss as Control).get_global_rect().grow(10.0)
	if not r.has_point(at):
		_spawn_text(at, "miss", 34, Color(0.8, 0.82, 0.88))
		return
	var head_hit := _part_global_rect(head).grow(10.0).has_point(at)
	_punch_player.pitch_scale = randf_range(1.0, 1.3)
	_punch_player.play()
	_flash_screen(0.2)
	_shake(14.0, 0.26)
	_spawn_stars(at, 8)
	_spawn_text(at + Vector2(0, -90), POW_WORDS[randi() % POW_WORDS.size()], 72,
		Color(1, 0.86, 0.16))
	_react_tex = _react[randi() % _react.size()]
	_react_time = 0.4
	_react_hit(head_hit, at.x < r.position.x + r.size.x * 0.5, head_hit)
	if randf() < 0.35:
		_say_line("pelted", Dia.PELTED)
	_apply_damage(at, 7.0 if head_hit else 5.0, head_hit)
	if hp <= 0.0:
		_knockout()

# --- gimmick: bridge push ----------------------------------------------------
# He teeters on the edge. Shove him with taps; he fights back toward balance.
# Tip him past the point of no return and he goes over.
var _teeter: float = 0.0        # -1 .. 1, past |1| he falls
var _teeter_vel: float = 0.0
var _fallen: bool = false

func _update_bridge(delta: float) -> void:
	if _fallen:
		return
	# He constantly claws back toward upright - that's the tension.
	_teeter_vel -= _teeter * 2.2 * delta
	_teeter_vel *= 0.985
	_teeter += _teeter_vel * delta
	if absf(_teeter) >= 1.0:
		_fallen = true
		_bridge_fall()
		return
	rig_anim.lean = _teeter * 0.55
	rig.position = Vector2(_teeter * 260.0, absf(_teeter) * 40.0)
	_prompt.visible = absf(_teeter) > 0.55

func _bridge_push(pos: Vector2) -> void:
	var r := (boss as Control).get_global_rect().grow(80.0)
	if not r.has_point(pos):
		return
	var from_left := pos.x < r.position.x + r.size.x * 0.5
	_teeter_vel += (1.55 if from_left else -1.55)
	_punch_player.pitch_scale = clampf(1.0 + absf(_teeter) * 0.6, 0.9, 1.9)
	_punch_player.play()
	_shake(8.0, 0.16)
	rig_anim.stagger(from_left, 0.6)
	_spawn_text(_text_anchor(from_left), "SHOVE!", 64, Color(1, 0.86, 0.16))
	_apply_damage(r.position + r.size * 0.5, 3.0, false)
	if randf() < 0.4:
		_say_line("bridge", Dia.BRIDGE)

func _bridge_fall() -> void:
	_say(_line("bridge", Dia.BRIDGE))
	rig_anim.own_body = false
	rig_anim.idle_enabled = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "position", Vector2(_teeter * 340.0, 2200.0), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(rig, "rotation", signf(_teeter) * 4.0, 1.0)
	_shake(20.0, 0.5)
	_set_hp(0.0)
	await tw.finished
	_knockout()

# --- gimmick: car ------------------------------------------------------------
# Drive at him. Tap to accelerate the car in from the side; time it so he's in
# the road rather than mid-dodge.
var _car: Sprite2D
var _car_busy: bool = false

func _car_run(_pos: Vector2) -> void:
	if _car_busy:
		return
	_car_busy = true
	if _car == null:
		_car = Sprite2D.new()
		_car.texture = load("res://assets/boss2/scenes/car.png")
		_car.z_index = 85
		add_child(_car)
	var from_left := randf() < 0.5
	# The art faces right, so mirror when it comes in from the other side.
	_car.scale = Vector2(1.9 if from_left else -1.9, 1.9)
	_car.position = Vector2(-400.0 if from_left else 2320.0, 940.0)
	_car.visible = true
	var tw := create_tween()
	tw.tween_property(_car, "position:x", 2320.0 if from_left else -400.0, 0.85) \
		.set_trans(Tween.TRANS_QUAD)
	# Impact when it reaches him.
	var hit := create_tween()
	hit.tween_interval(0.36)
	hit.tween_callback(func() -> void:
		var r := (boss as Control).get_global_rect()
		var at := r.position + r.size * 0.5
		_flash_screen(0.4)
		_shake(28.0, 0.4)
		_hitstop(0.06)
		_spawn_stars(at, 12)
		_spawn_text(at + Vector2(0, -180), "HONK!", 96, Color(1, 0.3, 0.25))
		rig_anim.spin_body(2)
		rig_anim.squash(1.3)
		_say_line("car", Dia.CAR)
		_apply_damage(at, 16.0, true)
		if hp <= 0.0:
			_knockout())
	await tw.finished
	_car.visible = false
	_car_busy = false

# --- gimmick: moon -----------------------------------------------------------
# A launch-angle / power minigame. A meter sweeps; tap to lock angle, tap again
# to lock power, and he flies. Farther is better.
var _moon_stage: int = 0        # 0 idle, 1 picking angle, 2 picking power
var _moon_angle: float = 0.0
var _moon_power: float = 0.0
var _moon_sweep: float = 0.0
var _moon_flying: bool = false
var _moon_best: float = 0.0

func _update_moon(delta: float) -> void:
	if _moon_flying:
		_boss_vel.y += 900.0 * delta
		_boss_at += _boss_vel * delta
		_spin += 5.0 * delta
		rig.position = _boss_at
		rig.rotation = _spin
		if _boss_at.y > 400.0 or _boss_at.x > 2600.0:
			_moon_land()
		return
	_moon_sweep += delta * 2.4
	match _moon_stage:
		0:
			_moon_stage = 1
		1:
			_moon_angle = 0.5 + 0.5 * sin(_moon_sweep * 1.6)      # 0..1
			rig_anim.lean = -_moon_angle * 0.5
		2:
			_moon_power = 0.5 + 0.5 * sin(_moon_sweep * 3.2)
			rig_anim.body_scale = Vector2(_moon_power * 0.12, -_moon_power * 0.12)
	_prompt.visible = true
	_prompt.text = "TAP: ANGLE" if _moon_stage == 1 else "TAP: POWER"

func _moon_tap() -> void:
	if _moon_flying:
		return
	if _moon_stage == 1:
		_moon_stage = 2
		_moon_sweep = 0.0
	elif _moon_stage == 2:
		_moon_launch()

func _moon_launch() -> void:
	_moon_flying = true
	_prompt.visible = false
	rig_anim.own_body = false
	rig_anim.idle_enabled = false
	var ang := lerpf(-1.35, -0.35, _moon_angle)       # radians, up and to the right
	var spd := lerpf(900.0, 2600.0, _moon_power)
	_boss_at = Vector2.ZERO
	_boss_vel = Vector2(cos(ang), sin(ang)) * spd
	_ko_player.play()
	_flash_screen(0.5)
	_shake(26.0, 0.4)
	_say_line("moon", Dia.MOON, true)
	_spawn_text(Vector2(960.0, 340.0), "LAUNCH!", 120, Color(1, 0.86, 0.16))

func _moon_land() -> void:
	_moon_flying = false
	var dist := maxf(0.0, _boss_at.x) / 100.0
	_moon_best = maxf(_moon_best, dist)
	_add_score(int(dist * 40.0), Vector2(960.0, 420.0))
	_spawn_text(Vector2(960.0, 300.0), "%.0f m" % dist, 110, Color(1, 0.86, 0.16))
	_apply_damage(Vector2(960.0, 420.0), 22.0 + dist * 0.6, true)
	if hp <= 0.0:
		_knockout()
		return
	# Reset for another shot.
	_boss_at = Vector2.ZERO
	_boss_vel = Vector2.ZERO
	_spin = 0.0
	rig.position = Vector2.ZERO
	rig.rotation = 0.0
	rig_anim.own_body = false
	rig_anim.idle_enabled = true
	_moon_stage = 1
	_moon_sweep = 0.0

# --- portrait layout scaffolding --------------------------------------------
# Behind a flag on purpose: the orientation decision is the user's, so this
# makes it a toggle rather than a rework. Enable with `--portrait` or by
# setting `portrait` in the save file.
#
# Landscape suits the Punch-Out framing; portrait suits one-handed commute
# play, which is when someone actually wants to punch their boss. Nothing here
# changes the default until that call is made.
#
# What it does: swaps the viewport to 1080x1920, re-anchors the HUD rows,
# moves the face buttons to a bottom thumb arc, and re-centres the boss.
var portrait: bool = false        # saved preference
var _force_portrait: bool = false # --portrait, this session only

func is_portrait() -> bool:
	return portrait or _force_portrait

func _apply_portrait() -> void:
	if not is_portrait():
		return
	var vp := get_window()
	vp.content_scale_size = Vector2i(1080, 1920)
	vp.size = Vector2i(540, 960)

	# Health rows span the narrower width.
	for n in [$Safe/RageTrack, $Safe/KoTrack]:
		(n as Control).offset_left = 96.0
		(n as Control).offset_right = -12.0
	if _player_bar != null and _player_bar.get_parent() is Control:
		var pt := _player_bar.get_parent() as Control
		pt.offset_left = 96.0
		pt.offset_right = -12.0

	# Dialogue bubble gets taller (text wraps more in a narrow column).
	var bubble := $Safe/Bubble as Control
	bubble.offset_bottom = 420.0

	# Boss re-centred for a 1080-wide frame, standing lower.
	boss.offset_left = 280.0
	boss.offset_right = 800.0
	boss.offset_top = 700.0
	boss.offset_bottom = 1940.0
	boss.scale = Vector2(0.62, 0.62)

	# Face buttons into a thumb arc near the bottom.
	var cx := 540.0
	var cy := 1620.0
	var rr := 150.0
	var places := {"Y": Vector2(cx, cy - rr), "A": Vector2(cx, cy + rr),
		"X": Vector2(cx - rr, cy), "B": Vector2(cx + rr, cy)}
	for k in places.keys():
		if _buttons.has(k):
			var b: Button = _buttons[k]
			b.position = places[k] - b.size / 2.0

	# Combo counter above the buttons rather than off to the side.
	if _combo_label != null:
		_combo_label.anchor_left = 0.0
		_combo_label.anchor_right = 1.0
		_combo_label.offset_left = 40.0
		_combo_label.offset_right = -40.0
		_combo_label.offset_top = 1180.0
		_combo_label.offset_bottom = 1400.0
	_apply_safe_area()

# --- multi-character rig ----------------------------------------------------
# One skeleton, many characters. Each entry supplies its own slice table, bone
# rest pose and art scale, so bodies with completely different proportions ride
# the same bones and the same animation library. Adding a character is data.
#
# `expressions` lists which head textures exist. Characters without a set fall
# back to head-bone motion for reactions instead of swapping faces.
const CHARS := {
	"suit": {
		"dir": "res://assets/boss2/parts",
		"scale": 1.23431, "ox": 41.55, "oy": 60.0,
		"head_canvas": true,          # normalised head sheet, swappable faces
		"customisable": true,
		"faces": {"dir": "res://assets/boss2/heads", "anchor": Vector2(230, 470),
			"react": ["hurt0", "hurt1", "hurt2", "dizzy0", "dizzy1", "dizzy2", "dizzy3"],
			"angry": []},
		"bones": {},                  # uses the rest pose authored in main.tscn
		"parts": [],                  # uses _PARTS
	},
	"big": {
		"dir": "res://assets/boss3/parts",
		"scale": 1.24211, "ox": -161.69, "oy": 60.0,
		"head_canvas": true,          # now has a harvested expression sheet
		"customisable": false,        # his art bakes its own palette
		"arm_gain": 0.5,              # short arms on a wide body: damp the swing
		# Canvas pixels equal his base pixels 1:1 (skull normalised to 309, the
		# width of his sliced rig head), so the bone anchor is a clean 260,400.
		"faces": {"dir": "res://assets/boss3/heads", "anchor": Vector2(260, 400),
			"react": ["hurt0", "hurt1", "hurt2", "hurt3", "shock", "worried"],
			"angry": ["angry0", "angry1", "angry2", "angry3"]},
		"bones": {
			"Hip": Vector2(261, 830),
			"Spine": Vector2(0, -236),
			"Chest": Vector2(0, -112),
			"Head": Vector2(0, -112),
			"ArmL": Vector2(-338, -323),
			"ForearmL": Vector2(-12, 168),
			"FistL": Vector2(-2, 145),
			"ArmR": Vector2(338, -323),
			"ForearmR": Vector2(10, 168),
			"FistR": Vector2(2, 145),
			"ThighL": Vector2(-124, 124),
			"ShinL": Vector2(2, 137),
			"FootL": Vector2(-15, 75),
			"ThighR": Vector2(122, 124),
			"ShinR": Vector2(-1, 137),
			"FootR": Vector2(14, 75),
		},
		"parts": [
			["foot_l",  "Hip/ThighL/ShinL/FootL", Vector2(134, 862), Vector2(230, 890), 0],
			["foot_r",  "Hip/ThighR/ShinR/FootR", Vector2(369, 862), Vector2(448, 890), 0],
			["shin_l",  "Hip/ThighL/ShinL", Vector2(174, 804), Vector2(242, 830), 1],
			["shin_r",  "Hip/ThighR/ShinR", Vector2(367, 804), Vector2(437, 830), 1],
			["thigh_l", "Hip/ThighL", Vector2(136, 688), Vector2(240, 720), 2],
			["thigh_r", "Hip/ThighR", Vector2(336, 688), Vector2(438, 720), 2],
			["hips",    "Hip", Vector2(96, 564), Vector2(340, 620), 3],
			["torso",   "Hip/Spine", Vector2(0, 228), Vector2(340, 430), 4],
			["uarm_l",  "Hip/ArmL", Vector2(1, 355), Vector2(68, 360), 5],
			["uarm_r",  "Hip/ArmR", Vector2(530, 355), Vector2(612, 360), 5],
			["farm_l",  "Hip/ArmL/ForearmL", Vector2(0, 468), Vector2(58, 495), 6],
			["farm_r",  "Hip/ArmR/ForearmR", Vector2(559, 468), Vector2(620, 495), 6],
			["hand_l",  "Hip/ArmL/ForearmL/FistL", Vector2(10, 588), Vector2(56, 612), 7],
			["hand_r",  "Hip/ArmR/ForearmR/FistR", Vector2(571, 588), Vector2(622, 612), 7],
		],
	},
}

var character: String = "suit"
var _outline_mat: Material
var _char_sprites: Array = []

# The rest pose authored in main.tscn, captured once at startup so switching
# back to the default character restores it exactly.
const BONE_PATHS := ["Hip", "Hip/Spine", "Hip/Spine/Chest", "Hip/Spine/Chest/Head",
	"Hip/ArmL", "Hip/ArmL/ForearmL", "Hip/ArmL/ForearmL/FistL",
	"Hip/ArmR", "Hip/ArmR/ForearmR", "Hip/ArmR/ForearmR/FistR",
	"Hip/ThighL", "Hip/ThighL/ShinL", "Hip/ThighL/ShinL/FootL",
	"Hip/ThighR", "Hip/ThighR/ShinR", "Hip/ThighR/ShinR/FootR"]
var _BONE_HOME: Dictionary = {}

func _capture_bone_home() -> void:
	if not _BONE_HOME.is_empty() or skel == null:
		return
	for path in BONE_PATHS:
		var b := skel.get_node_or_null(NodePath(path)) as Bone2D
		if b != null:
			_BONE_HOME[path] = b.position

func has_expressions() -> bool:
	return not CHARS[character].get("faces", {}).is_empty()

func is_customisable() -> bool:
	return bool(CHARS[character].get("customisable", false))

# Load this character's face set. Both characters now use a normalised head
# canvas; only the anchor and the roster of expressions differ.
var _angry_faces: Array = []

func _load_faces() -> void:
	var f: Dictionary = CHARS[character].get("faces", {})
	_react.clear()
	_angry_faces.clear()
	if f.is_empty():
		return
	var dir := String(f["dir"])
	_tex_neutral = load("%s/neutral.png" % dir)
	var talk_path := "%s/talk.png" % dir
	_tex_talk = load(talk_path) if ResourceLoader.exists(talk_path) else _tex_neutral
	for n in f.get("react", []):
		var p2 := "%s/%s.png" % [dir, n]
		if ResourceLoader.exists(p2):
			_react.append(load(p2))
	for n in f.get("angry", []):
		var p3 := "%s/%s.png" % [dir, n]
		if ResourceLoader.exists(p3):
			_angry_faces.append(load(p3))
	if _react.is_empty():
		_react.append(_tex_neutral)
	_react_tex = _react[0]

# Swap the whole figure: bone rest pose, then the sliced pieces.
func set_character(key: String, mat: Material) -> void:
	if not CHARS.has(key):
		return
	character = key
	var cfg: Dictionary = CHARS[key]
	# Bone rest pose. "suit" restores whatever main.tscn authored.
	var bones: Dictionary = cfg.get("bones", {})
	for path in _BONE_HOME.keys():
		var b := skel.get_node_or_null(NodePath(path)) as Bone2D
		if b == null:
			continue
		# CHARS keys bones by short name ("ArmL"); _BONE_HOME by full path
		# ("Hip/ArmL"). Looking up the full path in CHARS silently missed every
		# entry, so the new character wore the default character's skeleton.
		var leaf := String(path).get_slice("/", String(path).get_slice_count("/") - 1)
		var pos: Vector2 = bones.get(leaf, _BONE_HOME[path])
		b.position = pos
		b.rest = Transform2D(0.0, pos)
	# Rebuild the art.
	for s in _char_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_char_sprites.clear()
	_skin_sprites.clear()
	head = null
	torso_spr = null
	_load_faces()
	if String(cfg.get("dir", "")) == "res://assets/boss2/parts":
		_build_parts_suit(mat)
	else:
		_build_parts_from(cfg, mat)
		_build_canvas_head(cfg, mat)
	_build_look_layers(mat)
	_apply_look_no_save()
	if rig_anim != null:
		rig_anim.setup(skel, rig, head)
		rig_anim.arm_gain = float(cfg.get("arm_gain", 1.0))

# Head from the normalised expression canvas, anchored so face swaps can't jump.
func _build_canvas_head(cfg: Dictionary, mat: Material) -> void:
	var hb := skel.get_node_or_null(NodePath("Hip/Spine/Chest/Head"))
	if hb == null or _tex_neutral == null:
		return
	var sc := float(cfg["scale"])
	var anchor: Vector2 = cfg["faces"].get("anchor", Vector2.ZERO)
	var s := Sprite2D.new()
	s.texture = _tex_neutral
	s.centered = false
	s.scale = Vector2(sc, sc)
	s.position = -anchor * sc
	s.z_index = 8
	s.material = mat.duplicate()
	hb.add_child(s)
	head = s
	_char_sprites.append(s)

func _build_parts_from(cfg: Dictionary, mat: Material) -> void:
	var sc := float(cfg["scale"])
	var dir := String(cfg["dir"])
	for e in cfg["parts"]:
		var bone := skel.get_node_or_null(NodePath(e[1]))
		if bone == null:
			continue
		var path := "%s/%s.png" % [dir, e[0]]
		if not ResourceLoader.exists(path):
			push_warning("character art missing: %s" % path)
			continue
		var s := Sprite2D.new()
		s.texture = load(path)
		s.centered = false
		s.scale = Vector2(sc, sc)
		s.position = (Vector2(e[2]) - Vector2(e[3])) * sc
		s.z_index = int(e[4])
		s.material = mat.duplicate()
		bone.add_child(s)
		_char_sprites.append(s)
		if e[0] == "torso":
			torso_spr = s
		elif e[0] == "head":
			head = s
			_skin_sprites.append(s)
		elif e[0] in ["uarm_l", "uarm_r", "farm_l", "farm_r", "hand_l", "hand_r"]:
			_skin_sprites.append(s)

# --- full-body pose frames --------------------------------------------------
# Hybrid rig: the cutout skeleton stays the base (it carries idle life,
# reactions and attacks), and hand-drawn full-body poses take over for discrete
# HELD moments where a drawn pose reads better than a procedural one — the
# guard stance, a "stop" gesture, the walk-in.
#
# The pose sprite is a child of `rig`, so screen shake, hitstop, the wind-up
# lean and the K.O. tumble all still apply to it. Breathing is layered on top
# so a held pose never looks frozen.
var _pose_spr: Sprite2D
var _pose_name: String = ""
var _pose_t: float = 0.0

func _pose_dir() -> String:
	return "res://assets/%s/poses" % ("boss3" if character == "big" else "boss2")

func has_pose(name: String) -> bool:
	return ResourceLoader.exists("%s/%s.png" % [_pose_dir(), name])

func set_pose(name: String) -> void:
	if name == _pose_name:
		return
	if name != "" and not has_pose(name):
		return                      # character has no art for this pose
	_pose_name = name
	if name == "":
		if _pose_spr != null:
			_pose_spr.visible = false
		_set_rig_visible(true)
		return
	if _pose_spr == null:
		_pose_spr = Sprite2D.new()
		_pose_spr.centered = false
		_pose_spr.z_index = 20
		_pose_spr.material = _outline_mat
		rig.add_child(_pose_spr)
	var tex: Texture2D = load("%s/%s.png" % [_pose_dir(), name])
	_pose_spr.texture = tex
	# Every pose is drawn at the same figure scale, so one scale keeps him
	# consistent; bottom-centre alignment puts his feet on the same floor line
	# whatever the pose's bounding box does (the raised arm in "palm" makes that
	# box taller without making him taller).
	var sc := float(CHARS[character].get("scale", 1.0))
	_pose_spr.scale = Vector2(sc, sc)
	var w := tex.get_width() * sc
	var h := tex.get_height() * sc
	_pose_spr.position = Vector2(260.0 - w * 0.5, 1240.0 - h)
	_pose_spr.visible = true
	_pose_t = 0.0
	_set_rig_visible(false)

func _set_rig_visible(v: bool) -> void:
	for s in _char_sprites:
		if s != null and is_instance_valid(s):
			s.visible = v
	if _hair_spr != null and is_instance_valid(_hair_spr):
		_hair_spr.visible = v and is_customisable() and look_hair != 0
	if _moustache_spr != null and is_instance_valid(_moustache_spr):
		_moustache_spr.visible = v and is_customisable() and look_moustache != 0

# Keep a held pose breathing so it doesn't read as a freeze-frame.
func _update_pose(delta: float) -> void:
	if _pose_spr == null or not _pose_spr.visible:
		return
	_pose_t += delta
	var sc := float(CHARS[character].get("scale", 1.0))
	var breath := sin(_pose_t * 1.9) * 0.006
	var sway := sin(_pose_t * 0.72) * 0.004
	_pose_spr.scale = Vector2(sc * (1.0 + sway), sc * (1.0 + breath))

# Walk him in at the start of a fight, then hand back to the rig.
func play_entrance() -> void:
	if not has_pose("walk"):
		return
	set_pose("walk")
	var from := Vector2(760.0, 0.0)
	rig.position = from
	var tw := create_tween()
	tw.tween_property(rig, "position", Vector2.ZERO, 1.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	set_pose("guard" if has_pose("guard") else "")

# --- menu system ------------------------------------------------------------
# Touch-first: every row is a full-width button with a large tap target, since
# Android is the target and thumbs are imprecise. The title screen is the front
# door; everything else hangs off the main menu.
const MENU_ROW_H := 108.0
const MENU_W := 1120.0
# Customise two-column layout: left options column width, and how far the boss
# preview shifts right (into the clear half) so the option rows never cover him.
const MENU_COL_W := 940.0
const BOSS_PREVIEW_SHIFT := 360.0
var _boss_home: Vector2 = Vector2.ZERO   # authored Boss position, captured once

var _menu: Control
var _menu_dim: ColorRect
var _menu_title: Label
var _menu_rows: VBoxContainer
var _menu_back: Button
var unlocked: int = 1          # highest level reached, persisted

func _build_menu_ui() -> void:
	_boss_home = boss.position
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.z_index = 95
	_menu.visible = false
	add_child(_menu)

	_menu_dim = ColorRect.new()
	_menu_dim.color = Color(0.05, 0.03, 0.08, 0.86)
	_menu_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_menu_dim)

	_menu_title = _big_label(88, Color(1, 0.86, 0.16), -0.02)
	_menu_title.offset_top = 70.0
	_menu_title.offset_bottom = 190.0
	_menu.add_child(_menu_title)

	_menu_rows = VBoxContainer.new()
	_menu_rows.add_theme_constant_override("separation", 16)
	_menu_rows.anchor_left = 0.5
	_menu_rows.anchor_right = 0.5
	_menu_rows.offset_left = -MENU_W * 0.5
	_menu_rows.offset_right = MENU_W * 0.5
	_menu_rows.offset_top = 215.0
	_menu.add_child(_menu_rows)

	_menu_back = _menu_button("< BACK", Color(0.35, 0.33, 0.42))
	_menu_back.anchor_top = 1.0
	_menu_back.anchor_bottom = 1.0
	_menu_back.anchor_left = 0.5
	_menu_back.anchor_right = 0.5
	_menu_back.offset_left = -260.0
	_menu_back.offset_right = 260.0
	_menu_back.offset_top = -152.0
	_menu_back.offset_bottom = -152.0 + MENU_ROW_H
	_menu_back.pressed.connect(_menu_back_pressed)
	_menu.add_child(_menu_back)

func _menu_button(text: String, col: Color = Color(0.20, 0.45, 0.85)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, MENU_ROW_H)
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.66, 0.64, 0.72))
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(5)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	b.add_theme_stylebox_override("normal", sb)
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = col.lightened(0.14)
	b.add_theme_stylebox_override("hover", hv)
	var pr: StyleBoxFlat = sb.duplicate()
	pr.bg_color = col.darkened(0.22)
	b.add_theme_stylebox_override("pressed", pr)
	var ds: StyleBoxFlat = sb.duplicate()
	ds.bg_color = Color(0.17, 0.16, 0.21)
	ds.border_color = Color(1, 1, 1, 0.22)
	b.add_theme_stylebox_override("disabled", ds)
	return b

func _clear_rows() -> void:
	for c in _menu_rows.get_children():
		_menu_rows.remove_child(c)
		c.queue_free()

func open_menu(kind: int) -> void:
	phase = kind
	_set_hud_visible(false)
	boss_line.get_parent().visible = false
	_screen.visible = false
	_menu.visible = true
	_clear_rows()
	_menu_rows.add_theme_constant_override("separation", 16)
	_menu_rows.offset_top = 215.0
	# Customise is a two-column layout: options on the LEFT, the live character
	# preview on the RIGHT. Every other screen centres its rows over the (dimmed)
	# boss. The bug this fixes: centred option rows sat right on top of his head
	# - exactly the part hair/moustache/skin change - so you couldn't see the
	# edits you were making.
	if kind == Phase.CUSTOMIZE:
		_menu_rows.anchor_left = 0.0
		_menu_rows.anchor_right = 0.0
		_menu_rows.offset_left = 60.0
		_menu_rows.offset_right = 60.0 + MENU_COL_W
		_menu_rows.offset_top = 250.0
		# Offset from the AUTHORED position, not absolute: boss.position is not
		# additive, so setting it to (shift,0) earlier overwrote his ~817 base
		# offset and slid him left instead of right, straight under the title.
		boss.position = _boss_home + Vector2(BOSS_PREVIEW_SHIFT, 0.0)
	else:
		_menu_rows.anchor_left = 0.5
		_menu_rows.anchor_right = 0.5
		_menu_rows.offset_left = -MENU_W * 0.5
		_menu_rows.offset_right = MENU_W * 0.5
		boss.position = _boss_home
	# Customise wants the boss visible beside it; the rest dim him right out.
	var a := 0.42 if kind == Phase.CUSTOMIZE else 0.86
	_menu_dim.color = Color(0.05, 0.03, 0.08, a)
	_menu_back.visible = kind != Phase.MENU
	match kind:
		Phase.MENU:
			_populate_main()
		Phase.LEVELS:
			_populate_levels()
		Phase.CUSTOMIZE:
			_populate_customize()
		Phase.OPTIONS:
			_populate_options()

func close_menu() -> void:
	_menu.visible = false
	# Undo the customise-screen preview shift so a fight never starts off-centre.
	boss.position = _boss_home

func _menu_back_pressed() -> void:
	if phase != Phase.MENU:
		open_menu(Phase.MENU)

func _populate_main() -> void:
	_menu_title.text = "PUNCH MY BOSS"
	var play := _menu_button("PLAY   -   LEVEL %d" % level, Color(0.20, 0.70, 0.25))
	play.pressed.connect(_on_play)
	_menu_rows.add_child(play)
	var lv := _menu_button("LEVEL SELECT")
	lv.pressed.connect(func() -> void: open_menu(Phase.LEVELS))
	_menu_rows.add_child(lv)
	var cu := _menu_button("CUSTOMISE YOUR BOSS", Color(0.62, 0.28, 0.72))
	cu.pressed.connect(func() -> void: open_menu(Phase.CUSTOMIZE))
	_menu_rows.add_child(cu)
	var op := _menu_button("OPTIONS", Color(0.35, 0.33, 0.42))
	op.pressed.connect(func() -> void: open_menu(Phase.OPTIONS))
	_menu_rows.add_child(op)
	var st := Label.new()
	st.text = "BEST %d      %d punches thrown      %d K.O.s" % [best_score, stat_punches, stat_kos]
	st.add_theme_font_size_override("font_size", 32)
	st.add_theme_color_override("font_color", Color(0.82, 0.85, 0.95))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.custom_minimum_size = Vector2(0, 96)
	_menu_rows.add_child(st)

func _on_play() -> void:
	close_menu()
	_start_prefight()

func _populate_levels() -> void:
	_menu_title.text = "LEVEL SELECT"
	_menu_rows.add_theme_constant_override("separation", 10)
	_menu_rows.offset_top = 200.0
	for i in LEVELS.size():
		var n := i + 1
		var cfg: Dictionary = LEVELS[i]
		var who := "Your Boss"
		var r: Dictionary = ROSTER.get(n, {})
		if not r.is_empty():
			who = String(r.get("who", who))
		var locked := n > unlocked
		var label := "%d.  %s  -  %s" % [n, String(cfg.get("name", "")), who]
		if locked:
			label = "%d.   L O C K E D" % n
		var col := Color(0.20, 0.45, 0.85)
		if locked:
			col = Color(0.17, 0.16, 0.21)
		elif n == level:
			col = Color(0.20, 0.70, 0.25)
		var b := _menu_button(label, col)
		b.add_theme_font_size_override("font_size", 30)
		# 9 rows at the default height overflowed the screen: rows 8-9 fell off
		# the bottom and BACK sat on top of row 7.
		b.custom_minimum_size = Vector2(0, 70)
		b.disabled = locked
		if not locked:
			b.pressed.connect(_on_pick_level.bind(n))
		_menu_rows.add_child(b)

func _on_pick_level(n: int) -> void:
	level = n
	close_menu()
	_start_prefight()

func _populate_customize() -> void:
	_menu_title.text = "CUSTOMISE"
	if not is_customisable():
		var note := _menu_button("This opponent uses their own artwork.", Color(0.24, 0.22, 0.30))
		note.add_theme_font_size_override("font_size", 34)
		note.disabled = true
		_menu_rows.add_child(note)
		return
	_add_cycle_row("SKIN", "skin")
	_add_cycle_row("HAIR", "hair")
	_add_cycle_row("MOUSTACHE", "moustache")

func _look_value(what: String) -> String:
	match what:
		"skin":
			return "%d of %d" % [look_skin + 1, SKIN_TONES.size()]
		"hair":
			return _opt_name(HAIR_OPTS[posmod(look_hair, HAIR_OPTS.size())])
		_:
			return _opt_name(MOUSTACHE_OPTS[posmod(look_moustache, MOUSTACHE_OPTS.size())])

func _opt_name(s: String) -> String:
	if s == "":
		return "NONE"
	return s.replace("hair_", "").replace("mustache_", "").replace("mustache", "PLAIN").to_upper()

func _add_cycle_row(title: String, what: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, MENU_ROW_H)
	var lbl := _menu_button("%s:  %s" % [title, _look_value(what)], Color(0.24, 0.22, 0.30))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.disabled = true
	row.add_child(lbl)
	var nxt := _menu_button("NEXT", Color(0.62, 0.28, 0.72))
	nxt.custom_minimum_size = Vector2(300, MENU_ROW_H)
	nxt.pressed.connect(_on_cycle.bind(what, title, lbl))
	row.add_child(nxt)
	_menu_rows.add_child(row)

func _on_cycle(what: String, title: String, lbl: Button) -> void:
	cycle_look(what)
	if is_instance_valid(lbl):
		lbl.text = "%s:  %s" % [title, _look_value(what)]

func _populate_options() -> void:
	_menu_title.text = "OPTIONS"
	var mus := _menu_button("MUSIC:  %s" % ("ON" if music_on else "OFF"),
		Color(0.20, 0.70, 0.25) if music_on else Color(0.35, 0.33, 0.42))
	mus.pressed.connect(_on_toggle_music)
	_menu_rows.add_child(mus)

	var hap := _menu_button("VIBRATION:  %s" % ("ON" if haptics_on else "OFF"),
		Color(0.20, 0.70, 0.25) if haptics_on else Color(0.35, 0.33, 0.42))
	hap.pressed.connect(_on_toggle_haptics)
	_menu_rows.add_child(hap)

	var names := ["PUNCHING BAG", "DEFENSIVE", "BRAWLER"]
	var dif := _menu_button("DIFFICULTY:  %s" % names[clampi(difficulty, 0, 2)])
	dif.pressed.connect(_on_cycle_difficulty)
	_menu_rows.add_child(dif)

	var hint := Label.new()
	hint.text = "Punching Bag - he never fights back.\nDefensive - he guards, but won't swing.\nBrawler - he hits back, so dodge."
	hint.add_theme_font_size_override("font_size", 30)
	hint.add_theme_color_override("font_color", Color(0.82, 0.85, 0.95))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, 160)
	_menu_rows.add_child(hint)

func _on_toggle_music() -> void:
	toggle_music()
	open_menu(Phase.OPTIONS)

func _on_toggle_haptics() -> void:
	haptics_on = not haptics_on
	_save_prefs()
	open_menu(Phase.OPTIONS)

func _on_cycle_difficulty() -> void:
	difficulty = (difficulty + 1) % 3
	_save_prefs()
	open_menu(Phase.OPTIONS)

# --- hand-drawn frame animation ---------------------------------------------
# Plays a keyed frame sequence (e.g. the charge extracted from the uploaded
# video) on the same overlay sprite the poses use. One-shot: it runs once, then
# hands back to the rig via an optional callback. Frames share a union bbox so
# the character doesn't jitter between them.
var _anim_frames: Array = []
var _anim_i: int = 0
var _anim_t: float = 0.0
var _anim_fps: float = 8.0
var _anim_playing: bool = false
var _anim_done: Callable

func _anim_dir(name: String) -> String:
	return "res://assets/%s/anim/%s" % ["boss3" if character == "big" else "boss2", name]

func has_anim(name: String) -> bool:
	return ResourceLoader.exists("%s/f000.png" % _anim_dir(name))

func play_anim(name: String, fps: float, done: Callable = Callable()) -> void:
	if not has_anim(name):
		if done.is_valid():
			done.call()
		return
	_anim_frames.clear()
	var dir := _anim_dir(name)
	var i := 0
	while true:
		var path := "%s/f%03d.png" % [dir, i]
		if not ResourceLoader.exists(path):
			break
		_anim_frames.append(load(path))
		i += 1
	if _anim_frames.is_empty():
		if done.is_valid():
			done.call()
		return
	# Reuse the pose sprite as the surface.
	if _pose_spr == null:
		_pose_spr = Sprite2D.new()
		_pose_spr.centered = false
		_pose_spr.z_index = 20
		_pose_spr.material = _outline_mat
		rig.add_child(_pose_spr)
	_pose_name = "@anim"
	_set_rig_visible(false)
	_anim_i = 0
	_anim_t = 0.0
	_anim_fps = fps
	_anim_playing = true
	_anim_done = done
	_show_anim_frame()

func _show_anim_frame() -> void:
	var tex: Texture2D = _anim_frames[_anim_i]
	_pose_spr.texture = tex
	# Scale so the frame stands ~full rig height, feet on the floor line, and
	# horizontally centred - matching where the sliced figure stands.
	var target_h := 1180.0
	var sc := target_h / float(tex.get_height())
	_pose_spr.scale = Vector2(sc, sc)
	_pose_spr.position = Vector2(260.0 - tex.get_width() * sc * 0.5, 1240.0 - tex.get_height() * sc)
	_pose_spr.visible = true

func _update_anim(delta: float) -> void:
	if not _anim_playing:
		return
	_anim_t += delta
	var frame_dur := 1.0 / _anim_fps
	while _anim_t >= frame_dur:
		_anim_t -= frame_dur
		_anim_i += 1
		if _anim_i >= _anim_frames.size():
			_anim_playing = false
			_pose_name = ""
			if _anim_done.is_valid():
				_anim_done.call()
			return
		_show_anim_frame()
