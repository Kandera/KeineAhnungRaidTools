local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KAGS = LibStub("KAGS-1.0")
local KASC = LibStub("KASC-1.0")
local L = KART.L

KART.DurabilityCache = {} -- Cache für Reparaturstatus (Haltbarkeit in %)

-- Zentrale Buff-Konfiguration für einfachere Wartung.
-- Reviewed 2026-07 (see docs/REVIEW-DECISIONS.md): name fallbacks kept on purpose —
-- flask (no Phiole branch, past Dragonflight; season spell ids are primary) and the bronze
-- fallback ("Bronze"). Do not re-flag these. Vantus matches on spellID with a name fallback
-- for future rune versions. Oil is matched by enchantID only — it has no name detection at all
-- any more, deliberately (see FillPlayerBuffStates in KART.ScanBuffRoster).
KART.BuffData = {
    { id = "int",    labelKey = "BC_LABEL_INT",    col = 2, icon = 135932,  class = "MAGE",    spells = {1459, 264760}, report = "buff", reportLabelKey = "BC_REPORT_INT" },
    { id = "sta",    labelKey = "BC_LABEL_STA",    col = 3, icon = 135987,  class = "PRIEST",  spells = {21562}, report = "buff", reportLabelKey = "BC_REPORT_STA" },
    { id = "motw",   labelKey = "BC_LABEL_MOTW",   col = 4, icon = 136078,  class = "DRUID",   spells = {1126, 384461}, report = "buff", reportLabelKey = "BC_REPORT_MOTW" },
    { id = "shout",  labelKey = "BC_LABEL_SHOUT",  col = 5, icon = 132333,  class = "WARRIOR", spells = {6673}, report = "buff", reportLabelKey = "BC_REPORT_SHOUT" },
    { id = "bronze", labelKey = "BC_LABEL_BRONZE", col = 6, icon = 4622448, class = "EVOKER",  spells = {364343, 381732}, nameMatch = "Bronze", report = "buff", reportLabelKey = "BC_REPORT_BRONZE" },
    { id = "sky",    labelKey = "BC_LABEL_SKY",    col = 7, icon = 4630367, class = "SHAMAN",  spells = {462854}, nameMatch = {"Skyfury", "Himmelszorn"}, report = "buff", reportLabelKey = "BC_REPORT_SKY" },
    { id = "food",   labelKey = "BC_LABEL_FOOD",   col = 8, icon = 134062,  spells = {1232585, 1233713}, isFood = true, report = "item", reportLabelKey = "BC_REPORT_FOOD", whisper = true },
    { id = "flask",  labelKey = "BC_LABEL_FLASK",  col = 9, icon = 7548903, isFlask = true,
      -- Midnight flask buffs. Same four types Northern Sky's ready-check box uses on this
      -- client (crit/mastery/haste/vers); fleeting and personal share the buff. Name
      -- fallback (Fläschchen/Phial/Flask) stays for an id that is not in the list yet.
      spells = {1235111, 1235108, 1235110, 1235057},
      report = "item", reportLabelKey = "BC_REPORT_FLASK", whisper = true },
    { id = "vantus", labelKey = "BC_LABEL_VANTUS", col = 10, icon = 5976918, spells = {1277389, 1303164}, nameMatch = "Vantus" },
    -- whisper without report: Shift-click Report pokes the player; raid chat stays flask/food only.
    { id = "rune",   labelKey = "BC_LABEL_RUNE",   col = 11, icon = 4549099, spells = {453112, 1264426}, isRune = true, whisper = true },
    -- Item/aura IDs are the swap point after a live raid measurement. Healthstone is a bag
    -- item, not an aura: 5512 is the stone, 224464 the demonic one Northern Sky also counts.
    -- Soulstone is aura 20707 on the target, not warlock passive 231811.
    { id = "hs",     labelKey = "BC_LABEL_HS",     col = 12, icon = 538745,  isHealthstone = true, items = {5512, 224464}, class = "WARLOCK" },
    { id = "ss",     labelKey = "BC_LABEL_SS",     col = 13, icon = 136210,  spells = {20707}, class = "WARLOCK" },
    { id = "repair", labelKey = "BC_LABEL_REPAIR", col = 14, isRepair = true },
    -- All three lists hold enchantIDs, not spell ids: the weapon slot is read from
    -- GetWeaponEnchantInfo. Every id was taken from the game's own SpellItemEnchantment table
    -- (wago.tools DB2 export) and 8052 is confirmed against a live client. Temporary weapon enchants
    -- carry a Duration there, which is how each was classified.
    --   bestSpells  = top craft quality (Tier2) weapon consumables: the three enchanting oils plus
    --                 the three blacksmithing stones. All 7200s duration.
    --   offRankSpells = the SAME six at Tier1. Reported as the wrong rank, per the maintainer's rule
    --                 that only the best quality counts. The tiers have no fixed offset — Sharpened
    --                 is 7906/7905 but Weighted is 7907/7908 — so both were looked up, not derived.
    --   neutralSpells = shaman weapon imbues, which occupy this very slot and make an oil impossible.
    --                 Nothing to fix, so they must not be reported. Rogue poisons and the paladin's
    --                 Sacred Weapon are NOT here on purpose: neither is a weapon enchant any more,
    --                 they are player auras, so they never reach this check.
    -- bestSpells VERIFIED 2026-07-25 — all three of Midnight's weapon oils, each read off its own
    -- Wowhead spell page ("Enchant Item - Temporary: <name> (<id>)") and cross-checked against a live
    -- client, which reported 8052 while the player was using Thalassian Phoenix Oil:
    --   8052 Thalassian Phoenix Oil | 8054 Oil of Dawn | 8056 Smuggler's Enchanted Edge
    -- Temporary enchants carry their id on the spell itself, which is why these could be resolved at
    -- all — the permanent armour enchants can NOT (see GOOD_ENCHANTS in Utils.lua).
    --
    -- The commit that replaced the original {8052} claimed "8052/8051 are stale, both are ring
    -- enchantIDs in Midnight". That was false, and it is what broke oil detection: 8052 is the oil,
    -- 7997 is the ring enchant. 8052 had been right all along. Verify before deleting an id.
    --
    -- There is no neutralSpells list any more. It held guessed ids for the class mechanics that
    -- share the weapon slot (shaman imbues, rogue poisons, paladin armaments — the values were
    -- 8012, 8015, 8018, 8201, 8205, 8209, 7150, 7155, none of them verified) and existed only to
    -- keep those from being reported as a wrong-rank oil. rate() no longer reports ANY unrecognised
    -- enchant, so the list had stopped affecting the outcome. Reviving off-rank detection means
    -- verifying those ids first — the old numbers are recorded here purely as a starting point, not
    -- as fact.
    { id = "oil",    labelKey = "BC_LABEL_OIL",    col = 3, icon = 7548987, isOil = true,
      -- Tier2: Thalassian Phoenix Oil, Oil of Dawn, Smuggler's Enchanted Edge,
      --        Sharpened, Weighted, Razor Sharp
      bestSpells    = {8052, 8054, 8056, 7905, 7908, 7910},
      -- The same six at Tier1.
      offRankSpells = {8051, 8053, 8055, 7906, 7907, 7909},
      -- Flametongue and Windfury, both their old and current table entries.
      neutralSpells = {5400, 5401, 5872, 5875}, page = "advanced" },
    { id = "enchants",labelKey= "BC_LABEL_ENCHANTS",col= 4, isGearCheck = "enchants", page = "advanced" },
    { id = "gems",   labelKey = "BC_LABEL_GEMS",   col = 5, isGearCheck = "gems", page = "advanced" },
    { id = "addonRC",   labelKey = "BC_LABEL_RC",   col = 6, isAddonCheck = "RCLootCouncil",        page = "advanced" },
    { id = "addonNSRT", labelKey = "BC_LABEL_NSRT", col = 7, isAddonCheck = "NorthernSkyRaidTools", page = "advanced" },
    { id = "addonWU",   labelKey = "BC_LABEL_WU",   col = 8, isAddonCheck = "wowutils",             page = "advanced" }
}

