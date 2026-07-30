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
-- them. A message never comes back to its sender, exactly as in the game. What the tests then assert
-- is the thing the maintainer actually cares about: an item drops, EVERY client can see it and vote,
-- and the council sees those votes.
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
    "KART_Settings", "KART_LootHistory", "KART_LCTrades",
    "KART_LCOfficerNotes", "KART_Profiles", "KART_EquipCache",
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
    client.env.KART_LCTrades       = saved.KART_LCTrades or { pending = {}, owed = {} }
    client.env.KART_LCOfficerNotes = saved.KART_LCOfficerNotes or {}
    client.env.KART_Profiles       = saved.KART_Profiles or {}
    client.env.KART_EquipCache     = saved.KART_EquipCache or {}
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

    -- Fresh library instances per client. LibStub hands out singletons, so without clearing its
    -- registry every client would share one KASC -- one handler table, one identity cache, and
    -- no way to tell two clients apart.
    wipe(LibStub.libs)
    wipe(LibStub.minors)
    for _, path in ipairs(LIB_FILES) do loadInto(client, path) end

    client.KASC  = client.env.LibStub("KASC-1.0")
    client.KAUtil = client.env.LibStub("KAUtil-1.0")
    client.KART.UI = client.env.LibStub("KAUI-1.0")

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

    RaidSim.active = nil
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
function RaidSim.As(client, fn, ...)
    local prevClient, prevUnit = RaidSim.active, KARTTEST.activeUnit
    RaidSim.active, KARTTEST.activeUnit = client, client and client.unit or nil
    local results = { pcall(fn, ...) }
    RaidSim.active, KARTTEST.activeUnit = prevClient, prevUnit
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- The wire. One rule matters more than any other here and it is the source of a whole family of
-- real bugs: a sender never receives its own addon message. Anything the sender needs to do to its
-- own state, it must do itself -- and every time the addon forgot that, one client ended up
-- disagreeing with the other nineteen.
function RaidSim.Install(sim)
    _G.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
        local from = RaidSim.active
        if not from then error("raidsim: a message was sent with no active client", 0) end
        sim.log[#sim.log + 1] = { from = from.name, msg = msg, channel = channel, target = target }
        -- A message that leaves but never lands. Blizzard's chat rate limiter drops the overflow
        -- SILENTLY and SendAddonMessage's return code is discarded, so the sender cannot tell -- and
        -- an addon whose recovery depends on one unacknowledged message has no way back. Anything
        -- important enough to lose has to be tested against losing it.
        for token in pairs(sim.blackholed or {}) do
            if msg:sub(1, #token) == token then return end
        end
        local sender = from.name .. "-" .. from.realm
        for _, to in ipairs(sim.clients) do
            if to ~= from and (channel ~= "WHISPER" or target == sender or target == to.name
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

return RaidSim
