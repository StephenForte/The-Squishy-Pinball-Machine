extends SceneTree

## Slice squishies_catalog.png into keyed RGBA sprites (D-020).
## Re-runnable and byte-reproducible: a second run must leave git status clean.

const CATALOG_PATH := "res://assets/design/squishes/squishies_catalog.json"
const OUT_DIR := "res://assets/design/squishes/art"

const HUE_LO := 0.55
const HUE_HI := 0.80
const BACKDROP_V := 0.20
const BACKDROP_DIST := 0.18
const BACKDROP_TYPICAL := Color(0.015, 0.008, 0.090, 1)
const MIN_BODY_ROW := 8
const BODY_PROBE_FRAC := 0.60
const FADE_ROWS := 8
const BORDER_PX := 2


func _initialize() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(catalog) != TYPE_DICTIONARY:
		push_error("slice: catalog is not a dictionary")
		return 1
	var sheet_info: Dictionary = catalog.get("sheet", {})
	var sheet_path := String(sheet_info.get("file", ""))
	var cell := int(sheet_info.get("cell_px", 313))
	var grid: Array = sheet_info.get("grid", [4, 4])
	var cols := int(grid[0])
	var rows := int(grid[1])

	var sheet := Image.new()
	var err := sheet.load(sheet_path)
	if err != OK:
		push_error("slice: failed to load %s (%s)" % [sheet_path, err])
		return 1
	sheet.convert(Image.FORMAT_RGBA8)

	var dir := DirAccess.open("res://")
	if dir == null:
		push_error("slice: cannot open res://")
		return 1
	err = dir.make_dir_recursive("assets/design/squishes/art")
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("slice: cannot create art dir (%s)" % err)
		return 1

	var written := 0
	for entry_var in catalog.get("squishies", []):
		var entry: Dictionary = entry_var
		var squishy_id := String(entry.get("id", ""))
		var index := int(entry.get("sheet_index", -1))
		if squishy_id.is_empty() or index < 0:
			push_error("slice: bad catalog entry %s" % entry)
			return 1
		var row := index / cols
		var col := index % cols
		if row >= rows or col >= cols:
			push_error("slice: sheet_index %d out of range for %s" % [index, squishy_id])
			return 1
		var cell_rect := Rect2i(col * cell, row * cell, cell, cell)
		var cell_img := sheet.get_region(cell_rect)
		var keyed := _key_cell(cell_img)
		var out_path := "%s/%s.png" % [OUT_DIR, squishy_id]
		err = keyed.save_png(out_path)
		if err != OK:
			push_error("slice: save failed %s (%s)" % [out_path, err])
			return 1
		written += 1
		print("slice wrote %s %dx%d" % [out_path, keyed.get_width(), keyed.get_height()])

	print("slice done count=%d" % written)
	return 0 if written > 0 else 1