-- label/reportLabel are resolved from keys so a locale change (applied after file load,
-- see KART.UI:RegisterLocaleRefresher) reaches the baked-at-load BuffData table too.
local function ResolveBuffDataLabels()
    for _, d in ipairs(KART.BuffData) do
        d.label = L[d.labelKey]
        if d.reportLabelKey then d.reportLabel = L[d.reportLabelKey] end
    end
end
ResolveBuffDataLabels()

-- Bag count for our own Healthstone column. Reads BuffData.items so a live-raid ID swap
-- is one table, not a second copy in the comm responder.
-- Presence, not charges: a live dump of GetItemCount(5512) was 1, while includeUses
-- (the third argument) can be 0 on that same item.
function KART.CountOwnHealthstones()
    local fn = C_Item and C_Item.GetItemCount
    if not fn then return 0 end
    local n = 0
    for _, buff in ipairs(KART.BuffData) do
        if buff.isHealthstone and buff.items then
            for _, id in ipairs(buff.items) do
                local ok, c = pcall(fn, id)
                if ok and type(c) == "number" then n = n + c end
            end
        end
    end
    return n
end

local function BuildSlotNames()
    KART.SlotNames = {
        ["1"] = L.SLOT_HEAD,
        ["2"] = L.SLOT_NECK,
        ["3"] = L.SLOT_SHOULDER,
        ["5"] = L.SLOT_CHEST,
        ["7"] = L.SLOT_LEGS,
        ["8"] = L.SLOT_FEET,
        -- Blizzard INVSLOT ids: 6 = Waist, 9 = Wrist, 10 = Hands (slot 10 was previously labelled
        -- "Waist", so an empty gem socket in gloves reported the wrong item and the belt fell through
        -- to the "Slot %d" fallback). Sockets only appear on head/neck/waist/wrist/rings, but
        -- KAGS.CountMissingGear scans slots 1..17, so every slot it can report keeps a name.
        ["6"] = L.SLOT_WAIST,
        ["9"] = L.SLOT_WRIST,
        ["10"] = L.SLOT_HANDS,
        ["11"] = L.SLOT_FINGER .. " 1",
        ["12"] = L.SLOT_FINGER .. " 2",
        ["13"] = L.SLOT_TRINKET .. " 1",
        ["14"] = L.SLOT_TRINKET .. " 2",
        ["15"] = L.SLOT_BACK,
        ["16"] = L.SLOT_WEAPON,
        ["17"] = L.SLOT_OFFHAND,
    }
end
BuildSlotNames()

KART.UI:RegisterLocaleRefresher(function()
    ResolveBuffDataLabels()
    BuildSlotNames()
    -- Window is built lazily (after the refreshers ran), so headers/buttons pick the fresh
    -- labels up at creation. If it already exists, keep the report tooltip and the all-ok
    -- banner on the current language.
    local f = KART.BuffCheckFrame
    if f then
        if f.reportBtn then f.reportBtn.tooltipText = L.TIP_REPORT end
        if f.okBanner then f.okBanner:SetText(L.BC_ALL_CONSUMABLES_OK) end
    end
end)

-- Integration von LibDurability (wird durch BigWigs/MRT bereitgestellt). LibDurability is
-- LibStub-only (no global) and may be provided by an addon that loads AFTER KART (e.g. MRT — "M"
-- sorts after "K"), so the lookup can be nil at parse time. Idempotent + retried from Core's
-- PLAYER_ENTERING_WORLD once every addon has loaded, otherwise the repair column stays 100% for
-- everyone else forever.
function KART.RegisterLibDurability()
    if KART._durabilityRegistered then return end
    local LibDurability = LibStub and LibStub("LibDurability", true)
    if not (LibDurability and LibDurability.Register) then return end
    LibDurability:Register("KeineAhnungRaidTools", function(percent, _, sender)
        if type(sender) ~= "string" or type(percent) ~= "number" then return end
        -- Keyed by short name only — the render side reads DurabilityCache[shortName]. (A full
        -- "Name-Realm" entry was never read.)
        local shortName = sender:match("([^%-]+)")
        if shortName then
            KART.DurabilityCache[shortName] = percent
        end
        -- Live-Update falls Fenster offen
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            KART.UpdateBuffCheckThrottled()
        end
    end)
    KART._durabilityRegistered = true
end
KART.RegisterLibDurability()

KART.BuffCheckMode = "default" -- Standardmodus: "default" oder "advanced"

-- Drops peer data for anyone no longer in the group.
--
-- All of these are keyed by SHORT NAME and were never cleared, which made them wrong in two
-- different ways. Data for someone who left lingered forever and was rendered exactly like fresh
-- data (B17); worse, if Bob-Silvermoon left and Bob-Ravencrest joined, the new Bob silently
-- inherited the old Bob's oil, gear, item level and durability. That is not the accepted
-- simultaneous-namesake case in REVIEW-DECISIONS.md, which is about two namesakes present at once.
--
-- Only departures are purged, not everything: wiping on every GROUP_ROSTER_UPDATE would blank the
-- window repeatedly while a raid fills up, and the data for people who are still here is still good.
function KART.PruneDepartedPeers()
    local present = {}
    for unit in KAUtil.EachGroupUnit() do
        local n = UnitName(unit)
        if n then present[n] = true end
    end
    -- Not ipairs: a nil cache (nobody has answered that question yet) would stop the walk
    -- and leave a later cache unpruned.
    local function prune(cache)
        if type(cache) ~= "table" then return end
        for name in pairs(cache) do
            if not present[name] then cache[name] = nil end
        end
    end
    prune(KART.OilCache)
    prune(KART.ILvlCache)
    prune(KART.GearCache)
    prune(KART.DurabilityCache)
    prune(KART.EnchantScan)
    prune(KART.HSCache)
end

-- ReadyCheck status -> its Blizzard ready-check icon; an unlisted/nil status hides the icon. Shared
-- by the live buff-check rows and the settings preview so both stay identical.
local READY_CHECK_ICONS = { ready = 136814, notready = 136813, waiting = 136815 }
function KART.SetReadyCheckIcon(icon, status)
    local tex = status and READY_CHECK_ICONS[status]
    if tex then
        icon:SetTexture(tex)
        icon:Show()
    else
        icon:Hide()
    end
end

-- Merges one player's result for a buff id into the group-wide cache, keeping the strongest signal
-- seen across the raid: best > expiring > wrong > unknown > present(true). "unknown" only comes from
-- the gear/oil checks; the plain buff/gem path never passes it, so those callers simply never take
-- that branch. Priority is deliberately identical to the two inlined copies this replaced.
local function MergeBuffState(id, stateToSet)
    local current = KART.BuffStatesCache[id]
    if stateToSet == "best" then
        KART.BuffStatesCache[id] = "best"
    elseif stateToSet == "expiring" and current ~= "best" then
        KART.BuffStatesCache[id] = "expiring"
    elseif stateToSet == "wrong" and current ~= "best" and current ~= "expiring" then
        KART.BuffStatesCache[id] = "wrong"
    elseif stateToSet == "unknown" and current ~= "best" and current ~= "expiring" and current ~= "wrong" then
        KART.BuffStatesCache[id] = "unknown"
    elseif stateToSet == true and current ~= "best" and current ~= "expiring" and current ~= "wrong" then
        KART.BuffStatesCache[id] = true
    end
