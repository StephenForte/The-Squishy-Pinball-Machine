extends Node2D

## Catalog-driven sprite. Collision stays on the parent bumper/target (D-015).

@export var catalog_id: String = ""

const FIT_BUMPER := 64.0
const FIT_TARGET := 56.0
const FIT_DECOR := 50.0
const SQUASH := Vector2(1.22, 0.72)
const DANCE_SEC := 2.0

var _rest_scale := Vector2.ONE
var _dancing := false
var _dance_gen: int = 0
var _hit_tween: Tween
var _dance_tween: Tween

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("squishies")
	if not catalog_id.is_empty():
		setup(catalog_id)
	var parent := get_parent()
	if parent != null and parent.has_signal("hit"):
		parent.hit.connect(play_hit)


func _process(_delta: float) -> void:
	global_rotation = 0.0
	_place_art()
	_apply_lit()


func setup(id: String) -> void:
	catalog_id = id
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		return
	var path := SquishyCatalog.sprite_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_sprite.texture = load(path)
	_sprite.centered = true
	_apply_fit()


func play_hit() -> void:
	if _sprite == null:
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_sprite.scale = _rest_scale * SQUASH
	_hit_tween = create_tween()
	_hit_tween.tween_property(_sprite, "scale", _rest_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_dance(duration: float = DANCE_SEC) -> void:
	if _sprite == null:
		return
	_halt_dance_motion()
	_dancing = true
	_dance_gen += 1
	var gen := _dance_gen
	_dance_tween = create_tween()
	_dance_tween.set_loops()
	_dance_tween.tween_property(_sprite, "rotation_degrees", 14.0, 0.10)
	_dance_tween.tween_property(_sprite, "scale", _rest_scale * Vector2(1.08, 0.90), 0.10)
	_dance_tween.tween_property(_sprite, "rotation_degrees", -14.0, 0.10)
	_dance_tween.tween_property(_sprite, "scale", _rest_scale, 0.10)
	get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if gen == _dance_gen:
				stop_dance(),
		CONNECT_ONE_SHOT
	)


func is_dancing() -> bool:
	return _dancing


func stop_dance() -> void:
	_dance_gen += 1
	_halt_dance_motion()
	_dancing = false


func _halt_dance_motion() -> void:
	if _dance_tween != null and _dance_tween.is_valid():
		_dance_tween.kill()
	if _sprite != null:
		_sprite.rotation_degrees = 0.0
		_sprite.scale = _rest_scale


func _apply_fit() -> void:
	var tex := _sprite.texture
	if tex == null:
		return
	var longest := maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		return
	var fit := FIT_DECOR
	var parent := get_parent()
	if parent != null and parent.is_in_group("bumpers"):
		fit = FIT_BUMPER
	elif parent != null and parent.is_in_group("targets"):
		fit = FIT_TARGET
	var s := fit / longest
	_rest_scale = Vector2(s, s)
	_sprite.scale = _rest_scale


func _place_art() -> void:
	var parent := get_parent()
	if parent == null or not parent.is_in_group("targets"):
		return
	var center := Vector2(360, 640)
	var inward: Vector2 = center - parent.global_position
	if inward.length_squared() < 0.001:
		inward = Vector2.DOWN
	var dist := 36.0
	if absf(parent.rotation) < 0.2:
		dist = 72.0
	global_position = parent.global_position + inward.normalized() * dist


func _apply_lit() -> void:
	if _sprite == null:
		return
	var parent := get_parent()
	if parent == null or not parent.is_in_group("targets"):
		return
	if bool(parent.get("lit")):
		_sprite.modulate = Color(1, 1, 1, 1)
	else:
		_sprite.modulate = Color(0.62, 0.62, 0.72, 1)
