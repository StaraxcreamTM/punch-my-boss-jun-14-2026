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
enum Phase { TITLE, MENU, LEVELS, CUSTOMIZE, OPTIONS, AWARDS, STATS, FREEFIGHT, PREFIGHT, FIGHT, GAMEOVER, VICTORY }

# --- free fight / custom match ---
# The player picks any rigged opponent and any arena, then fights that combo with
# the normal rules. The chosen arena supplies the background/stats/gimmick; the
# chosen character overrides whoever that level would normally field.
const FREE_CHARS := [
	["suit", "Your Boss"],
	["big", "Big Terry"],
	["man", "Marcus"],
	["swim", "Sandra"],
	["suit_w", "Bev"],
	["suit_w2", "Yolanda"],
	["tank_w", "Nina"],
	["tank_w2", "Keisha"],
]
var _free_fight: bool = false
var free_char: String = "suit"      # persisted last selection
var free_arena: int = 1             # persisted last arena (level number)
var free_use_gimmick: bool = true   # include the arena's gimmick
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
var stat_worst_day: int = 0        # most damage dealt to a boss in one fight
var _fight_damage: int = 0         # running damage this fight, for worst_day
var stat_endless_best: int = 0     # furthest round reached in Endless mode
# --- adaptive difficulty (the "smarter boss") ---
# A rolling read of how the player is coping THIS fight: nudged up on a dodge or
# parry, down when they eat a punch. It shortens the boss's tell and quickens his
# attacks when you're dominating, and eases both when you're struggling - kept
# in a tight band so it's felt as "he adapts", not as rubber-banding. Only on
# Brawler (the mode where he actually attacks). Seeded from a persisted baseline
# so a returning veteran isn't re-taught from scratch every session.
var _skill: float = 0.5
var adapt_baseline: float = 0.5    # persisted long-term skill estimate
# --- endless / survival mode ---
var _endless: bool = false
var _endless_round: int = 0
var _hp_mul: float = 1.0           # boss HP scale (endless ramps this)
var _dmg_mul: float = 1.0          # boss damage scale (endless ramps this)
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
var _whiff_player: AudioStreamPlayer
var _block_player: AudioStreamPlayer
var _dodge_player: AudioStreamPlayer
var _crowd_player: AudioStreamPlayer

func _add_sfx(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p
var _music_btn: Button
var music_on: bool = true
# Haptics. MAKE-IT-SELLABLE calls this the single biggest feel gap on mobile:
# on a phone the buzz is half of what sells a punch. No-op on desktop, so it
# costs nothing to leave on.
var haptics_on: bool = true
var seen_howto: bool = false       # first-launch tutorial card shown once
var adaptive_enabled: bool = true  # the "smarter boss" can be switched off
var master_vol: float = 1.0        # 0..1, applied to the Master audio bus

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
var _dodge_holding: bool = false
# Parry: a tight counter window, and the adrenaline it feeds. Spend a full
# adrenaline meter on a super punch.
var _parry_time: float = 0.0
const PARRY_WINDOW := 0.18
var adrenaline: float = 0.0
const ADREN_MAX := 100.0
var _adren_bar: Panel
var _adren_label: Label
# Touch swipe detection for the punch fight (tap = punch, swipe = dodge/parry).
var _swipe_start: Vector2 = Vector2.ZERO
var _swipe_t: float = 0.0
const SWIPE_MIN := 90.0
const DODGE_WINDOW := 0.40

# Mid-fight transformation: at 50% HP an enrage-flagged boss speeds up, scowls
# permanently and hits harder. Prototype phase-change (Big Boy Boxing style).
var _enraged: bool = false
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
	 "enrage": true,
	 "line": "We're restructuring. You're the structure being restructured."},
	{"name": "Crunch Season", "hp": 300.0, "pace": 0.75, "dmg": 17.0, "gimmick": "rage",
	 "enrage": true,
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
	# --- themed scaffold levels (10-20) ---------------------------------------
	# Each points at a backdrop that doesn't exist yet: until the art lands, a
	# missing bg falls back to the office WITH A WARNING (see _apply_level_scene),
	# so these are all playable now as standard fights in the office. When the
	# scene art + themed boss art arrive, drop the png in assets/scenes/ and the
	# character into the roster - no code change. Placeholder gimmick "punch" and
	# a one-line tell each.
	{"name": "Nurses' Station", "mood": "tense", "hp": 240.0, "pace": 1.0, "dmg": 12.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/nurses_station.png", "enrage": true, "counter": true,
	 "line": "Say aah. Now say 'I accept this pay cut'."},
	{"name": "Police Station", "mood": "tense", "hp": 260.0, "pace": 0.95, "dmg": 13.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/police_station.png",
	 "hazard": {"sprite": "baton", "axis": "h", "period": [4.0, 6.5], "warn": 0.6, "dmg": 13.0},
	 "line": "You have the right to remain... doing overtime."},
	{"name": "Construction Site", "mood": "heavy", "hp": 300.0, "pace": 0.9, "dmg": 15.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/construction_site.png", "enrage": true,
	 "hazard": {"sprite": "ibeam", "axis": "h", "period": [4.5, 7.0], "warn": 0.8, "dmg": 16.0},
	 "line": "Where's your hard hat? Where's your WILL TO LIVE?"},
	{"name": "Fast Food Chain", "mood": "bright", "hp": 220.0, "pace": 1.05, "dmg": 11.0, "gimmick": "objects",
	 "bg": "res://assets/scenes/fast_food.png", "slick": true,
	 "line": "You want fries with that write-up?"},
	{"name": "Gas Station", "mood": "heavy", "hp": 250.0, "pace": 1.0, "dmg": 13.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/gas_station.png", "pump_zone": true,
	 "line": "Premium effort? On regular pay? Dream on."},
	{"name": "Library", "mood": "bright", "hp": 230.0, "pace": 1.1, "dmg": 10.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/library.png", "shush": true,
	 "line": "Shhh. Your career is overdue."},
	{"name": "Lawyer Office", "mood": "tense", "hp": 280.0, "pace": 0.9, "dmg": 14.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/lawyer_office.png", "enrage": true, "objection": true,
	 "line": "I'll see you in court. And in the parking lot."},
	{"name": "Hospital", "mood": "tense", "hp": 300.0, "pace": 0.85, "dmg": 15.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/hospital.png", "enrage": true,
	 "hazard": {"sprite": "gurney", "axis": "h", "period": [5.0, 8.0], "warn": 0.7, "dmg": 14.0},
	 "line": "This won't hurt me a bit."},
	{"name": "School", "mood": "bright", "hp": 260.0, "pace": 0.95, "dmg": 13.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/school.png",
	 "hazard": {"sprite": "eraser", "axis": "drop", "period": [3.5, 6.0], "warn": 0.55, "dmg": 10.0},
	 "line": "Detention. For you. Forever."},
	{"name": "College", "mood": "grand", "hp": 300.0, "pace": 0.85, "dmg": 16.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/college.png", "enrage": true,
	 "hazard": {"sprite": "projector", "axis": "drop", "period": [4.5, 7.0], "warn": 0.7, "dmg": 15.0},
	 "line": "This is a pass/fail course. You're failing."},
	{"name": "University", "mood": "grand", "hp": 340.0, "pace": 0.8, "dmg": 17.0, "gimmick": "punch",
	 "bg": "res://assets/scenes/university.png", "enrage": true, "objection": true,
	 "hazard": {"sprites": ["ibeam", "gurney", "eraser", "projector", "baton"], "period": [3.0, 4.5], "warn": 0.55, "dmg": 16.0},
	 "line": "Publish or perish. Preferably perish."},
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
	2: {"who": "Marcus, Facilities", "char": "man"},
	3: {"who": "Big Terry, Ops", "char": "big"},
	4: {"who": "Sandra, Retreat Coord.", "char": "swim"},
	5: {"who": "Bev, VP of Synergy", "char": "suit_w"},
	6: {"who": "Nina, Office Manager", "char": "tank_w"},
	7: {"who": "Yolanda, Regional Dir.", "char": "suit_w2"},
	8: {"who": "Big Terry, Ops", "char": "big"},
	9: {"who": "Keisha, HR Partner", "char": "tank_w2"},
	# Themed opponents for the scaffold levels. Name only for now (no "char"),
	# so they use the player's own boss until their character art is rigged -
	# add "char" here when it lands, nothing else changes.
	10: {"who": "Nurse Payne"},
	11: {"who": "Sgt. Bill Boyle"},
	12: {"who": "Foreman Duke"},
	13: {"who": "Manager Chad"},
	14: {"who": "Gus, Station Owner"},
	15: {"who": "Ms. Shush, Head Librarian"},
	16: {"who": "Mr. Sue, Esq."},
	17: {"who": "Dr. Payne, Chief of Med."},
	18: {"who": "Principal Vex"},
	19: {"who": "Prof. Tenure"},
	20: {"who": "Dean Loomis"},
}

# Swap in this level's opponent. Levels absent from ROSTER restore the player's
# own saved look - those are the fights against YOUR boss.
func _apply_opponent() -> void:
	var r: Dictionary = ROSTER.get(level, {})
	# Free fight overrides the character with the player's pick, keeping the
	# arena's stats/gimmick from `level`.
	if _free_fight:
		if free_char != character and _outline_mat != null:
			set_character(free_char, _outline_mat)
		if not has_expressions():
			return
		look_skin = 0
		look_hair = 0
		look_moustache = 0
		_apply_look_no_save()
		return
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
	if _free_fight:
		return _free_char_name(free_char)
	var r: Dictionary = ROSTER.get(level, {})
	return String(r.get("who", "Your Boss"))

func _free_char_name(key: String) -> String:
	for c in FREE_CHARS:
		if String(c[0]) == key:
			return String(c[1])
	return "Your Boss"

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
	_apply_volume()
	# Retroactively grant any stat-based awards a returning player already earned
	# before the system existed (suppress the toast flood on this first pass).
	_awards_silent = true
	_check_awards()
	_awards_silent = false
	_setup_shots()

	_punch_player = AudioStreamPlayer.new()
	_punch_player.stream = _make_punch()
	add_child(_punch_player)
	_ko_player = AudioStreamPlayer.new()
	_ko_player.stream = _make_ko()
	add_child(_ko_player)
	_whiff_player = _add_sfx(_make_whiff(), -6.0)
	_block_player = _add_sfx(_make_block(), -3.0)
	_dodge_player = _add_sfx(_make_dodge(), -7.0)
	_crowd_player = _add_sfx(_make_crowd(), -10.0)
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
	($Safe/Hint as Label).text = "TAP to punch   ·   SWIPE ← → ↓ to dodge   ·   SWIPE ↑ to parry"

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
	# First-ever launch: teach the controls before anything else. Skipped in the
	# screenshot demo and once the player has seen it.
	if not seen_howto and not _shot_mode:
		_show_howto(true)

	var taunt_timer := Timer.new()
	taunt_timer.wait_time = 3.8
	add_child(taunt_timer)
	taunt_timer.timeout.connect(_next_taunt)
	taunt_timer.start()

	_enter_guard()

func _process(delta: float) -> void:
	_clock += delta

	# Arcade attract mode: after a spell of no input on the title, roll into a
	# self-playing demo fight; any tap drops back to the title (handled in input).
	if phase == Phase.TITLE and not _attract and not _shot_mode \
			and (_howto_overlay == null or not _howto_overlay.visible):
		_title_idle += delta
		if _title_idle >= ATTRACT_IDLE:
			_enter_attract()

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
			_update_hazard(delta)   # environmental hazards layer on punch fights
			_update_noise(delta)    # library SHHH meter decays when you pause
			_update_counter(delta)  # nurses syringe counter-window

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
		# Named combo tiers: the label shows the count plus an escalating office
		# rank. Higher tiers also pay a bigger score multiplier (see _combo_tier).
		var tier := _combo_tier(combo)
		_combo_label.text = "%d\n%s" % [combo, tier[0]]
		_combo_label.scale = _combo_label.scale.lerp(Vector2.ONE * (1.0 + minf(combo, 30.0) * 0.012), 12.0 * delta)
		_combo_label.add_theme_color_override("font_color", tier[1])

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
	# Occasionally throw the boss's signature move with the taunt - only while
	# guarding (a drawn pose or an in-flight attack shouldn't be interrupted).
	if rig_anim != null and phase == Phase.FIGHT and _state == BossState.GUARD \
			and not has_pose("guard") and randf() < 0.5:
		rig_anim.play_signature(String(SIGNATURES.get(character, "")))

# Each character's signature move, fitting their name/role.
const SIGNATURES := {
	"suit": "present",         # your boss: presents a slide
	"man": "shrug",            # Marcus, Facilities: not-my-problem shrug
	"big": "belly_bump",       # Terry, Ops: gut thrust
	"swim": "trust_fall",      # Sandra, Retreat Coord: trust-fall lean
	"suit_w": "synergy_clap",  # Bev, VP of Synergy
	"suit_w2": "present",      # Yolanda, Regional Dir: presents
	"tank_w": "shrug",         # Nina, Office Manager
	"tank_w2": "finger_wag",   # Keisha, HR Partner: scolding wag
}

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
		_title_idle = 0.0
		# During attract, any press drops the demo and returns to the title -
		# nothing else (no punch, no menu) should register.
		if _attract:
			var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed) \
				or (event is InputEventJoypadButton and event.pressed)
			if pressed:
				_exit_attract()
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		# Dodge keys are HOLDABLE: begin the dodge on press, release on key-up.
		# Handled outside the press-only block so key-up is seen.
		if not event.echo:
			match event.keycode:
				KEY_LEFT:
					_dodge_press(-1) if event.pressed else _dodge_lift(-1)
				KEY_RIGHT:
					_dodge_press(1) if event.pressed else _dodge_lift(1)
				KEY_DOWN:
					_dodge_press(0) if event.pressed else _dodge_lift(0)
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_A: _press("A")
				KEY_B: _press("B")
				KEY_X: _press("X")
				KEY_Y: _press("Y")
				KEY_M: toggle_music()
				# Customisation: skin / hair / moustache.
				KEY_K: cycle_look("skin")
				KEY_H: cycle_look("hair")
				KEY_J: cycle_look("moustache")
				KEY_1: _pick_difficulty(Difficulty.BAG)
				KEY_2: _pick_difficulty(Difficulty.DEFENSIVE)
				KEY_3: _pick_difficulty(Difficulty.BRAWLER)
				KEY_UP: _parry()
				KEY_SHIFT: _super_punch()
				KEY_ESCAPE: _go_back()
				KEY_SPACE, KEY_ENTER: _advance_screen()
	elif event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:
				_dodge_press(-1) if event.pressed else _dodge_lift(-1)
			JOY_BUTTON_DPAD_RIGHT:
				_dodge_press(1) if event.pressed else _dodge_lift(1)
			JOY_BUTTON_DPAD_DOWN:
				_dodge_press(0) if event.pressed else _dodge_lift(0)
		if event.pressed:
			match event.button_index:
				JOY_BUTTON_A: _press("A")
				JOY_BUTTON_B: _press("B")
				JOY_BUTTON_X: _press("X")
				JOY_BUTTON_Y: _press("Y")
				JOY_BUTTON_RIGHT_SHOULDER: _parry()
				JOY_BUTTON_LEFT_SHOULDER: _super_punch()
	elif event is InputEventMouseButton:
		# Touches arrive here too via Godot's emulate_mouse_from_touch.
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mp := get_global_mouse_position()
			if phase in [Phase.MENU, Phase.LEVELS, Phase.CUSTOMIZE, Phase.OPTIONS, Phase.AWARDS]:
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
			else:
				# Punch fight: a TAP punches where you touched, a SWIPE dodges
				# (left/right/down) or parries (up). Makes the fight playable on
				# a phone with no keyboard.
				if event.pressed:
					_swipe_start = mp
					_swipe_t = _clock
				else:
					_resolve_swipe(mp)

