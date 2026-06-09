-- mod_token_moderation
-- Makes the JWT `context.user.moderator` claim the single source of truth for
-- who is a room moderator (MUC "owner"):
--   * On room creation we wrap set_affiliation so ONLY this plugin (actor
--     "token_plugin") may change affiliations. This stops Prosody/Jicofo from
--     auto-granting the room creator "owner".
--   * When an occupant joins, we read the verified token context and grant
--     "owner" only if moderator is truthy, otherwise "member".
--
-- NOTE: corabea_api emits the moderator claim as a STRING ("true"/"false"),
-- so is_moderator_flag accepts booleans AND the strings "true"/"1"/"yes".

local jid_bare = require "util.jid".bare;

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

local function setupAffiliation(room, origin, stanza)
    if not origin.auth_token then
        return;
    end

    local context_user = origin.jitsi_meet_context_user;
    local actor_jid = jid_bare(stanza.attr.from);
    local affiliation = "member";
    if context_user and is_moderator_flag(context_user.moderator) then
        affiliation = "owner";
    end

    -- Use the privileged actor so our own wrapper lets it through.
    room:set_affiliation("token_plugin", actor_jid, affiliation);
end

-- Lock down affiliation changes on every new room.
module:hook("muc-room-pre-create", function(event)
    local room = event.room;
    local _set_affiliation = room.set_affiliation;
    room.set_affiliation = function(self, actor, occupant_jid, affiliation, reason, data)
        if actor == "token_plugin" then
            return _set_affiliation(self, true, occupant_jid, affiliation, reason, data);
        end
        -- Reject any other attempt to (re)assign affiliations (e.g. auto-owner).
        return nil, "modify", "not-acceptable";
    end;
end, 100);

-- Apply the token-derived affiliation as each participant joins.
module:hook("muc-occupant-joined", function(event)
    setupAffiliation(event.room, event.origin, event.stanza);
end);

module:log("info", "mod_token_moderation loaded");
