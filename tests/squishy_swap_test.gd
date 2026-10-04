extends SceneTree

## D-061 / T45. Each board presentation with wave > 0 gives every host a new
## catalog squishy. Wave 0 restores the scene ids. The draw is pinned with
## table.squishy_seed_override (T49). Production leaves that unset and draws
## a fresh seed on every wave 0; cases 4, 6, and 7 compare two restarts, which
## only match when the seed is pinned.

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
const FIT_BUMPER := 64.0
const FIT_TARGET := 56.0
const BODY_RADIUS := {"bumpers": 28.0, "targets": 30.0}
const SENSOR_RADIUS := {"bumpers": 32.0, "targets": 34.0}

var _game: Node
var _table: Node2D
var _theme: Node
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("SQUISHY_SWAP start")
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load scenes/main.tscn")
		return
	await process_frame
	await physics_frame
	_game = root.get_node_or_null("/root/Game")
	_theme = root.get_node_or_null("/root/Theme")
	_table = current_scene.get_node_or_null("Table") as Node2D
	if _game == null or _theme == null or _table == null:
		_fail("Game, Theme, or Table missing")
		return
	if not _game.has_signal("board_shifted") or not _theme.has_signal("palette_changed"):
		_fail("board_shifted or palette_changed missing")
		return
	var drain := _table.get_node_or_null("Drain") as Area2D
	if drain != null:
		drain.monitoring = false
	if _host_count() != HOST_PATHS.size():
		_fail("hosts=%d" % _host_count())
		return
	# Was the constant SQUISHY_SWAP_SEED inside table.gd. The pin lives here
	# now so a real run is not stuck on one sequence.
	_table.set("squishy_seed_override", 61061)

	if not await _case_1_first_rotation():
		return
	if not await _case_2_second_rotation():
		return
	if not await _case_3_restart():
		return
	if not await _case_4_one_swap_per_frame():
		return
	if not await _case_5_palette_keeps_ids():
		return
	if not await _case_6_seed_repeats():
		return
	if not await _case_7_jump_is_one_swap():
		return

	print("SQUISHY_SWAP PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_first_rotation() -> bool:
	print("SQUISHY_SWAP case 1 first rotation")
	if not await _restart():
		return false
	var radii := _radii()
	var avatar_before := _avatar_texture()
	var originals := _ids()
	if not _distinct(originals):
		return _fail("case 1: wave 0 ids not distinct %s" % originals)
	_game.add_score(5000)
	await _settle()
	if int(_game.board_wave) != 1:
		return _fail("case 1: wave=%s" % _game.board_wave)
	var swapped := _ids()
	if not _all_changed(originals, swapped):
		return _fail("case 1: ids did not all change %s -> %s" % [originals, swapped])
	if not _distinct(swapped):
		return _fail("case 1: duplicate ids %s" % swapped)
	if not _textures_loaded():
		return _fail("case 1: a texture is null")
	if not _fit_holds():
		return _fail("case 1: sprite fit or origin changed")
	if not _radii_match(radii):
		return _fail("case 1: hit radius changed")
	if _avatar_texture() != avatar_before:
		return _fail("case 1: title avatar texture changed")
	if int(_table.get("squishy_swap_count")) != 1:
		return _fail("case 1: swaps=%s" % _table.get("squishy_swap_count"))
	_cases_passed += 1
	print("SQUISHY_SWAP case 1 pass")
	return true


func _case_2_second_rotation() -> bool:
	print("SQUISHY_SWAP case 2 second rotation")
	if not await _restart():
		return false
	_game.add_score(5000)
	await _settle()
	var wave1 := _ids()
	_game.add_score(5000)
	await _settle()
	if int(_game.board_wave) != 2:
		return _fail("case 2: wave=%s" % _game.board_wave)
	var wave2 := _ids()
	if not _all_changed(wave1, wave2):
		return _fail("case 2: ids did not all change %s -> %s" % [wave1, wave2])
	if not _distinct(wave2):
		return _fail("case 2: duplicate ids %s" % wave2)
	if not _textures_loaded():
		return _fail("case 2: a texture is null")
	if int(_table.get("squishy_swap_count")) != 2:
		return _fail("case 2: swaps=%s" % _table.get("squishy_swap_count"))
	_cases_passed += 1
	print("SQUISHY_SWAP case 2 pass")
	return true


func _case_3_restart() -> bool:
	print("SQUISHY_SWAP case 3 restart restores scene ids")
	if not await _restart():
		return false
	var originals := _ids()
	_game.add_score(10000)
	await _settle()
	if _same(originals, _ids()):
		return _fail("case 3: rotation did not change ids")
	if not await _restart():
		return false
	var restored := _ids()
	if not _same(originals, restored):
		return _fail("case 3: restored %s want %s" % [restored, originals])
	if int(_game.board_wave) != 0 or int(_table.get("squishy_swap_count")) != 0:
		return _fail("case 3: wave=%s swaps=%s" % [_game.board_wave, _table.get("squishy_swap_count")])
	_cases_passed += 1
	print("SQUISHY_SWAP case 3 pass")
	return true


func _case_4_one_swap_per_frame() -> bool:
	print("SQUISHY_SWAP case 4 two shifts in one physics frame")
	if not await _restart():
		return false
	_game.add_score(5000)
	await _settle()
	var once := _ids()
	_game.add_score(5000)
	await _settle()
	var twice := _ids()
	if _same(once, twice):
		return _fail("case 4: two sequential swaps landed on the same ids")
	if not await _restart():
		return false
	var before := _ids()
	var armed := [true]
	var saw_physics := [false]
	var on_physics := func() -> void:
		if not armed[0] or not Engine.is_in_physics_frame():
			return
		armed[0] = false
		saw_physics[0] = true
		_game.add_score(5000)
		_game.add_score(5000)
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
	await _settle()
	if int(_game.board_wave) != 2:
		return _fail("case 4: wave=%s" % _game.board_wave)
	var got := _ids()
	if not _all_changed(before, got):
		return _fail("case 4: no swap landed %s" % got)
	if not _same(got, once):
		return _fail("case 4: got %s one-swap %s" % [got, once])
	if _same(got, twice):
		return _fail("case 4: two swaps landed")
	if int(_table.get("squishy_swap_count")) != 1:
		return _fail("case 4: swaps=%s" % _table.get("squishy_swap_count"))
	_cases_passed += 1
	print("SQUISHY_SWAP case 4 pass")
	return true


func _case_5_palette_keeps_ids() -> bool:
	print("SQUISHY_SWAP case 5 palette keeps swapped ids")
	if not await _restart():
		return false
	var originals := _ids()
	_game.add_score(5000)
	await _settle()
	var swapped := _ids()
	if not _all_changed(originals, swapped):
		return _fail("case 5: positive control, ids did not swap")
	var settings_existed := false
	var settings_text := ""
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("settings.save"):
		settings_existed = true
		settings_text = FileAccess.get_file_as_string("user://settings.save")
	var palette_before := String(_theme.get("palette_id"))
	_theme.palette_changed.emit(palette_before)
	await _settle()
	if not _same(swapped, _ids()):
		return _fail("case 5: signal changed ids %s -> %s" % [swapped, _ids()])
	var other := ""
	var palette_ids: PackedStringArray = _theme.palette_ids()
	for id in palette_ids:
		if id != palette_before:
			other = id
			break
	if other.is_empty():
		return _fail("case 5: no second palette")
	_theme.set_palette(other)
	await _settle()
	if not _same(swapped, _ids()):
		return _fail("case 5: set_palette changed ids %s -> %s" % [swapped, _ids()])
	if not _textures_loaded():
		return _fail("case 5: a texture is null after palette change")
	_theme.set_palette(palette_before)
	_restore_settings(settings_existed, settings_text)
	_cases_passed += 1
	print("SQUISHY_SWAP case 5 pass")
	return true


func _case_6_seed_repeats() -> bool:
	print("SQUISHY_SWAP case 6 pinned seed repeats")
	var first := await _ten_rotations()
	if first.is_empty():
		return false
	var second := await _ten_rotations()
	if second.is_empty():
		return false
	if first.size() != 10 or second.size() != 10:
		return _fail("case 6: lengths %d %d" % [first.size(), second.size()])
	for i in first.size():
		var a: Array = first[i]
		var b: Array = second[i]
		if not _same(a, b):
			return _fail("case 6: rotation %d %s vs %s" % [i + 1, a, b])
		if not _distinct(a):
			return _fail("case 6: rotation %d not distinct %s" % [i + 1, a])
	_cases_passed += 1
	print("SQUISHY_SWAP case 6 pass")
	return true


func _case_7_jump_is_one_swap() -> bool:
	print("SQUISHY_SWAP case 7 score jump is one swap")
	if not await _restart():
		return false
	_game.add_score(5000)
	await _settle()
	var once := _ids()
	if not await _restart():
		return false
	var before := _ids()
	_game.add_score(15000)
	await _settle()
	if int(_game.board_wave) != 3:
		return _fail("case 7: wave=%s" % _game.board_wave)
	var got := _ids()
	if not _all_changed(before, got):
		return _fail("case 7: jump did not change ids")
	if not _same(got, once):
		return _fail("case 7: jump %s one-swap %s" % [got, once])
	if not _distinct(got) or not _textures_loaded():
		return _fail("case 7: ids %s" % got)
	if int(_table.get("squishy_swap_count")) != 1:
		return _fail("case 7: swaps=%s" % _table.get("squishy_swap_count"))
	_cases_passed += 1
	print("SQUISHY_SWAP case 7 pass")
	return true


func _ten_rotations() -> Array:
	if not await _restart():
		return []
	var sequence: Array = []
	var previous := _ids()
	for step in 10:
		_game.add_score(5000)
		await _settle()
		var now := _ids()
		if int(_game.board_wave) != step + 1:
			_fail("case 6: wave=%s at step %d" % [_game.board_wave, step + 1])
			return []
		if not _all_changed(previous, now):
			_fail("case 6: step %d did not change every id" % (step + 1))
			return []
		sequence.append(now)
		previous = now
	if int(_table.get("squishy_swap_count")) != 10:
		_fail("case 6: swaps=%s" % _table.get("squishy_swap_count"))
		return []
	return sequence


func _restart() -> bool:
	_game.restart()
	await _settle()
	if int(_game.board_wave) != 0:
		_fail("restart left wave=%s" % _game.board_wave)
		return false
	return true


func _settle() -> void:
	for _i in 4:
		await process_frame


func _host_count() -> int:
	var n := 0
	for path in HOST_PATHS:
		if _table.get_node_or_null(path) != null:
			n += 1
	return n


func _ids() -> Array:
	var out: Array = []
	for path in HOST_PATHS:
		var squishy := _table.get_node(path).get_node_or_null("Squishy")
		if squishy == null:
			out.append("")
		else:
			out.append(String(squishy.get("catalog_id")))
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if String(a[i]) != String(b[i]):
			return false
	return true


func _all_changed(before: Array, after: Array) -> bool:
	if before.size() != after.size() or before.is_empty():
		return false
	for i in before.size():
		if String(before[i]).is_empty() or String(before[i]) == String(after[i]):
			return false
	return true


func _distinct(ids: Array) -> bool:
	var seen := {}
	for id in ids:
		var key := String(id)
		if key.is_empty() or seen.has(key):
			return false
		seen[key] = true
	return seen.size() == HOST_PATHS.size()


func _textures_loaded() -> bool:
	for path in HOST_PATHS:
		var sprite := _table.get_node(path).get_node_or_null("Squishy/Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			return false
	return true


func _fit_holds() -> bool:
	for path in HOST_PATHS:
		var host := _table.get_node(path) as Node2D
		var squishy := host.get_node_or_null("Squishy") as Node2D
		var sprite := host.get_node_or_null("Squishy/Sprite") as Sprite2D
		if squishy == null or sprite == null or sprite.texture == null:
			return false
		if squishy.position != Vector2.ZERO:
			return false
		var longest := maxf(sprite.texture.get_width(), sprite.texture.get_height())
		if longest <= 0.0:
			return false
		var fit := FIT_TARGET
		if host.is_in_group("bumpers"):
			fit = FIT_BUMPER
		var scale := fit / longest
		if not is_equal_approx(sprite.scale.x, scale) or not is_equal_approx(sprite.scale.y, scale):
			return false
	return true


func _radii() -> Dictionary:
	var out := {}
	for path in HOST_PATHS:
		var host := _table.get_node(path)
		out[path] = [_radius(host, "CollisionShape2D"), _radius(host, "Sensor/CollisionShape2D")]
	return out


func _radii_match(before: Dictionary) -> bool:
	for path in HOST_PATHS:
		var host := _table.get_node(path)
		var got: Array = [_radius(host, "CollisionShape2D"), _radius(host, "Sensor/CollisionShape2D")]
		var want: Array = before[path]
		if not is_equal_approx(float(got[0]), float(want[0])) or not is_equal_approx(float(got[1]), float(want[1])):
			return false
		var group := "targets"
		if host.is_in_group("bumpers"):
			group = "bumpers"
		if not is_equal_approx(float(got[0]), float(BODY_RADIUS[group])):
			return false
		if not is_equal_approx(float(got[1]), float(SENSOR_RADIUS[group])):
			return false
	return true


func _radius(host: Node, shape_path: String) -> float:
	var node := host.get_node_or_null(shape_path) as CollisionShape2D
	if node == null or not (node.shape is CircleShape2D):
		return -1.0
	return (node.shape as CircleShape2D).radius


func _avatar_texture() -> Texture2D:
	if current_scene == null:
		return null
	var view := current_scene.get_node_or_null("Title/AvatarView") as TextureRect
	if view == null:
		return null
	return view.texture


func _restore_settings(existed: bool, text: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if not existed:
		if dir.file_exists("settings.save"):
			dir.remove("settings.save")
		return
	var file := FileAccess.open("user://settings.save", FileAccess.WRITE)
	if file != null:
		file.store_string(text)


func _fail(message: String) -> bool:
	push_error("SQUISHY_SWAP FAIL %s" % message)
	print("SQUISHY_SWAP FAIL %s" % message)
	quit(1)
	return false
