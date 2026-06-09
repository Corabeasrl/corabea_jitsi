# Corabea — minimal "null" STT image for the Jigasi transcriber.
# Speaks the Vosk websocket protocol with empty replies; loads no model.
FROM python:3.12-alpine
RUN pip install --no-cache-dir "websockets==12.0"
COPY server.py /app/server.py
WORKDIR /app
EXPOSE 2700
CMD ["python", "server.py"]
