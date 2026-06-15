-- mod_corabea_call_events
-- Reports MUC lifecycle events of `appointment-*` rooms to corabea_api so it can
-- track the call lifecycle (start / both-present / end) and remind the operator
-- near the end of the call.
--
-- For each join / leave / room-destroyed on an appointment room we POST a small
-- JSON body to CORABEA_CALL_EVENTS_URL, authenticated out-of-band with the
-- X-Prosody-Secret header (CORABEA_CALL_EVENTS_SECRET). The body carries no secret.
--
-- Role is derived from the occupant's verified JWT `context.user.moderator`
-- claim (corabea_api emits it as a STRING "true"/"false"): moderator -> operator,
-- otherwise -> patient. Token-less / focus (jicofo) occupants are reported as
-- "unknown" and ignored by the backend for presence accounting.

local jid_node = require "util.jid".node;
local json = require "util.json";
local http = require "net.http";
local timer = require "util.timer";
local st = require "util.stanza";
local new_uuid = require "util.uuid".generate;

local API_URL = os.getenv("CORABEA_CALL_EVENTS_URL");
local API_SECRET = os.getenv("CORABEA_CALL_EVENTS_SECRET");
local AUTO_TRANSCRIPTION = (function()
    local v = os.getenv("CORABEA_AUTO_TRANSCRIPTION");
    if v == nil then return true; end
    v = v:lower();
    return not (v == "false" or v == "0" or v == "no" or v == "");
end)();
local ROOM_PREFIX = "appointment-";

if not API_URL or API_URL == "" then
    module:log("warn", "mod_corabea_call_events: CORABEA_CALL_EVENTS_URL not set, module inactive");
    return;
end

-- Interpret the various truthy shapes the moderator flag can take.
local function is_moderator_flag(value)
    if value == true then
        return true;
    end
    if type(value) == "string" then
        local v = value:lower();
        return v == "true" or v == "1" or v == "yes";
    end
    return false;
end