end

-- Buff Check Logik & UI
function KART.CreateBuffCheckFrame()
    if KART.BuffCheckFrame then return end
    local f = CreateFrame("Frame", "KART_BuffCheckFrame", UIParent, "BackdropTemplate")
    -- Two extra columns (HS/SS) need a wider default than the old 710. A saved narrower
    -- width would clip repair; bump it on create, once.
    local BC_BASE_WIDTH, BC_CONTENT_WIDTH = 790, 740
    local w = KART_Settings.bcWidth or BC_BASE_WIDTH
    if w < BC_BASE_WIDTH then w = BC_BASE_WIDTH end
    f:SetSize(w, KART_Settings.bcHeight or 450)
    f:SetPoint(KART_Settings.bcPoint or "CENTER", UIParent, KART_Settings.bcRelativePoint or "CENTER", KART_Settings.bcX or 200, KART_Settings.bcY or 0)
    f:SetMovable(true)
    -- This window stores its position as point/relativePoint/offset (not the TOPLEFT-from-
    -- BOTTOMLEFT pair the LC popups use, so KAUI.IsSavedPosOnScreen doesn't apply). Let WoW keep it
    -- on screen instead: without this, a position saved on a wider monitor or at a different UI
    -- scale restores fully off screen, and since this frame isn't in UISpecialFrames and is only
    -- repositioned by dragging, the only way back is a full settings reset.
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    -- Max height is capped to the screen: taller than that and SetClampedToScreen pins the window
    -- against the top edge with its bottom — including the resize grip and the mode/refresh/report
    -- buttons — off screen and unreachable.
    f:SetResizeBounds(BC_BASE_WIDTH, 250, 1200, math.max(600, math.floor(UIParent:GetHeight())))
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) 
        self:StopMovingOrSizing() 
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        KART_Settings.bcPoint = point
        KART_Settings.bcRelativePoint = relativePoint
        KART_Settings.bcX = xOfs
        KART_Settings.bcY = yOfs
    end)
    KART.UI:ApplyPopupArtwork(f)
    KART.UI:RegisterStrataFrame(f)
    KART.UI:AddShowFade(f)
    KART.UI:ApplyPopupChrome(f, { title = L.BC_TITLE })

    -- Header Labels
    local offsets = {35, 145, 185, 225, 265, 310, 355, 395, 445, 495, 545, 590, 635, 680}
    f.headerStrings = {}
    
    -- Rows live in the scroll child (inset 10px from the window). Ready/name headers
    -- used the window's x and sat left of their columns; buff headers already matched
    -- because those icons subtract the same 10px.
    local ROW_INSET = 10
    local hRdy = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRdy:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_INSET + 12, -35)
    hRdy:SetText("Rdy") -- intentional: short abbreviation kept un-localized by design (review 2026-07-24)
    hRdy:SetTextColor(0.8, 0.8, 0.8)
    f.hRdy = hRdy

    -- Versteckter Header für Item-Level
    local hIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", f, "TOPLEFT", offsets[2], -35)
    hIlvl:SetText(L.BC_LABEL_ILVL)
    hIlvl:SetTextColor(0.8, 0.8, 0.8)
    hIlvl:Hide()
    f.hIlvl = hIlvl

    -- Erstes Label: Name
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_INSET + offsets[1], -35)
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

    local buffScrollThumb = KART.UI:StripScrollbarTextures(sf)
    if buffScrollThumb then buffScrollThumb:SetSize(8, 30) end
    KART.UI:RegisterAccentTexture(buffScrollThumb, 0.6)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(BC_CONTENT_WIDTH, 1)
    sf:SetScrollChild(content)
    f.scrollContent = content

    -- Pool für Zeilen (max 40 Spieler)
    f.rows = {}
    for i = 1, 40 do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(BC_CONTENT_WIDTH, 26)
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

        -- Textures are regions, not frames, so they take no mouse scripts of their own (same reason
        -- the Loot Council panel overlays hitbox frames on its note FontStrings). Put the tooltip on
        -- a small frame tracking the icon instead, shown/hidden alongside it. The reason text lives
        -- on row.reasonIcon, which is what the row update writes to.
        row.reasonHitbox = CreateFrame("Frame", nil, row)
        row.reasonHitbox:SetSize(16, 16)
        row.reasonHitbox:SetPoint("CENTER", row.reasonIcon)
        row.reasonHitbox:EnableMouse(true)
        row.reasonHitbox:Hide()
        row.reasonHitbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.reasonIcon.reasonText or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.reasonHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ilvlText:SetPoint("LEFT", row, "LEFT", offsets[2] - 10, 0)
        row.ilvlText:Hide()
        
        row.indicators = {}
        for j, data in ipairs(KART.BuffData) do
            if not data.isRepair and not data.isGearCheck and not data.isAddonCheck then
                local tex = row:CreateTexture(nil, "OVERLAY")
                tex:SetSize(20, 20)
                tex:SetPoint("LEFT", offsets[data.col] - 10, 0)
                tex:SetTexture(data.icon)
                KAUI.CropSpellIcon(tex)
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
                    if self.addonTip then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.tooltipTitle or "", 1, 1, 1)
                        GameTooltip:AddLine(self.addonTip, 0.8, 0.8, 0.8)
                        GameTooltip:Show()
                    elseif self.tooltipTitle and self.missingSlots then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
                        
                        local slots = KAUtil.SplitString(self.missingSlots, ",")
                        local countMap = {}
                        local uniqueSlots = {}
                        for _, s in ipairs(slots) do
                            if not countMap[s] then countMap[s] = 0 table.insert(uniqueSlots, s) end
                            countMap[s] = countMap[s] + 1
                        end
                        for _, s in ipairs(uniqueSlots) do
                            -- Entries are a slot number, "w"-suffixed when that slot carries the wrong
                            -- enchant rather than none (see KAGS.CountMissingGear). Both variants of a
                            -- slot keep their own line, so the player can tell the two cases apart.
                            local id, wrong = s:match("^(%d+)(w?)$")
                            id = id or s
                            local name = KART.SlotNames[id] or string.format(L.BC_SLOT_FALLBACK, id)
                            if wrong == "w" then name = name .. " " .. L.BC_SLOT_WRONG_ENCHANT end
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

    -- Debounced, and matching the responders' own answer cooldown in KASC. One click asks the whole
    -- raid four questions and every KART client answers all four: 80 outbound messages in a 20-man
    -- raid. A few impatient clicks used to overrun Blizzard's chat rate limiter, which drops the
    -- overflow silently and without retry -- so clicking again to make the missing data appear was
    -- precisely what stopped it from appearing (B16).
    local REQUEST_COOLDOWN = 5
    local lastRequest = -REQUEST_COOLDOWN
    local function RequestAdvancedData()
        if not IsInGroup() then return end
        if GetTime() - lastRequest < REQUEST_COOLDOWN then return end
        lastRequest = GetTime()
        KASC:Send("REQ_OIL")
        KASC:Send("REQ_ILVL")
        KASC:Send("REQ_GEAR")
        KASC:Send("REQ_HS")
    end

    local modeBtn = KART.UI:CreateModernButton(f, L.BTN_MODE_ADVANCED)
    modeBtn:SetPoint("BOTTOMLEFT", 10, 10)
    modeBtn:SetSize(150, 22)
    modeBtn:SetScript("OnClick", function() 
        if KART.BuffCheckMode == "advanced" then
            KART.BuffCheckMode = "default"
            modeBtn.text:SetText(L.BTN_MODE_ADVANCED)
        else
            KART.BuffCheckMode = "advanced"
            modeBtn.text:SetText(L.BTN_MODE_DEFAULT)
            -- Einmaliges Abrufen beim Wechseln auf die erweiterte Ansicht
            RequestAdvancedData()
        end
        KART.UpdateBuffCheck()
    end)
    f.modeBtn = modeBtn

    f.refreshBtn = KART.UI:CreateModernButton(f, L.BTN_REFRESH)
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

    f.reportBtn = KART.UI:CreateModernButton(f, L.BTN_REPORT, L.TIP_REPORT)
    f.reportBtn:SetPoint("BOTTOM", 45, 10)
    f.reportBtn:SetSize(80, 22)
    f.reportBtn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            KART.WhisperMissingConsumables()
        else
            KART.ReportMissingBuffs()
        end
    end)

    f.okBanner = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.okBanner:SetPoint("BOTTOMLEFT", 170, 14)
    f.okBanner:SetPoint("BOTTOMRIGHT", -40, 14)
    f.okBanner:SetJustifyH("LEFT")
    f.okBanner:SetText(L.BC_ALL_CONSUMABLES_OK)
    KART.UI:RegisterLabel(f.okBanner)
    f.okBanner:Hide()

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
        -- Persist the anchor too, not just the size. StartSizing("BOTTOMRIGHT") keeps the TOP-LEFT
        -- corner fixed, but the saved anchor may be CENTER (the default) — restoring a now-wider
        -- window against a centred anchor shifts it sideways by half the growth on the next reload.
        local point, _, relativePoint, xOfs, yOfs = f:GetPoint()
        KART_Settings.bcPoint = point
        KART_Settings.bcRelativePoint = relativePoint
        KART_Settings.bcX = xOfs
        KART_Settings.bcY = yOfs
    end)

    -- Dynamisches Verschieben der Spalten, wenn das Fenster breiter gezogen wird.
    -- HookScript, NOT SetScript: KART.UI:ApplyPopupArtwork already hooked OnSizeChanged to re-scale the
    -- background artwork's inset offsets, and SetScript would replace that whole handler chain. This
    -- is the only resizable KART window, i.e. the only one where that rescale actually matters.
    f:HookScript("OnSizeChanged", function(self, width, height)
        local extra = width - BC_BASE_WIDTH
        if extra < 0 then extra = 0 end
        
        if self.scrollContent then
            self.scrollContent:SetWidth(BC_CONTENT_WIDTH + extra)
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
                row:SetWidth(BC_CONTENT_WIDTH + extra)
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
    if KART.RegisterEditModeFrame then
        KART.RegisterEditModeFrame(f, "EDIT_MODE_LABEL_BUFFCHECK")
    end
    KART.UpdateStyles()
end

function KART.SyncBuffCheckForEditMode()
    local s = KART_Settings
    if KART.IsEditModeActive and KART.IsEditModeActive() and s and s.bcModuleEnabled then
        if not KART.BuffCheckFrame then KART.CreateBuffCheckFrame() end
        if KART.BuffCheckFrame and not KART.BuffCheckFrame:IsShown() then
            KART.editModeOpenedBuffCheck = true
            KART.BuffCheckFrame:Show()
        end
    elseif KART.editModeOpenedBuffCheck then
        KART.editModeOpenedBuffCheck = nil
        if KART.BuffCheckFrame then KART.BuffCheckFrame:Hide() end
    end
    if KART.RefreshEditModeChrome then KART.RefreshEditModeChrome() end
end

-- Master switch for the whole Buff-Checker window/UI (saves CPU for raiders who don't need it).
-- Does NOT affect the KART Sync responder in Core.lua (REQ_OIL/REQ_ILVL/REQ_GEAR) — that keeps
-- answering regardless, so the raid leader still gets accurate data about this player.
function KART.ShowBuffCheck()
    if KART_Settings.bcModuleEnabled == false then
        print("|cff00ff00KART:|r " .. KART.L.BC_MODULE_DISABLED_MSG)
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
        -- Re-check visibility: the window may have been closed during the 1s throttle window, in
        -- which case a full row rebuild is wasted work.
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            -- Preserve preview mode (see KART.UpdateBuffCheck): a refresh triggered while the
            -- settings preview is on screen must re-render the preview, not swap in live rows.
            KART.UpdateBuffCheck(KART.BuffCheckPreviewActive)
        end
    end)
end

local function setInd(row, idx, has, buffData, classes, extra)
    local ind = row.indicators[idx]
    if not ind then return end
    local classNeeded = buffData.class
    
    if buffData.isRepair then
        local textObj = ind.text or ind
        textObj:SetText(math.floor(has) .. "%")
        if has < 20 then textObj:SetTextColor(unpack(KART.DANGER))
        elseif has < 50 then textObj:SetTextColor(unpack(KART.WARNING))
        else textObj:SetTextColor(unpack(KART.SUCCESS)) end
        ind.tooltipTitle = nil
        ind.missingSlots = nil
        return
    end
    
    if buffData.isGearCheck then
        local textObj = ind.text or ind
        if has == "unknown" or not has then
            textObj:SetText("?") -- intentional: status glyph kept un-localized by design (review 2026-07-24)
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.missingSlots = nil
        elseif has == "0" then
            textObj:SetText("OK") -- intentional: status glyph kept un-localized by design (review 2026-07-24)
            textObj:SetTextColor(unpack(KART.SUCCESS))
            ind.missingSlots = nil
        else
            local count = select(2, has:gsub(",", "")) + 1
            textObj:SetText("-" .. count)
            textObj:SetTextColor(unpack(KART.DANGER))
            ind.missingSlots = has
            ind.tooltipTitle = buffData.reportLabel or buffData.label
        end
        return
    end

    if buffData.isAddonCheck then
        local textObj = ind.text or ind
        ind.missingSlots = nil
        ind.tooltipTitle = buffData.label
        if has == "ok" then
            textObj:SetText("✓")
            textObj:SetTextColor(unpack(KART.SUCCESS))
            ind.addonTip = extra
        elseif has == "old" then
            textObj:SetText("✗")
            textObj:SetTextColor(unpack(KART.DANGER))
            ind.addonTip = extra
        elseif has == "missing" then
            textObj:SetText("-")
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.addonTip = (L and L.BC_ADDON_NOT_INSTALLED) or "not installed"
        else
            textObj:SetText("?")
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.addonTip = (L and L.BC_ADDON_NO_HELLO) or "no KART handshake yet"
        end
        return
    end

    -- "unknown" is a non-empty string, which is truthy — without the extra clause a
    -- raider who has not answered looks like they have the buff (full-color icon).
    ind:SetDesaturated(not has or has == "unknown")
    if has == "expiring" then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 0.8, 0)
    elseif has == "best" then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(unpack(KART.SUCCESS))
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
        ind:SetVertexColor(unpack(KART.DANGER))
    end
