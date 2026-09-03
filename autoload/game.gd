extends Node

signal score_changed(new_score: int)
signal ball_count_changed(balls_left: int)
signal game_over(final_score: int, is_high_score: bool)
signal game_restarted

const SAVE_PATH := "user://highscore.save"
const BALLS_PER_GAME := 3

enum { READY, PLAYING, GAME_OVER }

var score: int = 0
var balls_left: int = BALLS_PER_GAME
var high_score: int = 0
var state: int = READY

var _drain_frame: int = -1


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


func on_ball_drained() -> void:
	if state == GAME_OVER:
		return
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


func _reset_run() -> void:
	score = 0
	balls_left = BALLS_PER_GAME
	state = READY
	_drain_frame = -1


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
