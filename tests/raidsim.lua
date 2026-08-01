-- A simulated raid: several real KART clients in one Lua process, exchanging real addon messages.
--
-- Everything else in tests/ checks one function at a time, usually by lifting it out of the source.
-- That has caught real bugs, but it cannot catch the ones that actually cost raid nights, because
-- those live BETWEEN clients: a session flag that is true on nineteen machines and false on the
-- twentieth, a config nobody broadcast, a vote that arrives before the roll it belongs to. Those
-- only appear when more than one client exists.
--
-- So this loads the addon files the way WoW does -- as chunks called with (addonName, KART) -- once
-- per simulated client, each in its own environment, and routes C_ChatInfo.SendAddonMessage between
-- them -- including back to the sender, exactly as the game does it (see the wire below). What the
-- tests then assert is the thing the maintainer actually cares about: an item drops, EVERY client
-- can see it and vote, and the council sees those votes.
--
-- Deliberately not simulated: rendering, taint, and Blizzard's own loot roll. Those need a client.
-- Every raid-night failure so far has been state and messages, which is what this covers.

local RaidSim = {}

-- Files each client loads, in .toc order. Settings and the main window are left out: they build the
-- options UI and pull in MainFrame, and nothing in the loot flow needs them.
local CLIENT_FILES = {
    "Locales/enUS.lua",
    "Locales/deDE.lua",
    "Utils.lua",
    "LootHistory.lua",
    "LootCouncil.lua",
    "LootCouncilOfficerNotes.lua",
    "LootCouncilRelevance.lua",
    "LootCouncilVote.lua",
    "LootCouncilTrade.lua",
    "LootCouncilPanel.lua",
    -- Loads after the panel, exactly as the .toc orders it: the panel is what asks it for a
    -- gain%, so a client without it would never exercise that call at all.
    "Droptimizer.lua",
    "BuffChecker.lua",
}

local LIB_FILES = {
    "Libs/KAUtil-1.0/KAUtil-1.0.lua",
    "Libs/KAGS-1.0/KAGS-1.0.lua",
    "Libs/KASC-1.0/KASC-1.0.lua",
    "Libs/KAUI-1.0/KAUI-1.0.lua",
}

