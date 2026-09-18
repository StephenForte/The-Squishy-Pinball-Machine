class_name Ball
extends RigidBody2D

var launched := false
var _ccd_ready := false
var _active: Dictionary = {}
var _rainbow_on := false
var _rainbow_cycle := 1.0
var _hue := 0.0
var _glow: Polygon2D
var _glow_alpha := 0.4
var _physics_trait_on := false
var _min_speed := 0.0
var _max_speed := 0.0
var _speed_scale := 1.0


func _ready() -> void:
	continuous_cd = CCD_MODE_DISABLED
	for _i in 4:
		await get_tree().physics_frame
	continuous_cd = CCD_MODE_CAST_SHAPE
	_ccd_ready = true


func launch(impulse: float) -> void:
	if not _ccd_ready:
		return
	launched = true
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	apply_central_impulse(Vector2(0.0, -impulse))


func apply_trait(id: String) -> bool:
	var spec := BallTraits.entry(id)
	if spec.is_empty():
		return false
	_apply_visual(spec)
	_apply_physics(spec)
	var duration := _duration_of(spec)
	_active[id] = duration if duration > 0.0 else -1.0
	return true


func has_trait(id: String) -> bool:
	return _active.has(id)


func active_trait_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in _active.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func _process(delta: float) -> void:
	if not _rainbow_on:
		return
	_hue = fmod(_hue + delta / _rainbow_cycle, 1.0)
	var body_color := Color.from_hsv(_hue, 0.85, 1.0)
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual != null:
		visual.color = body_color
	if _glow != null:
		_glow.color = Color.from_hsv(_hue, 0.7, 1.0, _glow_alpha)


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array[String] = []
	for key in _active.keys():
		var id := String(key)
		var remaining: float = float(_active[key])
		if remaining < 0.0:
			continue
		remaining -= delta
		if remaining <= 0.0:
			expired.append(id)
		else:
			_active[id] = remaining
	for id in expired:
		_clear_trait(id)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not _physics_trait_on:
		return
	var velocity := state.linear_velocity
	var speed := velocity.length()
	if _max_speed > 0.0 and speed > _max_speed:
		state.linear_velocity = velocity.normalized() * _max_speed
	elif speed < _min_speed:
		if speed > 1.0:
			state.linear_velocity = velocity.normalized() * _min_speed
		else:
			state.linear_velocity = Vector2(0.0, _min_speed)


func _apply_visual(spec: Dictionary) -> void:
	var visual_raw: Variant = spec.get("visual", {})
	if typeof(visual_raw) != TYPE_DICTIONARY or (visual_raw as Dictionary).is_empty():
		return
	var visual: Dictionary = visual_raw
	if String(visual.get("mode", "")) != "rainbow":
		return
	_rainbow_cycle = maxf(float(visual.get("cycle_sec", 1.0)), 0.05)
	_rainbow_on = true
	_hue = fmod(float(get_instance_id()) * 0.37, 1.0)
	_ensure_glow(visual)
	set_process(true)


func _apply_physics(spec: Dictionary) -> void:
	var physics_raw: Variant = spec.get("physics", {})
	if typeof(physics_raw) != TYPE_DICTIONARY or (physics_raw as Dictionary).is_empty():
		return
	var physics: Dictionary = physics_raw
	_speed_scale = float(physics.get("speed_scale", 1.0))
	_min_speed = float(physics.get("min_speed", 0.0))
	_max_speed = float(physics.get("max_speed", 0.0))
	_physics_trait_on = true
	var velocity := linear_velocity
	var speed := velocity.length()
	if _speed_scale != 1.0:
		if speed > 0.0:
			velocity *= _speed_scale
			speed = velocity.length()
		else:
			velocity = Vector2(0.0, _min_speed)
			speed = velocity.length()
	if _max_speed > 0.0 and speed > _max_speed:
		velocity = velocity.normalized() * _max_speed
	elif speed < _min_speed:
		if speed > 1.0:
			velocity = velocity.normalized() * _min_speed
		else:
			velocity = Vector2(0.0, _min_speed)
	linear_velocity = velocity
	sleeping = false


func _clear_trait(id: String) -> void:
	_active.erase(id)
	var spec := BallTraits.entry(id)
	if typeof(spec.get("physics", null)) == TYPE_DICTIONARY:
		_physics_trait_on = false
	if typeof(spec.get("visual", null)) == TYPE_DICTIONARY:
		_rainbow_on = false


func _duration_of(spec: Dictionary) -> float:
	if spec.has("duration_sec"):
		return float(spec["duration_sec"])
	var physics_raw: Variant = spec.get("physics", {})
	if typeof(physics_raw) == TYPE_DICTIONARY and (physics_raw as Dictionary).has("duration_sec"):
		return float((physics_raw as Dictionary)["duration_sec"])
	return 0.0


func _ensure_glow(visual: Dictionary) -> void:
	if _glow != null:
		return
	if not bool(visual.get("glow", false)):
		return
	var src := get_node_or_null("Visual") as Polygon2D
	if src == null:
		return
	_glow = Polygon2D.new()
	_glow.name = "TraitGlow"
	_glow.polygon = src.polygon
	var glow_scale := float(visual.get("glow_scale", 1.5))
	_glow.scale = Vector2(glow_scale, glow_scale)
	_glow.z_index = -1
	_glow_alpha = float(visual.get("glow_alpha", 0.4))
	_glow.color = Color(1, 1, 1, _glow_alpha)
	add_child(_glow)
