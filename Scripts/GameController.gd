extends CanvasLayer
class_name GameController

## Countdown timer + win/lose state shown at the top of the screen.
##  - Timer hits 0        -> shows "Captured"
##  - escape() is called  -> shows "Escaped" (the train calls this when the
##                           player touches one of its carriages)
## Killing NPCs adds time (NPCInstance calls add_time() through the
## "game_timer" group).

signal captured
signal escaped

enum State { RUNNING, CAPTURED, ESCAPED }

# ============================================================
# TIMER
# ============================================================
@export_group("Timer")
## Seconds on the clock when the scene starts.
@export var start_time: float = 60.0

## The clock can never go above this. 0 = no cap.
@export var max_time: float = 0.0

# ============================================================
# END MESSAGES
# ============================================================
@export_group("End Messages")
@export var captured_text: String = "Captured"
@export var escaped_text: String = "Escaped"
@export var captured_color: Color = Color(1.0, 0.2, 0.2)
@export var escaped_color: Color = Color(0.4, 1.0, 0.4)
@export var end_font_size: int = 72

## Seconds the end message stays up before the scene reloads.
@export var restart_delay: float = 3.0

## Captured always reloads the scene after restart_delay. Turn this on to
## reload after Escaped as well; off leaves the "Escaped" message up.
@export var restart_after_escape: bool = false

# ============================================================
# DISPLAY
# ============================================================
@export_group("Display")
@export var font_size: int = 48
## Gap between the top of the screen and the timer text.
@export var top_margin: int = 20
@export var normal_color: Color = Color.WHITE
@export var low_time_color: Color = Color(1.0, 0.2, 0.2)
## At or below this many seconds the text pulses toward low_time_color.
@export var low_time_threshold: float = 10.0
@export var bonus_color: Color = Color(0.4, 1.0, 0.4)
@export var bonus_font_size: int = 28

# ============================================================
# RUNTIME STATE
# ============================================================
var time_left: float = 0.0
var state: State = State.RUNNING

var _pulse_time: float = 0.0
var _label: Label
var _bonus_label: Label
var _bonus_tween: Tween


func _ready() -> void:
	add_to_group("game_timer")
	time_left = start_time
	_build_ui()
	_update_label(0.0)


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	time_left -= delta

	if time_left <= 0.0:
		capture()
		return

	_update_label(delta)


# ============================================================
# PUBLIC API
# ============================================================
## Adds (or, if negative, removes) seconds from the clock. Ignored once
## the game has ended.
func add_time(seconds: float) -> void:
	if state != State.RUNNING:
		return

	time_left += seconds

	if max_time > 0.0:
		time_left = minf(time_left, max_time)

	_show_bonus(seconds)


## Player got caught -- also what happens automatically when time runs out.
func capture() -> void:
	if state != State.RUNNING:
		return

	state = State.CAPTURED
	time_left = 0.0
	_show_end_message(captured_text, captured_color)
	captured.emit()
	_schedule_reload()


## Player made it out -- stops the clock and shows the escaped message.
func escape() -> void:
	if state != State.RUNNING:
		return

	state = State.ESCAPED
	_show_end_message(escaped_text, escaped_color)
	escaped.emit()

	if restart_after_escape:
		_schedule_reload()


## Puts the clock back to start_time and clears any end message, without
## reloading the scene.
func reset_timer() -> void:
	state = State.RUNNING
	time_left = start_time
	_pulse_time = 0.0
	_label.add_theme_font_size_override("font_size", font_size)
	_update_label(0.0)


# ============================================================
# SCENE RELOAD
# ============================================================
func _schedule_reload() -> void:
	get_tree().create_timer(restart_delay).timeout.connect(_reload_scene)


func _reload_scene() -> void:
	get_tree().reload_current_scene()


# ============================================================
# UI
# ============================================================
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", top_margin)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	margin.add_child(box)

	_label = Label.new()
	_label.text = "0:00"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 10)
	box.add_child(_label)

	# "+5" popup shown under the clock when time is added. Always present
	# (just invisible) so the layout doesn't jump when it appears.
	_bonus_label = Label.new()
	_bonus_label.text = " "
	_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus_label.add_theme_font_size_override("font_size", bonus_font_size)
	_bonus_label.add_theme_color_override("font_color", bonus_color)
	_bonus_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_bonus_label.add_theme_constant_override("outline_size", 8)
	_bonus_label.modulate.a = 0.0
	box.add_child(_bonus_label)


func _update_label(delta: float) -> void:
	if not _label:
		return

	_label.text = _format_time(time_left)

	var color := normal_color
	if time_left <= low_time_threshold:
		_pulse_time += delta
		var pulse: float = (sin(_pulse_time * TAU * 1.5) + 1.0) * 0.5
		color = normal_color.lerp(low_time_color, 0.4 + 0.6 * pulse)
	else:
		_pulse_time = 0.0

	_label.add_theme_color_override("font_color", color)


func _show_end_message(message: String, color: Color) -> void:
	if not _label:
		return

	_label.text = message
	_label.add_theme_font_size_override("font_size", end_font_size)
	_label.add_theme_color_override("font_color", color)

	# Clear any "+5s" popup that's still fading out.
	if _bonus_tween and _bonus_tween.is_valid():
		_bonus_tween.kill()
	if _bonus_label:
		_bonus_label.modulate.a = 0.0


func _show_bonus(seconds: float) -> void:
	if not _bonus_label or is_zero_approx(seconds):
		return

	var amount_text: String = ("%.1f" % absf(seconds)).trim_suffix(".0")
	var sign_text: String = "+" if seconds > 0.0 else "-"
	_bonus_label.text = "%s%ss" % [sign_text, amount_text]
	_bonus_label.modulate.a = 1.0

	if _bonus_tween and _bonus_tween.is_valid():
		_bonus_tween.kill()

	_bonus_tween = create_tween()
	_bonus_tween.tween_interval(0.6)
	_bonus_tween.tween_property(_bonus_label, "modulate:a", 0.0, 0.6)


func _format_time(t: float) -> String:
	var total: int = int(ceil(t))
	return "%d:%02d" % [floori(total / 60.0), total % 60]
