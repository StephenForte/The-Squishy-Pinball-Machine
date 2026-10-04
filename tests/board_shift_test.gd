extends SceneTree

## Every 5000 points rotates bumpers and targets through their home slots
## and adds pass-through bonus stars. Restart restores the scene layout.

const HOST_PATHS: Array[String] = [
	"Bumper1",
	"Bumper2",
	"Bumper3",
	"TargetBank/TargetLeft",
	"TargetBank/TargetRight",
	"TargetBank/TargetTop",
	"TargetBank/TargetLeft2",
	"TargetBank/TargetRight2",
]
const CLEARANCE := 80.0

var _game: Node
var _table: Node2D
var _hud: Node
var _board_label: Label
var _homes: Dictionary = {}
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("BOARD_SHIFT start")
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load scenes/main.tscn")
		return
	await process_frame
	await physics_frame
	_game = get_node_or_null("/root/Game")
	_table = current_scene.get_node_or_null("Table") as Node2D
	_hud = current_scene.get_node_or_null("HUD")
	if _game == null or _table == null or _hud == null:
		_fail("Game, Table, or HUD missing")
		return
	if not _game.has_signal("board_shifted") or not _game.has_method("bonus_offer"):
		_fail("board shift API missing")
		return
	_board_label = _hud.get_node_or_null("BoardLabel") as Label
	if _board_label == null:
		_fail("BoardLabel missing")
		return
	var drain := _table.get_node_or_null("Drain") as Area2D
	if drain != null:
		drain.monitoring = false
	_game.restart()
	await process_frame
	for path in HOST_PATHS:
		var host := _table.get_node_or_null(path) as Node2D
		if host == null:
			_fail("missing host %s" % path)
			return
		_homes[path] = host.position

	if not await _case_1_below_threshold():
		return
	if not await _case_2_first_wave():
		return
	if not await _case_3_grows_and_jumps():
		return
	if not await _case_4_restart():
		return
	if not await _case_5_orb_awards_once_per_visit():
		return
	if not await _case_6_game_over():
		return
	if not await _case_7_later_waves():
		return

	print("BOARD_SHIFT PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_below_threshold() -> bool:
	print("BOARD_SHIFT case 1 below 5000")
	_game.restart()
	await process_frame
	var bumper := _host("Bumper1")
	var before: Vector2 = bumper.position
	var emits: Array = []
	var on_shift := func(wave: int, bonus_count: int, bonus_points: int) -> void:
		emits.append([wave, bonus_count, bonus_points])
	_game.board_shifted.connect(on_shift)
	_game.add_score(4999)
	_game.board_shifted.disconnect(on_shift)
	if int(_game.score) != 4999 or int(_game.board_wave) != 0:
		return _fail("case 1: score=%s wave=%s" % [_game.score, _game.board_wave])
	if not emits.is_empty():
		return _fail("case 1: emitted %s" % emits)
	if bumper.position != before or not _layout_is_home():
		return _fail("case 1: layout moved below 5000")
	if _live_bonuses().size() != 0:
		return _fail("case 1: bonuses=%d" % _live_bonuses().size())
	if _board_label.visible:
		return _fail("case 1: BoardLabel visible")
	_cases_passed += 1
	print("BOARD_SHIFT case 1 pass")
	return true


func _case_2_first_wave() -> bool:
	print("BOARD_SHIFT case 2 first wave")
	_game.restart()
	await process_frame
	var home: Vector2 = _host("Bumper1").position
	_game.add_score(5000)
	await process_frame
	if int(_game.board_wave) != 1:
		return _fail("case 2: wave=%s" % _game.board_wave)
	var bumper := _host("Bumper1")
	if bumper.position.distance_to(home) < 1.0:
		return _fail("case 2: Bumper1 stayed at %s" % bumper.position)
	if not _layout_is_permutation():
		return _fail("case 2: hosts left the home slots")
	var bonuses := _live_bonuses()
	if bonuses.size() != 1:
		return _fail("case 2: bonuses=%d" % bonuses.size())
	var orb := bonuses[0] as Node2D
	if int(orb.get("points")) != 1000:
		return _fail("case 2: orb points=%s" % orb.get("points"))
	if not orb.is_in_group("bonuses") or orb.is_in_group("squishies") or orb.is_in_group("bumpers") or orb.is_in_group("targets"):
		return _fail("case 2: orb groups wrong")
	if not _bonuses_clear_of_hosts():
		return _fail("case 2: bonus overlaps a host")
	if not _board_label.visible:
		return _fail("case 2: BoardLabel hidden")
	if _board_label.text != "LAYOUT 1  ·  BONUS ×1  1000":
		return _fail("case 2: label '%s'" % _board_label.text)
	if _board_label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return _fail("case 2: BoardLabel mouse_filter=%s" % _board_label.mouse_filter)
	var offer: Dictionary = _game.bonus_offer(1)
	if int(offer["count"]) != 1 or int(offer["points"]) != 1000:
		return _fail("case 2: offer %s" % offer)
	_cases_passed += 1
	print("BOARD_SHIFT case 2 pass")
	return true


func _case_3_grows_and_jumps() -> bool:
	print("BOARD_SHIFT case 3 second wave and jump")
	_game.restart()
	await process_frame
	_game.add_score(5000)
	var wave1: Vector2 = _host("Bumper1").position
	var emits: Array = []
	var on_shift := func(wave: int, bonus_count: int, bonus_points: int) -> void:
		emits.append([wave, bonus_count, bonus_points])
	_game.board_shifted.connect(on_shift)
	_game.add_score(5000)
	_game.board_shifted.disconnect(on_shift)
	if emits.size() != 1 or int(emits[0][0]) != 2 or int(emits[0][1]) != 2 or int(emits[0][2]) != 1000:
		return _fail("case 3: step emit %s" % emits)
	if int(_game.board_wave) != 2 or int(_game.score) != 10000:
		return _fail("case 3: wave=%s score=%s" % [_game.board_wave, _game.score])
	if _live_bonuses().size() != 2:
		return _fail("case 3: bonuses=%d" % _live_bonuses().size())
	var wave2: Vector2 = _host("Bumper1").position
	if wave2.distance_to(wave1) < 1.0 or wave2.distance_to(_homes["Bumper1"]) < 1.0:
		return _fail("case 3: wave 2 layout %s wave1=%s home=%s" % [wave2, wave1, _homes["Bumper1"]])
	if not _layout_is_permutation() or not _bonuses_clear_of_hosts():
		return _fail("case 3: wave 2 layout invalid")
	if _board_label.text != "LAYOUT 2  ·  BONUS ×2  1000":
		return _fail("case 3: label '%s'" % _board_label.text)

	_game.restart()
	await process_frame
	emits.clear()
	_game.board_shifted.connect(on_shift)
	_game.add_score(10000)
	_game.board_shifted.disconnect(on_shift)
	if emits.size() != 1 or int(emits[0][0]) != 2:
		return _fail("case 3: jump emit %s" % emits)
	if int(_game.board_wave) != 2 or _live_bonuses().size() != 2:
		return _fail("case 3: jump wave=%s bonuses=%d" % [_game.board_wave, _live_bonuses().size()])
	if _host("Bumper1").position.distance_to(wave2) > 1.0:
		return _fail("case 3: jump layout %s expected %s" % [_host("Bumper1").position, wave2])
	_cases_passed += 1
	print("BOARD_SHIFT case 3 pass")
	return true


func _case_4_restart() -> bool:
	print("BOARD_SHIFT case 4 restart")
	_game.restart()
	await process_frame
	_game.add_score(5000)
	if _live_bonuses().is_empty():
		return _fail("case 4: expected a bonus before restart")
	_game.restart()
	await process_frame
	await physics_frame
	if int(_game.score) != 0 or int(_game.board_wave) != 0:
		return _fail("case 4: score=%s wave=%s" % [_game.score, _game.board_wave])
	if not _layout_is_home():
		return _fail("case 4: layout not restored")
	if _live_bonuses().size() != 0:
		return _fail("case 4: bonuses survived restart")
	if _board_label.visible:
		return _fail("case 4: BoardLabel still visible")

	var armed := [true]
	var saw_physics := [false]
	var on_physics := func() -> void:
		if not armed[0] or not Engine.is_in_physics_frame():
			return
		armed[0] = false
		saw_physics[0] = true
		_game.add_score(5000)
		_game.restart()
	physics_frame.connect(on_physics)
	for _i in 8:
		if not armed[0]:
			break
		await process_frame
	if physics_frame.is_connected(on_physics):
		physics_frame.disconnect(on_physics)
	if not saw_physics[0]:
		return _fail("case 4: did not enter a physics frame")
	await process_frame
	await physics_frame
	if int(_game.board_wave) != 0 or int(_game.score) != 0:
		return _fail("case 4: physics restart left wave=%s score=%s" % [_game.board_wave, _game.score])
	if not _layout_is_home() or _live_bonuses().size() != 0 or _board_label.visible:
		return _fail("case 4: deferred wave landed after restart")
	_cases_passed += 1
	print("BOARD_SHIFT case 4 pass")
	return true


func _case_5_orb_awards_once_per_visit() -> bool:
	print("BOARD_SHIFT case 5 bonus visit")
	_game.restart()
	await process_frame
	await _free_balls()
	_game.add_score(5000)
	var bonuses := _live_bonuses()
	if bonuses.size() != 1:
		return _fail("case 5: bonuses=%d" % bonuses.size())
	var orb := bonuses[0] as Node2D
	var worth := int(orb.get("points"))
	var ball := await _spawn_ball(orb.global_position + Vector2(0, 180))
	if ball == null:
		return _fail("case 5: no ball")
	var start := int(_game.score)
	_place_ball(ball, orb.global_position)
	var scored := false
	for _i in 20:
		await physics_frame
		if int(_game.score) != start:
			scored = true
			break
	if not scored or int(_game.score) - start != worth:
		return _fail("case 5: first visit +%d expected +%d" % [int(_game.score) - start, worth])
	var held := int(_game.score)
	for _i in 30:
		await physics_frame
		_place_ball(ball, orb.global_position)
	if int(_game.score) != held:
		return _fail("case 5: overlap scored again +%d" % (int(_game.score) - held))
	_place_ball(ball, orb.global_position + Vector2(0, 180))
	for _i in 8:
		await physics_frame
	var away := Time.get_ticks_msec()
	while Time.get_ticks_msec() - away < 500:
		await process_frame
	var before_return := int(_game.score)
	_place_ball(ball, orb.global_position)
	scored = false
	for _i in 20:
		await physics_frame
		if int(_game.score) != before_return:
			scored = true
			break
	if not scored or int(_game.score) - before_return != worth:
		return _fail("case 5: return visit +%d expected +%d" % [int(_game.score) - before_return, worth])
	if int(_game.board_wave) != 1:
		return _fail("case 5: wave moved to %s" % _game.board_wave)
	_cases_passed += 1
	print("BOARD_SHIFT case 5 pass")
	return true


func _case_6_game_over() -> bool:
	print("BOARD_SHIFT case 6 game over")
	_game.restart()
	await process_frame
	var bumper := _host("Bumper1")
	var before: Vector2 = bumper.position
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	if int(_game.state) != int(_game.GAME_OVER):
		return _fail("case 6: state=%s" % _game.state)
	_game.add_score(5000)
	await process_frame
	if int(_game.score) != 0 or int(_game.board_wave) != 0:
		return _fail("case 6: score=%s wave=%s" % [_game.score, _game.board_wave])
	if bumper.position.distance_to(before) > 0.5 or _live_bonuses().size() != 0:
		return _fail("case 6: board changed after GAME_OVER")
	_cases_passed += 1
	print("BOARD_SHIFT case 6 pass")
	return true


func _case_7_later_waves() -> bool:
	print("BOARD_SHIFT case 7 later waves")
	_game.restart()
	await process_frame
	var offer: Dictionary = _game.bonus_offer(5)
	if int(offer["count"]) != 4 or int(offer["points"]) != 1500:
		return _fail("case 7: offer %s" % offer)
	var early: Dictionary = _game.bonus_offer(4)
	if int(early["count"]) != 4 or int(early["points"]) != 1000:
		return _fail("case 7: wave 4 offer %s" % early)
	_game.add_score(25000)
	await process_frame
	if int(_game.board_wave) != 5:
		return _fail("case 7: wave=%s" % _game.board_wave)
	var bonuses := _live_bonuses()
	if bonuses.size() != 4:
		return _fail("case 7: bonuses=%d" % bonuses.size())
	for node in bonuses:
		if int(node.get("points")) != 1500:
			return _fail("case 7: points=%s" % node.get("points"))
	if not _layout_is_permutation() or not _bonuses_clear_of_hosts():
		return _fail("case 7: layout invalid")
	if _board_label.text != "LAYOUT 5  ·  BONUS ×4  1500":
		return _fail("case 7: label '%s'" % _board_label.text)
	_cases_passed += 1
	print("BOARD_SHIFT case 7 pass")
	return true


func _host(path: String) -> Node2D:
	return _table.get_node(path) as Node2D


func _layout_is_home() -> bool:
	for path in HOST_PATHS:
		var host := _host(path)
		if host.position.distance_to(_homes[path]) > 0.5:
			return false
	return true


func _layout_is_permutation() -> bool:
	var used: Dictionary = {}
	for path in HOST_PATHS:
		var pos: Vector2 = _host(path).position
		var matched := ""
		for home_path in _homes.keys():
			if used.has(home_path):
				continue
			var home: Vector2 = _homes[home_path]
			if pos.distance_to(home) <= 0.5:
				matched = home_path
				break
		if matched.is_empty():
			return false
		used[matched] = true
	return used.size() == HOST_PATHS.size()


func _live_bonuses() -> Array:
	var out: Array = []
	for node in get_nodes_in_group("bonuses"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			out.append(node)
	return out


func _bonuses_clear_of_hosts() -> bool:
	for bonus in _live_bonuses():
		if not (bonus is Node2D):
			return false
		var at: Vector2 = (bonus as Node2D).global_position
		for path in HOST_PATHS:
			if at.distance_to(_host(path).global_position) < CLEARANCE:
				return false
	return true


func _spawn_ball(pos: Vector2) -> RigidBody2D:
	var packed := load("res://scenes/ball.tscn") as PackedScene
	if packed == null:
		return null
	var ball := packed.instantiate() as RigidBody2D
	ball.position = pos
	ball.gravity_scale = 0.0
	ball.can_sleep = false
	_table.add_child(ball)
	_place_ball(ball, pos)
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	if not is_instance_valid(ball):
		return null
	_place_ball(ball, pos)
	return ball


func _place_ball(ball: RigidBody2D, pos: Vector2) -> void:
	ball.gravity_scale = 0.0
	ball.can_sleep = false
	ball.sleeping = false
	ball.freeze = false
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.global_position = pos
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, pos)
	)


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _fail(message: String) -> bool:
	push_error("BOARD_SHIFT FAIL %s" % message)
	print("BOARD_SHIFT FAIL %s" % message)
	quit(1)
	return false
