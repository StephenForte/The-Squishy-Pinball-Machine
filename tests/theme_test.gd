extends SceneTree

const ART_DIR := "res://assets/design/squishes/art"
const BEAR_EYE_SAMPLES := [
	Vector2i(66, 124),
	Vector2i(62, 132),
	Vector2i(132, 129),
	Vector2i(140, 140),
]
const SLOT_EXPECT := {
	"Bumper1": "bear_bounce",
	"Bumper2": "puffo",
	"Bumper3": "dumpling_dottie",
	"TargetLeft": "frog_gus",
	"TargetRight": "cosmo",
	"TargetTop": "lion_rumpus",
	"TargetLeft2": "puppy_jax",
	"TargetRight2": "peanut_pip",
}
const ALIGN_TOL_PX := 1.0

var _cases_passed: int = 0
var _theme: Node
var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_delete_settings()
	_theme = root.get_node_or_null("Theme")
	_game = root.get_node_or_null("Game")
	if _theme == null or _game == null:
		_fail("Theme or Game autoload missing")
		return
	_theme._load_catalog()
	_theme._load_settings()

	if not await _case_1_sprites():
		return
	if not await _case_2_palettes():
		return

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load main.tscn")
		return
	await process_frame
	await process_frame
	await process_frame

	if not await _case_3_reapply():
		return
	if not await _case_4_persist():
		return
	if not await _case_5_slots():
		return
	if not await _case_6_squash():
		return
	if not await _case_7_dance():
		return
	if not await _case_8_alignment():
		return
	if not await _case_9_texture_retry():
		return

	print("THEME PASS cases=9")
	quit(0)


func _case_1_sprites() -> bool:
	var catalog: Dictionary = SquishyCatalog.data()
	var entries: Array = catalog.get("squishies", [])
	if entries.size() != 16:
		return _fail("case 1: expected 16 catalog entries, got %d" % entries.size())
	for entry_var in entries:
		var entry: Dictionary = entry_var
		var sid := String(entry.get("id", ""))
		var path := "res://assets/design/squishes/art/%s.png" % sid
		if not FileAccess.file_exists(path):
			return _fail("case 1: missing %s" % path)
		var tex := load(path) as Texture2D
		if tex == null:
			return _fail("case 1: load failed %s" % path)
		var img := tex.get_image()
		if img == null:
			return _fail("case 1: no image %s" % path)
		img.convert(Image.FORMAT_RGBA8)
		if img.get_format() != Image.FORMAT_RGBA8:
			return _fail("case 1: %s is not RGBA" % sid)
		var w := img.get_width()
		var h := img.get_height()
		var opaque := 0
		var total := w * h
		for y in h:
			for x in w:
				var a := img.get_pixel(x, y).a
				if a >= 0.5:
					opaque += 1
				if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
					if a > 0.02:
						return _fail("case 1: %s border pixel (%d,%d) a=%.3f" % [sid, x, y, a])
		if float(opaque) / float(total) < 0.25:
			return _fail("case 1: %s opaque=%.1f%%" % [sid, 100.0 * float(opaque) / float(total)])
	var bear_tex := load("res://assets/design/squishes/art/bear_bounce.png") as Texture2D
	var bear := bear_tex.get_image()
	bear.convert(Image.FORMAT_RGBA8)
	for sample in BEAR_EYE_SAMPLES:
		var p := bear.get_pixel(sample.x, sample.y)
		if p.a < 0.99:
			return _fail("case 1: bear eye %s a=%.3f" % [sample, p.a])
	_cases_passed += 1
	print("THEME case 1 pass")
	return true


func _case_2_palettes() -> bool:
	if _theme.palette_count() != 4:
		return _fail("case 2: palette count %d" % _theme.palette_count())
	if String(_theme.default_palette_id) != "neon_candy_baseline":
		return _fail("case 2: default %s" % _theme.default_palette_id)
	if String(_theme.palette_id) != "neon_candy_baseline":
		return _fail("case 2: current %s" % _theme.palette_id)
	_cases_passed += 1
	print("THEME case 2 pass")
	return true


