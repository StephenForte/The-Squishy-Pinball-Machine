extends SceneTree

## Unit coverage for SquishyCatalog (D-020) and BallTraits (D-041).
## Does not load main.tscn. Restores the real ball-trait catalog before quit.

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

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("CATALOG start")
	if not _case_1_squishy_roster():
		return
	if not _case_2_squishy_lookups():
		return
	if not _case_3_ball_traits_happy():
		return
	if not _case_4_ball_traits_degrade():
		return
	print("CATALOG PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_squishy_roster() -> bool:
	print("CATALOG case 1 squishy roster")
	var data: Dictionary = SquishyCatalog.data()
	if data.is_empty():
		return _fail("case 1: catalog empty")
	if int(data.get("schema_version", 0)) != 1:
		return _fail("case 1: schema_version %s" % data.get("schema_version", ""))
	var entries: Array = data.get("squishies", [])
	if entries.size() != 16:
		return _fail("case 1: expected 16 squishies, got %d" % entries.size())
	var slots: Dictionary = SquishyCatalog.first_table_slots()
	if slots.size() != SLOT_EXPECT.size():
		return _fail("case 1: first_table_slots size %d" % slots.size())
	for key in SLOT_EXPECT.keys():
		if String(slots.get(key, "")) != String(SLOT_EXPECT[key]):
			return _fail("case 1: slot %s=%s want=%s" % [key, slots.get(key, ""), SLOT_EXPECT[key]])
	_cases_passed += 1
	print("CATALOG case 1 pass entries=16 slots=%d" % slots.size())
	return true


func _case_2_squishy_lookups() -> bool:
	print("CATALOG case 2 squishy lookups")
	var bear: Dictionary = SquishyCatalog.entry("bear_bounce")
	if bear.is_empty() or String(bear.get("id", "")) != "bear_bounce":
		return _fail("case 2: bear_bounce missing")
	if String(bear.get("display_name", "")) != "Bear Bounce":
		return _fail("case 2: display_name %s" % bear.get("display_name", ""))
	var sprite := SquishyCatalog.sprite_path("bear_bounce")
	if sprite != "res://assets/design/squishes/art/bear_bounce.png":
		return _fail("case 2: sprite_path %s" % sprite)
	if not FileAccess.file_exists(sprite):
		return _fail("case 2: sprite file missing at %s" % sprite)
	if not SquishyCatalog.entry("not_a_squishy").is_empty():
		return _fail("case 2: unknown id returned an entry")
	if SquishyCatalog.sprite_path("not_a_squishy") != "":
		return _fail("case 2: unknown id returned a sprite path")
	if SquishyCatalog.sprite_path("") != "":
		return _fail("case 2: empty id returned a sprite path")
	_cases_passed += 1
	print("CATALOG case 2 pass")
	return true


func _case_3_ball_traits_happy() -> bool:
	print("CATALOG case 3 ball traits")
	BallTraits.load_from()
	var ids := BallTraits.trait_ids()
	if ids.size() != 2 or String(ids[0]) != "rainbow" or String(ids[1]) != "turbo":
		return _fail("case 3: trait_ids %s" % [ids])
	var rainbow: Dictionary = BallTraits.entry("rainbow")
	if rainbow.is_empty() or String(rainbow.get("id", "")) != "rainbow":
		return _fail("case 3: rainbow missing")
	if not BallTraits.entry("not_a_trait").is_empty():
		return _fail("case 3: unknown trait returned an entry")
	var grants: Dictionary = BallTraits.grants("supercharge")
	if grants.get("all", []) != ["rainbow"] or grants.get("one", []) != ["turbo"]:
		return _fail("case 3: supercharge grants %s" % grants)
	if not BallTraits.grants("not_an_event").is_empty():
		return _fail("case 3: unknown event returned grants")
	if not BallTraits.grants("").is_empty():
		return _fail("case 3: empty event returned grants")
	_cases_passed += 1
	print("CATALOG case 3 pass ids=%s" % [ids])
	return true


func _case_4_ball_traits_degrade() -> bool:
	print("CATALOG case 4 ball traits degrade")
	var warnings_before := BallTraits.warning_count
	var bad_schema := "user://ball_traits_schema.json"
	if not _write_json(bad_schema, {"schema_version": 2, "traits": [{"id": "ghost"}]}):
		BallTraits.load_from()
		return _fail("case 4: could not write bad schema")
	BallTraits.load_from(bad_schema)
	if not BallTraits.trait_ids().is_empty():
		BallTraits.load_from()
		return _fail("case 4: schema_version 2 still listed traits")
	if BallTraits.warning_count != warnings_before + 1:
		BallTraits.load_from()
		return _fail("case 4: schema warnings=%d expected %d" % [BallTraits.warning_count, warnings_before + 1])

	var not_object := "user://ball_traits_array.json"
	if not _write_json(not_object, [{"id": "ghost"}]):
		BallTraits.load_from()
		return _fail("case 4: could not write array catalog")
	BallTraits.load_from(not_object)
	if not BallTraits.trait_ids().is_empty():
		BallTraits.load_from()
		return _fail("case 4: array catalog still listed traits")
	if BallTraits.warning_count != warnings_before + 2:
		BallTraits.load_from()
		return _fail("case 4: array warnings=%d expected %d" % [BallTraits.warning_count, warnings_before + 2])

	var bad_grants := "user://ball_traits_grants.json"
	if not _write_json(bad_grants, {"schema_version": 1, "traits": [{"id": "only"}], "grants": ["nope"]}):
		BallTraits.load_from()
		return _fail("case 4: could not write grants catalog")
	BallTraits.load_from(bad_grants)
	if BallTraits.trait_ids() != PackedStringArray(["only"]):
		BallTraits.load_from()
		return _fail("case 4: grants catalog ids %s" % [BallTraits.trait_ids()])
	if not BallTraits.grants("supercharge").is_empty():
		BallTraits.load_from()
		return _fail("case 4: non-dict grants still answered")

	BallTraits.load_from()
	if BallTraits.trait_ids().is_empty():
		return _fail("case 4: restore did not reload the real catalog")
	_cases_passed += 1
	print("CATALOG case 4 pass warnings=%d" % (BallTraits.warning_count - warnings_before))
	return true


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	return true


func _fail(message: String) -> bool:
	BallTraits.load_from()
	push_error("CATALOG FAIL %s" % message)
	print("CATALOG FAIL %s" % message)
	quit(1)
	return false
