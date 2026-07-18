local addonName, KART = ...
local L = KART.L

KART.DurabilityCache = {} -- Cache für Reparaturstatus (Haltbarkeit in %)

-- Zentrale Buff-Konfiguration für einfachere Wartung
KART.BuffData = {
    { id = "int",    label = L.BC_LABEL_INT,    col = 2, icon = 135932,  class = "MAGE",    spells = {1459, 264760}, report = "buff", reportLabel = L.BC_REPORT_INT },
    { id = "sta",    label = L.BC_LABEL_STA,    col = 3, icon = 135987,  class = "PRIEST",  spells = {21562}, report = "buff", reportLabel = L.BC_REPORT_STA },
    { id = "motw",   label = L.BC_LABEL_MOTW,   col = 4, icon = 136078,  class = "DRUID",   spells = {1126, 384461}, report = "buff", reportLabel = L.BC_REPORT_MOTW },
    { id = "shout",  label = L.BC_LABEL_SHOUT,  col = 5, icon = 132333,  class = "WARRIOR", spells = {6673}, report = "buff", reportLabel = L.BC_REPORT_SHOUT },
    { id = "bronze", label = L.BC_LABEL_BRONZE, col = 6, icon = 4622448, class = "EVOKER",  spells = {364343, 381732}, nameMatch = "Bronze", report = "buff", reportLabel = L.BC_REPORT_BRONZE },
    { id = "sky",    label = L.BC_LABEL_SKY,    col = 7, icon = 4630367, class = "SHAMAN",  spells = {462854}, nameMatch = "Skyfury", report = "buff", reportLabel = L.BC_REPORT_SKY },
    { id = "food",   label = L.BC_LABEL_FOOD,   col = 8, icon = 134062,  isFood = true, report = "item", reportLabel = L.BC_REPORT_FOOD },
    { id = "flask",  label = L.BC_LABEL_FLASK,  col = 9, icon = 7548903, isFlask = true, report = "item", reportLabel = L.BC_REPORT_FLASK },
    { id = "vantus", label = L.BC_LABEL_VANTUS, col = 10, icon = 5976918, nameMatch = "Vantus" },
    { id = "rune",   label = L.BC_LABEL_RUNE,   col = 11, icon = 4549099, spells = {453112, 1264426}, isRune = true },
    { id = "repair", label = L.BC_LABEL_REPAIR, col = 12, isRepair = true },
    { id = "oil",    label = L.BC_LABEL_OIL,    col = 3, icon = 7548987, isOil = true, bestSpells = {8052}, wrongSpells = {8051}, page = "advanced" },
    { id = "enchants",label= L.BC_LABEL_ENCHANTS,col= 4, isGearCheck = "enchants", page = "advanced" },
    { id = "gems",   label = L.BC_LABEL_GEMS,   col = 5, isGearCheck = "gems", page = "advanced" }
}

KART.SlotNames = {
    ["1"] = L.SLOT_HEAD or "Kopf",
    ["2"] = L.SLOT_NECK or "Hals",
    ["3"] = L.SLOT_SHOULDER or "Schulter",
    ["5"] = L.SLOT_CHEST or "Brust",
    ["7"] = L.SLOT_LEGS or "Beine",
    ["8"] = L.SLOT_FEET or "Füße",
    ["9"] = L.SLOT_WRIST or "Handgelenke",
    ["10"] = L.SLOT_WAIST or "Taille",
    ["11"] = (L.SLOT_FINGER or "Ring").." 1",
    ["12"] = (L.SLOT_FINGER or "Ring").." 2",
    ["16"] = L.SLOT_WEAPON or "Waffe",
    ["17"] = L.SLOT_OFFHAND or "Schildhand"
}

-- Integration von LibDurability (wird durch BigWigs/MRT bereitgestellt)
local LibDurability = LibStub and LibStub("LibDurability", true)
if LibDurability and LibDurability.Register then
    LibDurability:Register("KeineAhnungRaidTools", function(percent, _, sender)
        if type(sender) ~= "string" or type(percent) ~= "number" then return end
        
        KART.DurabilityCache[sender] = percent
        -- Servernamen abschneiden für saubere Zuordnung
        local shortName = sender:match("([^%-]+)")
        if shortName then
            KART.DurabilityCache[shortName] = percent
        end
        -- Live-Update falls Fenster offen
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            KART.UpdateBuffCheckThrottled()
        end
    end)
end

KART.BuffCheckMode = "default" -- Standardmodus: "default" oder "advanced"

