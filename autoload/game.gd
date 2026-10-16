extends Node

signal score_changed(new_score: int)
signal ball_count_changed(balls_left: int)
signal game_over(final_score: int, is_high_score: bool)
signal game_restarted
## player_id, new stored best. Emitted only when that id's best strictly
## increases. Listeners must ignore it unless the id is still current.
signal high_score_changed(player_id: String, value: int)
signal streak_changed(streak: int)
signal big_score_reached(score: int)
signal supercharged()
## The rainbow trio again, after a score milestone. Independent of the
## once-per-game streak supercharge. 100_000, then 250_000, then double
## (500_000, 1_000_000, 2_000_000, ...).
signal rainbow_recalled()
## wave, how many bonus spots are live, points each spot awards.
## Emitted when score crosses another multiple of BOARD_SHIFT_EVERY.
signal board_shifted(wave: int, bonus_count: int, bonus_points: int)

const SAVE_PATH := "user://highscore.save"
const BALLS_PER_GAME := 3
const STREAK_WINDOW_SEC := 2.0
const STREAK_CAP := 5
const BUMPER_POINTS := 100
const BIG_SCORE_THRESHOLD := 10000
const BOARD_SHIFT_EVERY := 5000
## First two rainbow-trio recalls. Later ones double from the second.
const RAINBOW_RECALL_FIRST := 100000
const RAINBOW_RECALL_SECOND := 250000
const _INT64_MAX := 9223372036854775807
const BOARD_BONUS_CAP := 4
const BOARD_BONUS_BASE := 1000
const BOARD_BONUS_STEP := 500
## Bonus stars stop growing once the score reaches this. Later waves keep
## the same stars. Points also never pass BONUS_FREEZE_POINTS, so the
## climb levels off at 25_000 (score 260_000) and stays there.
const BONUS_FREEZE_SCORE := 500000
const BONUS_FREEZE_POINTS := 25000
## Matches server/src/validate.js MAX_SCORE. Anything larger is refused by
## the board, so it is not a high score: not saved, not submitted, and a
## value already in the file is dropped on load. Otherwise one runaway
## game (the local "Dad" best) blocks every later high.
const POSTED_SCORE_MAX := 9999999

enum { READY, PLAYING, GAME_OVER }

var score: int = 0
var balls_left: int = BALLS_PER_GAME
var high_scores: Dictionary = {}
var state: int = READY
var streak: int = 0

var high_score: int:
	get:
		return _high_for(_current_player_id())
	set(value):
		_set_high_for(_current_player_id(), value)

var _drain_frame: int = -1
var _streak_remaining: float = 0.0
var _big_score_emitted: bool = false
var _supercharged_emitted: bool = false
## Next rainbow-recall milestone. 0 is 100_000, 1 is 250_000, then doubles.
var _rainbow_recall_index: int = 0
## True from emit until the split lands or the run resets. A miss (no ball
## in play) stays pending so the trio still arrives with the next ball.
var _rainbow_recall_pending: bool = false
var board_wave: int = 0


func _ready() -> void:
	_load_high_scores()
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
	_advance_board_wave()
	_try_rainbow_recall()
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
	if streak == 3 and not _supercharged_emitted:
		supercharged.emit()
		print("Game supercharged streak=%d" % streak)
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
	# A score the board will refuse must not become the stored best. The
	# run still reports its real total; HIGH stays the last legal one.
	var is_high := score <= POSTED_SCORE_MAX and score > high_score
	if is_high:
		high_score = score
	game_over.emit(score, is_high)
	print("Game game_over final_score=%d is_high_score=%s high_score=%d" % [score, is_high, high_score])


func note_supercharge_applied() -> void:
	_supercharged_emitted = true


## Milestone index → score. 100_000, 250_000, 500_000, 1_000_000, ...
## Returns -1 past the positive int64 range.
func rainbow_recall_threshold(index: int) -> int:
	if index < 0:
		return -1
	if index == 0:
		return RAINBOW_RECALL_FIRST
	var steps := index - 1
	if steps >= 62:
		return -1
	if RAINBOW_RECALL_SECOND > (_INT64_MAX >> steps):
		return -1
	return RAINBOW_RECALL_SECOND << steps


