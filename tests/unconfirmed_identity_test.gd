extends SceneTree

## D-058. A device id the server does not know, under a name someone else holds,
## is unconfirmed until the person at the device says so. The run is not posted
## under that id. The "is this name held?" question goes through Leaderboard.lookup_name.

const PORT := 18794
const HANG_PORT := 18795
const VIEWPORT := Rect2(0, 0, 720, 1280)
const KEYBOARD_TOP := 640.0
const MIN_TOUCH := 64.0
const DAD_ID := "b8aa808f-6d01-439e-87be-664baf0ead85"
const NAT_ID := "c4c4c4c4-1111-4222-8333-555555555555"
const DEAD_ID := "d2432de0-149e-45d0-954d-c7c0a125f6ad"
const SOLO_ID := "abababab-1111-4222-8333-666666666666"

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _main: Node
var _server_pid: int = -1
var _hang_pid: int = -1
var _log_path: String = ""
var _offline_hits: int = 0
var _synced: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("UNCONFIRMED start")
	_profile = root.get_node_or_null("/root/Profile")
	_leaderboard = root.get_node_or_null("/root/Leaderboard")
	_game = root.get_node_or_null("/root/Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("Profile, Leaderboard, or Game missing")
		return
	if not _leaderboard.has_method("lookup_name") or not _leaderboard.has_signal("name_lookup"):
		_fail("lookup_name is not the single held-name question")
		return
	if not _leaderboard.offline.is_connected(_on_offline):
		_leaderboard.offline.connect(_on_offline)
	if _leaderboard.has_signal("profile_synced") and not _leaderboard.profile_synced.is_connected(_on_synced):
		_leaderboard.profile_synced.connect(_on_synced)
	_log_path = ProjectSettings.globalize_path("user://t40-unconfirmed.log")
	if not _start_server():
		return
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")
	if not await _seed_profile(DAD_ID, "Dad", "frog_gus"):
		return
	if not await _seed_profile(NAT_ID, "Natasha", "frog_gus"):
		return
	if not await _load_main():
		return

	if not await _state_unnamed():
		return
	if not await _state_typed_name_confirming():
		return
	if not await _case_boot_shows_dad():
		return
	if not await _case_thats_me_then_quiet_boot():
		return
	if not await _case_not_me_then_new_name():
		return
	if not await _case_unconfirmed_game_over_posts_once():
		return
	if not await _case_unnamed_save_disabled():
		return
	if not await _case_invite_held_name():
		return
	if not await _case_same_name_skips_confirm():
		return
	if not await _case_gap_fill_posts():
		return
	if not await _case_transport():
		return
	if not await _case_rename_keeps_its_field():
		return

	_cleanup()
	print("UNCONFIRMED PASS cases=%d" % _cases_passed)
	quit(0)


func _on_offline(_reason: String) -> void:
	_offline_hits += 1


func _on_synced(_profile_body: Dictionary) -> void:
	_synced = true


func _state_unnamed() -> bool:
	print("UNCONFIRMED state unnamed")
	_fresh_unnamed()
	_show_title()
	await process_frame
	await process_frame
	var title := _main.get_node_or_null("Title")
	var entry := title.get_node_or_null("NameEntry") as Control if title != null else null
	if title == null or not title.visible or entry == null or not entry.visible:
		return _fail("unnamed: name prompt is not up")
	if String(_profile.player_name) != "":
		return _fail("unnamed: name '%s'" % _profile.player_name)
	if not _assert_title(title, "unnamed"):
		return false
	print("UNCONFIRMED state unnamed overlap_count=0")
	return true


func _state_typed_name_confirming() -> bool:
	print("UNCONFIRMED state typed-name confirming")
	var title := _main.get_node_or_null("Title")
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	var no := title.get_node_or_null("NameEntry/NoButton") as Button
	if edit == null or welcome == null or no == null:
		return _fail("typed-name confirming: controls missing")
	var before_id := String(_profile.player_id)
	edit.text = "Natasha"
	edit.text_submitted.emit("Natasha")
	if not await _wait_welcome(welcome, "Natasha"):
		return _fail("typed-name confirming: welcome did not show ('%s')" % welcome.text)
	if String(_profile.player_id) != before_id or String(_profile.player_name) != "":
		return _fail("typed-name confirming: adopted before That's me")
	if not _assert_title(title, "typed-name confirming"):
		return false
	print("UNCONFIRMED state typed-name confirming overlap_count=0")
	no.pressed.emit()
	await process_frame
	await process_frame
	if welcome.visible:
		return _fail("typed-name confirming: Not me left the welcome up")
	if String(_profile.player_id) != before_id:
		return _fail("typed-name confirming: Not me changed the id")
	return true


func _case_boot_shows_dad() -> bool:
	print("UNCONFIRMED case 1 404 then 409")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	var pushes := int(_leaderboard._profile_push_count)
	_leaderboard._boot_restore_profile()
	var title := _main.get_node_or_null("Title")
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	var entry := title.get_node_or_null("NameEntry") as Control
	if not await _wait_welcome(welcome, "Dad"):
		return _fail("case 1: welcome '%s' visible=%s" % [welcome.text if welcome != null else "", welcome.visible if welcome != null else false])
	if not bool(_leaderboard.identity_unconfirmed):
		return _fail("case 1: identity was not marked unconfirmed")
	if String(_profile.player_id) != DEAD_ID or String(_profile.player_name) != "Dad":
		return _fail("case 1: adopted %s/%s" % [_profile.player_id, _profile.player_name])
	if int(_leaderboard._profile_push_count) != pushes + 1:
		return _fail("case 1: gap-fill PUTs %s → %s" % [pushes, _leaderboard._profile_push_count])
	if int(_leaderboard.refused_name_count) < 1:
		return _fail("case 1: 409 name_taken was not counted")
	if _post_count(DEAD_ID) != 0:
		return _fail("case 1: posted under the dead id")
	await process_frame
	if not _assert_title(title, "unconfirmed-confirming"):
		return false
	print("UNCONFIRMED state unconfirmed-confirming overlap_count=0 id=%s" % _profile.player_id)
	_cases_passed += 1
	print("UNCONFIRMED case 1 pass")
	return true


func _case_thats_me_then_quiet_boot() -> bool:
	print("UNCONFIRMED case 2 That's me, then a quiet boot")
	var title := _main.get_node_or_null("Title")
	var yes := title.get_node_or_null("NameEntry/YesButton") as Button
	if yes == null or not yes.visible:
		return _fail("case 2: That's me is not showing")
	var fetches := int(_leaderboard.best_fetch_count)
	var refused := int(_leaderboard.refused_name_count)
	yes.pressed.emit()
	if not await _wait_id(DAD_ID):
		return _fail("case 2: did not adopt Dad (id=%s)" % _profile.player_id)
	if String(_profile.player_name) != "Dad":
		return _fail("case 2: name '%s'" % _profile.player_name)
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 2: adoption left the identity unconfirmed")
	if int(_leaderboard.best_fetch_count) < fetches + 1:
		return _fail("case 2: best fetch %s → %s" % [fetches, _leaderboard.best_fetch_count])
	await process_frame
	await process_frame
	var entry := title.get_node_or_null("NameEntry") as Control
	if entry != null and entry.visible:
		return _fail("case 2: name prompt stayed up after adoption")
	if not _assert_title(title, "named-idle"):
		return false
	print("UNCONFIRMED state named-idle overlap_count=0")
	if not await _wait_http_idle():
		return _fail("case 2: requests still in flight before the second boot")
	var pushes := int(_leaderboard._profile_push_count)
	_synced = false
	_leaderboard._boot_restore_profile()
	if not await _wait_synced():
		return _fail("case 2: second boot did not read the profile")
	await process_frame
	await process_frame
	if int(_leaderboard._profile_push_count) != pushes:
		return _fail("case 2: second boot PUT %s → %s" % [pushes, _leaderboard._profile_push_count])
	if int(_leaderboard.refused_name_count) != refused:
		return _fail("case 2: second boot saw another 409 (%s → %s)" % [refused, _leaderboard.refused_name_count])
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 2: second boot became unconfirmed")
	_cases_passed += 1
	print("UNCONFIRMED case 2 pass puts=0 refused=%d best_fetch=%d" % [refused, _leaderboard.best_fetch_count])
	return true


func _case_not_me_then_new_name() -> bool:
	print("UNCONFIRMED case 3 Not me, then a new name")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	_leaderboard._boot_restore_profile()
	var title := _main.get_node_or_null("Title")
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	var no := title.get_node_or_null("NameEntry/NoButton") as Button
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	if not await _wait_welcome(welcome, "Dad"):
		return _fail("case 3: welcome did not return")
	no.pressed.emit()
	await process_frame
	await process_frame
	if welcome.visible or edit == null or not edit.visible:
		return _fail("case 3: Not me did not return to name entry")
	if String(_profile.player_id) != DEAD_ID:
		return _fail("case 3: Not me adopted")
	edit.text = "Pip"
	edit.text_submitted.emit("Pip")
	if not await _wait_name("Pip"):
		return _fail("case 3: new name did not resolve (name=%s id=%s)" % [_profile.player_name, _profile.player_id])
	if String(_profile.player_id) == DEAD_ID:
		return _fail("case 3: Pip kept the dead id")
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 3: a resolved new name stayed unconfirmed")
	_cases_passed += 1
	print("UNCONFIRMED case 3 pass id=%s" % _profile.player_id)
	return true


func _case_unconfirmed_game_over_posts_once() -> bool:
	print("UNCONFIRMED case 4 game over does not spend the dead id")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	_leaderboard._boot_restore_profile()
	var title := _main.get_node_or_null("Title")
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	if not await _wait_welcome(welcome, "Dad"):
		return _fail("case 4: not unconfirmed at boot")
	var dead_posts := _post_count(DEAD_ID)
	var dad_rows := await _score_total(DAD_ID)
	if not await _play_to_over():
		return false
	var panel := _main.get_node_or_null("GameOver")
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var save := panel.get_node_or_null("SaveButton") as Button
	var invite_welcome := panel.get_node_or_null("WelcomeLabel") as Label
	if edit == null or not edit.visible or edit.text != "Dad":
		return _fail("case 4: invite text '%s'" % (edit.text if edit != null else ""))
	if save == null or save.disabled:
		return _fail("case 4: Save is disabled on a pre-filled name")
	if invite_welcome != null and invite_welcome.visible:
		return _fail("case 4: pre-filled Dad asked for confirmation")
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 4: posted %d times under the dead id before Save" % _post_count(DEAD_ID))
	if not _assert_panel(panel, "unconfirmed invite"):
		return false
	print("UNCONFIRMED state unconfirmed invite overlap_count=0 prefill='%s'" % edit.text)
	var score := int(_game.score)
	save.pressed.emit()
	if not await _wait_id(DAD_ID):
		return _fail("case 4: Save did not adopt Dad (id=%s)" % _profile.player_id)
	if not await _wait_score_total(DAD_ID, dad_rows + 1):
		return _fail("case 4: server did not gain Dad's row")
	var rows: Dictionary = await _score_page(DAD_ID)
	if int(rows.get("total", -1)) != dad_rows + 1:
		return _fail("case 4: Dad rows %s want %d" % [rows.get("total", -1), dad_rows + 1])
	if not _page_has_score(rows, DAD_ID, score):
		return _fail("case 4: row missing score %d (%s)" % [score, rows])
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 4: POST /v1/scores under the dead id count %d" % _post_count(DEAD_ID))
	if _post_count(DAD_ID) != 1:
		return _fail("case 4: Dad posts %d want 1" % _post_count(DAD_ID))
	_cases_passed += 1
	print("UNCONFIRMED case 4 pass score=%d dead_posts=%d" % [score, dead_posts])
	return true


func _case_unnamed_save_disabled() -> bool:
	print("UNCONFIRMED case 5 unnamed invite, Save disabled while blank")
	_fresh_unnamed()
	if not await _back_to_title():
		return false
	if not await _play_to_over():
		return false
	var panel := _main.get_node_or_null("GameOver")
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var save := panel.get_node_or_null("SaveButton") as Button
	if edit == null or save == null:
		return _fail("case 5: invite missing")
	if edit.text != "" or not save.disabled:
		return _fail("case 5: blank field text='%s' disabled=%s" % [edit.text, save.disabled])
	_type(edit, "   ")
	if not save.disabled:
		return _fail("case 5: whitespace enabled Save")
	edit.text_submitted.emit("   ")
	await process_frame
	if String(_profile.player_name) != "" or _post_count(String(_profile.player_id)) != 0:
		return _fail("case 5: blank return committed")
	edit.release_focus()
	await process_frame
	await process_frame
	if String(_profile.player_name) != "":
		return _fail("case 5: blank blur committed")
	_type(edit, "Mo")
	if save.disabled:
		return _fail("case 5: a name left Save disabled")
	if not _assert_panel(panel, "unnamed invite"):
		return false
	print("UNCONFIRMED state unnamed invite overlap_count=0")
	edit.text = ""
	await process_frame
	var skip := panel.get_node_or_null("SkipButton") as Button
	if skip != null:
		skip.pressed.emit()
	_cases_passed += 1
	print("UNCONFIRMED case 5 pass")
	return true


func _case_invite_held_name() -> bool:
	print("UNCONFIRMED case 6 held name at the invite asks first")
	_fresh_unnamed()
	if not await _back_to_title():
		return false
	if not await _play_to_over():
		return false
	var panel := _main.get_node_or_null("GameOver")
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var save := panel.get_node_or_null("SaveButton") as Button
	var welcome := panel.get_node_or_null("WelcomeLabel") as Label
	var yes := panel.get_node_or_null("YesButton") as Button
	var no := panel.get_node_or_null("NoButton") as Button
	if edit == null or save == null or welcome == null or yes == null or no == null:
		return _fail("case 6: invite confirmation controls missing")
	var before_id := String(_profile.player_id)
	var nat_rows := await _score_total(NAT_ID)
	_type(edit, "Natasha")
	# Leave the field before the lookup returns, so showing the welcome does
	# not blur it. A stuck suppress flag would then swallow the later leave.
	if edit.has_focus():
		edit.release_focus()
		await process_frame
		await process_frame
	if not welcome.visible:
		save.pressed.emit()
	if not await _wait_welcome(welcome, "Natasha"):
		return _fail("case 6: welcome '%s'" % welcome.text)
	if String(_profile.player_id) != before_id or String(_profile.player_name) != "":
		return _fail("case 6: adopted before That's me")
	if await _score_total(NAT_ID) != nat_rows or _post_count(NAT_ID) != 0:
		return _fail("case 6: posted before That's me")
	if not _assert_panel(panel, "invite confirming"):
		return false
	print("UNCONFIRMED state invite confirming overlap_count=0")
	no.pressed.emit()
	await process_frame
	await process_frame
	if welcome.visible or not edit.visible or edit.text != "Natasha":
		return _fail("case 6: Not me left welcome=%s edit='%s'" % [welcome.visible, edit.text if edit != null else ""])
	if edit.editable == false:
		return _fail("case 6: Not me locked the field")
	if await _score_total(NAT_ID) != nat_rows:
		return _fail("case 6: Not me wrote a row")
	edit.grab_focus()
	await process_frame
	edit.release_focus()
	if not await _wait_welcome(welcome, "Natasha"):
		return _fail("case 6: blur after Not me did not ask again")
	var score := int(_game.score)
	yes.pressed.emit()
	if not await _wait_id(NAT_ID):
		return _fail("case 6: That's me id=%s" % _profile.player_id)
	if not await _wait_score_total(NAT_ID, nat_rows + 1):
		return _fail("case 6: Natasha's row did not land")
	var rows: Dictionary = await _score_page(NAT_ID)
	if int(rows.get("total", -1)) != nat_rows + 1 or not _page_has_score(rows, NAT_ID, score):
		return _fail("case 6: rows %s want one score %d" % [rows, score])
	if _post_count(NAT_ID) != 1:
		return _fail("case 6: Natasha posts %d want 1" % _post_count(NAT_ID))
	_cases_passed += 1
	print("UNCONFIRMED case 6 pass score=%d" % score)
	return true


func _case_same_name_skips_confirm() -> bool:
	print("UNCONFIRMED case 7 typed dad is the last player")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	_leaderboard._boot_restore_profile()
	var boot_welcome := _main.get_node_or_null("Title/NameEntry/WelcomeLabel") as Label
	if not await _wait_welcome(boot_welcome, "Dad"):
		return _fail("case 7: boot confirmation missing")
	var dad_rows := await _score_total(DAD_ID)
	var dad_posts := _post_count(DAD_ID)
	if not await _play_to_over():
		return false
	var panel := _main.get_node_or_null("GameOver")
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var save := panel.get_node_or_null("SaveButton") as Button
	var welcome := panel.get_node_or_null("WelcomeLabel") as Label
	if edit == null or edit.text != "Dad":
		return _fail("case 7: prefill '%s'" % (edit.text if edit != null else ""))
	_type(edit, "dad")
	save.pressed.emit()
	await process_frame
	await process_frame
	if welcome != null and welcome.visible:
		return _fail("case 7: same name asked welcome back")
	if not await _wait_id(DAD_ID):
		return _fail("case 7: did not adopt (id=%s name=%s)" % [_profile.player_id, _profile.player_name])
	if welcome != null and welcome.visible:
		return _fail("case 7: welcome appeared after adopt")
	var score := int(_game.score)
	if not await _wait_score_total(DAD_ID, dad_rows + 1):
		return _fail("case 7: score did not land")
	if _post_count(DAD_ID) != dad_posts + 1:
		return _fail("case 7: posts %s → %s" % [dad_posts, _post_count(DAD_ID)])
	var rows: Dictionary = await _score_page(DAD_ID)
	if not _page_has_score(rows, DAD_ID, score):
		return _fail("case 7: row %s missing %d" % [rows, score])
	_cases_passed += 1
	print("UNCONFIRMED case 7 pass")
	return true


func _case_gap_fill_posts() -> bool:
	print("UNCONFIRMED case 8 gap-fill stays a normal boot")
	_plant(SOLO_ID, "Solo", "frog_gus")
	_show_title()
	await process_frame
	var pushes := int(_leaderboard._profile_push_count)
	var refused := int(_leaderboard.refused_name_count)
	_leaderboard._boot_restore_profile()
	if not await _wait_http_idle():
		return _fail("case 8: boot requests did not finish")
	if int(_leaderboard._profile_push_count) != pushes + 1:
		return _fail("case 8: PUTs %s → %s" % [pushes, _leaderboard._profile_push_count])
	if int(_leaderboard.refused_name_count) != refused:
		return _fail("case 8: gap-fill was refused")
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: a free name became unconfirmed")
	if String(_profile.player_id) != SOLO_ID or String(_profile.player_name) != "Solo":
		return _fail("case 8: identity changed to %s/%s" % [_profile.player_id, _profile.player_name])
	var welcome := _main.get_node_or_null("Title/NameEntry/WelcomeLabel") as Label
	if welcome != null and welcome.is_visible_in_tree():
		return _fail("case 8: gap-fill showed a confirmation")
	var cloud: Dictionary = await _http_json(HTTPClient.METHOD_GET, "/v1/profile?player_id=%s" % SOLO_ID, "", false)
	if int(cloud.get("code", 0)) != 200 or String(cloud.get("text", "")).find("Solo") < 0:
		return _fail("case 8: cloud profile %s %s" % [cloud.get("code", 0), cloud.get("text", "")])
	if not await _play_to_over():
		return false
	var panel := _main.get_node_or_null("GameOver")
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	if edit != null and edit.visible:
		return _fail("case 8: a confirmed player got the invite")
	if not _assert_panel(panel, "named"):
		return false
	print("UNCONFIRMED state named overlap_count=0")
	var score := int(_game.score)
	if not await _wait_score_total(SOLO_ID, 1):
		return _fail("case 8: Solo's run did not post")
	var rows: Dictionary = await _score_page(SOLO_ID)
	if int(rows.get("total", -1)) != 1 or not _page_has_score(rows, SOLO_ID, score):
		return _fail("case 8: rows %s want score %d" % [rows, score])
	if _post_count(SOLO_ID) != 1:
		return _fail("case 8: posts %d want 1" % _post_count(SOLO_ID))
	_cases_passed += 1
	print("UNCONFIRMED case 8 pass score=%d" % score)
	return true


func _case_transport() -> bool:
	print("UNCONFIRMED case 9 transport failure changes nothing")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	if not await _wait_http_idle():
		return _fail("case 9: requests still in flight")
	var offline_before := _offline_hits
	var top_before := _label_text("Title/TopFiveLabel")
	var over_before := _label_text("GameOver/OfflineLabel")
	var pushes := int(_leaderboard._profile_push_count)
	var refused := int(_leaderboard.refused_name_count)
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:9")
	_leaderboard._boot_restore_profile()
	if not await _wait_http_idle():
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 9: GET failure did not settle")
	if bool(_leaderboard.identity_unconfirmed):
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 9: GET failure marked unconfirmed")
	if int(_leaderboard._profile_push_count) != pushes:
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 9: GET failure PUT %s → %s" % [pushes, _leaderboard._profile_push_count])
	if not _offline_unchanged(offline_before, top_before, over_before):
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return false
	if not _start_hang_server():
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 9: hang server did not spawn")
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % HANG_PORT)
	offline_before = _offline_hits
	top_before = _label_text("Title/TopFiveLabel")
	over_before = _label_text("GameOver/OfflineLabel")
	pushes = int(_leaderboard._profile_push_count)
	_leaderboard._boot_restore_profile()
	if not await _wait_http_idle_long():
		_stop_hang_server()
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 9: PUT failure did not settle")
	_stop_hang_server()
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 9: PUT failure marked unconfirmed")
	if int(_leaderboard._profile_push_count) != pushes + 1:
		return _fail("case 9: PUT was not sent %s → %s" % [pushes, _leaderboard._profile_push_count])
	if int(_leaderboard.refused_name_count) != refused:
		return _fail("case 9: PUT failure counted as name_taken")
	if not _offline_unchanged(offline_before, top_before, over_before):
		return false
	if String(_profile.player_id) != DEAD_ID or String(_profile.player_name) != "Dad":
		return _fail("case 9: transport changed identity")
	_cases_passed += 1
	print("UNCONFIRMED case 9 pass")
	return true


