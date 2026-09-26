#!/usr/bin/env bash
# tools/export_web.sh — T26 / D-045
# Reproducible Web export from a clean checkout. Generates export_presets.cfg
# (gitignored, D-008) and writes the build to export/web/ (also gitignored).
# Single-threaded: this project does not use Thread / WorkerThreadPool, so
# the page does not need Cross-Origin-Opener/Embedder isolation headers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"
PRESET_NAME="Web"
PRESET_PATH="${SQUISH_EXPORT_PRESET_PATH:-$ROOT/export_presets.cfg}"
OUT_DIR="${SQUISH_EXPORT_OUT_DIR:-$ROOT/export/web}"
WRITE_PRESET_ONLY=0
DO_DOWNLOAD=0
SKIP_DOWNLOAD="${SQUISH_SKIP_TEMPLATE_DOWNLOAD:-0}"

TEMPLATES_URL_BASE="https://github.com/godotengine/godot-builds/releases/download"

usage() {
	cat <<'EOF'
Usage: bash tools/export_web.sh [--download] [--write-preset-only]

  --download            If the Godot web export templates are missing, fetch
                        the official .tpz (~1.3 GB) and install only the
                        web_nothreads zips this preset needs.
  --write-preset-only   Write export_presets.cfg and exit (no templates, no
                        export). Used by tests/export_web_test.gd.

Environment:
  GODOT                         godot binary (default: godot)
  SQUISH_EXPORT_TEMPLATES_DIR   override the templates folder (tests)
  SQUISH_EXPORT_PRESET_PATH     override where the preset is written
  SQUISH_EXPORT_OUT_DIR         override the export directory
  SQUISH_SKIP_TEMPLATE_DOWNLOAD=1
                                never fetch templates; fail if they are missing
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--download) DO_DOWNLOAD=1 ;;
		--write-preset-only) WRITE_PRESET_ONLY=1 ;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "export_web: unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

die() {
	echo "export_web: $*" >&2
	exit 1
}

require_godot() {
	if ! command -v "$GODOT" >/dev/null 2>&1; then
		die "godot not found (looked for '${GODOT}'). Install 4.7.2 and put it on PATH."
	fi
}

godot_version_raw() {
	"$GODOT" --version | head -1 | tr -d '\r'
}

# 4.7.2.stable.official.ed1daf0bf → 4.7.2.stable
godot_templates_folder() {
	local raw
	raw="$(godot_version_raw)"
	printf '%s\n' "$raw" | awk -F. '{print $1"."$2"."$3"."$4}'
}

# 4.7.2.stable → 4.7.2-stable
godot_release_tag() {
	local folder="$1"
	printf '%s\n' "${folder/.stable/-stable}"
}

default_templates_parent() {
	case "$(uname -s)" in
		Darwin)
			printf '%s\n' "$HOME/Library/Application Support/Godot/export_templates"
			;;
		*)
			printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates"
			;;
	esac
}

templates_dir() {
	if [ -n "${SQUISH_EXPORT_TEMPLATES_DIR:-}" ]; then
		printf '%s\n' "$SQUISH_EXPORT_TEMPLATES_DIR"
		return
	fi
	printf '%s/%s\n' "$(default_templates_parent)" "$(godot_templates_folder)"
}

# Official 4.7.2 name for extensions=false, thread_support=false, release.
# See platform/web/export/export_plugin.h :: _get_template_name.
required_template_name() {
	printf '%s\n' "web_nothreads_release.zip"
}

