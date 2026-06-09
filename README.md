# corabea_jitsi

Custom transcription/recording pipeline for the self-hosted **docker-jitsi-meet**
stack (`/opt/jitsi`). It auto-records appointment calls and ships the audio to S3
for transcription by a **separate Whisper server**.

This repo holds only the custom artifacts + a deploy script. The base
docker-jitsi-meet stack and the secrets (`/opt/jitsi/.env`) are **not** in here.

## What it does

```
appointment call (operator = moderator + patient both present)
  -> prosody module auto-starts transcription (no click)            [prosody/]
  -> Jigasi transcriber joins, records a mixed mono WAV
     (a no-op "null STT" satisfies Jigasi; transcript discarded)    [null-stt/]
  -> on file close, the WAV is uploaded to S3 and deleted locally   [uploader/]
       s3://<bucket>/recordings/<sha256(room)>/<uuid>.wav
  -> Whisper, on a SEPARATE server, reads the WAVs from S3
```

- **Automatic, only for `appointment-*` rooms.** Fires when both participants are
  present (operator must be a moderator).
- **Anonymous + grouped:** filenames are random UUIDs; all fragments of one call
  share a subfolder = a hash of the room (the appointment id is never in clear).
- **Cheap:** the null STT loads no model — CPU/RAM ~0, scales to many calls.
- **Privacy:** the sensitive draft `.txt` (names + text) is deleted after use.

## Layout

| Path | Purpose | Runs in |
|---|---|---|
| `compose/null-stt.yml` | compose override for the null-STT service | host (docker) |
| `null-stt/` | Dockerfile + `server.py` for the no-op STT | host (docker build) |
| `uploader/` | inotify watcher + safety-net timer (WAV -> S3) | host (systemd) |
| `prosody/mod_corabea_call_events.lua` | auto-start transcription on both-present | **prosody container** |
| `jibri/finalize.sh` | legacy Jibri recording -> S3 (kept for reference) | jibri container |

**Key rule:** anything a *container* reads via bind-mount (the prosody module)
must be **copied** into `/opt/jitsi` — a symlink to `/home` won't resolve inside
the container. Everything else is read by the host and can live in this repo.

## Deploy

On a host that already has docker-jitsi-meet at `/opt/jitsi`:

```bash
git clone <repo> /home/ubuntu/corabea_jitsi
cd /home/ubuntu/corabea_jitsi
# 1. put the vars from .env.example into /opt/jitsi/.env (real secrets), and ensure
#    XMPP_MUC_MODULES=token_moderation,corabea_call_events
# 2. deploy + launch:
just deploy
```

Recipes (matches the other corabea repos):

| Recipe | What |
|---|---|
| `just build` | build the null-STT image |
| `just install-uploader` | install the systemd uploader (watcher + timer) |
| `just deploy` | build + install-uploader + copy prosody/compose + launch the stack |
| `just up` | (re)launch the stack only |

The **operator's appointment JWT must set `moderator=true`** (the backend that
mints it lives elsewhere — `corabea_api`), or Jicofo refuses the auto-start.

## Known issue

The Jigasi transcriber's media/control channel to the JVB (colibri-websocket) is
**flaky during the conference-formation window** (the first ~minute). If it drops,
the systemd watcher uploads what was recorded and the prosody module re-arms, so a
call may be split into several WAVs (**no audio lost**, all under the same room
subfolder). Manually-started transcriptions (clicked once the call is settled) are
stable. A real fix would make the transcriber↔JVB channel reliable from inside
Docker (internal colibri-ws reachability or forcing the SCTP datachannel).