func _case_rename_keeps_its_field() -> bool:
	print("UNCONFIRMED case 10 409 during rename does not replace it")
	_plant(DEAD_ID, "Dad", "frog_gus")
	_show_title()
	await process_frame
	await process_frame
	var title := _main.get_node_or_null("Title")
	var entry := title.get_node_or_null("NameEntry") as Control
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	if entry == null or not entry.has_method("open"):
		return _fail("case 10: NameEntry missing")
	entry.call("open", false)
	await process_frame
	if not entry.visible or edit == null or not edit.visible or (welcome != null and welcome.visible):
		return _fail("case 10: rename did not open the field")
	if not _assert_title(title, "renaming"):
		return false
	print("UNCONFIRMED state renaming overlap_count=0")
	var refused := int(_leaderboard.refused_name_count)
	_leaderboard._boot_restore_profile()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000 and not bool(_leaderboard.identity_unconfirmed):
		await process_frame
	if not bool(_leaderboard.identity_unconfirmed):
		return _fail("case 10: 409 did not mark unconfirmed (refused %s → %s)" % [refused, _leaderboard.refused_name_count])
	await process_frame
	await process_frame
	if not entry.visible or not edit.visible or (welcome != null and welcome.visible):
		return _fail("case 10: 409 replaced the rename field")
	if String(_profile.player_id) != DEAD_ID:
		return _fail("case 10: id changed to %s" % _profile.player_id)
	if not _assert_title(title, "renaming-after-409"):
		return false
	_cases_passed += 1
	print("UNCONFIRMED case 10 pass")
	return true


