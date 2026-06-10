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

JITSI_DIR="${JITSI_DIR:-/opt/jitsi}"
ENV_FILE="${ENV_FILE:-${JITSI_DIR}/.env}"
TRANSCRIPTS_DIR="${TRANSCRIPTS_DIR:-${JITSI_DIR}/.jitsi-meet-cfg/transcripts}"
MC="${MC:-${JITSI_DIR}/transcripts/mc}"
MC_ALIAS="${MC_ALIAS:-corabea}"
LOG="${LOG:-${JITSI_DIR}/transcripts/upload.log}"
MIN_AGE_MIN="${MIN_AGE_MIN:-2}"
S3_PREFIX="${S3_PREFIX:-recordings}"
TXT_WAIT_TRIES=12

log() { echo "$(date -Is) [upload] $*" >> "$LOG" 2>/dev/null; }

# S3 endpoint + creds: prefer the env (container), else read from the jitsi .env.
[ -z "${S3_HOST:-}" ]   && [ -f "$ENV_FILE" ] && S3_HOST="$(grep -E '^S3_HOST=' "$ENV_FILE" | cut -d= -f2-)"
[ -z "${S3_BUCKET:-}" ] && [ -f "$ENV_FILE" ] && S3_BUCKET="$(grep -E '^S3_BUCKET=' "$ENV_FILE" | cut -d= -f2-)"
S3_BUCKET="${S3_BUCKET:-corabea}"
export MC_HOST_corabea="${S3_HOST:-}"

[ -n "${S3_HOST:-}" ]      || { log "ERROR: S3_HOST not set (env or ${ENV_FILE})"; exit 1; }
command -v "$MC" >/dev/null || { log "ERROR: mc not found ($MC)"; exit 1; }
[ -d "$TRANSCRIPTS_DIR" ]  || { log "ERROR: transcripts dir missing ($TRANSCRIPTS_DIR)"; exit 0; }

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

# Upload one WAV under its room-hash subfolder, then delete the local files.
# The WAV is compressed to Opus (16 kHz mono) before upload to cut bandwidth +
# storage ~25x; transcription is unaffected (Whisper runs at 16 kHz). Falls back
# to the raw WAV if ffmpeg is unavailable or encoding fails.
upload_one() {
    local wav="$1"
    [ -f "$wav" ] || return 0
    local dir base txt sub upfile upbase target
    dir="$(dirname "$wav")"
    base="$(basename "$wav")"
    txt="$(sibling_txt "$wav")"
    sub="$(subfolder_for "$txt")"

    upfile="$wav"; upbase="$base"
    if command -v ffmpeg >/dev/null 2>&1; then
        local opus="${wav%.wav}.opus"
        if ffmpeg -nostdin -y -hide_banner -loglevel error -i "$wav" \
                  -ac 1 -ar 16000 -c:a libopus -b:a "${OPUS_BITRATE:-32k}" "$opus" 2>>"$LOG"; then
            upfile="$opus"; upbase="$(basename "$opus")"
        else
            log "WARN: opus encode failed for ${base} — uploading raw wav"
            rm -f "$opus"
        fi
    else
        log "WARN: ffmpeg not found — uploading raw wav (install ffmpeg to compress)"
    fi

    if [ -n "$sub" ]; then
        target="${MC_ALIAS}/${S3_BUCKET}/${S3_PREFIX}/${sub}/${upbase}"
    else
        target="${MC_ALIAS}/${S3_BUCKET}/${S3_PREFIX}/${upbase}"
        log "WARN: room unknown for ${upbase} — uploading without call subfolder"
    fi
    log "uploading ${upbase} ($(stat -c%s "$upfile") bytes) -> ${target}"
    if "$MC" --quiet cp "$upfile" "$target" >> "$LOG" 2>&1; then
        log "OK: uploaded ${upbase} — removing local files + transcript"
        rm -f "$wav" "$upfile"
        [ -n "$txt" ] && rm -f "$txt"
        if rmdir "$dir" 2>/dev/null; then log "removed empty session dir"; fi
    else
        log "WARN: upload failed for ${upbase} — keeping wav for next run"
        [ "$upfile" != "$wav" ] && rm -f "$upfile"
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