-- Buff Check Logik & UI
function KART.CreateBuffCheckFrame()
    if KART.BuffCheckFrame then return end
    local f = CreateFrame("Frame", "KART_BuffCheckFrame", UIParent, "BackdropTemplate")
    f:SetSize(KART_Settings.bcWidth or 710, KART_Settings.bcHeight or 450)
    f:SetPoint(KART_Settings.bcPoint or "CENTER", UIParent, KART_Settings.bcRelativePoint or "CENTER", KART_Settings.bcX or 200, KART_Settings.bcY or 0)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(710, 250, 1200, 1500) -- Breite kann nun auch skaliert werden
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not IsKeyDown("SHIFT") then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) 
        self:StopMovingOrSizing() 
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        KART_Settings.bcPoint = point
        KART_Settings.bcRelativePoint = relativePoint
        KART_Settings.bcX = xOfs
        KART_Settings.bcY = yOfs
    end)
    -- PNG artwork background (kart-popup-bg-dark.png, 1024x768; opaque art box 1002x746 with a
    -- transparent drop-shadow margin of L12/R10/T12/B10). The frame itself is the art area; the
    -- texture extends past the frame edges by the margin ratios so the baked shadow stays
    -- visible. This window resizes freely, so the offsets scale with the current size and are
    -- recomputed from the OnSizeChanged handler below.
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-popup-bg-dark.png")
    local function UpdateBgInsets()
        local w, h = f:GetWidth(), f:GetHeight()
        f.bg:ClearAllPoints()
        f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -w * 12 / 1002, h * 12 / 746)
        f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", w * 10 / 1002, -h * 10 / 746)
    end
    UpdateBgInsets()
    KART.RegisterStrataFrame(f)
    KART.AddShowFade(f)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 16, -12)
    f.title:SetText(L.BC_TITLE)

    -- Code-drawn counterpart of the main window's baked header line (this window resizes
    -- freely, so the line can't live in the artwork). Colored with the user's accent color
    -- in KART.UpdateStyles.
    f.headerLine = f:CreateTexture(nil, "ARTWORK")
    f.headerLine:SetHeight(1)
    f.headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    f.headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)

    -- Header Labels
    local offsets = {35, 145, 185, 225, 265, 310, 355, 395, 445, 495, 545, 590, 635}
    f.headerStrings = {}
    
    -- Neues Label: ReadyCheck (Rdy)
    local hRdy = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRdy:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -35)
    hRdy:SetText("Rdy")
    hRdy:SetTextColor(0.8, 0.8, 0.8)
    f.hRdy = hRdy

    -- Versteckter Header für Item-Level
    local hIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", f, "TOPLEFT", offsets[2], -35)
    hIlvl:SetText(L.BC_LABEL_ILVL or "iLvl")
    hIlvl:SetTextColor(0.8, 0.8, 0.8)
    hIlvl:Hide()
    f.hIlvl = hIlvl

    -- Erstes Label: Name
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("TOPLEFT", f, "TOPLEFT", offsets[1], -35)
    hName:SetText(L.BC_NAME)
    hName:SetTextColor(0.8, 0.8, 0.8)
    f.hName = hName

    -- Dynamische Buff-Header
    for i, data in ipairs(KART.BuffData) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", offsets[data.col], -35)
        h:SetText(data.label)
        h:SetTextColor(0.8, 0.8, 0.8)
        f.headerStrings[i] = h
    end

    -- ScrollFrame für die Spielerliste
    local sf = CreateFrame("ScrollFrame", "KART_BuffCheckScrollFrame", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -55)
    sf:SetPoint("BOTTOMRIGHT", -30, 40)

    KART.BuffScrollThumb = KART.StripScrollbarTextures(sf)
    if KART.BuffScrollThumb then KART.BuffScrollThumb:SetSize(8, 30) end

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(660, 1)
    sf:SetScrollChild(content)
    f.scrollContent = content

    -- Pool für Zeilen (max 40 Spieler)
    f.rows = {}
    for i = 1, 40 do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(660, 26)
        row:SetPoint("TOPLEFT", 0, -(i-1)*26)

        -- Subtle alternating background so a dense 40-row player grid is easier to scan
        -- horizontally. Colored per-row in KART.UpdateBuffCheck (parity depends on the row's
        -- position in the currently-visible list, not its pool index, since rows are reused/
        -- reordered as group membership changes).
        row.stripeBg = row:CreateTexture(nil, "BACKGROUND")
        row.stripeBg:SetAllPoints(row)
        row.stripeBg:SetColorTexture(1, 1, 1, 1) -- placeholder; recolored via SetColorTexture (incl. alpha) per-frame below

        row.rcIcon = row:CreateTexture(nil, "OVERLAY")
        row.rcIcon:SetSize(14, 14)
        row.rcIcon:SetPoint("LEFT", row, "LEFT", 12, 0)
        
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", offsets[1], 0)
        row.name:SetWidth(82) -- leaves just enough room for the reason icon before the next column
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false) -- Verhindert Zeilenumbrüche, nutzt stattdessen den neuen Platz beim Resizen

        -- Kleines Hinweis-Icon statt Inline-Text für Ready-Check-Begründungen: unabhängig von der
        -- Textlänge, kein Überlappen mit den Buff-Icons mehr nötig (siehe voller Text im Tooltip).
        row.reasonIcon = row:CreateTexture(nil, "OVERLAY")
        row.reasonIcon:SetSize(14, 14)
        row.reasonIcon:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
        row.reasonIcon:SetTexture("Interface\\Common\\help-i")
        row.reasonIcon:SetVertexColor(1, 0.85, 0.1)
        row.reasonIcon:Hide()
        row.reasonIcon:EnableMouse(true)
        row.reasonIcon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.reasonText or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.reasonIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ilvlText:SetPoint("LEFT", row, "LEFT", offsets[2] - 10, 0)
        row.ilvlText:Hide()
        
        row.indicators = {}
        for j, data in ipairs(KART.BuffData) do
            if not data.isRepair and not data.isGearCheck then
                local tex = row:CreateTexture(nil, "OVERLAY")
                tex:SetSize(20, 20)
                tex:SetPoint("LEFT", offsets[data.col] - 10, 0)
                tex:SetTexture(data.icon)
                row.indicators[j] = tex
            else
                local frame = CreateFrame("Frame", nil, row)
                frame:SetSize(35, 20)
                frame:SetPoint("LEFT", offsets[data.col] - 10, 0)
                
                local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("LEFT", 0, 0)
                frame.text = text
                
                frame:EnableMouse(true)
                frame:SetScript("OnEnter", function(self)
                    if self.tooltipTitle and self.missingSlots then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
                        
                        local slots = KART.SplitString(self.missingSlots, ",")
                        local countMap = {}
                        local uniqueSlots = {}
                        for _, s in ipairs(slots) do
                            if not countMap[s] then countMap[s] = 0 table.insert(uniqueSlots, s) end
                            countMap[s] = countMap[s] + 1
                        end
                        for _, s in ipairs(uniqueSlots) do
                            local name = KART.SlotNames[s] or ("Slot " .. s)
                            local amt = countMap[s]
                            local amtStr = amt > 1 and (" (x" .. amt .. ")") or ""
                            GameTooltip:AddLine("- " .. name .. amtStr, 1, 0.2, 0.2)
                        end
                        GameTooltip:Show()
                    end
                end)
                frame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
                row.indicators[j] = frame
            end
        end
        row:Hide()
        f.rows[i] = row
    end

    local close = CreateFrame("Button", nil, f, "BackdropTemplate")
    close:SetPoint("TOPRIGHT", -5, -2)
    close:SetSize(20, 20)
    close.text = close:CreateFontString(nil, "OVERLAY")
    close.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("×")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(KART.Theme.AccentColor()) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = close

    local function RequestAdvancedData()
        if IsInGroup() then
            local chan = IsInRaid() and "RAID" or "PARTY"
            C_ChatInfo.SendAddonMessage("KART", "REQ_OIL", chan)
            C_ChatInfo.SendAddonMessage("KART", "REQ_ILVL", chan)
            C_ChatInfo.SendAddonMessage("KART", "REQ_GEAR", chan)
        end
    end

    local modeBtn = KART.CreateModernButton(f, L.BTN_MODE_ADVANCED or "Ansicht: Erweitert")
    modeBtn:SetPoint("BOTTOMLEFT", 10, 10)
    modeBtn:SetSize(150, 22)
    modeBtn:SetScript("OnClick", function() 
        if KART.BuffCheckMode == "advanced" then
            KART.BuffCheckMode = "default"
            modeBtn.text:SetText(L.BTN_MODE_ADVANCED or "Ansicht: Erweitert")
        else
            KART.BuffCheckMode = "advanced"
            modeBtn.text:SetText(L.BTN_MODE_DEFAULT or "Ansicht: Ready Check")
            -- Einmaliges Abrufen beim Wechseln auf die erweiterte Ansicht
            RequestAdvancedData()
        end
        KART.UpdateBuffCheck()
    end)
    f.modeBtn = modeBtn

    f.refreshBtn = KART.CreateModernButton(f, L.BTN_REFRESH)
    f.refreshBtn:SetPoint("BOTTOM", -45, 10)
    f.refreshBtn:SetSize(80, 22)
    f.refreshBtn:SetScript("OnClick", function() 
        -- Alle erweiterten Daten einmalig abrufen (verhindert Dauerspam)
        RequestAdvancedData()
        KART.UpdateBuffCheck() 
        local lib = LibStub and LibStub("LibDurability", true)
        if lib and lib.RequestDurability then
            lib:RequestDurability()
        end
    end)

    f.reportBtn = KART.CreateModernButton(f, L.BTN_REPORT)
    f.reportBtn:SetPoint("BOTTOM", 45, 10)
    f.reportBtn:SetSize(80, 22)
    f.reportBtn:SetScript("OnClick", function() KART.ReportMissingBuffs() end)

    -- Invisible hit area over the resize corner baked into the artwork (bottom right);
    -- HIGHLIGHT-layer texture shows automatically on hover.
    f.resizeBtn = CreateFrame("Button", nil, f)
    f.resizeBtn:SetSize(20, 20)
    f.resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    local resizeHover = f.resizeBtn:CreateTexture(nil, "HIGHLIGHT")
    resizeHover:SetAllPoints()
    resizeHover:SetColorTexture(1, 1, 1, 0.08)
    f.resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.resizeBtn:SetScript("OnMouseUp", function() 
        f:StopMovingOrSizing() 
        KART_Settings.bcWidth = f:GetWidth()
        KART_Settings.bcHeight = f:GetHeight()
    end)

    -- Dynamisches Verschieben der Spalten, wenn das Fenster breiter gezogen wird
    f:SetScript("OnSizeChanged", function(self, width, height)
        UpdateBgInsets() -- keep the artwork's shadow margin proportional to the new size

        local extra = width - 710
        if extra < 0 then extra = 0 end
        
        if self.scrollContent then
            self.scrollContent:SetWidth(660 + extra)
        end
        
        if self.headerStrings then
            for i, h in ipairs(self.headerStrings) do
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", self, "TOPLEFT", offsets[KART.BuffData[i].col] + extra, -35)
            end
        end
        if self.hIlvl then
            self.hIlvl:ClearAllPoints()
            self.hIlvl:SetPoint("TOPLEFT", self, "TOPLEFT", offsets[2] + extra, -35)
        end
        
        for i = 1, 40 do
            local row = self.rows[i]
            if row then
                row:SetWidth(660 + extra)
                if row.name then row.name:SetWidth(82 + extra) end
                if row.ilvlText then
                    row.ilvlText:ClearAllPoints()
                    row.ilvlText:SetPoint("LEFT", row, "LEFT", offsets[2] - 10 + extra, 0)
                end
                for j, ind in ipairs(row.indicators) do
                    ind:ClearAllPoints()
                    ind:SetPoint("LEFT", row, "LEFT", offsets[KART.BuffData[j].col] - 10 + extra, 0)
                end
            end
        end
    end)

    -- Einmaliges Auslösen, falls das Fenster beim Start direkt mit einer breiteren Breite geladen wurde
    local KART_OnSizeChanged = f:GetScript("OnSizeChanged")
    if KART_OnSizeChanged then KART_OnSizeChanged(f, f:GetWidth(), f:GetHeight()) end

    f:Hide()
    KART.BuffCheckFrame = f
    KART.UpdateStyles()
