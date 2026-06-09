import asyncio
import json
import websockets


async def handle(websocket, path=None):
    async for message in websocket:
        if isinstance(message, (bytes, bytearray)):
            await websocket.send('{"partial": ""}')
        else:
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
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
