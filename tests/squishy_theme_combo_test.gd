extends SceneTree

## D-061 / T49. T45's swap and T46's 10,000 palette shift in one run.
## A fresh wave-0 seed makes two unpinned runs differ. Pinning
## squishy_seed_override repeats a run. Hosts stay on the table's assignment
## even when the slot reset lands after the swap (the order that fails on
## main, where nothing re-applies after a deferred first_table_slots write).

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
## Two independent 10-rotation sequences. A fresh seed collides at 1 in 2^32;
## five misses means the reseed is stuck, not that we lost a coin flip.
const DIVERSITY_ATTEMPTS := 5
const ROTATIONS := 10
const MILESTONE_ROTATIONS := 20

var _game: Node
var _table: Node2D
var _theme: Node
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("SQUISHY_THEME_COMBO start")
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
	var drain := _table.get_node_or_null("Drain") as Area2D
	if drain != null:
		drain.monitoring = false
	if not _dismiss_title():
		return
	await process_frame

	if not await _case_bad_order():
		return
	if not await _case_diversity():
		return
	if not await _case_pinned_seed():
		return
	if not await _case_milestones():
		return

	print("SQUISHY_THEME_COMBO PASS cases=%d" % _cases_passed)
	quit(0)


func _case_bad_order() -> bool:
	print("SQUISHY_THEME_COMBO case bad-order deferred slot reset")
	_clear_seed_override()
	if not await _restart():
		return false
	var originals := _ids()
	_game.add_score(10000)
	await _settle()
	if int(_game.score) != 10000 or int(_game.board_wave) != 2:
		return _fail("bad-order: score=%s wave=%s" % [_game.score, _game.board_wave])
	var assigned := _assigned()
	if not _same(_ids(), assigned):
		return _fail("bad-order: before reset hosts %s assigned %s" % [_ids(), assigned])
	if _same(assigned, originals):
		return _fail("bad-order: assignment still the starting set %s" % assigned)
	if not _all_changed(originals, assigned) or not _distinct(assigned):
		return _fail("bad-order: assignment %s originals %s" % [assigned, originals])
	# The planner's positive control: paint first_table_slots on a later frame,
	# after palette_changed has already run. Today's listener cannot see it.
	_theme.call_deferred("_apply_slots_in_tree")
	await process_frame
	await process_frame
	var got := _ids()
	if not _same(got, assigned):
		return _fail(
			"bad-order: deferred slot reset left %s, assignment %s, starting %s"
			% [got, assigned, originals]
		)
	_cases_passed += 1
	print("SQUISHY_THEME_COMBO case bad-order pass")
	return true


func _case_diversity() -> bool:
	print("SQUISHY_THEME_COMBO case diversity fresh seed")
	_clear_seed_override()
	for attempt in DIVERSITY_ATTEMPTS:
		var first := await _rotations(ROTATIONS)
		if first.is_empty():
			return false
		var second := await _rotations(ROTATIONS)
		if second.is_empty():
			return false
		if not _sequences_equal(first, second):
			_cases_passed += 1
			print(
				"SQUISHY_THEME_COMBO case diversity pass attempts=%d bound=%d"
				% [attempt + 1, DIVERSITY_ATTEMPTS]
			)
			return true
		print("SQUISHY_THEME_COMBO diversity attempt %d matched; retrying" % (attempt + 1))
	return _fail(
		"diversity: %d pairs of %d rotations matched (fresh seed looks stuck)"
		% [DIVERSITY_ATTEMPTS, ROTATIONS]
	)


func _case_pinned_seed() -> bool:
	print("SQUISHY_THEME_COMBO case pinned seed")
	_table.set("squishy_seed_override", 61061)
	var first := await _rotations(ROTATIONS)
	if first.is_empty():
		return false
	var second := await _rotations(ROTATIONS)
	if second.is_empty():
		return false
	if not _sequences_equal(first, second):
		return _fail("pinned: sequences differed")
	_clear_seed_override()
	_cases_passed += 1
	print("SQUISHY_THEME_COMBO case pinned seed pass")
	return true