end

-- Master switch for the whole Buff-Checker window/UI (saves CPU for raiders who don't need it).
-- Does NOT affect the KART Sync responder in Core.lua (REQ_OIL/REQ_ILVL/REQ_GEAR) — that keeps
-- answering regardless, so the raid leader still gets accurate data about this player.
function KART.ShowBuffCheck()
    if KART_Settings.bcModuleEnabled == false then
        print("|cff00ff00KART:|r " .. (KART.L.BC_MODULE_DISABLED_MSG or "Buff-Checker is disabled in settings."))
        return
    end
    if not KART.BuffCheckFrame then
        KART.CreateBuffCheckFrame()
    end
    KART.BuffCheckFrame:Show()
    KART.UpdateBuffCheck()
end

-- Throttling für Performance-Optimierung
local isThrottled = false
function KART.UpdateBuffCheckThrottled()
    if isThrottled or not KART.BuffCheckFrame or not KART.BuffCheckFrame:IsShown() then return end
    isThrottled = true
    C_Timer.After(1, function()
        isThrottled = false
        KART.UpdateBuffCheck()
    end)
end

local function setInd(row, idx, has, buffData, classes)
    local ind = row.indicators[idx]
    if not ind then return end
    local classNeeded = buffData.class
    
    if buffData.isRepair then
        local textObj = ind.text or ind
        textObj:SetText(math.floor(has) .. "%")
        if has < 20 then textObj:SetTextColor(unpack(KART.Theme.DANGER))
        elseif has < 50 then textObj:SetTextColor(unpack(KART.Theme.WARNING))
        else textObj:SetTextColor(unpack(KART.Theme.SUCCESS)) end
        ind.tooltipTitle = nil
        ind.missingSlots = nil
        return
    end
    
    if buffData.isGearCheck then
        local textObj = ind.text or ind
        if has == "unknown" or not has then
            textObj:SetText("?")
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.missingSlots = nil
        elseif has == "0" then
            textObj:SetText("OK")
            textObj:SetTextColor(unpack(KART.Theme.SUCCESS))
            ind.missingSlots = nil
        else
            local count = select(2, has:gsub(",", "")) + 1
            textObj:SetText("-" .. count)
            textObj:SetTextColor(unpack(KART.Theme.DANGER))
            ind.missingSlots = has
            ind.tooltipTitle = buffData.reportLabel or buffData.label
        end
        return
    end

    ind:SetDesaturated(not has)
    if has == "expiring" then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 0.8, 0)
                elseif has == "best" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(unpack(KART.Theme.SUCCESS))
                elseif has == "wrong" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(0.8, 0.3, 0.9) -- Lila für falschen Rang
                elseif has == "unknown" then
                    ind:SetAlpha(0.3)
                    ind:SetVertexColor(0.5, 0.5, 0.5) -- Grau für fremde Spieler
    elseif has then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 1, 1)
    elseif classNeeded and not classes[classNeeded] then
        ind:SetAlpha(0.1)
        ind:SetVertexColor(0.5, 0.5, 0.5)
    else
        ind:SetAlpha(0.6)
        ind:SetVertexColor(unpack(KART.Theme.DANGER))
    end
