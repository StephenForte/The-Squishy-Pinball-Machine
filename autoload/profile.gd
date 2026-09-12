extends Node

## Autoload Profile. Per-name identity on this device (D-031).
## players: sanitised-lowercase name → UUID v4. player_id follows player_name.

signal name_changed(name: String)
signal avatar_changed(avatar_id: String)

const SAVE_PATH := "user://profile.save"
const NAME_MAX_LEN := 16

var player_id: String = ""
var player_name: String = ""
var players: Dictionary = {}
var avatar_id: String = ""
var avatars: Dictionary = {}


func _ready() -> void:
	_load_or_create()


# D-027 name. Signature matches Node.set_name so the script compiles;
# the engine still uses the native node-name setter (native_method_override).
@warning_ignore("native_method_override")
func set_name(n: StringName) -> void:
	var cleaned := _sanitize_name(String(n))
	var key := _name_key(cleaned)
	if key == _name_key(player_name):
		return
	var previous_avatar := avatar_id
	if cleaned.is_empty():
		player_name = ""
		avatar_id = ""
		_save()
		name_changed.emit(player_name)
		if previous_avatar != avatar_id:
			avatar_changed.emit(avatar_id)
		return
	if players.has(key) and _is_uuid_v4(String(players[key])):
		player_id = String(players[key])
	elif _is_uuid_v4(player_id) and not _id_is_claimed(player_id):
		players[key] = player_id
	else:
		player_id = _generate_uuid_v4()
		players[key] = player_id
	player_name = cleaned
	avatar_id = _avatar_for_key(key)
	_save()
	name_changed.emit(player_name)
	if previous_avatar != avatar_id:
		avatar_changed.emit(avatar_id)


func _load_or_create() -> void:
	if FileAccess.file_exists(SAVE_PATH) and _try_load():
		return
	player_id = _generate_uuid_v4()
	player_name = ""
	players = {}
	avatar_id = ""
	avatars = {}
	_save()


func _try_load() -> bool:
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	var id := String(data.get("player_id", ""))
	if not _is_uuid_v4(id):
		return false
	var loaded_name := _sanitize_name(String(data.get("player_name", "")))
	var loaded_players := _parse_players(data.get("players", {}))
	var loaded_avatars := _parse_avatars(data.get("avatars", {}))
	var migrated := not data.has("players") or not data.has("avatars")
	if loaded_players.is_empty() and not loaded_name.is_empty():
		loaded_players[_name_key(loaded_name)] = id
		migrated = true
	player_id = id
	player_name = loaded_name
	players = loaded_players
	avatars = loaded_avatars
	if not player_name.is_empty():
		var key := _name_key(player_name)
		if players.has(key) and _is_uuid_v4(String(players[key])):
			player_id = String(players[key])
		avatar_id = _avatar_for_key(key)
	else:
		avatar_id = ""
	if migrated:
		_save()
	return true


func set_avatar(id: String) -> bool:
	if not _is_catalog_avatar(id):
		return false
	var key := _name_key(player_name)
	if avatar_id == id and (key.is_empty() or String(avatars.get(key, "")) == id):
		return true
	avatar_id = id
	if not key.is_empty():
		avatars[key] = id
	_save()
	avatar_changed.emit(avatar_id)
	return true


func _avatar_for_key(key: String) -> String:
	var id := String(avatars.get(key, ""))
	if not _is_catalog_avatar(id):
		return ""
	return id


func _is_catalog_avatar(id: String) -> bool:
	if id.is_empty():
		return false
	return not SquishyCatalog.entry(id).is_empty()


func _parse_avatars(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var src: Dictionary = raw
	for key_variant in src.keys():
		var key := _name_key(_sanitize_name(String(key_variant)))
		var value := String(src[key_variant])
		if key.is_empty() or value.is_empty():
			continue
		out[key] = value
	return out


func _parse_players(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var src: Dictionary = raw
	for key_variant in src.keys():
		var key := _name_key(_sanitize_name(String(key_variant)))
		var value := String(src[key_variant])
		if key.is_empty() or not _is_uuid_v4(value):
			continue
		out[key] = value
	return out


func _id_is_claimed(id: String) -> bool:
	for key in players:
		if String(players[key]) == id:
			return true
	return false


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"player_id": player_id,
		"player_name": player_name,
		"players": players,
		"avatars": avatars,
	}))


func _name_key(n: String) -> String:
	return n.to_lower()


func _sanitize_name(n: String) -> String:
	# D-026: strip control chars, collapse whitespace, trim, ≤16 characters.
	var stripped := ""
	for i in n.length():
		var code := n.unicode_at(i)
		if code < 32 or code == 127:
			continue
		stripped += String.chr(code)
	var collapsed := ""
	var pending_space := false
	for i in stripped.length():
		var code := stripped.unicode_at(i)
		if code == 32 or code == 160:
			if not collapsed.is_empty():
				pending_space = true
			continue
		if pending_space:
			collapsed += " "
			pending_space = false
		collapsed += String.chr(code)
	if collapsed.length() > NAME_MAX_LEN:
		collapsed = collapsed.substr(0, NAME_MAX_LEN)
	return collapsed


func _generate_uuid_v4() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		bytes[0], bytes[1], bytes[2], bytes[3],
		bytes[4], bytes[5], bytes[6], bytes[7],
		bytes[8], bytes[9], bytes[10], bytes[11],
		bytes[12], bytes[13], bytes[14], bytes[15],
	]


func _is_uuid_v4(value: String) -> bool:
	var re := RegEx.new()
	if re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$") != OK:
		return false
	return re.search(value) != null