func _case_milestones() -> bool:
	print("SQUISHY_THEME_COMBO case milestones to 100000")
	_clear_seed_override()
	if not await _restart():
		return false
	var saved := String(_theme.get("saved_palette_id"))
	var previous := _ids()
	if not _distinct(previous):
		return _fail("milestones: wave 0 ids %s" % previous)
	for step in MILESTONE_ROTATIONS:
		_game.add_score(5000)
		await _settle()
		var score := int(_game.score)
		var wave := int(_game.board_wave)
		if score != (step + 1) * 5000 or wave != step + 1:
			return _fail("milestones: step %d score=%s wave=%s" % [step + 1, score, wave])
		var now := _ids()
		var assigned := _assigned()
		if not _all_changed(previous, now):
			return _fail("milestones: step %d repeated %s -> %s" % [step + 1, previous, now])
		if not _distinct(now):
			return _fail("milestones: step %d duplicates %s" % [step + 1, now])
		if not _same(now, assigned):
			return _fail("milestones: step %d hosts %s assigned %s" % [step + 1, now, assigned])
		if not _textures_loaded():
			return _fail("milestones: step %d texture null" % (step + 1))
		var want := _palette_for(saved, score)
		var got := String(_theme.get("palette_id"))
		if got != want:
			return _fail("milestones: step %d palette %s want %s" % [step + 1, got, want])
		previous = now
	if int(_table.get("squishy_swap_count")) != MILESTONE_ROTATIONS:
		return _fail("milestones: swaps=%s" % _table.get("squishy_swap_count"))
	_cases_passed += 1
	print("SQUISHY_THEME_COMBO case milestones pass rotations=%d" % MILESTONE_ROTATIONS)
	return true


func _rotations(count: int) -> Array:
	if not await _restart():
		return []
	var sequence: Array = []
	var previous := _ids()
	for step in count:
		_game.add_score(5000)
		await _settle()
		var now := _ids()
		if int(_game.board_wave) != step + 1:
			_fail("rotations: wave=%s at step %d" % [_game.board_wave, step + 1])
			return []
		if not _all_changed(previous, now) or not _distinct(now):
			_fail("rotations: step %d ids %s -> %s" % [step + 1, previous, now])
			return []
		if not _same(now, _assigned()):
			_fail("rotations: step %d hosts %s assigned %s" % [step + 1, now, _assigned()])
			return []
		sequence.append(now)
		previous = now
	return sequence


func _palette_for(saved: String, score: int) -> String:
	var ids: PackedStringArray = _theme.palette_ids()
	var base := 0
	for i in ids.size():
		if ids[i] == saved:
			base = i
			break
	var steps := 0
	if score > 0:
		steps = int(floor(float(score) / 10000.0))
	if ids.is_empty():
		return saved
	return String(ids[(base + steps) % ids.size()])


func _restart() -> bool:
	_game.restart()
	await _settle()
	if int(_game.board_wave) != 0 or int(_game.score) != 0:
		_fail("restart left wave=%s score=%s" % [_game.board_wave, _game.score])
		return false
	return true


func _settle() -> void:
	for _i in 4:
		await process_frame


func _dismiss_title() -> bool:
	var title := current_scene.get_node_or_null("Title")
	if title == null:
		_fail("title missing")
		return false
	if title.has_method("_dismiss_title"):
		title._dismiss_title()
	else:
		title.visible = false
	if bool(title.visible):
		_fail("title still shown")
		return false
	return true


func _clear_seed_override() -> void:
	if _table.get("squishy_seed_override") != null:
		_table.set("squishy_seed_override", null)


func _assigned() -> Array:
	var raw: Variant = _table.get("_assigned_squishy_ids")
	var out: Array = []
	if raw is Array:
		for id in raw:
			out.append(String(id))
	return out


func _ids() -> Array:
	var out: Array = []
	for path in HOST_PATHS:
		var host := _table.get_node_or_null(path)
		var squishy := host.get_node_or_null("Squishy") if host != null else null
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


func _sequences_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same(a[i], b[i]):
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


func _fail(message: String) -> bool:
	push_error("SQUISHY_THEME_COMBO FAIL %s" % message)
	print("SQUISHY_THEME_COMBO FAIL %s" % message)
	quit(1)
	return false