func _offline_unchanged(offline_before: int, top_before: String, over_before: String) -> bool:
	if _offline_hits != offline_before:
		_fail("case 9: offline signal %d → %d" % [offline_before, _offline_hits])
		return false
	if _label_text("Title/TopFiveLabel") != top_before:
		_fail("case 9: title offline text changed")
		return false
	if _label_text("GameOver/OfflineLabel") != over_before:
		_fail("case 9: game-over offline text changed")
		return false
	return true


func _assert_title(title: Node, label: String) -> bool:
	var kids := _visible_controls(title)
	if not _assert_no_overlap(kids, label):
		return false
	var hud := _hud_score_row()
	for node in kids:
		var shared: Rect2 = (node as Control).get_global_rect().intersection(hud)
		if shared.get_area() > 0.5:
			return _fail("%s: %s intersects the HUD score row %s" % [label, node.name, hud])
	return _assert_interactive(title, label)


func _assert_panel(panel: Node, label: String) -> bool:
	var kids: Array = []
	for child in panel.get_children():
		if not (child is Control):
			continue
		var node := child as Control
		if node.name == "Shade":
			continue
		if not node.visible or not node.is_visible_in_tree():
			continue
		kids.append(node)
	if not _assert_no_overlap(kids, label):
		return false
	return _assert_interactive(panel, label)


