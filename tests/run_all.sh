#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TEST_USER_DIR="$HOME/Library/Application Support/SquishyPinballTest"
SINGLE_TEST="${1:-}"

cd "$ROOT"

cleanup() {
	rm -f override.cfg
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
	run_test_script "$script"
done

echo "SUMMARY: all suites PASS"
