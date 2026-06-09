#!/bin/bash
#
# Corabea — Jigasi transcriber WAV -> S3 uploader
#
# The Jigasi transcriber drops, per transcription session, a mixed mono WAV plus
# a transcript .txt into .jitsi-meet-cfg/transcripts/<session>/. The .txt names
# the room (e.g. "in room appointment-<uuid>@muc.meet.jitsi"). We use that to
# group all fragments of the SAME call (a call may yield several WAVs if someone
# disconnects/reconnects) under one S3 subfolder = a short hash of the room, so
# fragments stay linked WITHOUT exposing the appointment id. The .txt itself
# (participant names + draft transcript) is sensitive and is DELETED after use.
#
# Two callers:
#   * EVENT mode  — `upload.sh <file.wav>` (from watch.sh, on CLOSE_WRITE)
#   * SWEEP mode  — `upload.sh` (no args, from the systemd timer; safety net,
#                   also cleans orphan transcript .txt files)
#
# Each WAV -> s3://<bucket>/recordings/<roomhash>/<uuid>.wav; local wav + txt are
# deleted on success. Whisper runs on a SEPARATE server reading from S3.
# Reuses the same mc binary + S3_HOST credentials as the Jibri finalize.sh.
#
set -uo pipefail

JITSI_DIR="/opt/jitsi"
ENV_FILE="${JITSI_DIR}/.env"
TRANSCRIPTS_DIR="${JITSI_DIR}/.jitsi-meet-cfg/transcripts"
MC="${JITSI_DIR}/transcripts/mc"
MC_ALIAS="corabea"
LOG="${JITSI_DIR}/transcripts/upload.log"
MIN_AGE_MIN="${MIN_AGE_MIN:-2}"   # sweep mode: only files idle > this many minutes
S3_PREFIX="recordings"            # same bucket folder as the Jibri recordings
TXT_WAIT_TRIES=12                 # event mode: poll up to ~6s for the sibling .txt

log() { echo "$(date -Is) [upload] $*" >> "$LOG" 2>/dev/null; }

# S3 endpoint + credentials come from the jitsi .env (same as finalize.sh).
S3_HOST="$(grep -E '^S3_HOST=' "$ENV_FILE" | cut -d= -f2-)"
S3_BUCKET="$(grep -E '^S3_BUCKET=' "$ENV_FILE" | cut -d= -f2-)"
S3_BUCKET="${S3_BUCKET:-corabea}"
export MC_HOST_corabea="$S3_HOST"

[ -n "$S3_HOST" ]         || { log "ERROR: S3_HOST empty in ${ENV_FILE}"; exit 1; }
[ -x "$MC" ]              || { log "ERROR: mc not found/executable at ${MC}"; exit 1; }
[ -d "$TRANSCRIPTS_DIR" ] || { log "ERROR: transcripts dir missing"; exit 0; }

# Path of the sibling transcript .txt in the wav's folder. In the event path the
# txt is written just after the wav closes, so poll briefly for it.
sibling_txt() {
    local dir; dir="$(dirname "$1")"
    local t i
    for ((i = 0; i < TXT_WAIT_TRIES; i++)); do
        t="$(find "$dir" -maxdepth 1 -name 'transcript_*.txt' 2>/dev/null | head -1)"
        [ -n "$t" ] && { printf '%s' "$t"; return 0; }
        sleep 0.5
    done
}

# Per-call S3 subfolder: short hash of the room read from the transcript, so all
# fragments of one call group together. Empty if the room can't be determined.
subfolder_for() {
    local txt="$1" room
    [ -n "$txt" ] && [ -f "$txt" ] || return 0
    room="$(grep -m1 -oE 'in room [^ ]+' "$txt" 2>/dev/null | sed 's/^in room //')"
    [ -n "$room" ] || return 0
    printf '%s' "$room" | sha256sum | cut -c1-16
}

# Upload one WAV under its room-hash subfolder, then delete the local wav + txt.
upload_one() {
    local wav="$1"
    [ -f "$wav" ] || return 0
    local dir base txt sub target
    dir="$(dirname "$wav")"
    base="$(basename "$wav")"
    txt="$(sibling_txt "$wav")"
    sub="$(subfolder_for "$txt")"
    if [ -n "$sub" ]; then
        target="${MC_ALIAS}/${S3_BUCKET}/${S3_PREFIX}/${sub}/${base}"
    else
        target="${MC_ALIAS}/${S3_BUCKET}/${S3_PREFIX}/${base}"
        log "WARN: room unknown for ${base} — uploading without call subfolder"
    fi
    log "uploading ${base} ($(stat -c%s "$wav") bytes) -> ${target}"
    if "$MC" --quiet cp "$wav" "$target" >> "$LOG" 2>&1; then
        log "OK: uploaded ${base} — removing local wav + transcript"
        rm -f "$wav"
        [ -n "$txt" ] && rm -f "$txt"
        if rmdir "$dir" 2>/dev/null; then log "removed empty session dir"; fi
    else
        log "WARN: upload failed for ${base} — keeping local for next run"
    fi
}

# EVENT mode: a specific (already-closed) file was passed.
if [ "$#" -ge 1 ]; then
    upload_one "$1"
    exit 0
fi

# SWEEP mode: finished WAVs (idle > MIN_AGE_MIN minutes).
mapfile -d '' wavs < <(find "$TRANSCRIPTS_DIR" -type f -name '*.wav' -mmin "+${MIN_AGE_MIN}" -print0)
for wav in "${wavs[@]}"; do
    upload_one "$wav"
done

# SWEEP mode: delete orphan transcript .txt (wav already uploaded/gone) — these
# carry names + draft text and must not pile up locally.
mapfile -d '' txts < <(find "$TRANSCRIPTS_DIR" -type f -name 'transcript_*.txt' -mmin "+${MIN_AGE_MIN}" -print0)
for txt in "${txts[@]}"; do
    dir="$(dirname "$txt")"
    if ! find "$dir" -maxdepth 1 -name '*.wav' -print -quit | grep -q .; then
        rm -f "$txt"
        rmdir "$dir" 2>/dev/null
        log "cleaned orphan transcript in $(basename "$dir")"
    fi
done

exit 0
