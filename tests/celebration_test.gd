extends SceneTree

const SAVE_PATH := "user://highscore.save"

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("CELEBRATION start")
	_delete_save()
	var game := root.get_node_or_null("Game")
	var theme_node := root.get_node_or_null("Theme")
	var leaderboard := root.get_node_or_null("Leaderboard")
	if game == null or theme_node == null:
		_fail("could not acquire Game or Theme autoload")
		return
	game.high_score = 0
	game.restart()
	await process_frame

	if not _case_tier_table():
		return

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("main scene did not load")
		return
	await process_frame
	await process_frame
	await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	var game_over := _require_node(main, "GameOver")
	if game_over == null:
		return
	var celebration := game_over.get_node_or_null("Celebration")
	if celebration == null:
		_fail("GameOver missing Celebration")
		return
	var confetti := celebration.get_node_or_null("Confetti")
	var fireworks := celebration.get_node_or_null("Fireworks")
	if confetti == null or fireworks == null:
		_fail("Celebration missing Confetti or Fireworks")
		return
	if not (confetti is CPUParticles2D) or not (fireworks is CPUParticles2D):
		_fail("emitters must be CPUParticles2D")
		return
	print("CELEBRATION emitters are CPUParticles2D")

	if not await _case_confetti_1500(game, celebration, confetti, fireworks):
		return
	if not await _case_fireworks_6000(game, celebration, confetti, fireworks):
		return
	if not await _case_upgrade_and_hold(game, leaderboard, celebration, fireworks):
		return
	if not await _case_restart_clears(game, celebration, confetti, fireworks):
		return
	if not await _case_late_submit_guard(leaderboard, celebration, confetti, fireworks):
		return
	if not await _case_recolour(theme_node, confetti, fireworks):
		return

	print("CELEBRATION PASS cases=%d" % _cases_passed)
	quit(0)


func _case_tier_table() -> bool:
	print("CELEBRATION case tier_for table")
	var script: Script = load("res://scripts/ui/celebration.gd")
	if script == null:
		return _fail("tier_for: could not load celebration.gd")
	var rows: Array = [
		[500, false, 0, "none"],
		[1000, false, 0, "none"],
		[1001, false, 0, "confetti"],
		[5000, false, 0, "confetti"],
		[5001, false, 0, "fireworks"],
		[1500, true, 0, "fireworks"],
		[1500, false, 1, "fireworks"],
		[1500, false, 2, "confetti"],
		[800, true, 1, "none"],
	]
	for row_variant in rows:
		var row: Array = row_variant
		var got: String = script.tier_for(int(row[0]), bool(row[1]), int(row[2]))
		var want: String = String(row[3])
		if got != want:
			return _fail("tier_for(%s,%s,%s) got %s want %s" % [row[0], row[1], row[2], got, want])
		print("CELEBRATION tier_for(%s,%s,%s)->%s" % [row[0], row[1], row[2], got])
	_cases_passed += 1
	print("CELEBRATION case tier_for pass")
	return true


