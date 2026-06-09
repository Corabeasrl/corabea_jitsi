jitsi         := "/opt/jitsi"
cfg           := jitsi / ".jitsi-meet-cfg"
jitsi_version := "stable-10978"
compose       := "docker compose -f docker-compose.yml -f transcriber.yml -f corabea.yml"

install-jitsi:
    sudo mkdir -p {{jitsi}}
    sudo chown -R "$(id -un):$(id -gn)" {{jitsi}}
    curl -fsSL https://github.com/jitsi/docker-jitsi-meet/archive/refs/tags/{{jitsi_version}}.tar.gz | tar -xz --strip-components=1 -C {{jitsi}}
    test -f {{jitsi}}/.env || (cp .env.example {{jitsi}}/.env && cd {{jitsi}} && ./gen-passwords.sh)
    @echo "Now fill the <PLACEHOLDER> values in {{jitsi}}/.env (domain, IP, JWT/S3/events secrets) — passwords are already generated — then: just deploy"

build:
    docker build -t corabea/null-stt:latest null-stt

install-uploader:
    command -v inotifywait >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y inotify-tools)
    mkdir -p {{jitsi}}/transcripts
    test -x {{jitsi}}/transcripts/mc || (curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o {{jitsi}}/transcripts/mc && chmod +x {{jitsi}}/transcripts/mc)
    cp uploader/upload.sh uploader/watch.sh {{jitsi}}/transcripts/
    chmod +x {{jitsi}}/transcripts/upload.sh {{jitsi}}/transcripts/watch.sh
    cp uploader/jitsi-transcripts-watch.service uploader/jitsi-transcripts-upload.service uploader/jitsi-transcripts-upload.timer {{jitsi}}/transcripts/
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-watch.service /etc/systemd/system/jitsi-transcripts-watch.service
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-upload.service /etc/systemd/system/jitsi-transcripts-upload.service
    sudo ln -sf {{jitsi}}/transcripts/jitsi-transcripts-upload.timer /etc/systemd/system/jitsi-transcripts-upload.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now jitsi-transcripts-watch.service jitsi-transcripts-upload.timer

deploy: (build) (install-uploader)
    sudo mkdir -p {{cfg}}/prosody/prosody-plugins-custom {{cfg}}/web
    sudo cp prosody/mod_corabea_call_events.lua prosody/mod_token_moderation.lua {{cfg}}/prosody/prosody-plugins-custom/
    sudo cp web/corabea-logo.png web/custom-head.html web/custom-title.html web/custom-config.js web/custom-interface_config.js {{cfg}}/web/
    cp compose/corabea.yml {{jitsi}}/corabea.yml
    cd {{jitsi}} && {{compose}} up -d --remove-orphans
    timeout 120 sh -c 'until docker logs jitsi-prosody-1 2>&1 | grep -q "All users registered"; do sleep 2; done'
    docker restart jitsi-transcriber-1

up:
    cd {{jitsi}} && {{compose}} up -d --remove-orphans
