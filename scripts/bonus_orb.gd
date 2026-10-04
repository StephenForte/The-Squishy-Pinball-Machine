extends Area2D

## Pass-through bonus spot. One award per visit; the ball is not blocked.
## Not a bumper or a bank target, so the D-005 target set stays five.

const RADIUS := 22.0
const COOLDOWN_SEC := 0.4

var points: int = 1000

var _cooling: bool = false
var _inside: Dictionary = {}


func _ready() -> void:
	add_to_group("bonuses")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	input_pickable = false
	z_index = 4
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var shape := CollisionShape2D.new()
	shape.shape = circle
	add_child(shape)

	var star := Polygon2D.new()
	star.color = Color(1.0, 0.82, 0.18, 0.95)
	star.polygon = _star_points()
	add_child(star)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("ball"):
		return
	if _cooling or _inside.has(body):
		return
	_inside[body] = true
	_cooling = true
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_method("add_score"):
		game.add_score(points)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(COOLDOWN_SEC).timeout.connect(_end_cooldown, CONNECT_ONE_SHOT)
	else:
		_cooling = false


func _on_body_exited(body: Node2D) -> void:
	_inside.erase(body)


func _end_cooldown() -> void:
	if not is_inside_tree():
		return
	_cooling = false


func _star_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var radius := RADIUS if i % 2 == 0 else RADIUS * 0.45
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
