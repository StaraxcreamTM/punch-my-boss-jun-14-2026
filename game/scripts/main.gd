extends Control

# Punch My Boss — starter gameplay screen.
# Sized to fit any Android phone: content scales with the screen (see project.godot
# stretch settings) and the UI is kept inside the device "safe area" so nothing
# hides under a notch or camera cutout.

@onready var safe: Control = $Safe
@onready var boss: Button = $Safe/Boss
@onready var counter: Label = $Safe/Counter

var punches: int = 0

func _ready() -> void:
	boss.resized.connect(_center_pivot)
	_center_pivot()
	boss.pressed.connect(_on_boss_pressed)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

func _center_pivot() -> void:
	# Scale animations should grow from the button's center, not its corner.
	boss.pivot_offset = boss.size / 2.0

func _on_boss_pressed() -> void:
	punches += 1
	counter.text = "Punches: %d" % punches
	# A quick squash-and-spring so every tap feels satisfying.
	var tween := create_tween()
	boss.scale = Vector2(0.88, 0.88)
	tween.tween_property(boss, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _apply_safe_area() -> void:
	# Inset the UI container to the phone's usable screen region.
	var screen := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var vis := get_viewport().get_visible_rect().size
	safe.offset_left = sa.position.x / screen.x * vis.x
	safe.offset_top = sa.position.y / screen.y * vis.y
	safe.offset_right = -((screen.x - (sa.position.x + sa.size.x)) / screen.x * vis.x)
	safe.offset_bottom = -((screen.y - (sa.position.y + sa.size.y)) / screen.y * vis.y)
