extends Node2D

## Game-over celebration (D-033). Display-only CPUParticles2D; never touches Table.
## Tiers: none (score ≤ 1000), confetti (> 1000), fireworks (> 5000 / PB / board #1).

const CONFETTI_MIN := 1000
const FIREWORKS_MIN := 5000
const BOARD_TOP_RANK := 1

const TIER_NONE := "none"
const TIER_CONFETTI := "confetti"
const TIER_FIREWORKS := "fireworks"

const _FW_BURST_COUNT := 4
const _FW_SPACING_SEC := 0.75
const _FW_POINTS: Array[Vector2] = [
	Vector2(180, 140),
	Vector2(540, 100),
	Vector2(360, 200),
	Vector2(250, 80),
	Vector2(470, 170),
]

var tier: String = TIER_NONE

@onready var _confetti: CPUParticles2D = $Confetti
@onready var _fireworks: CPUParticles2D = $Fireworks

var _fw_bursts_left: int = 0
var _fw_elapsed: float = 0.0
var _fw_next_at: float = 0.0
var _fw_point_i: int = 0


func _ready() -> void:
	z_index = 0
	_lift_sibling_text()
	_confetti.emitting = false
	_fireworks.emitting = false
	_fireworks.local_coords = false
	_confetti.texture = _rect_texture(8, 3)
	_fireworks.texture = _rect_texture(4, 4)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed") and not theme_node.palette_changed.is_connected(_apply_theme):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme(String(theme_node.get("palette_id")))


func _lift_sibling_text() -> void:
	# Stay above Shade (same z, later in tree) but below labels/buttons so FINAL/HIGH/rank stay readable.
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == self:
			continue
		if child is Label or child is Button:
			(child as CanvasItem).z_index = maxi((child as CanvasItem).z_index, 1)


static func tier_for(final_score: int, is_high_score: bool, rank: int) -> String:
	if final_score <= CONFETTI_MIN:
		return TIER_NONE
	var board_top := rank == BOARD_TOP_RANK
	if final_score > FIREWORKS_MIN or is_high_score or board_top:
		return TIER_FIREWORKS
	return TIER_CONFETTI


func play(next_tier: String) -> void:
	if next_tier == TIER_NONE or next_tier.is_empty():
		stop()
		return
	if next_tier == TIER_FIREWORKS:
		_confetti.emitting = false
		tier = TIER_FIREWORKS
		_start_fireworks()
		return
	if next_tier == TIER_CONFETTI:
		_stop_fireworks()
		tier = TIER_CONFETTI
		_confetti.restart()
		return
	stop()


func stop() -> void:
	_stop_fireworks()
	if _confetti != null:
		_confetti.emitting = false
	tier = TIER_NONE


func _process(delta: float) -> void:
	if _fw_bursts_left <= 0:
		return
	_fw_elapsed += delta
	if _fw_elapsed + 0.0001 < _fw_next_at:
		return
	_fire_one_burst()
	_fw_bursts_left -= 1
	_fw_next_at += _FW_SPACING_SEC


func _start_fireworks() -> void:
	_fw_bursts_left = _FW_BURST_COUNT
	_fw_elapsed = 0.0
	_fw_next_at = 0.0
	_fw_point_i = 0
	_fire_one_burst()
	_fw_bursts_left -= 1
	_fw_next_at = _FW_SPACING_SEC


func _stop_fireworks() -> void:
	_fw_bursts_left = 0
	_fw_elapsed = 0.0
	_fw_next_at = 0.0
	if _fireworks != null:
		_fireworks.emitting = false


func _fire_one_burst() -> void:
	if _fireworks == null:
		return
	_fireworks.position = _FW_POINTS[_fw_point_i % _FW_POINTS.size()]
	_fw_point_i += 1
	_fireworks.restart()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	var pink: Color = theme_node.color("object_pink")
	var yellow: Color = theme_node.color("object_yellow")
	var cyan: Color = theme_node.color("object_cyan")
	var orange: Color = theme_node.color("object_orange")
	_confetti.color = pink
	var confetti_ramp := Gradient.new()
	confetti_ramp.colors = PackedColorArray([pink, yellow, cyan, orange])
	_confetti.color_ramp = confetti_ramp
	var gold: Color = theme_node.color("glow_gold")
	var magenta: Color = theme_node.color("glow_magenta")
	var blue: Color = theme_node.color("glow_blue")
	_fireworks.color = gold
	var fade := blue
	fade.a = 0.0
	var fw_ramp := Gradient.new()
	fw_ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	fw_ramp.colors = PackedColorArray([gold, magenta, blue, fade])
	_fireworks.color_ramp = fw_ramp


func _rect_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
