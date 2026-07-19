local addonName, KART = ...

local LSM = LibStub("LibSharedMedia-3.0", true)
KART.L = KART.L or {}
KART.EditBoxes = {}
KART.DynamicLabels = {}
KART.SliderThumbs = {}
KART.CheckVisuals = {}
KART.TabButtons = {}
KART.ToggleCheckboxes = {}
KART.ButtonTexts = {}
KART.CloseButtonTexts = {} -- "×" FontStrings on close buttons that aren't already covered by a per-frame UpdateStyles font update
KART.AccentLines = {} -- 1px header lines on popup windows, recolored to the accent color in KART.UpdateStyles

-- Shared setup for the popup windows' artwork background (kart-popup-bg-dark.png, 1024x768;
-- opaque art box 1002x746, transparent drop-shadow margin L12/R10/T12/B10). The frame is the
-- art area; the texture extends past the frame edges by the margin ratios so the baked shadow
-- stays visible, and the offsets re-scale whenever the frame's size changes (several of these
-- windows resize dynamically). Sublevel -8 keeps the ground under every other BACKGROUND
-- texture the window draws (row stripes, item borders).
function KART.ApplyPopupArtwork(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-popup-bg-dark.png")
    local function updateInsets()
        local w, h = frame:GetWidth(), frame:GetHeight()
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -w * 12 / 1002, h * 12 / 746)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", w * 10 / 1002, -h * 10 / 746)
    end
    updateInsets()
    frame:HookScript("OnSizeChanged", updateInsets)
    frame.bg = bg
    return bg
end

-- Accent-colored 1px header line, the code-drawn counterpart of the main window's baked
-- divider (popup windows resize, so it can't live in their artwork). Color applied by
-- KART.UpdateStyles via KART.AccentLines.
function KART.CreateHeaderLine(frame, y)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, y)
    table.insert(KART.AccentLines, line)
    frame.headerLine = line
    return line
end

