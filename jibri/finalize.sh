#!/bin/bash
#
# Jibri finalize-script — Corabea
#
# Jibri runs this once a recording finishes, passing the recording's session
# directory as $1 (e.g. /config/recordings/<session-id>/).
#
# Pipeline (privacy minimization + central storage):
#   1. extract the AUDIO track from the mp4 to 16 kHz mono wav (Whisper-ready)
#   2. delete the mp4 (no video kept at rest — biometric minimization)
#   3. upload the wav to the remote MinIO bucket
#   4. delete the local wav ONLY if the upload succeeded
#
# If ffmpeg or the upload fails, the affected file is KEPT locally so nothing
# is lost (no automatic retry — handle leftover wavs manually for now).
#
# Config (env, set on the jibri container via .env):
#   S3_HOST     credentials URL for the S3 endpoint:
#               https://ACCESS_KEY:SECRET_KEY@s3.corabea.it
#   S3_BUCKET   target bucket (default: corabea)
#   S3_PREFIX   folder inside the bucket (default: recording)
#
set -uo pipefail

REC_DIR="${1:-}"
LOG="/config/finalize.log"
MC="/config/mc"
MC_ALIAS="corabea"            # internal mc alias name
MC_CFG="/config/.mc"
S3_BUCKET="${S3_BUCKET:-corabea}"       # bucket (s3://corabea)
S3_PREFIX="${S3_PREFIX:-recording}"     # folder inside the bucket

# mc reads credentials from MC_HOST_<alias>; bridge our S3_HOST env to it.
export MC_HOST_corabea="${S3_HOST:-}"

log() { echo "$(date -Is) [finalize] $*" >> "$LOG" 2>/dev/null; }

# Upload one file to S3. Returns 0 on success, non-zero otherwise.
upload_to_minio() {
    local file="$1"
    local base; base="$(basename "$file")"
    if [ -z "${S3_HOST:-}" ]; then
        log "WARN: S3 not configured (S3_HOST unset) — keeping ${base} local"
        return 1
    fi
    local target="${MC_ALIAS}/${S3_BUCKET}${S3_PREFIX:+/$S3_PREFIX}/${base}"
    log "uploading ${base} -> ${target}"
    "$MC" --config-dir "$MC_CFG" cp "$file" "$target" >> "$LOG" 2>&1
}

if [ -z "$REC_DIR" ] || [ ! -d "$REC_DIR" ]; then
    log "ERROR: invalid recording dir: '${REC_DIR}'"
    exit 1
fi

log "start: ${REC_DIR}"

shopt -s nullglob
mp4s=("$REC_DIR"/*.mp4)
if [ ${#mp4s[@]} -eq 0 ]; then
    log "WARN: no mp4 in ${REC_DIR}, nothing to do"
    exit 0
fi

for mp4 in "${mp4s[@]}"; do
    wav="${mp4%.mp4}.wav"
    log "extracting audio: ${mp4} -> ${wav}"
    if ffmpeg -nostdin -y -i "$mp4" -vn -ac 1 -ar 16000 -acodec pcm_s16le "$wav" >> "$LOG" 2>&1 && [ -s "$wav" ]; then
        log "OK: ${wav} ($(stat -c%s "$wav") bytes) — removing mp4"
        rm -f "$mp4"
        if upload_to_minio "$wav"; then
            log "OK: uploaded — removing local ${wav}"
            rm -f "$wav"
        else
            log "WARN: upload failed/skipped — keeping ${wav} for sweep retry"
        fi
    else
        log "ERROR: audio extraction failed for ${mp4} — KEEPING mp4"
        rm -f "$wav" 2>/dev/null
    fi
done

log "done: ${REC_DIR}"
exit 0