func _case_3_reapply() -> bool:
	var main := current_scene
	if main == null:
		return _fail("case 3: no main")
	var heard := {"id": ""}
	_theme.palette_changed.connect(func(id: String) -> void: heard["id"] = id, CONNECT_ONE_SHOT)
	_theme.set_palette("aqua_pool")
	await process_frame
	if heard["id"] != "aqua_pool":
		return _fail("case 3: palette_changed id=%s" % heard["id"])
	var score := main.find_child("ScoreLabel", true, false) as Label
	if score == null:
		return _fail("case 3: missing ScoreLabel")
	var got: Color = score.get_theme_color("font_color")
	var want: Color = _theme.color("text_primary")
	if not _colors_close(got, want):
		return _fail("case 3: ScoreLabel %s != %s" % [got, want])
	var playfield := main.find_child("Background", true, false) as Polygon2D
	if playfield == null:
		return _fail("case 3: missing Background")
	if not _colors_close(playfield.color, _theme.color("playfield_base")):
		return _fail("case 3: playfield %s != %s" % [playfield.color, _theme.color("playfield_base")])
	_cases_passed += 1
	print("THEME case 3 pass")
	return true


func _case_4_persist() -> bool:
	_theme.set_palette("grape_jam")
	await process_frame
	var fresh: Node = load("res://autoload/theme.gd").new()
	root.add_child(fresh)
	await process_frame
	var got := String(fresh.get("palette_id"))
	if fresh.get_tree() != null and fresh.get_tree().node_added.is_connected(fresh._on_node_added):
		fresh.get_tree().node_added.disconnect(fresh._on_node_added)
	fresh.queue_free()
	await process_frame
	if got != "grape_jam":
		return _fail("case 4: reloaded %s" % got)
	_cases_passed += 1
	print("THEME case 4 pass")
	return true


func _case_5_slots() -> bool:
	var table := current_scene.get_node_or_null("Table")
	if table == null:
		return _fail("case 5: missing Table")
	for node_name in SLOT_EXPECT.keys():
		var host := table.find_child(node_name, true, false)
		if host == null:
			return _fail("case 5: missing %s" % node_name)
		var squishy := host.get_node_or_null("Squishy")
		if squishy == null:
			return _fail("case 5: %s has no Squishy" % node_name)
		var got := String(squishy.get("catalog_id"))
		if got != SLOT_EXPECT[node_name]:
			return _fail("case 5: %s id=%s want=%s" % [node_name, got, SLOT_EXPECT[node_name]])
	if SquishyCatalog.first_table_slots().has("decor"):
		return _fail("case 5: first_table_slots still has decor")
	if table.get_node_or_null("Decor0") != null or table.get_node_or_null("Decor1") != null:
		return _fail("case 5: Decor0/Decor1 still on table")
	_cases_passed += 1
	print("THEME case 5 pass")
	return true


func _case_6_squash() -> bool:
	var table := current_scene.get_node_or_null("Table")
	var bumper := table.get_node_or_null("Bumper1")
	if bumper == null:
		return _fail("case 6: missing Bumper1")
	var squishy := bumper.get_node_or_null("Squishy")
	var sprite := squishy.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return _fail("case 6: missing sprite")
	var rest: Vector2 = sprite.scale
	bumper.hit.emit()
	var departed := false
	for _i in 3:
		await process_frame
		if sprite.scale.distance_to(rest) > 0.02:
			departed = true
			break
	if not departed:
		return _fail("case 6: scale did not leave rest within 3 frames")
	var returned := false
	for _i in 30:
		await process_frame
		if sprite.scale.distance_to(rest) <= 0.03:
			returned = true
			break
	if not returned:
		return _fail("case 6: scale did not return within 30 frames (now %s)" % sprite.scale)
	_cases_passed += 1
	print("THEME case 6 pass")
	return true


