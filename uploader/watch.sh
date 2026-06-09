#!/bin/bash
#
# Corabea — event-driven trigger for transcriber WAV uploads.
#
# Watches the transcripts tree and, the instant Jigasi CLOSES a .wav
# (CLOSE_WRITE = the transcription session finished, file fully written),
# hands that exact file to upload.sh for immediate upload to S3.
#
# This is the "upload when the call ends" path. The systemd timer that runs
# upload.sh in safety-net mode remains as a backstop for anything this watcher
# might miss (e.g. it was restarting at the moment a file closed).
#
set -uo pipefail

TRANSCRIPTS_DIR="/opt/jitsi/.jitsi-meet-cfg/transcripts"   # where Jigasi writes WAVs
UPLOAD="/opt/jitsi/transcripts/upload.sh"
LOCK="/run/jitsi-transcripts-upload.lock"
LOG="/opt/jitsi/transcripts/upload.log"

log() { echo "$(date -Is) [watch] $*" >> "$LOG" 2>/dev/null; }

log "watcher started on ${TRANSCRIPTS_DIR}"

# -m: keep running, -r: recurse into <session>/ subdirs (auto-watches new ones),
# -q: quiet, format prints the full path of the closed file.
inotifywait -m -r -q -e close_write --format '%w%f' "$TRANSCRIPTS_DIR" | while read -r path; do
    case "$path" in
        *.wav)
            log "CLOSE_WRITE ${path} -> uploading now"
            flock "$LOCK" "$UPLOAD" "$path"
            ;;
    esac
done
