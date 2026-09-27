extends SceneTree

## adopt_identity is still the landing point for a claimed name (D-053).
## These cases are the part of the old transfer suite that describes real
## behaviour: an adopt overwrites the local mapping, a rejected adopt leaves
## state untouched, and the adopted id survives a reload.
## The transfer-code UI and restore HTTP cases are gone with that feature.

const SAVE_PATH := "user://profile.save"
const CLOUD_ID := "6a7a41f5-0000-4000-8000-000000000001"
const OTHER_ID := "b8aa808f-0000-4000-8000-000000000002"

var _cases_passed: int = 0
var _profile: Node
var _name_changed_count: int = 0
var _avatar_changed_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("TRANSFER start")
	_profile = root.get_node_or_null("Profile")
	if _profile == null:
		_fail("Profile autoload missing")
		return
	if not _profile.has_method("adopt_identity"):
		_fail("Profile.adopt_identity missing")
		return
	if not _profile.name_changed.is_connected(_on_name_changed):
		_profile.name_changed.connect(_on_name_changed)
	if not _profile.avatar_changed.is_connected(_on_avatar_changed):
		_profile.avatar_changed.connect(_on_avatar_changed)

	if not _case_1_overwrite_existing_mapping():
		return
	if not _case_2_reject_leaves_untouched():
		return
	if not _case_3_round_trip_survives_reload():
		return

	print("TRANSFER PASS cases=%d" % _cases_passed)
	quit(0)


func _on_name_changed(_name: String) -> void:
	_name_changed_count += 1


func _on_avatar_changed(_avatar_id: String) -> void:
	_avatar_changed_count += 1


func _case_1_overwrite_existing_mapping() -> bool:
	print("TRANSFER case 1 overwrite existing players[key]")
	_profile.call("set_name", "Dad")
	var local_id := String(_profile.player_id)
	if not _is_uuid_v4(local_id):
		return _fail("case 1: local Dad id is not UUID v4: %s" % local_id)
	if String(_profile.players.get("dad", "")) != local_id:
		return _fail("case 1: players[dad] should be %s" % local_id)
	_name_changed_count = 0
	_avatar_changed_count = 0
	if not bool(_profile.adopt_identity(CLOUD_ID, "Dad", "bear_bounce")):
		return _fail("case 1: adopt_identity should succeed")
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 1: player_id %s want %s" % [_profile.player_id, CLOUD_ID])
	if String(_profile.player_name) != "Dad":
		return _fail("case 1: name %s want Dad" % _profile.player_name)
	if String(_profile.players.get("dad", "")) != CLOUD_ID:
		return _fail("case 1: players[dad] was not overwritten, got %s" % _profile.players.get("dad", ""))
	if String(_profile.players.get("dad", "")) == local_id:
		return _fail("case 1: previous local id was kept")
	if String(_profile.avatar_id) != "bear_bounce":
		return _fail("case 1: avatar_id %s want bear_bounce" % _profile.avatar_id)
	if String(_profile.avatars.get("dad", "")) != "bear_bounce":
		return _fail("case 1: avatars[dad] %s want bear_bounce" % _profile.avatars.get("dad", ""))
	if _name_changed_count < 1 or _avatar_changed_count < 1:
		return _fail("case 1: expected name_changed and avatar_changed")
	_cases_passed += 1
	print("TRANSFER case 1 pass")
	return true


func _case_2_reject_leaves_untouched() -> bool:
	print("TRANSFER case 2 rejected adopt leaves state")
	if not bool(_profile.adopt_identity(OTHER_ID, "Dad", "frog_gus")):
		return _fail("case 2: setup adopt failed")
	var before_id := String(_profile.player_id)
	var before_name := String(_profile.player_name)
	var before_players: Dictionary = _profile.players.duplicate(true)
	var before_avatars: Dictionary = _profile.avatars.duplicate(true)
	_name_changed_count = 0
	_avatar_changed_count = 0
	if bool(_profile.adopt_identity("not-a-uuid", "Dad", "bear_bounce")):
		return _fail("case 2: bad uuid should be rejected")
	if bool(_profile.adopt_identity(CLOUD_ID, "   ", "bear_bounce")):
		return _fail("case 2: whitespace name should be rejected")
	if bool(_profile.adopt_identity(CLOUD_ID, "", "bear_bounce")):
		return _fail("case 2: empty name should be rejected")
	if String(_profile.player_id) != before_id:
		return _fail("case 2: player_id changed on reject: %s" % _profile.player_id)
	if String(_profile.player_name) != before_name:
		return _fail("case 2: player_name changed on reject")
	if _dict_string(_profile.players) != _dict_string(before_players):
		return _fail("case 2: players changed on reject")
	if _dict_string(_profile.avatars) != _dict_string(before_avatars):
		return _fail("case 2: avatars changed on reject")
	if _name_changed_count != 0 or _avatar_changed_count != 0:
		return _fail("case 2: reject emitted signals")
	_cases_passed += 1
	print("TRANSFER case 2 pass")
	return true


func _case_3_round_trip_survives_reload() -> bool:
	print("TRANSFER case 3 round trip reload")
	if not bool(_profile.adopt_identity(CLOUD_ID, "Dad", "bear_bounce")):
		return _fail("case 3: adopt failed")
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 3: adopt did not set id")
	_profile._load_or_create()
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 3: reload dropped id, got %s" % _profile.player_id)
	if String(_profile.player_name) != "Dad":
		return _fail("case 3: reload dropped name, got %s" % _profile.player_name)
	if String(_profile.players.get("dad", "")) != CLOUD_ID:
		return _fail("case 3: reload dropped players[dad]")
	var disk := _read_profile_save()
	if String(disk.get("player_id", "")) != CLOUD_ID:
		return _fail("case 3: profile.save player_id %s want %s" % [disk.get("player_id", ""), CLOUD_ID])
	_cases_passed += 1
	print("TRANSFER case 3 pass")
	return true


func _read_profile_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _dict_string(value: Dictionary) -> String:
	return JSON.stringify(value)


func _is_uuid_v4(value: String) -> bool:
	var re := RegEx.new()
	if re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$") != OK:
		return false
	return re.search(value) != null


func _fail(message: String) -> bool:
	push_error("TRANSFER FAIL %s" % message)
	print("TRANSFER FAIL %s" % message)
	quit(1)
	return false