## The score header's authored boxes meet on a pixel, and the label's real
## rect is a few pixels taller than that box. That seam is pre-existing and
## this task may not move those nodes. Every other pair, including every
## invite control against the header, still fails the check.
const _HEADER_SEAM := {
	"TitleLabel": true,
	"FinalScoreLabel": true,
	"GameOverHighScoreLabel": true,
	"NewHighScoreLabel": true,
	"YourRankLabel": true,
	"OfflineLabel": true,
}


func _assert_no_overlap(kids: Array, label: String) -> bool:
	var overlap := 0
	for i in kids.size():
		var rect: Rect2 = (kids[i] as Control).get_global_rect()
		print("UNCONFIRMED layout %s %s %s" % [label, kids[i].name, rect])
		for j in range(i + 1, kids.size()):
			var shared: Rect2 = rect.intersection((kids[j] as Control).get_global_rect())
			if shared.get_area() <= 0.5:
				continue
			var left_name := String(kids[i].name)
			var right_name := String(kids[j].name)
			if _HEADER_SEAM.has(left_name) and _HEADER_SEAM.has(right_name):
				continue
			overlap += 1
			return _fail("%s: %s %s overlaps %s %s" % [label, left_name, rect, right_name, (kids[j] as Control).get_global_rect()])
	print("UNCONFIRMED layout %s overlap_count=%d visible=%d" % [label, overlap, kids.size()])
	return true


