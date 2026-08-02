-- The loot history WINDOW: paging, the two filter menus and the reset button.
--
-- Coverage put this file at 41% with 389 lines never executed, and nearly all of it was one block:
-- the window itself had never been built. The filter menus in it are the ones B98 and B99 were
-- about -- both were found by reading LH.GetUniquePlayers, because nothing could open the menu that
-- shows what it returns.
--
-- MenuUtil.CreateContextMenu was an empty stub, so the function that BUILDS a menu's entries never
-- ran anywhere in the suite. It answers honestly now (tests/wow_stubs.lua), which is what lets the
-- two menus below be opened and clicked rather than described.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim = F.NewRaid()
local me = sim.byName.Bramor
local KART = me.KART
local LH = KART.LH
local L = KART.L

local function As(fn, ...) return RaidSim.As(me, fn, ...) end
local GLOVES = KARTTEST.items[F.GLOVES].link

local function History(entries)
    me.env.KART_LootHistory = entries
    return entries
end

-- Builds n entries, newest first by timestamp, alternating between two winners.
local function Bulk(n)
    local out = {}
    for i = 1, n do
        local alric = (i % 2 == 1)
        out[i] = {
            winner    = alric and "Alric" or "Sinja",
            winnerKey = alric and "K-A" or "K-S",
            item      = GLOVES,
            reason    = alric and "BIS" or "Upgrade",
            time      = 1785000000 + (n - i),
        }
    end
    return out
end

-- The window ---------------------------------------------------------------------------------------
do
    History(Bulk(3))
    As(LH.Toggle)
    T.truthy(LH.historyWindow, "the history window builds")
    T.truthy(LH.historyWindow:IsShown(), "and opens on the first toggle")
    As(LH.Toggle)
    T.truthy(not LH.historyWindow:IsShown(), "and closes on the second")
end

local f
do
    As(LH.Toggle)
    f = LH.historyWindow
    T.truthy(f:IsShown(), "reopened for the rest of this file")
end

-- Paging -------------------------------------------------------------------------------------------
-- pageSize is derived from the visible row area and cached; the harness has no real heights, so it
-- stays at the documented fallback of 11. Everything below is written against that number.
do
    History(Bulk(3))
    As(LH.Refresh)
    T.truthy(not f.pageIndicator:IsShown(), "one page of results shows no page indicator")
    T.truthy(not f.nextPageBtn:IsShown(), "and no paging buttons")
end

do
    History(Bulk(25))
    As(LH.Refresh)
    T.eq(LH.currentPage, 1, "a fresh filter opens on the newest page")
    T.truthy(f.pageIndicator:IsShown(), "three pages of results show the indicator")
    T.truthy(f.nextPageBtn:IsShown() and f.prevPageBtn:IsShown(), "and both paging buttons")

    As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end)
    T.eq(LH.currentPage, 2, "next moves forward one page")
    As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end)
    As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end)
    T.eq(LH.currentPage, 3, "and stops at the last one rather than running off the end")

    As(function() f.prevPageBtn:GetScript("OnClick")(f.prevPageBtn) end)
    T.eq(LH.currentPage, 2, "prev moves back")
    As(function() f.prevPageBtn:GetScript("OnClick")(f.prevPageBtn) end)
    As(function() f.prevPageBtn:GetScript("OnClick")(f.prevPageBtn) end)
    T.eq(LH.currentPage, 1, "and stops at the first")
end

do
    -- Landing on a page that no longer exists is the shape of every "the list is empty but it says
    -- page 3" report: page forward, then narrow the filter under your own feet.
    History(Bulk(25))
    As(LH.Refresh)
    As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end)
    As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end)
    T.eq(LH.currentPage, 3, "on the last page of a long history")

    History(Bulk(3))
    As(LH.Refresh)
    T.eq(LH.currentPage, 1, "a history that shrank under the current page pulls it back into range")
end