func _key_cell(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			c.a = 1.0
			img.set_pixel(x, y, c)
	_flood_backdrop(img)
	_remove_reflection(img)
	_flood_backdrop(img)
	_keep_largest_blob(img)
	_force_border(img)
	return _crop_to_opaque(img)


func _is_backdrop(c: Color) -> bool:
	# Near-black playfield is backdrop when edge-connected; enclosed pupils stay.
	if c.v < 0.14:
		return true
	# Side/floor indigo glow: blue-dominant, almost no red/green. Purple bodies have red.
	if (
		c.v < 0.32
		and c.b >= 0.16
		and c.r < 0.10
		and c.g < 0.10
		and c.b >= maxf(c.r, c.g) * 2.0
		and c.h >= HUE_LO
		and c.h <= 0.78
	):
		return true
	if c.v >= BACKDROP_V:
		return false
	var dr := c.r - BACKDROP_TYPICAL.r
	var dg := c.g - BACKDROP_TYPICAL.g
	var db := c.b - BACKDROP_TYPICAL.b
	var dist := sqrt(dr * dr + dg * dg + db * db)
	if dist <= BACKDROP_DIST:
		return true
	# Residual dark indigo haze that is still empty playfield, not a purple body.
	if c.v < 0.22 and c.h >= HUE_LO and c.h <= HUE_HI and c.s >= 0.45 and c.b >= c.r and c.b >= c.g:
		return true
	return false


func _flood_backdrop(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for x in w:
		_enqueue(queue, seen, w, x, 0)
		_enqueue(queue, seen, w, x, h - 1)
	for y in h:
		_enqueue(queue, seen, w, 0, y)
		_enqueue(queue, seen, w, w - 1, y)
	var i := 0
	while i < queue.size():
		var p: Vector2i = queue[i]
		i += 1
		var c := img.get_pixel(p.x, p.y)
		if not _is_backdrop(c):
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		if p.x > 0:
			_enqueue(queue, seen, w, p.x - 1, p.y)
		if p.x + 1 < w:
			_enqueue(queue, seen, w, p.x + 1, p.y)
		if p.y > 0:
			_enqueue(queue, seen, w, p.x, p.y - 1)
		if p.y + 1 < h:
			_enqueue(queue, seen, w, p.x, p.y + 1)


func _enqueue(queue: Array[Vector2i], seen: Dictionary, w: int, x: int, y: int) -> void:
	var idx := y * w + x
	if seen.has(idx):
		return
	seen[idx] = true
	queue.append(Vector2i(x, y))


func _remove_reflection(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var radius := 12
	var core_bottom := -1
	var search_bottom := maxi(radius + 1, int(float(h) * 0.70) - radius)
	for y in range(radius, search_bottom):
		for x in range(radius, w - radius):
			var c := img.get_pixel(x, y)
			if c.a <= 0.5 or _is_floor_glow(c):
				continue
			if not _is_core_pixel(img, x, y, radius):
				continue
			if y > core_bottom:
				core_bottom = y
	var baseline := core_bottom
	if baseline < 0:
		baseline = _fallback_baseline(img)
	else:
		baseline = mini(h - 1, core_bottom + radius + 2)
	if baseline < 0:
		return
	for y in range(baseline + 1, h):
		var fade_t := 0.0
		if y - baseline < FADE_ROWS:
			fade_t = 1.0 - float(y - baseline) / float(FADE_ROWS)
		for x in w:
			var c := img.get_pixel(x, y)
			c.a *= fade_t
			img.set_pixel(x, y, c)


func _is_floor_glow(c: Color) -> bool:
	return (
		c.v < 0.50
		and c.h >= HUE_LO
		and c.h <= 0.78
		and c.s >= 0.40
		and c.b > c.r
		and c.b > c.g
	)


func _keep_largest_blob(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var best := -1
	var best_size := 0
	var next_id := 0
	for y in h:
		for x in w:
			var start := y * w + x
			if label[start] != -1 or img.get_pixel(x, y).a <= 0.5:
				continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			label[start] = next_id
			var qi := 0
			var count := 0
			while qi < queue.size():
				var p: Vector2i = queue[qi]
				qi += 1
				count += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					var idx := n.y * w + n.x
					if label[idx] != -1:
						continue
					if img.get_pixel(n.x, n.y).a <= 0.5:
						continue
					label[idx] = next_id
					queue.append(n)
			if count > best_size:
				best_size = count
				best = next_id
			next_id += 1
	if best < 0:
		return
	for y in h:
		for x in w:
			var idx := y * w + x
			if label[idx] != best and img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


func _is_core_pixel(img: Image, x: int, y: int, radius: int) -> bool:
	var needed := 0
	var ok := 0
	for dy in range(-radius, radius + 1, 3):
		for dx in range(-radius, radius + 1, 3):
			needed += 1
			if img.get_pixel(x + dx, y + dy).a > 0.5:
				ok += 1
	return ok * 4 >= needed * 3


func _fallback_baseline(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var last := -1
	var max_count := 0
	for y in int(float(h) * BODY_PROBE_FRAC):
		var count := 0
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				count += 1
		if count > max_count:
			max_count = count
		if count >= MIN_BODY_ROW:
			last = y
	if max_count <= 0:
		return last
	for y in range(int(float(h) * BODY_PROBE_FRAC), h):
		var count := 0
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				count += 1
		if count < maxi(MIN_BODY_ROW, int(float(max_count) * 0.28)):
			break
		last = y
	return last


func _force_border(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if x < BORDER_PX or y < BORDER_PX or x >= w - BORDER_PX or y >= h - BORDER_PX:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


func _crop_to_opaque(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.02:
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x < 0:
		return img
	min_x = maxi(0, min_x - BORDER_PX)
	min_y = maxi(0, min_y - BORDER_PX)
	max_x = mini(w - 1, max_x + BORDER_PX)
	max_y = mini(h - 1, max_y + BORDER_PX)
	var cropped := img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
	_force_border(cropped)
	return cropped
