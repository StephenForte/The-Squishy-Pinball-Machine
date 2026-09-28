extends SceneTree

## D-059. lookup_name asks GET /v1/players/lookup and does not claim.
## A free name stays free. A held name comes back with the server's display.
## Names that are special in a query string round-trip unchanged. A 404
## (an older server) is unanswered, so callers fall back to the claim.

const PORT := 18797
const PROXY_PORT := 18798
const STUB_PORT := 18799

var _cases_passed: int = 0
var _leaderboard: Node
var _server_pid: int = -1
var _proxy_pid: int = -1
var _stub_pid: int = -1
var _log_path: String = ""
var _proxy_lookups: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("NAME_LOOKUP start")
	_leaderboard = root.get_node_or_null("/root/Leaderboard")
	if _leaderboard == null or not _leaderboard.has_method("lookup_name"):
		_fail("Leaderboard.lookup_name missing")
		return
	if not _leaderboard.has_signal("name_lookup"):
		_fail("name_lookup signal missing")
		return
	_log_path = ProjectSettings.globalize_path("user://t41-name-lookup.log")
	if not _start_server():
		return
	if not _start_proxy():
		return
	if not _start_stub():
		return
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PROXY_PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")

	if not await _case_free():
		return
	if not await _case_held_display():
		return
	if not await _case_encoded_names():
		return
	if not await _case_not_found():
		return
	if not await _case_no_resolve_post():
		return

	_cleanup()
	print("NAME_LOOKUP PASS cases=%d" % _cases_passed)
	quit(0)


func _case_free() -> bool:
	print("NAME_LOOKUP case free")
	var before := await _score_total()
	var info := await _ask("T41 Free", true)
	if info.is_empty():
		return false
	if not bool(info.get("answered", false)) or bool(info.get("held", true)):
		return _fail("free name info %s" % info)
	if String(info.get("queried", "")) != "T41 Free":
		return _fail("free queried %s" % info.get("queried", ""))
	var after := await _score_total()
	if after != before:
		return _fail("free lookup changed score total %d -> %d" % [before, after])
	var claimed := await _resolve_direct("T41 Free")
	if int(claimed.get("code", 0)) != 201 or not bool(claimed.get("created", false)):
		return _fail("free name was already a holder %s" % claimed)
	_cases_passed += 1
	return true


func _case_held_display() -> bool:
	print("NAME_LOOKUP case held")
	var claimed := await _resolve_direct("Dad")
	if int(claimed.get("code", 0)) != 201 or String(claimed.get("name", "")) != "Dad":
		return _fail("could not seed Dad %s" % claimed)
	var info := await _ask("dad", true)
	if info.is_empty():
		return false
	if not bool(info.get("answered", false)) or not bool(info.get("held", false)):
		return _fail("held name info %s" % info)
	if String(info.get("display", "")) != "Dad":
		return _fail("display %s want Dad" % info.get("display", ""))
	if String(info.get("queried", "")) != "dad":
		return _fail("queried %s" % info.get("queried", ""))
	_cases_passed += 1
	return true


func _case_encoded_names() -> bool:
	var names: Array = ["Mary Jo", "A&B", "C+D", "E#F", "50%", "Zoë"]
	for raw in names:
		var player_name := String(raw)
		print("NAME_LOOKUP case encode %s" % player_name)
		var claimed := await _resolve_direct(player_name)
		if int(claimed.get("code", 0)) != 201 or String(claimed.get("name", "")) != player_name:
			return _fail("could not seed %s %s" % [player_name, claimed])
		var info := await _ask(player_name, true)
		if info.is_empty():
			return false
		if not bool(info.get("answered", false)) or not bool(info.get("held", false)):
			return _fail("%s info %s" % [player_name, info])
		if String(info.get("display", "")) != player_name:
			return _fail("%s display %s" % [player_name, info.get("display", "")])
		if String(info.get("queried", "")) != player_name:
			return _fail("%s queried %s" % [player_name, info.get("queried", "")])
		_cases_passed += 1
	return true


func _case_not_found() -> bool:
	print("NAME_LOOKUP case 404")
	var probe := await _http_json(STUB_PORT, HTTPClient.METHOD_GET, "/v1/players/lookup?name=Dad", "")
	if int(probe.get("code", 0)) != 404:
		return _fail("stub did not answer 404 (%s)" % probe)
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % STUB_PORT)
	var info := await _ask("Dad", false)
	if info.is_empty():
		return false
	if bool(info.get("answered", true)):
		return _fail("404 was answered %s" % info)
	if String(info.get("queried", "")) != "Dad":
		return _fail("404 queried %s" % info.get("queried", ""))
	_cases_passed += 1
	return true


func _case_no_resolve_post() -> bool:
	print("NAME_LOOKUP case no resolve post")
	var counts := await _counts()
	if counts.is_empty():
		return false
	var posts := int(counts.get("POST /v1/players/resolve", 0))
	var gets := int(counts.get("GET /v1/players/lookup", 0))
	if posts != 0:
		return _fail("lookup_name hit resolve %d times %s" % [posts, counts])
	if gets != _proxy_lookups:
		return _fail("lookup count %d want %d %s" % [gets, _proxy_lookups, counts])
	_cases_passed += 1
	return true


