extends Node
class_name BossRig

# Boss animation rig — Punch-Out combat poses with Looney Tunes reactions.
#
# Every animation is procedural: it tweens *additive offsets*, and _pose()
# composes idle + offsets into the actual bone transforms once per frame. That
# layering is the whole trick — a stagger can play on top of breathing, and a
# head spin on top of a stagger, without any of them fighting over a property.
# (Tweening bone rotations directly was the old approach and it broke the
# moment two animations overlapped.)
#
# Bone keys are short names; see _BONE_PATHS for the skeleton paths.

const BONES := ["hip", "spine", "chest", "head",
	"uarmL", "farmL", "handL", "uarmR", "farmR", "handR",
	"thighL", "shinL", "footL", "thighR", "shinR", "footR"]

const _BONE_PATHS := {
	"hip": "Hip",
	"spine": "Hip/Spine",
	"chest": "Hip/Spine/Chest",
	"head": "Hip/Spine/Chest/Head",
	"uarmL": "Hip/ArmL",
	"farmL": "Hip/ArmL/ForearmL",
	"handL": "Hip/ArmL/ForearmL/FistL",
	"uarmR": "Hip/ArmR",
	"farmR": "Hip/ArmR/ForearmR",
	"handR": "Hip/ArmR/ForearmR/FistR",
	"thighL": "Hip/ThighL",
	"shinL": "Hip/ThighL/ShinL",
	"footL": "Hip/ThighL/ShinL/FootL",
	"thighR": "Hip/ThighR",
	"shinR": "Hip/ThighR/ShinR",
	"footR": "Hip/ThighR/ShinR/FootR",
}

var skel: Skeleton2D
var rig: Control                  # whole-body node, for leans / hops / spins
var head_spr: Sprite2D

var _bone: Dictionary = {}        # key -> Bone2D
var _rest_pos: Dictionary = {}    # key -> Vector2 (rest position)
var _rot: Dictionary = {}         # key -> additive rotation offset
var _pos: Dictionary = {}         # key -> additive position offset
var _scale: Dictionary = {}       # key -> additive scale offset (Vector2, 0 = none)

# Whole-body additive offsets, written by animations.
var body_rot: float = 0.0
var body_pos: Vector2 = Vector2.ZERO
var body_scale: Vector2 = Vector2.ZERO   # additive on top of Vector2.ONE
# Separate channel for the fight-state lean, which the state machine writes
# every frame. Kept apart from body_rot so a per-frame write can't stomp an
# in-flight tween (a stun wobble and a wind-up lean can coexist).
var lean: float = 0.0

var idle_amp: float = 1.0         # scales the idle motion (agitation)
# Per-character damping for arm swing. Amplitudes tuned on a slim figure sweep
# a heavyset one's short arms right across its own belly, so wide characters
# turn this down. Applied to the additive offsets only - idle sway is already
# scaled by idle_amp.
var arm_gain: float = 1.0
const _ARM_KEYS := ["uarmL", "uarmR", "farmL", "farmR", "handL", "handR"]
var idle_enabled: bool = true
# When false, update() leaves the rig Control alone so cutscene code (the K.O.
# launch) can tween it directly without the two fighting over the transform.
var own_body: bool = true
var _t: float = 0.0

# Lively-idle extras
var _blink_t: float = 0.0
var _next_blink: float = 2.0
var _fidget_t: float = 0.0
var _next_fidget: float = 4.0
var _glance: float = 0.0          # -1..1 head turn

signal anim_finished(name: String)


func setup(p_skel: Skeleton2D, p_rig: Control, p_head: Sprite2D) -> void:
	skel = p_skel
	rig = p_rig
	head_spr = p_head
	for k in BONES:
		var b := skel.get_node_or_null(NodePath(_BONE_PATHS[k])) as Bone2D
		if b == null:
			push_warning("BossRig: missing bone %s (%s)" % [k, _BONE_PATHS[k]])
			continue
		_bone[k] = b
		_rest_pos[k] = b.position
		_rot[k] = 0.0
		_pos[k] = Vector2.ZERO
		_scale[k] = Vector2.ZERO
	_next_blink = randf_range(1.5, 4.0)
	_next_fidget = randf_range(3.0, 7.0)


