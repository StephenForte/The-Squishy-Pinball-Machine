extends SceneTree

const CATALOG_PATH := "res://assets/design/icons/app_icons.json"
const SAVE_PATH := "user://app_icon.save"
const EXPECTED_IDS := ["gummy_bear", "jelly_trio", "glitter_drop", "ice_cube"]

var _cases_passed: int = 0
var _app_icon: Node
var _changed_count: int = 0
var _last_changed_id: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("APP_ICON start")
	_delete_save()
	_app_icon = root.get_node_or_null("AppIcon")
	if _app_icon == null:
		_fail("AppIcon autoload missing")
		return
	_app_icon._load_catalog()
	_app_icon._load_save()
	if _app_icon.has_signal("icon_changed"):
		_app_icon.icon_changed.connect(_on_icon_changed)

	if not await _case_1_catalog():
		return
	if not await _case_2_images():
		return
	if not await _case_3_fresh_default():
		return
	if not await _case_4_persist_and_reject():
		return
	if not await _case_5_signal():
		return
	if not await _case_6_corrupt_fallback():
		return
	if not await _case_7_no_white_edge():
		return

	print("APP_ICON PASS cases=%d" % _cases_passed)
	quit(0)


func _on_icon_changed(id: String) -> void:
	_changed_count += 1
	_last_changed_id = id


func _case_1_catalog() -> bool:
	print("APP_ICON case 1 catalog")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("case 1: catalog is not a dictionary")
	var data: Dictionary = parsed
	if int(data.get("schema_version", 0)) != 1:
		return _fail("case 1: schema_version %s" % data.get("schema_version", ""))
	if String(data.get("default_icon_id", "")) != "glitter_drop":
		return _fail("case 1: default_icon_id %s" % data.get("default_icon_id", ""))
	var icons: Array = data.get("icons", [])
	if icons.size() != 4:
		return _fail("case 1: icons.size=%d" % icons.size())
	var ids: PackedStringArray = _app_icon.icon_ids()
	if ids.size() != 4:
		return _fail("case 1: icon_ids size %d" % ids.size())
	for i in EXPECTED_IDS.size():
		if String(ids[i]) != EXPECTED_IDS[i]:
			return _fail("case 1: id[%d]=%s want=%s" % [i, ids[i], EXPECTED_IDS[i]])
		var entry: Dictionary = icons[i]
		if String(entry.get("id", "")) != EXPECTED_IDS[i]:
			return _fail("case 1: catalog id[%d]=%s" % [i, entry.get("id", "")])
		if int(entry.get("sheet_index", -1)) != i:
			return _fail("case 1: sheet_index[%d]=%s" % [i, entry.get("sheet_index", "")])
	if String(_app_icon.default_icon_id) != "glitter_drop":
		return _fail("case 1: autoload default %s" % _app_icon.default_icon_id)
	if String(_app_icon.icon_name("glitter_drop")) == "":
		return _fail("case 1: icon_name empty")
	_cases_passed += 1
	print("APP_ICON case 1 pass")
	return true


