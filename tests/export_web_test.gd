extends SceneTree

## Headless checks for the T26 / D-045 web export pipeline.
## Does not run the browser build. It asserts the scripted preset and the
## fail-closed missing-templates path so a clean checkout cannot silently
## produce a broken wasm.

const SCRIPT_RES := "res://tools/export_web.sh"
const GITIGNORE_RES := "res://.gitignore"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("EXPORT_WEB start")
	if not await _case_1_script_and_gitignore():
		return
	if not await _case_2_write_preset():
		return
	if not await _case_3_missing_templates():
		return
	print("EXPORT_WEB PASS cases=3")
	quit(0)


func _case_1_script_and_gitignore() -> bool:
	print("EXPORT_WEB case 1: script + D-008 ignore rules")
	var script_path := ProjectSettings.globalize_path(SCRIPT_RES)
	if not FileAccess.file_exists(script_path):
		return _fail("case 1: tools/export_web.sh missing")
	var script := FileAccess.get_file_as_string(script_path)
	if script.is_empty():
		return _fail("case 1: tools/export_web.sh is empty")
	for needle in [
		"web_nothreads_release.zip",
		"variant/thread_support=false",
		"PRESET_NAME=\"Web\"",
		"export/web",
		"Godot web export templates are not installed",
	]:
		if not script.contains(needle):
			return _fail("case 1: export_web.sh does not contain %s" % needle)
	var ignore := FileAccess.get_file_as_string(ProjectSettings.globalize_path(GITIGNORE_RES))
	if not ignore.contains("export/"):
		return _fail("case 1: .gitignore lost export/ (D-008)")
	if not ignore.contains("export_presets.cfg"):
		return _fail("case 1: .gitignore lost export_presets.cfg (D-008)")
	var project := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://project.godot"))
	if not project.contains("import_etc2_astc=true"):
		return _fail("case 1: project.godot lost import_etc2_astc (Web mobile VRAM)")
	print("EXPORT_WEB case 1 PASS")
	return true


func _case_2_write_preset() -> bool:
	print("EXPORT_WEB case 2: generated Web preset")
	var preset_path := OS.get_user_data_dir().path_join("t26_export_presets.cfg")
	if FileAccess.file_exists(preset_path):
		DirAccess.remove_absolute(preset_path)
	var output: Array = []
	var code := OS.execute("/usr/bin/env", PackedStringArray([
		"SQUISH_EXPORT_PRESET_PATH=%s" % preset_path,
		"/bin/bash",
		ProjectSettings.globalize_path(SCRIPT_RES),
		"--write-preset-only",
	]), output, true)
	if code != 0:
		return _fail("case 2: --write-preset-only exit %d: %s" % [code, str(output)])
	if not FileAccess.file_exists(preset_path):
		return _fail("case 2: preset was not written to %s" % preset_path)
	var text := FileAccess.get_file_as_string(preset_path)
	DirAccess.remove_absolute(preset_path)
	var required := {
		"name=\"Web\"": true,
		"platform=\"Web\"": true,
		"variant/thread_support=false": true,
		"variant/extensions_support=false": true,
		"vram_texture_compression/for_desktop=true": true,
		"vram_texture_compression/for_mobile=true": true,
		"html/export_icon=true": true,
		"progressive_web_app/enabled=false": true,
		"progressive_web_app/ensure_cross_origin_isolation_headers=false": true,
		"html/experimental_virtual_keyboard=true": true,
		"export_path=": true,
	}
	for key in required:
		if not text.contains(String(key)):
			return _fail("case 2: generated preset missing %s" % String(key))
	if text.contains("variant/thread_support=true"):
		return _fail("case 2: generated preset enabled threads")
	if text.contains("html/experimental_virtual_keyboard=false"):
		return _fail("case 2: generated preset left the virtual keyboard off")
	print("EXPORT_WEB case 2 PASS")
	return true


func _case_3_missing_templates() -> bool:
	print("EXPORT_WEB case 3: missing templates fail closed")
	var empty_dir := OS.get_user_data_dir().path_join("t26_empty_templates")
	var out_dir := OS.get_user_data_dir().path_join("t26_empty_export")
	var preset_path := OS.get_user_data_dir().path_join("t26_empty_preset.cfg")
	_rm_tree(empty_dir)
	_rm_tree(out_dir)
	DirAccess.make_dir_recursive_absolute(empty_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Plant a decoy so a broken script that skips the template check would
	# still have somewhere to write. The wasm must not appear.
	var decoy := FileAccess.open(out_dir.path_join("stale.txt"), FileAccess.WRITE)
	if decoy != null:
		decoy.store_string("stale")
		decoy.close()
	var output: Array = []
	var code := OS.execute("/usr/bin/env", PackedStringArray([
		"SQUISH_EXPORT_TEMPLATES_DIR=%s" % empty_dir,
		"SQUISH_EXPORT_OUT_DIR=%s" % out_dir,
		"SQUISH_EXPORT_PRESET_PATH=%s" % preset_path,
		"SQUISH_SKIP_TEMPLATE_DOWNLOAD=1",
		"/bin/bash",
		ProjectSettings.globalize_path(SCRIPT_RES),
	]), output, true)
	var joined := ""
	for line in output:
		joined += str(line) + "\n"
	_rm_tree(empty_dir)
	var wrote_wasm := FileAccess.file_exists(out_dir.path_join("index.wasm"))
	_rm_tree(out_dir)
	if FileAccess.file_exists(preset_path):
		DirAccess.remove_absolute(preset_path)
	if code == 0:
		return _fail("case 3: export succeeded without templates")
	if wrote_wasm:
		return _fail("case 3: wrote index.wasm without templates")
	if not joined.contains("Godot web export templates are not installed"):
		return _fail("case 3: missing-templates message absent: %s" % joined)
	if not joined.contains("web_nothreads_release.zip"):
		return _fail("case 3: error did not name web_nothreads_release.zip")
	print("EXPORT_WEB case 3 PASS")
	return true


func _rm_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				_rm_tree(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _fail(message: String) -> bool:
	print("EXPORT_WEB FAIL %s" % message)
	quit(1)
	return false
