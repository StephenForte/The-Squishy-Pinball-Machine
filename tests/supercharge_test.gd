extends SceneTree

const BALL_PATH := "res://scenes/ball.tscn"
const MAIN_PATH := "res://scenes/main.tscn"
const VIEWPORT := Rect2(0, 0, 720, 1280)
const SOAK_BOUNDS := Rect2(-8, -8, 736, 1320)
const MARGIN := 8.0
const BALL_DIAMETER := 24.0
const SOAK_FRAMES := 3000

var _game: Node
var _table: Node2D
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("SUPERCHARGE start")
	BallTraits.load_from()
	if not await _case_1_catalog_apply():
		return
	if not await _case_2_visual_leaves_physics():
		return
	if not await _case_4_catalog_degrades():
		return
	if not await _boot_main():
		return
	if not await _case_3_turbo_bounds():
		return
	if not await _case_5_emits_once():
		return
	if not await _case_6_split_traits():
		return
	if not await _case_7_last_ball_life():
		return
	if not await _case_8_same_frame_drain():
		return
	if not await _case_9_once_per_game():
		return
	if not await _case_10_no_ball_keeps_flag():
		return
	if not await _case_11_three_lives():
		return
	if not await _case_12_supercharged_soak():
		return

	print("SUPERCHARGE PASS cases=%d" % _cases_passed)
	quit(0)


func _boot_main() -> bool:
	print("SUPERCHARGE boot main")
	if change_scene_to_file(MAIN_PATH) != OK:
		return _fail("could not load scenes/main.tscn")
	await process_frame
	await physics_frame
	await process_frame
	_game = root.get_node_or_null("Game")
	_table = current_scene.get_node_or_null("Table") if current_scene != null else null
	if _game == null or _table == null:
		return _fail("Game or Table missing after main load")
	return true


func _case_1_catalog_apply() -> bool:
	print("SUPERCHARGE case 1 catalog apply")
	BallTraits.load_from()
	var ids := BallTraits.trait_ids()
	if ids.is_empty():
		return _fail("case 1: catalog yielded no trait ids")
	var ball := await _standalone_ball(Vector2(360, 640))
	if ball == null:
		return _fail("case 1: could not make a ball")
	for id in ids:
		if not bool(ball.call("apply_trait", id)):
			return _fail("case 1: apply_trait('%s') returned false" % id)
		if not bool(ball.call("has_trait", id)):
			return _fail("case 1: trait '%s' not active after apply" % id)
	var before_ids: PackedStringArray = ball.call("active_trait_ids")
	var mass_before := ball.mass
	var vel_before := ball.linear_velocity
	if bool(ball.call("apply_trait", "nope")):
		return _fail("case 1: apply_trait('nope') should be false")
	var after_ids: PackedStringArray = ball.call("active_trait_ids")
	if after_ids != before_ids:
		return _fail("case 1: unknown id changed active traits %s → %s" % [before_ids, after_ids])
	if ball.mass != mass_before or ball.linear_velocity != vel_before:
		return _fail("case 1: unknown id changed body state")
	ball.queue_free()
	await process_frame
	_cases_passed += 1
	print("SUPERCHARGE case 1 pass ids=%s" % [ids])
	return true


func _case_2_visual_leaves_physics() -> bool:
	print("SUPERCHARGE case 2 visual physics")
	BallTraits.load_from()
	var visual_id := _first_visual_trait_id()
	if visual_id.is_empty():
		return _fail("case 2: catalog has no visual trait")
	var ball := await _standalone_ball(Vector2(360, 640))
	if ball == null:
		return _fail("case 2: could not make a ball")
	var mass_before := ball.mass
	var grav_before := ball.gravity_scale
	var mat_before := ball.physics_material_override
	var radius_before := _collider_radius(ball)
	if not bool(ball.call("apply_trait", visual_id)):
		return _fail("case 2: apply_trait('%s') failed" % visual_id)
	if ball.mass != mass_before:
		return _fail("case 2: mass changed %s → %s" % [mass_before, ball.mass])
	if ball.gravity_scale != grav_before:
		return _fail("case 2: gravity_scale changed")
	if ball.physics_material_override != mat_before:
		return _fail("case 2: physics_material_override changed")
	if not is_equal_approx(_collider_radius(ball), radius_before):
		return _fail("case 2: collider radius changed")
	ball.queue_free()
	await process_frame
	_cases_passed += 1
	print("SUPERCHARGE case 2 pass trait=%s" % visual_id)
	return true


