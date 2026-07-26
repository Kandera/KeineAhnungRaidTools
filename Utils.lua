local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAGS = LibStub("KAGS-1.0")

local KAUI = LibStub("KAUI-1.0")
KART.UI = KAUI:NewNamespace("KART")

-- KART.L itself is a STABLE table — its reference must never be replaced, only its values
-- swapped (files capture `local L = KART.L` at load time and keep that reference). Locale
-- refreshers (functions that re-apply static UI text once the saved language is known) are
-- registered via KART.UI:RegisterLocaleRefresher; Core.lua runs them once at ADDON_LOADED,
-- right after the locale values are copied into KART.L.
KART.L = KART.L or {}

-- Standardeinstellungen
KART.Defaults = {
    inviteKeywords = "inv;+;invite",
    inviteViaGuildChat = false,
    promoteNames = "",
    showRaidleadBar = false,
    lockRaidleadBar = false,
    autoHideRaidleadBar = false,
    pullTimerDuration = 10,
    keybinds = {}, -- filled per-action at runtime (see KART.ApplyKeybinds); nil fields in a table literal are a no-op anyway
    bcModuleEnabled = false,
    showBuffCheck = false,
    buffCheckAlpha = 90,
    bcCombatDelay = 2,
    grayOffline = true,
    minimap = {},
    showMinimapIcon = true,
    autoConvertToRaid = false,
    titleFontSize = 12,
    menuFontSize = 11,
    contentFontSize = 12,
    bgAlpha = 85,
    uiScale = 100, -- whole-window scale in percent (PNG-artwork window is not freely resizable)
    fontName = "Friz Quadrata",
    accentR = 0, accentG = 60, accentB = 100,
    bgR = 10, bgG = 10, bgB = 10,
    language = "Auto",
    lcModuleEnabled = false,
    lcAutoPass = true,
    lcVoteSeconds = 20,
    lcButtonLabels = "BIS;Upgrade;Offspec;Sonstiges;Pass", -- placeholder; localized in Core.lua ADDON_LOADED via LC_DEFAULT_BUTTONS
    lcCouncilMembers = "",
    lcLootmaster = "",
    lcShowNickNames = false,
    lcVoteLayoutCompact = false,
    lcFontSize = 12,
    lcRollsEnabled = false,
    lcVotedItemDisplay = "full",
    wuModuleEnabled = false,
    wuImportText = "",
    dtModuleEnabled = false,
    lcVotePopupPos = false,
    lcCouncilPanelPos = false,
    lcHistoryWindowPos = false,
    lcMinQuality = 4,
    frameStrata = 4, -- index into KART.StrataLevels (4 = HIGH)
    autoLogEnabled = false,
    autoLogRaidLFR = false,
    autoLogRaidNormal = false,
    autoLogRaidHeroic = false,
    autoLogRaidMythic = false,
    autoLogMythicPlus = false,
    autoLogMinKey = 2,
    autoLogDungeons = false,
    autoLogDelves = false,
    autoLogOwned = false, -- hidden: whether the addon (not the player) started the current combat log
}

