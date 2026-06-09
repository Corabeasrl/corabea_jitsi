# corabea_jitsi — custom transcription layer over docker-jitsi-meet (/opt/jitsi).
# Auto-records appointment calls -> S3 (Whisper runs on a separate server).

jitsi   := "/opt/jitsi"
cfg     := jitsi / ".jitsi-meet-cfg"
compose := "docker compose -f docker-compose.yml -f jibri.yml -f transcriber.yml -f null-stt.yml"

# Build the no-op "null STT" image (ignites Jigasi, loads no model).
build:
    docker build -t corabea/null-stt:latest null-stt

# Install the host-side uploader: inotify watcher + safety-net timer (WAV -> S3).
install-uploader:
    command -v inotifywait >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y inotify-tools)
    sudo mkdir -p {{jitsi}}/transcripts
    sudo cp uploader/upload.sh uploader/watch.sh {{jitsi}}/transcripts/
    sudo chmod +x {{jitsi}}/transcripts/upload.sh {{jitsi}}/transcripts/watch.sh
    sudo cp uploader/jitsi-transcripts-watch.service uploader/jitsi-transcripts-upload.service uploader/jitsi-transcripts-upload.timer {{jitsi}}/transcripts/
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-watch.service /etc/systemd/system/jitsi-transcripts-watch.service
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-upload.service /etc/systemd/system/jitsi-transcripts-upload.service
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-upload.timer /etc/systemd/system/jitsi-transcripts-upload.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now jitsi-transcripts-watch.service jitsi-transcripts-upload.timer

# (prosody module is COPIED, not symlinked: a container bind-mounts it)
# Deploy everything into /opt/jitsi and (re)launch the stack.
deploy: (build) (install-uploader)
    sudo cp prosody/mod_corabea_call_events.lua {{cfg}}/prosody/prosody-plugins-custom/
    sudo cp compose/null-stt.yml {{jitsi}}/null-stt.yml
    cd {{jitsi}} && sudo {{compose}} up -d --remove-orphans

# (Re)launch the stack only.
up:
    cd {{jitsi}} && sudo {{compose}} up -d --remove-orphans
