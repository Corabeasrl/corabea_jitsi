#!/usr/bin/env python3
"""
Corabea — "null" STT for the Jigasi transcriber.

Jigasi refuses to start without a transcription backend, but Corabea discards the
draft transcript entirely (real transcription runs on a separate Whisper server
reading the recorded WAVs from S3). So we don't need an STT that works — only one
that speaks the Vosk websocket protocol well enough to keep the transcriber
session alive so it records audio (RECORD_AUDIO).

This server accepts the websocket, consumes the config + audio frames, and replies
with EMPTY results in Vosk's shape. No model is loaded, so CPU and RAM are ~zero
and it scales to many concurrent calls.
"""
import asyncio
import json
import websockets


# `path` kept optional so the handler works on both old (8.x: handler(ws, path))
# and new (>=11: handler(ws)) websockets APIs.
async def handle(websocket, path=None):
    async for message in websocket:
        if isinstance(message, (bytes, bytearray)):
            # An audio chunk. Real Vosk replies with a partial/result; we just
            # acknowledge with an empty partial.
            await websocket.send('{"partial": ""}')
        else:
            # A control/text message: the initial {"config": {...}} or {"eof": 1}.
            try:
                obj = json.loads(message)
            except Exception:
                obj = {}
            if "eof" in obj:
                await websocket.send('{"text": ""}')
                break
            else:
                await websocket.send('{"partial": ""}')


async def main():
    async with websockets.serve(handle, "0.0.0.0", 2700, max_size=None):
        print("null-stt listening on :2700", flush=True)
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