-- Ordered list of WoW frame strata a KART window may sit on, kept here (rather than only inside
-- KAUI-1.0's own copy) purely so the settings-tab strata slider (MainFrame.lua) has a name list
-- and count to build its range and value display from. The strata registries and the apply/
-- register logic itself live in KAUI-1.0 now; see KART.UI:RegisterStrataFrame et al.
KART.StrataLevels = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

-- Resolves unit's Northern Sky Raid Tools nickname, or nil if NSRT isn't installed, has no
-- nickname stored for that character, or its "Global Nicknames" master toggle is off. NSAPI is
-- NSRT's own public API global (see its NickNames.lua) — calling GetName with no AddonName
-- argument makes it honor only that master toggle instead of a per-addon toggle KART was never
-- registered for (which would otherwise always read as disabled, see NSAPI:GetName's own "if no
-- AddonName is given we assume it's from an old WeakAura" comment). Wrapped in pcall since this
-- reaches into another addon's code, which KART never requires to be installed.
--
-- Returns two values: the lowercased nickname (for case-insensitive matching against configured
-- name lists — Auto-Promote, Loot Council members/lootmaster) and the nickname in its original
-- casing (for display, e.g. the council panel's name column). Extra return values are silently
-- dropped wherever a caller only wants the first one, so existing single-value call sites don't
-- need to change.
function KART.GetNickname(unit)
    if not (unit and NSAPI and NSAPI.GetName and UnitExists(unit)) then return nil end
    local ok, nick = pcall(NSAPI.GetName, NSAPI, unit)
    if not ok or not nick or nick == "" then return nil end
    local realName = UnitName(unit)
    if nick == realName then return nil end -- no nickname set, NSAPI just echoed the real name back
    -- CaseFold (not :lower()) so an umlaut nickname folds the same way the promote/council
    -- lists and Identity's name matching fold their side — otherwise umlaut nicks never match.
    return KAUtil.CaseFold(nick), nick
end

-- Fixed status colors, and the one corner radius that's still addon-owned (the other two --
-- the small-button radius and the too-small-to-round floor -- moved to KAUI-1.0 along with
-- ApplyRoundedMask, since only that moved function and the widget factories that moved with it
-- ever read them; see KAUI.CORNER_RADIUS_SM). Kept as plain data (no frame references) so
-- KART.UpdateStyles() can call the addon's own remaining factories fresh on every settings
-- change without caching stale colors.
KART.CORNER_RADIUS_LG = 6 -- panels, cards, main window

KART.SUCCESS = {0.35, 0.75, 0.35}
KART.WARNING = {0.90, 0.70, 0.20}
KART.DANGER  = {0.85, 0.30, 0.30}

-- Weitere UI-Hilfsfunktionen (Slider/Checkbox) hier implementieren...
-- Toggle-switch style: a pill-shaped track (34x16) with a round dot that slides between left
-- (off) and right (on). Still a real CheckButton under the hood so GetChecked/SetChecked and the
-- existing OnClick wiring below are unchanged for every call site.
function KART.CreateSettingsCheckbox(parent, name, labelText, settingKey, yOffset, callback, tooltipText)
    local cb = CreateFrame("CheckButton", name, parent, "BackdropTemplate")
    cb:SetSize(34, 16)
    cb:SetPoint("TOPLEFT", 20, yOffset)

    cb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(0, 0, 0, 0.5)
    cb:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    -- Pill track is fully rounded: half its own height, which is below CORNER_RADIUS_MIN_SIZE, so
    -- it needs its own mask call with a radius large enough to round the full end-caps rather than
    -- going through the generic small-corner path.
    KART.UI:ApplyRoundedMask(cb, 8)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.text:SetText(labelText)
    KART.UI:RegisterLabel(cb.text)

    -- Sliding dot: positioned left when unchecked, right when checked. Reused as the "checked
    -- texture" so WoW's own CheckButton show/hide-on-check logic still drives visibility, but its
    -- position (not just visibility) is updated in the click handler below.
    local dot = cb:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", cb, "LEFT", 2, 0)
    cb:SetCheckedTexture(dot)
    KART.UI:RegisterCheckVisual(dot)

    -- Checked texture only shows/hides by default; here it must always render (the dot represents
    -- "off" position too) — track color communicates on/off state.
    dot:Show()

    local function refreshVisual(self)
        dot:Show() -- override native CheckButton show/hide-on-check behavior; the dot must always
                   -- be visible, only its position communicates checked/unchecked state
        local checked = self:GetChecked()
        dot:ClearAllPoints()
        if checked then
            dot:SetPoint("RIGHT", self, "RIGHT", -2, 0)
        else
            dot:SetPoint("LEFT", self, "LEFT", 2, 0)
        end
        local r, g, bl = KART.UI:AccentColor()
        if checked then
            -- Explicit alpha (matching the unchecked branch's 0.5) rather than relying on Darken's
            -- 3 return values expanding into SetBackdropColor's 4-arg call: that would leave alpha
            -- unset, and every other SetBackdropColor call site in this file passes alpha
            -- explicitly, so an implicit default here would be an inconsistent one-off.
            local dr, dg, db = KAUI.Darken(r, g, bl, 0.35)
            self:SetBackdropColor(dr, dg, db, 0.5)
        else
            self:SetBackdropColor(0, 0, 0, 0.5)
        end
    end

    cb:SetScript("OnClick", function(self)
        KART_Settings[settingKey] = self:GetChecked()
        refreshVisual(self)
        if callback then callback() end
    end)
    -- Initial state (e.g. when the panel is first built, before any user click) still needs the
    -- dot in the correct position — CheckButton's own SetChecked (called elsewhere when settings
    -- load) doesn't fire OnClick, so hook OnShow as a catch-all.
    cb:HookScript("OnShow", function(self) refreshVisual(self) end)

    -- Exposes refreshVisual so KART.UpdateStyles() can re-sync this checkbox's track color to a
    -- freshly-changed accent color, the same way it already does for the dot (via KART.UI's
    -- check-visual registry) and slider thumbs/glows (via its slider-thumb registry).
    cb.RefreshVisual = function() refreshVisual(cb) end
    KART.UI:RegisterToggleCheckbox(cb)

    cb.tooltipText = tooltipText
    cb:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
end

function KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText, skipStyleRefresh)
    local s = CreateFrame("Slider", name, parent, "BackdropTemplate")
    s:SetSize(180, 4) -- thin track instead of the old 14px-tall bar
    s:SetPoint("TOPLEFT", 20, yOffset - 16) -- 16px Platz für das Label oben
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    s:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0, 0, 0, 0.5)
    s:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    KART.UI:ApplyRoundedMask(s, 2) -- track is only 4px tall; skips rounding via the min-size guard, kept for future-proofing if track height changes

    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.title:SetText(labelText)
    KART.UI:RegisterLabel(s.title)

    s.valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)

    -- Soft glow behind the thumb, hidden by default, faded in on hover/drag via alpha rather
    -- than Show/Hide so it never fights another script over the frame's visibility.
    local glow = s:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(20, 20)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetAlpha(0)
    KART.UI:RegisterSliderThumb(glow) -- colored alongside the thumb in KART.UpdateStyles

    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 12)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    s:SetThumbTexture(thumb)
    KART.UI:RegisterSliderThumb(thumb)
    local thumbMask = s:CreateMaskTexture(nil, "OVERLAY")
    local maskOk = pcall(function()
        thumbMask:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        thumbMask:SetAllPoints(thumb)
        thumb:AddMaskTexture(thumbMask)
    end)
    if not maskOk then thumbMask:Hide() end

    local function positionGlow()
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", thumb, "CENTER")
    end

    s:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value)
        KART_Settings[settingKey] = val
        self.valueText:SetText(val)
        positionGlow()
        -- skipStyleRefresh: sliders whose value doesn't feed KART.UpdateStyles (pull timer,
        -- combat delay, min key level, vote timer) skip the full restyle on every drag tick.
        if not skipStyleRefresh and KART.UpdateStyles then KART.UpdateStyles() end
    end)
    s:SetScript("OnEnter", function() glow:SetAlpha(0.35) end)
    s:SetScript("OnLeave", function() if not s.isDragging then glow:SetAlpha(0) end end)
    s:HookScript("OnMouseDown", function() s.isDragging = true; glow:SetAlpha(0.5) end)
    s:HookScript("OnMouseUp", function() s.isDragging = false; glow:SetAlpha(0) end)

    -- A slider whose saved value equals its minimum never fires OnValueChanged (SetValue(min) is a
    -- no-op on a fresh slider), so valueText would stay blank until the first drag. Populate it on
    -- show from the current value.
    s:HookScript("OnShow", function(self)
        self.valueText:SetText(math.floor(self:GetValue()))
    end)

    s.tooltipText = tooltipText
    s:HookScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    s:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return s