# Click/tap anywhere: throw a fist at that exact point. Hits on the boss deal
# damage; clicks in open air still swing (and whiff).
func _punch_click(pos: Vector2) -> void:
	if phase != Phase.FIGHT or _koing or _punch_cd > 0.0:
		return
	# Gas station: a live fuel pump sits beside the boss. Punch into its zone and
	# it goes up - big self-damage. You have to aim AROUND it.
	if _pump_rect != Rect2() and _pump_rect.has_point(pos):
		_pump_explosion(pos)
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
	if _whiff_player != null:
		_whiff_player.pitch_scale = randf_range(0.9, 1.1)
		_whiff_player.play()
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
			# Big head hits roll one of the cartoon head gags (now 10).
			match randi() % 10:
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
				5:
					rig_anim.stretch_up(1.0)
				6:
					rig_anim.orbit_head(randi_range(2, 3))
				7:
					rig_anim.backwards_bend(1.0)
				8:
					rig_anim.corkscrew(1.0)
				_:
					rig_anim.parts_launch(1.0)
		else:
			if randf() < 0.25:
				rig_anim.rubber_neck(2)
			else:
				rig_anim.stagger(side_left, 0.7)
	else:
		rig_anim.stagger(side_left, 1.0 if crit else 0.55)
		if crit:
			# Body criticals roll one of the body gags (now 7).
			match randi() % 7:
				0:
					rig_anim.flatten(1.0)
				1:
					rig_anim.jelly_legs(0.9)
				2:
					rig_anim.shock_hop(1.0)
				3:
					rig_anim.accordion(1.0)
				4:
					rig_anim.knee_knock(1.0)
				5:
					rig_anim.pancake_bounce(1.0)
				_:
					rig_anim.knees_buckle(0.9)

func _chip(impact: Vector2, text_pos: Vector2) -> void:
	# A normal punch while the boss is guarding: small damage, standard juice.
	# Pitch climbs with the combo - the classic arcade cue that a run is
	# building. Capped so it never turns into a squeak.
	_punch_player.pitch_scale = clampf(0.92 + float(combo) * 0.045, 0.9, 1.9) 		* randf_range(0.97, 1.04)
	_punch_player.play()
	if not _react.is_empty():
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
	if not _react.is_empty():
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
	var prev_tier: String = _combo_tier(combo)[0]
	combo += 1
	combo_time = COMBO_WINDOW
	max_combo = maxi(max_combo, combo)
	# Crossing into a new named tier pops a banner and a little juice.
	var new_tier: Array = _combo_tier(combo)
	if String(new_tier[0]) != prev_tier and combo >= 6:
		_spawn_text(Vector2(960.0, 500.0), String(new_tier[0]) + "!", 96, new_tier[1])
		_flash_screen(0.18)
		_shake(6.0, 0.18)
	if _combo_label != null:
		_combo_label.pivot_offset = _combo_label.size / 2.0
		_combo_label.scale = Vector2.ONE * 1.45
	if crit:
		crits += 1
		_crit_total += 1
	if combo >= 20:
		_check_awards()          # combo milestones announce as you cross them
	# Multiplier climbs to 4x. It can go this high because the punch cooldown
	# means a long combo has to be *earned* on timing rather than farmed by
	# mashing - which is what the old 1.8x ceiling was compensating for.
	var combo_mul := 1.0 + minf(float(combo) * 0.14, 3.0)
	var dmg := maxf(1.0, roundf(base * combo_mul * (1.35 if frenzy > 0.0 else 1.0)))
	_set_hp(hp - dmg)
	stat_damage += int(dmg)
	_fight_damage += int(dmg)
	stat_worst_day = maxi(stat_worst_day, _fight_damage)
	stat_best_combo = maxi(stat_best_combo, combo)
	_spawn_text(impact + Vector2(randf_range(-20.0, 20.0), -50.0), str(int(dmg)),
		64 if crit else 44, Color(1, 0.32, 0.21) if crit else Color(1, 1, 1))
	# Score: damage scaled by the multiplier, bonus for criticals and frenzy.
	var tier_mul: float = _combo_tier(combo)[2]
	var gained := int(roundf(dmg * 10.0 * combo_mul * tier_mul * (2.0 if crit else 1.0)))
	_add_noise(11.0 if crit else 8.0)
	_add_score(gained, impact)
	if frenzy <= 0.0:
		_set_rage(rage + (13.0 if crit else 5.0))
		if rage >= 100.0:
			frenzy = 6.0
			_set_rage(0.0)
			_flash_screen(0.5)
			_shake(18.0, 0.4)
			_spawn_text(Vector2(960.0, 300.0), "FRENZY!!", 130, Color(1, 0.24, 0.94))

# Named combo tiers, ascending. Returns [name, colour, score multiplier]. The
# office-rank names climb with the streak; the multiplier feeds scoring so a
# high tier is worth chasing, not just cosmetic.
func _combo_tier(c: int) -> Array:
	if c >= 50:
		return ["HR NIGHTMARE", Color(1, 0.1, 0.55), 2.5]
	elif c >= 40:
		return ["INSUBORDINATE", Color(1, 0.24, 0.94), 2.2]
	elif c >= 30:
		return ["GOING POSTAL", Color(1, 0.3, 0.3), 1.9]
	elif c >= 20:
		return ["UNHINGED", Color(1, 0.32, 0.21), 1.6]
	elif c >= 12:
		return ["ON A ROLL", Color(1, 0.5, 0.16), 1.35]
	elif c >= 6:
		return ["WARMED UP", Color(1, 0.7, 0.16), 1.15]
	return ["COMBO", Color(1, 0.82, 0.17), 1.0]

# Award points and pop a floating "+N" at the impact. Big gains read louder.
# Harder difficulty scores more, so choosing Brawler is a real trade, not just
# extra pain: he fights back, but every point is worth more.
const DIFF_SCORE_MUL := [1.0, 1.15, 1.35]   # BAG, DEFENSIVE, BRAWLER

func _add_score(amount: int, at: Vector2) -> void:
	if amount <= 0:
		return
	amount = int(round(float(amount) * DIFF_SCORE_MUL[clampi(difficulty, 0, 2)]))
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
	# While a dodge key is held the evade window stays full, so a held lean
	# covers the whole attack - the "holdable dodge" that rewards staying mobile.
	if _dodge_holding:
		_dodge_time = DODGE_WINDOW
	elif _dodge_time > 0.0:
		_dodge_time -= delta
	if _parry_time > 0.0:
		_parry_time -= delta
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

# Adaptive only kicks in when the boss actually fights back.
func _adaptive_on() -> bool:
	return adaptive_enabled and difficulty == Difficulty.BRAWLER

# Master-bus volume. 0 mutes; otherwise mapped through linear_to_db so the
# steps sound evenly spaced rather than bunched near the top.
func _apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	if master_vol <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(master_vol))

# Push the skill read toward a target by a step, clamped to [0,1].
func _nudge_skill(delta: float) -> void:
	if not _adaptive_on():
		return
	_skill = clampf(_skill + delta, 0.0, 1.0)

# 1.0 at neutral skill; <1 (faster/shorter) as the player dominates, >1 as they
# struggle. Tight band so the effect is fair, not swingy.
func _adapt_tell() -> float:
	if not _adaptive_on():
		return 1.0
	return lerpf(1.15, 0.80, _skill)

func _adapt_pace() -> float:
	if not _adaptive_on():
		return 1.0
	return lerpf(1.20, 0.82, _skill)

func _windup_dur() -> float:
	# Later levels telegraph faster, so the dodge window tightens; adaptive then
	# shortens it further for a dominating player (or eases it for a struggling one).
	return maxf(0.20, (WINDUP_DUR - float(level - 1) * 0.05) * _adapt_tell())

# The 50%-HP transformation. A held dramatic beat, then he's permanently angrier
# for the rest of the fight: faster guard cycles and a locked-on scowl.
func _boss_enrage() -> void:
	_enraged = true
	_hitstop(0.14)
	_flash_screen(0.6)
	_shake(24.0, 0.6)
	_buzz(60)
	_spawn_text(Vector2(960.0, 300.0), "ENOUGH!!", 130, Color(1, 0.24, 0.14))
	if _crowd_player != null:
		_crowd_player.play()
	_say("You know what? I've HAD it with you.")
	if rig_anim != null:
		rig_anim.spin_body(1)
		rig_anim.idle_amp = 1.7        # visibly more agitated idle
	# Lock a scowl on for characters that have one; others just seethe via bones.
	if not _angry_faces.is_empty():
		_react_tex = _angry_faces[randi() % _angry_faces.size()]
		_react_time = 999.0            # held until the next reaction overrides it

func _enter_guard() -> void:
	_state = BossState.GUARD
	# Enraged: attacks come ~40% faster (shorter guard gaps). Adaptive tightens or
	# loosens the gap based on how the player is coping.
	var pace := float(_level_cfg().get("pace", 1.0)) * (0.6 if _enraged else 1.0) * _adapt_pace()
	_state_time = randf_range(2.6, 4.2) * pace
	_prompt.visible = false
	# A permanent angry flush while enraged.
	boss.modulate = Color(1.0, 0.86, 0.82) if _enraged else Color(1, 1, 1)
	if has_pose("guard"):
		set_pose("guard")
	elif rig_anim != null and difficulty != Difficulty.BAG:
		rig_anim.block()
		if _block_player != null:
			_block_player.play()

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
	# Lawyer level: every tell throws an "OBJECTION!" parry prompt, cueing the
	# tight counter rather than a dodge.
	if not _is_feint and bool(_level_cfg().get("objection", false)):
		_spawn_text(Vector2(960.0, 250.0), "OBJECTION!", 76, Color(0.4, 0.9, 1.0))
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
	# Parry first: a tight-window counter (much tighter than the forgiving
	# holdable dodge). Land it on the strike frame and the boss is staggered wide
	# open and you bank adrenaline - high risk, high reward.
	if _parry_time > 0.0:
		_atk_whiffed = true
		_parry_time = 0.0
		_spawn_text(Vector2(960.0, 380.0), "PARRY!", 96, Color(0.4, 0.9, 1.0))
		_grant("parry_first")
		_flash_screen(0.5)
		_shake(14.0, 0.3)
		_hitstop(0.07)
		if _block_player != null:
			_block_player.pitch_scale = 1.4
			_block_player.play()
		if rig_anim != null:
			rig_anim.stagger(_atk_side, 1.2)
			rig_anim.knees_buckle(0.8)
		_add_adrenaline(34.0)
		_nudge_skill(0.10)       # clean parry: he's read
		_enter_stunned(1.6)      # extended punish window
		return
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
		_nudge_skill(0.06)       # read the tell, slipped it
		if rig_anim != null:
			rig_anim.body_pos = Vector2(0, 0)
	else:
		_hit_player()

func _hit_player() -> void:
	_buzz(80)
	_nudge_skill(-0.12)          # ate it: ease off
	_hits_this_fight += 1        # a landed boss punch: no longer flawless
	if _daily_oneshot:
		player_hp = 0.0          # Sudden Death daily: one hit ends it
	else:
		player_hp = maxf(0.0, player_hp - _level_cfg().get("dmg", 10.0) * _dmg_mul)
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