func _ask(raw_name: String, via_proxy: bool) -> Dictionary:
	if via_proxy:
		_proxy_lookups += 1
	var box := {"gen": -1, "done": false, "info": {}}
	var cb := func(generation: int, info: Dictionary) -> void:
		if generation != int(box.gen):
			return
		box.done = true
		box.info = info
	_leaderboard.name_lookup.connect(cb)
	box.gen = int(_leaderboard.lookup_name(raw_name))
	var start := Time.get_ticks_msec()
	while not bool(box.done) and Time.get_ticks_msec() - start < 2000:
		await process_frame
	if _leaderboard.name_lookup.is_connected(cb):
		_leaderboard.name_lookup.disconnect(cb)
	if not bool(box.done):
		_fail("lookup timed out for %s" % raw_name)
		return {}
	return box.info


func _resolve_direct(player_name: String) -> Dictionary:
	var body := JSON.stringify({"name": player_name})
	var got := await _http_json(PORT, HTTPClient.METHOD_POST, "/v1/players/resolve", body)
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	var created := false
	var stored := ""
	if typeof(parsed) == TYPE_DICTIONARY:
		created = bool(parsed.get("created", false))
		stored = String(parsed.get("name", ""))
	return {"code": int(got.get("code", 0)), "created": created, "name": stored}


func _score_total() -> int:
	var got := await _http_json(PORT, HTTPClient.METHOD_GET, "/v1/admin/scores?limit=50", "", true)
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return -1
	return int(parsed.get("total", -1))


func _counts() -> Dictionary:
	var got := await _http_json(PROXY_PORT, HTTPClient.METHOD_GET, "/__counts", "")
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("proxy counts missing %s" % got)
		return {}
	return parsed


func _http_json(port: int, method: int, path: String, body: String, admin: bool = false) -> Dictionary:
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
	if admin:
		headers.append("X-Squish-Admin: dev-admin")
	var err := http.request("http://127.0.0.1:%d%s" % [port, path], headers, method, body)
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


func _start_proxy() -> bool:
	_free_port(PROXY_PORT)
	var js := """const http=require('http');
const counts={};
const target=Number(process.env.TARGET_PORT);
http.createServer((req,res)=>{
  let u;
  try { u=new URL(req.url,'http://127.0.0.1'); }
  catch (e) { res.writeHead(400); res.end('{}'); return; }
  if (u.pathname==='/__counts') {
    const body=JSON.stringify(counts);
    res.writeHead(200,{'content-type':'application/json'});
    res.end(body);
    return;
  }
  const key=req.method+' '+u.pathname;
  counts[key]=(counts[key]||0)+1;
  const headers=Object.assign({}, req.headers);
  delete headers.host;
  const preq=http.request({hostname:'127.0.0.1',port:target,path:req.url,method:req.method,headers:headers},(pres)=>{
    res.writeHead(pres.statusCode||502, pres.headers);
    pres.pipe(res);
  });
  preq.on('error',()=>{ if(!res.headersSent){ res.writeHead(502); res.end('{}'); } });
  req.pipe(preq);
}).listen(Number(process.env.LISTEN_PORT),'127.0.0.1');
"""
	var b64 := Marshalls.raw_to_base64(js.to_utf8_buffer())
	var cmd := "exec env TARGET_PORT=%d LISTEN_PORT=%d node -e \"eval(Buffer.from('%s','base64').toString())\"" % [PORT, PROXY_PORT, b64]
	_proxy_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _proxy_pid <= 0:
		_fail("proxy did not spawn")
		return false
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/__counts" % PROXY_PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	_fail("proxy did not become healthy")
	return false


func _start_stub() -> bool:
	_free_port(STUB_PORT)
	var js := "require('http').createServer((q,s)=>{s.writeHead(404,{'Content-Type':'application/json'});s.end('{\\\"error\\\":\\\"not_found\\\"}');}).listen(%d,'127.0.0.1')" % STUB_PORT
	var cmd := "exec node -e \"%s\"" % js
	_stub_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _stub_pid <= 0:
		_fail("stub did not spawn")
		return false
	OS.delay_msec(200)
	return true


func _free_port(port: int) -> void:
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; sleep 0.2; kill -9 $pids 2>/dev/null || true; fi" % port])


func _cleanup() -> void:
	for pid in [_stub_pid, _proxy_pid, _server_pid]:
		if pid > 0:
			OS.execute("/bin/kill", ["-TERM", str(pid)])
			OS.execute("/bin/kill", ["-KILL", str(pid)])
	_stub_pid = -1
	_proxy_pid = -1
	_server_pid = -1
	_free_port(STUB_PORT)
	_free_port(PROXY_PORT)
	_free_port(PORT)
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _fail(message: String) -> bool:
	push_error("NAME_LOOKUP FAIL %s" % message)
	print("NAME_LOOKUP FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