-- Standardeinstellungen
KART.Defaults = {
    inviteKeywords = "inv;+;invite",
    inviteViaGuildChat = false,
    promoteNames = "",
    showRaidleadBar = false,
    lockRaidleadBar = false,
    autoHideRaidleadBar = false,
    pullTimerDuration = 10,
    keybinds = { readyCheck = nil, clearWorldMarkers = nil, pullTimer = nil, buffCheckToggle = nil },
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
    lcButtonLabels = "BIS;Upgrade;Offspec;Sonstiges;Pass",
    lcCouncilMembers = "",
    lcLootmaster = "",
    lcShowNickNames = false,
    lcVoteLayoutCompact = false,
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

-- Ordered list of WoW frame strata a KART window may sit on. All main windows share one
-- configurable stratum (KART_Settings.frameStrata, stored as an index into this list) so users
-- can decide whether other UI may cover the addon or not. Transient popups (confirm dialogs
-- etc.) always sit one stratum above the windows so they can't get buried under them.
KART.StrataLevels = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
KART.StrataFrames = {}       -- main windows
KART.StrataDialogFrames = {} -- popups shown above the windows

local function StrataIndex()
    local idx = KART_Settings and KART_Settings.frameStrata or KART.Defaults.frameStrata
    if type(idx) ~= "number" or idx < 1 or idx > #KART.StrataLevels then idx = KART.Defaults.frameStrata end
    return idx
end

function KART.GetWindowStrata()
    return KART.StrataLevels[StrataIndex()]
end

function KART.GetDialogStrata()
    local idx = StrataIndex()
    -- TOOLTIP is deliberately not offered for windows, but serves as the "one above" stratum
    -- when the windows themselves are maxed out at FULLSCREEN_DIALOG.
    return KART.StrataLevels[idx + 1] or "TOOLTIP"
end

-- Registers a top-level frame for the shared strata setting and applies the current value.
-- Called once per frame at creation time; KART.ApplyFrameStrata() re-applies on change.
function KART.RegisterStrataFrame(frame, isDialog)
    if isDialog then
        table.insert(KART.StrataDialogFrames, frame)
        frame:SetFrameStrata(KART.GetDialogStrata())
    else
        table.insert(KART.StrataFrames, frame)
        frame:SetFrameStrata(KART.GetWindowStrata())
    end
end

function KART.ApplyFrameStrata()
    local windowStrata, dialogStrata = KART.GetWindowStrata(), KART.GetDialogStrata()
    for _, f in ipairs(KART.StrataFrames) do f:SetFrameStrata(windowStrata) end
    for _, f in ipairs(KART.StrataDialogFrames) do f:SetFrameStrata(dialogStrata) end
end

function KART.TrimString(s)
    return s:match("^%s*(.-)%s*$")
end

function KART.SplitString(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

function KART.HasGroupPermissions()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

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
    return nick:lower(), nick
end

function KART.GetFontPath(name)
    if LSM then
        return LSM:Fetch("font", name)
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Central theme tokens: corner radii, fixed status colors, and color-derivation helpers used by
-- every UI factory function below. Kept as plain data + pure functions (no frame references) so
-- KART.UpdateStyles() can call these fresh on every settings change without caching stale colors.
KART.Theme = {
    CORNER_RADIUS_LG = 6,       -- panels, cards, main window
    CORNER_RADIUS_SM = 3,       -- buttons, checkboxes, slider thumb
    CORNER_RADIUS_MIN_SIZE = 16, -- elements smaller than this (either dimension) stay unrounded

    SUCCESS = {0.35, 0.75, 0.35},
    WARNING = {0.90, 0.70, 0.20},
    DANGER  = {0.85, 0.30, 0.30},
}

-- Lightens/darkens an RGB triple by `amount` (0-1), clamped to [0,1]. Used to derive hover/
-- pressed/disabled states from the user's chosen accent or background color instead of hard-
-- coding separate state colors that would drift out of sync with a custom accent.
function KART.Theme.Lighten(r, g, b, amount)
    return math.min(r + amount, 1), math.min(g + amount, 1), math.min(b + amount, 1)
end

function KART.Theme.Darken(r, g, b, amount)
    return math.max(r - amount, 0), math.max(g - amount, 0), math.max(b - amount, 0)
end

-- Fetches the user's accent color as a 0-1 RGB triple, falling back to the default accent
-- (0, 60, 100 out of 100) when KART_Settings isn't loaded yet. Centralizes the fetch-and-scale
-- pattern that was previously duplicated across CreateModernButton, CreateTabButton, and
-- CreateSettingsCheckbox.
function KART.Theme.AccentColor()
    local r = (KART_Settings and KART_Settings.accentR or 0) / 100
    local g = (KART_Settings and KART_Settings.accentG or 60) / 100
    local b = (KART_Settings and KART_Settings.accentB or 100) / 100
    return r, g, b
end

-- Applies rounded-corner masks to a BackdropTemplate frame's backdrop artwork (and its gradient
-- overlay, if any — see KART.CreateGradientOverlay). Uses four quarter-circle masks (one per corner)
-- instead of one full-region circle mask, producing proper rounded rectangles. Wrapped in pcall:
-- SetMask behavior varies across client versions, and a failure here must never break the frame's
-- layout or visibility, only skip the rounding.
function KART.ApplyRoundedMask(frame, radius)
    if not frame then return end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if w < KART.Theme.CORNER_RADIUS_MIN_SIZE or h < KART.Theme.CORNER_RADIUS_MIN_SIZE then
        return -- too small to round without looking broken
    end
    radius = radius or KART.Theme.CORNER_RADIUS_SM

    -- One quarter-circle mask per corner, sized radius x radius and anchored to that corner, so
    -- only the corners get cropped — pixels outside all four mask footprints (the flat edges and
    -- interior) are untouched, since a region's masks only affect the pixels they geometrically
    -- cover. Texture coordinates select one quadrant of the shared circle mask texture per corner.
    local CORNERS = {
        { point = "TOPLEFT",     coords = {0, 0.5, 0, 0.5} },
        { point = "TOPRIGHT",    coords = {0.5, 1, 0, 0.5} },
        { point = "BOTTOMLEFT",  coords = {0, 0.5, 0.5, 1} },
        { point = "BOTTOMRIGHT", coords = {0.5, 1, 0.5, 1} },
    }

    local function maskRegion(region)
        if not region then return end
        -- Idempotent: drop any masks this helper previously added to this region before adding
        -- new ones, so repeated calls (e.g. after a resize) don't stack masks indefinitely.
        if region.kartRoundedMasks then
            for _, old in ipairs(region.kartRoundedMasks) do
                region:RemoveMaskTexture(old)
            end
        end
        region.kartRoundedMasks = nil

        local applied = {}
        local ok = pcall(function()
            for _, corner in ipairs(CORNERS) do
                local m = frame:CreateMaskTexture(nil, "OVERLAY")
                m:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetTexCoord(unpack(corner.coords))
                m:SetSize(radius, radius)
                m:SetPoint(corner.point, region, corner.point)
                region:AddMaskTexture(m)
                table.insert(applied, m)
            end
        end)
        if ok then
            region.kartRoundedMasks = applied
        else
            -- Partial failure: remove whatever masks this call did manage to add, so the frame
            -- ends up fully unrounded rather than half-rounded.
            for _, m in ipairs(applied) do
                region:RemoveMaskTexture(m)
            end
        end
    end

    if frame.backdropTexture then maskRegion(frame.backdropTexture) end
    -- BackdropTemplate doesn't expose its background texture by name; fall back to scanning
    -- regions for the backdrop's own artwork layer.
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then
            maskRegion(region)
        end
    end
    if frame.gradientBg then maskRegion(frame.gradientBg) end
end

-- UI Factory: Modern Button
function KART.CreateModernButton(parent, text, tooltipText)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(130, 25)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(b, KART.Theme.CORNER_RADIUS_SM)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    table.insert(KART.ButtonTexts, b.text)

    -- Hover/leave color is derived from the user's accent color (KART_Settings.accentR/G/B) via
    -- KART.Theme.Darken instead of a hard-coded gray, so custom accent colors are respected in
    -- the hover state too.
    local function hoverColor()
        local r, g, bl = KART.Theme.AccentColor()
        return KART.Theme.Darken(r, g, bl, 0.55) -- darkened accent, not full brightness, so text stays readable
    end

    b:SetScript("OnEnter", function(self)
        local r, g, bl = hoverColor()
        self:SetBackdropColor(r, g, bl, 1)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        GameTooltip:Hide()
    end)
    return b
end

-- UI Factory: Sidebar tab button, flat style for the PNG-artwork sidebar.
-- Transparent at rest so the baked artwork shows through; subtle white tint
-- on hover; active tab gets a translucent accent fill, a left accent bar and
-- full-white text. Standalone (not built on CreateModernButton) because that
-- factory's opaque backdrop and border would cover the artwork.
function KART.CreateTabButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(176, 28)
    b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    b:SetBackdropColor(0, 0, 0, 0)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetText(text)
    table.insert(KART.ButtonTexts, b.text)

    local accentBar = b:CreateTexture(nil, "OVERLAY")
    accentBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:Hide()
    table.insert(KART.SliderThumbs, accentBar) -- reuse the accent-coloring loop in KART.UpdateStyles

    local isActive = false

    -- Translucent so the artwork stays visible beneath the active fill.
    local function activeColor()
        local r, g, bl = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.45)
        return dr, dg, db, 0.35
    end

    local function restingColor(self)
        if isActive then
            self:SetBackdropColor(activeColor())
        else
            self:SetBackdropColor(0, 0, 0, 0)
        end
        b.text:SetTextColor(isActive and 1 or 0.75, isActive and 1 or 0.75, isActive and 1 or 0.75)
    end

    b:SetScript("OnEnter", function(self)
        if not isActive then self:SetBackdropColor(1, 1, 1, 0.06) end
        b.text:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        restingColor(self)
    end)

    function b:SetActive(active)
        isActive = active
        accentBar:SetShown(active)
        restingColor(b)
    end

    -- Re-applies the current active/inactive color using the latest accent
    -- color; called from KART.UpdateStyles() when the accent changes.
    function b:RefreshActiveColor()
        if not b:IsMouseOver() then
            restingColor(b)
        end
    end

    table.insert(KART.TabButtons, b)
    b:SetActive(false)
    return b