# Holdable dodge. Press to snap into the lean and STAY evading while held;
# release to spring back. Direction matters at the strike frame - the uppercut
# punishes ducking, the overhead must be ducked, the barge must be sidestepped
# (see _resolve_attack). Holding the wrong way when the attack lands = a hit.
func _dodge_press(dir: int) -> void:
	if _koing or phase != Phase.FIGHT:
		return
	_dodge_holding = true
	_dodge_dir = dir
	_dodge_time = DODGE_WINDOW
	if _dodge_player != null:
		_dodge_player.pitch_scale = randf_range(0.95, 1.2)
		_dodge_player.play()
	if rig_anim != null:
		rig_anim.dodge_hold(dir)
	# Camera leans opposite so it reads as the player slipping.
	var shift := Vector2(-90.0 * float(dir), 34.0 if dir == 0 else 0.0)
	var tw := create_tween()
	tw.tween_property(safe, "position", shift, 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _dodge_lift(dir: int) -> void:
	# Only the currently-held direction releases (ignoring the other arrow).
	if not _dodge_holding or dir != _dodge_dir:
		return
	_dodge_holding = false
	if rig_anim != null:
		rig_anim.dodge_release()
	# Grease-slick floor (fast food): you SLIDE past the stop before recovering,
	# so the evade window lingers and precise timing is thrown off.
	if bool(_level_cfg().get("slick", false)):
		var overshoot := Vector2(-140.0 * float(dir), 0.0)
		_dodge_time = maxf(_dodge_time, 0.22)   # the slide keeps you evading longer
		var st := create_tween()
		st.tween_property(safe, "position", overshoot, 0.16).set_trans(Tween.TRANS_SINE)
		st.tween_property(safe, "position", Vector2.ZERO, 0.34).set_trans(Tween.TRANS_BACK)
		return
	var tw := create_tween()
	tw.tween_property(safe, "position", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_BACK)

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
		set_pose("")          # drop any held pose so the celebration shows
		rig_anim.laugh()
		rig_anim.victory_dance()
	_flash_screen(0.5)
	_shake(24.0, 0.5)
	await get_tree().create_timer(2.4).timeout
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
	if _crowd_player != null:
		_crowd_player.play()
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
	if not _react.is_empty():
		_react_tex = _react[_react.size() - 1]
	_react_time = 999.0

	ko_banner.text = "K.O.!"
	ko_banner.pivot_offset = ko_banner.size / 2.0
	ko_banner.modulate.a = 1.0
	ko_banner.scale = Vector2(0.5, 0.5)
	var bt := create_tween()
	bt.tween_property(ko_banner, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if has_anim("ko_collapse"):
		# Blender-authored full-body KO collapse (crumple to the floor). Plays as a
		# frame sequence overlay at normal speed - the hand-animated arc reads far
		# better than the generic launch.
		Engine.time_scale = 1.0
		play_anim("ko_collapse", 12.0)
		await get_tree().create_timer(22.0 / 12.0 + 0.2, true, false, true).timeout
	elif has_ko():
		# Floored KO: he drops where he stands and the hand-drawn KO art shows
		# him spread out on the ground.
		var drop := create_tween()
		drop.tween_property(rig, "position", Vector2(0.0, 40.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await drop.finished
		_show_ko_floor()
		await get_tree().create_timer(0.5, true, false, true).timeout
	else:
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
	set_pose("")          # clear the floored-KO art; the rig stands back up
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
	# Award checks that only a win can trip.
	_grant("first_ko")
	if _hits_this_fight == 0:
		_grant("flawless")
	if difficulty == Difficulty.BRAWLER:
		_grant("brawler")
	_check_awards()
	_save_prefs()
	_koing = false
	if _endless:
		_endless_next_round()
		return
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
	# Phase change: at half health an enrage-flagged boss "loses it". Only in a
	# real fight, once, and only on the way DOWN (not when HP is being reset).
	if not _enraged and phase == Phase.FIGHT and hp > 0.0 and hp <= hp_max * 0.5 \
			and bool(_level_cfg().get("enrage", false)):
		_boss_enrage()

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

# Whiff: a short filtered-noise whoosh with a falling pitch - a swing through air.
func _make_whiff() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.18
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		var t := float(i) / rate
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))     # swell in and out
		var nz := randf() * 2.0 - 1.0
		# One-pole low-pass whose cutoff falls, so the whoosh darkens.
		var k := lerpf(0.5, 0.08, t / dur)
		last = last + k * (nz - last)
		data.encode_s16(i * 2, int(clampf(last * env * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

# Block: a dull wooden thud - two fast low sine clicks.
func _make_block() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.12
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 40.0) + exp(-maxf(0.0, t - 0.05) * 40.0) * 0.6
		var s := sin(TAU * 120.0 * t) * env * 0.55
		s += (randf() * 2.0 - 1.0) * exp(-t * 80.0) * 0.2
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

# Dodge: a quick rising "swish".
func _make_dodge() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.14
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 10.0)
		var nz := randf() * 2.0 - 1.0
		var k := lerpf(0.10, 0.6, t / dur)   # cutoff RISES -> brighter swish
		last = last + k * (nz - last)
		data.encode_s16(i * 2, int(clampf(last * env * 0.45, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

# Crowd "oooh" - a soft filtered-noise swell, like a reacting office.
func _make_crowd() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.8
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))
		# A vowel-ish "ooh": low formants around 300/600 Hz plus air.
		var s := sin(TAU * 300.0 * t) * 0.4 + sin(TAU * 600.0 * t) * 0.2
		s += (randf() * 2.0 - 1.0) * 0.15
		data.encode_s16(i * 2, int(clampf(s * env * 0.4, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

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
	if "--nomenu" in OS.get_cmdline_user_args():
		_skip_menu = true
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
	# --attract: capture the arcade attract loop instead of the menu-tour demo.
	if "--attract" in OS.get_cmdline_user_args():
		_attract_debug = true
		get_tree().create_timer(0.4).timeout.connect(_start_endless)
		return
	var dm := Timer.new()
	dm.wait_time = _demo_period
	dm.autostart = true
	dm.timeout.connect(_demo_tick)
	add_child(dm)

var _tour: int = 0

var _skip_menu := false

func _demo_tour() -> void:
	if _skip_menu and phase != Phase.FIGHT:
		if phase == Phase.PREFIGHT:
			_start_fight()
		else:
			_start_prefight()
		return
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
					open_menu(Phase.AWARDS)
				4:
					open_menu(Phase.STATS)
				5:
					open_menu(Phase.OPTIONS)
				6:
					open_menu(Phase.FREEFIGHT)
				_:
					_on_play()
		Phase.LEVELS, Phase.OPTIONS, Phase.AWARDS, Phase.STATS, Phase.FREEFIGHT:
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
# --- attract mode (arcade-cabinet demo loop) --------------------------------
const ATTRACT_IDLE := 14.0        # seconds idle on the title before it kicks in
var _attract: bool = false
var _attract_step: int = 0
var _title_idle: float = 0.0
var _attract_timer: Timer
var _attract_badge: Control
var _attract_prev_diff: int = Difficulty.BRAWLER
var _attract_debug: bool = false   # allow attract under the shot harness for capture

func _enter_attract() -> void:
	if _attract or (_shot_mode and not _attract_debug):
		return
	_attract = true
	_attract_step = 0
	_attract_prev_diff = difficulty          # restore the player's choice on exit
	difficulty = Difficulty.BRAWLER          # lively: he fights back in the demo
	_ensure_attract_badge()
	_attract_badge.visible = true
	if _attract_timer == null:
		_attract_timer = Timer.new()
		_attract_timer.wait_time = 0.62
		_attract_timer.timeout.connect(_attract_tick)
		add_child(_attract_timer)
	_attract_timer.start()
	_attract_new_fight()

func _attract_new_fight() -> void:
	level = _rand_endless_level()
	_start_prefight()

func _attract_tick() -> void:
	if not _attract or _koing:
		return
	match phase:
		Phase.PREFIGHT:
			_start_fight()
		Phase.FIGHT:
			_attract_fight_step()
		Phase.VICTORY, Phase.GAMEOVER:
			_attract_new_fight()               # loop the reel
		_:
			_attract_new_fight()

# A compact version of the shot demo's fight driving: punch, dodge, parry, super.
func _attract_fight_step() -> void:
	_attract_step += 1
	if _attract_step % 5 == 0:
		_parry()
	if adrenaline >= ADREN_MAX:
		_super_punch()
	match _attract_step % 8:
		1, 2:
			_punch(_attract_step % 2 == 0, true)     # head
		3:
			_punch(true, false)                      # body
		4:
			_dodge_press(-1)
			get_tree().create_timer(0.4).timeout.connect(func() -> void: _dodge_lift(-1))
		5:
			_punch(false, false)
		6:
			_dodge_press(1)
			get_tree().create_timer(0.4).timeout.connect(func() -> void: _dodge_lift(1))
		7:
			_dodge_press(0)
			get_tree().create_timer(0.35).timeout.connect(func() -> void: _dodge_lift(0))
		_:
			_punch(true, true)

func _exit_attract() -> void:
	if not _attract:
		return
	_attract = false
	_title_idle = 0.0
	difficulty = _attract_prev_diff          # undo the forced Brawler
	if _attract_timer != null:
		_attract_timer.stop()
	if _attract_badge != null:
		_attract_badge.visible = false
	# Tear the demo fight down and return to a clean title.
	_koing = false
	set_pose("")
	score = 0
	_score_shown = 0.0
	close_menu()
	_show_title()

var _endless_hud: Label

func _ensure_endless_hud() -> void:
	if _endless_hud != null:
		return
	var l := Label.new()
	l.z_index = 40
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.16))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -220.0
	l.offset_right = 220.0
	l.offset_top = 132.0
	l.visible = false
	safe.add_child(l)
	_endless_hud = l

func _ensure_attract_badge() -> void:
	if _attract_badge != null:
		return
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 60
	c.visible = false
	safe.add_child(c)
	var lbl := Label.new()
	lbl.text = "◄  DEMO  ►    tap to play"
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color(1, 0.86, 0.16))
	lbl.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_top = -120.0
	lbl.offset_bottom = -40.0
	c.add_child(lbl)
	_attract_badge = c

func _demo_tick() -> void:
	if _koing:
		return
	# Walk the whole front end so the filmstrip covers every screen, not just
	# combat: title -> menu -> levels -> customise -> options -> play.
	if phase != Phase.FIGHT:
		_demo_tour()
		return
	_demo_step += 1
	# Exercise PAUSE once mid-fight so the filmstrip proves the pause overlay
	# renders, then resume so the fight (and the tour) continues.
	if _demo_step == 16 and phase == Phase.FIGHT:
		_on_pause()
		return
	if _demo_step == 17 and _pause_overlay != null and _pause_overlay.visible:
		_resume()
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
	# Occasionally parry and fire a super, to exercise those paths.
	if _demo_step % 5 == 0:
		_parry()
	if adrenaline >= ADREN_MAX:
		_super_punch()
	match _demo_step % 8:
		1, 2:
			_punch(_demo_step % 2 == 0, true)    # head
		3:
			_punch(true, false)                  # body
		4:
			# Hold a dodge for a beat, then release (exercises the holdable path).
			_dodge_press(-1)
			get_tree().create_timer(0.5).timeout.connect(func() -> void: _dodge_lift(-1))
		5:
			_punch(false, false)
		6:
			_dodge_press(1)
			get_tree().create_timer(0.5).timeout.connect(func() -> void: _dodge_lift(1))
		7:
			_dodge_press(0)
			get_tree().create_timer(0.4).timeout.connect(func() -> void: _dodge_lift(0))
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

# Per-mood chiptune loops. Each mood is a chord progression (bass roots), an
# arpeggio shape, a tempo and a brightness - all just numbers, so every track is
# generated maths with zero audio assets. Moods are themed to the environments:
# office (default), tense (hospital/police/lawyer), heavy (construction/gas),
# bright (fast food/school/library), grand (college/university).
const MUSIC_MOODS := {
	"office": {"bpm": 132.0, "roots": [55.00, 43.65, 65.41, 49.00],
		"arp": [0.0, 3.0, 7.0, 12.0, 7.0, 3.0], "bass": 0.30, "lead": 0.16},
	"tense":  {"bpm": 104.0, "roots": [55.00, 58.27, 55.00, 51.91],
		"arp": [0.0, 3.0, 6.0, 3.0], "bass": 0.34, "lead": 0.12},
	"heavy":  {"bpm": 120.0, "roots": [41.20, 41.20, 55.00, 49.00],
		"arp": [0.0, 5.0, 7.0, 12.0], "bass": 0.40, "lead": 0.13},
	"bright": {"bpm": 150.0, "roots": [65.41, 82.41, 73.42, 98.00],
		"arp": [0.0, 4.0, 7.0, 12.0, 16.0, 12.0], "bass": 0.26, "lead": 0.17},
	"grand":  {"bpm": 96.0, "roots": [55.00, 65.41, 49.00, 73.42],
		"arp": [0.0, 4.0, 7.0, 11.0, 12.0], "bass": 0.32, "lead": 0.15},
}

func _make_music(mood: String = "office") -> AudioStreamWAV:
	var cfg: Dictionary = MUSIC_MOODS.get(mood, MUSIC_MOODS["office"])
	var rate := 44100
	var beat := 60.0 / float(cfg["bpm"])
	var bars := 4
	var dur := beat * 4.0 * float(bars)
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var roots: Array = cfg["roots"]
	var arp: Array = cfg["arp"]
	var bass_amp: float = cfg["bass"]
	var lead_amp: float = cfg["lead"]
	for i in n:
		var t := float(i) / rate
		var bar := int(t / (beat * 4.0)) % bars
		var root: float = roots[bar]
		var tb := fmod(t, beat)
		var benv := exp(-tb * 7.0)
		var bs := (1.0 if sin(TAU * root * t) >= 0.0 else -1.0) * benv * bass_amp
		var step := int(t / (beat * 4.0 / float(arp.size()))) % arp.size()
		var af: float = root * 4.0 * pow(2.0, float(arp[step]) / 12.0)
		var aenv := exp(-fmod(t, beat * 4.0 / float(arp.size())) * 9.0)
		var ph := fmod(af * t, 1.0)
		var tri := 4.0 * absf(ph - 0.5) - 1.0
		var as_ := tri * aenv * lead_amp
		data.encode_s16(i * 2, int(clampf(bs + as_, -1.0, 1.0) * 32767.0))
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

# Swap the music to a mood (generated once per mood, then cached), keeping it
# playing across the swap if it was already going.
var _music_cache: Dictionary = {}
var _music_mood: String = "office"

func set_music_mood(mood: String) -> void:
	if mood == _music_mood or _music_player == null:
		return
	_music_mood = mood
	if not _music_cache.has(mood):
		_music_cache[mood] = _make_music(mood)
	var was_playing := _music_player.playing
	_music_player.stream = _music_cache[mood]
	if was_playing and music_on:
		_music_player.play()

func _notification(what: int) -> void:
	# --quit-after and a window close take different teardown paths, so cover
	# both plus the plain tree exit.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE 			or what == NOTIFICATION_EXIT_TREE:
		_release_music()
	# Android hardware back button (and desktop ESC, via _unhandled_input).
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()

# One "back" gesture, shared by the Android back button and the ESC key:
# pause->resume, fight->pause, a sub-screen->main menu, an end screen->menu.
# On the main menu it does nothing (no accidental app-quit).
func _go_back() -> void:
	if _pause_overlay != null and _pause_overlay.visible:
		_resume()
		return
	match phase:
		Phase.FIGHT:
			_on_pause()
		Phase.LEVELS, Phase.CUSTOMIZE, Phase.OPTIONS, Phase.AWARDS, Phase.STATS, Phase.FREEFIGHT, Phase.PREFIGHT:
			open_menu(Phase.MENU)
		Phase.VICTORY, Phase.GAMEOVER:
			_advance_screen()
		_:
			pass

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
	_music_cache["office"] = _make_music("office")
	_music_player.stream = _music_cache["office"]
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
var _pause_overlay: Control

func _ensure_pause_ui() -> void:
	if _pause_overlay != null:
		return
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.z_index = 120
	# ALWAYS so the overlay and its buttons keep processing while the rest of the
	# tree is frozen by get_tree().paused.
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(dim)
	var title := _big_label(96, Color(1, 0.86, 0.16), -0.02)
	title.text = "PAUSED"
	title.offset_top = 220.0
	title.offset_bottom = 360.0
	_pause_overlay.add_child(title)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.offset_left = -MENU_W * 0.5
	vb.offset_right = MENU_W * 0.5
	vb.offset_top = 430.0
	_pause_overlay.add_child(vb)
	var resume := _menu_button("RESUME", Color(0.20, 0.70, 0.25))
	resume.pressed.connect(_resume)
	vb.add_child(resume)
	var quit := _menu_button("QUIT TO MENU", Color(0.72, 0.26, 0.24))
	quit.pressed.connect(_quit_to_menu)
	vb.add_child(quit)

var _howto_overlay: Control

const HOWTO_BODY := "TAP the boss to punch  ·  A / B body,  X / Y head.
He WINDS UP before he swings — that's your cue.
SWIPE  ←  →  to dodge his punch,   SWIPE  ↓  to duck.
SWIPE  ↑  to PARRY it: staggers him wide open.
Fill the K.O. meter to launch him out of the office."

func _ensure_howto_ui() -> void:
	if _howto_overlay != null:
		return
	_howto_overlay = Control.new()
	_howto_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_howto_overlay.z_index = 125
	_howto_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_howto_overlay.visible = false
	add_child(_howto_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.08, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_howto_overlay.add_child(dim)
	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -660.0
	card.offset_right = 660.0
	card.offset_top = -390.0
	card.offset_bottom = 390.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.96, 0.86)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(6)
	sb.border_color = Color(0.82, 0.2, 0.18)
	card.add_theme_stylebox_override("panel", sb)
	_howto_overlay.add_child(card)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.82, 0.2, 0.18))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 34.0
	title.offset_bottom = 120.0
	card.add_child(title)
	var body := Label.new()
	body.text = HOWTO_BODY
	body.add_theme_font_size_override("font_size", 33)
	body.add_theme_color_override("font_color", Color(0.12, 0.10, 0.14))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.anchor_right = 1.0
	body.offset_left = 40.0
	body.offset_right = -40.0
	body.offset_top = 130.0
	body.offset_bottom = 470.0
	card.add_child(body)
	var go := _menu_button("LET'S GO!", Color(0.20, 0.70, 0.25))
	go.anchor_left = 0.5
	go.anchor_right = 0.5
	go.offset_left = -220.0
	go.offset_right = 220.0
	go.offset_top = 600.0
	go.offset_bottom = 600.0 + MENU_ROW_H
	go.pressed.connect(_dismiss_howto)
	card.add_child(go)

func _show_howto(first_time: bool) -> void:
	_ensure_howto_ui()
	_howto_overlay.visible = true
	_howto_first = first_time

var _howto_first: bool = false

func _dismiss_howto() -> void:
	if _howto_overlay != null:
		_howto_overlay.visible = false
	if _howto_first:
		seen_howto = true
		_save_prefs()
		_howto_first = false

func _on_pause() -> void:
	if phase != Phase.FIGHT:
		return
	_ensure_pause_ui()
	if _pause_overlay.visible:
		return
	_pause_overlay.visible = true
	# In the screenshot demo, don't actually freeze the tree - that would stall
	# the capture timer; showing the overlay is enough to film it.
	if not _shot_mode:
		get_tree().paused = true

func _resume() -> void:
	get_tree().paused = false
	if _pause_overlay != null:
		_pause_overlay.visible = false

func _quit_to_menu() -> void:
	get_tree().paused = false
	if _pause_overlay != null:
		_pause_overlay.visible = false
	_endless = false
	_hp_mul = 1.0
	_dmg_mul = 1.0
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
	stat_worst_day = int(cfg.get_value("stats", "worst_day", 0))
	stat_endless_best = int(cfg.get_value("stats", "endless_best", 0))
	adapt_baseline = clampf(float(cfg.get_value("settings", "adapt", 0.5)), 0.0, 1.0)
	_crit_total = int(cfg.get_value("stats", "crits", 0))
	awards_earned.clear()
	for id in cfg.get_value("awards", "earned", []):
		awards_earned[String(id)] = true
	haptics_on = bool(cfg.get_value("settings", "haptics", true))
	seen_howto = bool(cfg.get_value("settings", "seen_howto", false))
	adaptive_enabled = bool(cfg.get_value("settings", "adaptive", true))
	master_vol = clampf(float(cfg.get_value("settings", "volume", 1.0)), 0.0, 1.0)
	free_char = str(cfg.get_value("free", "char", "suit"))
	free_arena = clampi(int(cfg.get_value("free", "arena", 1)), 1, LEVELS.size())
	free_use_gimmick = bool(cfg.get_value("free", "gimmick", true))
	music_on = bool(cfg.get_value("settings", "music", true))
	difficulty = int(cfg.get_value("settings", "difficulty", Difficulty.BRAWLER))
	look_skin = int(cfg.get_value("look", "skin", 0))
	look_hair = int(cfg.get_value("look", "hair", 0))
	look_moustache = int(cfg.get_value("look", "moustache", 0))
	_own_skin = look_skin
	_own_hair = look_hair
	_own_moustache = look_moustache
	portrait = bool(cfg.get_value("settings", "portrait", false))
	grievance_points = int(cfg.get_value("daily", "points", 0))
	daily_streak = int(cfg.get_value("daily", "streak", 0))
	_daily_last = str(cfg.get_value("daily", "last", ""))

func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.set_value("score", "unlocked", unlocked)
	cfg.set_value("stats", "punches", stat_punches)
	cfg.set_value("stats", "damage", stat_damage)
	cfg.set_value("stats", "kos", stat_kos)
	cfg.set_value("stats", "fired", stat_fired)
	cfg.set_value("stats", "best_combo", stat_best_combo)
	cfg.set_value("stats", "worst_day", stat_worst_day)
	cfg.set_value("stats", "endless_best", stat_endless_best)
	cfg.set_value("settings", "adapt", adapt_baseline)
	cfg.set_value("stats", "crits", _crit_total)
	cfg.set_value("awards", "earned", awards_earned.keys())
	cfg.set_value("settings", "haptics", haptics_on)
	cfg.set_value("settings", "seen_howto", seen_howto)
	cfg.set_value("settings", "adaptive", adaptive_enabled)
	cfg.set_value("free", "char", free_char)
	cfg.set_value("free", "arena", free_arena)
	cfg.set_value("free", "gimmick", free_use_gimmick)
	cfg.set_value("settings", "volume", master_vol)
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("look", "skin", _own_skin)
	cfg.set_value("look", "hair", _own_hair)
	cfg.set_value("look", "moustache", _own_moustache)
	cfg.set_value("settings", "portrait", portrait)
	cfg.set_value("daily", "points", grievance_points)
	cfg.set_value("daily", "streak", daily_streak)
	cfg.set_value("daily", "last", _daily_last)
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
	# The boss glares out from behind the title: lower the dim so he reads, and
	# put an angry face on if the character has one, plus a slow menacing lean.
	if _screen_dim != null:
		_screen_dim.color = Color(0.05, 0.03, 0.08, 0.5)
	if rig_anim != null:
		rig_anim.taunt()
	if not _react.is_empty():
		_react_tex = _react[_react.size() - 1]
		_react_time = 999.0        # held glare until the fight starts
	_title_glare()
	_pop_screen()

# A slow head-tracking glare + occasional lean-in on the title screen.
func _title_glare() -> void:
	if rig_anim == null or phase != Phase.TITLE:
		return
	rig_anim.body_rot = 0.0
	var tw := create_tween()
	tw.tween_property(rig_anim, "lean", 0.05, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rig_anim, "lean", -0.03, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_title_glare)      # loops while on the title

# Punchy pop-in for a screen: the title/rows scale up from small with a fade.
func _pop_screen() -> void:
	for node in [_screen_title, _screen_sub, _screen_hint]:
		if node == null:
			continue
		node.pivot_offset = node.size / 2.0
		node.scale = Vector2(0.8, 0.8)
		node.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(node, "modulate:a", 1.0, 0.2)

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
func _start_prefight(free_fight: bool = false) -> void:
	# Starting a normal fight from the menu leaves Endless and clears its scaling.
	_endless = false
	_free_fight = free_fight
	_hp_mul = 1.0
	_dmg_mul = 1.0
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
%s · %s" % [_act_label(level), opponent_name(), String(cfg.get("name", ""))]
	# On a daily run, spell out the modifier so the rule isn't a surprise.
	if _daily_active:
		_screen_hint.text = "DAILY GRIEVANCE — %s\ntap to begin" % _daily_name()
	else:
		_screen_hint.text = "tap to begin"
	var pre: Array = Dia.PREFIGHT.get(level, [])
	if pre.is_empty():
		pre = [String(cfg.get("line", ""))]
	_say(_line("prefight%d" % level, pre))
	if rig_anim != null:
		rig_anim.point_at_player()

func _start_fight(reset_player_hp: bool = true) -> void:
	close_menu()
	phase = Phase.FIGHT
	_set_hud_visible(true)
	boss_line.get_parent().visible = true
	_screen.visible = false
	_screen_dim.color = Color(0.05, 0.03, 0.08, 0.82)
	_ensure_endless_hud()
	_endless_hud.visible = _endless
	if _endless:
		_endless_hud.text = "ROUND %d" % _endless_round
	var cfg := _level_cfg()
	# Daily modifier reshapes this fight (boss/player health, sudden death).
	_daily_oneshot = false
	var php_start := 1.0
	if _daily_active:
		var m := _daily_challenge()
		_hp_mul *= float(m.get("bosshp", 1.0))
		php_start = float(m.get("php", 1.0))
		_daily_oneshot = bool(m.get("oneshot", false))
	hp_max = float(cfg.get("hp", 120.0)) * _hp_mul
	if _shot_mode:
		hp_max = 14.0
	_set_hp(hp_max)
	if reset_player_hp:
		_set_player_hp(player_hp_max * php_start)
	_set_rage(0.0)
	combo = 0
	frenzy = 0.0
	_koing = false
	_enraged = false
	_hits_this_fight = 0
	_fight_damage = 0
	_skill = adapt_baseline      # adaptive difficulty starts from the learned baseline
	_reset_hazard()
	_reset_counter()
	_setup_pump()
	_build_noise_meter()
	_noise = 0.0
	if _noise_bar != null:
		_update_noise_bar()
	_set_noise_visible(_has_shush())
	_build_adren_meter()
	adrenaline = 0.0
	_parry_time = 0.0
	_update_adren_bar()
	# The parry/adrenaline layer only makes sense when the boss actually
	# attacks, so it shows on Brawler punch fights.
	var show_adren := difficulty == Difficulty.BRAWLER and _gimmick() == "punch"
	if _adren_bar != null:
		_adren_bar.get_parent().visible = show_adren
	if _adren_label != null:
		_adren_label.visible = show_adren
	if rig_anim != null:
		rig_anim.revive()
		rig_anim.idle_amp = 1.0
	_start_gimmick()
	set_music_mood(String(_level_cfg().get("mood", "office")))
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
		if _endless and _endless_round > 1 and has_anim("getup"):
			# Endless: the boss you just floored picks himself up for the next
			# round (Blender get-back-up), then the fight begins.
			play_anim("getup", 12.0, _enter_guard)
		elif has_anim("charge"):
			# Hand-drawn charge intro (from the uploaded video). It plays once,
			# then the fight begins on the callback.
			play_anim("charge", 12.0, _enter_guard)
		elif has_pose("walk"):
			play_entrance()
			_enter_guard()
		else:
			_enter_guard()

func _show_gameover(won: bool) -> void:
	# Endless can only end on a loss (a win rolls into the next round), so an
	# Endless gameover reports how far the survival run got.
	var was_endless := _endless
	var was_daily := _daily_active
	var rounds := _endless_round
	if won:
		_complete_daily(_hits_this_fight == 0)
	else:
		_daily_active = false
	_endless = false
	_hp_mul = 1.0
	_dmg_mul = 1.0
	# Grievance points from regular play too, so the rank ladder isn't gated on
	# the once-a-day challenge. (The daily grants its own via _complete_daily.)
	var griev := 0
	if won and not was_endless and not was_daily:
		griev = 10 + level * 3
		if _hits_this_fight == 0:
			griev *= 2                         # flawless bonus
	elif was_endless:
		griev = rounds * 8                     # reward the survival run on its loss
	if griev > 0:
		_grant_grievance(griev)
	# Fold this fight's skill read into the long-term baseline (Brawler only).
	if _adaptive_on():
		adapt_baseline = clampf(lerpf(adapt_baseline, _skill, 0.3), 0.0, 1.0)
	_check_awards()                            # rank-point awards can trip here
	if _endless_hud != null:
		_endless_hud.visible = false
	close_menu()
	phase = Phase.VICTORY if won else Phase.GAMEOVER
	best_score = maxi(best_score, score)
	_save_prefs()
	_set_hud_visible(false)
	boss_line.get_parent().visible = false
	_screen.visible = true
	if was_endless:
		_screen_title.text = "SURVIVED %d" % rounds
		_screen_title.offset_top = 180.0
		_screen_title.offset_bottom = 340.0
		_screen_sub.text = "You lasted %d round%s.\nbest run %d      score %d" % \
			[rounds, "" if rounds == 1 else "s", stat_endless_best, score]
		_screen_hint.text = "tap to continue"
		return
	_screen_title.text = "YOU WIN" if won else "YOU'RE FIRED"
	_screen_title.offset_top = 180.0
	_screen_title.offset_bottom = 340.0
	var sub := "SCORE %d      BEST %d\nmax combo %d      crits %d" % [score, best_score, max_combo, crits]
	if griev > 0:
		sub += "\n+%d grievance   ·   %s" % [griev, _rank_title()]
	_screen_sub.text = sub
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
	# Free fight can force a plain boxing match regardless of the arena's gimmick.
	if _free_fight and not free_use_gimmick:
		return "punch"
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
	if not _react.is_empty():
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
	if not _react.is_empty():
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
			"react": ["hurt0", "hurt1", "hurt2", "hurt3", "shock", "worried", "dizzy0"],
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
	"man": {
		"dir": "res://assets/boss4/parts",
		"scale": 1.21901, "ox": 47.89, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"bones": {
			"Hip": Vector2(260, 743),
			"Spine": Vector2(0, -195),
			"Chest": Vector2(0, -91),
			"Head": Vector2(0, -91),
			"ArmL": Vector2(-139, -293),
			"ForearmL": Vector2(-15, 158),
			"FistL": Vector2(-5, 183),
			"ArmR": Vector2(139, -293),
			"ForearmR": Vector2(15, 158),
			"FistR": Vector2(2, 183),
			"ThighL": Vector2(-41, 85),
			"ShinL": Vector2(-34, 207),
			"FootL": Vector2(-7, 134),
			"ThighR": Vector2(46, 85),
			"ShinR": Vector2(37, 207),
			"FootR": Vector2(7, 134),
		},
		"parts": [
			["foot_l",  "Hip/ThighL/ShinL/FootL", Vector2(0, 876), Vector2(106, 910), 0],
			["foot_r",  "Hip/ThighR/ShinR/FootR", Vector2(170, 876), Vector2(248, 910), 0],
			["shin_l",  "Hip/ThighL/ShinL", Vector2(50, 756), Vector2(112, 800), 1],
			["shin_r",  "Hip/ThighR/ShinR", Vector2(170, 756), Vector2(242, 800), 1],
			["thigh_l", "Hip/ThighL", Vector2(2, 596), Vector2(140, 630), 2],
			["thigh_r", "Hip/ThighR", Vector2(170, 596), Vector2(212, 630), 2],
			["hips",    "Hip", Vector2(9, 516), Vector2(174, 560), 3],
			["torso",   "Hip/Spine", Vector2(10, 296), Vector2(174, 400), 4],
			["uarm_l",  "Hip/ArmL", Vector2(25, 409), Vector2(60, 320), 5],
			["uarm_r",  "Hip/ArmR", Vector2(225, 412), Vector2(288, 320), 5],
			["farm_l",  "Hip/ArmL/ForearmL", Vector2(10, 426), Vector2(48, 450), 6],
			["farm_r",  "Hip/ArmR/ForearmR", Vector2(225, 426), Vector2(300, 450), 6],
			["hand_l",  "Hip/ArmL/ForearmL/FistL", Vector2(2, 556), Vector2(44, 600), 7],
			["hand_r",  "Hip/ArmR/ForearmR/FistR", Vector2(229, 556), Vector2(302, 600), 7],
			["head",    "Hip/Spine/Chest/Head", Vector2(92, 0), Vector2(174, 250), 8],
		],
	},
	"swim": {
		"dir": "res://assets/boss5/parts",
		"scale": 1.22789, "ox": 59.24, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"bones": {
			"Hip": Vector2(243, 821),
			"Spine": Vector2(0, -184),
			"Chest": Vector2(0, -104),
			"Head": Vector2(0, -104),
			"ArmL": Vector2(-135, -184),
			"ForearmL": Vector2(-10, 111),
			"FistL": Vector2(-2, 123),
			"ArmR": Vector2(147, -184),
			"ForearmR": Vector2(2, 111),
			"FistR": Vector2(10, 123),
			"ThighL": Vector2(-47, 86),
			"ShinL": Vector2(-5, 135),
			"FootL": Vector2(-10, 129),
			"ThighR": Vector2(49, 86),
			"ShinR": Vector2(39, 135),
			"FootR": Vector2(20, 129),
		},
		"parts": [
			["foot_l",  "Hip/ThighL/ShinL/FootL", Vector2(22, 880), Vector2(100, 905), 0],
			["foot_r",  "Hip/ThighR/ShinR/FootR", Vector2(193, 880), Vector2(238, 905), 0],
			["shin_l",  "Hip/ThighL/ShinL", Vector2(64, 790), Vector2(108, 800), 1],
			["shin_r",  "Hip/ThighR/ShinR", Vector2(189, 790), Vector2(222, 800), 1],
			["thigh_l", "Hip/ThighL", Vector2(12, 655), Vector2(112, 690), 2],
			["thigh_r", "Hip/ThighR", Vector2(151, 655), Vector2(190, 690), 2],
			["hips",    "Hip", Vector2(12, 580), Vector2(150, 620), 3],
			["torso",   "Hip/Spine", Vector2(18, 400), Vector2(150, 470), 4],
			["uarm_l",  "Hip/ArmL", Vector2(13, 448), Vector2(40, 470), 5],
			["uarm_r",  "Hip/ArmR", Vector2(233, 485), Vector2(270, 470), 5],
			["farm_l",  "Hip/ArmL/ForearmL", Vector2(11, 540), Vector2(32, 560), 6],
			["farm_r",  "Hip/ArmR/ForearmR", Vector2(167, 635), Vector2(272, 560), 6],
			["hand_l",  "Hip/ArmL/ForearmL/FistL", Vector2(11, 665), Vector2(30, 660), 7],
			["hand_r",  "Hip/ArmR/ForearmR/FistR", Vector2(172, 640), Vector2(280, 660), 7],
			["head",    "Hip/Spine/Chest/Head", Vector2(0, 0), Vector2(150, 300), 8],
		],
	},
	"suit_w": {
		"dir": "res://assets/boss6/parts",
		"scale": 1.15460, "ox": -98.50, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"bones": {
			"Hip": Vector2(259, 799),
			"Spine": Vector2(0, -196),
			"Chest": Vector2(0, -98),
			"Head": Vector2(0, -98),
			"ArmL": Vector2(-254, -196),
			"ForearmL": Vector2(-35, 139),
			"FistL": Vector2(-12, 115),
			"ArmR": Vector2(254, -196),
			"ForearmR": Vector2(35, 139),
			"FistR": Vector2(12, 115),
			"ThighL": Vector2(-81, 115),
			"ShinL": Vector2(-12, 150),
			"FootL": Vector2(-12, 104),
			"ThighR": Vector2(81, 115),
			"ShinR": Vector2(12, 150),
			"FootR": Vector2(12, 104),
		},
		"parts": [
			["foot_l", "Hip/ThighL/ShinL/FootL", Vector2(139, 910), Vector2(220, 960), 0],
			["foot_r", "Hip/ThighR/ShinR/FootR", Vector2(345, 908), Vector2(400, 960), 0],
			["shin_l", "Hip/ThighL/ShinL", Vector2(173, 826), Vector2(230, 870), 1],
			["shin_r", "Hip/ThighR/ShinR", Vector2(307, 826), Vector2(390, 870), 1],
			["thigh_l", "Hip/ThighL", Vector2(1, 676), Vector2(240, 740), 2],
			["thigh_r", "Hip/ThighR", Vector2(307, 676), Vector2(380, 740), 2],
			["hips", "Hip", Vector2(14, 536), Vector2(310, 640), 3],
			["torso", "Hip/Spine", Vector2(14, 376), Vector2(310, 470), 4],
			["uarm_l", "Hip/ArmL", Vector2(11, 416), Vector2(90, 470), 5],
			["uarm_r", "Hip/ArmR", Vector2(312, 416), Vector2(530, 470), 5],
			["farm_l", "Hip/ArmL/ForearmL", Vector2(0, 516), Vector2(60, 590), 6],
			["farm_r", "Hip/ArmR/ForearmR", Vector2(315, 516), Vector2(560, 590), 6],
			["hand_l", "Hip/ArmL/ForearmL/FistL", Vector2(0, 626), Vector2(50, 690), 7],
			["hand_r", "Hip/ArmR/ForearmR/FistR", Vector2(523, 626), Vector2(570, 690), 7],
			["head", "Hip/Spine/Chest/Head", Vector2(22, 0), Vector2(310, 300), 8],
		],
	},
	"suit_w2": {
		"dir": "res://assets/boss7/parts",
		"scale": 1.15347, "ox": -99.31, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"faces": {"dir": "res://assets/boss7/heads", "anchor": Vector2(280, 470),
			"react": ["hurt0", "dizzy0"], "angry": ["angry0"]},
		"bones": {
			"Hip": Vector2(259, 798),
			"Spine": Vector2(0, -196),
			"Chest": Vector2(0, -98),
			"Head": Vector2(0, -98),
			"ArmL": Vector2(-255, -196),
			"ForearmL": Vector2(-35, 138),
			"FistL": Vector2(-12, 115),
			"ArmR": Vector2(255, -196),
			"ForearmR": Vector2(35, 138),
			"FistR": Vector2(12, 115),
			"ThighL": Vector2(-81, 115),
			"ShinL": Vector2(-12, 150),
			"FootL": Vector2(-12, 104),
			"ThighR": Vector2(81, 115),
			"ShinR": Vector2(12, 150),
			"FootR": Vector2(12, 104),
		},
		"parts": [
			["foot_l", "Hip/ThighL/ShinL/FootL", Vector2(140, 906), Vector2(221, 960), 0],
			["foot_r", "Hip/ThighR/ShinR/FootR", Vector2(346, 906), Vector2(401, 960), 0],
			["shin_l", "Hip/ThighL/ShinL", Vector2(170, 826), Vector2(231, 870), 1],
			["shin_r", "Hip/ThighR/ShinR", Vector2(308, 826), Vector2(391, 870), 1],
			["thigh_l", "Hip/ThighL", Vector2(131, 676), Vector2(241, 740), 2],
			["thigh_r", "Hip/ThighR", Vector2(308, 676), Vector2(381, 740), 2],
			["hips", "Hip", Vector2(15, 536), Vector2(311, 640), 3],
			["torso", "Hip/Spine", Vector2(10, 376), Vector2(311, 470), 4],
			["uarm_l", "Hip/ArmL", Vector2(11, 416), Vector2(90, 470), 5],
			["uarm_r", "Hip/ArmR", Vector2(480, 416), Vector2(532, 470), 5],
			["farm_l", "Hip/ArmL/ForearmL", Vector2(0, 555), Vector2(60, 590), 6],
			["farm_r", "Hip/ArmR/ForearmR", Vector2(480, 555), Vector2(562, 590), 6],
			["hand_l", "Hip/ArmL/ForearmL/FistL", Vector2(0, 626), Vector2(50, 690), 7],
			["hand_r", "Hip/ArmR/ForearmR/FistR", Vector2(524, 626), Vector2(572, 690), 7],
		],
	},
	"tank_w": {
		"dir": "res://assets/boss8/parts",
		"scale": 1.16142, "ox": -105.85, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"bones": {
			"Hip": Vector2(260, 803),
			"Spine": Vector2(0, -197),
			"Chest": Vector2(0, -99),
			"Head": Vector2(0, -99),
			"ArmL": Vector2(-285, -93),
			"ForearmL": Vector2(-23, 116),
			"FistL": Vector2(-6, 70),
			"ArmR": Vector2(285, -93),
			"ForearmR": Vector2(23, 116),
			"FistR": Vector2(6, 70),
			"ThighL": Vector2(-116, 139),
			"ShinL": Vector2(0, 128),
			"FootL": Vector2(-6, 105),
			"ThighR": Vector2(116, 139),
			"ShinR": Vector2(0, 128),
			"FootR": Vector2(6, 105),
		},
		"parts": [
			["foot_l", "Hip/ThighL/ShinL/FootL", Vector2(139, 906), Vector2(210, 960), 0],
			["foot_r", "Hip/ThighR/ShinR/FootR", Vector2(343, 906), Vector2(420, 960), 0],
			["shin_l", "Hip/ThighL/ShinL", Vector2(154, 826), Vector2(215, 870), 1],
			["shin_r", "Hip/ThighR/ShinR", Vector2(339, 826), Vector2(415, 870), 1],
			["thigh_l", "Hip/ThighL", Vector2(0, 686), Vector2(215, 760), 2],
			["thigh_r", "Hip/ThighR", Vector2(312, 686), Vector2(415, 760), 2],
			["hips", "Hip", Vector2(13, 536), Vector2(315, 640), 3],
			["torso", "Hip/Spine", Vector2(13, 376), Vector2(315, 470), 4],
			["uarm_l", "Hip/ArmL", Vector2(11, 556), Vector2(70, 560), 5],
			["uarm_r", "Hip/ArmR", Vector2(483, 557), Vector2(560, 560), 5],
			["farm_l", "Hip/ArmL/ForearmL", Vector2(0, 596), Vector2(50, 660), 6],
			["farm_r", "Hip/ArmR/ForearmR", Vector2(520, 596), Vector2(580, 660), 6],
			["hand_l", "Hip/ArmL/ForearmL/FistL", Vector2(0, 686), Vector2(45, 720), 7],
			["hand_r", "Hip/ArmR/ForearmR/FistR", Vector2(313, 686), Vector2(585, 720), 7],
			["head", "Hip/Spine/Chest/Head", Vector2(13, 0), Vector2(315, 300), 8],
		],
	},
	"tank_w2": {
		"dir": "res://assets/boss9/parts",
		"scale": 1.16601, "ox": -117.20, "oy": 60.0,
		"customisable": false,
		"arm_gain": 1.0,
		"faces": {"dir": "res://assets/boss9/heads", "anchor": Vector2(280, 470),
			"react": ["dizzy0"], "angry": ["angry0"]},
		"bones": {
			"Hip": Vector2(259, 818),
			"Spine": Vector2(0, -198),
			"Chest": Vector2(0, -105),
			"Head": Vector2(0, -105),
			"ArmL": Vector2(-293, -93),
			"ForearmL": Vector2(-23, 117),
			"FistL": Vector2(-7, 70),
			"ArmR": Vector2(294, -93),
			"ForearmR": Vector2(23, 117),
			"FistR": Vector2(6, 70),
			"ThighL": Vector2(-120, 140),
			"ShinL": Vector2(0, 128),
			"FootL": Vector2(-6, 105),
			"ThighR": Vector2(119, 140),
			"ShinR": Vector2(0, 128),
			"FootR": Vector2(6, 105),
		},
		"parts": [
			["foot_l", "Hip/ThighL/ShinL/FootL", Vector2(147, 916), Vector2(215, 970), 0],
			["foot_r", "Hip/ThighR/ShinR/FootR", Vector2(357, 916), Vector2(430, 970), 0],
			["shin_l", "Hip/ThighL/ShinL", Vector2(167, 836), Vector2(220, 880), 1],
			["shin_r", "Hip/ThighR/ShinR", Vector2(348, 836), Vector2(425, 880), 1],
			["thigh_l", "Hip/ThighL", Vector2(0, 696), Vector2(220, 770), 2],
			["thigh_r", "Hip/ThighR", Vector2(320, 696), Vector2(425, 770), 2],
			["hips", "Hip", Vector2(3, 546), Vector2(323, 650), 3],
			["torso", "Hip/Spine", Vector2(3, 386), Vector2(323, 480), 4],
			["uarm_l", "Hip/ArmL", Vector2(3, 556), Vector2(72, 570), 5],
			["uarm_r", "Hip/ArmR", Vector2(503, 556), Vector2(575, 570), 5],
			["farm_l", "Hip/ArmL/ForearmL", Vector2(0, 606), Vector2(52, 670), 6],
			["farm_r", "Hip/ArmR/ForearmR", Vector2(326, 606), Vector2(595, 670), 6],
			["hand_l", "Hip/ArmL/ForearmL/FistL", Vector2(0, 696), Vector2(46, 730), 7],
			["hand_r", "Hip/ArmR/ForearmR/FistR", Vector2(326, 696), Vector2(600, 730), 7],
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
		if cfg.has("faces"):
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

func _char_root() -> String:
	# e.g. "res://assets/boss4/parts" -> "res://assets/boss4"
	var d := String(CHARS[character].get("dir", "res://assets/boss2/parts"))
	return d.get_base_dir()

func _pose_dir() -> String:
	return "%s/poses" % _char_root()

func has_pose(name: String) -> bool:
	return ResourceLoader.exists("%s/%s.png" % [_pose_dir(), name])

# Full-body knocked-out art (lying on the floor). Closes the floored-KO gap:
# characters with this show it on the ground during the K.O. beat instead of
# the generic offscreen launch.
func has_ko() -> bool:
	return ResourceLoader.exists("%s/ko/ko.png" % _char_root())

# Drop the KO art onto the floor, centred low, for the knocked-out beat.
func _show_ko_floor() -> void:
	var path := "%s/ko/ko.png" % _char_root()
	if not ResourceLoader.exists(path):
		return
	if _pose_spr == null:
		_pose_spr = Sprite2D.new()
		_pose_spr.centered = false
		_pose_spr.z_index = 20
		_pose_spr.material = _outline_mat
		rig.add_child(_pose_spr)
	_pose_name = "@ko"
	_anim_playing = false
	if _pose_fade_tw != null and _pose_fade_tw.is_valid():
		_pose_fade_tw.kill()
	_pose_spr.modulate.a = 1.0
	_set_rig_visible(false)
	var tex: Texture2D = load(path)
	_pose_spr.texture = tex
	# A figure lying spread out on the ground: scale it modestly and CENTRE it
	# on the office floor line, rather than treating it as a standing figure
	# (which shot it up past the top of the screen).
	var sc := 720.0 / float(tex.get_width())
	_pose_spr.scale = Vector2(sc, sc)
	_pose_spr.position = Vector2(260.0 - tex.get_width() * sc * 0.5,
		1010.0 - tex.get_height() * sc * 0.5)
	_pose_spr.visible = true

func set_pose(name: String) -> void:
	# Clearing must ALWAYS enforce the handoff, never short-circuit on _pose_name:
	# an anim/KO handoff can leave _pose_name desynced from what's actually drawn,
	# and a no-op here is exactly what left a stale pose sprite on top of the rig.
	if name == "":
		_pose_name = ""
		# Cancel any playing intro/anim: otherwise _update_anim re-shows _pose_spr
		# every frame and it draws on top of the now-visible rig (two bosses).
		_anim_playing = false
		_set_rig_visible(true)
		# Crossfade the outgoing pose/anim frame out over the now-visible rig, so
		# the system handoff (intro->fight, KO->recover, pose->rig) dissolves
		# instead of hard-cutting. Only when a pose sprite was actually up.
		if _pose_spr != null and is_instance_valid(_pose_spr) and _pose_spr.visible:
			_crossfade_pose_out()
		return
	if name == _pose_name:
		return
	if not has_pose(name):
		return                      # character has no art for this pose
	_pose_name = name
	# Cancel any in-flight fade-out and restore full alpha; this pose reuses the
	# same sprite and must not inherit a half-faded state.
	if _pose_fade_tw != null and _pose_fade_tw.is_valid():
		_pose_fade_tw.kill()
	if _pose_spr == null:
		_pose_spr = Sprite2D.new()
		_pose_spr.centered = false
		_pose_spr.z_index = 20
		_pose_spr.material = _outline_mat
		rig.add_child(_pose_spr)
	_pose_spr.modulate.a = 1.0
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

var _pose_fade_tw: Tween

# Dissolve the pose sprite out over the rig that's now showing underneath. Kills
# any in-flight fade first so rapid handoffs don't fight, and always restores the
# sprite's alpha to 1 when done (a later pose reuses the same sprite).
func _crossfade_pose_out() -> void:
	if _pose_spr == null or not is_instance_valid(_pose_spr):
		return
	if _pose_fade_tw != null and _pose_fade_tw.is_valid():
		_pose_fade_tw.kill()
	var spr := _pose_spr
	spr.modulate.a = 1.0
	_pose_fade_tw = create_tween()
	_pose_fade_tw.tween_property(spr, "modulate:a", 0.0, 0.12)
	_pose_fade_tw.tween_callback(func() -> void:
		if is_instance_valid(spr):
			spr.visible = false
			spr.modulate.a = 1.0)

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
const MENU_ROW_H := 82.0
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
	# Punchy pop-in: the whole menu scales up from small with a quick fade.
	_menu.pivot_offset = Vector2(960, 540)
	_menu.scale = Vector2(0.92, 0.92)
	_menu.modulate.a = 0.0
	var pop := create_tween()
	pop.tween_property(_menu, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.parallel().tween_property(_menu, "modulate:a", 1.0, 0.16)
	_clear_rows()
	_menu_rows.add_theme_constant_override("separation", 12)
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
		Phase.AWARDS:
			_populate_awards()
		Phase.STATS:
			_populate_stats()
		Phase.FREEFIGHT:
			_populate_freefight()

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
	var en_label := "ENDLESS SURVIVAL"
	if stat_endless_best > 0:
		en_label += "   (best: round %d)" % stat_endless_best
	var en := _menu_button(en_label, Color(0.86, 0.42, 0.16))
	en.pressed.connect(_start_endless)
	_menu_rows.add_child(en)
	var ff := _menu_button("FREE FIGHT", Color(0.24, 0.60, 0.55))
	ff.pressed.connect(func() -> void: open_menu(Phase.FREEFIGHT))
	_menu_rows.add_child(ff)
	# Daily grievance: one challenge a day. Shows "done" once claimed.
	if _daily_done_today():
		var dg := _menu_button("DAILY GRIEVANCE  -  DONE  (streak %d)" % daily_streak,
			Color(0.28, 0.30, 0.36))
		dg.disabled = true
		_menu_rows.add_child(dg)
	else:
		var dg := _menu_button("DAILY: %s  (Lv %d)" % [_daily_name(), _daily_level()],
			Color(0.86, 0.32, 0.30))
		dg.pressed.connect(_start_daily)
		_menu_rows.add_child(dg)
	var cu := _menu_button("CUSTOMISE YOUR BOSS", Color(0.62, 0.28, 0.72))
	cu.pressed.connect(func() -> void: open_menu(Phase.CUSTOMIZE))
	_menu_rows.add_child(cu)
	var aw := _menu_button("AWARDS   (%d / %d)" % [awards_earned.size(), ACHIEVEMENTS.size()],
		Color(0.82, 0.55, 0.12))
	aw.pressed.connect(func() -> void: open_menu(Phase.AWARDS))
	_menu_rows.add_child(aw)
	var stx := _menu_button("YOUR RECORD", Color(0.20, 0.55, 0.62))
	stx.pressed.connect(func() -> void: open_menu(Phase.STATS))
	_menu_rows.add_child(stx)
	var op := _menu_button("OPTIONS", Color(0.35, 0.33, 0.42))
	op.pressed.connect(func() -> void: open_menu(Phase.OPTIONS))
	_menu_rows.add_child(op)
	# Rank/points footer moved to the YOUR RECORD screen: with 8 buttons a footer
	# would push the list past the 1080 canvas (and off a portrait phone).

func _on_play() -> void:
	close_menu()
	_start_prefight()

# --- free fight picker ------------------------------------------------------
func _ff_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.95))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 44)
	return l

# A compact, selectable grid cell (selected = green, else the given colour).
func _ff_cell(text: String, selected: bool, w: float, base: Color) -> Button:
	var b := _menu_button(text, Color(0.20, 0.70, 0.25) if selected else base)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(w, 54)
	b.clip_text = true
	return b

func _populate_freefight() -> void:
	_menu_title.text = "FREE FIGHT"
	_menu_rows.offset_top = 170.0
	_menu_rows.add_child(_ff_label("OPPONENT"))
	var cgrid := GridContainer.new()
	cgrid.columns = 4
	cgrid.add_theme_constant_override("h_separation", 14)
	cgrid.add_theme_constant_override("v_separation", 8)
	_menu_rows.add_child(cgrid)
	for entry in FREE_CHARS:
		var key := String(entry[0])
		var cell := _ff_cell(String(entry[1]), key == free_char, 250.0, Color(0.24, 0.34, 0.52))
		cell.pressed.connect(func() -> void:
			free_char = key
			open_menu(Phase.FREEFIGHT))
		cgrid.add_child(cell)
	_menu_rows.add_child(_ff_label("ARENA"))
	var agrid := GridContainer.new()
	agrid.columns = 5
	agrid.add_theme_constant_override("h_separation", 12)
	agrid.add_theme_constant_override("v_separation", 8)
	_menu_rows.add_child(agrid)
	for i in range(LEVELS.size()):
		var n := i + 1
		var nm := "%d. %s" % [n, String((LEVELS[i] as Dictionary).get("name", ""))]
		var cell := _ff_cell(nm, n == free_arena, 205.0, Color(0.30, 0.28, 0.40))
		cell.pressed.connect(func() -> void:
			free_arena = n
			open_menu(Phase.FREEFIGHT))
		agrid.add_child(cell)
	var gim := _menu_button("ARENA GIMMICK:  %s" % ("ON" if free_use_gimmick else "OFF"),
		Color(0.20, 0.70, 0.25) if free_use_gimmick else Color(0.35, 0.33, 0.42))
	gim.add_theme_font_size_override("font_size", 30)
	gim.custom_minimum_size = Vector2(0, 66)
	gim.pressed.connect(func() -> void:
		free_use_gimmick = not free_use_gimmick
		open_menu(Phase.FREEFIGHT))
	_menu_rows.add_child(gim)
	var go := _menu_button("FIGHT!  %s  in  %s" % [_free_char_name(free_char),
		String((LEVELS[free_arena - 1] as Dictionary).get("name", ""))], Color(0.82, 0.2, 0.18))
	go.add_theme_font_size_override("font_size", 34)
	go.pressed.connect(_start_free_fight)
	_menu_rows.add_child(go)

func _start_free_fight() -> void:
	level = clampi(free_arena, 1, LEVELS.size())
	_save_prefs()
	_start_prefight(true)

func _populate_levels() -> void:
	_menu_title.text = "LEVEL SELECT"
	_menu_rows.offset_top = 180.0
	# Two-column grid: with 20+ levels a single column overflows the screen, so
	# lay them out in columns of ~10. Each cell is a fixed-width level button.
	var grid := GridContainer.new()
	var rows_per_col := 10
	grid.columns = int(ceil(float(LEVELS.size()) / float(rows_per_col)))
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	_menu_rows.add_child(grid)
	# Fill column-major so 1-10 are the left column, 11-20 the right.
	var order: Array = []
	for c in grid.columns:
		for rr in rows_per_col:
			var idx := c * rows_per_col + rr
			if idx < LEVELS.size():
				order.append(idx)
	for i in order:
		var n := int(i) + 1
		var cfg: Dictionary = LEVELS[int(i)]
		var who := "Your Boss"
		var r: Dictionary = ROSTER.get(n, {})
		if not r.is_empty():
			who = String(r.get("who", who))
		var locked := n > unlocked
		var label := "%d. %s" % [n, String(cfg.get("name", ""))]
		if locked:
			label = "%d.  LOCKED" % n
		# Unlocked levels take their act's colour, so the four career acts read as
		# coloured bands down the list; current level stays green, locked stays dim.
		var col := _act_color(n)
		if locked:
			col = Color(0.17, 0.16, 0.21)
		elif n == level:
			col = Color(0.20, 0.70, 0.25)
		var b := _menu_button(label, col)
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size = Vector2(540, 60)
		b.tooltip_text = "%s — %s" % [_act_label(n), who]
		b.disabled = locked
		if not locked:
			b.pressed.connect(_on_pick_level.bind(n))
		grid.add_child(b)

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

func _populate_awards() -> void:
	_menu_title.text = "AWARDS"
	_menu_rows.offset_top = 180.0
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	_menu_rows.add_child(grid)
	for a in ACHIEVEMENTS:
		var got: bool = awards_earned.has(a["id"])
		# Earned: gold with the title. Locked: dim with the how-to.
		var label := ("* %s" % a["title"]) if got else ("- %s" % a["desc"])
		var col := Color(0.82, 0.55, 0.12) if got else Color(0.20, 0.19, 0.24)
		var b := _menu_button(label, col)
		b.add_theme_font_size_override("font_size", 24)
		b.custom_minimum_size = Vector2(540, 62)
		b.disabled = true
		if got:
			b.tooltip_text = String(a["desc"])
		grid.add_child(b)

func _populate_stats() -> void:
	_menu_title.text = "YOUR RECORD"
	_menu_rows.offset_top = 200.0
	# The stress-relief scoreboard: lifetime totals that feed the fantasy
	# directly. One card per stat, two columns.
	var rows := [
		["Rank", _rank_title()],
		["Grievance points", "%d" % grievance_points],
		["Daily streak", "%d day%s" % [daily_streak, "" if daily_streak == 1 else "s"]],
		["Endless best", "round %d" % stat_endless_best],
		["Bosses knocked out", "%d" % stat_kos],
		["Bosses fired", "%d" % stat_fired],
		["Total punches thrown", "%d" % stat_punches],
		["Total damage dealt", "%d" % stat_damage],
		["Boss's worst day", "%d in one fight" % stat_worst_day],
		["Longest combo", "%dx" % stat_best_combo],
		["Critical hits", "%d" % _crit_total],
		["Best score", "%d" % best_score],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	_menu_rows.add_child(grid)
	for r in rows:
		var name_lbl := Label.new()
		name_lbl.text = String(r[0])
		name_lbl.add_theme_font_size_override("font_size", 34)
		name_lbl.add_theme_color_override("font_color", Color(0.72, 0.76, 0.90))
		name_lbl.custom_minimum_size = Vector2(560, 54)
		grid.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = String(r[1])
		val_lbl.add_theme_font_size_override("font_size", 34)
		val_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.custom_minimum_size = Vector2(360, 54)
		grid.add_child(val_lbl)

func _populate_options() -> void:
	_menu_title.text = "OPTIONS"
	_menu_rows.add_theme_constant_override("separation", 12)
	var mus := _menu_button("MUSIC:  %s" % ("ON" if music_on else "OFF"),
		Color(0.20, 0.70, 0.25) if music_on else Color(0.35, 0.33, 0.42))
	mus.pressed.connect(_on_toggle_music)
	_menu_rows.add_child(mus)

	_menu_rows.add_child(_make_volume_row())

	var hap := _menu_button("VIBRATION:  %s" % ("ON" if haptics_on else "OFF"),
		Color(0.20, 0.70, 0.25) if haptics_on else Color(0.35, 0.33, 0.42))
	hap.pressed.connect(_on_toggle_haptics)
	_menu_rows.add_child(hap)

	var names := ["PUNCHING BAG", "DEFENSIVE", "BRAWLER"]
	var d := clampi(difficulty, 0, 2)
	var bonus := int(round((DIFF_SCORE_MUL[d] - 1.0) * 100.0))
	var dtext := "DIFFICULTY:  %s" % names[d]
	if bonus > 0:
		dtext += "   (+%d%% score)" % bonus
	var dif := _menu_button(dtext)
	dif.pressed.connect(_on_cycle_difficulty)
	_menu_rows.add_child(dif)

	# Adaptive difficulty toggle - only meaningful on Brawler, but always shown
	# so players know the option exists.
	var adp := _menu_button("SMART BOSS:  %s" % ("ON" if adaptive_enabled else "OFF"),
		Color(0.20, 0.70, 0.25) if adaptive_enabled else Color(0.35, 0.33, 0.42))
	adp.pressed.connect(_on_toggle_adaptive)
	_menu_rows.add_child(adp)

	var howto := _menu_button("HOW TO PLAY", Color(0.20, 0.55, 0.62))
	howto.pressed.connect(func() -> void: _show_howto(false))
	_menu_rows.add_child(howto)

	var reset := _menu_button("RESET PROGRESS", Color(0.72, 0.26, 0.24))
	reset.pressed.connect(_on_reset_progress)
	_menu_rows.add_child(reset)
	# (No footer hint here: the bottom-anchored BACK button would overlap it.
	# SMART BOSS / DIFFICULTY labels are self-explanatory enough.)

func _on_toggle_music() -> void:
	toggle_music()
	open_menu(Phase.OPTIONS)

func _on_toggle_haptics() -> void:
	haptics_on = not haptics_on
	_save_prefs()
	open_menu(Phase.OPTIONS)

var _vol_pct: Label

# A real draggable volume slider (label + HSlider + live %). Applies live while
# dragging; persists on drag-end so we don't hammer the save file every frame.
func _make_volume_row() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, MENU_ROW_H)
	row.add_theme_constant_override("separation", 24)
	var lbl := Label.new()
	lbl.text = "VOLUME"
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(300, MENU_ROW_H)
	row.add_child(lbl)
	var sld := HSlider.new()
	sld.min_value = 0.0
	sld.max_value = 1.0
	sld.step = 0.05
	sld.value = master_vol
	sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sld.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sld.custom_minimum_size = Vector2(560, 60)
	sld.value_changed.connect(_on_volume_slide)
	sld.drag_ended.connect(func(_c: bool) -> void: _save_prefs())
	row.add_child(sld)
	_vol_pct = Label.new()
	_vol_pct.text = "%d%%" % int(round(master_vol * 100.0))
	_vol_pct.add_theme_font_size_override("font_size", 40)
	_vol_pct.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_vol_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vol_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vol_pct.custom_minimum_size = Vector2(160, MENU_ROW_H)
	row.add_child(_vol_pct)
	return row

func _on_volume_slide(v: float) -> void:
	master_vol = clampf(v, 0.0, 1.0)
	_apply_volume()
	if _vol_pct != null and is_instance_valid(_vol_pct):
		_vol_pct.text = "%d%%" % int(round(master_vol * 100.0))

func _on_toggle_adaptive() -> void:
	adaptive_enabled = not adaptive_enabled
	_save_prefs()
	open_menu(Phase.OPTIONS)

func _on_reset_progress() -> void:
	_ensure_reset_ui()
	_reset_overlay.visible = true

# Wipe progress/stats/awards/currency but KEEP settings (audio, difficulty,
# haptics, seen_howto). The confirm dialog gates this - an accidental tap here
# would otherwise erase everything.
func _do_reset_progress() -> void:
	best_score = 0
	unlocked = 1
	level = 1
	stat_punches = 0
	stat_damage = 0
	stat_kos = 0
	stat_fired = 0
	stat_best_combo = 0
	stat_worst_day = 0
	stat_endless_best = 0
	_crit_total = 0
	awards_earned.clear()
	grievance_points = 0
	daily_streak = 0
	_daily_last = ""
	adapt_baseline = 0.5
	_save_prefs()
	if _reset_overlay != null:
		_reset_overlay.visible = false
	open_menu(Phase.MENU)

var _reset_overlay: Control

func _ensure_reset_ui() -> void:
	if _reset_overlay != null:
		return
	_reset_overlay = Control.new()
	_reset_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reset_overlay.z_index = 126
	_reset_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_overlay.visible = false
	add_child(_reset_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.08, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reset_overlay.add_child(dim)
	var title := _big_label(72, Color(1, 0.5, 0.4), 0.0)
	title.text = "RESET PROGRESS?"
	title.offset_top = 300.0
	title.offset_bottom = 400.0
	_reset_overlay.add_child(title)
	var body := _big_label(36, Color(0.9, 0.92, 1.0), 0.0)
	body.text = "This clears your levels, stats, awards and\ngrievance points. Settings are kept."
	body.offset_top = 420.0
	body.offset_bottom = 540.0
	_reset_overlay.add_child(body)
	var vb := HBoxContainer.new()
	vb.add_theme_constant_override("separation", 40)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.offset_left = -520.0
	vb.offset_right = 520.0
	vb.offset_top = 580.0
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_reset_overlay.add_child(vb)
	var cancel := _menu_button("CANCEL", Color(0.35, 0.33, 0.42))
	cancel.custom_minimum_size = Vector2(440, MENU_ROW_H)
	cancel.pressed.connect(func() -> void: _reset_overlay.visible = false)
	vb.add_child(cancel)
	var yes := _menu_button("RESET", Color(0.72, 0.26, 0.24))
	yes.custom_minimum_size = Vector2(440, MENU_ROW_H)
	yes.pressed.connect(_do_reset_progress)
	vb.add_child(yes)

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
	return "%s/anim/%s" % [_char_root(), name]

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
	if _pose_fade_tw != null and _pose_fade_tw.is_valid():
		_pose_fade_tw.kill()
	_pose_spr.modulate.a = 1.0
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
			# Hand back to the rig PROPERLY: hide the anim surface and re-show the
			# rig before the callback runs. Previously this only set _pose_name=""
			# and left _pose_spr visible with the last frame, so the rig (re-shown
			# elsewhere) and the frozen anim frame drew at once - the "two bosses"
			# bug. Route through set_pose("") so the clear is enforced in one place.
			set_pose("")
			if _anim_done.is_valid():
				_anim_done.call()
			return
		_show_anim_frame()

# --- awards / achievements --------------------------------------------------
# Office-satire achievement titles, persisted, shown in the AWARDS menu and
# announced with a toast when earned. Conditions are checked at the moments
# that can trip them (a KO, a combo change, a fight won).
const ACHIEVEMENTS := [
	{"id": "first_ko", "title": "Employee of the Month", "desc": "Land your first K.O."},
	{"id": "combo20", "title": "Overachiever", "desc": "Reach a 20-hit combo."},
	{"id": "combo50", "title": "Workplace Hazard", "desc": "Reach a 50-hit combo."},
	{"id": "flawless", "title": "Model Employee", "desc": "Win a fight without being hit."},
	{"id": "brawler", "title": "No Notice Given", "desc": "K.O. a boss on Brawler."},
	{"id": "punches1k", "title": "Repeat Offender", "desc": "Throw 1,000 punches."},
	{"id": "damage10k", "title": "Going Postal", "desc": "Deal 10,000 total damage."},
	{"id": "crits100", "title": "Sharp Elbows", "desc": "Land 100 critical hits."},
	{"id": "roster9", "title": "Corner Office", "desc": "Beat the first nine bosses."},
	{"id": "level20", "title": "Tenured", "desc": "Reach the final level."},
	{"id": "endless5", "title": "Overtime", "desc": "Reach round 5 in Endless Survival."},
	{"id": "endless10", "title": "Unfireable", "desc": "Reach round 10 in Endless Survival."},
	{"id": "streak7", "title": "Grudge Holder", "desc": "Hit a 7-day Daily streak."},
	{"id": "rank_director", "title": "Middle Management", "desc": "Earn 1,000 grievance points."},
	{"id": "rank_vp", "title": "Executive Material", "desc": "Earn 2,400 grievance points."},
	{"id": "parry_first", "title": "Objection!", "desc": "Land a parry."},
	{"id": "super_first", "title": "Adrenaline Junkie", "desc": "Unleash a super punch."},
	{"id": "worst_day", "title": "Their Worst Day", "desc": "Deal 500 damage in one fight."},
]
var awards_earned: Dictionary = {}
var _crit_total: int = 0            # lifetime crits, persisted
var _hits_this_fight: int = 0       # for the flawless check
var _awards_silent: bool = false    # suppress toasts (retroactive grant on load)

func _grant(id: String) -> void:
	if awards_earned.has(id):
		return
	awards_earned[id] = true
	_save_prefs()
	if not _awards_silent:
		_award_toast(id)

func _title_of(id: String) -> String:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return String(a["title"])
	return id

# Check everything whose condition can currently be true. Cheap - runs on the
# events that matter, not every frame.
func _check_awards() -> void:
	if stat_kos >= 1:
		_grant("first_ko")
	if max_combo >= 20 or stat_best_combo >= 20:
		_grant("combo20")
	if max_combo >= 50 or stat_best_combo >= 50:
		_grant("combo50")
	if stat_punches >= 1000:
		_grant("punches1k")
	if stat_damage >= 10000:
		_grant("damage10k")
	if _crit_total >= 100:
		_grant("crits100")
	if unlocked >= 10:      # cleared 9 -> unlocked advanced to 10
		_grant("roster9")
	if unlocked >= 20:
		_grant("level20")
	if stat_endless_best >= 5:
		_grant("endless5")
	if stat_endless_best >= 10:
		_grant("endless10")
	if daily_streak >= 7:
		_grant("streak7")
	if grievance_points >= 1000:
		_grant("rank_director")
	if grievance_points >= 2400:
		_grant("rank_vp")
	if stat_worst_day >= 500:
		_grant("worst_day")

# A sliding office-memo toast that announces the award, then fades.
func _award_toast(id: String) -> void:
	var toast := Panel.new()
	toast.z_index = 98
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -360.0
	toast.offset_right = 360.0
	toast.offset_top = 40.0
	toast.offset_bottom = 168.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.96, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.82, 0.2, 0.18)
	toast.add_theme_stylebox_override("panel", sb)
	safe.add_child(toast)
	var head := Label.new()
	head.text = "* ACHIEVEMENT UNLOCKED *"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.82, 0.2, 0.18))
	head.position = Vector2(28, 16)
	toast.add_child(head)
	var body := Label.new()
	body.text = _title_of(id)
	body.add_theme_font_size_override("font_size", 40)
	body.add_theme_color_override("font_color", Color(0.1, 0.08, 0.12))
	body.position = Vector2(28, 52)
	toast.add_child(body)
	toast.modulate.a = 0.0
	toast.position.y = -60.0
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(toast, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(2.4)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(toast.queue_free)

# --- environmental hazards --------------------------------------------------
# A reusable sweep hazard layered on top of a normal punch fight. On a timer it
# warns, then a themed object sweeps across (I-beam, gurney) or drops (eraser);
# if the player isn't dodging at the strike moment it costs health and the
# combo. One system themes construction / hospital / school. A level opts in
# with a "hazard" dict: {sprite, axis: "h"|"drop", period: [lo,hi], warn, dmg}.
var _hazard_t: float = 0.0
var _hazard_spr: Sprite2D
var _hazard_busy: bool = false

func _hazard_cfg() -> Dictionary:
	return _level_cfg().get("hazard", {})

func _reset_hazard() -> void:
	var h := _hazard_cfg()
	_hazard_busy = false
	if not h.is_empty():
		_hazard_t = randf_range(2.0, 3.5)
	if _hazard_spr != null:
		_hazard_spr.visible = false

func _update_hazard(delta: float) -> void:
	var h := _hazard_cfg()
	if h.is_empty() or _koing or _hazard_busy:
		return
	_hazard_t -= delta
	if _hazard_t <= 0.0:
		_run_hazard(h)

func _run_hazard(h: Dictionary) -> void:
	_hazard_busy = true
	# The university gauntlet passes a "sprites" list and throws a random one
	# each time - so it cycles through every hazard the earlier levels used.
	var sprite := String(h.get("sprite", "ibeam"))
	if h.has("sprites"):
		var pool: Array = h["sprites"]
		sprite = String(pool[randi() % pool.size()])
	var path := "res://assets/hazards/%s.png" % sprite
	if not ResourceLoader.exists(path):
		_reset_hazard()
		return
	if _hazard_spr == null:
		_hazard_spr = Sprite2D.new()
		_hazard_spr.z_index = 30
		safe.add_child(_hazard_spr)
	_hazard_spr.texture = load(path)
	_hazard_spr.visible = true
	# Drops for the tall ones (eraser/projector), sweeps for the rest - unless
	# the config forces an axis.
	var axis := String(h.get("axis", "drop" if sprite in ["eraser", "projector"] else "h"))
	var warn := float(h.get("warn", 0.7))
	# Warning tell: a flashing arrow-word where it will come from.
	var from_left := randf() < 0.5
	_spawn_text(Vector2(960.0, 250.0), "LOOK OUT!", 84, Color(1, 0.3, 0.2))
	_shake(4.0, 0.2)
	await get_tree().create_timer(warn, true, false, true).timeout
	var vw := 1920.0
	var tw := create_tween()
	if axis == "drop":
		_hazard_spr.scale = Vector2(2.4, 2.4)
		_hazard_spr.position = Vector2(randf_range(500.0, 1420.0), -200.0)
		tw.tween_property(_hazard_spr, "position:y", 1160.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_hazard_spr.scale = Vector2(2.2 * (1.0 if from_left else -1.0), 2.2)
		var y := 620.0
		_hazard_spr.position = Vector2(-500.0 if from_left else vw + 500.0, y)
		tw.tween_property(_hazard_spr, "position:x", vw + 500.0 if from_left else -500.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD)
	# Danger check partway through the sweep.
	var hit_delay := 0.14 if axis == "drop" else 0.24
	await get_tree().create_timer(hit_delay, true, false, true).timeout
	# Dodging (any direction) clears a sweep; ducking clears a drop.
	var safe_now := _dodge_time > 0.0
	if not safe_now:
		_flash_screen(0.4)
		_shake(26.0, 0.4)
		_hitstop(0.06)
		_spawn_text(Vector2(960.0, 440.0), "CLONK!", 90, Color(1, 0.3, 0.25))
		combo = 0
		player_hp = maxf(0.0, player_hp - float(h.get("dmg", 12.0)))
		_set_player_hp(player_hp)
		if _crowd_player != null:
			_crowd_player.play()
		if player_hp <= 0.0:
			_game_over()
	else:
		_spawn_text(Vector2(960.0, 420.0), "DODGED!", 72, Color(0.6, 1.0, 0.7))
	await tw.finished
	_hazard_spr.visible = false
	_hazard_t = randf_range(float(h.get("period", [5.0, 8.0])[0]), float(h.get("period", [5.0, 8.0])[1]))
	_hazard_busy = false

# --- library "SHHH!" meter --------------------------------------------------
# Comedy mechanic for the library: every punch is NOISE. The meter fills as you
# pound away and decays when you pause. Max it out and the librarian shushes -
# a piercing SHHH!, your combo resets, and you eat a brief penalty. So the
# library wants controlled, paced aggression rather than a mash.
var _noise: float = 0.0
var _noise_bar: Panel
var _noise_label: Label
const NOISE_MAX := 100.0

func _has_shush() -> bool:
	return bool(_level_cfg().get("shush", false))

func _build_noise_meter() -> void:
	if _noise_bar != null:
		return
	var track := Panel.new()
	track.anchor_left = 1.0
	track.anchor_right = 1.0
	track.offset_left = -430.0
	track.offset_right = -30.0
	track.offset_top = 150.0
	track.offset_bottom = 184.0
	track.z_index = 41
	var track_sb := (ko_fill.get_parent() as Panel).get_theme_stylebox("panel")
	track.add_theme_stylebox_override("panel", track_sb)
	safe.add_child(track)
	_noise_bar = Panel.new()
	_noise_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_noise_bar.anchor_right = 0.0
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.95, 0.35, 0.2)
	fill_sb.set_corner_radius_all(13)
	_noise_bar.add_theme_stylebox_override("panel", fill_sb)
	track.add_child(_noise_bar)
	_noise_label = Label.new()
	_noise_label.text = "NOISE"
	_noise_label.add_theme_font_size_override("font_size", 24)
	_noise_label.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	_noise_label.add_theme_constant_override("outline_size", 8)
	_noise_label.anchor_left = 1.0
	_noise_label.anchor_right = 1.0
	_noise_label.offset_left = -430.0
	_noise_label.offset_right = -300.0
	_noise_label.offset_top = 116.0
	safe.add_child(_noise_label)
	_noise_bar.get_parent().visible = false
	_noise_label.visible = false

func _set_noise_visible(v: bool) -> void:
	if _noise_bar != null:
		_noise_bar.get_parent().visible = v
	if _noise_label != null:
		_noise_label.visible = v

func _add_noise(amount: float) -> void:
	if not _has_shush() or _koing:
		return
	_noise = clampf(_noise + amount, 0.0, NOISE_MAX)
	_update_noise_bar()
	if _noise >= NOISE_MAX:
		_librarian_shush()

func _update_noise_bar() -> void:
	if _noise_bar != null:
		_noise_bar.anchor_right = _noise / NOISE_MAX
		_noise_bar.offset_right = 0.0
		var m := _noise / NOISE_MAX
		var sb := _noise_bar.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.bg_color = Color(0.5, 0.8, 0.3).lerp(Color(1.0, 0.2, 0.15), m)

func _update_noise(delta: float) -> void:
	if not _has_shush() or _koing:
		return
	if _noise > 0.0:
		_noise = maxf(0.0, _noise - 22.0 * delta)   # quiets down when you pause
		_update_noise_bar()

func _librarian_shush() -> void:
	_noise = 0.0
	_update_noise_bar()
	combo = 0
	_flash_screen(0.5)
	_shake(20.0, 0.5)
	_spawn_text(Vector2(960.0, 320.0), "SHHH!!", 150, Color(0.95, 0.35, 0.2))
	_say("This is a LIBRARY. Use your INSIDE fists.")
	# Brief penalty window: punches don't land while you're being shushed.
	_punch_cd = 1.1
	player_hp = maxf(0.0, player_hp - 6.0)
	_set_player_hp(player_hp)
	if player_hp <= 0.0:
		_game_over()

# --- parry + adrenaline + super ---------------------------------------------
func _parry() -> void:
	if _koing or phase != Phase.FIGHT:
		return
	_parry_time = PARRY_WINDOW
	# A quick flash of the guard pose reads as the attempt.
	if rig_anim != null:
		rig_anim.body_scale = Vector2(0.06, 0.06)
		var tw := create_tween()
		tw.tween_property(rig_anim, "body_scale", Vector2.ZERO, 0.16)
	if _dodge_player != null:
		_dodge_player.pitch_scale = 1.5
		_dodge_player.play()

func _add_adrenaline(amount: float) -> void:
	adrenaline = clampf(adrenaline + amount, 0.0, ADREN_MAX)
	_update_adren_bar()
	if adrenaline >= ADREN_MAX:
		_spawn_text(Vector2(960.0, 560.0), "SUPER READY!", 64, Color(1, 0.85, 0.2))

func _update_adren_bar() -> void:
	if _adren_bar != null:
		_adren_bar.anchor_right = adrenaline / ADREN_MAX
		_adren_bar.offset_right = 0.0

func _build_adren_meter() -> void:
	if _adren_bar != null:
		return
	var track := Panel.new()
	track.anchor_top = 1.0
	track.anchor_bottom = 1.0
	track.offset_left = 30.0
	track.offset_right = 460.0
	track.offset_top = -60.0
	track.offset_bottom = -30.0
	track.z_index = 41
	track.add_theme_stylebox_override("panel", (ko_fill.get_parent() as Panel).get_theme_stylebox("panel"))
	safe.add_child(track)
	_adren_bar = Panel.new()
	_adren_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_adren_bar.anchor_right = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.75, 0.15)
	sb.set_corner_radius_all(11)
	_adren_bar.add_theme_stylebox_override("panel", sb)
	track.add_child(_adren_bar)
	_adren_label = Label.new()
	_adren_label.text = "ADRENALINE  (^ parry to build, shift = super)"
	_adren_label.add_theme_font_size_override("font_size", 20)
	_adren_label.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.09))
	_adren_label.add_theme_constant_override("outline_size", 6)
	_adren_label.anchor_top = 1.0
	_adren_label.anchor_bottom = 1.0
	_adren_label.offset_left = 34.0
	_adren_label.offset_top = -92.0
	safe.add_child(_adren_label)