end

function KART.ReportMissingBuffs()
    if not IsInGroup() or not KART.MissingBuffs then return end
    local channel = IsInRaid() and "RAID" or "PARTY"
    
    local delay = 0
    for _, buff in ipairs(KART.BuffData) do
        local list = KART.MissingBuffs[buff.id]
        if list and #list > 0 then
            C_Timer.After(delay, function()
                if buff.report == "buff" then
                    SendChatMessage(L.BC_MISSING .. (buff.reportLabel or buff.label), channel)
                elseif buff.report == "item" then
                    SendChatMessage(L.BC_MISSING .. (buff.reportLabel or buff.label) .. ": " .. table.concat(list, ", "), channel)
                end
            end)
            delay = delay + 0.5 -- 0.5 Sekunden Verzögerung zwischen den Nachrichten zum Schutz vor Disconnects
        end
    end
end

-- WoW FontStrings don't clip or ellipsize automatically when SetWordWrap(false) — text wider than
-- the string's SetWidth just overflows past it into whatever's anchored next (here, the reason
-- icon). Truncates to the widest prefix that fits maxWidth, so the name column never runs into the
-- next column regardless of the user's chosen content font size or how long the name-realm string is.
local function SetTruncatedName(fontString, text, maxWidth)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maxWidth then return end
    local lo, hi, best = 1, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = text:sub(1, mid) .. "..."
        fontString:SetText(candidate)
        if fontString:GetStringWidth() <= maxWidth then
            best = candidate
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    fontString:SetText(best ~= "" and best or "...")
end

