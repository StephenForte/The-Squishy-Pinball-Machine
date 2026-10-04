extends Node2D

signal ball_drained

const BALL_SCENE := preload("res://scenes/ball.tscn")
const BONUS_SCRIPT := preload("res://scripts/bonus_orb.gd")
const BALL_SPAWN := Vector2(666, 1219)
const GRANT_EVENT := "supercharge"
const BALL_SEP := 28.0
const FAN_RAD := deg_to_rad(22.0)
const PLAY_MIN := Vector2(40, 40)
const PLAY_MAX := Vector2(680, 1220)
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
## Open pockets between the home slots. Kept clear of walls, the lane, and the guides.
const BONUS_SLOTS: Array[Vector2] = [
	Vector2(360, 280),
	Vector2(190, 470),
	Vector2(470, 600),
	Vector2(330, 860),
]
const SHOVE_RADIUS := 64.0

var _supercharge_generation: int = 0
var _layout_token: int = 0
var _hosts: Array[Node2D] = []
var _homes: Array[Vector2] = []
var _orbs: Array = []


func _ready() -> void:
	$Drain.body_entered.connect(_on_drain_body_entered)
	_capture_homes()
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_signal("supercharged"):
		game.supercharged.connect(_on_supercharged)
	if game != null and game.has_signal("game_restarted"):
		game.game_restarted.connect(_on_game_restarted)
	if game != null and game.has_signal("board_shifted"):
		game.board_shifted.connect(_on_board_shifted)
	spawn_ball()


func spawn_ball() -> void:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.freeze = false
	ball.position = BALL_SPAWN
	add_child(ball)
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, BALL_SPAWN)
	)


func _on_drain_body_entered(body: Node2D) -> void:
	if not body.is_in_group("ball"):
		return
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	var others := _live_balls(body)
	body.queue_free()
	if others.is_empty():
		ball_drained.emit()


func _on_game_restarted() -> void:
	_supercharge_generation += 1
	_layout_token += 1
	_present_board(0, 0, 0)


func _on_board_shifted(wave: int, bonus_count: int, bonus_points: int) -> void:
	if Engine.is_in_physics_frame():
		_layout_token += 1
		_present_board_token.call_deferred(wave, bonus_count, bonus_points, _layout_token)
		return
	_layout_token += 1
	_present_board(wave, bonus_count, bonus_points)


func _present_board_token(wave: int, bonus_count: int, bonus_points: int, token: int) -> void:
	if token != _layout_token:
		return
	_present_board(wave, bonus_count, bonus_points)


func _capture_homes() -> void:
	_hosts.clear()
	_homes.clear()
	for path in HOST_PATHS:
		var host := get_node_or_null(path) as Node2D
		if host == null:
			push_warning("Table: missing board host %s" % path)
			continue
		_hosts.append(host)
		_homes.append(host.position)


func _present_board(wave: int, bonus_count: int, bonus_points: int) -> void:
	_apply_layout(wave)
	_sync_bonuses(bonus_count, bonus_points)
	if wave > 0:
		var effects := get_node_or_null("Effects")
		if effects != null and effects.has_method("shake"):
			effects.shake()
	print("Table board wave=%d bonuses=%d points=%d" % [wave, bonus_count, bonus_points])


func _apply_layout(wave: int) -> void:
	var count := _homes.size()
	if count == 0:
		return
	var shift := posmod(wave, count)
	for i in count:
		var dest: Vector2 = _homes[(i + shift) % count]
		var host := _hosts[i]
		_shove_balls(_global_for(host, dest))
		host.position = dest
		if host is CollisionObject2D:
			PhysicsServer2D.body_set_state(
				(host as CollisionObject2D).get_rid(),
				PhysicsServer2D.BODY_STATE_TRANSFORM,
				Transform2D(host.global_rotation, host.global_position)
			)


func _global_for(host: Node2D, local_pos: Vector2) -> Vector2:
	return host.global_position - host.position + local_pos


func _shove_balls(dest_global: Vector2) -> void:
	for node in _live_balls():
		if not (node is RigidBody2D):
			continue
		var ball := node as RigidBody2D
		var delta := ball.global_position - dest_global
		if delta.length() >= SHOVE_RADIUS:
			continue
		if delta.length_squared() < 1.0:
			delta = Vector2.UP
		var next := dest_global + delta.normalized() * SHOVE_RADIUS
		next.x = clampf(next.x, 48.0, 590.0)
		next.y = clampf(next.y, 48.0, 960.0)
		ball.sleeping = false
		ball.global_position = next
		PhysicsServer2D.body_set_state(
			ball.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(ball.global_rotation, next)
		)


