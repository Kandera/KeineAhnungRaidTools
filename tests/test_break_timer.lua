-- Break timer: payload, copy, slash gate, contain-fit. Isolated load of BreakTimer.lua.
local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
env._brkHandlers = {}
env._brkSent = {}
local KART = {
    L = {
        BREAK_STATUS = "Breaktime %d min until %s",
        SET_BREAK_IMAGES = "Break window pictures",
        DESC_BREAK_IMAGES = "When you start a break, every KART client shows a random picture.",
    },
    UI = {
        RegisterStaticPopup = function() end,
        CreateCard = function() return { SetPoint = function() end, SetSize = function() end } end,
        CreateSettingsCheckbox = function() return { text = {} } end,
        RegisterLocaleRefresher = function() end,
        RegisterStrataFrame = function() end,
        SetPixelBackdrop = function() end,
        ApplyPopupArtwork = function() end,
        ApplyRoundedMask = function() end,
        CreateModernButton = function() return { SetPoint = function() end, SetSize = function() end, SetScript = function() end } end,
    },
    UnitLeads = function() return false end,
    UnitAssists = function() return false end,
    Defaults = { breakShowImages = false },
}
env.KART = KART
env.KART_Settings = { breakShowImages = false }
do
    local realLibStub = LibStub
    local kascStub = {
        RegisterMessage = function(_, token, _, fn) env._brkHandlers[token] = fn end,
        Send = function(_, msg) env._brkSent[#env._brkSent + 1] = msg end,
        Identity = {},
    }
    env.LibStub = setmetatable({}, {
        __index = realLibStub,
        __call = function(_, name, silent)
            if name == "KASC-1.0" then return kascStub end
            return realLibStub(name, silent)
        end,
    })
end
do
    local chunk = assert(loadstring(assert(io.open("BreakTimer.lua", "r"):read("*a")), "@BreakTimer.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
local BT = KART.BT

do
    local s, img = BT.ParsePayload("720:1")
    T.eq(s, 720, "payload seconds")
    T.eq(img, 1, "payload pictures on")
    s, img = BT.ParsePayload("720:0")
    T.eq(img, 0, "payload pictures off")
    s, img = BT.ParsePayload("720:yes")
    T.eq(s, 720, "junk flag still yields duration")
    T.eq(img, 0, "junk flag yields no pictures")
    s, img = BT.ParsePayload("720:2")
    T.eq(s, 720, "non-one flag still yields duration")
    T.eq(img, 0, "non-one flag means no pictures")
    s, img = BT.ParsePayload("0:0")
    T.eq(s, 0, "zero seconds is cancel")
    s, img = BT.ParsePayload("720")
    T.eq(s, 720, "missing flag is still a duration")
    T.eq(img, 0, "missing flag means no pictures")
end

do
    local now = 1785001000
    T.eq(BT.FormatStatus(720, now), "Breaktime 12 min until " .. date("%H:%M", now + 720),
        "status line is minutes plus local clock")
end

do
    local w, h = BT.ContainSize(1024, 1024, 400)
    T.eq(w, 400, "square larger than the cap scales to 400")
    T.eq(h, 400, "square height matches")
    w, h = BT.ContainSize(800, 1200, 400)
    T.eq(h, 400, "portrait longest side is the cap")
    T.eq(w, math.floor(800 * 400 / 1200 + 0.5), "portrait width keeps aspect")
    w, h = BT.ContainSize(200, 200, 400)
    T.eq(w, 200, "small images are not upscaled")
    T.eq(h, 200, "small height stays native")
end

do
    env.BigWigsLoader = {}
    env.DBM = nil
    T.eq(BT.ShouldRegisterSlash(), false, "BigWigs present: KART does not take /break")
    env.BigWigsLoader = nil
    env.DBM = {}
    T.eq(BT.ShouldRegisterSlash(), false, "DBM present: KART does not take /break")
    env.DBM = nil
    T.eq(BT.ShouldRegisterSlash(), true, "neither boss mod: KART owns /break")
end
