#!/usr/bin/env bash
# Runs the headless test suite. Fails on test failures AND on any GDScript
# runtime error (which Godot prints but does not turn into an exit code).
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")"
"$GODOT" --headless --path . --import >/dev/null 2>&1
out=$("$GODOT" --headless --path . --script res://tests/run_tests.gd -- "${1:-}" 2>&1)
code=$?
echo "$out"
if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
  echo "Detected script errors in test run." >&2
  exit 1
fi
# The UI/AI handshake yields across frames and therefore needs a SceneTree runner.
if [[ -z "${1:-}" ]]; then
  integration_out=$("$GODOT" --headless --path . --script res://tests/integration/enemy_turn.gd 2>&1)
  integration_code=$?
  echo "$integration_out"
  if [[ $integration_code -ne 0 ]] || echo "$integration_out" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
    code=1
  fi
fi
# Asset pipeline: unit tests, and committed atlases/manifest must match the sources.
if command -v python3 >/dev/null && python3 -c "import PIL, numpy" 2>/dev/null; then
  if ! python3 -m unittest discover -s tools/assets/tests 2>&1 | tail -3; then code=1; fi
  if ! python3 tools/assets/pipeline.py check; then code=1; fi
else
  echo "Skipping asset pipeline tests (needs python3 with Pillow and numpy)."
fi
exit $code
