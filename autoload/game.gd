extends Node

signal score_changed(new_score: int)
signal ball_count_changed(balls_left: int)
signal game_over(final_score: int, is_high_score: bool)
signal game_restarted
signal streak_changed(streak: int)
signal big_score_reached(score: int)

const SAVE_PATH := "user://highscore.save"
const BALLS_PER_GAME := 3
const STREAK_WINDOW_SEC := 2.0
const STREAK_CAP := 5
const BUMPER_POINTS := 100
const BIG_SCORE_THRESHOLD := 10000

enum { READY, PLAYING, GAME_OVER }

var score: int = 0
var balls_left: int = BALLS_PER_GAME
var high_score: int = 0
var state: int = READY
var streak: int = 0

var _drain_frame: int = -1
var _streak_remaining: float = 0.0
var _big_score_emitted: bool = false


func _ready() -> void:
	high_score = _load_high_score()
	_reset_run()
	print("Game ready high_score=%d balls_left=%d state=%s" % [high_score, balls_left, _state_name()])


func add_score(points: int) -> void:
	if state == GAME_OVER:
		return
	if state == READY:
		state = PLAYING
	score += points
	score_changed.emit(score)
	print("Game score_changed score=%d" % score)
	if not _big_score_emitted and score >= BIG_SCORE_THRESHOLD:
		_big_score_emitted = true
		big_score_reached.emit(score)
		print("Game big_score_reached score=%d" % score)


func register_bumper_hit() -> int:
	if state == GAME_OVER:
		return 0
	if streak > 0 and _streak_remaining > 0.0:
		streak = mini(streak + 1, STREAK_CAP)
	else:
		streak = 1
	_streak_remaining = STREAK_WINDOW_SEC
	var points := BUMPER_POINTS * streak
	add_score(points)
	streak_changed.emit(streak)
	print("Game streak_changed streak=%d points=%d" % [streak, points])
	return points


func on_ball_drained() -> void:
	if state == GAME_OVER:
		return
	_clear_streak()
	var frame := Engine.get_physics_frames()
	if frame == _drain_frame:
		return
	_drain_frame = frame
	if state == READY:
		state = PLAYING
	balls_left -= 1
	if balls_left < 0:
		balls_left = 0
	ball_count_changed.emit(balls_left)
	print("Game ball_count_changed balls_left=%d" % balls_left)
	if balls_left > 0:
		return
	state = GAME_OVER
	var is_high := score > high_score
	if is_high:
		high_score = score
		_save_high_score()
	game_over.emit(score, is_high)
	print("Game game_over final_score=%d is_high_score=%s high_score=%d" % [score, is_high, high_score])


func restart() -> void:
	_reset_run()
	game_restarted.emit()
	print("Game game_restarted score=%d balls_left=%d high_score=%d" % [score, balls_left, high_score])


func _process(delta: float) -> void:
	if streak <= 0:
		return
	_streak_remaining -= delta
	if _streak_remaining <= 0.0:
		_clear_streak()


func _reset_run() -> void:
	score = 0
	balls_left = BALLS_PER_GAME
	state = READY
	_drain_frame = -1
	_big_score_emitted = false
	_clear_streak()


func _clear_streak() -> void:
	_streak_remaining = 0.0
	if streak == 0:
		return
	streak = 0
	streak_changed.emit(0)
	print("Game streak_changed streak=0")


func _load_high_score() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return 0
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return 0
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return 0
	if not (data as Dictionary).has("high_score"):
		return 0
	return int((data as Dictionary)["high_score"])


func _save_high_score() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Game: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"high_score": high_score}))


func _state_name() -> String:
	match state:
		READY:
			return "READY"
		PLAYING:
			return "PLAYING"
		GAME_OVER:
			return "GAME_OVER"
		_:
			return "UNKNOWN"
