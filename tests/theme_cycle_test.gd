extends SceneTree

## D-061 / T46. The palette on screen during a run is the saved pick shifted by
## floor(score / 10000). That shift is never written to settings.save.
## The title and game over show the saved pick again.

const BASE_0 := "neon_candy_baseline"
const BASE_1 := "grape_jam"
const BASE_2 := "aqua_pool"
const BASE_3 := "sherbet_sunrise"

var _cases_passed: int = 0
var _theme: Node
var _game: Node
var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("THEME_CYCLE start")
	var user_dir := OS.get_user_data_dir()
	if not user_dir.ends_with("SquishyPinballTest"):
		_fail("refusing to run outside the test user dir (%s)" % user_dir)
		return
	_delete_settings()
	_theme = root.get_node_or_null("Theme")
	_game = root.get_node_or_null("Game")
	if _theme == null or _game == null:
		_fail("Theme or Game autoload missing")
		return
	_theme._load_catalog()
	_theme._load_settings()
	if String(_theme.palette_id) != BASE_0 or String(_theme.saved_palette_id) != BASE_0:
		_fail("boot pick %s saved %s" % [_theme.palette_id, _theme.saved_palette_id])
		return

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load main.tscn")
		return
	await process_frame
	await process_frame
	await process_frame
	_main = current_scene
	if _main == null:
		_fail("no main scene")
		return
	var drain := _main.get_node_or_null("Table/Drain") as Area2D
	if drain != null:
		drain.monitoring = false

	if not await _picker_can_open_on_title():
		return
	if not await _leave_title():
		return

	if not await _case_1_base_zero():
		return
	if not await _case_2_base_two():
		return
	if not await _case_3_jump():
		return
	if not await _case_4_over_and_restart():
		return
	if not await _case_5_unrelated_save():
		return
	if not await _case_6_picker_closed_mid_run():
		return

	print("THEME_CYCLE PASS cases=%d" % _cases_passed)
	quit(0)


func _picker_can_open_on_title() -> bool:
	print("THEME_CYCLE picker positive control")
	var title := _main.get_node_or_null("Title")
	var settings := _main.get_node_or_null("Title/Settings") as Control
	var picker := _main.get_node_or_null("Title/Settings/ThemePicker") as Control
	if title == null or settings == null or picker == null:
		return _fail("positive: Title, Settings, or ThemePicker missing")
	if not title.visible:
		return _fail("positive: title should start visible")
	_release_name_focus(title)
	if settings.has_method("open"):
		settings.open()
	else:
		settings.visible = true
	await process_frame
	if not picker.is_visible_in_tree():
		return _fail("positive: ThemePicker should be on screen while the title is up")
	if settings.has_method("close"):
		settings.close()
	else:
		settings.visible = false
	await process_frame
	if picker.is_visible_in_tree():
		return _fail("positive: ThemePicker still up after close")
	print("THEME_CYCLE picker positive control pass")
	return true


func _leave_title() -> bool:
	var title := _main.get_node_or_null("Title")
	if title == null:
		return _fail("title missing")
	if title.has_method("_dismiss_title"):
		title._dismiss_title()
	else:
		title.visible = false
	await process_frame
	if bool(title.visible):
		return _fail("title still shown after dismiss")
	return true


func _case_1_base_zero() -> bool:
	print("THEME_CYCLE case 1 saved index 0")
	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(9999)
	await process_frame
	if not _active_is(BASE_0, "case 1 at 9999"):
		return false
	if not _file_holds(BASE_0, "case 1 at 9999"):
		return false

	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(10000)
	await process_frame
	if not _active_is(BASE_1, "case 1 at 10000"):
		return false
	if not _painted(BASE_1, "case 1 at 10000"):
		return false
	if not _file_holds(BASE_0, "case 1 at 10000"):
		return false

	var title := _main.get_node_or_null("Title")
	if title != null and title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	if title == null or not bool(title.visible):
		return _fail("case 1: title did not show")
	if not _active_is(BASE_0, "case 1 title shown at 10000"):
		return false
	if not await _leave_title():
		return false
	if int(_game.score) != 10000:
		return _fail("case 1: leaving the title changed the score")
	if not _active_is(BASE_1, "case 1 title hidden again"):
		return false

	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(20000)
	await process_frame
	if not _active_is(BASE_2, "case 1 at 20000"):
		return false

	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(40000)
	await process_frame
	if not _active_is(BASE_0, "case 1 at 40000 wrap"):
		return false
	if String(_theme.saved_palette_id) != BASE_0:
		return _fail("case 1: wrap wrote over the saved pick")

	_cases_passed += 1
	print("THEME_CYCLE case 1 pass")
	return true


