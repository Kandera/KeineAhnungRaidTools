-- Covers ONLY the store-binding contract of CreateSettingsCheckbox and CreateSettingsSlider:
-- opts.store may be a plain table or a zero-argument resolver function, and either form must
-- be resolved fresh at handler time (click/drag), never captured once at widget-creation time.
-- That is the exact bug fixed by ResolveStore in Libs/KAUI-1.0/KAUI-1.0.lua ("restoring late
-- binding of the settings store") -- every checkbox/slider in the real addon is built at file
-- scope, before KART_Settings exists, so an early-bound store was nil forever.
-- This file does NOT cover layout, appearance, or anything else about these widgets -- per the
-- Task 4 brief, the toolkit is frames all the way down and that is verified in-game.
--
-- Uses its own namespace ("KAUITest") rather than "KART": namespaces persist for the whole
-- process, and this file must not leave state behind for a test file that runs after it.
local KAUI = LibStub("KAUI-1.0")
local ns = KAUI:NewNamespace("KAUITest")

-- CreateSettingsCheckbox: late-bound resolver function ----------------------------------------
-- Reproduces the failure: build the widget while the resolver returns nil (file scope, before
-- ADDON_LOADED), then let the resolver start returning a real table (what Core.lua's
-- ADDON_LOADED handler does), and confirm a click still lands in the right place.
do
    local liveStore -- nil at build time, on purpose
    local cb = ns:CreateSettingsCheckbox(UIParent, {
        store = function() return liveStore end,
        key = "enabled",
        y = 0,
    })
    liveStore = { enabled = false }
    cb:SetChecked(true)

    local onClick = cb:GetScript("OnClick")
    T.truthy(onClick, "checkbox registers an OnClick handler")
    onClick(cb)
    T.eq(liveStore.enabled, true,
        "checkbox: store resolver is read at click time, not frozen at creation (late binding)")
end

-- CreateSettingsCheckbox: plain table store -----------------------------------------------------
do
    local store = { enabled = false }
    local cb = ns:CreateSettingsCheckbox(UIParent, {
        store = store,
        key = "enabled",
        y = 0,
    })
    cb:SetChecked(true)

    local onClick = cb:GetScript("OnClick")
    onClick(cb)
    T.eq(store.enabled, true, "checkbox: a plain table store still works")
end

-- CreateSettingsSlider: late-bound resolver function --------------------------------------------
do
    local liveStore -- nil at build time, on purpose
    local s = ns:CreateSettingsSlider(UIParent, {
        store = function() return liveStore end,
        key = "amount",
        min = 0, max = 100, y = 0,
    })
    liveStore = { amount = 0 }

    local onValueChanged = s:GetScript("OnValueChanged")
    T.truthy(onValueChanged, "slider registers an OnValueChanged handler")
    onValueChanged(s, 42)
    T.eq(liveStore.amount, 42,
        "slider: store resolver is read at drag time, not frozen at creation (late binding)")
end

-- CreateSettingsSlider: plain table store -----------------------------------------------------
do
    local store = { amount = 0 }
    local s = ns:CreateSettingsSlider(UIParent, {
        store = store,
        key = "amount",
        min = 0, max = 100, y = 0,
    })

    local onValueChanged = s:GetScript("OnValueChanged")
    onValueChanged(s, 42)
    T.eq(store.amount, 42, "slider: a plain table store still works")
end

-- The number sits in a boxed EditBox to the right of the track, not above it as a label.
do
    local s = ns:CreateSettingsSlider(UIParent, {
        store = { amount = 0 },
        key = "amount",
        min = 0, max = 100, y = 0,
    })
    local point, rel, relPoint = s.valueText:GetPoint(1)
    T.eq(point, "LEFT", "slider value box anchors from the left")
    T.eq(rel, s, "to the slider track")
    T.eq(relPoint, "RIGHT", "on the track's right edge")
    T.eq(s:GetWidth(), 140, "the track is the slider width, not the box")
    T.eq(s.valueText:GetWidth(), 44, "the number box is a compact field")
    T.eq(s.valueText:GetHeight(), 20, "and tall enough to type into")
end

do
    local s = ns:CreateSettingsSlider(UIParent, {
        store = { amount = 0 },
        key = "amount",
        min = 0, max = 100, y = 0,
        valueIsText = true,
    })
    T.eq(s.valueText:GetWidth(), 88, "named-value sliders get a wider box")
    T.eq(s.valueText:IsMouseEnabled(), false, "and stay read-only")
end

-- RegisterStaticPopup: the popup outranks the windows while it is ours ------------------------
-- Blizzard's popup frames sit at a fixed DIALOG stratum, so a consumer whose windows are set to
-- DIALOG or above buried its own confirm dialog behind the window that raised it (B8). The
-- registration now lifts the popup on show and restores it on hide, because those frames are
-- shared with every other addon.
local function FakePopup()
    local p = { strata = "DIALOG" }
    function p:GetFrameStrata() return self.strata end
    function p:SetFrameStrata(s) self.strata = s end
    return p
end

do
    ns:RegisterStaticPopup("KAUITEST_PLAIN", { text = "x" })
    local def = StaticPopupDialogs["KAUITEST_PLAIN"]
    T.truthy(def, "RegisterStaticPopup stores the definition under its name")
    T.eq(def.timeout, 0, "the shared modal defaults are applied")
    T.truthy(def.whileDead, "and usable while dead")
end

-- The frame must be left alone. Blizzard's popup frames are a shared pool, and an insecure write to
-- one of them taints it for the session -- the next Blizzard dialog handed that pooled frame then
-- has its protected calls refused and blames us. This shipped once and stopped players upgrading
-- items (see the comment on RegisterStaticPopup). A consumer's own handlers must reach the frame
-- untouched, so if a hook is ever reintroduced here, these assertions are what should stop it.
do
    local shown, hidden = false, false
    ns:RegisterStaticPopup("KAUITEST_HOOKED", {
        text = "x",
        OnShow = function() shown = true end,
        OnHide = function() hidden = true end,
    })
    local def = StaticPopupDialogs["KAUITEST_HOOKED"]

    local popup = FakePopup()
    def.OnShow(popup)
    T.truthy(shown, "the consumer's own OnShow runs")
    T.eq(popup.strata, "DIALOG", "and the popup frame's stratum was NOT written to")

    def.OnHide(popup)
    T.truthy(hidden, "the consumer's own OnHide runs")
    T.eq(popup.strata, "DIALOG", "and the frame is still untouched on hide")
    T.is_nil(popup.kauiPrevStrata, "no bookkeeping field is left on a Blizzard frame")
end

-- SetPixelBackdrop: a border is a whole physical pixel, whatever the UI scale ------------------
-- Every backdrop in the addon asks for a 1-unit border. That is one physical pixel only while the
-- UI scale matches the resolution. On the client that reported B23 the interface is scaled for
-- 1440 lines but rendered on 1080, one unit is 0.75 pixels, and WoW draws such a border in
-- patches. edgeSize is now derived from the frame's effective scale instead of hardcoded.
local function ApproxEq(actual, expected, msg)
    T.truthy(math.abs(actual - expected) < 1e-9,
        msg .. " (expected " .. expected .. ", got " .. tostring(actual) .. ")")
end

do
    KARTTEST.uiScale = 768 / 1080 -- what WoW picks itself: one unit is exactly one pixel
    local f = CreateFrame("Frame")
    ns:SetPixelBackdrop(f, { bgFile = "x", edgeFile = "y", edgeSize = 1 })
    ApproxEq(f:GetBackdrop().edgeSize, 1,
        "a scale matching the resolution leaves the border at exactly 1 unit -- nobody else changes")
end

do
    KARTTEST.uiScale = 768 / 1440 -- scaled for 1440p, rendered on 1080p: 0.75 pixels per unit
    local f = CreateFrame("Frame")
    ns:SetPixelBackdrop(f, { bgFile = "x", edgeFile = "y", edgeSize = 1 })
    ApproxEq(f:GetBackdrop().edgeSize, 4 / 3,
        "a 0.75-pixel unit widens the border to 4/3 units, which is one whole pixel (B23)")

    local thick = CreateFrame("Frame")
    ns:SetPixelBackdrop(thick, { bgFile = "x", edgeFile = "y", edgeSize = 2 })
    ApproxEq(thick:GetBackdrop().edgeSize, 8 / 3, "a 2-unit border scales the same way")
end

-- The frame's own scale counts too: the Loot Council windows carry one, set by their size slider.
do
    KARTTEST.uiScale = 768 / 1440
    local f = CreateFrame("Frame")
    f:SetScale(4 / 3) -- brings the effective scale back to pixel-perfect
    ns:SetPixelBackdrop(f, { bgFile = "x", edgeFile = "y", edgeSize = 1 })
    ApproxEq(f:GetBackdrop().edgeSize, 1,
        "a window whose own scale restores pixel-perfection needs no correction")
end

-- RefreshPixelBorders: recompute after a scale change, and keep the colors -----------------------
-- SetBackdrop drops the backdrop and border colors, so a refresh that only re-set the table would
-- leave every registered frame black. The scale slider calls this on every drag.
do
    KARTTEST.uiScale = 768 / 1080
    local f = CreateFrame("Frame")
    ns:SetPixelBackdrop(f, { bgFile = "x", edgeFile = "y", edgeSize = 1 })
    f:SetBackdropColor(0.1, 0.2, 0.3, 0.9)
    f:SetBackdropBorderColor(0.4, 0.5, 0.6, 1)

    f:SetScale(0.5)
    ns:RefreshPixelBorders()
    ApproxEq(f:GetBackdrop().edgeSize, 2, "a halved frame scale doubles the border in frame units")

    local r, g, b, a = f:GetBackdropColor()
    T.eq(r, 0.1, "refresh keeps the backdrop color")
    T.eq(a, 0.9, "refresh keeps the backdrop alpha")
    local er, eg, eb, ea = f:GetBackdropBorderColor()
    T.eq(er, 0.4, "refresh keeps the border color")
    T.eq(ea, 1, "refresh keeps the border alpha")
    T.truthy(g and b and eg and eb, "all four components survive the refresh")
end

-- While one of our popups is up, OUR windows step below Blizzard's DIALOG stratum --------------
-- B8's original symptom: a consumer whose windows sit at or above DIALOG buries its own confirm
-- dialog behind the window that raised it, and the button looks like it did nothing. B8's fix
-- raised the popup and tainted a shared Blizzard frame (see above), so the movement now happens on
-- our side. What is assertable offline is exactly that: whether the frames we own actually move and
-- actually come back. Whether the result then RENDERS on top needs a client.
local popNS = KAUI:NewNamespace("KAUIPopupTest")

local function Windows(strataIndex)
    popNS.strata = strataIndex -- the field ApplyStyle sets from the consumer's saved setting
    local window, dialog = CreateFrame("Frame"), CreateFrame("Frame")
    popNS:RegisterStrataFrame(window)
    popNS:RegisterStrataFrame(dialog, true)
    return window, dialog
end

do
    local window, dialog = Windows(5) -- DIALOG: the setting that produces the burial
    T.eq(window:GetFrameStrata(), "DIALOG", "a window follows the configured stratum")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "and its dialogs sit one above it")

    popNS:RegisterStaticPopup("KAUIPOPUP_A", { text = "x" })
    local a = StaticPopupDialogs["KAUIPOPUP_A"]
    local frameA = FakePopup()

    a.OnShow(frameA)
    T.eq(window:GetFrameStrata(), "HIGH", "the window drops below DIALOG while a popup is up")
    T.eq(dialog:GetFrameStrata(), "HIGH", "and so does a window registered as a dialog")
    T.eq(frameA.strata, "DIALOG", "the popup frame itself is still never written to")

    -- A settings change while the popup is up must not undo the clamp: the strata slider and every
    -- profile switch call ApplyFrameStrata, and it would otherwise raise the windows back over the
    -- dialog the player is currently looking at.
    popNS:ApplyFrameStrata()
    T.eq(window:GetFrameStrata(), "HIGH", "re-applying the styles while a popup is up keeps the clamp")

    -- ...nor may a window built while the popup is up come back in front of it.
    local late = CreateFrame("Frame")
    popNS:RegisterStrataFrame(late)
    T.eq(late:GetFrameStrata(), "HIGH", "a window created while a popup is up is clamped too")

    a.OnHide(frameA)
    T.eq(window:GetFrameStrata(), "DIALOG", "the configured stratum is restored on hide")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "for dialogs as well")
    T.eq(late:GetFrameStrata(), "DIALOG", "including the one built while the popup was up")