func _visible_controls(parent: Node) -> Array:
	var kids: Array = []
	for child in parent.get_children():
		if not (child is Control):
			continue
		var node := child as Control
		if node.name == "Shade":
			continue
		if not node.visible or not node.is_visible_in_tree():
			continue
		kids.append(node)
	return kids


func _hud_score_row() -> Rect2:
	var hud := _main.get_node_or_null("HUD")
	var merged := Rect2()
	var any := false
	if hud == null:
		return merged
	for node_name in ["ScoreLabel", "BallsLabel", "HighScoreLabel"]:
		var label := hud.get_node_or_null(node_name) as Control
		if label == null or not label.visible:
			continue
		var rect := label.get_global_rect()
		merged = rect if not any else merged.merge(rect)
		any = true
	return merged


func _assert_interactive(node: Node, label: String) -> bool:
	return _walk_interactive(node, label)


func _walk_interactive(node: Node, label: String) -> bool:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return true
	if node is Button or node is LineEdit:
		var rect: Rect2 = (node as Control).get_global_rect()
		var smaller := minf(rect.size.x, rect.size.y)
		if smaller < MIN_TOUCH:
			return _fail("%s: %s smaller side %.1f < 64 %s" % [label, node.name, smaller, rect])
		if not VIEWPORT.encloses(rect):
			return _fail("%s: %s %s outside the viewport" % [label, node.name, rect])
		if node is LineEdit and rect.position.y + rect.size.y > KEYBOARD_TOP:
			return _fail("%s: %s %s is not entirely above y=640" % [label, node.name, rect])
	for child in node.get_children():
		if not _walk_interactive(child, label):
			return false
	return true