end

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
    KART.ApplyRoundedMask(cb, 8)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.text:SetText(labelText)
    table.insert(KART.DynamicLabels, cb.text)

    -- Sliding dot: positioned left when unchecked, right when checked. Reused as the "checked
    -- texture" so WoW's own CheckButton show/hide-on-check logic still drives visibility, but its
    -- position (not just visibility) is updated in the click handler below.
    local dot = cb:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", cb, "LEFT", 2, 0)
    cb:SetCheckedTexture(dot)
    table.insert(KART.CheckVisuals, dot)

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
        local r, g, bl = KART.Theme.AccentColor()
        if checked then
            -- Explicit alpha (matching the unchecked branch's 0.5) rather than relying on Darken's
            -- 3 return values expanding into SetBackdropColor's 4-arg call: that would leave alpha
            -- unset, and every other SetBackdropColor call site in this file passes alpha
            -- explicitly, so an implicit default here would be an inconsistent one-off.
            local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.35)
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
    -- freshly-changed accent color, the same way it already does for the dot (via
    -- KART.CheckVisuals) and slider thumbs/glows (via KART.SliderThumbs).
    cb.RefreshVisual = function() refreshVisual(cb) end
    table.insert(KART.ToggleCheckboxes, cb)

    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

function KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText)
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
    KART.ApplyRoundedMask(s, 2) -- track is only 4px tall; skips rounding via the min-size guard, kept for future-proofing if track height changes

    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.title:SetText(labelText)
    table.insert(KART.DynamicLabels, s.title)

    s.valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)

    -- Soft glow behind the thumb, hidden by default, faded in on hover/drag via alpha rather
    -- than Show/Hide so it never fights another script over the frame's visibility.
    local glow = s:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(20, 20)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetAlpha(0)
    table.insert(KART.SliderThumbs, glow) -- colored alongside the thumb in KART.UpdateStyles

    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 12)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    s:SetThumbTexture(thumb)
    table.insert(KART.SliderThumbs, thumb)
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
        if KART.UpdateStyles then KART.UpdateStyles() end
    end)
    s:SetScript("OnEnter", function() glow:SetAlpha(0.35) end)
    s:SetScript("OnLeave", function() if not s.isDragging then glow:SetAlpha(0) end end)
    s:HookScript("OnMouseDown", function() s.isDragging = true; glow:SetAlpha(0.5) end)
    s:HookScript("OnMouseUp", function() s.isDragging = false; glow:SetAlpha(0) end)

    if tooltipText then
        s:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        s:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
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
    -- calling KART.ApplyRoundedMask here immediately would hit its min-size guard and silently
    -- no-op, leaving the card permanently square. Re-apply on every OnSizeChanged instead —
    -- ApplyRoundedMask is documented as idempotent for exactly this reuse pattern — so the mask
    -- is (re)established once the caller gives the card real dimensions, and stays correct if
    -- it's resized again later. Shadow's size is derived from card's via the anchors above, so
    -- its own OnSizeChanged fires in lockstep; re-mask it alongside card here rather than adding
    -- a second identical hook on shadow.
    card:HookScript("OnSizeChanged", function()
        KART.ApplyRoundedMask(card, KART.Theme.CORNER_RADIUS_LG)
        KART.ApplyRoundedMask(shadow, KART.Theme.CORNER_RADIUS_LG)
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
        table.insert(KART.DynamicLabels, card.titleText)
    end

    return card
end

-- UI Factory: styled single-line EditBox matching the card look — dark inset fill, rounded
-- corners, subtle resting border, accent-colored border while focused. Registers the box in
-- KART.EditBoxes for font updates and wires the common OnEscapePressed=ClearFocus behavior.
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
        KART.ApplyRoundedMask(eb, KART.Theme.CORNER_RADIUS_LG)
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        local r, g, b = KART.Theme.AccentColor()
        self:SetBackdropBorderColor(r, g, b, 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    table.insert(KART.EditBoxes, eb)
    return eb
end

function KART.UpdateMinimapButton()
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then
        if KART_Settings.showMinimapIcon then
            dbIcon:Show("KeineAhnungRaidTools")
        else
            dbIcon:Hide("KeineAhnungRaidTools")
        end
    end
end

function KART.OpenColorPicker(rKey, gKey, bKey)
    local startR = (KART_Settings[rKey] or 100) / 100
    local startG = (KART_Settings[gKey] or 100) / 100
    local startB = (KART_Settings[bKey] or 100) / 100
    
    local function onUpdate()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        if not r then return end
        KART_Settings[rKey] = math.floor(r * 100)
        KART_Settings[gKey] = math.floor(g * 100)
        KART_Settings[bKey] = math.floor(b * 100)
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    local function onCancel()
        KART_Settings[rKey] = math.floor(startR * 100)
        KART_Settings[gKey] = math.floor(startG * 100)
        KART_Settings[bKey] = math.floor(startB * 100)
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

-- Hidden scanning tooltip for KART.CountMissingGear's gem check below. C_Item.GetItemStats can
-- report a stale EMPTY_SOCKET_* stat for an item that was already gemmed this session (its cached
-- link predates the gem), so we read the socket state straight from the tooltip instead - that's
-- rendered fresh every time and matches exactly what the player sees on hover.
local KART_GearScanTooltip = CreateFrame("GameTooltip", "KART_GearScanTooltip", UIParent, "GameTooltipTemplate")
KART_GearScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Collects the display strings of every "EMPTY_SOCKET_*" global (Prismatic, Red, Cogwheel, ...)
-- instead of hardcoding them, so new socket types added in future patches are picked up automatically.
local emptySocketTexts
local function GetEmptySocketTexts()
    if emptySocketTexts then return emptySocketTexts end
    emptySocketTexts = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and k:match("^EMPTY_SOCKET_") then
            emptySocketTexts[v] = true
        end
    end
    return emptySocketTexts
end

local function SlotHasEmptySocket(slot)
    KART_GearScanTooltip:ClearLines()
    KART_GearScanTooltip:SetInventoryItem("player", slot)
    local texts = GetEmptySocketTexts()
    for i = 1, KART_GearScanTooltip:NumLines() do
        local fs = _G["KART_GearScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and texts[text] then return true end
    end
    return false
end

-- Funktion zum Zählen fehlender Verzauberungen und leerer Sockelplätze (Retail)
function KART.CountMissingGear()
    local missingEnchants = {}
    local missingGems = {}

    -- Slots mit Enchant: Head(1), Shoulders(3), Chest(5), Legs(7), Boots(8), Rings(11,12), Weapon(16)
    local enchantableSlots = {1, 3, 5, 7, 8, 11, 12, 16}
    for _, slot in ipairs(enchantableSlots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local enchant = link:match("item:%d+:(%d*):")
            if not enchant or enchant == "" or enchant == "0" then
                table.insert(missingEnchants, tostring(slot))
            end
        end
    end

    for slot = 1, 17 do
        local link = GetInventoryItemLink("player", slot)
        if link and SlotHasEmptySocket(slot) then
            table.insert(missingGems, tostring(slot))
        end
    end

    local eStr = table.concat(missingEnchants, ",")
    local gStr = table.concat(missingGems, ",")
    if eStr == "" then eStr = "0" end
    if gStr == "" then gStr = "0" end
    return eStr, gStr
end

-- Helper: Scrollbars bereinigen (verhindert Code-Duplizierung)
function KART.StripScrollbarTextures(scrollFrame)
    local sb = _G[scrollFrame:GetName().."ScrollBar"]
    if not sb then return nil end
    local up, down = _G[sb:GetName().."ScrollUpButton"], _G[sb:GetName().."ScrollDownButton"]
    for _, btn in ipairs({up, down}) do
        if btn then
            btn:Hide() btn:SetSize(1, 1)
            for i = 1, btn:GetNumRegions() do
                local region = select(i, btn:GetRegions())
                if region and region:IsObjectType("Texture") then region:SetTexture(nil) end
            end
        end
    end
    for i = 1, sb:GetNumRegions() do
        local region = select(i, sb:GetRegions())
        if region and region:IsObjectType("Texture") then region:SetTexture(nil) end
    end
    local thumb = sb:GetThumbTexture()
    if thumb then thumb:SetTexture("Interface\\Buttons\\WHITE8X8") end
    return thumb
end

-- Adds a short fade-in on every OnShow, so a window appearing feels less abrupt than an instant
-- pop-in. HookScript rather than replacing OnShow so it never interferes with a frame's own show
-- logic, and works no matter which of the frame's (possibly many) callers triggers the Show().
function KART.AddShowFade(frame, duration)
    local ag = frame:CreateAnimationGroup()
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(duration or 0.15)
    alpha:SetSmoothing("OUT")
    frame:HookScript("OnShow", function()
        ag:Stop()
        ag:Play()
    end)
end

-- Adds a subtle vertical gradient overlay on top of a frame's flat backdrop fill, so panels read
-- as less flat without abandoning the existing color-picker-driven backdrop system: the backdrop
-- itself stays the color/alpha source of truth (and remains a safe solid-color fallback everywhere
-- else), this only layers a soft brightness falloff on top of whatever color that resolves to.
-- Sits one sublevel above the backdrop's own BACKGROUND fill so it never covers the BORDER-layer
-- edge texture. Returns the texture so the caller can update its color via SetGradientOverlayColor
-- whenever KART.UpdateStyles() recomputes the frame's backdrop color.
function KART.CreateGradientOverlay(frame)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    return tex
end

-- SetGradient's exact signature has changed across WoW API versions, and this can't be tested
-- outside a live client — pcall so a mismatch just skips the visual flourish instead of breaking
-- the rest of KART.UpdateStyles() (fonts, colors, etc.) for every other frame in the same call.
function KART.SetGradientOverlayColor(tex, r, g, b, alpha)
    if not tex then return end
    local top    = CreateColor(math.min(r + 0.06, 1), math.min(g + 0.06, 1), math.min(b + 0.06, 1), alpha)
    local bottom = CreateColor(math.max(r - 0.06, 0), math.max(g - 0.06, 0), math.max(b - 0.06, 0), alpha)
    pcall(tex.SetGradient, tex, "VERTICAL", top, bottom)
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

-- Plain recursive table copy — KART_Settings only ever holds strings, numbers, booleans, and
-- nested plain tables (e.g. the keybinds/minimap sub-tables), so no metatable/function handling
-- is needed here.
function KART.DeepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            copy[k] = KART.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end
