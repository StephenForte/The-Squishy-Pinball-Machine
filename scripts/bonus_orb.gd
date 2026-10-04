extends Area2D

## Pass-through bonus spot. One award per visit; the ball is not blocked.
## Not a bumper or a bank target, so the D-005 target set stays five.
##
## COOLDOWN_SEC spaces awards. A ball that arrives during that window is
## recorded immediately and paid when the timer ends, including a visit that
## has already left the star. The ball just paid is not queued again if it
## flickers out and back during the cooldown.

const RADIUS := 22.0
const COOLDOWN_SEC := 0.4

var points: int = 1000

var _cooling: bool = false
## Instance ids overlapping the star right now.
var _inside: Dictionary = {}
## Visits that have not been paid yet.
var _pending: Dictionary = {}
## Instance ids paid for an overlap that is still inside the debounce window.
var _awarded: Dictionary = {}


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
	var id := body.get_instance_id()
	if _inside.has(id):
		return
	_inside[id] = true
	# A re-entry of the ball we just paid is the same visit until it leaves
	# after the cooldown. Other balls are queued even while cooling.
	if _awarded.has(id):
		return
	_pending[id] = true
	_pay_next()


func _on_body_exited(body: Node2D) -> void:
	var id := body.get_instance_id()
	_inside.erase(id)
	if _cooling:
		return
	_pending.erase(id)
	_awarded.erase(id)


func _end_cooldown() -> void:
	if not is_inside_tree():
		return
	_cooling = false
	var finished: Array = []
	for id in _awarded.keys():
		if not _inside.has(id):
			finished.append(id)
	for id in finished:
		_awarded.erase(id)
	_pay_next()


func _pay_next() -> void:
	if _cooling:
		return
	for id in _pending.keys():
		if _awarded.has(id):
			_pending.erase(id)
			continue
		_pending.erase(id)
		if _inside.has(id):
			_awarded[id] = true
		_cooling = true
		var game := get_node_or_null("/root/Game")
		if game != null and game.has_method("add_score"):
			game.add_score(points)
		var tree := get_tree()
		if tree != null:
			tree.create_timer(COOLDOWN_SEC).timeout.connect(_end_cooldown, CONNECT_ONE_SHOT)
		else:
			_cooling = false
		return


func _star_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var radius := RADIUS if i % 2 == 0 else RADIUS * 0.45
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
