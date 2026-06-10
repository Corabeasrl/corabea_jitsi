FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ffmpeg inotify-tools ca-certificates curl \
    && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc \
    && apt-get purge -y curl && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY upload.sh watch.sh run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/upload.sh /usr/local/bin/watch.sh /usr/local/bin/run.sh

ENV TRANSCRIPTS_DIR=/transcripts \
    UPLOAD=/usr/local/bin/upload.sh \
    WATCH=/usr/local/bin/watch.sh \
    MC=mc \
    LOG=/dev/stdout \
    OPUS_BITRATE=32k

CMD ["/usr/local/bin/run.sh"]