func _case_confetti_1500(game: Node, celebration: Node, confetti: CPUParticles2D, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case 1500 confetti")
	game.high_score = 20000
	game.restart()
	await process_frame
	game.add_score(1500)
	if not await _drain_three(game):
		return false
	await process_frame
	await process_frame
	if String(celebration.tier) != "confetti":
		return _fail("1500: tier=%s expected confetti" % celebration.tier)
	if not confetti.emitting:
		return _fail("1500: Confetti should be emitting")
	if fireworks.emitting:
		return _fail("1500: Fireworks should not be emitting")
	_cases_passed += 1
	print("CELEBRATION case 1500 pass")
	return true


func _case_fireworks_6000(game: Node, celebration: Node, confetti: CPUParticles2D, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case 6000 fireworks")
	game.high_score = 20000
	game.restart()
	await process_frame
	game.add_score(6000)
	if not await _drain_three(game):
		return false
	await process_frame
	await process_frame
	if String(celebration.tier) != "fireworks":
		return _fail("6000: tier=%s expected fireworks" % celebration.tier)
	if not fireworks.emitting:
		return _fail("6000: Fireworks should be emitting")
	if confetti.emitting:
		return _fail("6000: Confetti should not be emitting")
	_cases_passed += 1
	print("CELEBRATION case 6000 pass")
	return true


func _case_upgrade_and_hold(game: Node, leaderboard: Node, celebration: Node, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case upgrade rank 1")
	if leaderboard == null or not leaderboard.has_signal("submitted"):
		return _fail("upgrade: Leaderboard.submitted missing")
	game.high_score = 20000
	game.restart()
	await process_frame
	game.add_score(1500)
	if not await _drain_three(game):
		return false
	await process_frame
	await process_frame
	if String(celebration.tier) != "confetti":
		return _fail("upgrade: starting tier=%s expected confetti" % celebration.tier)
	leaderboard.submitted.emit({
		"rank": 1,
		"best": 20000,
		"is_personal_best": false,
		"total_players": 4,
	})
	await process_frame
	if String(celebration.tier) != "confetti":
		return _fail("upgrade: rank 1 without personal best must stay confetti, got %s" % celebration.tier)
	print("CELEBRATION upgrade rank 1 without PB stays confetti")
	leaderboard.submitted.emit({
		"rank": 1,
		"best": 1500,
		"is_personal_best": true,
		"total_players": 4,
	})
	await process_frame
	if String(celebration.tier) != "fireworks":
		return _fail("upgrade: tier=%s expected fireworks after rank 1 personal best" % celebration.tier)
	if not fireworks.emitting:
		return _fail("upgrade: Fireworks should be emitting after rank 1 personal best")
	print("CELEBRATION upgrade rank 1 personal best -> fireworks")
	leaderboard.submitted.emit({
		"rank": 3,
		"best": 1500,
		"is_personal_best": false,
		"total_players": 4,
	})
	await process_frame
	if String(celebration.tier) != "fireworks":
		return _fail("upgrade: downgraded to %s after rank 3" % celebration.tier)
	_cases_passed += 1
	print("CELEBRATION case upgrade pass")
	return true


func _case_restart_clears(game: Node, celebration: Node, confetti: CPUParticles2D, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case restart clears")
	game.restart()
	await process_frame
	if String(celebration.tier) != "none":
		return _fail("restart: tier=%s expected none" % celebration.tier)
	if confetti.emitting or fireworks.emitting:
		return _fail("restart: emitters still on")
	_cases_passed += 1
	print("CELEBRATION case restart pass")
	return true


func _case_late_submit_guard(leaderboard: Node, celebration: Node, confetti: CPUParticles2D, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case late submitted guard")
	if leaderboard == null:
		return _fail("guard: Leaderboard missing")
	leaderboard.submitted.emit({
		"rank": 1,
		"best": 1500,
		"is_personal_best": true,
		"total_players": 4,
	})
	await process_frame
	if String(celebration.tier) != "none":
		return _fail("guard: late submit set tier=%s" % celebration.tier)
	if confetti.emitting or fireworks.emitting:
		return _fail("guard: late submit started emitters")
	_cases_passed += 1
	print("CELEBRATION case late submit pass")
	return true


func _case_recolour(theme_node: Node, confetti: CPUParticles2D, fireworks: CPUParticles2D) -> bool:
	print("CELEBRATION case recolour")
	var before_c: Color = confetti.color
	var before_f: Color = fireworks.color
	var current := String(theme_node.get("palette_id"))
	var other := "grape_jam" if current != "grape_jam" else "aqua_pool"
	theme_node.set_palette(other)
	await process_frame
	if confetti.color == before_c and fireworks.color == before_f:
		return _fail("recolour: neither emitter color changed after set_palette")
	if confetti.color == before_c:
		return _fail("recolour: Confetti.color unchanged")
	if fireworks.color == before_f:
		return _fail("recolour: Fireworks.color unchanged")
	theme_node.set_palette(current)
	_cases_passed += 1
	print("CELEBRATION case recolour pass")
	return true


func _drain_three(game: Node) -> bool:
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	return true


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _require_node(root_node: Node, node_name: String) -> Node:
	var node := root_node.find_child(node_name, true, false)
	if node == null:
		_fail("missing node %s" % node_name)
	return node


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("highscore.save"):
		dir.remove("highscore.save")


func _fail(message: String) -> bool:
	push_error("CELEBRATION FAIL %s" % message)
	print("CELEBRATION FAIL %s" % message)
	quit(1)
	return false