# Spend a full meter on a super punch: a huge guaranteed crit with big juice.
func _super_punch() -> void:
	if adrenaline < ADREN_MAX or _koing or phase != Phase.FIGHT:
		return
	adrenaline = 0.0
	_grant("super_first")
	_update_adren_bar()
	_flash_screen(0.8)
	_shake(30.0, 0.5)
	_zoom_punch(0.12)
	_spawn_text(Vector2(960.0, 300.0), "HAYMAKER!", 130, Color(1, 0.3, 0.2))
	var at: Vector2 = boss.get_global_transform() * (boss.size * 0.5)
	if rig_anim != null:
		rig_anim.head_spin(4)
		rig_anim.knees_buckle(1.2)
	_crit_player.play()
	# Big fixed damage that ignores the guard state.
	_apply_damage(at, 55.0, true)
	if hp <= 0.0:
		_knockout()

# --- gas station: explosive pump zone ---------------------------------------
# A fuel pump beside the boss. Its rect is a no-punch zone: hit it and it blows,
# costing the player health. Forces aimed punches instead of blind mashing.
var _pump_rect: Rect2 = Rect2()
var _pump_marker: Control

func _setup_pump() -> void:
	# Zone in Safe-local coords, off to the boss's right at torso height.
	if not bool(_level_cfg().get("pump_zone", false)):
		_pump_rect = Rect2()
		if _pump_marker != null:
			_pump_marker.visible = false
		return
	_pump_rect = Rect2(1360, 620, 300, 460)
	if _pump_marker == null:
		_pump_marker = Panel.new()
		_pump_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pump_marker.z_index = 24
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.9, 0.15, 0.1, 0.22)
		sb.border_color = Color(1, 0.3, 0.15, 0.9)
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(12)
		_pump_marker.add_theme_stylebox_override("panel", sb)
		safe.add_child(_pump_marker)
		var warn := Label.new()
		warn.text = "!! PUMP !!\nDON'T HIT"
		warn.add_theme_font_size_override("font_size", 32)
		warn.add_theme_color_override("font_color", Color(1, 0.5, 0.2))
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.position = Vector2(30, 30)
		_pump_marker.add_child(warn)
	_pump_marker.position = _pump_rect.position
	_pump_marker.size = _pump_rect.size
	_pump_marker.visible = true