end

-- UI Factory: Card panel — a rounded, slightly recessed container used to visually group related
-- settings (e.g. all Raidlead Bar options) instead of leaving controls floating directly on the
-- tab background. Draws a second, 2px-larger, darker backdrop behind the card as a cheap "shadow"
-- (WoW has no real blur/drop-shadow primitive), then the card's own backdrop on top.
function KART.CreateCard(parent, title)
    local shadow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    shadow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    shadow:SetBackdropColor(0, 0, 0, 0.35)

    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card.shadow = shadow
    -- Anchor the shadow 2px outside the card's edges, one-way (shadow follows card, never the
    -- reverse). WoW resolves SetPoint anchors live against the target frame's current position/
    -- size, so this single pair of calls keeps the shadow tracking the card through every future
    -- SetSize/SetPoint the caller makes on `card` — no OnSizeChanged plumbing needed for
    -- positioning, and no risk of card and shadow ending up anchored to each other (which WoW
    -- rejects as a dependency loop). `card` itself is intentionally left unanchored/unsized here:
    -- per this function's contract, the caller sizes and positions the returned frame.
    shadow:SetPoint("TOPLEFT", card, "TOPLEFT", -2, 2)
    shadow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 2, -2)

    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    card:SetBackdropBorderColor(0, 0, 0, 1)

    -- `card` has no size yet at this point (the caller sizes it after CreateCard returns), so
    -- calling KART.UI:ApplyRoundedMask here immediately would hit its min-size guard and silently
    -- no-op, leaving the card permanently square. Re-apply on every OnSizeChanged instead —
    -- ApplyRoundedMask is documented as idempotent for exactly this reuse pattern — so the mask
    -- is (re)established once the caller gives the card real dimensions, and stays correct if
    -- it's resized again later. Shadow's size is derived from card's via the anchors above, so
    -- its own OnSizeChanged fires in lockstep; re-mask it alongside card here rather than adding
    -- a second identical hook on shadow.
    card:HookScript("OnSizeChanged", function()
        KART.UI:ApplyRoundedMask(card, KART.CORNER_RADIUS_LG)
        KART.UI:ApplyRoundedMask(shadow, KART.CORNER_RADIUS_LG)
    end)

    -- shadow is a sibling of card (not its child, so it stays visually behind card without
    -- needing an explicit frame level), so it doesn't automatically follow card's Show/Hide.
    -- Keep it in sync explicitly so callers that hide the card don't leave a detached shadow
    -- floating on screen.
    card:HookScript("OnShow", function() shadow:Show() end)
    card:HookScript("OnHide", function() shadow:Hide() end)

    if title then
        card.titleText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.titleText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        card.titleText:SetText(title)
        KART.UI:RegisterLabel(card.titleText)
    end

    return card
