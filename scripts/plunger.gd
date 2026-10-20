extends Node2D

## Drawn plunger at the shooter-lane floor. No collision and no effect on
## the ball. Colours come from Theme so a mid-game palette cycle repaints it.
## The pull cue uses Launcher.lane_ball() — the same body launch() would fire —
## and the snap plays only on Launcher.launched.

const LANE_LEFT := 636.0
const LANE_RIGHT := 696.0
const FLOOR_TOP := 1232.0
const FLOOR_BOTTOM := 1280.0
const HEAD_HALF_W := 16.0
const HEAD_HALF_H := 6.0
const PULL_TRAVEL := 22.0
const SPRING_BOTTOM := 32.0
const COILS := 5
const CHEVRON_X := 20.0
const CHEVRON_REACH := 25.0
const OVERSHOOT := 0.06
const RELEASE_SEC := 0.24
const CUE_PERIOD := 1.4
const CUE_PULL_MIN := 0.30
const CUE_PULL_MAX := 0.75

var _pull := 0.0
var _releasing := false
var _release_from := 0.0
var _release_elapsed := 0.0
var _cue_time := 0.0
var _cue_alpha := 0.0


func _ready() -> void:
	var launcher := get_parent()
	if launcher != null and launcher.has_signal("launched"):
		if not launcher.launched.is_connected(_on_launched):
			launcher.launched.connect(_on_launched)
	var theme := get_node_or_null("/root/Theme")
	if theme != null and theme.has_signal("palette_changed"):
		if not theme.palette_changed.is_connected(_on_palette_changed):
			theme.palette_changed.connect(_on_palette_changed)
	queue_redraw()


func _process(delta: float) -> void:
	if _releasing:
		_release_elapsed += delta
		var u := clampf(_release_elapsed / RELEASE_SEC, 0.0, 1.0)
		if u < 0.72:
			var snap := 1.0 - pow(1.0 - (u / 0.72), 3.0)
			_pull = lerpf(_release_from, -OVERSHOOT, snap)
		else:
			var settle := ((u - 0.72) / 0.28)
			settle = settle * settle
			_pull = lerpf(-OVERSHOOT, 0.0, settle)
		_cue_alpha = 0.0
		if u >= 1.0:
			_releasing = false
			_pull = 0.0
	elif _ball_waiting():
		_cue_time += delta
		var wave := 0.5 - 0.5 * cos(TAU * _cue_time / CUE_PERIOD)
		_pull = lerpf(CUE_PULL_MIN, CUE_PULL_MAX, wave)
		var blink := 0.5 - 0.5 * cos(TAU * _cue_time / (CUE_PERIOD * 0.5))
		_cue_alpha = lerpf(0.55, 1.0, blink)
	else:
		_pull = 0.0
		_cue_time = 0.0
		_cue_alpha = 0.0
	queue_redraw()


func shows_cue() -> bool:
	return _ball_waiting() and not _releasing


func cue_alpha() -> float:
	if not shows_cue():
		return 0.0
	return _cue_alpha


func pull_amount() -> float:
	return _pull


func is_releasing() -> bool:
	return _releasing


func at_rest() -> bool:
	return not _releasing and absf(_pull) <= 0.001


func head_color() -> Color:
	return _role("object_yellow", Color("ffd21c"))


## Every drawn point stays inside the lane interior and on the floor.
func fits_lane() -> bool:
	var origin := global_position
	var min_x := origin.x - CHEVRON_REACH
	var max_x := origin.x + CHEVRON_REACH
	var min_y := origin.y - OVERSHOOT * PULL_TRAVEL - HEAD_HALF_H
	var max_y := origin.y + SPRING_BOTTOM
	return (
		min_x >= LANE_LEFT
		and max_x <= LANE_RIGHT
		and min_y >= FLOOR_TOP
		and max_y <= FLOOR_BOTTOM
	)


func _on_launched(_impulse: float) -> void:
	_release_from = maxf(_pull, 0.62)
	_pull = _release_from
	_releasing = true
	_release_elapsed = 0.0
	_cue_alpha = 0.0
	queue_redraw()


func _on_palette_changed(_id: String = "") -> void:
	queue_redraw()


func _ball_waiting() -> bool:
	var launcher := get_parent()
	if launcher == null or not launcher.has_method("lane_ball"):
		return false
	var body: Node = launcher.lane_ball()
	return body != null and is_instance_valid(body)


func _draw() -> void:
	var head := head_color()
	var spring := _role("object_white", Color("f7f4ff"))
	var base := _role("rail_primary", Color("5635d6"))
	var knob := _role("object_orange", Color("ff9e18"))
	var head_y := _pull * PULL_TRAVEL
	var base_top := SPRING_BOTTOM - 5.0
	draw_rect(Rect2(-14.0, base_top, 28.0, 5.0), base)
	var coil_top := head_y + HEAD_HALF_H
	var span := base_top - coil_top
	draw_line(Vector2(0.0, coil_top), Vector2(0.0, base_top), spring, 2.0)
	if span > 1.0:
		var pts := PackedVector2Array()
		pts.append(Vector2(0.0, coil_top))
		for i in COILS:
			var along := float(i + 1) / float(COILS + 1)
			var y := coil_top + span * along
			var x := 7.0 if (i % 2 == 0) else -7.0
			pts.append(Vector2(x, y))
		pts.append(Vector2(0.0, base_top))
		draw_polyline(pts, spring, 2.0, true)
	_draw_head(Vector2(0.0, head_y), head, knob)
	if shows_cue() and _cue_alpha > 0.0:
		var chevron := _role("glow_gold", Color("fff06a"))
		chevron.a = _cue_alpha
		_draw_chevron(Vector2(-CHEVRON_X, head_y), chevron)
		_draw_chevron(Vector2(CHEVRON_X, head_y), chevron)


func _draw_head(center: Vector2, color: Color, knob: Color) -> void:
	var cap := HEAD_HALF_H
	var body_w := (HEAD_HALF_W - cap) * 2.0
	draw_rect(Rect2(center.x - HEAD_HALF_W + cap, center.y - cap, body_w, cap * 2.0), color)
	draw_circle(Vector2(center.x - HEAD_HALF_W + cap, center.y), cap, color)
	draw_circle(Vector2(center.x + HEAD_HALF_W - cap, center.y), cap, color)
	draw_circle(center, 3.5, knob)


func _draw_chevron(origin: Vector2, color: Color) -> void:
	var left := origin + Vector2(-5.0, -3.5)
	var mid := origin + Vector2(0.0, 3.5)
	var right := origin + Vector2(5.0, -3.5)
	draw_line(left, mid, color, 2.0)
	draw_line(mid, right, color, 2.0)
	var lower := origin + Vector2(0.0, 8.0)
	draw_line(lower + Vector2(-3.5, -2.5), lower, color, 1.5)
	draw_line(lower, lower + Vector2(3.5, -2.5), color, 1.5)


func _role(role: String, fallback: Color) -> Color:
	var theme := get_node_or_null("/root/Theme")
	if theme != null and theme.has_method("color"):
		return theme.color(role)
	return fallback