func _case_2_images() -> bool:
	print("APP_ICON case 2 images")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var data: Dictionary = parsed
	for entry_var in data.get("icons", []):
		var entry: Dictionary = entry_var
		var icon_id := String(entry.get("id", ""))
		var assets: Dictionary = entry.get("assets", {})
		var path := String(assets.get("icon", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			return _fail("case 2: missing %s" % path)
		var tex := load(path) as Texture2D
		if tex == null:
			return _fail("case 2: Texture2D load failed %s" % path)
		var img := tex.get_image()
		if img == null:
			return _fail("case 2: no image %s" % path)
		if img.is_compressed():
			img.decompress()
		if img.get_width() != 512 or img.get_height() != 512:
			return _fail("case 2: %s is %dx%d" % [icon_id, img.get_width(), img.get_height()])
	_cases_passed += 1
	print("APP_ICON case 2 pass")
	return true


func _case_3_fresh_default() -> bool:
	print("APP_ICON case 3 fresh")
	_delete_save()
	_app_icon._load_save()
	if String(_app_icon.icon_id) != String(_app_icon.default_icon_id):
		return _fail("case 3: icon_id=%s default=%s" % [_app_icon.icon_id, _app_icon.default_icon_id])
	if String(_app_icon.icon_id) != "glitter_drop":
		return _fail("case 3: expected glitter_drop, got %s" % _app_icon.icon_id)
	if FileAccess.file_exists(SAVE_PATH):
		return _fail("case 3: save file should not exist on a fresh user dir")
	_cases_passed += 1
	print("APP_ICON case 3 pass")
	return true


func _case_4_persist_and_reject() -> bool:
	print("APP_ICON case 4 persist")
	_changed_count = 0
	if not bool(_app_icon.set_icon("ice_cube")):
		return _fail("case 4: set_icon(ice_cube) returned false")
	if String(_app_icon.icon_id) != "ice_cube":
		return _fail("case 4: icon_id=%s" % _app_icon.icon_id)
	if not FileAccess.file_exists(SAVE_PATH):
		return _fail("case 4: app_icon.save missing")
	var saved_text := FileAccess.get_file_as_string(SAVE_PATH)
	var saved_parsed: Variant = JSON.parse_string(saved_text)
	if typeof(saved_parsed) != TYPE_DICTIONARY:
		return _fail("case 4: save is not a dictionary")
	if String(saved_parsed.get("icon_id", "")) != "ice_cube":
		return _fail("case 4: save icon_id=%s" % saved_parsed.get("icon_id", ""))

	var fresh: Node = load("res://autoload/app_icon.gd").new()
	root.add_child(fresh)
	await process_frame
	var reloaded := String(fresh.get("icon_id"))
	fresh.queue_free()
	await process_frame
	if reloaded != "ice_cube":
		return _fail("case 4: reloaded %s" % reloaded)

	var before := FileAccess.get_file_as_string(SAVE_PATH)
	if bool(_app_icon.set_icon("nope")):
		return _fail("case 4: set_icon(nope) returned true")
	if String(_app_icon.icon_id) != "ice_cube":
		return _fail("case 4: reject changed id to %s" % _app_icon.icon_id)
	var after := FileAccess.get_file_as_string(SAVE_PATH)
	if after != before:
		return _fail("case 4: reject rewrote the save file")
	_cases_passed += 1
	print("APP_ICON case 4 pass")
	return true


func _case_5_signal() -> bool:
	print("APP_ICON case 5 signal")
	_changed_count = 0
	_last_changed_id = ""
	if not bool(_app_icon.set_icon("gummy_bear")):
		return _fail("case 5: set_icon(gummy_bear) failed")
	if _changed_count != 1:
		return _fail("case 5: expected 1 emit after success, got %d" % _changed_count)
	if _last_changed_id != "gummy_bear":
		return _fail("case 5: emitted id=%s" % _last_changed_id)
	if bool(_app_icon.set_icon("nope")):
		return _fail("case 5: set_icon(nope) returned true")
	if _changed_count != 1:
		return _fail("case 5: reject emitted icon_changed (count=%d)" % _changed_count)
	if String(_app_icon.icon_id) != "gummy_bear":
		return _fail("case 5: reject changed id to %s" % _app_icon.icon_id)
	_cases_passed += 1
	print("APP_ICON case 5 pass")
	return true


func _case_6_corrupt_fallback() -> bool:
	print("APP_ICON case 6 corrupt")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("case 6: could not write save")
	file.store_string('{"icon_id":"not_an_icon"}')
	file.close()
	_app_icon._load_save()
	if String(_app_icon.icon_id) != "glitter_drop":
		return _fail("case 6: unknown id yielded %s" % _app_icon.icon_id)

	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("case 6: could not write corrupt save")
	file.store_string("not-json{{{")
	file.close()
	_app_icon._load_save()
	if String(_app_icon.icon_id) != "glitter_drop":
		return _fail("case 6: corrupt json yielded %s" % _app_icon.icon_id)
	_cases_passed += 1
	print("APP_ICON case 6 pass")
	return true


func _case_7_no_white_edge() -> bool:
	print("APP_ICON case 7 edges")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("case 7: catalog is not a dictionary")
	var data: Dictionary = parsed
	for entry_var in data.get("icons", []):
		var entry: Dictionary = entry_var
		var icon_id := String(entry.get("id", ""))
		var assets: Dictionary = entry.get("assets", {})
		var path := String(assets.get("icon", ""))
		var abs_path := ProjectSettings.globalize_path(path)
		var img := Image.load_from_file(abs_path)
		if img == null:
			return _fail("case 7: load_from_file failed %s" % path)
		var top := _row_mean_luminance(img, 0)
		var bottom := _row_mean_luminance(img, img.get_height() - 1)
		print("APP_ICON case 7 %s lum top=%.2f bottom=%.2f" % [icon_id, top, bottom])
		if top >= 0.9:
			return _fail("case 7: %s top-row luminance %.2f >= 0.9" % [icon_id, top])
		if bottom >= 0.9:
			return _fail("case 7: %s bottom-row luminance %.2f >= 0.9" % [icon_id, bottom])
	_cases_passed += 1
	print("APP_ICON case 7 pass")
	return true


func _row_mean_luminance(img: Image, y: int) -> float:
	var w := img.get_width()
	if w <= 0:
		return 0.0
	var total := 0.0
	for x in w:
		total += img.get_pixel(x, y).get_luminance()
	return total / float(w)


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("app_icon.save"):
		dir.remove("app_icon.save")


func _fail(message: String) -> bool:
	push_error("APP_ICON FAIL %s" % message)
	print("APP_ICON FAIL %s" % message)
	quit(1)
	return false