func has_bones() -> bool:
	return _bone.size() == BONES.size()


# --- per-frame composition -------------------------------------------------

func update(delta: float) -> void:
	if _bone.is_empty():
		return
	_t += delta
	_tick_life(delta)

	var breath := sin(_t * 1.9)
	var sway := sin(_t * 0.72)
	var trail := sin(_t * 0.72 + 0.9)
	var a := idle_amp if idle_enabled else 0.0

	_apply("hip", sway * 0.018 * a, Vector2(sway * 5.0 * a, -breath * 2.0))
	_apply("spine", -sway * 0.026 * a + breath * 0.008, Vector2.ZERO)
	_apply("chest", -sway * 0.014 * a + breath * 0.012, Vector2.ZERO)
	_apply("head", sway * 0.030 * a - breath * 0.010 + _glance * 0.12,
		Vector2(sway * 3.0 * a + _glance * 6.0, -breath * 2.0))

	_apply("uarmL", sway * 0.055 * a, Vector2.ZERO)
	_apply("uarmR", -sway * 0.055 * a, Vector2.ZERO)
	_apply("farmL", trail * 0.045 * a, Vector2.ZERO)
	_apply("farmR", -trail * 0.045 * a, Vector2.ZERO)
	_apply("handL", sin(_t * 0.72 + 1.6) * 0.05 * a, Vector2.ZERO)
	_apply("handR", -sin(_t * 0.72 + 1.6) * 0.05 * a, Vector2.ZERO)

	_apply("thighL", -sway * 0.020 * a, Vector2.ZERO)
	_apply("thighR", -sway * 0.020 * a, Vector2.ZERO)
	_apply("shinL", sway * 0.014 * a, Vector2.ZERO)
	_apply("shinR", sway * 0.014 * a, Vector2.ZERO)
	_apply("footL", -sway * 0.010 * a, Vector2.ZERO)
	_apply("footR", -sway * 0.010 * a, Vector2.ZERO)

	if rig != null and own_body:
		rig.rotation = body_rot + lean
		rig.position = body_pos
		rig.scale = Vector2.ONE + body_scale


func _apply(key: String, idle_rot: float, idle_pos: Vector2) -> void:
	var b: Bone2D = _bone.get(key)
	if b == null:
		return
	var add: float = _rot[key]
	if arm_gain != 1.0 and key in _ARM_KEYS:
		add *= arm_gain
	b.rotation = idle_rot + add
	b.position = _rest_pos[key] + idle_pos + _pos[key]
	var s: Vector2 = _scale[key]
	b.scale = Vector2.ONE + s


# Blinking, glancing and small fidgets — the "he's alive" layer.
func _tick_life(delta: float) -> void:
	if not idle_enabled:
		return
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(1.8, 5.0)
		blink()
	_fidget_t += delta
	if _fidget_t >= _next_fidget:
		_fidget_t = 0.0
		_next_fidget = randf_range(3.5, 8.0)
		_do_fidget()


