#!/bin/bash

set -uo pipefail

UPLOAD="${UPLOAD:-/usr/local/bin/upload.sh}"
WATCH="${WATCH:-/usr/local/bin/watch.sh}"
SWEEP_INTERVAL="${SWEEP_INTERVAL:-300}"

( while true; do sleep "$SWEEP_INTERVAL"; "$UPLOAD" || true; done ) &

exec "$WATCH"