func _case_3_turbo_bounds() -> bool:
	print("SUPERCHARGE case 3 turbo bounds")
	BallTraits.load_from()
	var spec := BallTraits.entry("turbo")
	if spec.is_empty():
		return _fail("case 3: turbo missing from catalog")
	var physics: Dictionary = spec.get("physics", {})
	var scale := float(physics.get("speed_scale", 1.0))
	var min_speed := float(physics.get("min_speed", 0.0))
	var max_speed := float(physics.get("max_speed", 0.0))
	var duration := float(spec.get("duration_sec", physics.get("duration_sec", 0.0)))
	if duration <= 0.0 or max_speed <= 0.0:
		return _fail("case 3: turbo must have positive duration_sec and max_speed")
	await _free_balls()
	var ball := await _place_ball(Vector2(360, 640), Vector2(300, 0))
	if ball == null:
		return _fail("case 3: could not make a ball")
	_table.get_node("Drain").monitoring = false
	ball.linear_velocity = Vector2(300, 0)
	if not bool(ball.call("apply_trait", "turbo")):
		return _fail("case 3: apply_trait('turbo') failed")
	var granted := ball.linear_velocity.length()
	var expected := minf(300.0 * scale, max_speed)
	if absf(granted - expected) > 1.0:
		return _fail("case 3: grant speed %s expected ~%s" % [granted, expected])
	ball.linear_velocity = Vector2(12, 0)
	await physics_frame
	await physics_frame
	if ball.linear_velocity.length() + 0.5 < min_speed:
		return _fail("case 3: speed %s below min_speed %s" % [ball.linear_velocity.length(), min_speed])
	ball.linear_velocity = Vector2(max_speed * 4.0, 0)
	await physics_frame
	await physics_frame
	if ball.linear_velocity.length() > max_speed + 1.0:
		return _fail("case 3: speed %s exceeded max_speed %s" % [ball.linear_velocity.length(), max_speed])
	ball.freeze = true
	var wait_frames := int(ceil(duration * 120.0)) + 8
	print("SUPERCHARGE case 3 waiting %d frames for turbo expiry" % wait_frames)
	for _i in wait_frames:
		await physics_frame
	ball.freeze = false
	if bool(ball.call("has_trait", "turbo")):
		return _fail("case 3: turbo still active after duration_sec")
	ball.linear_velocity = Vector2(0, 50)
	await physics_frame
	await physics_frame
	if ball.linear_velocity.length() >= min_speed:
		return _fail(
			"case 3: after expiry speed %s should be able to sit below min_speed %s"
			% [ball.linear_velocity.length(), min_speed]
		)
	ball.queue_free()
	_table.get_node("Drain").monitoring = true
	await process_frame
	_cases_passed += 1
	print(
		"SUPERCHARGE case 3 pass scale=%s min=%s max=%s duration=%s"
		% [scale, min_speed, max_speed, duration]
	)
	return true


func _case_4_catalog_degrades() -> bool:
	print("SUPERCHARGE case 4 catalog degrades")
	var warnings_before := BallTraits.warning_count
	BallTraits.load_from("res://assets/design/ball_traits_missing.json")
	if not BallTraits.trait_ids().is_empty():
		BallTraits.load_from()
		return _fail("case 4: missing catalog still listed traits")
	if BallTraits.warning_count != warnings_before + 1:
		BallTraits.load_from()
		return _fail("case 4: missing catalog warnings=%d expected %d" % [BallTraits.warning_count, warnings_before + 1])
	var bad_path := "user://ball_traits_bad.json"
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	if file == null:
		BallTraits.load_from()
		return _fail("case 4: could not write malformed catalog")
	file.store_string("{\"schema_version\":1}")
	file = null
	BallTraits.load_from(bad_path)
	if not BallTraits.trait_ids().is_empty():
		BallTraits.load_from()
		return _fail("case 4: malformed catalog still listed traits")
	if BallTraits.warning_count != warnings_before + 2:
		BallTraits.load_from()
		return _fail("case 4: malformed catalog warnings=%d expected %d" % [BallTraits.warning_count, warnings_before + 2])
	var packed: PackedScene = load(BALL_PATH)
	var ball := packed.instantiate() as RigidBody2D
	root.add_child(ball)
	await process_frame
	if bool(ball.call("apply_trait", "rainbow")):
		ball.queue_free()
		BallTraits.load_from()
		return _fail("case 4: apply_trait should fail with empty catalog")
	ball.queue_free()
	BallTraits.load_from()
	if BallTraits.trait_ids().is_empty():
		return _fail("case 4: restore did not reload the real catalog")
	_cases_passed += 1
	print("SUPERCHARGE case 4 pass warnings=%d" % (BallTraits.warning_count - warnings_before))
	return true


