local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local SCHEMA = 1
local owedHooked = false
local owedEventsRegistered = false
local incomingLinks = {}
local hidingInternally = false
local owedRows = {}

local function OwedEnabled()
    return KART_Settings and KART_Settings.rcShowOwedReminder ~= false
end

function RC.EnsureOwedStore()
    if type(KART_RCOwed) ~= "table" or KART_RCOwed.schemaVersion ~= SCHEMA then
        KART_RCOwed = { schemaVersion = SCHEMA, items = {}, dismissed = false }
        return KART_RCOwed
    end
    if type(KART_RCOwed.items) ~= "table" then KART_RCOwed.items = {} end
    if KART_RCOwed.dismissed ~= true then KART_RCOwed.dismissed = false end
    return KART_RCOwed
end

function RC.OwedItems()
    return RC.EnsureOwedStore().items
end

local function IsPlayer(name)
    if not name or name == "" then return false end
    local theirs = Identity.ResolvePlayer(name)
    local mine = Identity.ResolvePlayer("player")
    return Identity.IsResolvedKey(theirs) and theirs == mine
end

local function AwardLink(session)
    local addon = RC.GetAddon()
    if not addon or type(addon.GetLootTable) ~= "function" then return nil end
    local ok, lt = pcall(addon.GetLootTable, addon)
    if not ok or type(lt) ~= "table" then return nil end
    local entry = lt[session]
    if type(entry) ~= "table" then return nil end
    return entry.link or entry.itemLink
end

local function RemoveSession(store, session)
    local kept = {}
    for _, row in ipairs(store.items) do
        if row.session ~= session then kept[#kept + 1] = row end
    end
    store.items = kept
end

local function SameItem(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local sa, sb = KAUtil.GetItemString(a), KAUtil.GetItemString(b)
    return sa ~= nil and sa == sb
end

function RC.OwedShouldShow()
    if not OwedEnabled() then return false end
    local store = RC.EnsureOwedStore()
    if store.dismissed then return false end
    if #store.items == 0 then return false end
    if InCombatLockdown() then return false end
    return true
end

local function HideOwedFrame()
    if not RC.OwedFrame then return end
    hidingInternally = true
    RC.OwedFrame:Hide()
    hidingInternally = false
end

local function EnsureOwedFrame()
    if RC.OwedFrame or not KART.UI then return RC.OwedFrame end
    local L = KART.L or {}
    local f = CreateFrame("Frame", "KART_RCOwedFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 140)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    KART.UI:SetPixelBackdrop(f, {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    if KART.UI.ApplyRoundedMask then
        local KAUI = LibStub("KAUI-1.0", true)
        KART.UI:ApplyRoundedMask(f, (KAUI and KAUI.CORNER_RADIUS_LG) or 6)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L.RC_OWED_TITLE or "You are owed")
    KART.UI:RegisterLabel(f.title)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        RC.DismissOwed()
    end)

    f:SetScript("OnHide", function()
        if hidingInternally then return end
        local store = RC.EnsureOwedStore()
        store.dismissed = true
    end)

    RC.OwedFrame = f
    return f
end

local function RangeColor(trader)
    local short = Ambiguate(trader or "", "short")
    if CheckInteractDistance(short, 2) then
        return 0.2, 0.9, 0.2
    end
    return 0.9, 0.2, 0.2
end

local function EnsureOwedRow(parent, i)
    local row = owedRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, parent)
    row:SetSize(296, 22)
    row:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 24)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetPoint("RIGHT", 0, 0)
    row.text:SetJustifyH("LEFT")
    if KART.UI and KART.UI.RegisterLabel then KART.UI:RegisterLabel(row.text) end
    row:SetScript("OnClick", function()
        RC.TryTradeOwed(i)
    end)
    owedRows[i] = row
    return row
end

