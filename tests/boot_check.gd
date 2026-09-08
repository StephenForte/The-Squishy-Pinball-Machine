extends Node

## Real-boot regression autoload (D-030). Injected by tests/run_all.sh only —
## not registered in project.godot. Waits ≥60 process frames so deferred
## Theme applies finish, then asserts boot-time invariants and quits.
## Frame wait (not a 1 s timer) so `--quit-after 600` cannot win the race.

const UUID_RE := "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"


func _ready() -> void:
	await _run()


func _run() -> void:
	var tree := get_tree()
	if tree == null:
		await _finish(false, "no tree")
		return
	var frames := 0
	while frames < 60:
		await tree.process_frame
		frames += 1
		tree = get_tree()
		if tree == null:
			await _finish(false, "no tree during wait")
			return
	await _assert_boot()


func _assert_boot() -> void:
	var tree := get_tree()
	if tree == null:
		await _finish(false, "no tree after wait")
		return

	var theme := get_node_or_null("/root/Theme")
	if theme == null:
		await _finish(false, "Theme missing")
		return
	if String(theme.get("palette_id")).is_empty():
		await _finish(false, "Theme.palette_id empty")
		return

	var title := get_node_or_null("/root/Main/Title")
	if title == null:
		await _finish(false, "Main/Title missing")
		return
	if not title.visible:
		await _finish(false, "Main/Title not visible")
		return

	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		await _finish(false, "Profile missing")
		return
	var player_id := String(profile.get("player_id"))
	if not _is_uuid(player_id):
		await _finish(false, "Profile.player_id not a UUID")
		return

	var squishies: Array = tree.get_nodes_in_group("squishies")
	if squishies.is_empty():
		await _finish(false, "no squishies")
		return
	for node in squishies:
		var catalog_id := ""
		if "catalog_id" in node:
			catalog_id = String(node.catalog_id)
		if catalog_id.is_empty():
			await _finish(false, "squishy catalog_id empty")
			return
		var sprite: Node = node.get_node_or_null("Sprite")
		if sprite == null or not (sprite is Sprite2D):
			await _finish(false, "squishy %s missing Sprite" % catalog_id)
			return
		if (sprite as Sprite2D).texture == null:
			await _finish(false, "squishy %s tex=null" % catalog_id)
			return
	if squishies.size() != 8:
		await _finish(false, "squishies=%d expected 8" % squishies.size())
		return

	await _finish(true, "squishies=%d" % squishies.size())


func _is_uuid(value: String) -> bool:
	var re := RegEx.new()
	if re.compile(UUID_RE) != OK:
		return false
	return re.search(value) != null


func _finish(ok: bool, detail: String) -> void:
	if ok:
		print("BOOT PASS %s" % detail)
	else:
		print("BOOT FAIL %s" % detail)
	var tree := get_tree()
	if tree != null:
		await tree.process_frame
		tree.quit(0 if ok else 1)
	else:
		push_error("BOOT: no tree to quit")
