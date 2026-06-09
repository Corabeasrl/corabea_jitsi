# corabea_jitsi

Custom layer on top of **docker-jitsi-meet**: auto-records appointment audio and
uploads it to S3.

## Quickstart (new server)

```bash
git clone <repo> /home/ubuntu/corabea_jitsi
cd /home/ubuntu/corabea_jitsi

just install-jitsi
just deploy
```

Open `https://<your-domain>` to check.
