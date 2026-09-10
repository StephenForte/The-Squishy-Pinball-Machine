extends SceneTree

## Slice app_icons_sheet.png into 512×512 PNGs (D-032).
## Re-runnable and byte-reproducible: a second run must leave git status clean.

const CATALOG_PATH := "res://assets/design/icons/app_icons.json"
const OUT_SIZE := 512


func _initialize() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(catalog) != TYPE_DICTIONARY:
		push_error("slice_icons: catalog is not a dictionary")
		return 1
	var sheet_info: Dictionary = catalog.get("sheet", {})
	var sheet_path := String(sheet_info.get("file", ""))
	var cell := int(sheet_info.get("cell", 617))
	var border := int(sheet_info.get("border", 6))
	var gutter := int(sheet_info.get("gutter", 8))
	var grid: Array = sheet_info.get("grid", [2, 2])
	var cols := int(grid[0])
	var rows := int(grid[1])

	var sheet := Image.new()
	var err := sheet.load(sheet_path)
	if err != OK:
		push_error("slice_icons: failed to load %s (%s)" % [sheet_path, err])
		return 1
	sheet.convert(Image.FORMAT_RGBA8)

	var dir := DirAccess.open("res://")
	if dir == null:
		push_error("slice_icons: cannot open res://")
		return 1
	err = dir.make_dir_recursive("assets/icons")
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("slice_icons: cannot create icons dir (%s)" % err)
		return 1

	var written := 0
	for entry_var in catalog.get("icons", []):
		var entry: Dictionary = entry_var
		var icon_id := String(entry.get("id", ""))
		var index := int(entry.get("sheet_index", -1))
		if icon_id.is_empty() or index < 0:
			push_error("slice_icons: bad catalog entry %s" % entry)
			return 1
		var row := index / cols
		var col := index % cols
		if row >= rows or col >= cols:
			push_error("slice_icons: sheet_index %d out of range for %s" % [index, icon_id])
			return 1
		var x := border + col * (cell + gutter)
		var y := border + row * (cell + gutter)
		var cell_rect := Rect2i(x, y, cell, cell)
		var cell_img := sheet.get_region(cell_rect)
		cell_img.convert(Image.FORMAT_RGBA8)
		cell_img.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
		var assets: Dictionary = entry.get("assets", {})
		var out_path := String(assets.get("icon", "res://assets/icons/%s.png" % icon_id))
		err = cell_img.save_png(out_path)
		if err != OK:
			push_error("slice_icons: save failed %s (%s)" % [out_path, err])
			return 1
		written += 1
		print("slice_icons wrote %s %dx%d from (%d,%d)" % [out_path, cell_img.get_width(), cell_img.get_height(), x, y])

	print("slice_icons done count=%d" % written)
	return 0 if written > 0 else 1