local function slurp(path)
    local f = assert(io.open(path, "r"), "raidsim: cannot open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

-- Loads one file as WoW would: a chunk called with the addon name and the addon's shared table,
-- running in this client's environment so its globals (KART_Settings and friends) stay its own.
local function loadInto(client, path)
    local chunk = assert(loadstring(slurp(path), "@" .. path))
    setfenv(chunk, client.env)
    local ok, err = pcall(chunk, "KeineAhnungRaidTools", client.KART)
    if not ok then
        error("raidsim: " .. client.name .. " failed loading " .. path .. ": " .. tostring(err), 0)
    end
end

-- The whole roster, shared by every client, plus which client is currently executing. The WoW stubs
-- resolve "player" through this, so UnitName("player") answers differently depending on whose code
-- is running -- which is the entire point.
RaidSim.active = nil

-- The SavedVariables a /reload keeps. Everything else about a client -- every table in KART.LC, the
-- session flag, the tracked rolls -- is runtime state and starts empty again, which is exactly the
-- asymmetry that makes a reloading lootmaster dangerous.
local SAVED_VARIABLES = {
    "KART_Settings", "KART_LootHistory", "KART_LootHistoryClearedAt", "KART_LCTrades",
    "KART_LCOfficerNotes", "KART_Profiles", "KART_PlayerCache", "KART_LCSession",
}

-- The member table is copied, not referenced: it is what the roster stubs answer from, so a test
-- that promotes someone to raid leader would otherwise be editing the shared fixture and every later
-- test would inherit it.
local function NewClient(sim, def)
    local m = {}
    for k, v in pairs(def) do m[k] = v end
    return { name = m.name, realm = m.realm, guid = m.guid, sim = sim, member = m }
end

-- Rebuilds the roster the stubs answer from, in sim.clients order: raid1..raidN, matching
-- KAUtil.EachGroupUnit's scheme. Unit tokens are positional in WoW too, so someone leaving really
-- does renumber everyone behind them.
local function Reindex(sim)
    local members = {}
    for i, c in ipairs(sim.clients) do
        c.unit = "raid" .. i
        members[i] = c.member
    end
    KARTTEST.SetRaid(members)
end

-- Brings one client up from nothing: its own environment, its own library instances, the addon
-- files, and the defaults Core.lua would have applied. `saved` carries SavedVariables across a
-- /reload; leave it nil for a client logging in fresh.
local function Boot(client, saved)
    local m = client.member

    -- Own environment: reads fall through to the shared stubs, writes stay here. That is what
    -- keeps KART_Settings, and every SavedVariable, per client.
    client.env = setmetatable({}, { __index = _G })
    -- Every SavedVariable the loaded files touch, per client. Core.lua creates these on
    -- ADDON_LOADED in the game; the harness does not load Core.lua, so they are created here.
    saved = saved or {}
    client.env.KART_Settings       = saved.KART_Settings or {}
    client.env.KART_LootHistory    = saved.KART_LootHistory or {}
    client.env.KART_LootHistoryClearedAt = saved.KART_LootHistoryClearedAt
    client.env.KART_LCTrades       = saved.KART_LCTrades or { pending = {}, owed = {} }
    client.env.KART_LCSession      = saved.KART_LCSession or {}
    client.env.KART_LCOfficerNotes = saved.KART_LCOfficerNotes or {}
    client.env.KART_Profiles       = saved.KART_Profiles or {}
    client.env.KART_WoWUtilsCache  = {}
    -- Blizzard's dialog registry is a global table, and every client registers its own handlers
    -- into it under the same names. Shared, the last client to load would own every confirm
    -- dialog in the raid -- accepting a reassign would run somebody else's assignment.
    client.env.StaticPopupDialogs  = {}
    -- Nickname support is per client, not per raid. `nsrt = false` on a member models the real
    -- and common case of one person missing Northern Sky, or having its global nickname sharing
    -- switched off: a false here shadows the shared NSAPI through this client's environment, so
    -- only they go blind. That asymmetry is the whole point -- it is what silently cost a raid
    -- its rolls before 3.1.0.
    if m.nsrt == false then client.env.NSAPI = false end

    client.KART = { LC = {} }
    client.env.KART = client.KART

    -- Everything this client is about to create belongs to it, LIBRARIES INCLUDED, so
    -- KARTTEST.FireEvent can reach one client's handlers and nobody else's -- and, just as
    -- important, so the next boot under this name can drop them again. A reload creates a whole new
    -- set; leaving the old ones registered would have a reloaded client hear every event twice.
    --
    -- Set before the libraries, not after: KASC registers a CHAT_MSG_ADDON frame of its own, and
    -- with the owner still nil at that point nothing could ever match it for removal. Every boot
    -- then left one behind, and each of those pins the whole client environment -- ten loaded addon
    -- chunks and every table in them -- so a long soak grew by about 3 MB per raid and ran the
    -- process out of memory around seed 8000. Measured, not guessed: the START_LOOT_ROLL
    -- registrations stayed correctly at five while the CHAT_MSG_ADDON ones climbed one per boot.
    KARTTEST.frameOwner = client.name
    for i = #KARTTEST.eventFrames, 1, -1 do
        if KARTTEST.eventFrames[i].owner == client.name then table.remove(KARTTEST.eventFrames, i) end
    end

    -- Fresh library instances per client. LibStub hands out singletons, so without clearing its
    -- registry every client would share one KASC -- one handler table, one identity cache, and
    -- no way to tell two clients apart.
    wipe(LibStub.libs)
    wipe(LibStub.minors)
    for _, path in ipairs(LIB_FILES) do loadInto(client, path) end

    client.KASC  = client.env.LibStub("KASC-1.0")
    client.KAUtil = client.env.LibStub("KAUtil-1.0")
    client.KART.UI = client.env.LibStub("KAUI-1.0")

    -- The two things Core.lua does to KASC on ADDON_LOADED, and both matter.
    --
    -- Init sets the message prefix; without it every KASC:Send goes out with a nil prefix, which in
    -- the game means nothing is received at all.
    --
    -- AttachCache is the one that quietly changed what the tests could see: with no cache attached,
    -- KASC.Identity's persistent-name lookup is a no-op, so the branch that resolves somebody who is
    -- NOT currently in the roster never ran -- and neither did the hazard it carries, a stale cache
    -- entry resolving a departed player's name onto their old GUID. A whole raid's worth of identity
    -- behaviour was being tested in a world where the cache did not exist.
    client.KASC:Init("KART")
    client.env.KART_PlayerCache = saved.KART_PlayerCache or {}
    client.KASC:AttachCache(client.env.KART_PlayerCache)

    RaidSim.active = client
    for _, path in ipairs(CLIENT_FILES) do loadInto(client, path) end

    -- KART.L is assembled by Core.lua, which the harness does not load: English first, then the
    -- German file laid over it, exactly as Core does. A client's language is part of its
    -- identity here because it changes what its DEFAULT vote buttons are called -- "Other"
    -- against "Sonstiges" -- so two clients that never received a raid config disagree about
    -- what the same vote index means. Mixed languages are normal in this guild.
    client.locale = m.locale or "enUS"
    client.KART.L = {}
    for k, v in pairs(client.KART.L_enUS) do client.KART.L[k] = v end
    if client.locale == "deDE" then
        for k, v in pairs(client.KART.L_deDE or {}) do client.KART.L[k] = v end
    end

    -- Defaults, the way Core.lua's ADDON_LOADED applies them -- including localising the vote
    -- buttons BEFORE the merge, which is what makes a German and an English client start from
    -- different words when no raid config has reached them.
    client.KART.Defaults.lcButtonLabels = client.KART.L.LC_DEFAULT_BUTTONS
    client.KAUtil.MergeDefaults(client.env.KART_Settings, client.KART.Defaults)
    client.env.KART_Settings.lcModuleEnabled = true

    -- Outstanding trade obligations from before the reload. Core.lua restores these on ADDON_LOADED,
    -- and leaving it out meant RaidSim.Reload modelled a reload WITHOUT the one step that brings
    -- loot-flow state back -- so anything about who still owes whom an item across a relog was being
    -- measured against a client that had deliberately forgotten.
    RaidSim.active = client
    if client.KART.LC.Trade and client.KART.LC.Trade.RestorePersistedTrades then
        pcall(client.KART.LC.Trade.RestorePersistedTrades)
    end

    -- The items that were still on the table, in the same order Core.lua restores them: trades
    -- first, then the tracked rolls (B81). Leaving this out modelled a reload that deliberately
    -- forgets the distribution it was in the middle of.
    if client.KART.LC.RestoreSessionSnapshot then
        pcall(client.KART.LC.RestoreSessionSnapshot)
    end

    RaidSim.active = nil
    KARTTEST.frameOwner = nil
    return client
end

function RaidSim.New(members)
    local sim = { clients = {}, byName = {}, log = {} }
    for i, m in ipairs(members) do
        sim.clients[i] = NewClient(sim, m)
        sim.byName[m.name] = sim.clients[i]
    end
    Reindex(sim)
    for _, client in ipairs(sim.clients) do Boot(client) end
    return sim
end

-- Someone logs in, or ports in from the other split raid, partway through the evening. They arrive
-- knowing nothing: no config, no session, no idea a boss just died.
function RaidSim.Join(sim, m)
    local client = NewClient(sim, m)
    sim.clients[#sim.clients + 1] = client
    sim.byName[m.name] = client
    Reindex(sim)
    return Boot(client)
end

-- Someone ports out to the other raid. They stop receiving the group's messages immediately, which
-- is what removing them from sim.clients does. The returned client is kept only so a test can read
-- the state they left with -- their unit token is gone, so their own code must not be driven again.
function RaidSim.Leave(sim, name)
    local client = sim.byName[name]
    for i, c in ipairs(sim.clients) do
        if c == client then table.remove(sim.clients, i) break end
    end
    sim.byName[name] = nil

    -- A raid is never left without a leader. When the leader drops out the server hands the role to
    -- somebody else immediately, and there is no moment in the game where a group has nobody in
    -- charge -- so the harness must not produce one either.
    --
    -- It used to, and it cost real time: with no lootmaster configured the raid leader stands in
    -- (see LC.IsLootOwner), so a leaderless raid has no loot owner at all, nobody broadcasts
    -- LC_START, and every client sits there with an item Blizzard rolled and no vote window. That
    -- looked exactly like a protocol bug and was written up as one -- it was this line missing.
    -- Ten of the thirteen breaks in a 3000-run soak were this.
    if client and client.member and client.member.leader and sim.clients[1] then
        RaidSim.Promote(sim, sim.clients[1].name)
    end

    Reindex(sim)
    return client
end

-- Raid lead passes to someone else -- which is what happens the moment the leader ports out to the
-- other split raid, and the moment ownership has to fall back to somebody.
function RaidSim.Promote(sim, name)
    for _, c in ipairs(sim.clients) do c.member.leader = (c.name == name) end
    Reindex(sim)
    return sim.byName[name]
end

-- /reload, a disconnect, or a character swap that keeps the same account settings. SavedVariables
-- survive; every scrap of runtime state does not. The returned client REPLACES the old one in the
-- sim, so a test holding the previous reference is holding a corpse -- deliberately, since that is
-- what makes it obvious when an assertion is looking at pre-reload state.
function RaidSim.Reload(sim, name)
    local old = sim.byName[name]
    -- PLAYER_LOGOUT, which the game raises before SavedVariables are written -- for a /reload
    -- as much as for a logout. Without it a test would be measuring a client that crashed,
    -- not one that reloaded (B81).
    if old.KART.LC.SaveSessionSnapshot then
        RaidSim.As(old, function() pcall(old.KART.LC.SaveSessionSnapshot) end)
    end
    local saved = {}
    for _, key in ipairs(SAVED_VARIABLES) do saved[key] = old.env[key] end

    local client = NewClient(sim, old.member)
    for i, c in ipairs(sim.clients) do
        if c == old then sim.clients[i] = client break end
    end
    sim.byName[name] = client
    Reindex(sim)
    return Boot(client, saved)
end

-- PLAYER_ENTERING_WORLD, as Core.lua handles it (see its LC.CheckRaidJoin call). Kept apart from
-- Reload rather than folded into it, because the two are separate moments and one test wants the
-- gap between them -- but in the game a reload is ALWAYS followed by this, within a second. A test
-- that reloads and then leaves the client sitting there is modelling a client that never announced
-- itself, which cannot happen, and it will blame the addon for the silence.
function RaidSim.EnterWorld(sim, name)
    local client = sim.byName[name]
    if not client then return nil end
    RaidSim.As(client, function() client.KART.LC.CheckRaidJoin() end)
    return client
end

-- GROUP_ROSTER_UPDATE, as Core.lua routes it: every client in the group runs its own handler, in no
-- particular order. Everything Loot Council recovery hangs off is in here -- the state request, the
-- config re-broadcast, the raid-exit confirmation -- so this is the single event a test uses to say
-- "the roster changed and the addon noticed".
function RaidSim.RosterUpdate(sim)
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KART.LC.CheckRaidJoin()
            if c.KART.LC.RetryPendingResolutionsThrottled then c.KART.LC.RetryPendingResolutionsThrottled() end
            if c.KART.LC.RetryPendingConfigThrottled then c.KART.LC.RetryPendingConfigThrottled() end
        end)
    end
end

-- The stubs reach back through this for anything that lives in a client's own environment rather
-- than in the shared globals -- currently the dialog registry.
function KARTTEST.PopupRegistry()
    return RaidSim.active and RaidSim.active.env.StaticPopupDialogs or _G.StaticPopupDialogs
end

-- Delayed work runs as whoever scheduled it (see the C_Timer stub). Without this a raid-exit
-- confirmation, three seconds after the client that started it stopped executing, re-read the group
-- as nobody in particular -- and cancelled itself every time.
function KARTTEST.CaptureContext()
    return { client = RaidSim.active, unit = KARTTEST.activeUnit }
end

function KARTTEST.RestoreContext(ctx)
    local prev = { client = RaidSim.active, unit = KARTTEST.activeUnit }
    RaidSim.active     = ctx and ctx.client or nil
    KARTTEST.activeUnit = ctx and ctx.unit or nil
    return prev
end

-- Runs fn with `client` as the executing client, so the stubs resolve "player" to them.
--
-- Depth is tracked because the echo (see the wire below) must land AFTER the sending client has
-- finished what it was doing, never in the middle of it -- so the queue is drained only when
-- control comes back out to the test.
local asDepth = 0
function RaidSim.As(client, fn, ...)
    local prevClient, prevUnit = RaidSim.active, KARTTEST.activeUnit
    local prevOwner = KARTTEST.frameOwner
    RaidSim.active, KARTTEST.activeUnit = client, client and client.unit or nil
    -- So KARTTEST.FireEvent reaches THIS client's frames. Same reason activeUnit exists: an
    -- event is delivered to one client's handlers, not to the whole raid's at once.
    KARTTEST.frameOwner = client and client.name or nil
    asDepth = asDepth + 1
    local results = { pcall(fn, ...) }
    asDepth = asDepth - 1
    RaidSim.active, KARTTEST.activeUnit = prevClient, prevUnit
    KARTTEST.frameOwner = prevOwner
    if asDepth == 0 and KARTTEST.FlushEcho then KARTTEST.FlushEcho() end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- The wire.
--
-- It used to encode the opposite of the truth: "a sender never receives its own addon message".
-- Measured in a live client on 2026-07-30, on GUILD and on PARTY, the sender DOES receive it --
-- CHAT_MSG_ADDON fires on the sender too, with their own realm-qualified name as the sender, and
-- KASC's dispatcher has no self-filter, so the message runs through the sender's own handler like
-- anybody else's. Every "the sender must also do this itself" compensation in the addon therefore
-- runs a second time on the echo, and whatever is not repeatable breaks there.
--
-- The echo is queued rather than delivered inline: a real one comes back over the server, so it
-- can never land in the middle of the sending function. Delivering it inline would let a handler
-- observe its own sender's half-finished state, which is a failure mode the game cannot produce.
function RaidSim.Install(sim)
    sim.echoQueue = {}

    -- Drains the echo queue. Delivering an echo can send more messages, which queue more echoes,
    -- so this loops -- with a cap, because a handler that answers its own echo would otherwise
    -- spin here forever, and that is a bug worth failing loudly on rather than hanging on.
    local flushing = false
    function KARTTEST.FlushEcho()
        if flushing then return end
        flushing = true
        local rounds = 0
        while #sim.echoQueue > 0 do
            rounds = rounds + 1
            if rounds > 200 then
                flushing = false
                error("raidsim: echo storm -- a handler keeps answering its own message", 0)
            end
            local pending = sim.echoQueue
            sim.echoQueue = {}
            for _, e in ipairs(pending) do
                RaidSim.As(e.to, function() e.to.KASC.Dispatch(e.msg, e.channel, e.sender) end)
            end
        end
        flushing = false
    end

    _G.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
        local from = RaidSim.active
        if not from then error("raidsim: a message was sent with no active client", 0) end
        sim.log[#sim.log + 1] = { from = from.name, msg = msg, channel = channel, target = target }
        -- The transport caps a payload at 255 bytes and drops anything longer without telling the
        -- sender. The addon carries three separate guards against that cap; none of them was
        -- reachable from a harness that delivered a message of any length.
        if #msg > 255 then
            sim.oversized = sim.oversized or {}
            sim.oversized[#sim.oversized + 1] = { from = from.name, bytes = #msg, msg = msg }
            return
        end
        -- A message that leaves but never lands. Blizzard's chat rate limiter drops the overflow
        -- SILENTLY and SendAddonMessage's return code is discarded, so the sender cannot tell -- and
        -- an addon whose recovery depends on one unacknowledged message has no way back. Anything
        -- important enough to lose has to be tested against losing it.
        for token in pairs(sim.blackholed or {}) do
            if msg:sub(1, #token) == token then return end
        end
        -- HELD, not dropped: parked until RaidSim.Release, then delivered in send order.
        --
        -- Blackhole models a message that is lost; this models one that is merely SLOW, and the two
        -- are not interchangeable. Two clients acting on the same thing before either has heard from
        -- the other -- two council members awarding one item at the same moment (B35) -- cannot be
        -- built out of drops at all: the harness delivers to peers immediately, so the second client
        -- always sees the first one's decision and takes a different path entirely.
        for token in pairs(sim.held or {}) do
            if msg:sub(1, #token) == token then
                sim.heldQueue[#sim.heldQueue + 1] =
                    { prefix = prefix, msg = msg, channel = channel, target = target, from = from }
                return
            end
        end
        local sender = from.name .. "-" .. from.realm
        -- The sender's own copy. A whisper only comes back when it was addressed to the sender
        -- themselves; anything sent to the group always does.
        if channel ~= "WHISPER" or target == from.name
                                or target == from.name .. "-" .. from.realm then
            sim.echoQueue[#sim.echoQueue + 1] =
                { to = from, msg = msg, channel = channel, sender = sender }
        end
        for _, to in ipairs(sim.clients) do
            -- A whisper reaches its target and nobody else. `target == sender` used to be accepted
            -- here as well, which delivered a whisper addressed to the SENDER'S OWN name to every
            -- peer -- so a reply sent to the wrong target still reached the right one, and a bug
            -- where nobody in the game receives the answer looked like a pass.
            if to ~= from and (channel ~= "WHISPER" or target == to.name
                               or target == to.name .. "-" .. to.realm) then
                RaidSim.As(to, function() to.KASC.Dispatch(msg, channel, sender) end)
            end
        end
    end
end

-- Every message sent so far whose text starts with `token`, oldest first.
function RaidSim.Sent(sim, token)
    local out = {}
    for _, e in ipairs(sim.log) do
        if e.msg:sub(1, #token) == token then out[#out + 1] = e end
    end
    return out
end

function RaidSim.ClearLog(sim) sim.log = {} end

-- Messages starting with `token` are sent but never delivered, until Deliver puts them back.
function RaidSim.Blackhole(sim, token)
    sim.blackholed = sim.blackholed or {}
    sim.blackholed[token] = true
end

function RaidSim.Deliver(sim, token)
    if sim.blackholed then sim.blackholed[token] = nil end
end

-- Holds every message whose token matches, instead of dropping it. See the wire above for why this
-- is not the same tool as Blackhole.
function RaidSim.Hold(sim, token)
    sim.held = sim.held or {}
    sim.held[token] = true
    sim.heldQueue = sim.heldQueue or {}
end

-- Lets them go, in send order, as the client that sent each one. Returns how many were released.
function RaidSim.Release(sim, token)
    if sim.held then sim.held[token] = nil end
    local queue = sim.heldQueue or {}
    sim.heldQueue = {}
    local n = 0
    for _, m in ipairs(queue) do
        if m.msg:sub(1, #token) == token then
            n = n + 1
            RaidSim.As(m.from, function()
                _G.C_ChatInfo.SendAddonMessage(m.prefix, m.msg, m.channel, m.target)
            end)
        else
            sim.heldQueue[#sim.heldQueue + 1] = m
        end
    end
    return n
end

return RaidSim