func _case_5_emits_once() -> bool:
	print("SUPERCHARGE case 5 emits once")
	_game.restart()
	await process_frame
	await physics_frame
	var emits: Array[int] = []
	var on_super := func() -> void:
		emits.append(int(_game.streak))
	_game.supercharged.connect(on_super)
	for _i in 5:
		_game.register_bumper_hit()
	await process_frame
	_game.supercharged.disconnect(on_super)
	if emits != [3]:
		return _fail("case 5: expected one emit at streak 3, got %s" % [emits])
	if int(_game.streak) != 5:
		return _fail("case 5: streak %d expected 5" % _game.streak)
	_cases_passed += 1
	print("SUPERCHARGE case 5 pass emits=1")
	return true


func _case_6_split_traits() -> bool:
	print("SUPERCHARGE case 6 split traits")
	await _reset_and_place(Vector2(360, 520), Vector2(180, -80))
	var grant := BallTraits.grants("supercharge")
	var all_ids: Array = grant.get("all", [])
	var one_ids: Array = grant.get("one", [])
	if all_ids.is_empty() and one_ids.is_empty():
		return _fail("case 6: grants.supercharge is empty")
	await _trigger_split()
	var balls := _live_balls()
	if balls.size() != 3:
		return _fail("case 6: expected 3 balls, got %d" % balls.size())
	var bounds := VIEWPORT.grow(-MARGIN)
	for i in balls.size():
		var ball := balls[i] as Node2D
		if not bounds.has_point(ball.global_position):
			return _fail("case 6: ball %d outside playfield at %s" % [i, ball.global_position])
		for j in range(i + 1, balls.size()):
			var other := balls[j] as Node2D
			var gap := ball.global_position.distance_to(other.global_position)
			if gap < BALL_DIAMETER:
				return _fail("case 6: balls overlapping at spawn gap=%s" % gap)
	for ball in balls:
		for id_var in all_ids:
			if not bool(ball.call("has_trait", String(id_var))):
				return _fail("case 6: ball missing all-trait %s" % id_var)
	for id_var in one_ids:
		var holders := 0
		for ball in balls:
			if bool(ball.call("has_trait", String(id_var))):
				holders += 1
		if holders != 1:
			return _fail("case 6: trait %s holders=%d expected 1" % [id_var, holders])
	_cases_passed += 1
	print("SUPERCHARGE case 6 pass balls=3")
	return true


func _case_7_last_ball_life() -> bool:
	print("SUPERCHARGE case 7 last-ball life")
	await _reset_and_place(Vector2(360, 520), Vector2(120, -40))
	await _trigger_split()
	var balls := _live_balls()
	if balls.size() != 3:
		return _fail("case 7: expected 3 balls, got %d" % balls.size())
	var lives := int(_game.balls_left)
	var counts: Array[int] = []
	var on_count := func(n: int) -> void:
		counts.append(n)
	_game.ball_count_changed.connect(on_count)
	_table.call("_on_drain_body_entered", balls[0])
	await process_frame
	if int(_game.balls_left) != lives or not counts.is_empty():
		_game.ball_count_changed.disconnect(on_count)
		return _fail("case 7: first drain cost a life counts=%s balls=%s" % [counts, _game.balls_left])
	_table.call("_on_drain_body_entered", balls[1])
	await process_frame
	if int(_game.balls_left) != lives or not counts.is_empty():
		_game.ball_count_changed.disconnect(on_count)
		return _fail("case 7: second drain cost a life counts=%s balls=%s" % [counts, _game.balls_left])
	_table.call("_on_drain_body_entered", balls[2])
	await physics_frame
	await process_frame
	_game.ball_count_changed.disconnect(on_count)
	if int(_game.balls_left) != lives - 1:
		return _fail("case 7: third drain balls_left=%s expected %s" % [_game.balls_left, lives - 1])
	if counts != [lives - 1]:
		return _fail("case 7: third drain counts=%s expected [%s]" % [counts, lives - 1])
	_cases_passed += 1
	print("SUPERCHARGE case 7 pass last_ball_life=1")
	return true