func _pump_explosion(at: Vector2) -> void:
	_punch_cd = 0.5
	_flash_screen(0.9)
	_shake(40.0, 0.6)
	_hitstop(0.08)
	_spawn_text(at + Vector2(0, -80), "KABOOM!", 120, Color(1, 0.5, 0.1))
	_spawn_stars(at, 16)
	combo = 0
	if _ko_player != null:
		_ko_player.play()
	player_hp = maxf(0.0, player_hp - 18.0)
	_set_player_hp(player_hp)
	if player_hp <= 0.0:
		_game_over()

# --- nurses' station: syringe counter-window --------------------------------
# The nurse periodically lunges with a syringe. A tight window opens to PARRY
# (counter) the jab: nail it and she's staggered and you bank adrenaline; miss
# and you take the needle. Reuses the parry input, themed as a counter.
var _counter_t: float = 0.0
var _counter_spr: Sprite2D
var _counter_busy: bool = false

func _has_counter() -> bool:
	return bool(_level_cfg().get("counter", false))

func _reset_counter() -> void:
	_counter_busy = false
	if _has_counter():
		_counter_t = randf_range(2.5, 4.0)
	if _counter_spr != null:
		_counter_spr.visible = false

func _update_counter(delta: float) -> void:
	if not _has_counter() or _koing or _counter_busy:
		return
	_counter_t -= delta
	if _counter_t <= 0.0:
		_run_counter()

