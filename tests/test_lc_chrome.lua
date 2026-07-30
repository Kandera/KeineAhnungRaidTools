-- The Loot Council windows step aside for the addon's own confirm dialogs.
--
-- Blizzard's StaticPopup frames are stuck at the DIALOG stratum and moving one taints it for the
-- rest of the session, which is what B8's original fix did and why it was taken out again (B55, and
-- the comment on KAUI's RegisterStaticPopup). So the movement happens on our side instead: KAUI
-- clamps the frames it owns while one of our popups is up.
--
-- These windows are NOT among them. They keep their own list and their own stratum setting so the
-- module stays separable for a future split (B22), which means KAUI's clamp cannot reach them and
-- they subscribe with RegisterPopupYielder instead. Without that subscription the Loot Council
-- windows would be the only ones left covering the dialog -- and they are the ones actually in the
-- way, because they are what the player is looking at when the prompt appears.
--
-- The stand-in prompt is why this is worth a test rather than a comment: it is raised while the
-- council panel is open, and a raid whose lootmaster has left waits on somebody pressing a button
-- they cannot see.
--
-- What is assertable offline is whether the frames move and come back. Whether the result then
-- renders on top needs a client.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local _, lm = F.NewRaid()

RaidSim.As(lm, function()
    local LC = lm.KART.LC

    -- DIALOG is the setting that produces the burial: the windows land on the same stratum as
    -- Blizzard's popup frames, and which one draws on top is then not ours to decide.
    lm.env.KART_Settings.lcFrameStrata = 5
    local window, dialog = CreateFrame("Frame"), CreateFrame("Frame")
    LC.RegisterWindow(window)
    LC.RegisterWindow(dialog, true)
    T.eq(window:GetFrameStrata(), "DIALOG", "a Loot Council window follows its own strata setting")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "and its own dialogs sit one above it")

    local def = lm.env.StaticPopupDialogs["KART_LC_STAND_IN"]
    T.truthy(def, "the stand-in prompt is registered")

    -- Stands in for a pooled Blizzard popup frame. Nothing here is ever written to -- that is the
    -- taint that started all of this -- so it only has to be identifiable.
    local popup = {}

    def.OnShow(popup)
    T.eq(window:GetFrameStrata(), "HIGH",
        "the council window comes down while the stand-in prompt is up")
    T.eq(dialog:GetFrameStrata(), "HIGH", "and so does a Loot Council dialog")

    -- A window built while the prompt is up must not appear in front of it either. The vote window
    -- opening on an incoming roll is exactly that case.
    local late = CreateFrame("Frame")
    LC.RegisterWindow(late)
    T.eq(late:GetFrameStrata(), "HIGH", "a window created while the prompt is up is clamped too")

    def.OnHide(popup)
    T.eq(window:GetFrameStrata(), "DIALOG", "the configured stratum is restored when it closes")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "for Loot Council dialogs as well")
    T.eq(late:GetFrameStrata(), "DIALOG", "including the one built while the prompt was up")
end)

-- A setting below DIALOG was never buried, and must not be moved at all -- dropping those windows
-- to HIGH would raise a player who deliberately put them on MEDIUM.
RaidSim.As(lm, function()
    local LC = lm.KART.LC
    lm.env.KART_Settings.lcFrameStrata = 3 -- MEDIUM
    local window = CreateFrame("Frame")
    LC.RegisterWindow(window)
    T.eq(window:GetFrameStrata(), "MEDIUM", "a window configured below DIALOG starts there")

    local def = lm.env.StaticPopupDialogs["KART_LC_STAND_IN"]
    local popup = {}
    def.OnShow(popup)
    T.eq(window:GetFrameStrata(), "MEDIUM", "and stays there while a popup is up -- it was never in the way")
    def.OnHide(popup)
    T.eq(window:GetFrameStrata(), "MEDIUM", "and is unchanged afterwards")
end)
