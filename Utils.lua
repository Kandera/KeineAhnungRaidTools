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

-- Locale refreshers: files that build UI text at load time (before the saved language is
-- known) register a function here that re-applies all their static texts from KART.L.
-- Core.lua runs them once at ADDON_LOADED, right after the locale values are copied in.
-- KART.L itself is a STABLE table — its reference must never be replaced, only its values
-- swapped (files capture `local L = KART.L` at load time and keep that reference).
KART.LocaleRefreshers = {}
function KART.RegisterLocaleRefresher(fn)
    table.insert(KART.LocaleRefreshers, fn)
end
function KART.ApplyLocaleRefreshers()
    for _, fn in ipairs(KART.LocaleRefreshers) do fn() end
end

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

-- "×"/"-"/"+" header buttons used by every popup window. The glyph FontString registers in
-- KART.CloseButtonTexts so KART.UpdateStyles keeps its font in sync with the chosen font.
function KART.CreateHeaderIconButton(parent, glyph, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    btn.text:SetPoint("CENTER", 0, 1)
    btn.text:SetText(glyph or "×")
    table.insert(KART.CloseButtonTexts, btn.text)
    btn:SetScript("OnEnter", function(s) s.text:SetTextColor(KART.Theme.AccentColor()) end)
    btn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnClick", onClick)
    return btn
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

-- Whether fullName (a realm-qualified "Name-Realm", as CHAT_MSG_ADDON delivers its sender) is a
-- member of our current group. Used to authorize addon messages that make us answer with our own
-- data, write into a shared cache, or act on someone else's authority — CHAT_MSG_ADDON also carries
-- WHISPER and GUILD, and the "KART" prefix is public, so an unauthorized sender is entirely possible.
--
-- Compares name AND realm separately, never the raw concatenation, because the two sides spell the
-- realm differently:
--   * CHAT_MSG_ADDON's sender is ALWAYS realm-qualified, with the realm in normalized form
--     ("Bob-TarrenMill") — including for a sender on our own realm.
--   * UnitName(unit)'s realm return is nil for a same-realm unit, and for a cross-realm one it may
--     carry the display spelling ("Tarren Mill").
-- So the realm is canonicalized on both sides (separators stripped, case-folded, same treatment
-- Droptimizer applies for the same reason) and a missing realm on either side means "our realm".
-- A raw "name-realm" string compare would reject EVERY same-realm member, silently disabling every
-- handler gated on this.
--
-- Deliberately not routed through Identity.ResolvePlayer: that falls back to a short-name cache
-- lookup for anyone not currently in the group, which would map an outsider onto a same-short-named
-- group member and wrongly authorize them. That is exactly what this function exists to prevent.
local function CanonRealm(realm)
    return KART.CaseFold(((realm or ""):gsub("[%s%-']", "")))
end

function KART.IsFullNameInGroup(fullName)
    if type(fullName) ~= "string" or fullName == "" then return false end
    local wantName, wantRealm = fullName:match("^([^%-]+)%-?(.*)$")
    if not wantName then return false end
    local ownRealm = CanonRealm(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName())
    wantName  = KART.CaseFold(wantName)
    wantRealm = CanonRealm(wantRealm)
    if wantRealm == "" then wantRealm = ownRealm end

    for unit in KART.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local unitRealm = CanonRealm(realm)
            if unitRealm == "" then unitRealm = ownRealm end
            if KART.CaseFold(name) == wantName and unitRealm == wantRealm then return true end
        end
    end
    return false
end

-- Returns true if a saved window position (a TOPLEFT offset relative to UIParent's BOTTOMLEFT — the
-- anchor every KART popup restores with) still lands the window on screen. A position saved at a
-- larger resolution or UI scale can otherwise restore a window fully off-screen where it can't be
-- grabbed; callers keep their default anchor when this returns false.
-- The margins are deliberately loose and symmetric: the point is to catch a window stranded
-- entirely off screen (saved at a bigger resolution or UI scale), NOT to enforce that it sits fully
-- inside the viewport. These frames are freely movable and unclamped, and parking one slightly past
-- an edge is normal — the council panel's tab strip even lives 44px to the LEFT of the frame, so a
-- deliberate negative x is a legitimate saved layout. Rejecting those would silently reset the
-- user's window position on the next login.
local POS_ON_SCREEN_MARGIN = 60 -- how much of the window must remain reachable, in pixels
function KART.IsSavedPosOnScreen(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local m = POS_ON_SCREEN_MARGIN
    return x <= sw - m and x >= -(sw - m) and y >= m and y <= sh + m
end

function KART.SplitString(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

-- Test mode uses plain coloured strings as fake items; guard against SetHyperlink on non-links.
function KART.IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Full item string (itemID + every bonus ID), not just the bare itemID — two drops can share
-- an itemID while being different variants, and comparing only itemID would treat them as
-- interchangeable (see the auto-trade and history-export call sites).
function KART.GetItemString(link)
    return KART.IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
end

-- Case-fold for comparison/search. Lua 5.1's string.lower is ASCII-only, so German umlauts (common
-- on DE realms) don't fold — "Ö" stays "Ö" and never matches "ö". Folds the umlauts too. Not a full
-- Unicode fold, just the letters WoW's German client uses. Fold BOTH sides of any comparison so the
-- result is self-consistent regardless of how the other side cased its input.
function KART.CaseFold(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):lower())
end

function KART.HasGroupPermissions()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Iterates every current raid/party unit token, including the player. Returns (unit, index)
-- so callers that pool rows by position keep their index. Yields nothing when not in a group.
function KART.EachGroupUnit()
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    local i = 0
    return function()
        i = i + 1
        if i > numMem then return nil end
        return (isRaid and ("raid" .. i) or (i == numMem and "player" or "party" .. i)), i
    end
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
    -- CaseFold (not :lower()) so an umlaut nickname folds the same way the promote/council
    -- lists and Identity's name matching fold their side — otherwise umlaut nicks never match.
    return KART.CaseFold(nick), nick
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

-- Base color for alternating row stripes: the configured window background lightened a touch.
-- bgR/bgG/bgB have no settings UI anymore (the background color picker was removed with the
-- artwork rework) but are kept as tunable saved values; this helper is their only consumer.
function KART.GetRowStripeColor()
    local br = (KART_Settings and KART_Settings.bgR or 10) / 100
    local bg = (KART_Settings and KART_Settings.bgG or 10) / 100
    local bb = (KART_Settings and KART_Settings.bgB or 10) / 100
    return KART.Theme.Lighten(br, bg, bb, 0.06)
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
        -- Reuse the mask textures we already created for this region. WoW can't destroy mask
        -- textures, so removing and recreating them on every call (e.g. every OnSizeChanged) would
        -- orphan the old ones for the whole session — instead create the set once, then only
        -- reposition/resize on later calls.
        local existing = region.kartRoundedMasks
        if existing and #existing == #CORNERS then
            for i, corner in ipairs(CORNERS) do
                local m = existing[i]
                m:SetSize(radius, radius)
                m:ClearAllPoints()
                m:SetPoint(corner.point, region, corner.point)
            end
            return
        end

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

    -- Tooltip strings live on the button (not in this closure) so locale refreshers can
    -- update them after the saved language is applied; the headline is the button's current
    -- label so dynamic buttons (font/language pickers) always show their live text.
    b.tooltipText = tooltipText
    b:SetScript("OnEnter", function(self)
        local r, g, bl = hoverColor()
        self:SetBackdropColor(r, g, bl, 1)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        GameTooltip:Hide()
    end)
    return b
end

-- Registers a StaticPopup with KART's shared modal defaults (no timeout, usable while dead, closable
-- with Escape, drawn above the default UI). Pass only the dialog-specific fields — these four were
-- copy-pasted identically across every KART popup.
function KART.RegisterStaticPopup(name, def)
    def.timeout        = 0
    def.whileDead      = true
    def.hideOnEscape   = true
    def.preferredIndex = 3
    StaticPopupDialogs[name] = def ---@diagnostic disable-line: undefined-global
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
        KART.RegisterStrataFrame(f, true)
        KART.ApplyPopupArtwork(f)
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
            local text = KART.TrimString(f.editBox:GetText() or "")
            if text == "" and not o.allowEmpty then
                if o.emptyMessage then UIErrorsFrame:AddMessage(o.emptyMessage, 1, 0.1, 0.1, 1, 3) end
                return
            end
            f:Hide()
            o.onAccept(text)
        end

        f.btnOK = KART.CreateModernButton(f, KART.L.BTN_ACCEPT)
        f.btnOK:SetSize(120, 26)
        f.btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        f.btnOK:SetScript("OnClick", accept)

        f.btnCancel = KART.CreateModernButton(f, KART.L.BTN_CANCEL)
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
    alpha:SetDuration(duration or 0.15)
    alpha:SetSmoothing("OUT")

    -- The target alpha is the frame's OWN resting alpha, sampled fresh on every show, not a
    -- hard-coded 1: the main window's opacity is a user setting (KART.UpdateStyles calls SetAlpha on
    -- it), so fading to full would flash the window opaque and then snap it back down.
    --
    -- restingAlpha is only held for the duration of one run and cleared when it finishes. Keeping it
    -- across runs would mean re-applying a value the opacity slider has since changed, silently
    -- reverting the user's setting the next time the window is opened.
    local restingAlpha
    ag:SetScript("OnFinished", function()
        if restingAlpha then frame:SetAlpha(restingAlpha) end
        restingAlpha = nil
    end)
    frame:HookScript("OnShow", function()
        ag:Stop() -- Stop() fires OnStop, not OnFinished, so the restore below is still needed
        if restingAlpha then frame:SetAlpha(restingAlpha) end -- undo a run cut short mid-fade
        restingAlpha = frame:GetAlpha()
        alpha:SetToAlpha(restingAlpha)
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

-- Recursively fills missing default keys into dst, at every level. Unlike a shallow merge, a nested
-- default table that already exists in dst gets its missing sub-keys added instead of being skipped
-- whole — so a settings/profile blob saved before a nested default gained a field still picks that
-- field up on load. Only fills gaps; never overwrites a value dst already holds.
function KART.MergeDefaults(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = KART.DeepCopy(v)
            else
                KART.MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

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

-- Builds the settings search index by walking KART.DynamicLabels — every settings label already
-- gets inserted there by its creation site (checkboxes, sliders, card titles, hints, tab titles),
-- so no per-widget registration is needed here. A label whose parent chain never reaches one of
-- the 6 main tab panels (e.g. one that belongs to a popup window like Loot History) is silently
-- skipped, which is how "only the 6 main tabs are searchable" enforces itself.
function KART.BuildSearchIndex()
    local index = {}
    for _, fs in ipairs(KART.DynamicLabels) do
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