-- Comparing aura.spellId can throw if the aura carries "secret" (private-aura) values, which
-- pcall safely catches. Hoisted out of the per-aura loop below (up to 40 players * 100 auras per
-- update) instead of being recreated as a closure on every single call.
local function IsAuraSafe(aura)
    return aura.spellId == 0 and type(aura.name) == "string"
end

function KART.UpdateBuffCheck(isPreview)
    if not KART.BuffCheckFrame then return end

    -- Table-Wiederverwendung für bessere Performance
    KART.MissingBuffs = KART.MissingBuffs or {}
    KART.ClassCache = KART.ClassCache or {}
    wipe(KART.ClassCache)
    
    for _, buff in ipairs(KART.BuffData) do
        if buff.report then
            KART.MissingBuffs[buff.id] = KART.MissingBuffs[buff.id] or {}
            wipe(KART.MissingBuffs[buff.id])
        end
    end

    -- Alle Zeilen verstecken
    for _, row in ipairs(KART.BuffCheckFrame.rows) do row:Hide() end

    if KART.BuffCheckMode == "advanced" then
        for i, h in ipairs(KART.BuffCheckFrame.headerStrings) do 
            if KART.BuffData[i].page == "advanced" then h:Show() else h:Hide() end
        end
        KART.BuffCheckFrame.hIlvl:Show()
    else
        for i, h in ipairs(KART.BuffCheckFrame.headerStrings) do 
            if KART.BuffData[i].page == "advanced" then h:Hide() else h:Show() end
        end
        KART.BuffCheckFrame.hIlvl:Hide()
    end

    if isPreview then
        local rcPreview = {"ready", "notready", "waiting", nil, "ready"}
        local rcReasonsPreview = {nil, "Katze brennt", "Muss kurz zur Tür, der Postbote hat geklingelt", nil, nil}
        for i = 1, 5 do
            local row = KART.BuffCheckFrame.rows[i]
            if row.stripeBg then
                if i % 2 == 0 then
                    local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
                    local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
                    row.stripeBg:SetColorTexture(lr, lg, lb, 0.5)
                    row.stripeBg:Show()
                else
                    row.stripeBg:Hide()
                end
            end

            row.name:SetText(L.BC_EXAMPLE_PLAYER .. i)
            row.name:SetTextColor(0.5, 0.5, 1)

            local rc = rcPreview[i]
            local reason = (rc == "notready" or rc == "waiting") and rcReasonsPreview[i] or nil
            if reason then
                row.reasonIcon.reasonText = reason
                row.reasonIcon:Show()
            else
                row.reasonIcon:Hide()
            end
            
            if rc == "ready" then
                row.rcIcon:SetTexture(136814)
                row.rcIcon:Show()
            elseif rc == "notready" then
                row.rcIcon:SetTexture(136813)
                row.rcIcon:Show()
            elseif rc == "waiting" then
                row.rcIcon:SetTexture(136815)
                row.rcIcon:Show()
            else
                row.rcIcon:Hide()
            end
            
            if KART.BuffCheckMode == "advanced" then
                row.ilvlText:SetText(string.format("%.1f", 620 + i))
                row.ilvlText:SetTextColor(0.2, 1, 0.2)
                row.ilvlText:Show()
            else
                row.ilvlText:Hide()
            end
            
            for j, data in ipairs(KART.BuffData) do
                local ind = row.indicators[j]
                
                if KART.BuffCheckMode == "advanced" then
                    if data.page == "advanced" then ind:Show() else ind:Hide() end
                else
                    if data.page == "advanced" then ind:Hide() else ind:Show() end
                end
                
                if data.isGearCheck then
                    local textObj = ind.text or ind
                    if i == 2 then textObj:SetText("-1"); textObj:SetTextColor(unpack(KART.Theme.DANGER)); ind.missingSlots = "5"; ind.tooltipTitle = data.reportLabel or data.label
                    else textObj:SetText("OK"); textObj:SetTextColor(unpack(KART.Theme.SUCCESS)); ind.missingSlots = nil end
                elseif not data.isRepair then
                    ind:SetDesaturated(false)
                    if i == 1 and j == 7 then -- Beispiel für auslaufendes Food
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(1, 0.8, 0) -- Gelb
                    elseif (i + j) % 3 == 0 then
                        ind:SetAlpha(0.6)
                        ind:SetVertexColor(unpack(KART.Theme.DANGER)) -- Fehlend (Rot)
                    elseif data.isOil and i == 2 then
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(0.8, 0.3, 0.9) -- Lila für Preview
                    elseif data.isOil then
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(unpack(KART.Theme.SUCCESS)) -- best rank, matches setInd's "best" branch
                    else
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(1, 1, 1) -- Vorhanden
                    end
                else
                    local textObj = ind.text or ind
                    textObj:SetText("85%")
                    textObj:SetTextColor(unpack(KART.Theme.SUCCESS))
                end
            end
            row:Show()
        end
        KART.BuffCheckFrame.scrollContent:SetHeight(5 * 26)
        return
    end

    local num = GetNumGroupMembers() or 0
    local isRaid = IsInRaid()
    local buffDataCount = #KART.BuffData
    local timeNow = GetTime()
    
    local iterMax = (num == 0) and 1 or num -- Erlaubt das Anzeigen des Buff-Checks, auch wenn man solo ist

    for i = 1, iterMax do
        local unit = (num == 0) and "player" or (isRaid and ("raid"..i) or (i == num and "player" or "party"..i))
        local _, class = UnitClass(unit)
        if class then KART.ClassCache[class] = true end
    end
    
    KART.BuffStatesCache = KART.BuffStatesCache or {}

    for i = 1, iterMax do
        if i > 40 then break end -- Sicherheitscheck: Verhindert Absturz in Epic BGs (> 40 Spieler)
        local unit = (num == 0) and "player" or (isRaid and ("raid"..i) or (i == num and "player" or "party"..i))
        
        local row = KART.BuffCheckFrame.rows[i]
        if row.stripeBg then
            if i % 2 == 0 then
                local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
                local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
                row.stripeBg:SetColorTexture(lr, lg, lb, 0.5)
                row.stripeBg:Show()
            else
                row.stripeBg:Hide()
            end
        end
        local nameStr = UnitName(unit)
        local _, class = UnitClass(unit)

        -- Offline Check
        if KART_Settings.grayOffline then
            local isConnected = UnitIsConnected(unit)
            row:SetAlpha(isConnected and 1.0 or 0.4)
        else
            row:SetAlpha(1.0)
        end
        
        -- ReadyCheck Status
        local rcStatus = GetReadyCheckStatus(unit)
        if rcStatus == "ready" then
            row.rcIcon:SetTexture(136814)
            row.rcIcon:Show()
        elseif rcStatus == "notready" then
            row.rcIcon:SetTexture(136813)
            row.rcIcon:Show()
        elseif rcStatus == "waiting" then
            row.rcIcon:SetTexture(136815)
            row.rcIcon:Show()
        else
            row.rcIcon:Hide()
        end

        wipe(KART.BuffStatesCache) -- Vor jedem Spieler leeren
        
        -- Zurück zu deiner sicheren und 100% stabilen C_UnitAuras Schleife
        for j = 1, 100 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
            if not aura then break end
            
            -- Überprüfen, ob die Aura "geheime" (secret) Werte enthält (Private Auras).
            -- Ein Vergleich (==) löst bei Secrets einen Fehler aus, den pcall sicher abfängt.
            local isSafe = pcall(IsAuraSafe, aura)

            if isSafe and aura.name then
                for k = 1, buffDataCount do
                    local buff = KART.BuffData[k]
                    local match = false
                    local buffState = true
                    if buff.spells and type(aura.spellId) == "number" then
                        for _, sid in ipairs(buff.spells) do
                            if aura.spellId == sid then match = true end
                        end
                    end
                    if buff.nameMatch and aura.name:find(buff.nameMatch) then match = true end
                    if buff.isFood and (aura.isFullFood or aura.name:find("Satt") or aura.name:find("Well Fed")) then match = true end
                    if buff.isFlask and (aura.name:find("Fläschchen") or aura.name:find("Phial") or aura.name:find("Flask")) then match = true end
                    if buff.isRune and (aura.name:find("Augment") or aura.name:find("Verstärkungsrune")) then match = true end
                    if buff.isOil then
                        if buff.bestSpells and type(aura.spellId) == "number" then
                            for _, sid in ipairs(buff.bestSpells) do
                                if aura.spellId == sid then match = true; buffState = "best" end
                            end
                        end
                        if buff.wrongSpells and type(aura.spellId) == "number" then
                            for _, sid in ipairs(buff.wrongSpells) do
                                if aura.spellId == sid then match = true; buffState = "wrong" end
                            end
                        end
                        if not match and (aura.name:find("Oil") or aura.name:find("oil") or aura.name:find("Öl") or aura.name:find("öl")) then
                            match = true
                            buffState = "best" -- Fallback, bis IDs eingetragen sind
                        end
                    end

                    if match then
                        local expiring = false
                        if aura.expirationTime and aura.expirationTime > 0 then
                            local remaining = aura.expirationTime - timeNow
                            if remaining > 0 and remaining < 300 then
                                expiring = true
                            end
                        end

                        local stateToSet = buffState
                        if expiring and buffState ~= "wrong" then
                            stateToSet = "expiring"
                        end

                        local current = KART.BuffStatesCache[buff.id]
                        if stateToSet == "best" then
                            KART.BuffStatesCache[buff.id] = "best"
                        elseif stateToSet == "expiring" and current ~= "best" then
                            KART.BuffStatesCache[buff.id] = "expiring"
                        elseif stateToSet == "wrong" and current ~= "best" and current ~= "expiring" then
                            KART.BuffStatesCache[buff.id] = "wrong"
                        elseif stateToSet == true and current ~= "best" and current ~= "expiring" and current ~= "wrong" then
                            KART.BuffStatesCache[buff.id] = true
                        end
                    end
                end
            end
        end

        -- 2. Nach der Aura-Schleife prüfen wir auf Waffenverzauberungen (für das Öl)
        for k = 1, buffDataCount do
            local buff = KART.BuffData[k]
            if buff.isOil and KART.BuffStatesCache[buff.id] ~= "best" then
                local match = false
                local buffState = true
                local isExpiring = false

                local function checkEnchant(enchantID, expTime)
                    if not enchantID then return end
                    local found = false
                    if buff.bestSpells then
                        for _, id in ipairs(buff.bestSpells) do
                            if enchantID == id then match = true; buffState = "best"; found = true; break end
                        end
                    end
                    if not found and buff.wrongSpells then
                        for _, id in ipairs(buff.wrongSpells) do
                            if enchantID == id then match = true; buffState = "wrong"; found = true; break end
                        end
                    end
                    if found and expTime and expTime > 0 and expTime < 300000 then -- 300.000 ms = 5 Minuten
                        isExpiring = true
                    end
                end

                if UnitIsUnit(unit, "player") then
                    local hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = GetWeaponEnchantInfo()
                    if hasMH and mhID then checkEnchant(mhID, mhExp) end
                    if not match and hasOH and ohID then checkEnchant(ohID, ohExp) end
                else
                    -- 1. KART Addon Sync auslesen (für Spieler, die KART installiert haben)
                    local shortName = nameStr:match("([^%-]+)")
                    if KART.OilCache and shortName and KART.OilCache[shortName] then
                        local o = KART.OilCache[shortName]
                        if o.mh and o.mh > 0 then checkEnchant(o.mh, 300000) end
                        if not match and o.oh and o.oh > 0 then checkEnchant(o.oh, 300000) end
                    end

                    -- 2. Wenn unbekannt (Addon fehlt), grau anzeigen
                    if not match then
                        buffState = "unknown"
                        match = true
                    end
                end

                if match then
                    local stateToSet = buffState
                    if isExpiring and buffState ~= "wrong" then stateToSet = "expiring" end

                    local current = KART.BuffStatesCache[buff.id]
                    if stateToSet == "best" then
                        KART.BuffStatesCache[buff.id] = "best"
                    elseif stateToSet == "expiring" and current ~= "best" then
                        KART.BuffStatesCache[buff.id] = "expiring"
                    elseif stateToSet == "wrong" and current ~= "best" and current ~= "expiring" then
                        KART.BuffStatesCache[buff.id] = "wrong"
                    elseif stateToSet == "unknown" and current ~= "best" and current ~= "expiring" and current ~= "wrong" then
                        KART.BuffStatesCache[buff.id] = "unknown"
                    elseif stateToSet == true and current ~= "best" and current ~= "expiring" and current ~= "wrong" then
                        KART.BuffStatesCache[buff.id] = true
                    end
                end
            end
        end
        
        local playerMissingEnchants, playerMissingGems
        for k = 1, buffDataCount do
            local buff = KART.BuffData[k]
            if buff.isGearCheck then
                if UnitIsUnit(unit, "player") then
                    if not playerMissingEnchants then playerMissingEnchants, playerMissingGems = KART.CountMissingGear() end
                    KART.BuffStatesCache[buff.id] = (buff.isGearCheck == "enchants") and playerMissingEnchants or playerMissingGems
                else
                    local shortName = nameStr:match("([^%-]+)")
                    if KART.GearCache and shortName and KART.GearCache[shortName] then
                        KART.BuffStatesCache[buff.id] = KART.GearCache[shortName][buff.isGearCheck]
                    else
                        KART.BuffStatesCache[buff.id] = "unknown"
                    end
                end
            end
        end

        -- Row Update
        local shortName = nameStr:match("([^%-]+)")
        SetTruncatedName(row.name, nameStr, row.name:GetWidth())
        local c = RAID_CLASS_COLORS[class] or {r=1, g=1, b=1}
        row.name:SetTextColor(c.r, c.g, c.b)

        local reason = rcStatus == "notready" and shortName and KART.ReadyCheckReasons and KART.ReadyCheckReasons[shortName]
        if reason then
            row.reasonIcon.reasonText = reason
            row.reasonIcon:Show()
        else
            row.reasonIcon:Hide()
        end

        if UnitIsUnit(unit, "player") then
            row.ilvlText:SetText(string.format("%.1f", select(2, GetAverageItemLevel())))
            row.ilvlText:SetTextColor(1, 1, 1)
        else
            local ilvl = shortName and KART.ILvlCache and KART.ILvlCache[shortName]
            if ilvl then
                row.ilvlText:SetText(string.format("%.1f", ilvl))
                row.ilvlText:SetTextColor(1, 1, 1)
            else
                row.ilvlText:SetText("?")
                row.ilvlText:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        if KART.BuffCheckMode == "advanced" then
            row.ilvlText:Show()
        else
            row.ilvlText:Hide()
        end

        for j, buff in ipairs(KART.BuffData) do
            local has = KART.BuffStatesCache[buff.id]
            if buff.isRepair then has = KART.DurabilityCache[nameStr] or 100 end
            setInd(row, j, has, buff, KART.ClassCache)
            
            local isMissing = false
            local missingCount = 0
            if buff.isGearCheck and type(has) == "string" and has ~= "0" and has ~= "unknown" then
                isMissing = true
                missingCount = select(2, has:gsub(",", "")) + 1
            elseif not buff.isGearCheck and not buff.isRepair and (not has or has == "wrong") then
                isMissing = true
            end
            
            if isMissing and buff.report then
                if not buff.class or (buff.class and KART.ClassCache[buff.class]) then
                    local repName = nameStr
                    if buff.isGearCheck then repName = nameStr .. " (-" .. missingCount .. ")" end
                    table.insert(KART.MissingBuffs[buff.id], repName)
                end
            end
            
            if KART.BuffCheckMode == "advanced" then
                if buff.page == "advanced" then row.indicators[j]:Show() else row.indicators[j]:Hide() end
            else
                if buff.page == "advanced" then row.indicators[j]:Hide() else row.indicators[j]:Show() end
            end
        end
        row:Show()
    end
    KART.BuffCheckFrame.scrollContent:SetHeight(iterMax * 26)
end