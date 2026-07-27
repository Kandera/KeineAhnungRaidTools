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

    local popup = FakePopup()
    def.OnShow(popup)
    T.eq(popup.strata, "TOOLTIP",
        "popup is lifted above every window stratum while one of ours is showing")
    def.OnHide(popup)
    T.eq(popup.strata, "DIALOG",
        "popup goes back to the stratum it had, since the frame is shared")
end

-- A consumer's own OnShow/OnHide must survive the wrapping.
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
    T.truthy(shown, "the consumer's own OnShow still runs")
    T.eq(popup.strata, "TOOLTIP", "and the lift happened anyway")

    def.OnHide(popup)
    T.truthy(hidden, "the consumer's own OnHide still runs")
    T.eq(popup.strata, "DIALOG", "and the restore happened anyway")
end