func _case_7_dance() -> bool:
	_game.restart()
	await process_frame
	_game.add_score(10000)
	await process_frame
	await process_frame
	var squishies := get_nodes_in_group("squishies")
	if squishies.size() < 8:
		return _fail("case 7: squishies=%d" % squishies.size())
	var dancing := 0
	for node in squishies:
		if bool(node.call("is_dancing")):
			dancing += 1
	if dancing < 8:
		return _fail("case 7: dancing=%d" % dancing)
	_game.restart()
	await process_frame
	await process_frame
	for node in squishies:
		if is_instance_valid(node) and bool(node.call("is_dancing")):
			return _fail("case 7: dance continued after restart")
	_game.add_score(10000)
	await process_frame
	await process_frame
	var stopped := false
	for _i in 360:
		await process_frame
		var still := 0
		for node in squishies:
			if is_instance_valid(node) and bool(node.call("is_dancing")):
				still += 1
		if still == 0:
			stopped = true
			break
	if not stopped:
		return _fail("case 7: dance did not stop within 3s")
	_cases_passed += 1
	print("THEME case 7 pass")
	return true


func _case_8_alignment() -> bool:
	_theme.set_palette("neon_candy_baseline")
	await process_frame
	await process_frame
	if not _alignment_holds("after palette"):
		return false
	_theme.set_palette("aqua_pool")
	await process_frame
	await process_frame
	if not _alignment_holds("after palette switch"):
		return false
	_cases_passed += 1
	print("THEME case 8 pass alignment")
	return true


func _case_9_texture_retry() -> bool:
	var table := current_scene.get_node_or_null("Table")
	if table == null:
		return _fail("case 9: missing Table")
	var bumper := table.get_node_or_null("Bumper1")
	if bumper == null:
		return _fail("case 9: missing Bumper1")
	var squishy := bumper.get_node_or_null("Squishy")
	if squishy == null:
		return _fail("case 9: Bumper1 has no Squishy")
	var sprite := squishy.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return _fail("case 9: missing Sprite")
	var catalog_id := String(squishy.get("catalog_id"))
	var item: Dictionary = SquishyCatalog.entry(catalog_id)
	if item.is_empty() or not item.has("assets"):
		return _fail("case 9: catalog entry missing for %s" % catalog_id)
	var assets: Dictionary = item["assets"]
	var original_path := String(assets.get("sprite", ""))
	assets["sprite"] = "res://assets/design/squishes/art/__missing_t14__.png"
	squishy.call("setup", catalog_id)
	if sprite.texture != null:
		assets["sprite"] = original_path
		return _fail("case 9: texture should be null after a missing sprite path")
	assets["sprite"] = original_path
	_theme.palette_changed.emit(String(_theme.palette_id))
	await process_frame
	await process_frame
	if sprite.texture == null:
		return _fail("case 9: texture should load after palette_changed once the path is fixed")
	_cases_passed += 1
	print("THEME case 9 pass")
	return true


func _alignment_holds(when: String) -> bool:
	var squishies := get_nodes_in_group("squishies")
	if squishies.is_empty():
		return _fail("case 8: no squishies %s" % when)
	for node in squishies:
		if not (node is Node2D):
			continue
		var host := (node as Node).get_parent()
		if host == null:
			return _fail("case 8: %s has no host %s" % [node.name, when])
		var is_bumper := host.is_in_group("bumpers")
		var is_target := host.is_in_group("targets")
		if not is_bumper and not is_target:
			return _fail("case 8: %s host %s is not Bumper/Target %s" % [node.name, host.name, when])
		var sprite := node.get_node_or_null("Sprite") as Sprite2D
		var collider := host.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if sprite == null or collider == null:
			return _fail("case 8: %s missing sprite/collider %s" % [host.name, when])
		var delta: float = sprite.global_position.distance_to(collider.global_position)
		if delta > ALIGN_TOL_PX:
			return _fail(
				"case 8: %s sprite %s collider %s d=%.2f %s"
				% [host.name, sprite.global_position, collider.global_position, delta, when]
			)
	return true


func _colors_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _delete_settings() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("settings.save"):
		dir.remove("settings.save")


func _fail(message: String) -> bool:
	push_error("THEME FAIL %s" % message)
	print("THEME FAIL %s" % message)
	quit(1)
	return false
