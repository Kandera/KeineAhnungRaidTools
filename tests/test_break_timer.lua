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

do
    T.truthy(BT.OnStart, "OnStart exists")
    BT.OnStart(720, 0)
    local f = env.KART_BreakFrame or _G.KART_BreakFrame
    -- Isolated CreateFrame stores the name on env if the stub writes _G; also keep BT.frame.
    f = f or BT.frame
    T.truthy(f, "start creates the frame")
    T.eq(f:IsShown(), true, "start shows the frame")
    T.eq(BT.statusText:GetText(), BT.FormatStatus(720, time()), "status uses FormatStatus")
    local special = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "KART_BreakFrame" then special = true end
    end
    T.eq(special, false, "break frame is not in UISpecialFrames")
    BT.OnCancel()
    T.eq(f:IsShown(), false, "cancel hides the frame")
end

do
    BT.OnStart(60, 0)
    BT.OnStart(120, 0)
    T.eq(BT.frame:IsShown(), true, "a second start still has one frame")
    T.eq(BT.statusText:GetText(), BT.FormatStatus(120, time()), "the later duration wins")
    BT.OnCancel()
end

do
    env._lead = false
    env._assist = false
    KART.UnitLeads = function() return env._lead end
    KART.UnitAssists = function() return env._assist end
    local ctx = { sender = "Pug-TarrenMill", shortName = "Pug" }
    T.eq(BT.SenderMayControl(ctx), false, "a raider cannot flip pictures")
    env._lead = true
    T.eq(BT.SenderMayControl(ctx), false, "local lead does not authorize a stranger's BRK")
    local savedUnitName = env.UnitName
    env.UnitName = function(unit)
        if unit == "player" then return "Ann", "TarrenMill" end
        return savedUnitName and savedUnitName(unit)
    end
    ctx = { sender = "Ann-OtherRealm", shortName = "Ann" }
    T.eq(BT.SenderMayControl(ctx), false, "realm mismatch rejects player fallback even when local lead")
    env.UnitName = savedUnitName
end

do
    local snap = KARTTEST.SnapshotRoster()
    KARTTEST.realm = "TarrenMill"
    KARTTEST.SetRaid({ { name = "Ann", leader = true } })
    local savedUnitName = env.UnitName
    env.UnitName = function(unit)
        if unit == "raid1" then return "Ann", nil end
        return savedUnitName and savedUnitName(unit)
    end
    KART.UnitLeads = function(unit) return unit == "raid1" end
    KART.UnitAssists = function() return false end
    local ctx = { sender = "Ann-TarrenMill", shortName = "Ann" }
    T.truthy(BT.SenderMayControl(ctx), "same-realm lead matches when UnitName omits realm")
    env.UnitName = savedUnitName
    KARTTEST.RestoreRoster(snap)
end

do
    local fn = env._brkHandlers.BRK
    T.truthy(fn, "BRK is registered")
    local savedUnitName = env.UnitName
    env.UnitName = function(unit)
        if unit == "player" then return "Ann", "TarrenMill" end
        return savedUnitName and savedUnitName(unit)
    end
    env._lead = true
    fn("0:0", { sender = "Ann-TarrenMill", shortName = "Ann" })
    T.eq(BT.frame:IsShown(), false, "BRK:0 closes")
    fn("180:1", { sender = "Ann-TarrenMill", shortName = "Ann" })
    T.eq(BT.frame:IsShown(), true, "authorized BRK opens")
    T.eq(BT.wantPictures, true, "flag 1 arms pictures")
    env._lead = false
    env._assist = false
    BT.OnCancel()
    fn("180:1", { sender = "Pug-TarrenMill", shortName = "Pug" })
    T.eq(BT.frame:IsShown(), false, "unauthorized BRK is ignored")
    env._lead = true
    fn("180:1", { sender = "Pug-TarrenMill", shortName = "Pug" })
    T.eq(BT.frame:IsShown(), false, "stranger BRK ignored even when local player is lead")
    env.UnitName = savedUnitName
end

do
    BT.OnCancel()
    env._brkSent = {}
    env.IsInGroup = function() return true end
    BT.SendBreak(180, 0)
    T.eq(#env._brkSent, 1, "SendBreak sends BRK in group")
    T.eq(env._brkSent[1], "BRK:180:0", "SendBreak payload")
    T.eq(BT.frame:IsShown(), true, "SendBreak opens the window locally")
    BT.OnCancel()
end

do
    T.truthy(BT.POOL and #BT.POOL >= 1, "the pool lists at least one file after media ships")
    local saved = BT.POOL
    BT.POOL = {}
    T.is_nil(BT.PickImage(), "empty pool picks nothing")
    BT.POOL = saved
end

do
    local saved = BT.POOL
    BT.POOL = {}
    BT.OnStart(720, 1)
    T.truthy(BT.image, "EnsureFrame creates the image texture")
    T.eq(BT.image:IsShown(), false, "empty pool does not show the image")
    T.eq(BT.image:GetTexture(), nil, "empty pool does not set a texture")
    T.eq(BT.frame:IsShown(), true, "text-only window still shows")
    BT.POOL = saved
    BT.OnCancel()
end

do
    for i, entry in ipairs(BT.POOL) do
        T.truthy(entry.file:find("%.png$"), "pool file " .. i .. " includes .png")
        T.truthy(entry.contentW > 0 and entry.contentH > 0, "pool " .. i .. " content size is non-zero")
        T.truthy(entry.texW > 0 and entry.texH > 0, "pool " .. i .. " texture size is non-zero")
    end
    BT.currentImage = { file = "stale.png", contentW = 1, contentH = 1, texW = 1, texH = 1 }
    BT.OnStart(720, 1)
    T.truthy(BT.currentImage and BT.currentImage.file ~= "stale.png", "new start picks a fresh image")
    T.eq(BT.image:IsShown(), true, "pictures on shows the image")
    local tex = BT.image:GetTexture()
    T.truthy(tex and tex:find("%.png"), "texture path includes .png")
    T.truthy(tex and tex:find("media\\break\\"), "texture is under media/break")
    local imgW, imgH = BT.ContainSize(BT.currentImage.contentW, BT.currentImage.contentH, 400)
    T.eq(BT.image:GetWidth(), imgW, "image width is contain-fit")
    T.eq(BT.image:GetHeight(), imgH, "image height is contain-fit")
    T.eq(BT.frame:GetWidth(), math.max(280, imgW + 16), "frame width wraps the image")
    T.eq(BT.frame:GetHeight(), 28 + imgH + 16, "frame height is bar plus image")
    BT.OnStart(720, 0)
    T.eq(BT.image:IsShown(), false, "pictures off hides the image")
    BT.OnStart(720, 1)
    BT.minimized = true
    BT.ApplyLayout()
    T.eq(BT.image:IsShown(), false, "minimized hides the image")
    BT.OnCancel()
end