func _case_2_base_two() -> bool:
	print("THEME_CYCLE case 2 saved index 2")
	if not await _fresh_base(BASE_2):
		return false
	_game.add_score(10000)
	await process_frame
	if not _active_is(BASE_3, "case 2 at 10000"):
		return false
	if not _file_holds(BASE_2, "case 2 at 10000"):
		return false

	if not await _fresh_base(BASE_2):
		return false
	_game.add_score(20000)
	await process_frame
	if not _active_is(BASE_0, "case 2 at 20000"):
		return false
	if String(_theme.saved_palette_id) != BASE_2:
		return _fail("case 2: saved pick moved")

	_cases_passed += 1
	print("THEME_CYCLE case 2 pass")
	return true


func _case_3_jump() -> bool:
	print("THEME_CYCLE case 3 one add_score crosses two milestones")
	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(9000)
	await process_frame
	if not _active_is(BASE_0, "case 3 at 9000"):
		return false
	var heard := {"n": 0, "last": ""}
	var on_palette := func(id: String) -> void:
		heard["n"] = int(heard["n"]) + 1
		heard["last"] = id
	_theme.palette_changed.connect(on_palette)
	_game.add_score(12000)
	await process_frame
	if _theme.palette_changed.is_connected(on_palette):
		_theme.palette_changed.disconnect(on_palette)
	if int(_game.score) != 21000:
		return _fail("case 3: score %s" % _game.score)
	if int(heard["n"]) != 1:
		return _fail("case 3: palette_changed count %s last %s" % [heard["n"], heard["last"]])
	if str(heard["last"]) != BASE_2:
		return _fail("case 3: emitted %s" % heard["last"])
	if not _active_is(BASE_2, "case 3 at 21000"):
		return false
	if not _painted(BASE_2, "case 3 at 21000"):
		return false

	_cases_passed += 1
	print("THEME_CYCLE case 3 pass")
	return true


func _case_4_over_and_restart() -> bool:
	print("THEME_CYCLE case 4 game over and restart")
	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(10000)
	await process_frame
	if not _active_is(BASE_1, "case 4 before game over"):
		return false
	for _i in 3:
		_game.on_ball_drained()
		await physics_frame
		await process_frame
	if int(_game.state) != int(_game.GAME_OVER):
		return _fail("case 4: state %s" % _game.state)
	if not _active_is(BASE_0, "case 4 game over"):
		return false
	if not _painted(BASE_0, "case 4 game over"):
		return false
	if not _file_holds(BASE_0, "case 4 game over"):
		return false

	_game.restart()
	await process_frame
	if int(_game.score) != 0:
		return _fail("case 4: restart score %s" % _game.score)
	if int(_game.state) == int(_game.GAME_OVER):
		return _fail("case 4: restart left GAME_OVER")
	if not _active_is(BASE_0, "case 4 restart"):
		return false
	if not _painted(BASE_0, "case 4 restart"):
		return false
	if String(_theme.saved_palette_id) != BASE_0:
		return _fail("case 4: restart changed the saved pick")

	_cases_passed += 1
	print("THEME_CYCLE case 4 pass")
	return true


func _case_5_unrelated_save() -> bool:
	print("THEME_CYCLE case 5 unrelated settings save")
	if not await _fresh_base(BASE_0):
		return false
	_game.add_score(10000)
	await process_frame
	if not _active_is(BASE_1, "case 5 before save"):
		return false
	var planted: Variant = JSON.parse_string(_settings_text())
	if typeof(planted) != TYPE_DICTIONARY:
		return _fail("case 5: settings.save missing before the extra save")
	var data: Dictionary = planted
	if String(data.get("palette_id", "")) != BASE_0:
		return _fail("case 5: file already held %s" % data.get("palette_id", ""))
	data["sfx_muted"] = true
	var file := FileAccess.open("user://settings.save", FileAccess.WRITE)
	if file == null:
		return _fail("case 5: could not write settings.save")
	file.store_string(JSON.stringify(data))
	file.close()
	_theme._load_settings()
	await process_frame
	if not _active_is(BASE_1, "case 5 after reload"):
		return false
	if String(_theme.saved_palette_id) != BASE_0:
		return _fail("case 5: reload saved %s" % _theme.saved_palette_id)
	_theme._save_settings()
	var saved: Variant = JSON.parse_string(_settings_text())
	if typeof(saved) != TYPE_DICTIONARY:
		return _fail("case 5: settings.save unreadable after save")
	var after: Dictionary = saved
	if String(after.get("palette_id", "")) != BASE_0:
		return _fail("case 5: save wrote %s (run palette %s)" % [after.get("palette_id", ""), _theme.palette_id])
	if after.get("palette_id", "") == _theme.palette_id:
		return _fail("case 5: file matches the run palette")
	if after.get("sfx_muted", false) != true:
		return _fail("case 5: unrelated key dropped")
	if not _active_is(BASE_1, "case 5 after save"):
		return false

	_cases_passed += 1
	print("THEME_CYCLE case 5 pass")
	return true