end

-- Windows maxed out: GetDialogStrata answers TOOLTIP, which is not in the ordered list at all -----
do
    local window, dialog = Windows(7) -- FULLSCREEN_DIALOG
    T.eq(dialog:GetFrameStrata(), "TOOLTIP", "a maxed-out window's dialogs land on TOOLTIP")

    local a = StaticPopupDialogs["KAUIPOPUP_A"]
    local frameA = FakePopup()
    a.OnShow(frameA)
    T.eq(window:GetFrameStrata(), "HIGH", "FULLSCREEN_DIALOG comes down")
    T.eq(dialog:GetFrameStrata(), "HIGH", "and so does TOOLTIP, which the list does not contain")
    a.OnHide(frameA)
    T.eq(dialog:GetFrameStrata(), "TOOLTIP", "and goes back up afterwards")
end

-- Two popups at once, and the same popup shown twice --------------------------------------------
do
    local window = Windows(5)
    popNS:RegisterStaticPopup("KAUIPOPUP_B", { text = "x" })
    local a, b = StaticPopupDialogs["KAUIPOPUP_A"], StaticPopupDialogs["KAUIPOPUP_B"]
    local frameA, frameB = FakePopup(), FakePopup()

    a.OnShow(frameA)
    b.OnShow(frameB)
    b.OnHide(frameB)
    T.eq(window:GetFrameStrata(), "HIGH", "closing one popup while another is up keeps the windows down")
    a.OnHide(frameA)
    T.eq(window:GetFrameStrata(), "DIALOG", "and the last one closing puts them back")

    -- StaticPopup_Show on a dialog that is already up reuses the same frame and fires OnShow again
    -- with no OnHide in between. A counted implementation would be left one too high here and the
    -- windows would stay lowered for the rest of the session.
    a.OnShow(frameA)
    a.OnShow(frameA)
    a.OnHide(frameA)
    T.eq(window:GetFrameStrata(), "DIALOG",
        "showing the same popup twice still releases on a single hide")