function RC.RefreshOwedDisplay()
    if not RC.OwedShouldShow() then
        HideOwedFrame()
        return
    end
    local f = EnsureOwedFrame()
    if not f then return end
    local store = RC.EnsureOwedStore()
    local L = KART.L or {}
    for i, item in ipairs(store.items) do
        local row = EnsureOwedRow(f, i)
        local trader = RC.DisplayName and RC.DisplayName(item.trader) or Ambiguate(item.trader or "?", "short")
        local label = (item.link or ("#" .. tostring(item.session)))
            .. " <- " .. trader
        row.text:SetText(label)
        row.text:SetTextColor(RangeColor(item.trader))
        row:Show()
    end
    for i = #store.items + 1, #owedRows do
        if owedRows[i] then owedRows[i]:Hide() end
    end
    local rows = #store.items
    f:SetHeight(math.max(80, 40 + rows * 24))
    if f.title then
        f.title:SetText(L.RC_OWED_TITLE or "You are owed")
    end
    f:Show()
end

function RC.DismissOwed()
    RC.EnsureOwedStore().dismissed = true
    RC.RefreshOwedDisplay()
end

function RC.OpenOwedWindow()
    local L = KART.L or {}
    if not OwedEnabled() then
        print(L.RC_OWED_DISABLED or "|cffff0000KART:|r Winner trade reminder is switched off.")
        return false
    end
    local store = RC.EnsureOwedStore()
    store.dismissed = false
    RC.RefreshOwedDisplay()
    return RC.OwedShouldShow()
end

function RC.HandleOwedAward(session, winner, trader)
    local store = RC.EnsureOwedStore()
    session = tonumber(session) or session
    if not IsPlayer(winner) or IsPlayer(trader) then
        RemoveSession(store, session)
        RC.RefreshOwedDisplay()
        return
    end
    RemoveSession(store, session)
    store.items[#store.items + 1] = {
        session = session,
        link = AwardLink(session),
        trader = trader,
    }
    store.dismissed = false
    RC.RefreshOwedDisplay()
end

function RC.HandleOwedIncomingLinks(links)
    if type(links) ~= "table" then return end
    local store = RC.EnsureOwedStore()
    local kept = {}
    for _, row in ipairs(store.items) do
        local received = false
        for _, link in ipairs(links) do
            if SameItem(row.link, link) then
                received = true
                break
            end
        end
        if not received then kept[#kept + 1] = row end
    end
    store.items = kept
    RC.RefreshOwedDisplay()
end

function RC.OnOwedOutOfCombat()
    RC.RefreshOwedDisplay()
end

function RC.TryTradeOwed(index)
    local row = RC.OwedItems()[index]
    if not row or not row.trader then return false end
    local short = Ambiguate(row.trader, "short")
    if InCombatLockdown() or not CheckInteractDistance(short, 2) then
        local L = KART.L or {}
        print(L.RC_OWED_OUT_OF_RANGE or "|cffff0000KART:|r Not in trade range.")
        return false
    end
    InitiateTrade(short)
    return true
end

local function SnapshotIncoming()
    wipe(incomingLinks)
    local maxSlots = (_G.MAX_TRADE_ITEMS or 7) - 1
    for i = 1, maxSlots do
        local link = GetTradeTargetItemLink(i)
        if link then incomingLinks[#incomingLinks + 1] = link end
    end
end

local function HookTradeUI()
    if owedHooked or not RC.IsRCLoaded() then return end
    local addon = RC.GetAddon()
    local tradeUI = addon and addon.TradeUI
    if type(tradeUI) ~= "table" or type(tradeUI.OnAwardReceived) ~= "function" then return end
    hooksecurefunc(tradeUI, "OnAwardReceived", function(_, session, winner, trader)
        RC.HandleOwedAward(session, winner, trader)
    end)
    owedHooked = true
end

local function RegisterOwedEvents()
    if owedEventsRegistered then return end
    owedEventsRegistered = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("UI_INFO_MESSAGE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "TRADE_ACCEPT_UPDATE" then
            SnapshotIncoming()
        elseif event == "UI_INFO_MESSAGE" then
            if select(1, ...) == _G.LE_GAME_ERR_TRADE_COMPLETE then
                RC.HandleOwedIncomingLinks(incomingLinks)
                wipe(incomingLinks)
            end
        end
    end)
    RC.OwedEventFrame = f
end

function RC.EnableOwed()
    RC.EnsureOwedStore()
    RegisterOwedEvents()
    HookTradeUI()
    RC.RefreshOwedDisplay()
end