end

-- SendChatMessage takes at most 255 bytes, and a longer line is not truncated into something the
-- raid can still read -- it does not arrive at all. Two of the checks report NAMES (food and flask,
-- the two most commonly missing things in any raid), and the list used to be concatenated into one
-- message however long it came out. So on the pull where fifteen people have no food, the report
-- silently did nothing: worst exactly when it matters most, with nothing printed on either side.
--
-- Split on name boundaries, never inside one, and repeat the label on each line so the second line
-- still says what it is about. A single name that does not fit on its own cannot be helped; it goes
-- out as its own line and the client refuses that one rather than the whole report.
local CHAT_MSG_MAX = 255

local function SplitNameLines(prefix, names)
    local lines, current = {}, nil
    for _, name in ipairs(names) do
        local candidate = current and (current .. ", " .. name) or (prefix .. name)
        if current and #candidate > CHAT_MSG_MAX then
            lines[#lines + 1] = current
            current = prefix .. name
        else
            current = candidate
        end
    end
    if current then lines[#lines + 1] = current end
    return lines
end

function KART.ConsumablesComplete()
    local missing = KART.MissingBuffs
    if not missing then return true end
    for _, buff in ipairs(KART.BuffData) do
        if buff.whisper then
            local list = missing[buff.id]
            if list and #list > 0 then return false end
        end
    end
    return true
end

local function RefreshOkBanner(isPreview)
    local f = KART.BuffCheckFrame
    if not f or not f.okBanner then return end
    if isPreview or not IsInGroup() or not KART.ConsumablesComplete() then
        f.okBanner:Hide()
    else
        f.okBanner:SetText(L.BC_ALL_CONSUMABLES_OK)
        f.okBanner:Show()
    end
end

-- One whisper per raider, flask/food/rune only. Class buffs stay on the raid Report click.
-- Names are snapshotted now for the same reason ReportMissingBuffs snapshots: MissingBuffs is
-- wiped on the next render, which can land before a staggered C_Timer.After fires.
function KART.WhisperMissingConsumables()
    if not IsInGroup() or not KART.MissingBuffs then return end
    local me = Ambiguate(UnitName("player") or "", "short")
    local byPlayer, order = {}, {}
    for _, buff in ipairs(KART.BuffData) do
        if buff.whisper then
            local list = KART.MissingBuffs[buff.id]
            if list then
                for _, name in ipairs(list) do
                    local short = Ambiguate(name, "short")
                    if short ~= me then
                        if not byPlayer[short] then
                            byPlayer[short] = {}
                            order[#order + 1] = short
                        end
                        byPlayer[short][#byPlayer[short] + 1] = buff.reportLabel or buff.label
                    end
                end
            end
        end
    end
    local delay = 0
    for _, name in ipairs(order) do
        local msg = string.format(L.BC_WHISPER_MISSING, table.concat(byPlayer[name], ", "))
        local target = name
        C_Timer.After(delay, function() SendChatMessage(msg, "WHISPER", nil, target) end)
        delay = delay + 0.5
    end
end

function KART.ReportMissingBuffs()
    if not IsInGroup() or not KART.MissingBuffs then return end
    -- Reviewed 2026-07-25, intentional: RAID/PARTY only, never INSTANCE_CHAT. /Report targets the
    -- organized premade raids this tool is for; posting into LFR/LFG instance chat is deliberately
    -- not supported. Do not re-flag.
    local channel = IsInRaid() and "RAID" or "PARTY"
    
    local delay = 0
    for _, buff in ipairs(KART.BuffData) do
        local list = KART.MissingBuffs[buff.id]
        if list and #list > 0 then
            -- Built now, not inside the timer: this table is wiped/refilled by UpdateBuffCheck
            -- (roster, durability and ready-check ticks all trigger it), so reading it when the
            -- staggered message actually fires up to N*0.5s later could report a stale or empty
            -- player list.
            local label = L.BC_MISSING .. (buff.reportLabel or buff.label)
            local lines
            if buff.report == "buff" then
                lines = { label }
            elseif buff.report == "item" then
                lines = SplitNameLines(label .. ": ", list)
            end
            for _, line in ipairs(lines or {}) do
                C_Timer.After(delay, function() SendChatMessage(line, channel) end)
                delay = delay + 0.5 -- Verzögerung zwischen den Nachrichten zum Schutz vor Disconnects
            end
        end
    end
end

-- WoW FontStrings don't clip or ellipsize automatically when SetWordWrap(false) — text wider than
-- the string's SetWidth just overflows past it into whatever's anchored next (here, the reason
-- icon). Truncates to the widest prefix that fits maxWidth, so the name column never runs into the
-- next column regardless of the user's chosen content font size or how long the name-realm string is.
-- Snaps a byte index back to the end of a full UTF-8 character so a multi-byte glyph (German
-- umlauts are 2 bytes) is never sliced in half — a half glyph renders as a broken "?" box. A UTF-8
-- continuation byte is 0x80-0xBF; if the byte right after i is one, i sits inside a character, so
-- back up until the next byte starts a new character (or the string ends).
local function Utf8Floor(s, i)
    while i > 0 do
        local nb = s:byte(i + 1)
        if not nb or nb < 128 or nb >= 192 then return i end
        i = i - 1
    end
    return i
end

local function SetTruncatedName(fontString, text, maxWidth)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maxWidth then return end
    local lo, hi, best = 1, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = text:sub(1, Utf8Floor(text, mid)) .. "..."
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
-- Built for 12.1's secret aura values. A PROBE rather than a predicate, and the name stays as it is
-- because docs/BACKLOG-12.1.md's P3 entry refers to it by name -- do not rename it without editing that.
--
-- 12.x hands out private auras whose fields are SECRET: reading one is fine, COMPARING one raises. So
-- what this function is for is performing a comparison inside a pcall. The caller reads pcall's `ok` and
-- DISCARDS what this returns, which is correct and deliberate -- and it means the constant is arbitrary:
-- `== 0` tests nothing, any comparison against aura.spellId would do the same job.
--
-- Two ways to "tidy" this break the whole buff check silently, so both are named here. Reading pcall's
-- SECOND return (`local ok, safe = pcall(...)`) would then require spellId to actually be 0, and no aura
-- would ever match again. Removing the comparison because it looks pointless takes away the only thing
-- that throws, after which a secret aura reaches the match loop below.
--
-- What this does NOT cover is the index CALL itself. GetAuraDataByIndex is AllowedWhenUntainted and
-- Lua-errors while auras are secret (combat / encounter / M+ / PvP) if the addon is tainted. The
-- out-of-combat P3 measurement missed that; a live error on party units is what reopened it. The scan
-- below pcalls the index API and falls back to GetUnitAuraBySpellID (AllowedWhenTainted).
local function IsAuraSafe(aura)
    return aura.spellId == 0 and type(aura.name) == "string"
end

local HELPFUL_AURAS = "HELPFUL"

local function IndexAuraScanBlocked()
    local secrets = _G.C_Secrets
    return secrets and secrets.ShouldAurasBeSecret and secrets.ShouldAurasBeSecret() == true
end

-- Second return is true when the client refused the index API (secret + tainted). nil aura with
-- false means "no aura at this index", the normal end of the scan.
local function ReadHelpfulAuraByIndex(unit, index)
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, HELPFUL_AURAS)
    if not ok then return nil, true end
    return aura, false
end

local function ReadAuraBySpellID(unit, spellID)
    local fn = C_UnitAuras.GetUnitAuraBySpellID
    if not fn then return nil end
    local ok, aura = pcall(fn, unit, spellID)
    if ok then return aura end
    return nil
end

local function ApplyHelpfulAura(aura, buffDataCount, timeNow)
    local comparable = pcall(IsAuraSafe, aura)
    if not (comparable and aura.name) then return end

    for k = 1, buffDataCount do
        local buff = KART.BuffData[k]
        local match = false
        if buff.spells and type(aura.spellId) == "number" then
            for _, sid in ipairs(buff.spells) do
                if aura.spellId == sid then match = true end
            end
        end
        if buff.nameMatch then
            -- nameMatch may be a single string or a DE+EN list (spell-name fallback for
            -- when spellId detection misses) — match any of them.
            if type(buff.nameMatch) == "table" then
                for _, nm in ipairs(buff.nameMatch) do
                    if aura.name:find(nm, 1, true) then match = true break end
                end
            elseif aura.name:find(buff.nameMatch, 1, true) then
                match = true
            end
        end
        if buff.isFood and not match and (aura.name:find("gesättigt", 1, true) or aura.name:find("Well Fed", 1, true)) then match = true end
        if buff.isFlask and (aura.name:find("Fläschchen", 1, true) or aura.name:find("Phial", 1, true) or aura.name:find("Flask", 1, true)) then match = true end
        if buff.isRune and (aura.name:find("Augment", 1, true) or aura.name:find("Verstärkungsrune", 1, true)) then match = true end
        -- buff.isOil is deliberately absent from this loop. An oil is a temporary WEAPON
        -- enchant and never shows up as an aura at all, so the only thing this pass could
        -- ever do for it was match by name — and "oil"/"öl" as a bare substring also hits
        -- "Coil", "Turmoil", "Wölfe", "Höllen…". That fallback wrote "wrong", and
        -- MergeBuffState only lets "best" override "wrong", so one such aura pinned the
        -- column red with no way back: a shaman with a legitimate imbue rates 3 (-> true,
        -- blocked) and a raider without KART rates "unknown" (also blocked). Both
        -- authoritative paths already exist in the weapon-enchant pass below
        -- (GetWeaponEnchantInfo for us, KART.OilCache for everyone else), so this only
        -- ever produced false alarms. Do not re-add a name fallback here.

        if match then
            -- Everything this loop can still match is a plain present/absent aura, so the
            -- only distinction left is whether it's about to run out. (There used to be a
            -- "best"/"wrong" state here too — that was the oil, which is rated by
            -- enchantID in the weapon pass below and no longer reaches this loop at all.)
            local expiring = false
            if aura.expirationTime and aura.expirationTime > 0 then
                local remaining = aura.expirationTime - timeNow
                expiring = remaining > 0 and remaining < 300
            end

            MergeBuffState(buff.id, expiring and "expiring" or true)
        end
    end
end

local function ScanHelpfulAurasBySpellID(unit, buffDataCount, timeNow)
    for k = 1, buffDataCount do
        local buff = KART.BuffData[k]
        if buff.spells then
            for _, sid in ipairs(buff.spells) do
                local aura = ReadAuraBySpellID(unit, sid)
                if aura then
                    ApplyHelpfulAura(aura, buffDataCount, timeNow)
                    break
                end
            end
        end
    end
end

-- Aura, oil and gear into BuffStatesCache for one unit. Caller wipes the cache first.
local function FillPlayerBuffStates(unit, shortName, buffDataCount, timeNow)
    local indexScanFailed = IndexAuraScanBlocked()
    if not indexScanFailed then
        for j = 1, 100 do
            local aura, blocked = ReadHelpfulAuraByIndex(unit, j)
            if blocked then
                indexScanFailed = true
                break
            end
            if not aura then break end
            ApplyHelpfulAura(aura, buffDataCount, timeNow)
        end
    end
    if indexScanFailed then
        ScanHelpfulAurasBySpellID(unit, buffDataCount, timeNow)
    end

    for k = 1, buffDataCount do
        local buff = KART.BuffData[k]
        if buff.isOil then
            local rank, isExpiring, rated, hasData = nil, false, false, true

            local function inList(list, id)
                if not list then return false end
                for _, v in ipairs(list) do
                    if v == id then return true end
                end
                return false
            end

            local function rate(enchantID, expTime)
                rated = true
                local r = 1
                if enchantID and enchantID > 0 then
                    if inList(buff.bestSpells, enchantID) then r = 4
                    elseif inList(buff.offRankSpells, enchantID) then r = 2
                    else r = 3 end
                end
                if r == 4 and expTime and expTime > 0 and expTime < 300000 then
                    isExpiring = true
                end
                if not rank or r < rank then rank = r end
            end

            if UnitIsUnit(unit, "player") then
                local hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = GetWeaponEnchantInfo()
                if KAGS.SlotNeedsOil(16) then rate(hasMH and mhID or 0, mhExp) end
                if KAGS.SlotNeedsOil(17) then rate(hasOH and ohID or 0, ohExp) end
            else
                local o = KART.OilCache and shortName and KART.OilCache[shortName]
                hasData = o ~= nil
                if o then
                    if o.mh ~= "n" then rate(o.mh, 300000) end
                    if o.oh ~= "n" then rate(o.oh, 300000) end
                end
            end

            local stateToSet
            if not hasData then
                stateToSet = "unknown"
            elseif not rated then
                stateToSet = true
            elseif rank == 4 then
                stateToSet = isExpiring and "expiring" or "best"
            elseif rank == 3 then
                stateToSet = true
            elseif rank == 2 then
                stateToSet = "wrong"
            end
            if stateToSet then MergeBuffState(buff.id, stateToSet) end
        end
        if buff.isHealthstone then
            if UnitIsUnit(unit, "player") then
                if KART.CountOwnHealthstones() > 0 then MergeBuffState(buff.id, true) end
            else
                local cached = shortName and KART.HSCache and KART.HSCache[shortName]
                if cached == nil then
                    MergeBuffState(buff.id, "unknown")
                elseif cached then
                    MergeBuffState(buff.id, true)
                end
            end
        end
    end

    local playerMissingEnchants, playerMissingGems
    for k = 1, buffDataCount do
        local buff = KART.BuffData[k]
        if buff.isGearCheck then
            if UnitIsUnit(unit, "player") then
                if not playerMissingEnchants then playerMissingEnchants, playerMissingGems = KAGS.CountMissingGear() end
                KART.BuffStatesCache[buff.id] = (buff.isGearCheck == "enchants") and playerMissingEnchants or playerMissingGems
            else
                if KART.GearCache and shortName and KART.GearCache[shortName] then
                    KART.BuffStatesCache[buff.id] = KART.GearCache[shortName][buff.isGearCheck]
                else
                    KART.BuffStatesCache[buff.id] = "unknown"
                end
            end
        end
        if buff.isAddonCheck then
            local mine = KART.NeighborVersion(buff.isAddonCheck)
            local hasHello, theirs
            if UnitIsUnit(unit, "player") then
                hasHello, theirs = true, mine
            else
                hasHello = shortName and KART.PlayerVersions and KART.PlayerVersions[shortName] ~= nil
                theirs = shortName and KART.PlayerAddonVersions and KART.PlayerAddonVersions[shortName]
                    and KART.PlayerAddonVersions[shortName][buff.isAddonCheck]
            end
            KART.BuffStatesCache[buff.id] = KART.AddonCellStatus(theirs, mine, hasHello)
        end
    end
end

local function GroupUnitAt(i, num, isRaid)
    if num == 0 then return "player" end
    if isRaid then return "raid" .. i end
    return (i == num) and "player" or ("party" .. i)
end

-- Roster snapshot: per-player buff states and MissingBuffs. No frames. Paint and the
-- tonight strip both read this so flask/food cannot disagree. Preview rows do not scan.
function KART.ScanBuffRoster()
    KART.MissingBuffs = KART.MissingBuffs or {}
    KART.ClassCache = KART.ClassCache or {}
    wipe(KART.ClassCache)

    for _, buff in ipairs(KART.BuffData) do
        if buff.report or buff.whisper then
            KART.MissingBuffs[buff.id] = KART.MissingBuffs[buff.id] or {}
            wipe(KART.MissingBuffs[buff.id])
        end
    end

    local num = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local buffDataCount = #KART.BuffData
    local timeNow = GetTime()
    local iterMax = (num == 0) and 1 or num
    local players = {}

    for i = 1, iterMax do
        local unit = GroupUnitAt(i, num, isRaid)
        local _, class = UnitClass(unit)
        if class then KART.ClassCache[class] = true end
    end

    KART.BuffStatesCache = KART.BuffStatesCache or {}

    for i = 1, iterMax do
        if i > 40 then break end
        local unit = GroupUnitAt(i, num, isRaid)
        local nameStr = UnitName(unit) or UNKNOWN ---@diagnostic disable-line: undefined-global
        local shortName = nameStr:match("([^%-]+)")
        local _, class = UnitClass(unit)

        wipe(KART.BuffStatesCache)
        FillPlayerBuffStates(unit, shortName, buffDataCount, timeNow)

        for _, buff in ipairs(KART.BuffData) do
            local has = KART.BuffStatesCache[buff.id]
            if buff.isRepair then has = (shortName and KART.DurabilityCache[shortName]) or 100 end
            local isMissing = not buff.isGearCheck and not buff.isRepair and not buff.isAddonCheck
                and (not has or has == "wrong")
            if isMissing and (buff.report or buff.whisper) and buff.page ~= "advanced" then
                if not buff.class or KART.ClassCache[buff.class] then
                    table.insert(KART.MissingBuffs[buff.id], nameStr)
                end
            end
        end

        local states = {}
        for id, st in pairs(KART.BuffStatesCache) do states[id] = st end

        local rcStatus = GetReadyCheckStatus(unit)
            or (KART.ReadyCheckStatus and shortName and KART.ReadyCheckStatus[shortName])
        local reason = shortName and KART.ReadyCheckReasons and KART.ReadyCheckReasons[shortName]
        local ilvl, ilvlKnown
        if UnitIsUnit(unit, "player") then
            ilvl = select(2, GetAverageItemLevel())
            ilvlKnown = true
        else
            ilvl = shortName and KART.ILvlCache and KART.ILvlCache[shortName]
            ilvlKnown = ilvl ~= nil
        end

        players[#players + 1] = {
            unit = unit,
            name = nameStr,
            shortName = shortName,
            class = class,
            connected = UnitIsConnected(unit),
            rcStatus = rcStatus,
            reason = reason,
            ilvl = ilvl,
            ilvlKnown = ilvlKnown,
            repair = (shortName and KART.DurabilityCache[shortName]) or 100,
            states = states,
        }
    end

    local snap = { players = players }
    KART.BuffRosterSnapshot = snap
    return snap
end

-- People in the group missing flask or food. Independent of the Buff Check window: the main
-- window's tonight strip has to answer this without opening that frame. One person missing both
-- still counts as one. Uses the same scan as the window so the number cannot disagree.
function KART.CountMissingFlaskFood()
    if not IsInGroup() then return 0 end
    KART.ScanBuffRoster()
    local seen, n = {}, 0
    for _, id in ipairs({ "flask", "food" }) do
        for _, name in ipairs(KART.MissingBuffs[id] or {}) do
            if not seen[name] then
                seen[name] = true
                n = n + 1
            end
        end
    end
    return n
end

function KART.UpdateBuffCheck(isPreview)
    if not KART.BuffCheckFrame then return end
    -- Remember which mode the window is currently rendering. The throttled refresh (fired by roster
    -- events, incoming sync data and KART.UpdateStyles) has no argument of its own, so without this
    -- it would re-render the settings preview as live data — replacing the sample rows the moment
    -- the user touches the very sliders the preview exists to demonstrate.
    KART.BuffCheckPreviewActive = isPreview and true or false

    -- Table-Wiederverwendung für bessere Performance
    KART.MissingBuffs = KART.MissingBuffs or {}
    KART.ClassCache = KART.ClassCache or {}
    wipe(KART.ClassCache)
    
    for _, buff in ipairs(KART.BuffData) do
        if buff.report or buff.whisper then
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
        -- Intentional: these preview sample reasons stay hardcoded German by design — sample data
        -- for the settings preview only, never shown in the live ready-check (review 2026-07-24).
        -- Indexed 1..5 explicitly by the loop below (the embedded nil means # / ipairs would stop
        -- early — don't convert these to ipairs). Only "notready" rows carry a reason, matching the
        -- live path, so both sample reasons sit on the one "notready" row: the long one demonstrates
        -- the tooltip wrapping that the reason icon exists for.
        local rcPreview = {"ready", "notready", "waiting", nil, "ready"}
        local rcReasonsPreview = {nil, "Muss kurz zur Tür, der Postbote hat geklingelt", nil, nil, nil}
        for i = 1, 5 do
            local row = KART.BuffCheckFrame.rows[i]
            if row.stripeBg then
                if i % 2 == 0 then
                    local lr, lg, lb = KART.UI:GetRowStripeColor()
                    row.stripeBg:SetColorTexture(lr, lg, lb, 0.5)
                    row.stripeBg:Show()
                else
                    row.stripeBg:Hide()
                end
            end

            row.name:SetText(L.BC_EXAMPLE_PLAYER .. i)
            row.name:SetTextColor(0.5, 0.5, 1)

            local rc = rcPreview[i]
            -- Only "notready" shows a reason icon in the live path (see the row update below), so the
            -- preview must match — "waiting" never carries a reason.
            local reason = (rc == "notready") and rcReasonsPreview[i] or nil
            if reason then
                row.reasonIcon.reasonText = reason
                row.reasonIcon:Show()
                row.reasonHitbox:Show()
            else
                row.reasonIcon:Hide()
                row.reasonHitbox:Hide()
            end
            
            KART.SetReadyCheckIcon(row.rcIcon, rc)
            
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
                    if i == 2 then textObj:SetText("-1"); textObj:SetTextColor(unpack(KART.DANGER)); ind.missingSlots = "5"; ind.tooltipTitle = data.reportLabel or data.label
                    else textObj:SetText("OK"); textObj:SetTextColor(unpack(KART.SUCCESS)); ind.missingSlots = nil end
                elseif data.isAddonCheck then
                    local textObj = ind.text or ind
                    if i == 1 then
                        textObj:SetText("✓"); textObj:SetTextColor(unpack(KART.SUCCESS))
                    elseif i == 2 then
                        textObj:SetText("✗"); textObj:SetTextColor(unpack(KART.DANGER))
                    elseif i == 3 then
                        textObj:SetText("-"); textObj:SetTextColor(0.5, 0.5, 0.5)
                    else
                        textObj:SetText("?"); textObj:SetTextColor(0.5, 0.5, 0.5)
                    end
                elseif not data.isRepair then
                    ind:SetDesaturated(false)
                    if i == 1 and j == 7 then -- Beispiel für auslaufendes Food
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(1, 0.8, 0) -- Gelb
                    elseif (i + j) % 3 == 0 then
                        ind:SetAlpha(0.6)
                        ind:SetVertexColor(unpack(KART.DANGER)) -- Fehlend (Rot)
                    elseif data.isOil and i == 2 then
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(0.8, 0.3, 0.9) -- Lila für Preview
                    elseif data.isOil then
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(unpack(KART.SUCCESS)) -- best rank, matches setInd's "best" branch
                    else
                        ind:SetAlpha(1.0)
                        ind:SetVertexColor(1, 1, 1) -- Vorhanden
                    end
                else
                    local textObj = ind.text or ind
                    textObj:SetText("85%")
                    textObj:SetTextColor(unpack(KART.SUCCESS))
                end
            end
            row:Show()
        end
        KART.BuffCheckFrame.scrollContent:SetHeight(5 * 26)
        RefreshOkBanner(true)
        return
    end

    local snap = KART.ScanBuffRoster()
    local rows = KART.BuffCheckFrame.rows

    for i, player in ipairs(snap.players) do
        local row = rows[i]
        if not row then break end
        if row.stripeBg then
            if i % 2 == 0 then
                local lr, lg, lb = KART.UI:GetRowStripeColor()
                row.stripeBg:SetColorTexture(lr, lg, lb, 0.5)
                row.stripeBg:Show()
            else
                row.stripeBg:Hide()
            end
        end

        if KART_Settings.grayOffline then
            row:SetAlpha(player.connected and 1.0 or 0.4)
        else
            row:SetAlpha(1.0)
        end

        KART.SetReadyCheckIcon(row.rcIcon, player.rcStatus)
        SetTruncatedName(row.name, player.name, row.name:GetWidth())
        local c = RAID_CLASS_COLORS[player.class] or { r = 1, g = 1, b = 1 }
        row.name:SetTextColor(c.r, c.g, c.b)

        if player.reason then
            row.reasonIcon.reasonText = player.reason
            row.reasonIcon:Show()
            row.reasonHitbox:Show()
        else
            row.reasonIcon:Hide()
            row.reasonHitbox:Hide()
        end

        if player.ilvlKnown then
            row.ilvlText:SetText(string.format("%.1f", player.ilvl))
            row.ilvlText:SetTextColor(1, 1, 1)
        else
            row.ilvlText:SetText("?")
            row.ilvlText:SetTextColor(0.5, 0.5, 0.5)
        end
        if KART.BuffCheckMode == "advanced" then
            row.ilvlText:Show()
        else
            row.ilvlText:Hide()
        end

        for j, buff in ipairs(KART.BuffData) do
            local has = player.states[buff.id]
            if buff.isRepair then has = player.repair end
            local extra
            if buff.isAddonCheck then
                if UnitIsUnit(player.unit, "player") then
                    extra = KART.NeighborVersion(buff.isAddonCheck)
                else
                    extra = player.shortName and KART.PlayerAddonVersions
                        and KART.PlayerAddonVersions[player.shortName]
                        and KART.PlayerAddonVersions[player.shortName][buff.isAddonCheck]
                end
            end
            setInd(row, j, has, buff, KART.ClassCache, extra)
            if KART.BuffCheckMode == "advanced" then
                if buff.page == "advanced" then row.indicators[j]:Show() else row.indicators[j]:Hide() end
            else
                if buff.page == "advanced" then row.indicators[j]:Hide() else row.indicators[j]:Show() end
            end
        end
        row:Show()
    end
    KART.BuffCheckFrame.scrollContent:SetHeight(math.min(#snap.players, 40) * 26)
    
    RefreshOkBanner(false)
    if KART.RefreshStatusStripThrottled then KART.RefreshStatusStripThrottled() end
end

-- =====================================================================
--  Addon-message receivers -- the OIL/ILVL/GEAR/ENCH replies to KASC's REQ_* responders
-- =====================================================================

-- Whether s is a well-formed missing-slot list as KAGS.CountMissingGear produces them: "0", or one
-- or more comma-separated entries, each an inventory slot number optionally suffixed with "w" for
-- "wrong enchant". Used to reject a malformed GEAR reply before it reaches the cache (see the GEAR
-- handler below). Entries are validated one at a time because Lua patterns can't quantify a group,
-- so a single anchored "^%d+w?(,%d+w?)*$" would silently match nothing at all.
local function IsSlotList(s)
    if s == "" then return false end
    if s:find(",,") or s:find("^,") or s:find(",$") then return false end -- no empty entries
    for entry in s:gmatch("[^,]+") do
        if not entry:match("^%d+w?$") then return false end
    end
    return true
end

-- One hand of an OIL payload: an enchantID, "0" for a weapon carrying nothing, or "n" for a hand that
-- takes no oil at all (see the REQ_OIL responder). Returns nil for anything else, so a malformed or
-- hostile reply is dropped instead of reaching the cache.
local function ParseOilField(s)
    if not s then return nil end
    if s == "n" then return "n" end
    if s:match("^%d+$") then return tonumber(s) end
    return nil
end

KASC:RegisterMessage("OIL", { payload = true, group = true }, function(payload, ctx)
    local mhStr, ohStr = payload:match("^([^:]+):([^:]+)$")
    local mh, oh = ParseOilField(mhStr), ParseOilField(ohStr)
    if mh and oh then
        KART.OilCache = KART.OilCache or {}
        KART.OilCache[ctx.shortName] = { mh = mh, oh = oh }
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end
end)

KASC:RegisterMessage("ILVL", { payload = true, group = true }, function(payload, ctx)
    local ilvl = tonumber(payload)
    if ilvl then
        KART.ILvlCache = KART.ILvlCache or {}
        KART.ILvlCache[ctx.shortName] = ilvl
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end
end)

KASC:RegisterMessage("ENCH", { payload = true, group = true }, function(payload, ctx)
    -- Reply to REQ_ENCH: "slot=id" pairs, plus "oil=id" for the temporary weapon enchant. Purely
    -- a maintenance tally (KART.PrintEnchantScan) — nothing renders it, so the only rule is that
    -- one malformed entry drops the whole message rather than poisoning the counts.
    local ids = {}
    for entry in payload:gmatch("[^,]+") do
        local k, v = entry:match("^(%w+)=(%d+)$")
        if not k then return end
        if k == "oil" then
            ids.oil = v
        elseif k:match("^%d+$") then
            ids[tonumber(k)] = v
        else
            return
        end
    end
    KART.EnchantScan = KART.EnchantScan or {}
    KART.EnchantScan[ctx.shortName] = ids
end)

KASC:RegisterMessage("GEAR", { payload = true, group = true }, function(payload, ctx)
    local e, g = payload:match("^([^:]+):([^:]+)")
    -- Validate the shape before caching. Both fields are slot lists — "0" for "nothing missing",
    -- otherwise comma-separated inventory slot NUMBERS, optionally "w"-suffixed for a wrong
    -- enchant (see KAGS.CountMissingGear) — but the
    -- captures above accept any colon-free text. BuffChecker renders an unrecognized slot through
    -- string.format(BC_SLOT_FALLBACK, s), whose "%d" throws a Lua error on non-numeric input, so a
    -- broken or hostile client could make the Advanced-view tooltip error on every hover. Rejecting
    -- the whole message is also what keeps a bogus "-5 missing" count out of the cache.
    if e and g and IsSlotList(e) and IsSlotList(g) then
        KART.GearCache = KART.GearCache or {}
        KART.GearCache[ctx.shortName] = { enchants = e, gems = g }
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end
end)

-- Healthstone is a bag item. Peers answer HS:1 / HS:0; anything else is dropped.
KASC:RegisterMessage("HS", { payload = true, group = true }, function(payload, ctx)
    if payload ~= "0" and payload ~= "1" then return end
    KART.HSCache = KART.HSCache or {}
    KART.HSCache[ctx.shortName] = payload == "1"
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
end)

local lastHsAnswer = -5
KASC:RegisterMessage("REQ_HS", { group = true }, function()
    local now = GetTime()
    if now - lastHsAnswer < 5 then return end
    lastHsAnswer = now
    if not IsInGroup() then return end
    local n = KART.CountOwnHealthstones and KART.CountOwnHealthstones() or 0
    KASC:Send("HS:" .. ((n > 0) and "1" or "0"))
end)