## Assigning LineEdit.text does not emit text_changed in Godot 4.7. A real
## keystroke does. Set the text, then emit, so Save follows the typing path.
func _type(edit: LineEdit, value: String) -> void:
	edit.text = value
	edit.text_changed.emit(value)


func _show_title() -> void:
	var title := _main.get_node_or_null("Title")
	if title != null and title.has_method("show_menu"):
		title.show_menu()


func _back_to_title() -> bool:
	if _main != null and _main.has_method("return_to_menu"):
		_main.return_to_menu()
	else:
		_game.restart()
		_show_title()
	for _i in 6:
		await process_frame
	var title := _main.get_node_or_null("Title")
	if title == null or not title.visible:
		return _fail("title did not return")
	return true


func _play_to_over() -> bool:
	if _game.state == _game.GAME_OVER:
		_game.restart()
		for _i in 4:
			await process_frame
	var title := _main.get_node_or_null("Title")
	if title != null and title.visible:
		var play := title.get_node_or_null("PlayButton") as Button
		if play == null:
			return _fail("Play missing")
		play.pressed.emit()
		for _i in 8:
			await process_frame
		if title.visible:
			return _fail("could not leave the title")
	_game.add_score(9000)
	for _i in 3:
		_game.on_ball_drained()
		await physics_frame
		await process_frame
	var panel := _main.get_node_or_null("GameOver")
	if panel == null or not panel.visible or _game.state != _game.GAME_OVER:
		return _fail("expected GAME_OVER")
	return true


