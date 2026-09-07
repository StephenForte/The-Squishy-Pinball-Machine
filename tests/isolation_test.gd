extends SceneTree


func _initialize() -> void:
	var dir := OS.get_user_data_dir()
	if not dir.ends_with("SquishyPinballTest"):
		print("ISOLATION FAIL running against real user dir")
		quit(1)
		return
	print("ISOLATION PASS user_dir=%s" % dir)
	quit(0)
