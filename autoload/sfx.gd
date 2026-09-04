extends Node

## Autoload Sfx. Plays WAVs from assets/sfx/. Listens to D-018 signals only;
## no gameplay file calls Sfx. Bookkeeping is for headless tests (no audio device).

const SFX_DIR := "res://assets/sfx/"
const STREAM_NAMES := [
	"flipper",
	"bumper",
	"target",
	"all_targets",
	"drain",
	"game_over",
	"big_score",
]
const PLAYER_COUNT := 8
const BUMPER_PITCH_STEP := 0.12

var play_counts: Dictionary = {}
var last_stream: Dictionary = {}
var table_wired: bool = false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	_build_players()
	_load_streams()
	_connect_game()
	await get_tree().process_frame
	if _try_connect_table():
		return
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func play(sfx_name: String, pitch: float = 1.0) -> void:
	play_counts[sfx_name] = int(play_counts.get(sfx_name, 0)) + 1
	var stream: AudioStream = _streams.get(sfx_name) as AudioStream
	last_stream[sfx_name] = stream
	if stream == null or _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % PLAYER_COUNT
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func reset_counts() -> void:
	play_counts.clear()
	last_stream.clear()


func count_of(sfx_name: String) -> int:
	return int(play_counts.get(sfx_name, 0))


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("flipper_left"):
		play("flipper")
	if Input.is_action_just_pressed("flipper_right"):
		play("flipper")


func _build_players() -> void:
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % i
		add_child(player)
		_players.append(player)


func _load_streams() -> void:
	for sfx_name in STREAM_NAMES:
		var path := "%s%s.wav" % [SFX_DIR, sfx_name]
		var loaded: Resource = load(path)
		if loaded is AudioStreamWAV:
			_streams[sfx_name] = loaded


func _connect_game() -> void:
	var game: Node = get_node("/root/Game")
	if not game.ball_count_changed.is_connected(_on_ball_count_changed):
		game.ball_count_changed.connect(_on_ball_count_changed)
	if not game.game_over.is_connected(_on_game_over):
		game.game_over.connect(_on_game_over)
	if not game.big_score_reached.is_connected(_on_big_score_reached):
		game.big_score_reached.connect(_on_big_score_reached)


func _on_node_added(_node: Node) -> void:
	if _try_connect_table() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _try_connect_table() -> bool:
	for bumper in get_tree().get_nodes_in_group("bumpers"):
		if bumper.has_signal("hit") and not bumper.hit.is_connected(_on_bumper_hit):
			bumper.hit.connect(_on_bumper_hit)
	for target in get_tree().get_nodes_in_group("targets"):
		if target.has_signal("hit") and not target.hit.is_connected(_on_target_hit):
			target.hit.connect(_on_target_hit)
	var bank := _find_bank()
	if bank != null and bank.has_signal("all_targets_hit"):
		if not bank.all_targets_hit.is_connected(_on_all_targets_hit):
			bank.all_targets_hit.connect(_on_all_targets_hit)
	var bumpers := get_tree().get_nodes_in_group("bumpers")
	var targets := get_tree().get_nodes_in_group("targets")
	table_wired = bumpers.size() >= 3 and targets.size() >= 3 and bank != null
	return table_wired


func _find_bank() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var named := scene.find_child("TargetBank", true, false)
		if named != null and named.has_signal("all_targets_hit"):
			return named
	for node in get_tree().get_nodes_in_group("targets"):
		var parent: Node = node.get_parent()
		if parent != null and parent.has_signal("all_targets_hit"):
			return parent
	return null


func _on_bumper_hit() -> void:
	var streak: int = int(get_node("/root/Game").streak)
	var pitch := 1.0 + float(maxi(streak - 1, 0)) * BUMPER_PITCH_STEP
	play("bumper", pitch)


func _on_target_hit() -> void:
	play("target")


func _on_all_targets_hit() -> void:
	play("all_targets")


func _on_ball_count_changed(_balls_left: int) -> void:
	play("drain")


func _on_game_over(_final_score: int, _is_high_score: bool) -> void:
	play("game_over")


func _on_big_score_reached(_score: int) -> void:
	play("big_score")