func _do_fidget() -> void:
	# Occasional glance to the side, or a small shoulder roll.
	if randf() < 0.55:
		var dir := 1.0 if randf() < 0.5 else -1.0
		var tw := create_tween()
		tw.tween_property(self, "_glance", dir, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(randf_range(0.6, 1.4))
		tw.tween_property(self, "_glance", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	else:
		var side := "uarmL" if randf() < 0.5 else "uarmR"
		_tw_rot(side, 0.10, 0.28, Tween.TRANS_SINE)
		_tw_rot_back(side, 0.0, 0.5, 0.30)


# Blink: the head art has no closed-eye frame, so squash the head sprite
# briefly. On this flat cartoon art a fast vertical pinch reads as a blink.
func blink() -> void:
	if head_spr == null:
		return
	var tw := create_tween()
	tw.tween_property(head_spr, "scale:y", head_spr.scale.y * 0.94, 0.05)
	tw.tween_property(head_spr, "scale:y", head_spr.scale.y, 0.07)


# --- offset tween helpers --------------------------------------------------

func _tw_rot(key: String, to: float, dur: float, trans := Tween.TRANS_QUAD) -> Tween:
	if not _rot.has(key):
		return null
	var from: float = _rot[key]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _rot[key] = v, from, to, dur) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	return tw


func _tw_rot_back(key: String, to: float, delay: float, dur: float) -> void:
	if not _rot.has(key):
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: _rot[key] = v, _rot[key], to, dur) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _tw_pos(key: String, to: Vector2, dur: float) -> void:
	if not _pos.has(key):
		return
	var from: Vector2 = _pos[key]
	var tw := create_tween()
	tw.tween_method(func(v: Vector2) -> void: _pos[key] = v, from, to, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Drive several bones to a pose over `dur`, then optionally spring home.
func pose(map: Dictionary, dur: float, hold: float = 0.0, ret: float = 0.0) -> void:
	for key in map.keys():
		if not _rot.has(key):
			continue
		var target: float = map[key]
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _rot[key] = v, _rot[key], target, dur) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if ret > 0.0:
			tw.tween_interval(hold)
			tw.tween_method(func(v: float) -> void: _rot[key] = v, target, 0.0, ret) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func clear_offsets(dur: float = 0.25) -> void:
	for key in _rot.keys():
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _rot[key] = v, _rot[key], 0.0, dur)
		var tp := create_tween()
		tp.tween_method(func(v: Vector2) -> void: _pos[key] = v, _pos[key], Vector2.ZERO, dur)
		var ts := create_tween()
		ts.tween_method(func(v: Vector2) -> void: _scale[key] = v, _scale[key], Vector2.ZERO, dur)
	var tb := create_tween()
	tb.set_parallel(true)
	tb.tween_property(self, "body_rot", 0.0, dur)
	tb.tween_property(self, "body_pos", Vector2.ZERO, dur)
	tb.tween_property(self, "body_scale", Vector2.ZERO, dur)


# --- OFFENSE ---------------------------------------------------------------

# Wind-up "tell": he cocks the arm back and leans away. This is the window the
# player reads to time a dodge.
func tell(side_left: bool, dur: float) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	pose({u: -0.9 * s, f: -1.1 * s, "chest": 0.16 * s, "hip": 0.08 * s}, dur)
	var tb := create_tween()
	tb.set_parallel(true)
	tb.tween_property(self, "body_rot", 0.06 * s, dur).set_trans(Tween.TRANS_SINE)
	tb.tween_property(self, "body_pos", Vector2(18.0 * s, 0.0), dur)