func _case_6_picker_closed_mid_run() -> bool:
	print("THEME_CYCLE case 6 picker cannot open mid-run")
	if not _active_is(BASE_1, "case 6 still mid-run"):
		return false
	var title := _main.get_node_or_null("Title")
	var settings := _main.get_node_or_null("Title/Settings") as Control
	var picker := _main.get_node_or_null("Title/Settings/ThemePicker") as Control
	if title == null or settings == null or picker == null:
		return _fail("case 6: settings nodes missing")
	if bool(title.visible):
		return _fail("case 6: title is shown, so this is not mid-run")
	_release_name_focus(title)
	if settings.has_method("open"):
		settings.open()
	else:
		settings.visible = true
	await process_frame
	if picker.is_visible_in_tree() or (settings.has_method("is_open") and settings.is_open()):
		return _fail("case 6: ThemePicker opened during the run")
	if settings.visible and bool(title.visible):
		return _fail("case 6: opening settings brought the title back")
	# The open() call did run: the overlay flag is set, the title hides it.
	if not settings.visible:
		return _fail("case 6: settings.open() did not run (no effect to disprove)")
	var saved_before := String(_theme.saved_palette_id)
	var active_before := String(_theme.palette_id)
	if settings.has_method("close"):
		settings.close()
	if String(_theme.saved_palette_id) != saved_before or String(_theme.palette_id) != active_before:
		return _fail("case 6: a closed picker changed the palette")

	_cases_passed += 1
	print("THEME_CYCLE case 6 pass")
	return true


func _fresh_base(id: String) -> bool:
	_game.restart()
	await process_frame
	var title := _main.get_node_or_null("Title")
	if title != null and bool(title.visible):
		if not await _leave_title():
			return false
	_theme.set_palette(id)
	await process_frame
	if int(_game.score) != 0:
		return _fail("fresh base: score %s" % _game.score)
	if String(_theme.saved_palette_id) != id:
		return _fail("fresh base: saved %s" % _theme.saved_palette_id)
	if String(_theme.palette_id) != id:
		return _fail("fresh base: active %s at score 0" % _theme.palette_id)
	return true


func _active_is(id: String, where: String) -> bool:
	if String(_theme.palette_id) != id:
		return _fail("%s: active %s saved %s" % [where, _theme.palette_id, _theme.saved_palette_id])
	return true


func _painted(id: String, where: String) -> bool:
	if String(_theme.palette_id) != id:
		return _fail("%s: palette %s" % [where, _theme.palette_id])
	var playfield := _main.find_child("Background", true, false) as Polygon2D
	if playfield == null:
		return _fail("%s: missing playfield" % where)
	var want: Color = _theme.color("playfield_base")
	if not _colors_close(playfield.color, want):
		return _fail("%s: playfield %s != %s" % [where, playfield.color, want])
	var score := _main.find_child("ScoreLabel", true, false) as Label
	if score == null:
		return _fail("%s: missing ScoreLabel" % where)
	if not _colors_close(score.get_theme_color("font_color"), _theme.color("text_primary")):
		return _fail("%s: ScoreLabel did not follow palette_changed" % where)
	var paddle := _main.get_node_or_null("Table/FlipperLeft/Visual") as Polygon2D
	if paddle == null:
		return _fail("%s: missing flipper visual" % where)
	if not _colors_close(paddle.color, _theme.color("object_orange")):
		return _fail("%s: flipper did not follow palette_changed" % where)
	var squishy := _main.get_node_or_null("Table/Bumper1/Squishy")
	if squishy == null or squishy.get_node_or_null("Sprite") == null:
		return _fail("%s: slot squishy missing after apply" % where)
	var sprite := squishy.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return _fail("%s: slot sprite lost its texture" % where)
	return true


func _file_holds(id: String, where: String) -> bool:
	var parsed: Variant = JSON.parse_string(_settings_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("%s: settings.save unreadable" % where)
	var got := String((parsed as Dictionary).get("palette_id", ""))
	if got != id:
		return _fail("%s: settings.save palette_id %s" % [where, got])
	return true


func _settings_text() -> String:
	if not FileAccess.file_exists("user://settings.save"):
		return ""
	return FileAccess.get_file_as_string("user://settings.save")


func _release_name_focus(title: Node) -> void:
	var entry := title.get_node_or_null("NameEntry")
	if entry != null and entry.has_method("release_name_focus"):
		entry.release_name_focus()


func _colors_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _delete_settings() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("settings.save"):
		dir.remove("settings.save")


func _fail(message: String) -> bool:
	push_error("THEME_CYCLE FAIL %s" % message)
	print("THEME_CYCLE FAIL %s" % message)
	quit(1)
	return false
