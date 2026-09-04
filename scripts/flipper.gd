extends AnimatableBody2D

## Left flipper (facing = 1) points +X; right flipper (facing = -1) points -X.
## Rest is REST_DEG below horizontal, inward. Hold raises by SWING_DEG.
@export var action_name: StringName = &"flipper_left"
@export var facing: int = 1

const REST_DEG := 22.0
const SWING_DEG := 65.0
const LENGTH := 90.0
const HALF_WIDTH := 8.0
const BALL_RADIUS := 12.0
const UP_SPEED_DEG := 830.0
const DOWN_SPEED_DEG := 560.0
const PIVOT_TRAP_RADIUS := 30.0
const PIVOT_TRAP_SPEED := 5.0
const PIVOT_NUDGE := 140.0

var rest_rad: float
var up_rad: float
var angle: float


func _ready() -> void:
	sync_to_physics = true
	rest_rad = deg_to_rad(REST_DEG if facing > 0 else 180.0 - REST_DEG)
	up_rad = rest_rad + float(facing) * deg_to_rad(-SWING_DEG)
	angle = rest_rad
	rotation = angle
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme(String(theme_node.get("palette_id")))


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	var visual := get_node_or_null("Visual") as Polygon2D
	var hub := get_node_or_null("Hub") as Polygon2D
	if visual != null:
		visual.color = theme_node.color("object_orange")
	if hub != null:
		hub.color = theme_node.color("object_yellow")


func _physics_process(delta: float) -> void:
	var pressed := Input.is_action_pressed(action_name)
	var target := up_rad if pressed else rest_rad
	var speed_deg := UP_SPEED_DEG if pressed else DOWN_SPEED_DEG
	angle = move_toward(angle, target, deg_to_rad(speed_deg) * delta)
	rotation = angle
	_nudge_pivot_trap()


func _nudge_pivot_trap() -> void:
	for body in get_tree().get_nodes_in_group("ball"):
		if not (body is RigidBody2D) or not is_instance_valid(body):
			continue
		var to_ball: Vector2 = body.global_position - global_position
		if to_ball.length() >= PIVOT_TRAP_RADIUS:
			continue
		if body.linear_velocity.length() >= PIVOT_TRAP_SPEED:
			continue
		var nudge := rest_direction() + playfield_normal_at_rest()
		if nudge.length_squared() < 0.001:
			continue
		body.apply_central_impulse(nudge.normalized() * PIVOT_NUDGE)


func rest_direction() -> Vector2:
	return Vector2.from_angle(rest_rad)


func playfield_normal_at_rest() -> Vector2:
	var dir := rest_direction()
	return Vector2(float(facing) * dir.y, -float(facing) * dir.x)


func rest_line_point(along: float) -> Vector2:
	return global_position + rest_direction() * (LENGTH * along)


func ball_rest_spot(along: float = 0.82) -> Vector2:
	return rest_line_point(along) + playfield_normal_at_rest() * (HALF_WIDTH + BALL_RADIUS + 1.0)


func is_below_rest_line(point: Vector2) -> bool:
	var dir := rest_direction()
	var to_point := point - global_position
	var cross := dir.x * to_point.y - dir.y * to_point.x
	return float(facing) * cross > 0.0
