#!/usr/bin/env bash
# Runs the orca-coord substrate test suite: preflight (python unittest) +
# spawn_worker (fake-orca shim scenarios). Exit nonzero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== preflight.py tests =="
python3 -m unittest discover -s tests -p 'test_*.py' -v

echo
echo "== spawn_worker.sh tests =="
bash tests/test_spawn_worker.sh

echo
echo "orca-coord substrate tests: ALL GREEN"