func _plant(player_id: String, player_name: String, avatar: String) -> void:
	_profile.player_id = player_id
	_profile.player_name = player_name
	_profile.players = {player_name.to_lower(): player_id}
	_profile.avatar_id = avatar
	_profile.avatars = {player_name.to_lower(): avatar}
	_profile._save()


func _fresh_unnamed() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	_profile._load_or_create()


func _post_count(player_id: String) -> int:
	var want := player_id.to_lower()
	var n := 0
	for id in _leaderboard.score_post_ids:
		if String(id).to_lower() == want:
			n += 1
	return n


func _wait_welcome(welcome: Label, name_part: String) -> bool:
	if welcome == null:
		return false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if welcome.visible and welcome.text.find(name_part) >= 0:
			return true
		await process_frame
	return welcome.visible and welcome.text.find(name_part) >= 0


func _wait_id(player_id: String) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if String(_profile.player_id) == player_id:
			return true
		await process_frame
	return String(_profile.player_id) == player_id


func _wait_name(player_name: String) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if String(_profile.player_name) == player_name:
			return true
		await process_frame
	return String(_profile.player_name) == player_name


func _wait_synced() -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if _synced:
			return true
		await process_frame
	return _synced


func _wait_http_idle() -> bool:
	return await _wait_http_idle_for(2000)