func jab(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	pose({u: 1.35 * s, f: 0.15 * s, "chest": -0.20 * s}, 0.08, 0.05, 0.30)
	var tb := create_tween()
	tb.tween_property(self, "body_pos", Vector2(-46.0 * s, 0.0), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tb.tween_property(self, "body_pos", Vector2.ZERO, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	emit_signal("anim_finished", "jab")


func hook(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	pose({u: 1.9 * s, f: 1.2 * s, "chest": -0.34 * s, "hip": -0.18 * s}, 0.11, 0.06, 0.34)
	var tb := create_tween()
	tb.set_parallel(true)
	tb.tween_property(self, "body_rot", -0.16 * s, 0.11)
	tb.tween_property(self, "body_pos", Vector2(-38.0 * s, 0.0), 0.11)
	var tb2 := create_tween()
	tb2.set_parallel(true)
	tb2.tween_interval(0.17)
	tb2.tween_property(self, "body_rot", 0.0, 0.32).set_trans(Tween.TRANS_ELASTIC)
	tb2.tween_property(self, "body_pos", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_BACK)
	emit_signal("anim_finished", "hook")


func uppercut(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	# Drops low, then explodes upward.
	pose({u: -0.5 * s, f: -0.8 * s}, 0.14)
	var crouch := create_tween()
	crouch.tween_property(self, "body_pos", Vector2(0.0, 46.0), 0.14)
	crouch.tween_property(self, "body_pos", Vector2(0.0, -30.0), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	crouch.tween_property(self, "body_pos", Vector2.ZERO, 0.30).set_trans(Tween.TRANS_BACK)
	var t2 := create_tween()
	t2.tween_interval(0.14)
	t2.tween_callback(func() -> void:
		pose({u: 2.5 * s, f: 0.6 * s, "chest": -0.25 * s}, 0.10, 0.05, 0.34))
	emit_signal("anim_finished", "uppercut")


# --- DEFENSE ---------------------------------------------------------------

func block() -> void:
	pose({"uarmL": 1.5, "farmL": -1.5, "uarmR": -1.5, "farmR": 1.5,
		"chest": 0.0, "head": 0.10}, 0.14)


func unblock() -> void:
	pose({"uarmL": 0.0, "farmL": 0.0, "uarmR": 0.0, "farmR": 0.0, "head": 0.0}, 0.22)


func dodge(dir: int) -> void:
	# dir: -1 left, +1 right, 0 duck.
	if dir == 0:
		var tw := create_tween()
		tw.tween_property(self, "body_pos", Vector2(0.0, 90.0), 0.13) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.10)
		tw.tween_property(self, "body_pos", Vector2.ZERO, 0.26).set_trans(Tween.TRANS_BACK)
		pose({"thighL": 0.35, "thighR": -0.35, "shinL": -0.5, "shinR": 0.5}, 0.13, 0.10, 0.26)
		return
	var s := float(dir)
	var tb := create_tween()
	tb.set_parallel(true)
	tb.tween_property(self, "body_pos", Vector2(150.0 * s, 10.0), 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tb.tween_property(self, "body_rot", 0.20 * s, 0.13)
	var tb2 := create_tween()
	tb2.set_parallel(true)
	tb2.tween_interval(0.20)
	tb2.tween_property(self, "body_pos", Vector2.ZERO, 0.30).set_trans(Tween.TRANS_BACK)
	tb2.tween_property(self, "body_rot", 0.0, 0.30).set_trans(Tween.TRANS_ELASTIC)
	pose({"chest": -0.20 * s, "head": -0.25 * s}, 0.13, 0.10, 0.30)


# --- REACTIONS (Looney Tunes) ----------------------------------------------

# Standard flinch: head snaps aside, torso rocks, arms fly out.
func stagger(side_left: bool, power: float = 1.0) -> void:
	var s := 1.0 if side_left else -1.0
	pose({
		"head": 0.55 * s * power,
		"chest": 0.22 * s * power,
		"spine": 0.14 * s * power,
		# Forearms counter-rotate against the upper arms. Same-sign rotation
		# read as the elbow bending backwards, which looks broken rather than
		# cartoonish.
		"uarmL": 0.42 * power, "uarmR": -0.42 * power,
		"farmL": -0.30 * power, "farmR": 0.30 * power,
	}, 0.05, 0.04, 0.42)
	var tb := create_tween()
	tb.tween_property(self, "body_pos", Vector2(-52.0 * s * power, 0.0), 0.05)
	tb.tween_property(self, "body_pos", Vector2.ZERO, 0.36).set_trans(Tween.TRANS_ELASTIC)


# The head spins all the way around N times. Pure cartoon logic.
func head_spin(times: int = 3, dur: float = 0.75) -> void:
	var key := "head"
	if not _rot.has(key):
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _rot[key] = v,
		0.0, TAU * float(times), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _rot[key] = v, 0.0, 0.0, 0.01)
	# A wobble as it settles.
	tw.tween_method(func(v: float) -> void: _rot[key] = v, 0.5, 0.0, 0.45) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# Neck stretches way back like rubber, then snaps home.
func neck_stretch(side_left: bool, power: float = 1.0) -> void:
	var s := 1.0 if side_left else -1.0
	if head_spr != null:
		var ts := create_tween()
		ts.tween_property(head_spr, "scale", head_spr.scale * Vector2(0.86, 1.30), 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ts.tween_property(head_spr, "scale", head_spr.scale, 0.45) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var key := "head"
	if _pos.has(key):
		var tp := create_tween()
		tp.tween_method(func(v: Vector2) -> void: _pos[key] = v,
			Vector2.ZERO, Vector2(-120.0 * s * power, -70.0 * power), 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tp.tween_method(func(v: Vector2) -> void: _pos[key] = v,
			Vector2(-120.0 * s * power, -70.0 * power), Vector2.ZERO, 0.5) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	pose({"head": 0.8 * s * power, "chest": 0.3 * s}, 0.09, 0.06, 0.45)


# Dazed wobble — knees buckle, body sways like a metronome winding down.
func wobble_stun(duration: float = 1.6) -> void:
	idle_amp = 0.25
	var steps := 6
	var tb := create_tween()
	for i in steps:
		var mag := (1.0 - float(i) / float(steps)) * 0.22
		var dir := 1.0 if i % 2 == 0 else -1.0
		tb.tween_property(self, "body_rot", mag * dir, duration / float(steps)) \
			.set_trans(Tween.TRANS_SINE)
	tb.tween_property(self, "body_rot", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
	tb.tween_callback(func() -> void: idle_amp = 1.0)
	pose({"thighL": 0.22, "thighR": -0.22, "shinL": -0.3, "shinR": 0.3,
		"head": 0.2, "uarmL": 0.4, "uarmR": -0.4}, 0.2, duration, 0.4)


# Knees buckle briefly (used on heavy body blows).
func knees_buckle(power: float = 1.0) -> void:
	pose({"thighL": 0.30 * power, "thighR": -0.30 * power,
		"shinL": -0.45 * power, "shinR": 0.45 * power, "spine": 0.18 * power}, 0.09, 0.06, 0.38)
	var tw := create_tween()
	tw.tween_property(self, "body_pos", Vector2(0.0, 44.0 * power), 0.09)
	tw.tween_property(self, "body_pos", Vector2.ZERO, 0.36).set_trans(Tween.TRANS_ELASTIC)


# Squash on impact, then overshoot back — the classic cartoon hit accent.
func squash(power: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "body_scale", Vector2(0.14 * power, -0.16 * power), 0.05)
	tw.tween_property(self, "body_scale", Vector2(-0.07 * power, 0.09 * power), 0.09)
	tw.tween_property(self, "body_scale", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_ELASTIC)


# Full collapse for a KO: folds up and drops.
func ko_collapse() -> void:
	idle_enabled = false
	pose({"spine": 0.5, "chest": 0.4, "head": 0.9,
		"thighL": 0.6, "thighR": -0.6, "shinL": -0.9, "shinR": 0.9,
		"uarmL": 1.1, "uarmR": -1.1}, 0.35)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "body_rot", 0.5, 0.5).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "body_pos", Vector2(0.0, 120.0), 0.5).set_trans(Tween.TRANS_BOUNCE)


func revive() -> void:
	idle_enabled = true
	idle_amp = 1.0
	clear_offsets(0.4)


# --- FLAVOUR ---------------------------------------------------------------

func taunt() -> void:
	# Rolls the shoulders and tips the head back — smug.
	pose({"chest": -0.12, "head": -0.22, "uarmL": 0.55, "uarmR": -0.55,
		"farmL": -0.7, "farmR": 0.7}, 0.28, 0.55, 0.45)


func laugh() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "body_pos", Vector2(0.0, -16.0), 0.09).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "body_pos", Vector2(0.0, 0.0), 0.09).set_trans(Tween.TRANS_SINE)
	pose({"head": -0.25, "chest": -0.15}, 0.12, 0.6, 0.3)


func point_at_player() -> void:
	pose({"uarmR": -1.5, "farmR": 0.5, "chest": -0.1, "head": 0.05}, 0.2, 0.7, 0.35)


# --- extra Looney Tunes reactions -------------------------------------------
# More gags for the reaction roll. Each is layered on the same additive offsets
# as everything else, so they stack with breathing and with each other.

# The whole body spins like a top, then wobbles to a stop.
func spin_body(times: int = 2, dur: float = 0.7) -> void:
	var tw := create_tween()
	tw.tween_property(self, "body_rot", TAU * float(times), dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: body_rot = 0.0)
	tw.tween_property(self, "body_rot", 0.0, 0.4).from(0.35) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# Squashed flat like an anvil landed on him, then pops back up.
func flatten(power: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "body_scale", Vector2(0.45 * power, -0.55 * power), 0.07) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.16)
	tw.tween_property(self, "body_scale", Vector2(-0.18, 0.26), 0.14).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "body_scale", Vector2.ZERO, 0.30).set_trans(Tween.TRANS_ELASTIC)
	pose({"thighL": 0.5, "thighR": -0.5, "shinL": -0.7, "shinR": 0.7,
		"uarmL": 0.9, "uarmR": -0.9, "head": 0.2}, 0.07, 0.16, 0.34)

# Stretches tall like a startled cat, then drops.
func stretch_up(power: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "body_scale", Vector2(-0.22 * power, 0.42 * power), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "body_scale", Vector2.ZERO, 0.34).set_trans(Tween.TRANS_BOUNCE)
	var tp := create_tween()
	tp.tween_property(self, "body_pos", Vector2(0.0, -70.0 * power), 0.09)
	tp.tween_property(self, "body_pos", Vector2.ZERO, 0.30).set_trans(Tween.TRANS_BOUNCE)

# Head whips side to side several times - the multi-hit rubber neck.
func rubber_neck(hits: int = 4) -> void:
	var key := "head"
	if not _rot.has(key):
		return
	var tw := create_tween()
	for i in hits:
		var mag := (1.0 - float(i) / float(hits + 1)) * 0.85
		var dir := 1.0 if i % 2 == 0 else -1.0
		tw.tween_method(func(v: float) -> void: _rot[key] = v,
			_rot[key], mag * dir, 0.06).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float) -> void: _rot[key] = v, _rot[key], 0.0, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if head_spr != null:
		var ts := create_tween()
		ts.tween_property(head_spr, "scale", head_spr.scale * Vector2(1.18, 0.88), 0.07)
		ts.tween_property(head_spr, "scale", head_spr.scale, 0.38).set_trans(Tween.TRANS_ELASTIC)

# Knees knock together and the whole figure jellies.
func jelly_legs(dur: float = 1.0) -> void:
	var tw := create_tween()
	var steps := 5
	for i in steps:
		var mag := (1.0 - float(i) / float(steps)) * 0.34
		var dir := 1.0 if i % 2 == 0 else -1.0
		tw.tween_method(func(v: float) -> void:
			_rot["thighL"] = v
			_rot["thighR"] = v
			_rot["shinL"] = -v * 1.4
			_rot["shinR"] = -v * 1.4, _rot["thighL"], mag * dir, dur / float(steps)) \
			.set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void:
		_rot["thighL"] = v
		_rot["thighR"] = v
		_rot["shinL"] = -v
		_rot["shinR"] = -v, _rot["thighL"], 0.0, 0.3)

