extends RigidBody2D

var launched := false
var _ccd_ready := false


func _ready() -> void:
	continuous_cd = CCD_MODE_DISABLED
	for _i in 4:
		await get_tree().physics_frame
	continuous_cd = CCD_MODE_CAST_SHAPE
	_ccd_ready = true


func launch(impulse: float) -> void:
	if launched or not _ccd_ready:
		return
	launched = true
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	apply_central_impulse(Vector2(0.0, -impulse))
