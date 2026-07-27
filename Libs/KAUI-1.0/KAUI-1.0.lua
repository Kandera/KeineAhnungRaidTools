-- KAUI-1.0: the shared widget toolkit. The only one of the KA libraries with per-consumer
-- state -- the widget registries that ApplyStyle walks. That state is held per namespace, so
-- two addons sharing this library each restyle only their own widgets and each fire only
-- their own locale refreshers.
local MAJOR, MINOR = "KAUI-1.0", 2
local KAUI = LibStub:NewLibrary(MAJOR, MINOR)
if not KAUI then return end

local LSM = LibStub("LibSharedMedia-3.0", true)
local KAUtil = LibStub("KAUtil-1.0")

KAUI.namespaces = KAUI.namespaces or {}

-- Persisted on the library table (like KAUI.namespaces) rather than as a plain file-local: an
-- existing namespace's metatable keeps pointing at this same table across a library upgrade, so
-- a v2 method added here reaches namespaces created back under v1. A fresh file-local would
-- leave any already-created namespace permanently stuck on the method set frozen at its own
-- creation, since setmetatable captured that local's identity at NewNamespace time, not "whatever
-- nsProto currently means."
KAUI.nsProto = KAUI.nsProto or {}
local nsProto = KAUI.nsProto
local nsMeta = { __index = nsProto }

-- Every registry is an array, never a hash: BuildSearchIndex walks the labels in insertion
-- order and that order decides how search results are sorted.
local REGISTRIES = {
    "labels", "editBoxes", "buttonTexts", "closeButtonTexts",
    "sliderThumbs", "checkVisuals", "accentLines", "accentTextures",
    "tabButtons", "toggleCheckboxes", "localeRefreshers",
    "strataFrames", "strataDialogFrames",
}

function KAUI:NewNamespace(name)
    assert(type(name) == "string" and name ~= "", "KAUI: namespace name must be a non-empty string")
    if self.namespaces[name] then return self.namespaces[name] end
    local ns = setmetatable({ name = name, accent = { 1, 1, 1 }, background = { 0.1, 0.1, 0.1 } }, nsMeta)
    for _, key in ipairs(REGISTRIES) do ns[key] = {} end
    self.namespaces[name] = ns
    return ns
end

