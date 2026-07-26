-- KAUI-1.0: the shared widget toolkit. The only one of the KA libraries with per-consumer
-- state -- the widget registries that ApplyStyle walks. That state is held per namespace, so
-- two addons sharing this library each restyle only their own widgets and each fire only
-- their own locale refreshers.
local MAJOR, MINOR = "KAUI-1.0", 1
local KAUI = LibStub:NewLibrary(MAJOR, MINOR)
if not KAUI then return end

local LSM = LibStub("LibSharedMedia-3.0", true)

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
local DEFAULT_STRATA_INDEX = 4 -- HIGH; used before the consumer's first ApplyStyle call has set self.strata

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
    for _, fs in ipairs(self.closeButtonTexts) do fs:SetFont(font, 14, "OUTLINE") end

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
