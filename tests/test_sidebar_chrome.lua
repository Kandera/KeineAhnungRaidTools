-- Sidebar chrome helpers in Utils.lua: session Edit Mode and link copy.
local env = setmetatable({}, { __index = _G })
local KART = { L = { LINK_COPY_TITLE = "Copy this link (Ctrl+C)", BTN_CLOSE = "Close" } }
env.KART = KART

local chunk = assert(loadstring(assert(io.open("Utils.lua", "r")):read("*a"), "@Utils.lua"))
setfenv(chunk, env)
chunk("KeineAhnungRaidTools", KART)

do
    T.truthy(not KART.IsEditModeActive(), "edit mode starts off each session")
    KART.SetEditModeActive(true)
    T.truthy(KART.IsEditModeActive(), "edit mode can be turned on")
    T.truthy(KART.EditModeDim and KART.EditModeDim:IsShown(), "turning on shows the dim overlay")
    T.truthy(KART.EditModeBanner and KART.EditModeBanner:IsShown(), "and the done banner")
    T.truthy(KART.BtnEditModeDone, "the banner has a Done button")
    KART.SetEditModeActive(true)
    T.truthy(KART.IsEditModeActive(), "turning on twice is a no-op")
    KART.BtnEditModeDone:GetScript("OnClick")(KART.BtnEditModeDone)
    T.truthy(not KART.IsEditModeActive(), "Done leaves edit mode")
    T.truthy(not KART.EditModeDim:IsShown(), "and hides the overlay")
end

do
    KARTTEST.inCombat = true
    KART.SetEditModeActive(true)
    T.truthy(not KART.IsEditModeActive(), "combat refuses to enter edit mode")
    KARTTEST.inCombat = false
    KART.SetEditModeActive(true)
    KARTTEST.inCombat = true
    KART.SetEditModeActive(false)
    T.truthy(not KART.IsEditModeActive(), "combat still allows leaving")
    KARTTEST.inCombat = false
end

do
    KARTTEST.clipboard = nil
    _G.CopyToClipboard = function(text) KARTTEST.clipboard = text end
    KART.L.LINK_COPY_TITLE = "Copy this link (Ctrl+C)"
    KART.L.BTN_CLOSE = "Close"
    KART.CopyLink("https://example.test/kart")
    T.eq(KARTTEST.clipboard, nil, "CopyLink does not call protected CopyToClipboard")
    T.truthy(KART.UI.inputDialog and KART.UI.inputDialog:IsShown(),
        "CopyLink opens a dialog with the URL")
    T.eq(KART.UI.inputDialog.editBox:GetText(), "https://example.test/kart",
        "and the box holds the link")
    KART.UI.inputDialog:Hide()
end

do
    T.truthy(type(KART.InGameChangelog) == "table", "in-game changelog table exists")
    T.truthy(#KART.InGameChangelog >= 2, "changelog covers unreleased and a shipped version")
    T.eq(KART.InGameChangelog[1].version, "Unreleased", "first block is unreleased")
    T.truthy(KART.InGameChangelog[1].entries[1]:find("Tonight strip", 1, true),
        "in-game unreleased list starts with the current polish")
    local lead, rest = KART.ParseChangelogLine("**Lead** rest of the line")
    T.eq(lead, "Lead", "changelog lead is the starred span")
    T.eq(rest, "rest of the line", "and the note is everything after it")
    local plain, empty = KART.ParseChangelogLine("plain")
    T.eq(plain, "plain", "a line without stars is all lead")
    T.eq(empty, "", "with no note")
    local _, punct = KART.ParseChangelogLine("**Lead**, and more")
    T.eq(punct, ", and more", "a comma after the stars stays on the note")
    T.eq(KART.StrataSliderLabel(4), "HIGH", "strata slider shows HIGH for index 4")
    T.eq(KART.StrataSliderLabel(7), "FS+D", "and a short label for FULLSCREEN_DIALOG")
end