relpath_from_root() {
	local target="$1"
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "$ROOT"
		return
	fi
	case "$target" in
		"$ROOT"/*) printf '%s\n' "${target#"$ROOT"/}" ;;
		*) printf '%s\n' "$target" ;;
	esac
}

write_preset() {
	local out_html="$OUT_DIR/index.html"
	local rel_html
	rel_html="$(relpath_from_root "$out_html")"

	# D-050: touch browsers only build the hidden input when this flag is on.
	# That input is what iOS attaches a keyboard to. Leave it true.
	mkdir -p "$(dirname "$PRESET_PATH")"
	cat > "$PRESET_PATH" <<EOF
[preset.0]

name="${PRESET_NAME}"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="${rel_html}"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell=""
html/head_include="<meta name=\\"description\\" content=\\"Natasha's virtual pinball machine\\">"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=true
progressive_web_app/enabled=false
progressive_web_app/ensure_cross_origin_isolation_headers=false
progressive_web_app/offline_page=""
progressive_web_app/display=1
progressive_web_app/orientation=0
progressive_web_app/icon_144x144=""
progressive_web_app/icon_180x180=""
progressive_web_app/icon_512x512=""
progressive_web_app/background_color=Color(0, 0, 0, 1)
threads/emscripten_pool_size=8
threads/godot_pool_size=4
EOF
	echo "export_web: wrote preset '${PRESET_NAME}' → ${PRESET_PATH}"
}

templates_missing_message() {
	local dir="$1"
	local zip="$2"
	local folder
	folder="$(godot_templates_folder)"
	local tag
	tag="$(godot_release_tag "$folder")"
	cat <<EOF
export_web: Godot web export templates are not installed.

Looked for: ${dir}/${zip}
Godot:      $(godot_version_raw)

Install them, then re-run this script. Either:

  1. Editor → Manage Export Templates… → Download and Install
     (installs into $(default_templates_parent)/${folder}/)

  2. bash tools/export_web.sh --download
     fetches Godot_v${tag}_export_templates.tpz (~1.3 GB) from
     ${TEMPLATES_URL_BASE}/${tag}/
     and extracts only the web_nothreads zips this preset needs.

Do not commit the templates, export_presets.cfg, or export/ (D-008).
The script refuses to export without ${zip} so it cannot produce a
broken white-screen build.
EOF
}

download_templates() {
	local dir="$1"
	if [ -n "${SQUISH_EXPORT_TEMPLATES_DIR:-}" ]; then
		die "refusing to download into SQUISH_EXPORT_TEMPLATES_DIR (${SQUISH_EXPORT_TEMPLATES_DIR})"
	fi
	local folder tag url tmp
	folder="$(godot_templates_folder)"
	tag="$(godot_release_tag "$folder")"
	url="${TEMPLATES_URL_BASE}/${tag}/Godot_v${tag}_export_templates.tpz"
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/squish-web-templates.XXXXXX")"
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" RETURN
	echo "export_web: downloading official export templates (~1.3 GB) from"
	echo "            ${url}"
	if ! command -v curl >/dev/null 2>&1; then
		die "curl is required to download export templates"
	fi
	if ! curl -fL --progress-bar -o "$tmp/templates.tpz" "$url"; then
		die "download failed. Install templates from the editor, or retry --download."
	fi
	if ! command -v unzip >/dev/null 2>&1; then
		die "unzip is required to extract export templates"
	fi
	# .tpz is a zip whose members live under templates/.
	if ! unzip -q -o "$tmp/templates.tpz" \
		"templates/version.txt" \
		"templates/web_nothreads_debug.zip" \
		"templates/web_nothreads_release.zip" \
		-d "$tmp"; then
		die "the downloaded archive did not contain web_nothreads templates"
	fi
	mkdir -p "$dir"
	cp -f "$tmp/templates/version.txt" \
		"$tmp/templates/web_nothreads_debug.zip" \
		"$tmp/templates/web_nothreads_release.zip" \
		"$dir/"
	echo "export_web: installed web_nothreads templates → ${dir}"
}

ensure_templates() {
	local dir zip
	dir="$(templates_dir)"
	zip="$(required_template_name)"
	if [ -f "${dir}/${zip}" ]; then
		echo "export_web: templates ok (${dir}/${zip})"
		return 0
	fi
	if [ "$SKIP_DOWNLOAD" = "1" ]; then
		templates_missing_message "$dir" "$zip" >&2
		exit 1
	fi
	if [ "$DO_DOWNLOAD" = "1" ]; then
		download_templates "$dir"
		if [ ! -f "${dir}/${zip}" ]; then
			die "download finished but ${dir}/${zip} is still missing"
		fi
		return 0
	fi
	templates_missing_message "$dir" "$zip" >&2
	exit 1
}

verify_output() {
	local html="$OUT_DIR/index.html"
	local missing=0
	local f
	# Godot 4.7 names the exported icon index.icon.png (not favicon.png).
	for f in index.html index.js index.wasm index.pck index.icon.png; do
		if [ ! -s "${OUT_DIR}/${f}" ]; then
			echo "export_web: missing or empty ${OUT_DIR}/${f}" >&2
			missing=1
		fi
	done
	if [ "$missing" -ne 0 ]; then
		die "export reported success but the web build is incomplete. Not treating this as a working build."
	fi
	# A white-screen wasm is often a near-empty pck or a tiny wasm stub.
	local wasm_size pck_size
	wasm_size="$(wc -c < "${OUT_DIR}/index.wasm" | tr -d ' ')"
	pck_size="$(wc -c < "${OUT_DIR}/index.pck" | tr -d ' ')"
	if [ "$wasm_size" -lt 1000000 ]; then
		die "index.wasm is ${wasm_size} bytes — too small to be a real Godot 4 web template"
	fi
	if [ "$pck_size" -lt 100000 ]; then
		die "index.pck is ${pck_size} bytes — too small to contain this project"
	fi
	echo "export_web: ${html}"
	echo "export_web: index.wasm ${wasm_size} bytes"
	echo "export_web: index.pck  ${pck_size} bytes"
	du -sh "$OUT_DIR" | awk '{print "export_web: output dir "$1"  '"$OUT_DIR"'"}'
}

require_godot
write_preset

if [ "$WRITE_PRESET_ONLY" = "1" ]; then
	exit 0
fi

ensure_templates

mkdir -p "$OUT_DIR"
# Wipe previous artifacts so a failed export cannot leave a stale mix.
find "$OUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

echo "export_web: importing project"
"$GODOT" --path "$ROOT" --headless --import

echo "export_web: exporting preset '${PRESET_NAME}' → ${OUT_DIR}/index.html"
if ! "$GODOT" --path "$ROOT" --headless --export-release "$PRESET_NAME" "$OUT_DIR/index.html"; then
	die "godot --export-release '${PRESET_NAME}' failed. See the log above. No working build was produced."
fi

verify_output
echo "export_web: done. Serve with: python3 -m http.server 8080 --directory export/web"