func _run_counter() -> void:
	_counter_busy = true
	var path := "res://assets/hazards/syringe.png"
	if not ResourceLoader.exists(path):
		_reset_counter()
		return
	if _counter_spr == null:
		_counter_spr = Sprite2D.new()
		_counter_spr.z_index = 32
		safe.add_child(_counter_spr)
	_counter_spr.texture = load(path)
	_counter_spr.visible = true
	_counter_spr.scale = Vector2(2.6, 2.6)
	# Wind-up: syringe drawn back by the boss, with a COUNTER! cue.
	_counter_spr.position = Vector2(1180, 560)
	_spawn_text(Vector2(960.0, 250.0), "INJECTION! (parry!)", 72, Color(0.4, 0.9, 1.0))
	_shake(4.0, 0.2)
	await get_tree().create_timer(0.7, true, false, true).timeout
	# Lunge toward the player (screen-forward, i.e. down-centre).
	var tw := create_tween()
	tw.tween_property(_counter_spr, "position", Vector2(900, 950), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.18, true, false, true).timeout
	if _parry_time > 0.0:
		_parry_time = 0.0
		_spawn_text(Vector2(960.0, 380.0), "COUNTERED!", 90, Color(0.4, 0.9, 1.0))
		_flash_screen(0.4)
		_hitstop(0.06)
		if rig_anim != null:
			rig_anim.stagger(randf() < 0.5, 1.1)
		_add_adrenaline(30.0)
		_enter_stunned(1.4)
	else:
		_flash_screen(0.4)
		_shake(22.0, 0.4)
		_spawn_text(Vector2(960.0, 440.0), "JAB!", 96, Color(1, 0.3, 0.25))
		combo = 0
		player_hp = maxf(0.0, player_hp - 14.0)
		_set_player_hp(player_hp)
		if player_hp <= 0.0:
			_game_over()
	await tw.finished
	_counter_spr.visible = false
	_counter_t = randf_range(4.0, 6.5)
	_counter_busy = false