## Table calls this after the milestone split actually puts balls in play.
## A trigger with no ball leaves the milestone pending.
func note_rainbow_recall_applied() -> void:
	if not _rainbow_recall_pending:
		return
	_rainbow_recall_pending = false
	_rainbow_recall_index += 1
	_try_rainbow_recall()


func _try_rainbow_recall() -> void:
	if state == GAME_OVER or _rainbow_recall_pending:
		return
	var threshold := rainbow_recall_threshold(_rainbow_recall_index)
	if threshold < 0 or score < threshold:
		return
	_rainbow_recall_pending = true
	rainbow_recalled.emit()
	print("Game rainbow_recalled score=%d threshold=%d" % [score, threshold])


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


func bonus_offer(wave: int) -> Dictionary:
	var freeze_wave := int(BONUS_FREEZE_SCORE / BOARD_SHIFT_EVERY)
	var used := mini(maxi(wave, 0), freeze_wave)
	var count := mini(used, BOARD_BONUS_CAP)
	var extra := maxi(0, used - BOARD_BONUS_CAP)
	var points := BOARD_BONUS_BASE + BOARD_BONUS_STEP * extra
	if points > BONUS_FREEZE_POINTS:
		points = BONUS_FREEZE_POINTS
	return {
		"count": count,
		"points": points,
	}


func score_is_postable(value: int) -> bool:
	return value > 0 and value <= POSTED_SCORE_MAX


func _advance_board_wave() -> void:
	var wave := int(score / BOARD_SHIFT_EVERY)
	if wave <= board_wave:
		return
	board_wave = wave
	var offer := bonus_offer(wave)
	board_shifted.emit(wave, int(offer["count"]), int(offer["points"]))
	print(
		"Game board_shifted wave=%d bonuses=%d points=%d"
		% [wave, int(offer["count"]), int(offer["points"])]
	)


func _reset_run() -> void:
	var previous_wave := board_wave
	score = 0
	balls_left = BALLS_PER_GAME
	state = READY
	_drain_frame = -1
	_big_score_emitted = false
	_supercharged_emitted = false
	_rainbow_recall_index = 0
	_rainbow_recall_pending = false
	board_wave = 0
	_clear_streak()
	if previous_wave != 0:
		board_shifted.emit(0, 0, 0)
		print("Game board_shifted wave=0 bonuses=0 points=0")


func _clear_streak() -> void:
	_streak_remaining = 0.0
	if streak == 0:
		return
	streak = 0
	streak_changed.emit(0)
	print("Game streak_changed streak=0")


func _current_player_id() -> String:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return ""
	return String(profile.get("player_id"))


func _high_for(player_id: String) -> int:
	if player_id.is_empty():
		return 0
	return int(high_scores.get(player_id, 0))


func _set_high_for(player_id: String, value: int) -> void:
	if player_id.is_empty():
		return
	if not _accept_high(value):
		return
	high_scores[player_id] = int(value)
	_save_high_scores()


## D-057. Persist max(this device's best, server_best) for the id the request
## was made for. A late response must not stamp that best onto whoever became
## current in the meantime, and a smaller server number must not lower the file.
func reconcile_best(player_id: String, server_best: int) -> void:
	if player_id.is_empty():
		return
	if not _accept_high(server_best):
		return
	var device := _high_for(player_id)
	if not _accept_high(device):
		device = 0
	if server_best <= device:
		return
	_set_high_for(player_id, server_best)
	high_score_changed.emit(player_id, server_best)


func _load_high_scores() -> void:
	high_scores = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	var parsed: Dictionary = data
	if parsed.has("high_scores") and typeof(parsed["high_scores"]) == TYPE_DICTIONARY:
		var src: Dictionary = parsed["high_scores"]
		var dropped := false
		for key_variant in src.keys():
			var value := int(src[key_variant])
			if not _accept_high(value):
				dropped = true
				continue
			high_scores[String(key_variant)] = value
		if dropped:
			_save_high_scores()
		return
	if parsed.has("high_score"):
		var id := _current_player_id()
		if id.is_empty():
			return
		var legacy := int(parsed["high_score"])
		if _accept_high(legacy):
			high_scores[id] = legacy
		_save_high_scores()


func _save_high_scores() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Game: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"high_scores": high_scores}))


func _accept_high(value: int) -> bool:
	return value >= 0 and value <= POSTED_SCORE_MAX


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