func _case_8_same_frame_drain() -> bool:
	print("SUPERCHARGE case 8 same-frame drain")
	_game.restart()
	await process_frame
	await physics_frame
	await _free_balls()
	var a := await _place_ball(Vector2(300, 500), Vector2.ZERO)
	var b := await _place_ball(Vector2(420, 500), Vector2.ZERO)
	if a == null or b == null:
		return _fail("case 8: could not place two balls")
	var lives := int(_game.balls_left)
	var counts: Array[int] = []
	var on_count := func(n: int) -> void:
		counts.append(n)
	_game.ball_count_changed.connect(on_count)
	_table.call("_on_drain_body_entered", a)
	_table.call("_on_drain_body_entered", b)
	await physics_frame
	await process_frame
	_game.ball_count_changed.disconnect(on_count)
	if counts.size() > 1:
		return _fail("case 8: same-frame drains emitted %s" % [counts])
	if lives - int(_game.balls_left) > 1:
		return _fail("case 8: same-frame drains cost %s lives" % (lives - int(_game.balls_left)))
	if int(_game.balls_left) != lives - 1 or counts != [lives - 1]:
		return _fail("case 8: expected exactly one life, balls=%s counts=%s" % [_game.balls_left, counts])
	_cases_passed += 1
	print("SUPERCHARGE case 8 pass same_frame_lives=1")
	return true


func _case_9_once_per_game() -> bool:
	print("SUPERCHARGE case 9 once per game")
	await _reset_and_place(Vector2(360, 520), Vector2(80, -20))
	await _trigger_split()
	if _live_balls().size() != 3:
		return _fail("case 9: first split did not make 3 balls")
	var extras := _live_balls()
	_table.call("_on_drain_body_entered", extras[1])
	_table.call("_on_drain_body_entered", extras[2])
	await process_frame
	_game._clear_streak()
	await process_frame
	await _trigger_split()
	if _live_balls().size() != 1:
		return _fail("case 9: second streak-3 split again, balls=%d" % _live_balls().size())
	_game.restart()
	await process_frame
	await physics_frame
	await _reset_and_place(Vector2(360, 520), Vector2(80, -20))
	await _trigger_split()
	if _live_balls().size() != 3:
		return _fail("case 9: restart did not allow a new split, balls=%d" % _live_balls().size())
	_cases_passed += 1
	print("SUPERCHARGE case 9 pass once_per_game")
	return true


func _case_10_no_ball_keeps_flag() -> bool:
	print("SUPERCHARGE case 10 no-ball flag")
	_game.restart()
	await process_frame
	await physics_frame
	await _free_balls()
	await _trigger_split()
	if not _live_balls().is_empty():
		return _fail("case 10: no-ball trigger spawned %d balls" % _live_balls().size())
	await _wait_sec(2.1)
	if int(_game.streak) != 0:
		_game._clear_streak()
	await _place_ball(Vector2(360, 520), Vector2(90, -30))
	await _trigger_split()
	if _live_balls().size() != 3:
		return _fail("case 10: later streak-3 did not split, balls=%d" % _live_balls().size())
	_cases_passed += 1
	print("SUPERCHARGE case 10 pass flag_unused")
	return true


func _case_11_three_lives() -> bool:
	print("SUPERCHARGE case 11 three lives")
	await _reset_and_place(Vector2(360, 520), Vector2(100, -40))
	await _trigger_split()
	var balls := _live_balls()
	if balls.size() != 3:
		return _fail("case 11: expected 3 balls, got %d" % balls.size())
	_table.call("_on_drain_body_entered", balls[0])
	_table.call("_on_drain_body_entered", balls[1])
	await process_frame
	if int(_game.balls_left) != 3:
		return _fail("case 11: extras cost a life, balls_left=%s" % _game.balls_left)
	_table.call("_on_drain_body_entered", balls[2])
	await physics_frame
	if int(_game.balls_left) != 2:
		return _fail("case 11: first life left balls_left=%s" % _game.balls_left)
	if not await _wait_for_ball_count(1, 200):
		return _fail("case 11: no respawn after first life")
	var second := _live_balls()
	if second.is_empty():
		return _fail("case 11: missing second-life ball")
	_table.call("_on_drain_body_entered", second[0])
	await physics_frame
	if int(_game.balls_left) != 1:
		return _fail("case 11: second life left balls_left=%s" % _game.balls_left)
	if not await _wait_for_ball_count(1, 200):
		return _fail("case 11: no respawn after second life")
	var third := _live_balls()
	if third.is_empty():
		return _fail("case 11: missing third-life ball")
	_table.call("_on_drain_body_entered", third[0])
	await physics_frame
	await process_frame
	if int(_game.balls_left) != 0 or int(_game.state) != _game.GAME_OVER:
		return _fail(
			"case 11: expected GAME_OVER after 3 lives, balls_left=%s state=%s"
			% [_game.balls_left, _game.state]
		)
	_cases_passed += 1
	print("SUPERCHARGE case 11 pass lives=3")
	return true