func _sync_bonuses(count: int, points: int) -> void:
	var capped := mini(maxi(count, 0), BONUS_SLOTS.size())
	while _orbs.size() > capped:
		var extra: Node = _orbs.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	for i in capped:
		var slot: Vector2 = BONUS_SLOTS[i]
		var orb: Area2D = null
		if i < _orbs.size() and is_instance_valid(_orbs[i]):
			orb = _orbs[i] as Area2D
		if orb == null:
			orb = BONUS_SCRIPT.new() as Area2D
			orb.name = "BonusOrb%d" % (i + 1)
			orb.position = slot
			add_child(orb)
			if i < _orbs.size():
				_orbs[i] = orb
			else:
				_orbs.append(orb)
		orb.set("points", points)
		_shove_balls(to_global(slot))
		orb.position = slot


func _on_supercharged() -> void:
	_split_supercharge_deferred.call_deferred(_supercharge_generation)


func _split_supercharge_deferred(generation: int) -> void:
	if generation != _supercharge_generation:
		return
	if not _split_supercharge():
		return
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_method("note_supercharge_applied"):
		game.note_supercharge_applied()


func _split_supercharge() -> bool:
	var live := _pick_live_ball()
	if live == null:
		return false
	var origin := live.global_position
	var velocity := live.linear_velocity
	var extras := _nudge_positions(origin)
	var headings := _fanned_velocities(velocity)
	var extra_balls: Array[RigidBody2D] = []
	for i in extras.size():
		extra_balls.append(_spawn_split_ball(extras[i], headings[i]))
	var trio: Array[RigidBody2D] = [live]
	trio.append_array(extra_balls)
	_apply_grant(GRANT_EVENT, trio, live)
	print("Table supercharge split balls=%d" % trio.size())
	return true


func _spawn_split_ball(pos: Vector2, vel: Vector2) -> RigidBody2D:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.freeze = false
	ball.position = pos
	add_child(ball)
	if "launched" in ball:
		ball.set("launched", true)
	ball.linear_velocity = vel
	ball.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, pos)
	)
	return ball


func _apply_grant(event: String, all_balls: Array[RigidBody2D], one_ball: RigidBody2D) -> void:
	var grant := BallTraits.grants(event)
	for id_var in grant.get("all", []):
		var id := String(id_var)
		for ball in all_balls:
			if ball.has_method("apply_trait"):
				ball.apply_trait(id)
	if one_ball != null:
		for id_var in grant.get("one", []):
			if one_ball.has_method("apply_trait"):
				one_ball.apply_trait(String(id_var))


func _pick_live_ball() -> RigidBody2D:
	var best: RigidBody2D = null
	for node in _live_balls():
		if not (node is RigidBody2D):
			continue
		var ball := node as RigidBody2D
		if best == null or ball.get_instance_id() < best.get_instance_id():
			best = ball
	return best


func _live_balls(excluding: Node = null) -> Array[Node]:
	var out: Array[Node] = []
	for node in get_tree().get_nodes_in_group("ball"):
		if node == excluding:
			continue
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		out.append(node)
	return out


func _nudge_positions(origin: Vector2) -> Array[Vector2]:
	var chosen: Array[Vector2] = [origin]
	var offsets: Array[Vector2] = [
		Vector2(0, -BALL_SEP),
		Vector2(0, -BALL_SEP * 2.0),
		Vector2(BALL_SEP, 0),
		Vector2(-BALL_SEP, 0),
		Vector2(BALL_SEP, -BALL_SEP),
		Vector2(-BALL_SEP, -BALL_SEP),
		Vector2(0, BALL_SEP),
		Vector2(BALL_SEP * 2.0, 0),
	]
	for offset in offsets:
		if chosen.size() >= 3:
			break
		var pos := _clamp_play(origin + offset)
		var ok := true
		for existing in chosen:
			if pos.distance_to(existing) < BALL_SEP - 1.0:
				ok = false
				break
		if ok:
			chosen.append(pos)
	var extras: Array[Vector2] = []
	for i in range(1, chosen.size()):
		extras.append(chosen[i])
	while extras.size() < 2:
		var fallback := _clamp_play(origin + Vector2(0, -BALL_SEP * float(extras.size() + 1)))
		extras.append(fallback)
	return extras


func _clamp_play(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, PLAY_MIN.x, PLAY_MAX.x),
		clampf(pos.y, PLAY_MIN.y, PLAY_MAX.y)
	)


func _fanned_velocities(velocity: Vector2) -> Array[Vector2]:
	var speed := velocity.length()
	var heading := velocity.normalized() if speed > 1.0 else Vector2.UP
	return [
		heading.rotated(-FAN_RAD) * speed,
		heading.rotated(FAN_RAD) * speed,
	]
