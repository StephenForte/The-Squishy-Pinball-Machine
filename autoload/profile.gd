extends Node

## Autoload Profile. Device id + player name, persisted at user://profile.save (D-027).

signal name_changed(name: String)

const SAVE_PATH := "user://profile.save"
const NAME_MAX_LEN := 16

var player_id: String = ""
var player_name: String = ""


func _ready() -> void:
	_load_or_create()


# D-027 name. Signature matches Node.set_name so the script compiles;
# the engine still uses the native node-name setter (native_method_override).
@warning_ignore("native_method_override")
func set_name(n: StringName) -> void:
	var cleaned := _sanitize_name(String(n))
	if cleaned == player_name:
		return
	player_name = cleaned
	_save()
	name_changed.emit(player_name)


func _load_or_create() -> void:
	if FileAccess.file_exists(SAVE_PATH) and _try_load():
		return
	player_id = _generate_uuid_v4()
	player_name = ""
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
	player_id = id
	player_name = _sanitize_name(String(data.get("player_name", "")))
	return true


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"player_id": player_id, "player_name": player_name}))


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