# Resolve a touch release in a punch fight: short movement = a tap (punch at the
# point), a fast flick past SWIPE_MIN = a directional swipe (dodge, or parry on
# an up-swipe). This is the mobile control scheme - no keyboard needed.
func _resolve_swipe(release_pos: Vector2) -> void:
	var delta := release_pos - _swipe_start
	var dur := _clock - _swipe_t
	if delta.length() < SWIPE_MIN or dur > 0.5:
		_punch_click(_swipe_start)      # a tap: punch where it started
		# A held touch releases any swipe-dodge lean.
		if _dodge_holding:
			_dodge_lift(_dodge_dir)
		return
	# A flick: pick the dominant axis.
	if absf(delta.x) > absf(delta.y):
		_dodge_press(-1 if delta.x < 0.0 else 1)
		# Auto-release the swipe-dodge shortly after (touch has no key-up hold).
		get_tree().create_timer(0.34, true, false, true).timeout.connect(func() -> void:
			if _dodge_holding:
				_dodge_lift(_dodge_dir))
	elif delta.y > 0.0:
		_dodge_press(0)                 # swipe down = duck
		get_tree().create_timer(0.34, true, false, true).timeout.connect(func() -> void:
			if _dodge_holding:
				_dodge_lift(_dodge_dir))
	else:
		_parry()                        # swipe up = parry