func _case_12_supercharged_soak() -> bool:
	print("SUPERCHARGE case 12 soak")
	await _reset_and_place(Vector2(360, 480), Vector2(220, -160))
	await _trigger_split()
	var balls := _live_balls()
	if balls.size() != 3:
		return _fail("case 12: expected 3 balls, got %d" % balls.size())
	var turbo_live := false
	for ball in balls:
		if bool(ball.call("has_trait", "turbo")):
			turbo_live = true
			break
	if not turbo_live:
		return _fail("case 12: turbo ball not live at soak start")
	var oob := 0
	for _f in SOAK_FRAMES:
		await physics_frame
		for node in _live_balls():
			if not SOAK_BOUNDS.has_point((node as Node2D).global_position):
				oob += 1
				return _fail("case 12: out of bounds at %s" % (node as Node2D).global_position)
	if oob != 0:
		return _fail("case 12: out_of_bounds=%d" % oob)
	for _life in 6:
		var remaining := _live_balls()
		if remaining.is_empty() and int(_game.state) == _game.GAME_OVER:
			break
		if remaining.is_empty():
			if not await _wait_for_ball_count(1, 200):
				break
			remaining = _live_balls()
		if remaining.size() > 1:
			for i in range(0, remaining.size() - 1):
				_table.call("_on_drain_body_entered", remaining[i])
			await process_frame
			remaining = _live_balls()
		if not remaining.is_empty():
			_table.call("_on_drain_body_entered", remaining[0])
			await physics_frame
			await process_frame
	if int(_game.state) != _game.GAME_OVER:
		return _fail("case 12: game did not end after supercharged soak")
	_cases_passed += 1
	print("SUPERCHARGE case 12 pass soak_frames=%d oob=0 ended=1" % SOAK_FRAMES)
	return true


func _standalone_ball(pos: Vector2) -> RigidBody2D:
	var packed: PackedScene = load(BALL_PATH)
	if packed == null:
		return null
	var ball := packed.instantiate() as RigidBody2D
	ball.position = pos
	root.add_child(ball)
	await process_frame
	await physics_frame
	return ball if is_instance_valid(ball) else null


func _reset_and_place(pos: Vector2, vel: Vector2) -> void:
	_game.restart()
	await process_frame
	await physics_frame
	await _free_balls()
	await _place_ball(pos, vel)


func _place_ball(pos: Vector2, vel: Vector2) -> RigidBody2D:
	var packed: PackedScene = load(BALL_PATH)
	var ball := packed.instantiate() as RigidBody2D
	ball.position = pos
	_table.add_child(ball)
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, pos)
	)
	await physics_frame
	if not is_instance_valid(ball):
		return null
	ball.sleeping = false
	ball.linear_velocity = vel
	return ball


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	await physics_frame


func _live_balls() -> Array[Node]:
	var out: Array[Node] = []
	for node in get_nodes_in_group("ball"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		out.append(node)
	return out


func _hit_streak(n: int) -> void:
	for _i in n:
		_game.register_bumper_hit()


func _trigger_split() -> void:
	_hit_streak(3)
	await process_frame


func _wait_for_ball_count(count: int, frames: int) -> bool:
	for _i in frames:
		if _live_balls().size() == count:
			return true
		await physics_frame
	return _live_balls().size() == count


func _drain_all_but_force_end() -> void:
	var balls := _live_balls()
	if balls.is_empty():
		return
	if balls.size() == 1:
		_table.call("_on_drain_body_entered", balls[0])
		return
	for i in range(0, balls.size() - 1):
		_table.call("_on_drain_body_entered", balls[i])


func _first_visual_trait_id() -> String:
	for id in BallTraits.trait_ids():
		var spec := BallTraits.entry(id)
		if typeof(spec.get("visual", null)) == TYPE_DICTIONARY:
			return id
	return ""


func _collider_radius(ball: RigidBody2D) -> float:
	var node := ball.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if node == null or not (node.shape is CircleShape2D):
		return -1.0
	return (node.shape as CircleShape2D).radius


func _wait_sec(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		var node := current_scene
		var delta := 1.0 / 120.0
		if node != null:
			delta = maxf(node.get_process_delta_time(), 1.0 / 120.0)
		elapsed += delta


func _fail(message: String) -> bool:
	push_error("SUPERCHARGE FAIL %s" % message)
	print("SUPERCHARGE FAIL %s" % message)
	quit(1)
	return false