-- The player filter menu ---------------------------------------------------------------------------
do
    History(Bulk(6))
    As(LH.Refresh)
    As(function() f.btnPlayerFilter:GetScript("OnClick")(f.btnPlayerFilter) end)

    local labels = KARTTEST.MenuLabels()
    T.truthy(#labels > 0, "the player filter menu has entries")
    T.eq(labels[1], L.LH_FILTER_ALL_PLAYERS, "the first of which clears the filter")

    local seen = {}
    for _, name in ipairs(labels) do seen[name] = (seen[name] or 0) + 1 end
    T.eq(seen["Alric"], 1, "each raider appears once (B98)")
    T.eq(seen["Sinja"], 1, "and so does the other one")
    T.eq(#labels, 3, "with nobody else listed")

    T.truthy(As(function() return KARTTEST.ClickMenu("Alric") end), "picking a raider is possible")
    T.eq(f.btnPlayerFilter.text:GetText(), "Alric", "the button then names who is being shown")
    T.eq(LH.filters.player, "K-A", "and the filter holds their key")
    T.truthy(LH.filters.playerIds and LH.filters.playerIds["K-A"], "as a set, so legacy rows match too")

    As(function() f.btnPlayerFilter:GetScript("OnClick")(f.btnPlayerFilter) end)
    T.truthy(As(function() return KARTTEST.ClickMenu(L.LH_FILTER_ALL_PLAYERS) end),
        "and the filter can be cleared again")
    T.eq(LH.filters.player, nil, "which drops the key")
    T.eq(LH.filters.playerIds, nil, "and the set with it -- either one left behind still filters")
end

-- The reason filter menu ---------------------------------------------------------------------------
do
    History(Bulk(6))
    As(LH.Refresh)
    As(function() f.btnReasonFilter:GetScript("OnClick")(f.btnReasonFilter) end)
    local labels = KARTTEST.MenuLabels()
    T.eq(labels[1], L.LH_FILTER_ALL_REASONS, "the reason menu opens with the clear entry")
    T.eq(#labels, 3, "and lists each reason once")

    T.truthy(As(function() return KARTTEST.ClickMenu("BIS") end), "a reason can be picked")
    T.eq(LH.filters.reason, "BIS", "and is what the list is narrowed by")
    T.eq(f.btnReasonFilter.text:GetText(), "BIS", "with the button saying so")
end

do
    -- An entry logged without a reason is a real case -- "assign without reason" is a menu item on
    -- every council row -- and it must be pickable rather than an empty line.
    History({
        { winner = "Alric", winnerKey = "K-A", item = GLOVES, reason = "", time = 1785000002 },
        { winner = "Sinja", winnerKey = "K-S", item = GLOVES, reason = "BIS", time = 1785000001 },
    })
    LH.filters.reason = nil
    As(LH.Refresh)
    As(function() f.btnReasonFilter:GetScript("OnClick")(f.btnReasonFilter) end)
    T.truthy(As(function() return KARTTEST.ClickMenu(L.LH_NO_REASON) end),
        "the no-reason group is offered under a name rather than as a blank row")
    T.eq(LH.filters.reason, "", "and filters on the empty reason")
end

-- Reset --------------------------------------------------------------------------------------------
do
    History(Bulk(6))
    LH.filters.player, LH.filters.playerIds, LH.filters.reason = "K-A", { ["K-A"] = true }, "BIS"
    LH.filters.search = "glove"
    f.searchBox:SetText("glove")
    As(LH.Refresh)

    As(function() f.btnReset:GetScript("OnClick")(f.btnReset) end)
    T.eq(LH.filters.player, nil, "reset drops the player filter")
    T.eq(LH.filters.playerIds, nil, "and its id set")
    T.eq(LH.filters.reason, nil, "and the reason filter")
    T.eq(LH.filters.search, "", "and the search text")
    T.eq(f.searchBox:GetText(), "", "clearing the box the player typed into as well")
    T.eq(f.btnPlayerFilter.text:GetText(), L.LH_FILTER_ALL_PLAYERS,
        "with both buttons back to saying they filter nothing")
    T.eq(f.btnReasonFilter.text:GetText(), L.LH_FILTER_ALL_REASONS, "the reason one too")
end

-- Search -------------------------------------------------------------------------------------------
do
    History(Bulk(4))
    As(function() f.searchBox:SetText("nothingmatchesthis") end)
    As(function() f.searchBox:GetScript("OnTextChanged")(f.searchBox) end)
    T.truthy(f.emptyLabel:IsShown(), "a search matching nothing says so rather than showing a blank list")

    As(function() f.searchBox:SetText("") end)
    As(function() f.searchBox:GetScript("OnTextChanged")(f.searchBox) end)
    T.truthy(not f.emptyLabel:IsShown(), "and clearing it brings the rows back")
end

-- The page arrows ----------------------------------------------------------------------------------
-- Both arrows are always visible once there is more than one page; whether they DO anything is said
-- by their colour alone. A bright arrow on the first page is an invitation to click something that
-- cannot happen, on the one screen a raider opens to check they were not skipped.
do
    History(Bulk(30))
    As(LH.Refresh)
    T.truthy(f.prevPageBtn:IsShown() and f.nextPageBtn:IsShown(), "both arrows are up on a long list")

    local p = f.prevPageBtn.text:GetTextColor()
    local n = f.nextPageBtn.text:GetTextColor()
    T.truthy(p < n, "on the first page, back is dimmed and forward is not")

    -- Walk to the last page and check the other end of the same rule.
    for _ = 1, 10 do As(function() f.nextPageBtn:GetScript("OnClick")(f.nextPageBtn) end) end
    p = f.prevPageBtn.text:GetTextColor()
    n = f.nextPageBtn.text:GetTextColor()
    T.truthy(n < p, "and on the last page it is the other way round")
end

-- The rows themselves ------------------------------------------------------------------------------
do
    History(Bulk(4))
    As(LH.Refresh)
    local rows = f.rows or (f.scrollChild and f.scrollChild.rows)
    T.truthy(rows and rows[1] and rows[2], "the list builds its rows")

    -- Alternating shading, and both halves of it an opacity: a boolean is different from 0.1 and is
    -- not a shade, so "the rows differ" on its own does not say this works.
    local _, _, _, a1 = rows[1].bg:GetColorTexture()
    local _, _, _, a2 = rows[2].bg:GetColorTexture()
    local _, _, _, a3 = rows[3].bg:GetColorTexture()
    T.eq(type(a1), "number", "a row's shading is an opacity")
    T.eq(type(a2), "number", "and so is its neighbour's")
    T.truthy(a1 ~= a2, "neighbouring rows are shaded differently")
    T.eq(a1, a3, "and the shading alternates rather than drifting")

    -- The item icon is the ITEM's icon, not the item id that was used to look it up. Both are
    -- truthy, and a texture path built out of an id renders as the green-and-black missing texture.
    T.truthy(tostring(rows[1].icon:GetTexture()):find("Interface", 1, true),
        "the row shows the item's icon rather than the number it was found by")
end

do
    -- A class this client does not know. Entries outlive expansions in a SavedVariable, they arrive
    -- from peers, and the class is a bare string on the wire -- so "not in RAID_CLASS_COLORS" is an
    -- ordinary state, not a corrupt one. Colouring by it must fall back rather than index nil.
    History({ { winner = "Alric", winnerKey = "K-A", item = GLOVES, reason = "BIS",
                time = 1785000000, class = "TINKER" } })
    local ok = pcall(function() As(LH.Refresh) end)
    T.truthy(ok, "an entry naming a class this client has never heard of still renders")

    local rows = f.rows or (f.scrollChild and f.scrollChild.rows)
    local r, g, b = rows[1].playerText:GetTextColor()
    T.truthy(r == 0.8 and g == 0.8 and b == 0.8, "in the neutral colour, not one read off nothing")
end
