#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TEST_USER_DIR="$HOME/Library/Application Support/SquishyPinballTest"
SINGLE_TEST="${1:-}"
LB_PORT=8787
LB_SERVER_PID=""
CLOSED_LB_URL="http://127.0.0.1:1"

cd "$ROOT"

# Tests must never hit the live Render board. Default to a closed port; the
# leaderboard suite alone is pointed at the local memory server.
export SQUISH_LEADERBOARD_URL="${CLOSED_LB_URL}"
export SQUISH_LEADERBOARD_KEY="devkey"

stop_leaderboard_server() {
	if command -v lsof >/dev/null 2>&1; then
		local pids
		pids="$(lsof -ti tcp:${LB_PORT} 2>/dev/null || true)"
		if [ -n "$pids" ]; then
			# word-split intended: lsof may return several pids
			kill $pids 2>/dev/null || true
			sleep 0.2
			kill -9 $pids 2>/dev/null || true
		fi
	fi
	if [ -n "${LB_SERVER_PID:-}" ]; then
		kill "$LB_SERVER_PID" 2>/dev/null || true
		wait "$LB_SERVER_PID" 2>/dev/null || true
		LB_SERVER_PID=""
	fi
	rm -f /tmp/squish-lb-test.pid
	export SQUISH_LEADERBOARD_URL="${CLOSED_LB_URL}"
}

wait_for_healthz() {
	local i=0
	while [ "$i" -lt 20 ]; do
		if curl -sf --max-time 1 "http://127.0.0.1:${LB_PORT}/healthz" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.5
		i=$((i + 1))
	done
	echo "leaderboard server: /healthz not ready within 10s"
	return 1
}

start_leaderboard_server() {
	stop_leaderboard_server
	(
		cd "$ROOT/server"
		exec env DB_PATH=:memory: SQUISH_KEY=devkey PORT="${LB_PORT}" \
			node --no-warnings=ExperimentalWarning src/index.js
	) >/tmp/squish-lb-test.log 2>&1 &
	LB_SERVER_PID=$!
	echo "$LB_SERVER_PID" > /tmp/squish-lb-test.pid
	disown "$LB_SERVER_PID" 2>/dev/null || true
	echo "leaderboard server: starting pid=${LB_SERVER_PID}"
	if ! wait_for_healthz; then
		echo "leaderboard server failed to start (pid ${LB_SERVER_PID})"
		if [ -f /tmp/squish-lb-test.log ]; then
			cat /tmp/squish-lb-test.log
		fi
		return 1
	fi
	export SQUISH_LEADERBOARD_URL="http://127.0.0.1:${LB_PORT}"
	export SQUISH_LEADERBOARD_KEY="devkey"
}

cleanup() {
	rm -f override.cfg
	stop_leaderboard_server
}
trap cleanup EXIT INT TERM

rm -rf "$TEST_USER_DIR"

write_isolation_override() {
	cat > override.cfg <<'EOF'
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="SquishyPinballTest"
EOF
}

write_isolation_override

run_step() {
	local label="$1"
	shift
	echo "=== ${label} ==="
	if "$@"; then
		echo "${label}: PASS"
	else
		echo "${label}: FAIL"
		exit 1
	fi
}

run_test_script() {
	local script="$1"
	local name
	name="$(basename "$script" .gd)"
	local output=""
	local rc=0

	set +e
	output="$("$GODOT" --headless -s "$script" --fixed-fps 120 2>&1)"
	rc=$?
	set -e

	echo "$output"

	if echo "$output" | grep -q 'FAIL'; then
		echo "${name}: FAIL"
		return 1
	fi
	if [ "$rc" -ne 0 ]; then
		echo "${name}: FAIL (exit ${rc})"
		return 1
	fi
	if echo "$output" | grep -q 'PASS'; then
		echo "${name}: PASS"
		return 0
	fi

	echo "${name}: FAIL (no PASS line)"
	return 1
}

run_boot_check() {
	# Godot reads override.cfg once at startup; append BootCheck only for this step.
	cat >> override.cfg <<'EOF'

[autoload]
BootCheck="*res://tests/boot_check.gd"
EOF

	local output=""
	local rc=0
	set +e
	output="$("$GODOT" --path . --headless --quit-after 600 2>&1)"
	rc=$?
	set -e

	# Rewrite even if the boot step failed — set -e would otherwise skip this.
	write_isolation_override

	echo "$output"

	if echo "$output" | grep -q 'BOOT PASS' && [ "$rc" -eq 0 ]; then
		local pass_line
		pass_line="$(echo "$output" | grep -m1 'BOOT PASS')"
		echo "boot-check: PASS (${pass_line})"
		return 0
	fi
	echo "boot-check: FAIL"
	return 1
}

if [ -n "$SINGLE_TEST" ]; then
	case "$SINGLE_TEST" in
		boot_check|boot_check.gd)
			run_boot_check
			echo "SUMMARY: boot_check PASS"
			exit 0
			;;
		*.gd) script="tests/${SINGLE_TEST}" ;;
		*) script="tests/${SINGLE_TEST}.gd" ;;
	esac
	if [ ! -f "$script" ]; then
		echo "Unknown test: ${SINGLE_TEST}"
		exit 1
	fi
	if [ "$(basename "$script")" = "leaderboard_test.gd" ]; then
		start_leaderboard_server
	fi
	run_test_script "$script"
	echo "SUMMARY: ${SINGLE_TEST} PASS"
	exit 0
fi

run_step "import" "$GODOT" --headless --import
run_step "quit-after-300" "$GODOT" --headless --quit-after 300

echo "=== boot-check ==="
if ! run_boot_check; then
	exit 1
fi

TESTS=(
	tests/isolation_test.gd
)
while IFS= read -r test; do
	TESTS+=("$test")
done < <(find tests -maxdepth 1 -name '*_test.gd' ! -name 'isolation_test.gd' | sort)
TESTS+=(tests/game_flow.gd)
TESTS+=(tests/soak_launch.gd)

for script in "${TESTS[@]}"; do
	if [ "$(basename "$script")" = "leaderboard_test.gd" ]; then
		start_leaderboard_server
		if ! run_test_script "$script"; then
			stop_leaderboard_server
			exit 1
		fi
		stop_leaderboard_server
	else
		run_test_script "$script"
	fi
done

echo "SUMMARY: all suites PASS"