end

-- A consumer that keeps strata frames outside this namespace subscribes instead -------------------
-- KART's Loot Council windows are exactly that: their own list, their own stratum setting, so they
-- stay separable. Without the callback they would be the ONLY windows left covering the dialog.
do
    Windows(5)
    local seen = {}
    popNS:RegisterPopupYielder(function(yielding) seen[#seen + 1] = yielding end)

    local a = StaticPopupDialogs["KAUIPOPUP_A"]
    local frameA = FakePopup()
    a.OnShow(frameA)
    a.OnHide(frameA)
    T.eq(#seen, 2, "the yielder is told on the way in and on the way out")
    T.eq(seen[1], true, "step aside")
    T.eq(seen[2], false, "and come back")
end

KARTTEST.uiScale = 768 / 1080 -- leave the scale as found, for whatever file runs next

-- CreateTabButton: optional module ON/OFF chip on the right ------------------------------------
do
    local b = ns:CreateTabButton(UIParent, "Raidlead", { moduleChip = true })
    T.truthy(b.chip, "module tab gets a chip")
    T.eq(b.chip:GetText(), "OFF", "chip starts off")
    b:SetModuleChipOn(true)
    T.eq(b.chip:GetText(), "ON", "chip shows on")
    b:SetModuleChipOn(false)
    T.eq(b.chip:GetText(), "OFF", "chip shows off again")
end

do
    local plain = ns:CreateTabButton(UIParent, "Settings")
    T.is_nil(plain.chip, "non-module tabs have no chip")
end