# Jumps clean off the floor in shock.
func shock_hop(power: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "body_pos", Vector2(0.0, -150.0 * power), 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "body_pos", Vector2.ZERO, 0.26).set_trans(Tween.TRANS_BOUNCE)
	pose({"uarmL": 1.3, "uarmR": -1.3, "farmL": 0.6, "farmR": -0.6,
		"thighL": -0.3, "thighR": 0.3, "head": -0.15}, 0.12, 0.10, 0.32)


# --- more offense --------------------------------------------------------
# Distinct attacks so each level's boss reads differently, not just faster.

# Overhead smash: winds up high, comes straight down.
func overhead(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	pose({u: -2.4 * s, f: -0.9 * s, "chest": 0.18 * s}, 0.16)
	var t2 := create_tween()
	t2.tween_interval(0.16)
	t2.tween_callback(func() -> void:
		pose({u: 1.7 * s, f: 0.5 * s, "chest": -0.30 * s, "spine": -0.16 * s},
			0.08, 0.06, 0.34))
	var tb := create_tween()
	tb.tween_interval(0.16)
	tb.tween_property(self, "body_pos", Vector2(0.0, 34.0), 0.08)
	tb.tween_property(self, "body_pos", Vector2.ZERO, 0.30).set_trans(Tween.TRANS_BACK)

# Double jab: two quick straight shots off the same arm.
func double_jab(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var s := 1.0 if side_left else -1.0
	var tw := create_tween()
	for i in 2:
		tw.tween_method(func(v: float) -> void: _rot[u] = v, 0.0, 1.35 * s, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float) -> void: _rot[u] = v, 1.35 * s, 0.15 * s, 0.09)
	tw.tween_method(func(v: float) -> void: _rot[u] = v, _rot[u], 0.0, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC)

# Wild haymaker: huge telegraphed wind-around.
func haymaker(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var f := "farmL" if side_left else "farmR"
	var s := 1.0 if side_left else -1.0
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _rot[u] = v, 0.0, -TAU * 0.9 * s, 0.26) \
		.set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float) -> void: _rot[u] = v, -TAU * 0.9 * s, 2.1 * s, 0.09) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _rot[u] = v, 2.1 * s, 0.0, 0.36) \
		.set_trans(Tween.TRANS_ELASTIC)
	pose({f: 1.0 * s, "chest": -0.38 * s, "hip": -0.2 * s}, 0.30, 0.05, 0.36)
	var tb := create_tween()
	tb.tween_interval(0.26)
	tb.tween_property(self, "body_rot", -0.22 * s, 0.09)
	tb.tween_property(self, "body_rot", 0.0, 0.34).set_trans(Tween.TRANS_ELASTIC)

# A feint: he starts the tell then aborts it. Bait for a panic dodge.
func feint(side_left: bool) -> void:
	var u := "uarmL" if side_left else "uarmR"
	var s := 1.0 if side_left else -1.0
	pose({u: -0.8 * s, "chest": 0.12 * s}, 0.12, 0.05, 0.20)
	var tb := create_tween()
	tb.tween_property(self, "body_pos", Vector2(12.0 * s, 0.0), 0.12)
	tb.tween_property(self, "body_pos", Vector2.ZERO, 0.18)

# Charging shoulder barge across the floor.
func barge(side_left: bool) -> void:
	var s := 1.0 if side_left else -1.0
	pose({"chest": -0.30 * s, "spine": -0.2 * s, "head": -0.15 * s,
		"uarmL": 0.7, "uarmR": -0.7}, 0.10, 0.10, 0.34)
	var tb := create_tween()
	tb.tween_property(self, "body_pos", Vector2(-120.0 * s, 0.0), 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tb.tween_interval(0.06)
	tb.tween_property(self, "body_pos", Vector2.ZERO, 0.34).set_trans(Tween.TRANS_BACK)