# --- endless / survival mode ------------------------------------------------
# A back-to-back gauntlet of random bosses that get tougher every round, so the
# best-score chase finally has a mode built around it. Reuses the whole fight
# loop; only the boss HP/damage scale and the win-goes-to-next-round wiring are
# new. HP carries between rounds with a small heal per clear - that carry-over
# is what makes it a survival run instead of 20 independent fights.

# The boxing-style levels only: setpiece gimmicks (car, moon, bridge...) are
# one-off spectacles that would break the back-to-back rhythm.
const ENDLESS_GIMMICKS := ["punch", "basic", "double", "feint", "rage"]

func _endless_pool() -> Array:
	var pool: Array = []
	for i in range(1, LEVELS.size() + 1):
		var g := String((LEVELS[i - 1] as Dictionary).get("gimmick", "punch"))
		if g in ENDLESS_GIMMICKS:
			pool.append(i)
	if pool.is_empty():
		pool.append(1)
	return pool

func _rand_endless_level() -> int:
	var pool := _endless_pool()
	return int(pool[randi() % pool.size()])

func _start_endless() -> void:
	_endless = true
	_free_fight = false
	_endless_round = 1
	_hp_mul = 1.0
	_dmg_mul = 1.0
	difficulty = Difficulty.BRAWLER    # survival only makes sense if he hits back
	level = _rand_endless_level()
	_apply_opponent()
	close_menu()
	_set_player_hp(player_hp_max)
	_endless_banner()
	_start_fight()

func _endless_next_round() -> void:
	_endless_round += 1
	# Ramp: each round the boss is tougher and hits harder.
	_hp_mul = 1.0 + 0.22 * float(_endless_round - 1)
	_dmg_mul = 1.0 + 0.15 * float(_endless_round - 1)
	if _endless_round > stat_endless_best:
		stat_endless_best = _endless_round
		_save_prefs()
	# Clearing a round heals a quarter of your bar - a breather, not a full reset.
	var healed := minf(player_hp_max, player_hp + player_hp_max * 0.25)
	level = _rand_endless_level()
	_apply_opponent()
	_endless_banner()
	_set_player_hp(healed)
	_start_fight(false)

func _endless_banner() -> void:
	_spawn_text(Vector2(960.0, 300.0), "ROUND %d" % _endless_round, 110, Color(1.0, 0.55, 0.16))

# --- daily grievance (retention) --------------------------------------------
# One challenge a day, picked deterministically from the calendar date: beat a
# rotating level, extra reward for staying flawless. Completing it grants
# "grievance points" (a currency) and builds a daily streak. Cheap retention,
# no server - the date comes from the system clock.
# Each daily is a real fight modifier, not just flavour: "name" shows on the
# menu, the other keys reshape the fight when the daily is active. "php" scales
# the player's starting health, "bosshp" scales the boss's, "oneshot" ends the
# run on a single hit. The date picks one deterministically.
const DAILY_CHALLENGES := [
	{"name": "Clock out early: just win.", "php": 1.0, "bosshp": 1.0, "oneshot": false},
	{"name": "Model Employee: stay flawless for double.", "php": 1.0, "bosshp": 1.0, "oneshot": false},
	{"name": "Glass Jaw: you start at half health.", "php": 0.5, "bosshp": 1.0, "oneshot": false},
	{"name": "Iron Boss: he has double health.", "php": 1.0, "bosshp": 2.0, "oneshot": false},
	{"name": "Sudden Death: one punch and you're fired.", "php": 1.0, "bosshp": 1.0, "oneshot": true},
]
var grievance_points: int = 0
var daily_streak: int = 0
var _daily_last: String = ""       # yyyy-mm-dd of last completion
var _daily_active: bool = false
var _daily_oneshot: bool = false   # this fight ends on a single hit

# Career ranks earned by accumulating grievance points - a progression spine
# so the currency the daily challenge grants actually means something. Pure
# text, no art to mismatch. [threshold, title], ascending.
const RANKS := [
	[0, "New Hire"],
	[100, "Intern"],
	[300, "Associate"],
	[600, "Team Lead"],
	[1000, "Middle Manager"],
	[1600, "Director"],
	[2400, "Vice President"],
	[3500, "C-Suite"],
	[5000, "Boss of Bosses"],
]

func _rank_index() -> int:
	var idx := 0
	for i in range(RANKS.size()):
		if grievance_points >= int(RANKS[i][0]):
			idx = i
	return idx

func _rank_title() -> String:
	return str(RANKS[_rank_index()][1])

# Points still needed for the next rank, or -1 if already at the top.
func _rank_to_next() -> int:
	var idx := _rank_index()
	if idx >= RANKS.size() - 1:
		return -1
	return int(RANKS[idx + 1][0]) - grievance_points

# Career acts: the 20 levels grouped into a climb up the org chart, so the run
# reads as a story (intern -> CEO) instead of a flat list. [first_level, roman,
# title, role-colour]. Levels past the last act's range fall into that act.
const ACTS := [
	[1, "I", "Onboarding", Color(0.30, 0.62, 0.36)],
	[6, "II", "Middle Management", Color(0.24, 0.52, 0.82)],
	[11, "III", "The Corner Office", Color(0.66, 0.36, 0.78)],
	[16, "IV", "The C-Suite", Color(0.86, 0.42, 0.16)],
]

func _act_index_for(lvl: int) -> int:
	var idx := 0
	for i in range(ACTS.size()):
		if lvl >= int(ACTS[i][0]):
			idx = i
	return idx

func _act_label(lvl: int) -> String:
	var a: Array = ACTS[_act_index_for(lvl)]
	return "ACT %s · %s" % [String(a[1]), String(a[2])]

func _act_color(lvl: int) -> Color:
	return ACTS[_act_index_for(lvl)][3]

func _today_str() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _yesterday_str() -> String:
	var now := Time.get_unix_time_from_system()
	var d := Time.get_date_dict_from_unix_time(int(now) - 86400)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func _day_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return d.year * 10000 + d.month * 100 + d.day

func _daily_level() -> int:
	return (_day_seed() % LEVELS.size()) + 1

func _daily_challenge() -> Dictionary:
	return DAILY_CHALLENGES[_day_seed() % DAILY_CHALLENGES.size()]

func _daily_name() -> String:
	return String(_daily_challenge().get("name", ""))

func _daily_done_today() -> bool:
	return _daily_last == _today_str()

func _start_daily() -> void:
	if _daily_done_today():
		return
	_daily_active = true
	level = _daily_level()
	close_menu()
	_start_prefight()

# Called on a win; if it was the daily and not yet claimed today, reward it.
func _complete_daily(was_flawless: bool) -> void:
	if not _daily_active or _daily_done_today():
		_daily_active = false
		return
	_daily_active = false
	# Streak continues only if the last completion was exactly yesterday.
	if _daily_last == _yesterday_str():
		daily_streak += 1
	else:
		daily_streak = 1
	_daily_last = _today_str()
	var reward := 50 + daily_streak * 10
	if was_flawless:
		reward *= 2
	_save_prefs()
	_award_toast_text("DAILY GRIEVANCE", "Streak %d  ·  +%d points" % [daily_streak, reward])
	_grant_grievance(reward)

# Add grievance points, pop the floating total, and celebrate a promotion if the
# points crossed a rank threshold. Shared by the daily, normal wins and Endless.
func _grant_grievance(amount: int) -> void:
	if amount <= 0:
		return
	var rank_before := _rank_index()
	grievance_points += amount
	_spawn_text(Vector2(960.0, 360.0), "+%d GRIEVANCE" % amount, 80, Color(1, 0.7, 0.16))
	if _rank_index() > rank_before:
		_award_toast_text("PROMOTED", _rank_title(), 184.0)

# Generic toast (the achievement toast, reusable for the daily reward).
func _award_toast_text(head_text: String, body_text: String, y_top: float = 40.0) -> void:
	var toast := Panel.new()
	toast.z_index = 98
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -360.0
	toast.offset_right = 360.0
	toast.offset_top = y_top
	toast.offset_bottom = y_top + 128.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.96, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.82, 0.2, 0.18)
	toast.add_theme_stylebox_override("panel", sb)
	safe.add_child(toast)
	var head := Label.new()
	head.text = head_text
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.82, 0.2, 0.18))
	head.position = Vector2(28, 16)
	toast.add_child(head)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", 38)
	body.add_theme_color_override("font_color", Color(0.1, 0.08, 0.12))
	body.position = Vector2(28, 54)
	toast.add_child(body)
	toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.6)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(toast.queue_free)