-- Appointment room node (e.g. "appointment-<uuid>") or nil if not an appointment room.
local function appointment_node(room)
    if not room or not room.jid then
        return nil;
    end
    local node = jid_node(room.jid);
    if node and node:sub(1, #ROOM_PREFIX) == ROOM_PREFIX then
        return node;
    end
    return nil;
end

-- Derive role + a stable participant id from the joining session's verified token.
local function role_and_pid(origin, occupant)
    local context_user = origin and origin.jitsi_meet_context_user;
    if context_user then
        local role = is_moderator_flag(context_user.moderator) and "operator" or "patient";
        local pid = context_user.id or (occupant and occupant.nick);
        return role, pid;
    end
    -- No token (focus / anonymous) -> unknown.
    return "unknown", occupant and occupant.nick or nil;
end

-- True if this occupant is the Jigasi transcriber bot (transcriber@hidden...).
local function is_transcriber(occupant)
    local bare = occupant and occupant.bare_jid;
    return bare ~= nil and jid_node(bare) == "transcriber";
end

-- Count human occupants currently in the room. Excludes the focus (jicofo,
-- node "focus") and the transcriber bot; everyone else (operator / patient,
-- all tokened) is a real participant.
local function human_occupant_count(room)
    local count = 0;
    if not room or not room.each_occupant then
        return count;
    end
    for _, occupant in room:each_occupant() do
        local node = occupant.bare_jid and jid_node(occupant.bare_jid);
        if node and node ~= "focus" and node ~= "transcriber" then
            count = count + 1;
        end
    end
    return count;
end

local function post_event(payload)
    local body = json.encode(payload);
    http.request(API_URL, {
        method = "POST",
        body = body,
        headers = {
            ["Content-Type"] = "application/json",
            ["X-Prosody-Secret"] = API_SECRET or "",
        },
    }, function(response_body, code)
        if code and code >= 200 and code < 300 then
            module:log("debug", "corabea_call_events: posted %s for %s (HTTP %s)",
                payload.event, payload.room, tostring(code));
        else
            module:log("warn", "corabea_call_events: POST failed for %s %s (HTTP %s)",
                payload.event, payload.room, tostring(code));
        end
    end);
end

-- Ask Jicofo to invite the transcriber into the room. Replicates the rayo
-- "dial" IQ the web client sends on "Start transcription", so transcription
-- (and thus the WAV recording) starts automatically with no user action.
local function start_transcription(room, from_jid)
    if not AUTO_TRANSCRIPTION then
        return;
    end
    if room.corabea_transcription_started then
        return;
    end
    room.corabea_transcription_started = true;
    local iq = st.iq({
        type = "set",
        id = new_uuid() .. ":sendIQ",
        from = from_jid,
        to = room.jid .. "/focus",
    })
        :tag("dial", {
            xmlns = "urn:xmpp:rayo:1",
            from = "fromnumber",
            to = "jitsi_meet_transcribe",
        })
            :tag("header", {
                xmlns = "urn:xmpp:rayo:1",
                name = "JvbRoomName",
                value = room.jid,
            });
    module:send(iq);
    module:log("info", "corabea: auto-started transcription for %s (from %s)", room.jid, from_jid);
end

-- (Re)start transcription when appropriate: both humans present, the moderator
-- is known, it isn't already running. Deferred a few seconds so occupant
-- affiliations settle and the count reflects the real post-event state (this
-- also avoids restarting at call teardown, when humans are leaving too).
local function arm_transcription(room)
    timer.add_task(3, function()
        local humans = human_occupant_count(room);
        if not room.corabea_transcription_started
            and room.corabea_moderator_jid
            and humans >= 2 then
            start_transcription(room, room.corabea_moderator_jid);
        else
            module:log("info",
                "corabea: arm_transcription skip room=%s started=%s mod_jid=%s humans=%d",
                room.jid,
                tostring(room.corabea_transcription_started),
                tostring(room.corabea_moderator_jid),
                humans);
        end
        return nil;
    end);
end

module:hook("muc-occupant-joined", function(event)
    local node = appointment_node(event.room);
    if not node then
        return;
    end
    local role, pid = role_and_pid(event.origin, event.occupant);
    -- Skip the focus / token-less occupants: the backend ignores them anyway.
    if role == "unknown" then
        return;
    end
    -- Remember the moderator (operator) occupant. Jicofo only honors a
    -- transcription request coming from a moderator, so the auto-start IQ MUST
    -- be sent from this JID, not from whoever happened to join last. Use the
    -- occupant's REAL jid (like mod_jibri_autostart does), not the MUC nick.
    if role == "operator" then
        event.room.corabea_moderator_jid = event.occupant.jid;
    end
    post_event({
        event = "join",
        room = node,
        role = role,
        participant_id = pid,
        occupant_count = human_occupant_count(event.room),
        timestamp = os.time(),
    });
    -- Auto-start transcription whenever the preconditions might now be met:
    -- either we just learned the moderator JID (operator joined late), or we
    -- just reached 2 humans. arm_transcription() defers 3s and re-checks both
    -- conditions, so calling it eagerly on every relevant join is safe and
    -- avoids the bug where a late-joining operator never triggered the dial.
    if event.room.corabea_moderator_jid then
        arm_transcription(event.room);
    end
end);

module:hook("muc-occupant-left", function(event)
    local node = appointment_node(event.room);
    if not node then
        return;
    end
    -- If the transcriber bot itself left while humans are still in the call
    -- (e.g. a brief disconnect/reconnect), clear the guard and re-arm so
    -- transcription restarts and we don't lose the rest of the call. The 3s
    -- deferred re-check means we do NOT restart when the room is actually
    -- emptying at call end.
    if is_transcriber(event.occupant) then
        event.room.corabea_transcription_started = false;
        arm_transcription(event.room);
        return;
    end
    local role, pid = role_and_pid(event.origin, event.occupant);
    -- Skip the focus / token-less occupants: the backend ignores them anyway.
    if role == "unknown" then
        return;
    end
    -- The leaving occupant may still be present in the room table at hook time;
    -- defer the count by a tick so it reflects the post-leave state.
    local room = event.room;
    timer.add_task(0.1, function()
        post_event({
            event = "leave",
            room = node,
            role = role,
            participant_id = pid,
            occupant_count = human_occupant_count(room),
            timestamp = os.time(),
        });
        return nil;
    end);
end);

module:hook("muc-room-destroyed", function(event)
    local node = appointment_node(event.room);
    if not node then
        return;
    end
    post_event({
        event = "room_destroyed",
        room = node,
        role = "unknown",
        participant_id = nil,
        occupant_count = 0,
        timestamp = os.time(),
    });
end);

module:log("info", "mod_corabea_call_events loaded (url=%s auto_transcription=%s)",
    API_URL, tostring(AUTO_TRANSCRIPTION));