func _wait_http_idle_long() -> bool:
	return await _wait_http_idle_for(5000)


func _wait_http_idle_for(ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if _http_nodes() == 0:
			await process_frame
			return _http_nodes() == 0
		await process_frame
	return _http_nodes() == 0


func _http_nodes() -> int:
	var n := 0
	for child in _leaderboard.get_children():
		if child is HTTPRequest:
			n += 1
	return n


func _wait_score_total(player_id: String, want: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if await _score_total(player_id) >= want:
			return true
		await process_frame
	return await _score_total(player_id) >= want


func _score_total(player_id: String) -> int:
	var page := await _score_page(player_id)
	return int(page.get("total", -1))


func _score_page(player_id: String) -> Dictionary:
	var got := await _http_json(HTTPClient.METHOD_GET, "/v1/admin/scores?player_id=%s&limit=50" % player_id, "", false, true)
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"total": -1, "rows": [], "code": int(got.get("code", 0))}
	var data: Dictionary = parsed
	data["code"] = int(got.get("code", 0))
	return data


func _page_has_score(page: Dictionary, player_id: String, score: int) -> bool:
	var rows: Variant = page.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return false
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if String(row.get("player_id", "")).to_lower() == player_id.to_lower() and int(row.get("score", -1)) == score:
			return true
	return false


func _seed_profile(player_id: String, player_name: String, avatar: String) -> bool:
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"avatar": avatar,
		"client": "squish/1.0",
	})
	var got := await _http_json(HTTPClient.METHOD_PUT, "/v1/profile", body, true)
	if int(got.get("code", 0)) != 200:
		_fail("seed %s failed %s %s" % [player_name, got.get("code", 0), got.get("text", "")])
		return false
	return true


func _http_json(method: int, path: String, body: String, with_key: bool, admin: bool = false) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	root.add_child(http)
	var done := {"got": false, "code": 0, "text": ""}
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, res_body: PackedByteArray) -> void:
		done.got = true
		done.code = code
		done.text = res_body.get_string_from_utf8()
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if with_key:
		headers.append("X-Squish-Key: devkey")
	if admin:
		headers.append("X-Squish-Admin: dev-admin")
	var err := http.request("http://127.0.0.1:%d%s" % [PORT, path], headers, method, body)
	if err != OK:
		http.queue_free()
		return {"code": 0, "text": ""}
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if bool(done.got):
			break
		await process_frame
	var code := int(done.code)
	var text := String(done.text)
	http.queue_free()
	return {"code": code, "text": text}


func _label_text(path: String) -> String:
	var label := _main.get_node_or_null(path) as Label if _main != null else null
	if label == null:
		return ""
	return label.text


func _load_main() -> bool:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK:
		_fail("could not load main.tscn")
		return false
	for _i in 4:
		await process_frame
	_main = current_scene
	if _main == null:
		_fail("main scene did not load")
		return false
	var table := _main.get_node_or_null("Table")
	if table != null:
		var drain := table.get_node_or_null("Drain")
		if drain != null and drain is Area2D:
			(drain as Area2D).monitoring = false
	return true


func _start_server() -> bool:
	_free_port(PORT)
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH=:memory: SQUISH_KEY=devkey SQUISH_ADMIN_KEY=dev-admin PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _server_pid <= 0:
		_fail("server did not spawn")
		return false
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	_fail("server did not become healthy")
	return false


func _start_hang_server() -> bool:
	_free_port(HANG_PORT)
	var js := "require('http').createServer((q,s)=>{if(q.method==='PUT')return;s.writeHead(404,{'Content-Type':'application/json'});s.end('{\\\"error\\\":\\\"unknown_profile\\\"}');}).listen(%d)" % HANG_PORT
	var cmd := "exec node -e \"%s\"" % js
	_hang_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _hang_pid <= 0:
		return false
	OS.delay_msec(200)
	return true


func _stop_hang_server() -> void:
	if _hang_pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_hang_pid)])
		OS.execute("/bin/kill", ["-KILL", str(_hang_pid)])
		_hang_pid = -1
	_free_port(HANG_PORT)


func _free_port(port: int) -> void:
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; sleep 0.2; kill -9 $pids 2>/dev/null || true; fi" % port])


func _cleanup() -> void:
	_stop_hang_server()
	if _server_pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_server_pid)])
		OS.execute("/bin/kill", ["-KILL", str(_server_pid)])
		_server_pid = -1
	_free_port(PORT)
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _fail(message: String) -> bool:
	push_error("UNCONFIRMED FAIL %s" % message)
	print("UNCONFIRMED FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