-- Every registration method has the same shape: append and return the item so a call site can
-- wrap a creation expression. Accent textures are the one exception (they carry an alpha) and
-- get their own function below.
local function appender(registry)
    return function(ns, item)
        if not item then return item end
        ns[registry][#ns[registry] + 1] = item
        return item
    end
end

nsProto.RegisterLabel           = appender("labels")
nsProto.RegisterEditBox         = appender("editBoxes")
nsProto.RegisterButtonText      = appender("buttonTexts")
nsProto.RegisterCloseButtonText = appender("closeButtonTexts")
nsProto.RegisterSliderThumb     = appender("sliderThumbs")
nsProto.RegisterCheckVisual     = appender("checkVisuals")
nsProto.RegisterAccentLine      = appender("accentLines")
nsProto.RegisterTabButton       = appender("tabButtons")
nsProto.RegisterToggleCheckbox  = appender("toggleCheckboxes")

-- Accent textures carry their own alpha, so they are stored as { texture, alpha } pairs.
-- Replaces five hand-written lines in the consumer's UpdateStyles, one per scroll thumb, each
-- of which had to be remembered when a new scrollbar was added.
function nsProto:RegisterAccentTexture(tex, alpha)
    if not tex then return tex end
    self.accentTextures[#self.accentTextures + 1] = { tex, alpha or 0.6 }
    return tex
end

function nsProto:GetLabels() return self.labels end

function nsProto:RegisterLocaleRefresher(fn)
    self.localeRefreshers[#self.localeRefreshers + 1] = fn
end

function nsProto:ApplyLocaleRefreshers()
    for _, fn in ipairs(self.localeRefreshers) do fn() end
end

-- Ordered list of WoW frame strata a registered window may sit on. All of a consumer's main
-- windows share one configurable stratum (an index into this list, supplied to ApplyStyle's
-- `strata` field) so users can decide whether other UI may cover the addon or not. Transient
-- popups (confirm dialogs etc.) always sit one stratum above the windows so they can't get
-- buried under them.
-- Kept in sync by hand with an identical copy of this list a consumer's own Utils.lua keeps,
-- which drives that consumer's settings slider (range + index-to-name display) since this list
-- is intentionally not exported. If the two ever diverge, the slider names one stratum while
-- this applies another for the same saved index -- check the consumer's copy before changing
-- this list.
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
-- HIGH; used before the consumer's first ApplyStyle call has set self.strata. Mirrors
-- Defaults.frameStrata = 4 in this addon's own Utils.lua -- the same "check the consumer's copy
-- before changing this" caveat as STRATA_ORDER above applies here too.
local DEFAULT_STRATA_INDEX = 4

local function StrataIndex(self)
    local idx = self.strata
    if type(idx) ~= "number" or idx < 1 or idx > #STRATA_ORDER then idx = DEFAULT_STRATA_INDEX end
    return idx
end

function nsProto:GetWindowStrata()
    return STRATA_ORDER[StrataIndex(self)]
end

function nsProto:GetDialogStrata()
    local idx = StrataIndex(self)
    -- TOOLTIP is deliberately not offered for windows, but serves as the "one above" stratum
    -- when the windows themselves are maxed out at FULLSCREEN_DIALOG.
    return STRATA_ORDER[idx + 1] or "TOOLTIP"
end

-- Registers a top-level frame for the shared strata setting and applies the current value.
-- Called once per frame at creation time; ApplyFrameStrata() re-applies on change.
function nsProto:RegisterStrataFrame(frame, isDialog)
    -- Raise on click, like every movable window in the game. Without it a frame keeps whatever
    -- level it was created at for the whole session, so where two of these overlap, the one in
    -- front is decided by creation order and clicking the other does nothing at all -- there was no
    -- way to bring it forward (GitHub issue #4, B24). SetToplevel does exactly this and nothing
    -- else; it acts within the frame's own stratum, so it cannot lift a window over a dialog.
    if frame.SetToplevel then frame:SetToplevel(true) end
    if isDialog then
        self.strataDialogFrames[#self.strataDialogFrames + 1] = frame
        frame:SetFrameStrata(self:GetDialogStrata())
    else
        self.strataFrames[#self.strataFrames + 1] = frame
        frame:SetFrameStrata(self:GetWindowStrata())
    end
end

function nsProto:ApplyFrameStrata()
    local windowStrata, dialogStrata = self:GetWindowStrata(), self:GetDialogStrata()
    for _, f in ipairs(self.strataFrames) do f:SetFrameStrata(windowStrata) end
    for _, f in ipairs(self.strataDialogFrames) do f:SetFrameStrata(dialogStrata) end
end

-- Returns true if a saved window position (a TOPLEFT offset relative to UIParent's BOTTOMLEFT --
-- the anchor every popup restores with) still lands the window on screen. A position saved at a
-- larger resolution or UI scale can otherwise restore a window fully off-screen where it can't be
-- grabbed; callers keep their default anchor when this returns false.
-- The margins are deliberately loose and symmetric: the point is to catch a window stranded
-- entirely off screen (saved at a bigger resolution or UI scale), NOT to enforce that it sits
-- fully inside the viewport. These frames are freely movable and unclamped, and parking one
-- slightly past an edge is normal. Rejecting those would silently reset the user's window
-- position on the next login.
local POS_ON_SCREEN_MARGIN = 60 -- how much of the window must remain reachable, in pixels
function KAUI.IsSavedPosOnScreen(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local m = POS_ON_SCREEN_MARGIN
    return x <= sw - m and x >= -(sw - m) and y >= m and y <= sh + m
end

function nsProto:GetFontPath(name)
    if LSM then
        return LSM:Fetch("font", name)
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Lightens/darkens an RGB triple by `amount` (0-1), clamped to [0,1]. Used to derive hover/
-- pressed/disabled states from a consumer's chosen accent or background color instead of hard-
-- coding separate state colors that would drift out of sync with a custom accent.
function KAUI.Lighten(r, g, b, amount)
    return math.min(r + amount, 1), math.min(g + amount, 1), math.min(b + amount, 1)
end

function KAUI.Darken(r, g, b, amount)
    return math.max(r - amount, 0), math.max(g - amount, 0), math.max(b - amount, 0)
end

-- Returns the accent color last passed to ApplyStyle, as a 0-1 RGB triple.
function nsProto:AccentColor()
    return unpack(self.accent)
end

-- Base color for alternating row stripes: the configured window background lightened a touch.
-- Reads self.background (set by ApplyStyle's `background` field), not any consumer-specific
-- global -- two namespaces with different saved background colors get different stripe colors.
function nsProto:GetRowStripeColor()
    return KAUI.Lighten(self.background[1], self.background[2], self.background[3], 0.06)
end

-- Shared setup for the popup windows' artwork background (1024x768; opaque art box 1002x746,
-- transparent drop-shadow margin L12/R10/T12/B10). The path itself is per-namespace state
-- (self.popupArtworkPath), set by the consumer next to its KAUI:NewNamespace call -- this
-- library ships no addon's folder name, so a second addon sharing it supplies its own art or
-- none at all. A namespace that never set one gets no texture: the frame is left with no `bg`
-- field, which the popup renders as a plain (unthemed) window rather than throwing, and every
-- existing reader of `.bg` (e.g. Core.lua's alpha refresh) already guards for it being absent.
-- The frame is the art area; the texture extends past the frame edges by the margin ratios so
-- the baked shadow stays visible, and the offsets re-scale whenever the frame's size changes
-- (several of these windows resize dynamically). Sublevel -8 keeps the ground under every other
-- BACKGROUND texture the window draws (row stripes, item borders).
function nsProto:ApplyPopupArtwork(frame)
    if not self.popupArtworkPath then return nil end
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture(self.popupArtworkPath)
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
-- ApplyStyle via the namespace's accent-line registry.
function nsProto:CreateHeaderLine(frame, y)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, y)
    self:RegisterAccentLine(line)
    frame.headerLine = line
    return line
end

-- Single source for the header icon button's glyph size, read by both the factory below (initial
-- font) and ApplyStyle (restyle font) so the two can't drift apart -- that drift is exactly what
-- made this glyph small on every button before B5: the factory set one size and ApplyStyle
-- silently re-fonted every button back to its own hardcoded copy on the next restyle.
local CLOSE_BUTTON_GLYPH_SIZE = 18

-- "×"/"-"/"+" header buttons used by every popup window. The glyph FontString registers with
-- this namespace so ApplyStyle keeps its font in sync with the chosen font.
function nsProto:CreateHeaderIconButton(parent, glyph, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(26, 26)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont("Fonts\\FRIZQT__.TTF", CLOSE_BUTTON_GLYPH_SIZE, "OUTLINE")
    btn.text:SetPoint("CENTER", 0, 1)
    btn.text:SetText(glyph or "×")
    self:RegisterCloseButtonText(btn.text)
    btn:SetScript("OnEnter", function(s) s.text:SetTextColor(self:AccentColor()) end)
    btn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Small-radius default for ApplyRoundedMask below, and the size floor under which rounding is
-- skipped entirely. CORNER_RADIUS_MIN_SIZE is used only inside ApplyRoundedMask and stays a
-- private library local. CORNER_RADIUS_SM and CORNER_RADIUS_LG are exported (KAUI.CORNER_RADIUS_*)
-- instead: both are also the exact radii a handful of the addon's own (non-widget-factory) call
-- sites want when they call ApplyRoundedMask explicitly, so one definition of each here -- read
-- by both the relevant factory below and those external call sites -- replaces what would
-- otherwise be two copies of the same number drifting apart.
local CORNER_RADIUS_MIN_SIZE = 16 -- elements smaller than this (either dimension) stay unrounded
KAUI.CORNER_RADIUS_SM = 3 -- buttons, checkboxes, slider thumb
KAUI.CORNER_RADIUS_LG = 6 -- panels, cards, main window

-- Applies rounded-corner masks to a BackdropTemplate frame's backdrop artwork (and its gradient
-- overlay, if any -- see CreateGradientOverlay below). Uses four quarter-circle masks (one per
-- corner) instead of one full-region circle mask, producing proper rounded rectangles. Wrapped
-- in pcall: SetMask behavior varies across client versions, and a failure here must never break
-- the frame's layout or visibility, only skip the rounding.
function nsProto:ApplyRoundedMask(frame, radius)
    if not frame then return end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if w < CORNER_RADIUS_MIN_SIZE or h < CORNER_RADIUS_MIN_SIZE then
        return -- too small to round without looking broken
    end
    radius = radius or KAUI.CORNER_RADIUS_SM

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
-- Defined dot-style with an explicit `ns` receiver (not `nsProto:`/`self`) because the button's
-- own OnEnter/OnLeave callbacks below are conventionally named `self` for the button itself;
-- a consumer's normal colon call syntax (ns:CreateModernButton(...)) works identically either way.
function nsProto.CreateModernButton(ns, parent, text, tooltipText)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(130, 25)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    ns:ApplyRoundedMask(b, KAUI.CORNER_RADIUS_SM)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    ns:RegisterButtonText(b.text)

    -- Hover/leave color is derived from the consumer's chosen accent color (set via ApplyStyle)
    -- via KAUI.Darken instead of a hard-coded gray, so a custom accent color is respected in
    -- the hover state too.
    local function hoverColor()
        local r, g, bl = ns:AccentColor()
        return KAUI.Darken(r, g, bl, 0.55) -- darkened accent, not full brightness, so text stays readable
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

-- Registers a StaticPopup with this namespace's shared modal defaults (no timeout, usable while
-- dead, closable with Escape, drawn above the default UI). Pass only the dialog-specific fields
-- -- these four would otherwise be copy-pasted identically across every popup a consumer defines.
function nsProto:RegisterStaticPopup(name, def)
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
-- Defined dot-style with an explicit `ns` receiver for the same reason as CreateModernButton
-- above: several closures below are conventionally named `self` for the button/frame itself.
function nsProto.CreateTabButton(ns, parent, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(176, 28)
    b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    b:SetBackdropColor(0, 0, 0, 0)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetText(text)
    ns:RegisterButtonText(b.text)

    local accentBar = b:CreateTexture(nil, "OVERLAY")
    accentBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:Hide()
    ns:RegisterSliderThumb(accentBar) -- reuse the accent-coloring loop in ApplyStyle

    local isActive = false

    -- Translucent so the artwork stays visible beneath the active fill.
    local function activeColor()
        local r, g, bl = ns:AccentColor()
        local dr, dg, db = KAUI.Darken(r, g, bl, 0.45)
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
    -- color; called from ApplyStyle when the accent changes.
    function b:RefreshActiveColor()
        if not b:IsMouseOver() then
            restingColor(b)
        end
    end

    ns:RegisterTabButton(b)
    b:SetActive(false)
    return b
end

-- Strips Blizzard's default scrollbar/button textures from a scroll frame, so it can be skinned
-- (or left invisible) instead -- shared by every scrollbar in the addon instead of duplicating
-- this per call site.
function nsProto:StripScrollbarTextures(scrollFrame)
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
function nsProto:AddShowFade(frame, duration)
    local ag = frame:CreateAnimationGroup()
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetDuration(duration or 0.15)
    alpha:SetSmoothing("OUT")

    -- The target alpha is the frame's OWN resting alpha, sampled fresh on every show, not a
    -- hard-coded 1: a window's opacity is often itself a user setting the consumer applies
    -- elsewhere (e.g. a SetAlpha call in its own UpdateStyles), so fading to full would flash
    -- the window opaque and then snap it back down.
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
-- whenever the consumer recomputes the frame's backdrop color (e.g. from its own UpdateStyles).
function nsProto:CreateGradientOverlay(frame)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    return tex
end

-- SetGradient's exact signature has changed across WoW API versions, and this can't be tested
-- outside a live client — pcall so a mismatch just skips the visual flourish instead of breaking
-- the rest of the consumer's own style-refresh pass (fonts, colors, etc.) for every other frame
-- in the same call.
function nsProto:SetGradientOverlayColor(tex, r, g, b, alpha)
    if not tex then return end
    local top    = CreateColor(math.min(r + 0.06, 1), math.min(g + 0.06, 1), math.min(b + 0.06, 1), alpha)
    local bottom = CreateColor(math.max(r - 0.06, 0), math.max(g - 0.06, 0), math.max(b - 0.06, 0), alpha)
    pcall(tex.SetGradient, tex, "VERTICAL", top, bottom)
end

-- UI Factory: Card panel — a rounded, slightly recessed container used to visually group related
-- settings instead of leaving controls floating directly on the tab background. Draws a second,
-- 2px-larger, darker backdrop behind the card as a cheap "shadow" (WoW has no real blur/drop-
-- shadow primitive), then the card's own backdrop on top.
function nsProto:CreateCard(parent, title)
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
    -- calling ApplyRoundedMask here immediately would hit its min-size guard and silently no-op,
    -- leaving the card permanently square. Re-apply on every OnSizeChanged instead --
    -- ApplyRoundedMask is documented as idempotent for exactly this reuse pattern -- so the mask
    -- is (re)established once the caller gives the card real dimensions, and stays correct if
    -- it's resized again later. Shadow's size is derived from card's via the anchors above, so
    -- its own OnSizeChanged fires in lockstep; re-mask it alongside card here rather than adding
    -- a second identical hook on shadow.
    card:HookScript("OnSizeChanged", function()
        self:ApplyRoundedMask(card, KAUI.CORNER_RADIUS_LG)
        self:ApplyRoundedMask(shadow, KAUI.CORNER_RADIUS_LG)
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
        self:RegisterLabel(card.titleText)
    end

    return card
end

-- UI Factory: styled single-line EditBox matching the card look — dark inset fill, rounded
-- corners, subtle resting border, accent-colored border while focused. Registers the box with
-- this namespace for font updates and wires the common OnEscapePressed=ClearFocus behavior.
-- Caller sets size/point and its own OnTextChanged (and SetMaxLetters where needed). The rounded
-- mask is (re)applied on OnSizeChanged like CreateCard does, because the box has no size yet at
-- creation time and ApplyRoundedMask would silently no-op on it here.
-- Defined dot-style with an explicit `ns` receiver for the same reason as CreateModernButton
-- above: the focus-color callback below is conventionally named `self` for the edit box itself.
function nsProto.CreateStyledEditBox(ns, parent, name)
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
        ns:ApplyRoundedMask(eb, KAUI.CORNER_RADIUS_LG)
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        local r, g, b = ns:AccentColor()
        self:SetBackdropBorderColor(r, g, b, 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    ns:RegisterEditBox(eb)
    return eb
end

-- Generic single-line input dialog, replacing three near-identical hand-rolled dialogs (LC sync
-- target, officer note, save profile). Hand-rolled rather than StaticPopup because retail's
-- StaticPopup doesn't reliably expose its edit box to OnAccept.
-- opts = { title, okLabel, cancelLabel, allowEmpty, emptyMessage, maxLetters, initialText, onAccept }
-- okLabel/cancelLabel fall back to Blizzard's own localized ACCEPT/CANCEL strings if the consumer
-- doesn't supply its own -- this library has no locale table of its own to fall back to instead.
-- Defined dot-style with an explicit `ns` receiver for the same reason as CreateModernButton
-- above: the drag callbacks below are conventionally named `self` for the dialog frame itself.
-- The dialog itself is held on self.inputDialog, not a file-local: a file-local would be a single
-- dialog shared by every namespace, so after a split whichever namespace opened it first would
-- own its RegisterStrataFrame/RegisterEditBox registrations forever, and the second namespace's
-- font and frame-strata settings would never reach a dialog it doesn't actually own. Frame names
-- are derived from the namespace's own name for the same reason, rather than a hardcoded prefix.
function nsProto.ShowInputDialog(ns, opts)
    if not ns.inputDialog then
        local f = CreateFrame("Frame", ns.name .. "_InputDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        ns:RegisterStrataFrame(f, true)
        ns:ApplyPopupArtwork(f)
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

        f.editBox = ns:CreateStyledEditBox(f, ns.name .. "_InputDialogEditBox")
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

        f.btnOK = ns:CreateModernButton(f, ACCEPT)
        f.btnOK:SetSize(120, 26)
        f.btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        f.btnOK:SetScript("OnClick", accept)

        f.btnCancel = ns:CreateModernButton(f, CANCEL)
        f.btnCancel:SetSize(120, 26)
        f.btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        f.btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        ns.inputDialog = f
    end
    local f = ns.inputDialog
    f.opts = opts
    f.title:SetText(opts.title)
    -- Re-set both button captions each show so they follow the consumer's own currently active
    -- language -- this addon lets the user pick a language independent of their WoW client
    -- locale, so a caption resolved from ACCEPT/CANCEL (the client's language) would show the
    -- wrong one whenever the two differ.
    f.btnOK.text:SetText(opts.okLabel or ACCEPT)
    f.btnCancel.text:SetText(opts.cancelLabel or CANCEL)
    f.editBox:SetMaxLetters(opts.maxLetters or 64)
    f.editBox:SetText(opts.initialText or "")
    f:Show()
    f.editBox:SetFocus()
    if (opts.initialText or "") ~= "" then f.editBox:HighlightText() end
end

-- opts.store may be the settings table itself, or a zero-argument function that returns it.
-- Resolved fresh at every read/write instead of once at creation time: a consumer that builds
-- its widgets at file load time (as this addon's do, before its own ADDON_LOADED handler has
-- created the real SavedVariables table) would otherwise capture whatever opts.store was at that
-- moment -- typically nil -- and every click/drag afterwards would write into that same stale
-- capture forever. Passing a resolver function instead defers the lookup to callback time, which
-- is what the old key-string API did implicitly by reading a global inside the handler; a
-- consumer whose store already exists at creation time can keep passing the table directly.
local function ResolveStore(store)
    if type(store) == "function" then return store() end
    return store
end

-- opts = {
--   name             frame name, or nil for an anonymous frame
--   label            visible text
--   store            the table holding the setting, or a function returning it -- see ResolveStore above
--   key              the field inside store
--   y                TOPLEFT y offset
--   onChanged        called after the value changes; replaces the old direct UpdateStyles call
--   tooltip          tooltip body text
-- }
-- The settings table is passed per call rather than injected once into the library: after a
-- split there would be two stores and one setter, and the last consumer to initialise would
-- silently win.
-- Toggle-switch style: a pill-shaped track (34x16) with a round dot that slides between left
-- (off) and right (on). Still a real CheckButton under the hood so GetChecked/SetChecked and the
-- existing OnClick wiring below are unchanged for every call site.
-- Defined dot-style with an explicit `ns` receiver for the same reason as CreateModernButton
-- above: refreshVisual below is conventionally named `self` for the checkbox itself.
function nsProto.CreateSettingsCheckbox(ns, parent, opts)
    local cb = CreateFrame("CheckButton", opts.name, parent, "BackdropTemplate")
    cb:SetSize(34, 16)
    cb:SetPoint("TOPLEFT", 20, opts.y)

    cb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(0, 0, 0, 0.5)
    cb:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    -- Pill track is fully rounded: half its own height, which is below the too-small-to-round
    -- floor, so it needs its own mask call with a radius large enough to round the full end-caps
    -- rather than going through the generic small-corner path.
    ns:ApplyRoundedMask(cb, 8)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.text:SetText(opts.label)
    ns:RegisterLabel(cb.text)

    -- Sliding dot: positioned left when unchecked, right when checked. Reused as the "checked
    -- texture" so WoW's own CheckButton show/hide-on-check logic still drives visibility, but its
    -- position (not just visibility) is updated in the click handler below.
    local dot = cb:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", cb, "LEFT", 2, 0)
    cb:SetCheckedTexture(dot)
    ns:RegisterCheckVisual(dot)

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
        local r, g, bl = ns:AccentColor()
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
        ResolveStore(opts.store)[opts.key] = self:GetChecked()
        refreshVisual(self)
        if opts.onChanged then opts.onChanged() end
    end)
    -- Initial state (e.g. when the panel is first built, before any user click) still needs the
    -- dot in the correct position — CheckButton's own SetChecked (called elsewhere when settings
    -- load) doesn't fire OnClick, so hook OnShow as a catch-all.
    cb:HookScript("OnShow", function(self) refreshVisual(self) end)

    -- Exposes refreshVisual so ApplyStyle can re-sync this checkbox's track color to a
    -- freshly-changed accent color, the same way it already does for the dot (via this
    -- namespace's check-visual registry) and slider thumbs/glows (via its slider-thumb registry).
    cb.RefreshVisual = function() refreshVisual(cb) end
    ns:RegisterToggleCheckbox(cb)

    cb.tooltipText = opts.tooltip
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

-- opts = {
--   name             frame name, or nil for an anonymous frame
--   label            visible text
--   min, max         value range
--   store            the table holding the setting, or a function returning it -- see ResolveStore above
--   key              the field inside store
--   y                TOPLEFT y offset (the label sits 16px above this)
--   tooltip          tooltip body text
--   onChanged        called after the value changes. A slider that needs no reaction simply omits
--                    it -- there is no separate opt-out flag, and there must not be one: the
--                    former skipStyleRefresh existed to suppress a hardcoded UpdateStyles call
--                    that no longer exists, and had quietly become a switch that swallowed the
--                    caller's own callback with no error and no symptom (B9).
-- }
-- Defined dot-style with an explicit `ns` receiver for the same reason as CreateModernButton
-- above: the OnValueChanged/OnShow/OnEnter callbacks below are conventionally named `self` for
-- the slider itself.
function nsProto.CreateSettingsSlider(ns, parent, opts)
    local s = CreateFrame("Slider", opts.name, parent, "BackdropTemplate")
    s:SetSize(180, 4) -- thin track instead of the old 14px-tall bar
    s:SetPoint("TOPLEFT", 20, opts.y - 16) -- 16px space reserved for the label above
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(opts.min, opts.max)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    s:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0, 0, 0, 0.5)
    s:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    ns:ApplyRoundedMask(s, 2) -- track is only 4px tall; skips rounding via the min-size guard, kept for future-proofing if track height changes

    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.title:SetText(opts.label)
    ns:RegisterLabel(s.title)

    s.valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)

    -- Soft glow behind the thumb, hidden by default, faded in on hover/drag via alpha rather
    -- than Show/Hide so it never fights another script over the frame's visibility.
    local glow = s:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(20, 20)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetAlpha(0)
    ns:RegisterSliderThumb(glow) -- colored alongside the thumb in ApplyStyle

    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 12)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    s:SetThumbTexture(thumb)
    ns:RegisterSliderThumb(thumb)
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
        ResolveStore(opts.store)[opts.key] = val
        self.valueText:SetText(val)
        positionGlow()
        if opts.onChanged then opts.onChanged() end
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

    s.tooltipText = opts.tooltip
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

-- opts = { store, rKey, gKey, bKey, onApply }
-- onApply runs after both the live-update and the cancel path, so the consumer restyles
-- itself instead of the library reaching into the addon.
function nsProto:OpenColorPicker(opts)
    -- The ORIGINAL 0-100 integers are kept for the cancel path below, not re-derived from the
    -- 0-1 values handed to the picker: round-tripping through /100 and math.floor(x*100) loses
    -- a whole unit for 29, 57 and 58 (binary floating point), so cancelling silently darkened
    -- the colour instead of restoring exactly what was there.
    local store = opts.store
    local origR = store[opts.rKey] or 100
    local origG = store[opts.gKey] or 100
    local origB = store[opts.bKey] or 100
    local startR, startG, startB = origR / 100, origG / 100, origB / 100

    local function onUpdate()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        if not r then return end
        -- Round (+0.5), don't truncate: the picker returns 0-1 floats and plain flooring drops
        -- a full unit off most of them (0.29 * 100 is 28.999…), so every pick drifted darker.
        store[opts.rKey] = math.floor(r * 100 + 0.5)
        store[opts.gKey] = math.floor(g * 100 + 0.5)
        store[opts.bKey] = math.floor(b * 100 + 0.5)
        if opts.onApply then opts.onApply() end
    end

    local function onCancel()
        store[opts.rKey] = origR
        store[opts.gKey] = origG
        store[opts.bKey] = origB
        if opts.onApply then opts.onApply() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR, g = startG, b = startB,
            swatchFunc = onUpdate,
            cancelFunc = onCancel,
        })
    end
end

-- Applies font and accent colour across every registered widget. Everything consumer-specific
-- -- window alpha, window scale, the minimap icon tint, a particular window's title font --
-- stays in the consumer's own UpdateStyles.
function nsProto:ApplyStyle(spec)
    local font        = spec.font
    local menuSize    = spec.menuSize or 11
    local contentSize = spec.contentSize or 12

    self.accent = spec.accent or self.accent
    local r, g, b = self.accent[1], self.accent[2], self.accent[3]

    self.background = spec.background or self.background

    if spec.strata then
        self.strata = spec.strata
        self:ApplyFrameStrata()
    end

    for _, fs in ipairs(self.buttonTexts) do fs:SetFont(font, menuSize, "") end
    for _, eb in ipairs(self.editBoxes) do eb:SetFont(font, contentSize, "") end
    for _, fs in ipairs(self.labels) do fs:SetFont(font, contentSize, "") end
    for _, fs in ipairs(self.closeButtonTexts) do fs:SetFont(font, CLOSE_BUTTON_GLYPH_SIZE, "OUTLINE") end

    for _, tex in ipairs(self.sliderThumbs) do tex:SetColorTexture(r, g, b, 1) end
    for _, tex in ipairs(self.checkVisuals) do tex:SetColorTexture(r, g, b, 1) end
    for _, tex in ipairs(self.accentLines) do tex:SetColorTexture(r, g, b, 0.6) end
    for _, entry in ipairs(self.accentTextures) do entry[1]:SetColorTexture(r, g, b, entry[2]) end

    -- Not simple SetColorTexture calls: these depend on Darken() with different amounts and on
    -- the widget's current checked/active state, so they cannot fold into the loops above.
    for _, btn in ipairs(self.tabButtons) do
        if btn.RefreshActiveColor then btn:RefreshActiveColor() end
    end
    for _, cb in ipairs(self.toggleCheckboxes) do
        if cb.RefreshVisual then cb:RefreshVisual() end
    end
end