end

-- UI Factory: styled single-line EditBox matching the card look — dark inset fill, rounded
-- corners, subtle resting border, accent-colored border while focused. Registers the box with
-- KART.UI for font updates and wires the common OnEscapePressed=ClearFocus behavior.
-- Caller sets size/point and its own OnTextChanged (and SetMaxLetters where needed). The
-- rounded mask is (re)applied on OnSizeChanged like KART.CreateCard does, because the box has
-- no size yet at creation time and ApplyRoundedMask would silently no-op on it here.
function KART.CreateStyledEditBox(parent, name)
    local eb = CreateFrame("EditBox", name, parent, "BackdropTemplate")
    eb:SetAutoFocus(false)
    eb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    eb:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
    eb:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    eb:SetTextInsets(10, 10, 0, 0)
    eb:HookScript("OnSizeChanged", function()
        KART.UI:ApplyRoundedMask(eb, KART.CORNER_RADIUS_LG)
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        local r, g, b = KART.UI:AccentColor()
        self:SetBackdropBorderColor(r, g, b, 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    KART.UI:RegisterEditBox(eb)
    return eb
end

-- Generic single-line input dialog, replacing three near-identical hand-rolled dialogs
-- (LC sync target, officer note, save profile). Hand-rolled rather than StaticPopup because
-- retail's StaticPopup doesn't reliably expose its edit box to OnAccept (see the original
-- ShowOfficerNoteDialog comment in git history for the full story).
local inputDialog
function KART.ShowInputDialog(opts)
    if not inputDialog then
        local f = CreateFrame("Frame", "KART_InputDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        KART.UI:RegisterStrataFrame(f, true)
        KART.UI:ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetWidth(270)
        f.title:SetWordWrap(true)

        f.editBox = KART.CreateStyledEditBox(f, "KART_InputDialogEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            local o = f.opts
            local text = KAUtil.TrimString(f.editBox:GetText() or "")
            if text == "" and not o.allowEmpty then
                if o.emptyMessage then UIErrorsFrame:AddMessage(o.emptyMessage, 1, 0.1, 0.1, 1, 3) end
                return
            end
            f:Hide()
            o.onAccept(text)
        end

        f.btnOK = KART.UI:CreateModernButton(f, KART.L.BTN_ACCEPT)
        f.btnOK:SetSize(120, 26)
        f.btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        f.btnOK:SetScript("OnClick", accept)

        f.btnCancel = KART.UI:CreateModernButton(f, KART.L.BTN_CANCEL)
        f.btnCancel:SetSize(120, 26)
        f.btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        f.btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        inputDialog = f
    end
    local f = inputDialog
    f.opts = opts
    f.title:SetText(opts.title)
    -- Re-set both button captions each show so they follow the KART language (which the picker
    -- reloads to switch), not the WoW client locale that ACCEPT/CANCEL globals would carry.
    f.btnOK.text:SetText(opts.okLabel or KART.L.BTN_ACCEPT)
    f.btnCancel.text:SetText(KART.L.BTN_CANCEL)
    f.editBox:SetMaxLetters(opts.maxLetters or 64)
    f.editBox:SetText(opts.initialText or "")
    f:Show()
    f.editBox:SetFocus()
    if (opts.initialText or "") ~= "" then f.editBox:HighlightText() end
end

function KART.UpdateMinimapButton()
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not dbIcon then return end
    if KART_Settings.showMinimapIcon then
        dbIcon:Show("KeineAhnungRaidTools")
    else
        dbIcon:Hide("KeineAhnungRaidTools")
    end
    -- LibDBIcon only reads minimapPos out of its saved table when told to refresh. A profile switch
    -- swaps that table's contents (Profiles.lua keeps the table's identity for exactly this reason),
    -- so without this the icon keeps the previous profile's angle until the next drag or reload.
    if dbIcon.Refresh then
        pcall(dbIcon.Refresh, dbIcon, "KeineAhnungRaidTools", KART_Settings.minimap)
    end
end

function KART.OpenColorPicker(rKey, gKey, bKey)
    -- The ORIGINAL 0-100 integers are kept for the cancel path below, not re-derived from the 0-1
    -- values handed to the picker: round-tripping through /100 and math.floor(x*100) loses a whole
    -- unit for 29, 57 and 58 (binary floating point), so cancelling silently darkened the colour
    -- instead of restoring exactly what was there.
    local origR = KART_Settings[rKey] or 100
    local origG = KART_Settings[gKey] or 100
    local origB = KART_Settings[bKey] or 100
    local startR, startG, startB = origR / 100, origG / 100, origB / 100

    local function onUpdate()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        if not r then return end
        -- Round (+0.5), don't truncate: the picker returns 0-1 floats and plain flooring drops a
        -- full unit off most of them (0.29 * 100 is 28.999…), so every pick drifted darker.
        KART_Settings[rKey] = math.floor(r * 100 + 0.5)
        KART_Settings[gKey] = math.floor(g * 100 + 0.5)
        KART_Settings[bKey] = math.floor(b * 100 + 0.5)
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    local function onCancel()
        KART_Settings[rKey] = origR
        KART_Settings[gKey] = origG
        KART_Settings[bKey] = origB
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR, g = startG, b = startB,
            swatchFunc = onUpdate,
            cancelFunc = onCancel,
        })
    end
end

-- The enchant's display NAME for `slot`, read off the item tooltip's "Enchanted: X" line.
--
-- This is the piece that makes the whole exercise verifiable. The item link carries only the numeric
-- id, and a bare number can't be checked against anything — which is how a table of invented ids got
-- shipped in the first place. The name can: it maps straight onto a published list of the tier's
-- enchants, so an id is only ever accepted once its name has been confirmed as one of them.
local function EnchantNameForSlot(slot)
    if not ENCHANTED_TOOLTIP then return nil end ---@diagnostic disable-line: undefined-global
    -- ENCHANTED_TOOLTIP is Blizzard's own localized "Enchanted: %s" template. Escaping it and then
    -- turning its %s into a capture keeps this working on a German client ("Verzaubert: %s") without
    -- hardcoding either language.
    local pattern = "^" .. ENCHANTED_TOOLTIP ---@diagnostic disable-line: undefined-global
        :gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        :gsub("%%%%s", "(.+)")
    KART_GearScanTooltip:ClearLines()
    KART_GearScanTooltip:SetInventoryItem("player", slot)
    for i = 1, KART_GearScanTooltip:NumLines() do
        local fs = _G["KART_GearScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        local name = text and text:match(pattern)
        if name then return name end
    end
    return nil
end

function KART.PrintEnchantDump()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_PERMANENT)
    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            print(string.format("  slot %d: -", slot))
        else
            local enchant = link:match("item:%d+:(%d*):")
            local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            print(string.format("  slot %d: enchant=%s  [%s]  equipLoc=%s  %s",
                slot,
                (enchant and enchant ~= "" and enchant ~= "0") and enchant or "NONE",
                EnchantNameForSlot(slot) or "?",
                tostring(equipLoc),
                C_Item.GetItemInfo(link) or "?"))
        end
    end

    local hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = GetWeaponEnchantInfo()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_TEMPORARY)
    print(string.format("  main hand: has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasMH), tostring(mhID), tostring(mhExp), tostring(KAGS.SlotNeedsOil(16))))
    print(string.format("  off hand:  has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasOH), tostring(ohID), tostring(ohExp), tostring(KAGS.SlotNeedsOil(17))))
end

-- Answers to a raid scan, keyed by short name so a repeated reply replaces rather than double-counts.
KART.EnchantScan = KART.EnchantScan or {}

-- Asks every KART user in the group for their enchant ids and prints the tally a few seconds later.
--
-- READ THIS BEFORE USING THE OUTPUT: the tally shows what the raid WEARS, which is not the same as
-- what is CORRECT. Pasting it into GOOD_ENCHANTS (Libs/KAGS-1.0/KAGS-1.0.lua) would bless whatever
-- outdated enchant someone happens to have — the list would then approve exactly the case the
-- check is meant to catch. There is no in-game API that ranks an enchantID, so correctness can
-- only come from outside the game.
--
-- What it is actually good for is spotting outliers by eye: when eighteen people share an id on a
-- slot and one person has a different one, that one is worth a look. A human reads that; the code
-- must not.
function KART.StartEnchantScan()
    if not IsInGroup() then
        print("|cffff0000KART:|r " .. KART.L.ENCH_SCAN_NOT_IN_GROUP)
        return
    end
    wipe(KART.EnchantScan)
    -- Our own answer: SendAddonMessage never echoes back to its sender.
    KART.EnchantScan[UnitName("player") or "?"] = KAGS.GetOwnEnchantIDs()
    KART.Sync.Send("REQ_ENCH")
    print("|cff00ff00KART:|r " .. KART.L.ENCH_SCAN_START)
    C_Timer.After(5, KART.PrintEnchantScan)
end

function KART.PrintEnchantScan()
    local perSlot, responders = {}, 0
    for _, ids in pairs(KART.EnchantScan) do
        responders = responders + 1
        for slot, id in pairs(ids) do
            perSlot[slot] = perSlot[slot] or {}
            perSlot[slot][id] = (perSlot[slot][id] or 0) + 1
        end
    end

    print("|cff00ff00KART|r " .. string.format(KART.L.ENCH_SCAN_RESULT, responders))
    local order = {}
    for _, s in ipairs(KAGS.ENCHANTABLE_SLOTS) do order[#order + 1] = s end
    order[#order + 1] = "oil"
    for _, slot in ipairs(order) do
        local counts = perSlot[slot]
        if counts then
            local list = {}
            for id, n in pairs(counts) do list[#list + 1] = { id = id, n = n } end
            -- Most-used first, so the common enchants read as the accepted set and any one-off
            -- (the likely outdated one) sits at the end.
            table.sort(list, function(a, b)
                if a.n ~= b.n then return a.n > b.n end
                return a.id < b.id
            end)
            local parts = {}
            for _, e in ipairs(list) do parts[#parts + 1] = e.id .. " (x" .. e.n .. ")" end
            print(string.format("  %s: %s", tostring(slot), table.concat(parts, ", ")))
        end
    end
end

-- Keybind action list: shared between ApplyKeybinds and the settings-tab bind UI so both
-- stay in sync with a single source of truth for which 4 actions are bindable. Lives in
-- Utils.lua (rather than RaidleadBar.lua where ApplyKeybinds is defined) because it loads
-- before MainFrame.lua, which reads it at file-load time to build the keybind settings card.
KART.KeybindActions = {
    { key = "readyCheck", button = "KART_RL_ReadyCheckBtn" },
    { key = "clearWorldMarkers", button = "KART_RL_ClearWorldMarkersBtn" },
    { key = "pullTimer", button = "KART_RL_PullTimerBtn" },
    { key = "buffCheckToggle", button = "KART_RL_BuffCheckToggleBtn" },
}

-- Maps each of the 6 main-window tab-content panels to its ShowTab index. Used by
-- KART.BuildSearchIndex to figure out which tab a given label belongs to, by walking up the
-- label's parent chain until one of these panels is found.
local SEARCH_TAB_PANELS = {
    { panel = "PromotePanel", tabIndex = 1 },
    { panel = "RaidleadPanel", tabIndex = 2 },
    { panel = "BuffCheckPanel", tabIndex = 3 },
    { panel = "SettingsPanel", tabIndex = 4 },
    { panel = "LootCouncilPanel", tabIndex = 5 },
    { panel = "WoWUtilsPanel", tabIndex = 6 },
}

-- Builds the settings search index by walking KART.UI's label registry — every settings label
-- already gets registered there by its creation site (checkboxes, sliders, card titles, hints,
-- tab titles), so no per-widget registration is needed here. A label whose parent chain never
-- reaches one of the 6 main tab panels (e.g. one that belongs to a popup window like Loot
-- History) is silently skipped, which is how "only the 6 main tabs are searchable" enforces itself.
function KART.BuildSearchIndex()
    local index = {}
    for _, fs in ipairs(KART.UI:GetLabels()) do
        local text = fs:GetText()
        -- Skip hidden labels: a FontString keeps its text after :Hide(), so a conditionally-shown one
        -- (e.g. the council pending-resolution label) would stay searchable and its result row would
        -- scroll to and highlight an invisible, zero-content strip of the panel.
        if text and text ~= "" and fs:IsShown() then
            local ancestor = fs:GetParent()
            local tabIndex
            while ancestor and not tabIndex do
                for _, entry in ipairs(SEARCH_TAB_PANELS) do
                    if ancestor == KART[entry.panel] then
                        tabIndex = entry.tabIndex
                        break
                    end
                end
                ancestor = ancestor:GetParent()
            end
            if tabIndex then
                table.insert(index, { text = text, tabIndex = tabIndex, widget = fs })
            end
        end
    end
    return index
end
