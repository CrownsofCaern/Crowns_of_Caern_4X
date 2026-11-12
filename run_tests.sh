#!/usr/bin/env bash
# Runs the headless test suite. Fails on test failures AND on any GDScript
# runtime error (which Godot prints but does not turn into an exit code).
#
#   ./run_tests.sh [--slow] [filter]
#
# The GDScript tests run in TEST_JOBS Godot processes (default: one per CPU
# core) that share the test files through a queue directory; the asset
# pipeline tests run beside them. The whole run should take under 4 minutes.
# --slow adds the long tests that test files list in their SLOW constant
# (whole AI games, balance sweeps); run them before changing the AI or balance.
set -uo pipefail
GODOT="${GODOT:-godot}"
SLOW=()
FILTER=""
for arg in "$@"; do
  if [[ "$arg" == "--slow" ]]; then SLOW=(--slow); else FILTER="$arg"; fi
done
cd "$(dirname "$0")"
JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
start=$(date +%s)
"$GODOT" --headless --path . --import >/dev/null 2>&1

# Asset pipeline: unit tests, and committed atlases/manifest must match the sources.
assets=0
if [[ -z "$FILTER" ]] && command -v python3 >/dev/null && python3 -c "import PIL, numpy" 2>/dev/null; then
  assets=1
  (python3 -m unittest discover -s tools/assets/tests >"$tmp/assets_unit.log" 2>&1; echo $? >"$tmp/assets_unit.code") &
  (python3 tools/assets/pipeline.py check >"$tmp/assets_check.log" 2>&1; echo $? >"$tmp/assets_check.code") &
fi

# Each Godot process gets its own empty home, so parallel runners never share
# user:// (saves, settings, custom maps), and tests never touch your own saves.
isolated() {
  local home="$tmp/home_$1"
  mkdir -p "$home"
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" "${@:2}"
}
mkdir -p "$tmp/queue"
for ((i = 0; i < JOBS; i++)); do
  (isolated "$i" "$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$FILTER" ${SLOW[@]+"${SLOW[@]}"} --queue "$tmp/queue" \
    >"$tmp/unit_$i.log" 2>&1; echo $? >"$tmp/unit_$i.code") &
done
# The UI/AI handshake yields across frames and therefore needs a SceneTree runner.
if [[ -z "$FILTER" ]]; then
  (isolated integration "$GODOT" --headless --path . --script res://tests/integration/enemy_turn.gd \
    >"$tmp/integration.log" 2>&1; echo $? >"$tmp/integration.code") &
  (isolated online "$GODOT" --headless --path . --script res://tests/integration/online_loopback.gd \
    >"$tmp/online.log" 2>&1; echo $? >"$tmp/online.code") &
fi
wait

code=0
total=0
failed=0
skipped=0
for ((i = 0; i < JOBS; i++)); do
  out=$(cat "$tmp/unit_$i.log")
  echo "$out" | grep -E "^(PASS|FAIL) |^  - "
  if [[ "$(cat "$tmp/unit_$i.code")" != 0 ]]; then code=1; fi
  if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
    echo "$out" | grep -E -A3 "SCRIPT ERROR|Parse Error|Failed to load script"
    echo "Detected script errors in test run." >&2
    code=1
  fi
  summary=$(echo "$out" | grep -E "^[0-9]+ tests, [0-9]+ failed" | tail -1)
  if [[ -z "$summary" ]]; then
    echo "Test runner $i ended without a summary:" >&2
    echo "$out" | tail -20 >&2
    code=1
  else
    total=$((total + $(echo "$summary" | cut -d' ' -f1)))
    failed=$((failed + $(echo "$summary" | cut -d' ' -f3)))
    skipped=$((skipped + $(echo "$summary" | sed -E 's/.*\(([0-9]+) slow tests skipped.*/\1/')))
  fi
done
if [[ $total -eq 0 ]]; then code=1; fi
echo ""
echo "$total tests, $failed failed ($JOBS runners; $skipped slow tests skipped, run with --slow)"

if [[ -z "$FILTER" ]]; then
  cat "$tmp/integration.log"
  if [[ "$(cat "$tmp/integration.code")" != 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$tmp/integration.log"; then
    code=1
  fi
  cat "$tmp/online.log"
  if [[ "$(cat "$tmp/online.code")" != 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$tmp/online.log"; then
    code=1
  fi
fi

if [[ $assets -eq 1 ]]; then
  tail -3 "$tmp/assets_unit.log"
  if [[ "$(cat "$tmp/assets_unit.code")" != 0 ]]; then cat "$tmp/assets_unit.log"; code=1; fi
  cat "$tmp/assets_check.log"
  if [[ "$(cat "$tmp/assets_check.code")" != 0 ]]; then code=1; fi
elif [[ -z "$FILTER" ]]; then
  echo "Skipping asset pipeline tests (needs python3 with Pillow and numpy)."
fi
echo "Finished in $(($(date +%s) - start))s."
exit $code
