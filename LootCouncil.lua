local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

KART.LC = KART.LC or {}
local LC = KART.LC

LC.sessionActive        = false
-- Whether LC.sessionActive above is an ANSWER or merely a starting value. False after every load and
-- every reload; true once we have either set the flag ourselves or been told it by the loot owner.
-- The distinction exists because "no session" and "I have not found out yet" look identical in a
-- boolean, and the loot owner answering the second as though it were the first ended the session for
-- everyone who asked them (see LC.HandleStateRequest, backlog B30).
LC.sessionStateKnown    = false
--- Whether the session currently running is one WE started, as opposed to one we were told about.
--- Both look identical in LC.sessionActive, and the difference decides whether the raid-leader
--- fallback in LC.IsConfigOwner may claim the config: starting a session with an empty Lootmaster
--- field is the documented setup where the leader's own settings ARE the raid's, while walking into
--- a session somebody else is running means the raid already agreed something and ours must not
--- replace it. Reset by every reload, like the rest of the runtime state.
LC.sessionStartedByUs   = false
LC.promptedThisSession  = false
LC.votes                = {}  -- [rollID][Identity key] = {idx, note}  (key is a GUID, see KASC.Identity)
LC.rolls                = {}  -- [rollID][Identity key] = 1-100 random roll (opt-in, see lcRollsEnabled)
LC.councilVotes         = {}  -- [rollID][council member Identity key] = candidate Identity key they picked (tally only, not binding)
LC.rollItems            = {}  -- [rollID] = itemLink
LC.voteListRolls        = {}  -- ordered list of rollIDs currently shown as rows in the looter's vote list
-- What this client REFUSED, and why. Companion to KASC:Diagnostics(), which counts the two refusals
-- that happen one layer below (not in our group, unknown token) — together they are the whole set of
-- ways a message can reach this client and still do nothing.
--
-- Both counters exist because of B118: a raid lost an End Round, two roll announcements and four
-- votes in one evening, and every one of those losses was silent on both ends. A refused message and
-- a message that never arrived look identical from outside, and they need completely different fixes.
-- Printed by /kart status whenever anything here is non-zero.
LC.diag = LC.diag or {
    refusedSender = 0, -- the sender is not who this client believes may send that message
    unknownRoll   = 0, -- a vote/roll/result for an item this client has never heard of
    -- ...and the same message for an item it DID know and has since let go of. Split out on
    -- 2026-08-05, because together they were unreadable: one client went from 2 to 181 in seven
    -- minutes while holding no rolls at all, and every one of those was a raider voting on an item
    -- this client had already finished with -- twenty senders times however many the boss dropped.
    -- That is ordinary traffic, and it buried the counter that had found the message loss the night
    -- before. Kept as a count rather than dropped: a large number here still says something, namely
    -- that this client is releasing rolls well before the rest of the raid is done with them.
    staleRoll     = 0,
    -- A peer's roll table for an item we already hold, whose numbers are NOT the ones we hold. Not a
    -- refusal like the two above -- it is a positive finding, and the only one in the addon that
    -- proves two clients scored one item off different numbers (see LC.HandleRolls). An agreeing
    -- duplicate is ordinary traffic since B131 and is not counted anywhere.
    rollsConflict = 0,
    -- A batch LC_DROP that named more entries than TABLE_MAX_IDS could carry, past the sender's own
    -- StartManualRoll cap -- an older or modified sender, since a current one never writes past the
    -- cap. See the break in LC.HandleDrop.
    dropCapped    = 0,
    -- A packed block (LC_DROP, LC_ROLLS) this client could not read back: damaged in transit, written
    -- by a LibDeflate that is not the one we compressed with -- LibStub hands out the highest minor
    -- loaded by ANY addon, so a raider does not necessarily run our copy -- or simply too large to be
    -- ours (see PACK_MAX_BLOCK). Without this the refusal is the one silent failure in these two
    -- handlers: the client loses a whole boss's items and neither end has anything to read.
    packedUnreadable = 0,
    -- Our OWN heartbeat had more votes to carry than one message may name (VOTES_MAX_ENTRIES), so
    -- some of them were left out of it. Unlike every other counter here this one is about what this
    -- client SENT, not what it received -- and it is the one case where a raider's own answer can go
    -- missing without anything else noticing.
    votesCapped = 0,
    -- A vote heartbeat that ARRIVED naming more votes than one message may carry (VOTES_MAX_ENTRIES),
    -- past the sender's own cap -- an older or modified sender, since a current one never writes past
    -- it. The received twin of votesCapped above, and kept apart from it because the two are opposite
    -- failures: that one is this raider's answer going missing, this one is somebody else's.
    voteBatchCapped = 0,
    -- A voting clock that was pushed FORWARD on an item that was already running one. Purely a
    -- measurement, not a guard: nothing here refuses anything, the deadline is written either way.
    --
    -- It exists because #28 could not be reproduced. "Die items verschwinden immer wieder und tauchen
    -- dann im LC wieder auf. Die Zeit wird immer wieder zurück gesetzt" -- reported by a council
    -- member, and three separate explanations for it were each refuted by the test harness (a
    -- re-raised START_LOOT_ROLL announces nothing; the owner's own deadline does not move;
    -- LC.CatchUpCouncilPanel passes the remaining time through and lands on the same instant). Rather
    -- than guess a fourth time, count it: if the raider sees it happen and this stays at zero, the
    -- clock is not what is moving and the report is about something else.
    clockRestarted = 0,
    clockRestartedBy = nil, -- which writer did it last, so the count names a place and not just a number
}

LC.councilTabs          = {}  -- ordered list of rollIDs currently shown as tabs in the council panel
LC.councilTabsNew       = {}  -- [rollID] = true while a tab hasn't been switched to yet (unseen-item marker)
LC.rollDeadlines        = {}  -- [rollID] = GetTime() timestamp when voting closes, shared by both UIs
LC.rollDurations        = {}  -- [rollID] = original vote-window length in seconds, used only to size
                               -- the council header's time-bar fill (rollDeadlines alone gives a
                               -- deadline but not the window's original length)

-- The one place the two UI entry points write a voting clock, so there is one place that can see a
-- clock being pushed forward on an item that was already running one. Behaviour is unchanged -- the
-- deadline is written whatever the answer -- and the only product is LC.diag.clockRestarted; see
-- there for the report this is trying to settle.
--
-- source names the writer rather than the roll: the count is only useful if it says WHERE, and a
-- rollID means nothing to whoever pastes the status line.
--
-- A second of slack, because both writers rebuild the deadline from whole seconds and a repeat that
-- faithfully carries the remaining time still lands a fraction away from where it started. That is
-- not the thing being looked for.
-- Which of the two counters a message about an untracked roll belongs in.
--
-- LC.rollLootedAt is the discriminator, and it is the right one by construction: every path that
-- tracks a roll stamps it (LC.OnStartLootRoll and LC.HandleStart both do), and the stamp deliberately
-- OUTLIVES the roll -- Trade.PruneExpiredLootStamps owns its lifetime, not Trade.ClearRollState --
-- because the four-hour trade window is measured from it. So a stamp with no roll under it is exactly
-- "this client knew about this item and has let it go".
--
-- A rollID Blizzard has reused could carry a stamp from the previous item and send a genuinely
-- unknown roll into the stale count instead. Bounded by the four-hour prune, and it is a counter, not
-- a guard: nothing is refused differently either way.
LC.Diag = LC.Diag or {}
function LC.Diag.CountUntracked(rollID)
    if LC.rollLootedAt and LC.rollLootedAt[rollID] then
        LC.diag.staleRoll = LC.diag.staleRoll + 1
    else
        LC.diag.unknownRoll = LC.diag.unknownRoll + 1
    end
end

function LC.SetRollDeadline(rollID, seconds, source)
    local deadline = GetTime() + (seconds or 20)
    local running = LC.rollDeadlines[rollID]
    if running and deadline > running + 1 then
        LC.diag.clockRestarted = LC.diag.clockRestarted + 1
        LC.diag.clockRestartedBy = source
    end
    LC.rollDeadlines[rollID] = deadline
    LC.rollDurations[rollID] = seconds or 20
end
LC.pendingTrades        = {}  -- items assigned to someone else, not yet handed over: {rollID, itemLink, winnerKey}
LC.CouncilNamesTable    = {}  -- resolved KASC.Identity key -> true. Written by exactly two paths:
                               -- LC.HandleConfig (a received LC_CONFIG) and LC.ApplyOwnConfig (our own
                               -- settings, but only while WE own the config — see LC.IsConfigOwner).
                               -- Never from a non-owner's local settings, so a regular raider can't
                               -- self-promote by editing their own council-member list.
LC.raidConfig           = {}  -- the authoritative config: minQuality, buttonLabels, rollsEnabled,
                               -- lootmaster, councilMembers. Same two writers as CouncilNamesTable above;
                               -- raidConfig.fromSelf marks the ApplyOwnConfig case (see there).

-- =====================================================================
--  Window chrome: scale and frame strata, owned by Loot Council alone
-- =====================================================================
-- Every other KART window follows KART_Settings.uiScale/frameStrata through KART.UI. The Loot
-- Council ones deliberately do not: they are the windows a raider stares at mid-pull, on a screen
-- that may be a third smaller than the maintainer's (see B18 in docs/BACKLOG.md), and wanting them
-- smaller than the main window — or on a different layer, above a boss mod — is the normal case
-- rather than an edge one. KART.MainFrame's own scale never reached them anyway; it is applied to
-- that one frame and nothing else.
--
-- Registering here rather than with KART.UI:RegisterStrataFrame is also what keeps this separable
-- for a future KALC split: the Loot Council owns its own chrome and takes it with it.
LC.windowFrames  = {} -- top-level Loot Council windows
LC.windowDialogs = {} -- its transient popups, kept one stratum above the windows

-- The stratum directly below Blizzard's DIALOG, where its StaticPopup frames live. A stratum that
-- is not in the list counts as above it: ApplyWindowChrome answers "TOOLTIP" for its dialogs once
-- the windows are maxed out, and that is exactly the case that has to come down.
local POPUP_CEILING_INDEX = 4 -- HIGH, in KART.StrataLevels
local function ClampBelowDialog(strata)
    for i = 1, POPUP_CEILING_INDEX do
        if KART.StrataLevels[i] == strata then return strata end
    end
    return KART.StrataLevels[POPUP_CEILING_INDEX]
end

-- Drop-in replacement for KART.UI:RegisterStrataFrame at Loot Council call sites. Applies the
-- current values immediately, exactly as that one does, so a frame built after login is not left
-- unstyled until the next settings change.
function LC.RegisterWindow(frame, isDialog)
    local list = isDialog and LC.windowDialogs or LC.windowFrames
    list[#list + 1] = frame
    -- Raise on click, exactly as KAUI:RegisterStrataFrame does for every other KART window (B24).
    -- These frames leave that path, so they have to carry it themselves — the vote window over the
    -- council panel is the single most likely overlap in the whole addon.
    if frame.SetToplevel then frame:SetToplevel(true) end
    LC.ApplyWindowChrome(frame, isDialog)
end

-- Applies to one frame, or to every registered frame when called with no arguments (the path
-- KART.UpdateStyles takes on any settings or profile change).
function LC.ApplyWindowChrome(frame, isDialog)
    local idx = KART_Settings and KART_Settings.lcFrameStrata
    if type(idx) ~= "number" or idx < 1 or idx > #KART.StrataLevels then idx = 4 end
    local windowStrata = KART.StrataLevels[idx]
    -- Same rule KAUI applies to its own dialogs: one stratum above the windows, so a confirm
    -- popup can never end up buried under the panel that opened it. TOOLTIP is the step above
    -- the top entry, which is otherwise not offered for windows.
    local dialogStrata = KART.StrataLevels[idx + 1] or "TOOLTIP"

    -- Blizzard's StaticPopup frames are stuck at DIALOG and moving one taints it (B8/B55), so while
    -- one of ours is up these windows come down instead. Registered with KAUI below; these windows
    -- keep their own list and their own setting, so KAUI's own clamp cannot reach them.
    if LC.popupYield then
        windowStrata = ClampBelowDialog(windowStrata)
        dialogStrata = ClampBelowDialog(dialogStrata)
    end
    local scale = ((KART_Settings and KART_Settings.lcScale) or 100) / 100

    -- Background opacity is the addon-wide setting, not a Loot Council one -- but these windows
    -- were simply never wired to it, so the slider did nothing to them at all (B3). Their artwork
    -- texture is frame.bg, put there by KAUI:ApplyPopupArtwork; only that fades, exactly as the
    -- main and history windows do it, so rows and text stay legible at any opacity. Applied here
    -- because this is now the one place that knows every Loot Council window.
    local alpha = math.max(20, (KART_Settings and KART_Settings.bgAlpha) or 85) / 100

    local function apply(f, strata)
        f:SetFrameStrata(strata)
        f:SetScale(scale)
        if f.bg then f.bg:SetAlpha(alpha) end
    end

    if frame then
        apply(frame, isDialog and dialogStrata or windowStrata)
        return
    end
    for _, f in ipairs(LC.windowFrames) do apply(f, windowStrata) end
    for _, f in ipairs(LC.windowDialogs) do apply(f, dialogStrata) end
end

-- KAUI clamps the frames it owns while one of our confirm dialogs is up; these windows are outside
-- that registry on purpose, so they subscribe instead. The stand-in prompt is why it matters: it is
-- raised while the council panel is open, and a raid whose lootmaster has left waits on somebody
-- pressing a button they cannot see.
KART.UI:RegisterPopupYielder(function(yielding)
    LC.popupYield = yielding or nil
    LC.ApplyWindowChrome()
end)

-- Items simulated by the Test buttons (StartTest) — several so the vote-list/council-panel
-- handling of multiple simultaneous rolls can actually be tested (multiple items dropping at
-- once is the normal case in a real raid, not the exception). Real item links, not fake strings
-- — so tabs show real icons and the armor-eligibility / equipped-item comparison features have
-- real item data to work with in test mode too. The trinket is included specifically so the
-- two-slot comparison logic in GetEquippedForUnit (rings/trinkets check both slots and show
-- whichever is weaker) has something to actually exercise — the three weapons are all
-- single-slot. Safe to use for testing regardless: everything that matters (no broadcast, no
-- chat announce, no loot history entry, no trade reminder) is gated on the rollID being a test
-- roll (see IsTestRoll), not on whether the item link itself is real. "(TEST)" sits inside the
-- hyperlink's own label so it shows up wherever the link is displayed as text, without breaking
-- GameTooltip:SetHyperlink (which ignores the label and looks up the real item by ID) or
-- IsRealItemLink.
local TEST_ITEMS = {
    "|cffff8000|Hitem:17182:0:0:0:0:0:0:0:0:0:0:0|h[Sulfuras, Hand von Ragnaros] (TEST)|h|r",
    "|cffff8000|Hitem:19019:0:0:0:0:0:0:0:0:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker] (TEST)|h|r",
    "|cffff8000|Hitem:22691:0:0:0:0:0:0:0:0:0:0:0|h[Corrupted Ashbringer] (TEST)|h|r",
    "|cffa335ee|Hitem:12938:0:0:0:0:0:0:0:0:0:0:0|h[Hand of Justice] (TEST)|h|r",
}

-- Fixed rollID range used by the Test buttons: TEST_ROLL_ID .. TEST_ROLL_ID + TEST_ITEM_COUNT -
-- 1, one per simulated item (see TEST_ITEMS). Kept separate from real, server-issued rollIDs so
-- test votes/assignments never collide with a live roll, and so the vote/assign/announce logic
-- below can special-case them: no addon-channel broadcast, no raid-chat spam, no permanent
-- loot-history entry — testing must stay entirely local to the tester's client.
local TEST_ROLL_ID    = 99999
local TEST_ITEM_COUNT = #TEST_ITEMS

-- Manually-added items (see LC.StartManualRoll) get their own rollID range, well clear of both
-- real server-issued rollIDs and the fixed TEST_ROLL_ID block above — each item /kart add starts
-- increments past the last one used, since (unlike the 4 fixed test slots) any number of these
-- can exist. Already comfortably outside IsTestRoll's range (99999..100002), so no separate
-- IsManualRoll check is needed anywhere — AddPendingTrade's existing IsTestRoll guard already
-- treats these as real rolls, which is exactly the wanted behavior (unlike test rolls, they
-- should be tradeable).
local MANUAL_ROLL_ID_BASE = 500000
-- Seed off the session clock (base + seconds-of-epoch mod 100000, range 500000..599999) so a
-- mid-raid /reload doesn't restart the counter at the base and reuse an ID a peer is still
-- tracking from before the reload — which would show the old item and old votes under the new
-- roll. time() moves forward every reload, so each session's manual IDs occupy a distinct range.
LC.nextManualRollID = LC.nextManualRollID or (MANUAL_ROLL_ID_BASE + time() % 100000)

-- Which mode (true = council/master, false = looter) last actually (re)populated the test data
-- in LC.StartTest — nil until the first test run. Lets StartTest tell "the OTHER test window is
-- still open, don't wipe its data out from under it" apart from "the SAME window got re-clicked,
-- treat that as an explicit restart" (see the sessionActive/suppressReset comment in StartTest).
LC.testSessionShowCouncil = nil

function LC.IsTestRoll(rollID)
    return rollID ~= nil and rollID >= TEST_ROLL_ID and rollID < TEST_ROLL_ID + TEST_ITEM_COUNT
end

-- Preset accent colors per button position
local BUTTON_COLORS = {
    {r=1.0,  g=0.15, b=0.0 },
    {r=0.0,  g=0.85, b=0.25},
    {r=0.2,  g=0.4,  b=1.0 },
    {r=0.9,  g=0.75, b=0.0 },
    {r=0.55, g=0.55, b=0.55},
    {r=0.7,  g=0.3,  b=0.9 },
}

-- The fixed Transmog response is appended by GetButtonConfig as the LAST entry, so its position
-- shifts with however many labels the raid leader configured. Colour and icon therefore travel
-- with the entry itself instead of being looked up by index — otherwise the same response would
-- render yellow in a raid with three labels and purple in one with five.
local TRANSMOG_COLOR = {r = 0.85, g = 0.5, b = 1.0}
local TRANSMOG_ICON  = "Interface\\MINIMAP\\TRACKING\\Transmogrifier"

-- Native icon textures used as small chips on vote buttons/pills, one per button *position* (not
-- tied to label text, since labels are leader-configurable free text — see GetButtonConfig). All
-- five are Blizzard's own default group-loot icons, reused purely because they already ship with
-- the client and render correctly at small sizes — Unicode symbol glyphs (★ ▲ etc.) were
-- considered and rejected: WoW's default game fonts render most of the Geometric Shapes/Dingbats
-- blocks as an empty "tofu" box (the reason row.councilVoteBtn.text below is ASCII-only already).
local VOTE_ICON_TEXTURES = {
    "Interface\\Buttons\\UI-GroupLoot-Dice-Up",   -- 1: strongest want (BIS)
    "Interface\\Buttons\\UI-GroupLoot-Coin-Up",   -- 2: secondary want (Upgrade)
    "Interface\\Buttons\\UI-GroupLoot-DE-Up",     -- 3: alternate use (Offspec)
    "Interface\\COMMON\\help-i",                  -- 4: catch-all (Sonstiges)
    "Interface\\Buttons\\UI-GroupLoot-Pass-Up",   -- 5: Pass
}
function LC.GetVoteIconTexture(index, def)
    -- An entry that carries its own icon (the fixed Transmog response) wins: its position is not
    -- fixed, so the position-keyed list below cannot describe it.
    if def and def.icon then return def.icon end
    -- Out-of-range index (labels allow up to 5 configurable buttons plus Transmog, this list holds
    -- the 5 default semantics) falls back to the neutral catch-all icon (4), NOT Pass (the last
    -- entry, 5) — otherwise a configured 5th button would render with the green Pass chip.
    return VOTE_ICON_TEXTURES[index] or VOTE_ICON_TEXTURES[4]
end

-- Round class icon (the same atlas used by default raid/party frames) so a council-row candidate's
-- class reads at a glance without parsing the class-coloured name text.
function LC.SetClassIconTexture(tex, classFile)
    if not (classFile and CLASS_ICON_TEXCOORDS and CLASS_ICON_TEXCOORDS[classFile]) then
        tex:Hide()
        return
    end
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circle")
    tex:SetTexCoord(unpack(CLASS_ICON_TEXCOORDS[classFile]))
    tex:Show()
end

-- =====================================================================
--  Helpers
-- =====================================================================

-- Vote-button labels/colors are authoritative from the config owner (LC.raidConfig), so every
-- raider's vote index maps to the SAME label in everyone's UI. The owner always uses their own
-- local setting directly (they ARE the source of truth); everyone else uses the synced value,
-- falling back to their own local setting only when solo / not yet synced (e.g. testing).
--
-- Gated on LC.IsConfigOwner, NOT UnitIsGroupLeader: config ownership follows the lootmaster entry
-- (see LC.HandleConfig). A raid leader who isn't the lootmaster receives the owner's LC_CONFIG like
-- everyone else and must honour it — the old leader check made them silently keep their own
-- (usually default) labels, quality threshold and rolls flag while the rest of the raid used the
-- owner's, and made LC_ACTIVE from the lootmaster get rejected on the leader's client.
-- A fingerprint of the button set a vote was cast against (B43-B45).
--
-- The wire used to carry the COUNT, which catches a vote cast against a longer or shorter list but
-- not a same-length rename or reorder -- and the config owner editing labels mid-roll pushes the new
-- set live, so votes cast before the edit were then rendered under whatever the label became, stated
-- as fact on the one screen that decides who gets the item. The count is folded in, so a length
-- change is still caught by the same comparison.
--
-- Deliberately not a cryptographic hash: this is a mismatch detector, not a security boundary -- a
-- forged vote can claim any fingerprint it likes and could equally have claimed the right count.
-- djb2, kept under 2^32 so Lua 5.1 arithmetic stays exact and the value survives tostring/tonumber
-- on the wire.
function LC.ButtonFingerprint(buttons)
    buttons = buttons or LC.GetButtonConfig()
    local parts = {}
    for i, def in ipairs(buttons) do parts[i] = def.label or "" end
    local text = #buttons .. "|" .. table.concat(parts, ";")
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967291 end
    return h
end

-- Whether a vote belongs to the item currently tracked under its roll (B46).
--
-- Blizzard reuses a rollID for a genuinely different drop within seconds on trash. The vote carries
-- the item it was cast for, and this is where that is read -- deliberately at the READER rather than
-- at the receiver, because a vote is sent exactly once with no retry: dropping one on a mismatch
-- threw it away for good whenever OUR link was the stale half of the disagreement.
--
-- Unknown on either side means "cannot tell", and cannot-tell counts as belonging: an older client
-- sends no item, and a roll still held as "???" has none to compare against. Refusing those would
-- blank a whole raid's votes over a link that had not arrived yet.
function LC.VoteIsForItem(vote, rollID)
    local stamped = type(vote) == "table" and vote.item or nil
    if stamped == nil or stamped == "" then return true end
    local link = LC.rollItems[rollID]
    local mine = (type(link) == "string" and link:match("item:(%d+)")) or ""
    if mine == "" then return true end
    return stamped == mine
end

-- Whether a vote cast against `storedFp` can still be shown as a label (B43-B45).
--
-- Named and shared because it is read from three places that must agree -- the council rows, the tab
-- tooltip above them, and the voter's own badge -- and they did not: the tooltip skipped the check
-- entirely and stated with full confidence the very vote the rows below rendered as "?", and the
-- badge had nothing stored to check at all. Duplicating a one-line expression across three render
-- sites is how they came apart, and none of the three is reachable from the offline harness, so the
-- rule is tested here rather than through what it draws.
--
-- An absent fingerprint is NOT stale: a vote from an older client arrives without one, and refusing
-- to show it would turn a mixed-version raid into a screen full of question marks.
function LC.VoteLabelStale(storedFp, buttons)
    if storedFp == nil then return false end
    return storedFp ~= LC.ButtonFingerprint(buttons)
end

function LC.GetButtonConfig()
    local raw
    if LC.IsConfigOwner() or not LC.raidConfig.buttonLabels or LC.raidConfig.buttonLabels == "" then
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or KART.L.LC_DEFAULT_BUTTONS
    else
        raw = LC.raidConfig.buttonLabels
    end
    local parts = KAUtil.SplitString(raw, ";")
    local result = {}
    for _, label in ipairs(parts) do
        local trimmed = KAUtil.TrimString(label)
        -- 5, not 6: the sixth slot is now permanently the fixed Transmog response appended below.
        if trimmed ~= "" and #result < 5 then
            -- Color by the COMPACTED position (#result+1), not the raw split index, so it matches the
            -- vote icon (chosen by the returned button's index). A whitespace-only label between real
            -- ones is dropped from result but would otherwise advance the split index, desyncing the
            -- two.
            -- Colour AND icon are stamped from the configured position and then travel with the
            -- entry, because Transmog is inserted in front of the last label below and shifts it one
            -- place along. Looked up by final index instead, the last label — "Pass" — would land
            -- outside VOTE_ICON_TEXTURES and lose its green pass chip for the neutral catch-all.
            local col = BUTTON_COLORS[#result + 1] or BUTTON_COLORS[6]
            table.insert(result, {label = trimmed, r = col.r, g = col.g, b = col.b,
                                  icon = LC.GetVoteIconTexture(#result + 1)})
        end
    end
    if #result == 0 then
        for i, label in ipairs(KAUtil.SplitString(KART.L.LC_DEFAULT_BUTTONS, ";")) do
            if i <= 5 then
                local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
                table.insert(result, {label = label, r = col.r, g = col.g, b = col.b,
                                      icon = LC.GetVoteIconTexture(i)})
            end
        end
    end
    -- The Transmog response is not leader-configurable: the auto-transmog setting votes with it, and
    -- a renamed or missing button would make that setting silently vote something else.
    --
    -- ALWAYS LAST, and it must stay last. It was briefly moved in front of the last configured label
    -- to fix its position in the council panel's sort order, and that was the wrong lever: the vote
    -- index is what travels over the wire, so moving it desynchronised every client that had not yet
    -- updated. Both lists still had six entries, so the count guard in Vote.CastVote saw nothing
    -- wrong, and a raider on the older build pressing "Pass" was displayed to the council as
    -- "Transmog". A whole evening's votes were read wrong that way.
    --
    -- The panel's ordering is a display concern and is solved where it belongs, in
    -- LC.GetVoteSortRank below. Never reorder this list to change how something looks.
    table.insert(result, {
        label    = KART.L.LC_BUTTON_TRANSMOG,
        r        = TRANSMOG_COLOR.r, g = TRANSMOG_COLOR.g, b = TRANSMOG_COLOR.b,
        transmog = true,
        icon     = TRANSMOG_ICON,
    })
    return result
end

-- Is this item a collectible — a mount, battle pet or toy — that must stay out of Loot Council
-- entirely (see the standing rule quoted in LC.OnStartLootRoll)?
--
-- This used to read `classID == 15` and that was too blunt. classID 15 is "Miscellaneous", Blizzard's
-- bucket for everything that fits nowhere else, and **tier tokens live in it too**: measured against
-- the guild's own loot history, all sixteen Midnight Nullcore tokens are classID 15 / subclass 0,
-- exactly like the Riftbloom tokens, while the raid's one mount is classID 15 / subclass 5. So the
-- carve-out meant to keep mounts out was quietly keeping every tier token out as well — no
-- ForceWinRoll for the lootmaster, no Auto-Pass for the raiders, the single most contested drop in
-- the instance bypassing Council completely. Reported from a live raid.
--
-- This is an ALLOW-LIST, and it has to stay one. The first attempt at narrowing named the things to
-- keep out — mounts, pets, toys — and let everything else in classID 15 through. Housing decor
-- promptly walked through that gap and the lootmaster force-won it, which is exactly what the rule
-- exists to prevent. Miscellaneous is Blizzard's junk drawer; new compartments appear with every
-- expansion, and a rule that has to be taught about each one in turn is wrong by construction.
--
-- Subclass 0 is the only compartment measured to hold gear tokens (all sixteen Midnight Nullcores and
-- the Riftblooms sit there). So subclass 0 is the only one Council may see. Everything else in 15 —
-- pets (2), mounts (5), mount equipment (6), housing decor, and whatever comes next — stays out
-- without needing to be enumerated. An unresolved subclass counts as "not 0" and therefore stays out
-- too: GetItemInfoInstant answers from the client database for any real link, so that case barely
-- exists, and staying out is the direction that cannot force-win someone's furniture.
--
-- The journals are asked FIRST, before the class is looked at at all. They used to sit behind the
-- `classID == 15` gate, on the assumption that toys share the tokens' 15/0 bucket. Measured in a
-- live client (2026-07-30, the 41 toys of one player's Toy Box): 39 are classID 15, but 2 are
-- classID 0 — Consumable — e.g. 229828, classID 0 / subclass 8. Those never reached the toy lookup.
-- A toy therefore read as ordinary Bind-on-Pickup gear: force-won by the lootmaster, passed by every
-- Auto-Pass raider, the standing rule broken through a bucket nobody had looked in. An item the
-- client itself identifies as a mount, pet or toy is one whatever compartment Blizzard filed it
-- under, and no gear token appears in any of the three journals, so asking first cannot pull a token
-- out of Council.
--
-- C_ToyBox.GetToyInfo is trustworthy enough to decide on. Measured in the same session: the Toy Box
-- holds all 1144 toys on a fresh login without Collections ever being opened, it answers for toys
-- the player has NOT collected (425 of the 1144 were learned), and it answers regardless of the
-- box's own display filter, which on that client was showing 41 entries.
-- Enum.ItemClass.Recipe. Spelled out rather than read from the enum for the same reason every other
-- class id in this file is: the offline harness has no Enum table, and a number with a name next to
-- it cannot be broken by a client that renames the field.
local ITEM_CLASS_RECIPE = 9

function LC.IsCollectibleItem(itemID, classID, subclassID)
    if itemID then
        if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then return true end
        if C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(itemID) then return true end
        if C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(itemID) then return true end
    end
    -- 20 is Enum.ItemClass.Housing, new in Midnight, and written as a bare number for the same reason
    -- 15 below is: tests/test_lc_collectible.lua compiles this function out of the source on its own,
    -- where a file-local constant would be nil -- and `classID == nil` then matches every unresolved
    -- item, which is the opposite of what this line is for.
    --
    -- Housing decor used to be a compartment of Miscellaneous and now has a class of its own, so the
    -- 15 test stopped covering it. Mounts, pets and toys are caught by their journal APIs whatever
    -- class they sit in; housing has no such API here, so it was reaching Loot Council against the
    -- standing rule -- silently, because nothing in this file had changed.
    if classID == 20 then return true end
    if classID ~= 15 then return false end
    if subclassID ~= 0 then return true end
    if not itemID then return true end
    return false
end

-- Index of the fixed Transmog response: always the last entry (see GetButtonConfig). Named rather
-- than open-coded so callers never encode the position themselves.
function LC.GetTransmogButtonIndex()
    return #LC.GetButtonConfig()
end

-- Where a vote sorts on the council panel, which is NOT the same question as which index it carries
-- on the wire. The panel lists candidates by rank ascending, so rank order is the priority order the
-- council reads top to bottom, and the fixed Transmog response belongs directly in front of the last
-- configured label — someone who wants the appearance ranks above someone who wants nothing at all.
--
-- Doing this here rather than by reordering the button list is deliberate and was learned the hard
-- way: the index is a wire value shared with every other client, and moving it desynchronised the
-- raid without tripping the count guard (see GetButtonConfig). A rank is local, so it can be
-- whatever reads best without anyone else having to agree.
--
-- Half steps rather than a renumbering, so an index this client cannot resolve — a vote from a
-- client with a different button set — still sorts by its raw value instead of collapsing to 0.
function LC.GetVoteSortRank(idx)
    idx = tonumber(idx)
    if not idx then return math.huge end
    local n = #LC.GetButtonConfig()
    if idx == n and n >= 2 then return n - 1.5 end -- the Transmog entry, in front of the last label
    return idx
end

-- Index of the last FREELY CONFIGURED label, which the hide-irrelevant setting votes with. That is
-- "Pass" in the default configuration and in every configuration this guild has used. A raid leader
-- who renames the last label to something that is not a pass makes that setting vote it instead —
-- documented in the setting's own tooltip, deliberately not guessed at from the label text.
-- nil when the config holds nothing but the appended Transmog entry, which cannot happen through the
-- settings UI (an empty field falls back to the defaults) but is cheap to be honest about.
function LC.GetPassButtonIndex()
    local n = #LC.GetButtonConfig() - 1
    if n < 1 then return nil end
    return n
end

-- The loot owner counts as council without having to be listed in the council-member field. He is
-- the one who physically wins every item (ForceWinRoll) and the only one who may end the session, so
-- a lootmaster left out of that list ended up with no council panel at all — no way to assign a
-- winner, no "Close Session" button (it lives on that panel), and no window for his own "/kart add".
--
-- The raid leader is NOT council by virtue of being the leader (see LC.IsLootOwner's standing
-- decision) — only while no lootmaster is configured, where IsLootOwner falls back to them anyway.
-- A leader who should sit on the council goes in the council-member list like everyone else.
function LC.IsCouncil()
    if LC.IsLootOwner() then return true end
    local myKey = (KASC.Identity.ResolvePlayer("player"))
    return LC.CouncilNamesTable[myKey] == true
end

-- Whether senderKey (already resolved off CHAT_MSG_ADDON's sender, see Core.lua) currently holds
-- council status — used to validate the sender of messages that grant real authority (LC_RESULT
-- logs a permanent history entry and fires the "you win" popup; LC_ONOTE overwrites a persistent
-- officer note) before acting on them. Resolving to a live unit first, rather than trusting the
-- key alone, matters because CHAT_MSG_ADDON also delivers whispers: someone not currently in our
-- group is never authorized, even if their key happens to match an entry in CouncilNamesTable.
function LC.IsSenderCouncil(senderKey)
    local unit = senderKey and KASC.Identity.FindUnitForKey(senderKey)
    if not unit then return false end
    -- Mirrors LC.IsCouncil: the loot owner is council whether or not he's in the council-member
    -- list. Without this, peers rejected the LC_RESULT of an unlisted lootmaster — so his awards
    -- produced no loot-history entry, no winner popup and no owed-item reminder anywhere in the
    -- raid. IsSenderLootOwner also covers the leader while no lootmaster is configured, and forces
    -- the pending-key migration itself.
    if LC.IsSenderLootOwner(senderKey) then return true end
    if LC.CouncilNamesTable[senderKey] == true then return true end
    -- The council table can still hold this member under a pending-TEXT key (they were out of group
    -- when the config was parsed, so ResolveConfigName couldn't produce their GUID yet) while
    -- senderKey is already a live GUID. GROUP_ROSTER_UPDATE's throttled retry would migrate it, but
    -- an authoritative LC_RESULT/LC_ONOTE can arrive inside that throttle window and get wrongly
    -- dropped. Force the synchronous, pending-only migration now, then re-check, so a genuine
    -- council member's message is never lost to that timing race.
    LC.RetryPendingResolutions()
    return LC.CouncilNamesTable[senderKey] == true
end

-- target (optional): whisper this one player instead of broadcasting to the group. Used for replies
-- to a directed request (see LC.HandleStateRequest), so answering one person doesn't push state at
-- everyone else.
-- Which of these messages must survive an addon-comm restriction (see KASC's CommsRestricted) rather
-- than be lost to it. The rule is "would the raid be wrong afterwards if this never arrived?":
--
--   * the ones listed here change what a client BELIEVES -- an item is on the table, the round ended,
--     somebody voted, somebody won. Losing one leaves two clients disagreeing, with nothing to notice
--     it. They are held and sent when comms come back.
--   * everything else is a QUESTION (state requests, the table heartbeat, roll requests) or a
--     broadcast that repeats anyway. A question answered forty seconds late is noise: the asker has
--     asked again by then.
--
-- Loot drops at the END of an encounter, which is exactly the window this is about, so the top half
-- of this list is the loot flow itself.
-- LC_START and LC_MANUAL_START are no longer sent by any shipping version -- a drop travels as
-- LC_DROP -- and their entries here and in TOKEN_PRIO below are pure ROLLOUT TOLERANCE: this table is
-- read by the SENDER, keyed on the token it is about to put on the wire, so nothing in this build can
-- reach either line. What can is a client still on the previous build sending one at us, or a rollback
-- to it, and then both tables have to already say what those messages are worth. (LC_ROLL_CATCHUP
-- routing through LC.HandleStart is a receive-side fact and is NOT the reason: it has its own key.)
-- Cheaper than an entry that turns out to be missing later; delete them once no build that sends them
-- can still be in a raid.
local GUARANTEED_TOKENS = {
    LC_DROP = true,
    LC_START = true, LC_MANUAL_START = true, LC_ROLL_CATCHUP = true,
    LC_END_ROUND = true, LC_ACTIVE = true, LC_SESSION_RESUME = true,
    LC_CONFIG = true, LC_CONFIG_RELAY = true,
    LC_VOTE = true, LC_CVOTE = true, LC_ROLLS = true,
    LC_RESULT = true, LC_ONOTE = true,
}

-- ChatThrottleLib splits the available bandwidth evenly across its three priorities, so this table
-- is not about speed but about who has to wait for whom when the pipe is full. Two rules, and both
-- come out of 2026-08-03:
--
--   * ALERT is for the two moments the whole raid is standing still for -- an item going on the
--     table, and the round ending. Everything else can be a second late without anybody noticing.
--   * BULK is for traffic that arrives in storms. The history catch-up is answered by every peer
--     with one message per award; the handshake is the other one and carries its own BULK (see
--     KASC:RequestHello / AnnounceHello).
--
-- Everything not listed is NORMAL: votes, rolls, awards, config, session state.
local TOKEN_PRIO = {
    LC_DROP = "ALERT",
    LC_START = "ALERT", LC_MANUAL_START = "ALERT", LC_END_ROUND = "ALERT",
    LC_HIST_REQ = "BULK",
}

function LC.SendLC(msg, target)
    if not IsInGroup() then return end
    local token = msg:match("^([^:]+)")
    local opts = { guaranteed = GUARANTEED_TOKENS[token] or nil, prio = TOKEN_PRIO[token] }
    if target then
        KASC:Send(msg, "WHISPER", target, opts)
    else
        KASC:Send(msg, nil, nil, opts)
    end
end

-- Minimum item quality is authoritative from the raid leader, same reasoning as GetButtonConfig.
-- NOTE: this does NOT gate Auto-Pass (see OnStartLootRoll) — that stays a personal preference.
function LC.GetRaidMinQuality()
    if LC.IsConfigOwner() then
        return KART_Settings.lcMinQuality or 4
    end
    return LC.raidConfig.minQuality or 4
end

-- Applies the LootCouncil-specific font size (KART_Settings.lcFontSize, independent from the main
-- window's Content Font Size) to every text element in the vote-list window and the council panel
-- — see the root-cause note on this task for why neither window currently tracks any font setting
-- at all. Three tiers relative to the base size preserve the existing visual hierarchy (item name
-- and window title bigger, column headers smaller) while making all of them move together.
function LC.ApplyFontSize()
    local fontPath = KART.UI:GetFontPath(KART_Settings.fontName)
    local base  = KART_Settings.lcFontSize or 12
    local big   = base + 2   -- item name / window title
    local small = math.max(8, base - 2) -- column headers

    local function setAll(list, size)
        for _, elem in ipairs(list) do
            if elem then elem:SetFont(fontPath, size, "") end
        end
    end

    local vf = LC.voteListFrame
    if vf then
        setAll({vf.title}, big) -- window title scales with lcFontSize like the council panel's does
        for _, row in ipairs(vf.rows or {}) do
            setAll({row.itemText}, big)
            setAll({row.timerText, row.gainText, row.votedText}, base)
            for _, btn in ipairs(row.voteButtons or {}) do
                if btn.text then btn.text:SetFont(fontPath, base, "") end
            end
        end
        for _, row in ipairs(vf.compactRows or {}) do
            setAll({row.itemText}, big)
            setAll({row.timerText, row.gainText, row.votedText}, base)
            -- Compact layout's vote "chips" are icon-only (see RefreshVoteListRows_Compact) —
            -- no button text to size here.
        end
    end

    local cp = LC.councilPanel
    if cp then
        setAll({cp.title, cp.itemText}, big)
        setAll({cp.timerText, cp.ilvlText}, base)
        setAll({cp.hName, cp.hRank, cp.hIlvl, cp.hVote, cp.hRoll, cp.hCouncilVotes, cp.hGain}, small)
        for _, row in ipairs(cp.rows or {}) do
            setAll({row.nameText, row.rankText, row.equippedText, row.voteText, row.rollText, row.gainText}, base)
            if row.councilVoteBtn and row.councilVoteBtn.text then
                row.councilVoteBtn.text:SetFont(fontPath, base, "")
            end
        end
        for _, tab in ipairs(cp.tabs or {}) do
            if tab.countText then tab.countText:SetFont(fontPath, small, "") end
        end
    end
end

-- The designated lootmaster (trimmed, lowercase, "" = none) — same authority reasoning as
-- GetButtonConfig/GetRaidMinQuality: only the raid leader's own local setting is authoritative,
-- everyone else (including the designated lootmaster themselves) goes by the synced value. This
-- is deliberately NOT a personal toggle like lcAutoPass — see LC.OnStartLootRoll, which overrides
-- a raider's own Auto-Pass preference when they are this person, precisely so it can't be turned
-- off by anyone except the raid leader reassigning it.
--
-- The stored value can be either a character short name OR a Northern Sky Raid Tools nickname —
-- LC.IsMe (below) is what actually resolves it against the local player, trying both.

-- Resolves free-typed config text (a council-list entry, or the lootmaster field) to a stable
-- key via KASC.Identity.ResolvePlayer, trimming first. Returns nil for blank text. Shared by
-- LC.HandleConfig (a received LC_CONFIG broadcast) and LC.GetLootmaster's raid-leader branch
-- below (the leader's own local settings, resolved fresh on every read rather than cached,
-- since the leader does not process its own broadcast to trigger HandleConfig).
function LC.ResolveConfigName(text)
    local trimmed = KAUtil.TrimString(text or "")
    if trimmed == "" then return nil end
    return (KASC.Identity.ResolvePlayer(trimmed))
end

-- The synced lootmaster key, or "" if that person is not in the raid any more.
--
-- Checked at the moment of use rather than by clearing the key on every path that could make it
-- stale. That open-ended obligation is precisely what produced B29: `LC.raidConfig.lootmaster` was
-- written when a config arrived and invalidated nowhere, so a lootmaster who left kept answering all
-- evening — `IsLootOwner()` was then false for EVERYBODY, since the raid-leader fallback is
-- unreachable while the string is non-empty. Nobody force-won anything, no `LC_START` went out, and
-- the session could not be closed by anyone.
--
-- Presence means "in the roster", not "online": `FindUnitForKey` deliberately still finds someone who
-- has dropped connection. A disconnect is temporary and their bags are still holding the loot;
-- moving ownership on every connection hiccup would leave the stand-in's trade list ignorant of items
-- somebody else is carrying. Leaving the raid is not temporary.
--
-- A pending text key is "we cannot place this person", not "they left" (see KASC.Identity), so it is
-- never read as absence — that would hand ownership to the raid leader over a nickname the client
-- simply cannot resolve yet.
local function PresentLootmaster(key)
    if not key or key == "" then return "" end
    if not IsInGroup() then return key end
    -- A designation nobody could place is not a designation yet, and the raid leader carries the loot
    -- flow until it resolves. This used to return the pending key -- "we cannot place this person" was
    -- deliberately NOT read as absence, so a client that simply could not see a nickname would not
    -- hand the role to the raid leader over it.
    --
    -- That reasoning belonged to the old wire format, where every receiver resolved the NAME for
    -- itself and a nickname-blind client was the one that failed. The config owner now resolves it
    -- once and sends an identity key (see LC.BroadcastRaidConfig), so raw text on the wire means the
    -- owner could not place them either -- and the owner is the person who typed it and is in the
    -- raid with them. Nobody can. Holding the loot flow hostage to it left the raid with no owner at
    -- all: no force-win, no LC_START, no vote window, over a typo.
    --
    -- Self-healing: LC.ApplyOwnConfig re-resolves on every roster change, so the moment the name does
    -- resolve the owner broadcasts a proper key and the designation takes effect.
    if not KASC.Identity.IsResolvedKey(key) then return "" end
    return KASC.Identity.FindUnitForKey(key) and key or ""
end

-- Whether a lootmaster IS named and is demonstrably no longer here — the one case that hands the
-- role to the raid leader, and the only one that asks first (see LC.CheckStandIn).
local function LootmasterAbsent()
    local key = LC.raidConfig.lootmaster
    if not key or key == "" or not IsInGroup() then return false end
    if not KASC.Identity.IsResolvedKey(key) then return false end
    return KASC.Identity.FindUnitForKey(key) == nil
end

-- One derivation for everybody, owner included. LC.ApplyOwnConfig has already written the owner's
-- own field into LC.raidConfig, so reading KART_Settings again here only reintroduced an asymmetry:
-- the owner kept naming a designee who had left while every peer blanked them, so the raid disagreed
-- about who was handing out loot at exactly the moment it mattered. Absence is resolved the same way
-- on every client now (see PresentLootmaster), and the stand-in prompt reads the raw field, so an
-- absent designee still comes back to their role by simply returning.
function LC.GetLootmaster()
    return PresentLootmaster(LC.raidConfig.lootmaster)
end

-- Whether configuredKey (a resolved KASC.Identity key, see LC.GetLootmaster/LC.ResolveConfigName)
-- identifies the local player. Resolution (character short name vs. Northern Sky Raid Tools
-- nickname, see KASC.Identity.GetNickname) already happened upstream when the key was
-- produced, so a raid leader can name a *person* once ("kandera") instead of re-typing the field
-- whenever that person switches characters — every alt just needs the same NSRT nickname set,
-- which raiders already do for the addon's other nickname-aware features.
function LC.IsMe(configuredKey)
    if not configuredKey or configuredKey == "" then return false end
    return (KASC.Identity.ResolvePlayer("player")) == configuredKey
end

-- =====================================================================
--  Loot owner  (who drives the whole loot flow)
-- =====================================================================
-- STANDING DECISION (maintainer, 2026-07-25; revised 2026-07-27): the LOOTMASTER owns the entire
-- loot flow — starting and ending the session, broadcasting every roll, adding items with
-- /kart add, and physically holding the items until they're traded. The raid leader has nothing to
-- do with any of it unless they ARE the lootmaster or are listed as a council member. The only
-- exception is the fallback below: while NO lootmaster is configured at all, the raid leader stands
-- in, so a raid that never filled the field keeps working exactly as before.
--
-- Assigning a winner is deliberately NOT on that exclusive list — it is open to the whole council,
-- by design: Council.ShowAssignMenu is reached from an ungated row right-click, and an incoming
-- assignment is accepted via LC.IsSenderCouncil, which admits any council member, not just the
-- lootmaster. (This corrects the original 2026-07-25 wording, which listed "assigning winners"
-- among the lootmaster's exclusive duties — the code never enforced that, and the maintainer has
-- confirmed the code is right and the old text was wrong.)
--
-- Every authority check in this module goes through LC.IsLootOwner / LC.IsSenderLootOwner. Do not
-- reintroduce a bare UnitIsGroupLeader test for anything loot-related — that is what made a raid
-- leader's /reload silently stop the whole raid's roll broadcasts while the lootmaster kept winning
-- items nobody could vote on.

-- Whether WE are that client. Falls back to the plain leader check while no lootmaster is set,
-- which is byte-for-byte the behaviour this module had before the role existed (including solo,
-- where UnitIsGroupLeader("player") is false).
function LC.IsLootOwner()
    local lootmaster = LC.GetLootmaster()
    if lootmaster ~= "" then return LC.IsMe(lootmaster) end
    -- A named lootmaster who has left hands the role to the raid leader — but only once that leader
    -- has said yes (see LC.CheckStandIn). Standing in means every council-eligible item is force-won
    -- into their own bags from that moment on, which is not something to start doing to somebody and
    -- mention afterwards. A raid that never named a lootmaster at all is a different case and is not
    -- asked anything: that is the documented setup, and it has always worked this way.
    if LootmasterAbsent() and not LC.standInAccepted then return false end
    -- The raid has a lootmaster and this client was not told who: that is what a relay's presence
    -- field says (see LC.RelayRaidConfig). Somebody out there is running the loot flow, and a client
    -- that does not know who is not the one -- whether that somebody is here ("1") or gone ("0"),
    -- because in the second case the raid still has to be ASKED before anybody takes over.
    if LC.raidConfig.relayLootmaster and not LC.standInAccepted then return false end
    return UnitIsGroupLeader("player")
end

-- The loot owner's resolved identity key, for the places that need to name them rather than test
-- for themselves (the winner's "you're owed this" entry). "" when nobody can be resolved.
function LC.GetLootOwnerKey()
    local lootmaster = LC.GetLootmaster()
    if lootmaster ~= "" then return lootmaster end
    for unit in KAUtil.EachGroupUnit() do
        if UnitIsGroupLeader(unit) then return (KASC.Identity.ResolvePlayer(unit)) end
    end
    return ""
end

-- Sender-side counterpart, for validating an incoming addon message. Resolves to a live unit first
-- (CHAT_MSG_ADDON also delivers whispers, so someone outside the group is never authorized) and
-- forces the pending-key migration before comparing — senderKey is always a GUID while the stored
-- lootmaster can still be plain config text if they weren't in our roster when LC_CONFIG was parsed.
function LC.IsSenderLootOwner(senderKey)
    local unit = senderKey and KASC.Identity.FindUnitForKey(senderKey)
    if not unit then return false end
    local lootmaster = LC.GetLootmaster()
    if lootmaster ~= "" and not KASC.Identity.IsResolvedKey(lootmaster) then
        LC.RetryPendingResolutions()
        lootmaster = LC.GetLootmaster()
    end
    if lootmaster ~= "" then return senderKey == lootmaster end
    -- Deliberately does NOT consult LC.standInAccepted, unlike LC.IsLootOwner. That flag lives on the
    -- stand-in's own client and nobody else can see it, so a receiver has no way to ask. It does not
    -- need to: a leader who has not accepted sends nothing, because their own IsLootOwner gates every
    -- send. Being permissive here costs nothing and refusing would break the stand-in outright — do
    -- not "fix" this asymmetry.
    return UnitIsGroupLeader(unit)
end

-- Random 1-100 rolls are an opt-in raid-wide feature (analogous to RCLootCouncil's Need roll),
-- same authority reasoning as GetButtonConfig/GetRaidMinQuality.
function LC.GetRollsEnabled()
    -- Same fallback shape as GetButtonConfig: trust our own local setting when solo/not yet
    -- synced too, not just when we actually own the config — otherwise LC.IsConfigOwner() being
    -- false while ungrouped (e.g. solo testing) would always read as "rolls off", no matter what
    -- the checkbox says, since LC.raidConfig.rollsEnabled never gets synced there.
    if LC.IsConfigOwner() or LC.raidConfig.rollsEnabled == nil then
        return KART_Settings.lcRollsEnabled == true
    end
    return LC.raidConfig.rollsEnabled == true
end

-- Sends the leader's authoritative settings (min quality, vote-button labels, rolls toggle,
-- lootmaster, council member list) to the raid so every client interprets votes/roles identically.
-- No-ops for non-leaders. Payload order is minQ:buttons:rolls:lootmaster:council — council stays
-- last because it's the only greedy (.*) capture in HandleConfig's pattern, so it's the only field
-- allowed to contain further colons; every field before it (lootmaster included) is one colon-free
-- segment, which is why the synced free-text fields strip colons at input (LootCouncilSettings).
--
-- SendAddonMessage payloads are capped at 255 bytes by the underlying chat protocol. Button
-- labels (up to 128 chars) plus a large council list (up to 255 chars, per its editbox's
-- SetMaxLetters) can together exceed that, and a transport-truncated message can make
-- HandleConfig's anchored payload pattern fail to match on every other client, leaving them
-- silently stuck on stale config. Trim the council list — the field most likely to grow large —
-- to whatever whole entries fit instead, and tell the leader locally so they know to shorten it.
local ADDON_MSG_MAX_BYTES = 255

-- Fits council (the ";"-separated, variable-length tail shared by LC_CONFIG and LC_SYNC_REQUEST)
-- into the addon-message byte budget left after prefix — dropping whole trailing entries rather than
-- splitting one mid-name, and warning the user locally when it had to. Returns the full payload.
-- Returns nil when the fixed part alone cannot fit, in which case nothing must be sent.
--
-- Trimming the council list is only meaningful while there is a budget left to trim it into. Button
-- labels run to 128 characters and the lootmaster field is unbounded, so the prefix on its own can
-- exceed the limit -- and the old code then emptied the council list, still returned the oversized
-- prefix, and let the transport chop it. Every client's anchored HandleConfig pattern fails on the
-- result, so the whole raid silently stays on stale config: the exact failure this function's
-- truncation exists to avoid, reached by trying to avoid it. Refuse instead, and say so.
local function BuildCouncilPayload(prefix, council)
    local budget = ADDON_MSG_MAX_BYTES - #prefix
    if budget <= 0 then
        print("|cffff0000KART:|r " .. KART.L.LC_CONFIG_TOO_LONG)
        return nil
    end
    if #council > budget then
        council = council:sub(1, budget):match("^(.*);") or ""
        print("|cffff0000KART:|r " .. KART.L.LC_CONFIG_TRUNCATED)
    end
    return prefix .. council
end

-- Whether WE own the raid config, i.e. whether our own settings name us as the lootmaster. Only the
-- config owner broadcasts it (see LC.BroadcastRaidConfig) and only their broadcast is accepted (see
-- LC.HandleConfig). Reads KART_Settings directly rather than LC.GetLootmaster, which for a non-owner
-- returns the synced raidConfig value — that would make everyone who received a config think they
-- own it.
-- KART_Settings is guarded, not read raw: this runs at FILE-LOAD time too (the settings panel's
-- role-status label is set while building, before ADDON_LOADED has created the SavedVariable), and
-- an unguarded read errored out mid-build on a fresh install. ResolveConfigName(nil) returns nil and
-- IsMe(nil) is false, so "no settings yet" correctly reads as "we don't own the config".
--
-- An EMPTY field falls back to the raid leader, the same way LC.IsLootOwner does. Leaving it empty is
-- a documented setup, and without this fallback it meant nobody owned the config at all: no client
-- ever received one, so every raider silently used their own vote-button labels, their own minimum
-- quality and their own roll setting — which defaults to off. A whole raid not rolling, and the
-- role-status label reporting that all was well (backlog B33). The two ownership derivations
-- disagreeing was the bug; they now agree.
--
-- The fallback stands down as soon as somebody else actually claims the role, so a raid leader with
-- an empty field cannot fight a named lootmaster over who broadcasts. Note this reads LC.raidConfig,
-- which ApplyOwnConfig also writes — stable, because a config we applied ourselves names either us
-- or nobody, and neither takes this branch.
--
-- Deliberately NOT presence-checked, unlike LC.GetLootmaster. A named lootmaster who has merely
-- stepped out still owns the config: the vote labels, minimum quality, roll setting and council list
-- the raid agreed on are theirs and are still the right ones. Letting a stand-in leader own them
-- instead pushes that leader's own settings over the raid — erasing the name the lootmaster reclaims
-- on the way back in, and taking the council list with it if that leader never filled one in.
-- Standing in is about the loot flow (see LC.IsLootOwner), not about the settings.
function LC.IsConfigOwner()
    -- THE RAID LEADER OWNS THE CONFIG. Nothing else decides it. See docs/OWNERSHIP.md.
    --
    -- Everything this function used to do is gone on purpose, and the five guards that used to live
    -- here are the reason: they existed only to arbitrate a CLAIM. The old rule asked "does my own
    -- Lootmaster field name me?", which made ownership something a client asserted about itself
    -- rather than something the raid could observe -- so two clients could both believe it (B64) or
    -- neither could (B70), and defending a claim against one invented after a reload needed
    -- `fromSelf`, `sessionStartedByUs` and a timed grace, each of which went wrong on its own (B69,
    -- B70). Raid lead is a fact the game tracks and every client already agrees on, so there is
    -- nothing left to arbitrate.
    --
    -- Ungrouped counts as owning it, so the settings tab and a solo test roll still work.
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player")
end

-- Applies OUR OWN settings as the raid config, locally. KASC drops our own message when it comes back, see Dispatch, so it never reaches its
-- own sender, so the config owner is the one client that does not process their own LC_CONFIG — which
-- left LC.raidConfig and LC.CouncilNamesTable empty on exactly the person the config is about. On a
-- lootmaster who isn't also the raid leader that broke their entire role: GetLootmaster() read "",
-- so they never force-won a roll (they auto-passed instead), "/kart add" refused, no pending-trade
-- reminder was created for the person actually holding the items, and Close Session stayed greyed
-- out — while an empty CouncilNamesTable made IsCouncil() false (no council panel at all) and made
-- IsSenderCouncil reject LC_RESULT/LC_ONOTE from every council member except the raid leader.
--
-- Mirrors LC.HandleConfig's parsing exactly, so both write paths produce identical state.
function LC.ApplyOwnConfig()
    if not LC.IsConfigOwner() then
        -- We do not hold raid lead, so our own settings are not the raid's and this writes nothing.
        --
        -- Whatever we are holding stays. It is either the raid's config, or -- if we were the leader
        -- a moment ago -- the config the raid is still running on, and keeping it is strictly better
        -- than falling back to defaults while the new leader gets round to broadcasting. Their
        -- LC_CONFIG replaces it when it lands, unconditionally (see TryAcceptConfig): under the new
        -- rule nothing has to be arbitrated on content, so a stale copy cannot win.
        --
        -- The handover branch that used to be here is gone with the rule that needed it. It sent
        -- LC_RESIGN and wiped, because ownership was a claim and "I am no longer the lootmaster" had
        -- no other way to reach the raid (B32). Ownership is now the raid leader, which every client
        -- derives for itself, and a lootmaster change is a designation change inside the config --
        -- carried by the next broadcast, after the session is restarted. Nothing to announce.
        LC.configOwnerAnnounced = nil
        return
    end

    -- Taking the role over is now silent by construction -- nobody hands it to you, you simply hold
    -- raid lead -- and from that moment the RAID runs on your settings. Somebody promoted by accident,
    -- or while standing in for a moment, would otherwise switch the whole raid onto their own defaults
    -- without a word, and lcRollsEnabled defaults to OFF. Say it once per time the role arrives.
    --
    -- Ungrouped is not the raid's business: LC.IsConfigOwner is true there so the settings tab works
    -- solo, and announcing it would fire on every settings change outside a group.
    if IsInGroup() and not LC.configOwnerAnnounced then
        LC.configOwnerAnnounced = true
        print("|cffff0000KART:|r " .. KART.L.LC_CONFIG_OWNER_NOW)
    end

    LC.raidConfig.minQuality     = KART_Settings.lcMinQuality or 4
    LC.raidConfig.buttonLabels   = KART_Settings.lcButtonLabels or ""
    LC.raidConfig.rollsEnabled   = KART_Settings.lcRollsEnabled == true
    -- An EMPTY Lootmaster field means "not configured", not "this raid designates nobody" (B76). Same
    -- rule as the council list below, one field over, and it was written for exactly this shape:
    -- raid lead moves to somebody who has never filled the field in -- a stand-in, or a promotion by
    -- accident -- and writing their emptiness in made them answer LC.IsLootOwner with "yes" while
    -- everybody else still pointed at the person actually handing out the loot. Both halves stay
    -- internally consistent, which is what makes it so quiet: the new leader force-wins the next item
    -- and announces it, and every client that still holds the designation rejects the LC_START
    -- (LC.HandleStart opens with IsSenderLootOwner), so the roll exists on part of the raid and a
    -- vote cast on it is dropped for good by the rest.
    --
    -- The Lootmaster field is documented as required, which is what makes this the right direction:
    -- an empty one is somebody who has not got round to it, never "nobody hands out loot tonight".
    -- Narrow the same way: a field that HAS a name replaces the designation outright, so changing who
    -- hands out the loot still takes one broadcast.
    -- LC.GetLootmaster, not the raw field: a designation naming somebody who has LEFT is already
    -- masked to "" there, and that case must still clear. It is the one time the raid genuinely has
    -- to move on -- the stand-in's empty field becomes the raid's, and the role follows raid lead
    -- from then on. Keeping a departed name would leave the raid pointed at an empty chair.
    if (KART_Settings.lcLootmaster or "") ~= "" or LC.GetLootmaster() == "" then
        LC.raidConfig.lootmaster = LC.ResolveConfigName(KART_Settings.lcLootmaster) or ""
    end
    -- Only a field that NAMES somebody clears what a relay said about the raid (see
    -- LC.HandleConfigRelay). An empty one deliberately does not: this function runs on every
    -- GROUP_ROSTER_UPDATE, so clearing it here would drop the fact within seconds of learning it --
    -- one person joining or one promotion -- and hand the loot flow back to a leader the raid is
    -- not running on. That is precisely how the first attempt at B130 undid itself.
    if (KART_Settings.lcLootmaster or "") ~= "" then LC.raidConfig.relayLootmaster = nil end
    -- Same rule the receiving side applies (see TryAcceptConfig): an empty council list means "not
    -- configured", not "this raid has no council". It has to hold on BOTH sides or they disagree --
    -- the config owner never processes its own broadcast, so leaving it out here made the new leader
    -- the only client in the raid with an empty council while everybody else kept the real one.
    if (KART_Settings.lcCouncilMembers or "") ~= "" or (LC.raidConfig.councilMembers or "") == "" then
        LC.raidConfig.councilMembers = KART_Settings.lcCouncilMembers or ""
    end
    LC.raidConfig.fromSelf       = true

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KAUtil.SplitString(LC.raidConfig.councilMembers, ";")) do
        local key = LC.ResolveConfigName(name)
        if key then LC.CouncilNamesTable[key] = true end
    end
end

-- target (optional): whisper the config to one player instead of broadcasting (see LC.SendLC).
function LC.BroadcastRaidConfig(target)
    -- Apply it to ourselves first, and outside the IsInGroup guard below: our own state has to be
    -- right even while solo (test mode) — see LC.ApplyOwnConfig, which self-guards on ownership.
    LC.ApplyOwnConfig()
    -- Config authority follows the lootmaster entry, NOT raid lead — see LC.HandleConfig. A promoted
    -- assistant with empty settings would otherwise push those over the whole raid's config.
    if not (IsInGroup() and LC.IsConfigOwner()) then return end
    -- And not while our claim is a guess nobody has confirmed (see LC.SetSessionActive, B69). This
    -- has to be checked HERE rather than only at the point the session starts: every roster change
    -- re-broadcasts, so a one-off guard would be undone by the next person walking in.
    local minQ     = KART_Settings.lcMinQuality or 4
    local buttons  = KART_Settings.lcButtonLabels or ""
    local rolls    = KART_Settings.lcRollsEnabled and "1" or "0"
    -- Keep the full "Name-Realm" text (don't strip the realm): GetLootmaster resolves the same
    -- unstripped value on the leader, so stripping here would let a cross-realm lootmaster resolve
    -- to a different person (or a same-named local) on peers than on the leader.
    -- The DESIGNATION, resolved here rather than on the wire as free text (see docs/OWNERSHIP.md).
    --
    -- Under the old rule the sender was always naming themselves, so a receiver could ignore the text
    -- and use the sender's own identity. A designation names somebody else, so the name now has to
    -- survive the trip -- and resolving it on every receiver is exactly the dead end that cost a raid
    -- its config once already: a client without Northern Sky, or with global nicknames off, can never
    -- resolve a nickname and would be left with a designation it cannot place, for ever.
    --
    -- The config owner CAN resolve it: they typed it, and they are in the raid with that person. So
    -- they do it once and put the identity key on the wire. Raw text only when even we cannot place
    -- them yet -- a receiver may still manage, and LC.RetryPendingResolutions covers the rest.
    -- The designation IN FORCE, for the same reason the council list below is: LC.ApplyOwnConfig has
    -- just written it and keeps the raid's when our own field is empty (B76). Sending the raw field
    -- instead would put an emptiness on the wire that we had deliberately declined to adopt -- and a
    -- client with no config yet has nothing to keep, so a newcomer would end up as the only person
    -- in the raid who does not know who hands out the loot.
    local lootmasterField = KAUtil.TrimString(KART_Settings.lcLootmaster or "")
    local lootmaster = LC.raidConfig.lootmaster
    if not lootmaster or lootmaster == "" then
        lootmaster = LC.ResolveConfigName(lootmasterField) or lootmasterField
    end
    -- The council list IN FORCE, not our own raw setting. LC.ApplyOwnConfig has just written it, and
    -- it keeps the raid's list when ours is empty ("not configured", see there) -- so sending the raw
    -- setting would hand a newcomer an empty council while everybody already here has the real one.
    local council  = LC.raidConfig.councilMembers or KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_CONFIG:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":"
    local payload = BuildCouncilPayload(prefix, council)
    if payload then
        LC.SendLC(payload, target)
        -- What a relay told us about the raid's designation (see LC.HandleConfigRelay) is answered by
        -- this message: every peer takes the field above as the raid's, and we do not process our own
        -- broadcast, so clearing it here is the same hand-written step every other send in this module
        -- needs. Leaving it would make the config owner the one client in the raid that does not
        -- believe what it just told everybody -- and, since nothing else clears it for a leader whose
        -- own field is empty, no client at all would own the loot from then on.
        --
        -- Only the RAID-WIDE one. A targeted send is the sync-request answer (see
        -- LC.HandleStateRequest), and it reaches exactly one client: the rest of the raid still holds
        -- the designation it was told about, so forgetting it here would leave us claiming a loot flow
        -- somebody else is running, in front of an audience that never heard otherwise -- B130 through
        -- a different door, and reachable by anybody reloading mid-session.
        if not target then LC.raidConfig.relayLootmaster = nil end
    end
end

-- Hands on the config the RAID agreed, to a client that has none (B65).
--
-- The config owner re-broadcasts on every roster change, so a joiner is normally covered by that
-- alone. This is for the gap before it: somebody who arrives, or comes back from a reload, between
-- one broadcast and the next ran the evening on their own vote buttons, their own minimum quality
-- and their own roll setting -- and their vote reached the council under a different label than they
-- clicked, with nothing to show for it on either side.
--
-- Three things keep this from becoming a second, competing authority:
--   * It carries LC.raidConfig, never KART_Settings. A stand-in's own (usually empty) council list
--     can no more overwrite the raid's here than it could through LC.BroadcastRaidConfig.
--   * The lootmaster field NAMES nobody. This says "here is what the raid settled on", not "and I
--     am in charge of it": ownership stays derived, so the real lootmaster reclaims it simply by
--     coming back and broadcasting (their own field names them, ours does not). It does say whether
--     the raid has one and whether they are here -- see the presence field below.
--   * Only whoever is actually running the loot flow relays, and only to someone who asked.
-- The receiving side adds the fourth: it fills a void and never replaces anything.
function LC.RelayRaidConfig(target)
    if not (IsInGroup() and target) then return end
    if next(LC.raidConfig) == nil then return end
    if LC.IsConfigOwner() then return end  -- the owner sends the real thing, with their name on it
    -- Only a config we RECEIVED. A fromSelf one is either ours by declaration -- in which case
    -- IsConfigOwner just returned and this is unreachable -- or one this client invented from its
    -- own defaults after a reload cleared raidConfig. Relaying that would spread it: the inventor
    -- hands "rolls off, empty council" to the next client that asks, that client stores it as the
    -- raid's, and from there it looks exactly like the real thing to everybody downstream.
    if LC.raidConfig.fromSelf then return end
    -- No role test beyond that, deliberately. Restricting this to the loot owner, and then to the
    -- council, kept covering the wrong half: after the lootmaster leaves and a few people reload,
    -- the only client still holding the config the raid agreed can be an ordinary raider -- and
    -- that is exactly the raid where somebody needs handing it. The receiver's rule is what makes
    -- this safe from anyone: it fills a void and can never replace or clear an existing config, so
    -- the worst a wrong sender achieves is giving settings to a client that had none.
    -- The field the lootmaster's key used to occupy. The key itself still does NOT travel -- only the
    -- config owner may name anybody, and that rule is what the empty field was protecting. What the
    -- relayer CAN say is whether the config it is passing on names somebody at all, and whether that
    -- somebody is standing here: both are facts about the raid, not a designation.
    --
    -- Without this a receiver could not tell "nobody was named" from "I was not told", and a raid
    -- leader that reads the second as the first hands itself a loot flow somebody else is already
    -- running (B130).
    --
    -- An unresolved key counts as PRESENT: we cannot show that person has gone, and the safe
    -- direction is the one where this client defers rather than claims.
    --
    -- A client passes on what it KNOWS, and what it was told counts as knowing. Our own designation
    -- is blank on every client that got its config from a relay in the first place (see
    -- LC.HandleConfigRelay), so deriving from that alone would make the second hop assert "nobody was
    -- named" -- the exact untruth B130 is about, stated affirmatively rather than merely implied. A
    -- client that was told nothing still says nothing.
    local designated = LC.raidConfig.lootmaster or ""
    local presence = LC.raidConfig.relayLootmaster or ""
    if designated ~= "" then
        presence = (not KASC.Identity.IsResolvedKey(designated)
            or KASC.Identity.FindUnitForKey(designated) ~= nil) and "1" or "0"
    end
    local prefix = "LC_CONFIG_RELAY:" .. (LC.raidConfig.minQuality or 4) .. ":"
        .. (LC.raidConfig.buttonLabels or "") .. ":"
        .. (LC.raidConfig.rollsEnabled and "1" or "0") .. ":" .. presence .. ":"
    local payload = BuildCouncilPayload(prefix, LC.raidConfig.councilMembers or "")
    if payload then LC.SendLC(payload, target) end
end

-- The other half. Accepted only into an EMPTY raidConfig, which is what makes it safe to send from
-- someone who is not the config owner: it can give a client the raid's settings, and it can never
-- take anything away or overwrite a real config with a forwarded copy. A returning lootmaster whose
-- own ApplyOwnConfig has already run is therefore untouched by it.
function LC.HandleConfigRelay(payload, senderKey)
    -- A void, or a config nobody agreed. The second case is the raid leader after a reload: their
    -- raidConfig came back empty, their own Lootmaster field is empty too, so LC.ApplyOwnConfig
    -- makes them config owner by the raid-leader fallback and writes THEIR defaults into it --
    -- usually rolls off and an empty council list. The fromSelf guard in LC.IsConfigOwner exists to
    -- stop exactly that, and it has nothing to bite on once a reload has cleared the table. A
    -- leader who typed their own name in the field is untouched: that is a config they own on
    -- purpose, and declaredKey short-circuits the fallback long before this.
    local ownField = LC.ResolveConfigName(KART_Settings and KART_Settings.lcLootmaster)
    local selfInvented = LC.raidConfig.fromSelf and not ownField
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    local minQ, buttons, rolls, presence, council = payload:match("^(%d+):([^:]*):([01]):([^:]*):(.*)$")
    if not minQ then return end

    -- The same rule TryAcceptConfig and LC.ApplyOwnConfig apply, at the third site that writes this
    -- field: an EMPTY council list means "not configured", not "this raid has no council". Here it
    -- decides two things.
    --
    -- One, a relay that carries a list is worth taking even when we have already taken one. Every
    -- peer answers a state request at once, spread over a fraction of a second, and the first answer
    -- may come from another client that has just reloaded and has no list either. Measured in the
    -- soak: an empty answer landed 0.17s ahead of the real one, cleared the "still waiting" marker,
    -- and the real one -- from a client that had been in the raid all evening -- was then rejected
    -- as "we already have a config". Two clients with amnesia confirmed each other and the raid
    -- split over who was council, which means every award from the other half is rejected.
    --
    -- Two, an empty list never replaces one we hold. Between them the transition only ever runs
    -- no-list to list, so peers still answering cannot swap it back and forth.
    local gainsCouncil = council ~= "" and (LC.raidConfig.councilMembers or "") == ""
    if next(LC.raidConfig) ~= nil and not selfInvented and not gainsCouncil then return end

    LC.raidConfig.minQuality     = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels   = buttons
    LC.raidConfig.rollsEnabled   = (rolls == "1")
    -- Left empty on purpose, matching what the sender put on the wire: nobody owns this config, so
    -- LC.GetLootmaster falls back to raid lead here exactly as it already does on every client that
    -- watched the lootmaster leave.
    LC.raidConfig.lootmaster     = ""
    -- What the relay says about the raid's designation -- not who it is, only whether there is one
    -- and whether they are here. "" means nobody was named, which is an answer, not a gap.
    --
    -- Set only on a relay we actually TOOK as our config (everything past the guard above), and
    -- deliberately so: a relay we reject as a config has told us nothing we were willing to believe
    -- about this raid, and letting the half we discard decide who owns the loot would make a message
    -- we refused the most consequential one we get. The client that rejected it already holds a
    -- config of its own, whose lootmaster field is the better answer anyway.
    --
    -- It survives everything except a better answer. This describes the RAID, not us, so only a
    -- source allowed to name somebody may overwrite it: another relay, the config owner's LC_CONFIG
    -- (see TryAcceptConfig), or our own field naming somebody (see LC.ApplyOwnConfig). Notably NOT
    -- an ApplyOwnConfig whose own field is empty -- that function runs on every GROUP_ROSTER_UPDATE
    -- and would wipe this within seconds of a join or a promotion, which is exactly how the first
    -- attempt at B130 undid itself.
    --
    -- Only the two values this protocol defines are stored. The capture is `[^:]*`, so anything at
    -- all can arrive here -- a garbled field, or whatever a later revision puts in this slot -- and
    -- every non-empty string is truthy: a 3.3.1 client would defer for ever over it, and never be
    -- offered the stand-in question either, because only "0" reaches LootmasterGone. Unrecognised
    -- reads as "told nothing", which is the state the addon behaved correctly in before this field
    -- existed at all.
    presence = (presence == "1" or presence == "0") and presence or nil
    LC.raidConfig.relayLootmaster = presence
    if council ~= "" or (LC.raidConfig.councilMembers or "") == "" then
        LC.raidConfig.councilMembers = council
    end
    LC.raidConfig.fromSelf       = nil

    -- Built from what we ENDED UP holding, not from what arrived: those differ whenever the list on
    -- the wire was empty and we kept ours, and rebuilding from the payload there would empty the
    -- lookup table while the config still named a council.
    LC.CouncilNamesTable = {}
    for _, name in ipairs(KAUtil.SplitString(LC.raidConfig.councilMembers or "", ";")) do
        local key = LC.ResolveConfigName(name)
        if key then LC.CouncilNamesTable[key] = true end
    end
    if LC.RefreshRaidWideFields then LC.RefreshRaidWideFields() end
    -- "Named and gone" is the stand-in question, and it has just become answerable for the first
    -- time. Waiting for the next GROUP_ROSTER_UPDATE to ask it would leave the raid with no loot
    -- owner for however long nobody joins or leaves, which in a boss pull is the whole fight.
    --
    -- Only to ASK it, never to withdraw an answer already given. LC.CheckStandIn's other half resets
    -- LC.standInAccepted when the lootmaster is back -- but a relay's "1" is not proof of that. When
    -- the relayer holds the raid's actual designation, its "1" is derived from that same designation
    -- (one raid, one config), so it IS about the person the stand-in replaced -- but "1" is also what
    -- goes out for a key that has not resolved yet, with no evidence of presence, and a relay-fed
    -- relayer only forwards what it was told, which can itself be stale. Weak evidence, not none, and
    -- not enough to withdraw an accepted stand-in on. A stand-in mid-round who takes a relay through
    -- the gainsCouncil exception would otherwise be stripped of the loot flow they are running,
    -- silently and without being asked anything. The roster path still resets them, off the
    -- designation it can actually see.
    if LC.CheckStandIn and not LC.standInAccepted then LC.CheckStandIn() end
end

-- The council/lootmaster/button-label edit boxes fire OnTextChanged on every keystroke; broadcasting
-- the full raid config per letter floods the raid with addon messages. Coalesce edits into a single
-- broadcast ~1s after typing stops (trailing edge, so the final complete text is what actually goes
-- out — unlike the leading-edge throttles elsewhere, which would send partial text mid-word).
function LC.BroadcastRaidConfigThrottled()
    if LC._cfgBroadcastTimer then LC._cfgBroadcastTimer:Cancel() end
    LC._cfgBroadcastTimer = C_Timer.NewTimer(1, function()
        LC._cfgBroadcastTimer = nil
        LC.BroadcastRaidConfig()
    end)
end

-- Authority is the configured LOOTMASTER, not the raid leader: the config is only accepted when the
-- sender is the very player the payload names as lootmaster. That is self-validating — no prior
-- state is needed, so it works for a client that has never seen a config — and it means handing raid
-- lead to someone else no longer lets their (usually empty) local settings overwrite the raid's
-- council list and lootmaster. Someone who should take over the config pulls it with the Sync button
-- (LC_SYNC_REQUEST) first, which is confirmed by the receiver.
--
-- A forged LC_CONFIG therefore can't self-promote either: the sender would have to name themselves
-- lootmaster, and every client resolves that name against the live roster the same way.
--
-- Factored out of LC.HandleConfig so LC.RetryPendingConfig (below) can re-run the exact same
-- acceptance predicate later, instead of a hand-rolled approximation of it — see B12 in
-- docs/BACKLOG.md. Returns true on success. On failure returns false plus a reason: "no-sender" (the
-- sender isn't resolvable at all — e.g. they've since left the group, or the raid is still forming;
-- the only retryable one), "parse-fail" (malformed payload), or "lootmaster-mismatch" (the payload
-- names a lootmaster who resolves to somebody other than the sender). Only the caller decides what
-- to do with the reason.
-- A lootmaster designation as it comes off the wire. LC.BroadcastRaidConfig sends a resolved identity
-- key whenever it can, and raw text only when it could not place the person either -- so this has to
-- accept both. A key must NOT be pushed back through LC.ResolveConfigName: that resolves names, and
-- would turn a perfectly good GUID into a pending text key.
local function ConfigKeyFromWire(value)
    if not value or value == "" then return nil end
    if KASC.Identity.IsResolvedKey(value) then return value end
    return LC.ResolveConfigName(value)
end

local function TryAcceptConfig(payload, senderKey)
    local unit = senderKey and KASC.Identity.FindUnitForKey(senderKey)
    if not unit then return false, "no-sender" end

    local minQ, buttons, rolls, lootmaster, council = payload:match("^(%d+):([^:]*):([01]):([^:]*):(.*)$")
    if not minQ then return false, "parse-fail" end

    -- THE ONLY ACCEPTANCE RULE: the sender holds raid lead (see docs/OWNERSHIP.md). Checked against
    -- our own roster, so it needs no stored state and follows a leader change by itself. There is
    -- exactly one such client in a raid, and every client can name which one -- so there is nothing
    -- left to arbitrate, and the guards that used to do the arbitrating are gone with the claim they
    -- existed for: a "lootmaster-mismatch" rejection (the sender no longer names itself -- naming
    -- somebody else is the whole point now), a "not-leader" rejection for an unnamed field, and the
    -- "weaker-claim" rule that decided between two configs on their content.
    if not UnitIsGroupLeader(unit) then return false, "not-leader" end

    LC.raidConfig.minQuality    = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels  = buttons
    LC.raidConfig.rollsEnabled  = (rolls == "1")
    -- The DESIGNATION, not the sender. Under the old rule the sender was always naming itself, so
    -- recording senderKey was the same thing; now the config owner is the raid leader and the field
    -- names whoever they put in charge of the loot -- usually somebody else entirely.
    --
    -- Empty stays empty and means "the raid leader hands it out themselves" (see LC.GetLootmaster's
    -- fallback), which is a real setting, not a missing one.
    LC.raidConfig.lootmaster    = ConfigKeyFromWire(lootmaster) or ""
    -- The authoritative answer to the question a relay could only answer sideways (see
    -- LC.HandleConfigRelay): the config owner is allowed to name somebody, so whatever this says --
    -- empty included -- replaces what a relay told us about the raid's designation.
    LC.raidConfig.relayLootmaster = nil
    -- An EMPTY council list means "not configured", not "this raid has no council".
    --
    -- The one content-based exception in this function, and it is here because the soak found what it
    -- costs to be without it: a client promoted to raid lead for a moment, who has never configured
    -- KART, broadcasts an empty list -- and every receiver then rejects every award, because
    -- Trade.HandleResult gates on LC.IsSenderCouncil and nobody is council any more. 94 of 3000 soak
    -- raids lost an award that way, silently. lcCouncilMembers has no default, so empty is exactly
    -- what an unconfigured client sends, and a raid deliberately running with no council at all is
    -- not a thing this guild does -- deciding items together IS the feature.
    --
    -- Narrow on purpose: it applies to this one field, and only in the direction that cannot lose
    -- information. A leader who genuinely wants a different council sends a non-empty list, which
    -- replaces the old one outright, so changing the council still works in one broadcast.
    local keepCouncil = council == "" and (LC.raidConfig.councilMembers or "") ~= ""
    if not keepCouncil then
        LC.raidConfig.councilMembers = council
    end
    LC.raidConfig.fromSelf      = nil -- received, not self-applied (see LC.ApplyOwnConfig)

    if not keepCouncil then
        LC.CouncilNamesTable = {}
        for _, name in ipairs(KAUtil.SplitString(council, ";")) do
            local key = LC.ResolveConfigName(name)
            if key then LC.CouncilNamesTable[key] = true end
        end
    end

    -- Two clients claiming to be lootmaster. Ours keeps precedence (LC.GetLootmaster prefers our
    -- own settings while IsConfigOwner holds), which is what protects a genuine lootmaster from
    -- being displaced by somebody else's stale entry -- but it is also exactly what leaves B11's
    -- raider without a vote window all evening: their own name in that field makes every LC_START
    -- from the real lootmaster fail LC.IsSenderLootOwner.
    --
    -- Deliberately not resolved by guessing. Nothing on the wire says which of the two is actually
    -- handing out loot, and silently flipping loot authority to whoever broadcast last would be far
    -- worse than saying so. One line, and the raider can clear their field in seconds.
    if LC.IsConfigOwner() and senderKey ~= LC.ResolveConfigName(KART_Settings.lcLootmaster) then
        local senderName = UnitName(unit) or "?"
        if not LC.lootmasterClashWarned then
            LC.lootmasterClashWarned = true
            print("|cff00ff00KART:|r " .. string.format(KART.L.LC_LOOTMASTER_CLASH, senderName))
        end
    else
        -- Cleared once the clash is gone, the same way LC.configRejectWarned is. Latched for the
        -- whole session it silenced the warning for a recurrence — a profile switch or a pasted name
        -- puts the raider back in the state where every LC_START from the real lootmaster is
        -- rejected on their client, and without this they would lose every vote window in silence.
        LC.lootmasterClashWarned = false
    end

    return true
end

-- Prints what THIS client actually believes about the Loot Council, for `/kart status`.
--
-- Exists because every value below was previously invisible from both ends. A raider could sit in a
-- raid running entirely different vote buttons, no rolls and an empty council, while the lootmaster
-- saw nothing wrong and the raider had no way to check — the evening of 2026-07-27 went that way
-- for hours. One line each, so a raider can paste the output and the question is settled.
--
-- Reports the EFFECTIVE values (LC.GetButtonConfig, LC.GetRollsEnabled, LC.GetLootmaster), not the
-- saved settings: the whole class of bug being diagnosed is the two disagreeing.
function LC.PrintStatus()
    local L = KART.L
    print("|cff00ff00KART " .. (KART.Version or "?") .. "|r " .. L.LC_STATUS_HEADER)

    local moduleOn = KART_Settings.lcModuleEnabled ~= false
    print("  " .. L.LC_STATUS_MODULE .. ": " .. (moduleOn and L.LC_STATUS_ON or L.LC_STATUS_OFF))
    -- The one personal setting a raid can be misled by. "Auto-Pass does not work" was answered four
    -- times on 2026-08-05 before anybody thought to ask whether it was switched on, and the status
    -- line -- the whole point of which is to answer that class of question without a round trip --
    -- did not say. It is not raid-wide and never overridden, so nothing else here implies it.
    print("  " .. L.LC_STATUS_AUTOPASS .. ": "
        .. (KART_Settings.lcAutoPass and L.LC_STATUS_ON or L.LC_STATUS_OFF))
    -- The session line says what this client BELIEVES; the qualifier says whether that belief is an
    -- answer or merely a starting value (see LC.sessionStateKnown). The two look identical from the
    -- outside and behave completely differently -- a client that has never been told is still
    -- asking, one that has been told is not -- and every reload-shaped failure so far came down to
    -- which of the two it was (B30, B31). Worth one word in the line a raider pastes into an issue.
    print("  " .. L.LC_STATUS_SESSION .. ": " .. (LC.sessionActive and L.LC_STATUS_ON or L.LC_STATUS_OFF)
        .. " (" .. (LC.sessionStateKnown and L.LC_STATUS_TOLD or L.LC_STATUS_UNTOLD) .. ")")

    -- Where the config in force came from. "own" and "received" behave completely differently and
    -- confusing them is what made the original reports so hard to read.
    local source
    if LC.IsConfigOwner() then
        source = L.LC_STATUS_SRC_OWN
    elseif LC.raidConfig and LC.raidConfig.lootmaster and LC.raidConfig.lootmaster ~= "" and not LC.raidConfig.fromSelf then
        local unit = KASC.Identity.FindUnitForKey(LC.raidConfig.lootmaster)
        source = string.format(L.LC_STATUS_SRC_RAID, (unit and UnitName(unit)) or "?")
    else
        source = L.LC_STATUS_SRC_NONE
    end
    print("  " .. L.LC_STATUS_CONFIG .. ": " .. source)

    -- The button count is the number that decides whether this client's votes can be matched at all
    -- (see B25) — spelled out rather than left to be counted off the list.
    local buttons = LC.GetButtonConfig()
    local labels = {}
    for _, def in ipairs(buttons) do labels[#labels + 1] = def.label end
    print("  " .. string.format(L.LC_STATUS_BUTTONS, #buttons) .. ": " .. table.concat(labels, ";"))

    print("  " .. L.LC_STATUS_ROLLS .. ": " .. (LC.GetRollsEnabled() and L.LC_STATUS_ON or L.LC_STATUS_OFF))

    -- Resolved against pending: a name that never resolves is a member who silently isn't one.
    local resolved, pending = 0, 0
    for key in pairs(LC.CouncilNamesTable or {}) do
        if KASC.Identity.IsResolvedKey(key) then resolved = resolved + 1 else pending = pending + 1 end
    end
    print("  " .. string.format(L.LC_STATUS_COUNCIL, resolved, pending))

    -- Who this client reads as raid lead, by name. Every ownership failure this week came down to
    -- two clients giving different answers to that -- each of them consistent with itself, which
    -- is what made them so quiet (B76, and the config nobody re-broadcast in a split raid). The
    -- config line above says where our config CAME from; this says who we think may send one, and
    -- comparing that one word across a raid is what tells the two apart in seconds.
    local leader = "-"
    for unit in KAUtil.EachGroupUnit() do
        if UnitIsGroupLeader(unit) then leader = UnitName(unit) or "?" break end
    end
    print("  " .. L.LC_STATUS_LEADER .. ": " .. leader
        .. (LC.IsConfigOwner() and (" (" .. L.LC_STATUS_IS_ME .. ")") or ""))

    local lm = LC.GetLootmaster()
    local lmUnit = lm ~= "" and KASC.Identity.FindUnitForKey(lm)
    print("  " .. L.LC_STATUS_LOOTMASTER .. ": " .. ((lmUnit and UnitName(lmUnit)) or (lm ~= "" and "?" or "-")))
    print("  " .. L.LC_STATUS_IS_ME .. ": " .. (LC.IsLootOwner() and L.LC_STATUS_YES or L.LC_STATUS_NO))

    -- What this client is actually tracking right now. "The item did not show up for me" is the most
    -- common report there is, and it has three different causes this line tells apart: no rolls at
    -- all (never heard about it), rolls listed but no vote row (heard, then hidden or pruned), or
    -- the item present and only the window missing. Sorted, because pairs order would differ between
    -- two people comparing their output side by side.
    local ids = {}
    for rollID in pairs(LC.rollItems or {}) do ids[#ids + 1] = rollID end
    table.sort(ids)
    local held = 0
    for _, rollID in ipairs(ids) do
        if not LC.rollNotInOurBags[rollID] then held = held + 1 end
    end
    print("  " .. string.format(L.LC_STATUS_TRACKED, #ids, held, #LC.voteListRolls, #LC.councilTabs)
        .. (#ids > 0 and (": " .. table.concat(ids, ",")) or ""))

    -- Named even when this client is not the loot owner and therefore never printed the warning: the
    -- person pasting this output is usually the one who cannot see an item, and "somebody in the raid
    -- is on the old protocol" explains a whole evening of silence (B62).
    local outdated = LC.OutdatedRaiders()
    print("  " .. string.format(L.LC_STATUS_OUTDATED, LC.PROTOCOL_VERSION, #outdated)
        .. (#outdated > 0 and (": " .. table.concat(outdated, ",")) or ""))

    -- Printed only when something actually went missing. On a clean evening this line is noise; on a
    -- broken one it is the first thing worth reading, because it separates the three causes that were
    -- indistinguishable on 2026-08-03 (B118): a message this client refused, a message it never
    -- recognised, and one of its own that never left. All four "refused" counters being zero while a
    -- raider is missing an item means the message never arrived at all — which is Blizzard's delivery,
    -- and needs the catch-up rather than a guard change.
    local kd = KASC:Diagnostics()
    if kd.dropNotInGroup + kd.dropUnknownToken + kd.sendRejected + kd.sendHeldBack
        + kd.sendDroppedRestricted + LC.diag.refusedSender + LC.diag.unknownRoll > 0 then
        print("  " .. string.format(L.LC_STATUS_DROPS, LC.diag.refusedSender, kd.dropNotInGroup,
            LC.diag.unknownRoll, kd.dropUnknownToken, kd.sendRejected, kd.sendQueued,
            kd.sendHeldBack, kd.sendDroppedRestricted))
    end
    -- Its own line and its own condition, because it answers a different question than the one
    -- above: not "how many sends were refused" but "how many of them stayed refused". A refused
    -- send is now put back on the wire (see SEND_RETRY_DELAYS in KASC), so sendRejected alone no
    -- longer means anything was lost -- only sendGaveUp does.
    if kd.sendRetried + kd.sendGaveUp > 0 then
        print("  " .. string.format(L.LC_STATUS_RESENDS, kd.sendRetried, kd.sendGaveUp))
    end
    -- On its own line and on its own condition: this one is not a "message went nowhere" count at
    -- all. A non-zero here means two clients demonstrably held different numbers for one item, which
    -- is worth reading even on an evening where nothing else was refused.
    if LC.diag.rollsConflict > 0 then
        print("  " .. string.format(L.LC_STATUS_ROLLCONFLICT, LC.diag.rollsConflict))
    end
    -- A measurement with no fix behind it yet (see LC.diag.clockRestarted): the report it belongs to
    -- has no reproduction, so the line has to name the writer as well as the count.
    -- Its own line, because it is not a refusal: these are answers to items this client had and has
    -- since released, which is ordinary. It is here at all because a large number says this client
    -- lets rolls go well before the rest of the raid is finished with them -- and because leaving it
    -- inside the refusal count is what made that count unreadable (see LC.diag.staleRoll).
    if LC.diag.staleRoll > 0 then
        print("  " .. string.format(L.LC_STATUS_STALEROLL, LC.diag.staleRoll))
    end
    if LC.diag.clockRestarted > 0 then
        print("  " .. string.format(L.LC_STATUS_CLOCKRESTART, LC.diag.clockRestarted,
            LC.diag.clockRestartedBy or "?"))
    end
    -- Own line, same reason as rollsConflict above: a non-zero count here means a batch this client
    -- received named more entries than one message can carry, so some of the raid's loot never
    -- reached this screen -- worth reading regardless of what else is zero.
    if LC.diag.dropCapped > 0 then
        print("  " .. string.format(L.LC_STATUS_DROPCAPPED, LC.diag.dropCapped))
    end
    -- Own line, same reason again: a non-zero here means a packed announcement or roll table arrived
    -- and this client could not read it back, so a whole boss's items never reached this screen. The
    -- one thing it points at that nothing else does is a LibDeflate mismatch -- LibStub hands out the
    -- highest minor any addon loaded, so this raider may not be running our copy at all.
    if LC.diag.packedUnreadable > 0 then
        print("  " .. string.format(L.LC_STATUS_PACKUNREADABLE, LC.diag.packedUnreadable))
    end
    -- Own line as well, and the only counter here that is about what this client SENT: a non-zero
    -- count means this raider's own answer was left out of its own repeat, which is the one failure
    -- on this path that nobody else's screen can show.
    if LC.diag.votesCapped > 0 then
        print("  " .. string.format(L.LC_STATUS_VOTESCAPPED, LC.diag.votesCapped))
    end
    -- The received twin, on its own line for the same reason dropCapped has one: a non-zero here
    -- means somebody's repeat arrived longer than one message may carry, so part of what they voted
    -- never reached this screen and no repeat of theirs will ever bring it.
    if LC.diag.voteBatchCapped > 0 then
        print("  " .. string.format(L.LC_STATUS_VOTEBATCHCAPPED, LC.diag.voteBatchCapped))
    end
end

-- ==========================================================================
--  B12: retry a config rejected only because the sender wasn't resolvable yet
-- ==========================================================================
--
-- A config can arrive before its sender is resolvable on this client — normal while a raid is still
-- forming — and nothing re-delivers it on its own once the roster settles (see B12 in
-- docs/BACKLOG.md), so the one payload that failed for that reason is kept around and retried, with
-- the SAME predicate and never a relaxed one, until it succeeds or the budget below runs out.
--
-- This originally retried an unresolved lootmaster NAME, which was the far more common failure and
-- for some clients a permanent one — see TryAcceptConfig, which no longer consults the name for the
-- decision at all. That case cannot occur any more; this machinery now covers only the genuinely
-- transient one it was always meant for.
LC.pendingConfig = nil -- {payload, senderKey, attempts, timer} or nil while nothing is pending

-- A rejected config leaves this client quietly using its OWN vote button labels, rolls toggle and
-- council list while it still takes part in the session — so its votes land under the wrong label
-- on the council panel and it never rolls (see B25). That went unnoticed for a whole raid on
-- 2026-07-27 because nothing said a word. Say something.
--
-- Latched: LC_CONFIG is re-broadcast on every roster change, so an unlatched print would repeat
-- once per join during raid formation. Cleared on the next acceptance, which is exactly when the
-- situation has actually changed.
LC.configRejectWarned = false
local function WarnConfigRejected(reason)
    if LC.configRejectWarned then return end
    LC.configRejectWarned = true
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_CONFIG_REJECTED, tostring(reason)))
end

-- Every 10s for up to 12 attempts (~2 minutes) between roster changes — comfortably longer than a
-- raid takes to finish filling up, without retrying all evening.
-- Roster changes (see LC.RetryPendingConfigThrottled) do NOT add attempts on top of this schedule —
-- they consume one and re-arm the timer early, so sustained roster churn (the leading-edge throttle
-- allows roughly one attempt per second) can collapse the effective window to as little as ~12
-- seconds. This mostly self-corrects in practice: a roster change during an active session also
-- re-broadcasts the config (LootCouncil.lua:1089), and a fresh "no-sender" rejection replaces the
-- pending payload and resets attempts back to 0 (see LC.HandleConfig below).
local PENDING_CONFIG_RETRY_INTERVAL = 10
local PENDING_CONFIG_MAX_ATTEMPTS   = 12

-- (Re)arms the single retry timer for the current pending payload, cancelling any timer already
-- running for it first — this is called from both the timer's own callback and the roster-change
-- hook, and only one may be in flight at a time. Unlike LC.BroadcastRaidConfigThrottled's callback,
-- this doesn't nil the handle as the callback's first line before doing anything else: Cancel()ing
-- a timer that has already fired (which is what happens here and in LC.CancelPendingConfig below,
-- whenever either runs from inside this timer's own callback) is a documented no-op, so there's
-- nothing to guard against by nil-ing early.
local function ScheduleNextPendingConfigAttempt()
    local pending = LC.pendingConfig
    if not pending then return end
    if pending.timer then pending.timer:Cancel() end
    pending.timer = C_Timer.NewTimer(PENDING_CONFIG_RETRY_INTERVAL, LC.RetryPendingConfig)
end

-- Cancels and clears the pending payload, if any. Called on successful acceptance, when the session
-- ends (LC.SetSessionActive, LC.HandleActive) and when leaving the raid (LC.CheckRaidJoin) — a
-- payload from a session/raid that's no longer current has nothing left to become relevant to.
-- Also self-called from inside the retry timer's own callback on success (see
-- ScheduleNextPendingConfigAttempt above for why cancelling that same timer here is still safe).
function LC.CancelPendingConfig()
    if LC.pendingConfig and LC.pendingConfig.timer then
        LC.pendingConfig.timer:Cancel()
    end
    LC.pendingConfig = nil
end

-- CouncilNamesTable/raidConfig just changed, so a member who wasn't council before may be now —
-- refresh the open panel the same way ResolveRollItemLink does for a late-arriving item link
-- (LootCouncil.lua:1110, refresh block at :1117-1120). The vote popup needs no equivalent: it
-- doesn't show council-only info.
local function RefreshCouncilPanelIfOpen()
    if LC.councilPanel and LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
        KART.LC.Council.RefreshCouncilTabs()
    end
end

-- Everything that has to happen once a config is finally in force, wherever it came from.
--
-- Two of these were only on the retry path, which is how they came to be filed separately:
--   * B52 -- LC.HandleConfig's own accept branch never repainted an open council panel, so a council
--     member kept reading votes under the previous label set until some unrelated event refreshed
--     the rows. On the one screen that decides who gets the item.
--   * B61 -- council membership was evaluated once, at roll start, by the four sites that open the
--     panel. A client whose config lands afterwards IS council from that moment, but had no tab for
--     the items already on the table and could not assign them.
function LC.OnConfigAccepted()
    LC.CancelPendingConfig()
    LC.configRejectWarned = false
    if LC.RefreshRaidWideFields then LC.RefreshRaidWideFields() end
    RefreshCouncilPanelIfOpen()
    LC.CatchUpCouncilPanel()
end

-- What `/kart lc` does: brings back whichever Loot Council window still has tracked, unfinished
-- rolls. Does nothing (rather than error) when nothing is being tracked right now.
--
-- Both branches REBUILD before showing (B51). The command used to call :Show() on the frame, and a
-- frame's row pool holds whatever was last drawn — while both these windows only HIDE on their "x",
-- so the picture that came back could be arbitrarily old: rows for items long since won or expired,
-- countdowns frozen where they stopped, and live vote buttons on all of them.
function LC.ReopenTrackedWindow()
    if #LC.councilTabs > 0 then
        -- Built here if it does not exist yet, rather than guarded on. The panel is created lazily,
        -- by the first item that reaches it — so after a reload the tabs are back (B81) while
        -- LC.councilPanel is still nil, and guarding on it made this command fall silently through
        -- its own condition. That is the report this whole thread started from: "session is running,
        -- two items on the table, /kart lc opens nothing".
        if not LC.councilPanel then KART.LC.Council.CreateCouncilPanel() end
        KART.LC.Council.RefreshCouncilRows()
        KART.LC.Council.RefreshCouncilTabs()
        -- Asked for by hand, so whatever was put away is being taken back out on purpose (B123).
        LC.councilPanelDismissed = nil
        LC.councilPanel:Show()
    elseif #LC.voteListRolls > 0 then
        -- The dispatcher rather than :Show(): it rebuilds the rows, sizes the window and shows it
        -- itself. It also leaves it hidden when every remaining roll is hidden by a personal
        -- setting, which is the honest answer in that state — `/kart showall` is what overrides it.
        LC.Vote.RefreshVoteListRows()
    end
end

-- What `/kart trade` and `/kart owed` do. Same shape and same reason as LC.ReopenTrackedWindow
-- above: both reminder windows only HIDE on their "x", and every removal path deliberately refuses
-- to reopen a closed one (see Trade.RefreshTradeReminderIfShown). So an obligation ticked off,
-- traded away or timed out while the window was shut stayed in the frame's row pool, and a plain
-- :Show() put that picture back on screen -- an item the lootmaster had already handed over, still
-- listed as owed. The refresh below rebuilds the rows, sizes the window and shows it itself, and
-- correctly leaves it hidden when nothing is owed any more.
function LC.ReopenTradeReminder()
    LC.Trade.RefreshTradeReminder()
end

function LC.ReopenOwedReminder()
    LC.Trade.RefreshOwedReminder()
end

-- Opens a tab for every roll already on the table, for a client that has just become council.
--
-- The remaining time is carried across rather than restarted: Council.ShowCouncilPanel writes
-- LC.rollDeadlines from the seconds it is given, so passing the default would hand a late arrival a
-- longer vote than everybody else is looking at -- and the council decides when the shortest one
-- runs out. A roll whose deadline has already passed is skipped; it is not on the table any more.
function LC.CatchUpCouncilPanel()
    if not (LC.sessionActive and LC.IsCouncil()) then return end
    if not (KART.LC.Council and KART.LC.Council.ShowCouncilPanel) then return end
    local ids = {}
    for rollID in pairs(LC.rollItems or {}) do ids[#ids + 1] = rollID end
    table.sort(ids)   -- deterministic tab order, not pairs order
    for _, rollID in ipairs(ids) do
        local deadline = LC.rollDeadlines and LC.rollDeadlines[rollID]
        local left = deadline and (deadline - GetTime()) or nil
        if left == nil or left > 0 then
            KART.LC.Council.ShowCouncilPanel(rollID, left or (KART_Settings.lcVoteSeconds or 20))
        end
    end
end

-- Re-runs TryAcceptConfig for the one stored payload, if any. Called by its own retry timer and by
-- the roster-change hook (LC.RetryPendingConfigThrottled) — both are ways the lootmaster-resolution
-- failure can clear up. Re-running the WHOLE predicate (not just the lootmaster check) matters here:
-- the stored sender may have left the group since, in which case TryAcceptConfig now fails with
-- "no-sender" instead — and that can never resolve, so the payload is dropped instead of retried.
--
-- Not gated on lcEnabled the way the LC_CONFIG message handler is (see the KASC:RegisterMessage
-- call near the bottom of this file) — that gate only guards message dispatch, HandleConfig itself
-- never checks it either. So a payload stored while the module was enabled is still applied here if
-- the raider disables Loot Council before the retry fires. Harmless, just not a uniform gate.
function LC.RetryPendingConfig()
    local pending = LC.pendingConfig
    if not pending then return end

    local accepted, reason = TryAcceptConfig(pending.payload, pending.senderKey)
    if accepted then
        LC.OnConfigAccepted()
        return
    end

    -- "no-sender" is the reason we stored this payload for, so it is the one reason to keep
    -- waiting on. Anything else appearing now means the payload became unusable for a different
    -- reason entirely, and no further attempt will change that.
    if reason ~= "no-sender" then
        LC.CancelPendingConfig()
        WarnConfigRejected(reason)
        return
    end

    pending.attempts = pending.attempts + 1
    if pending.attempts >= PENDING_CONFIG_MAX_ATTEMPTS then
        LC.CancelPendingConfig()
        WarnConfigRejected(reason) -- gave up: from here the user is on their own settings for good
        return
    end
    ScheduleNextPendingConfigAttempt()
end

-- Leading-edge throttle, same pattern as LC.RetryPendingResolutionsThrottled right below — but a
-- separate flag and a separate function. That one retries council-list/lootmaster entries already
-- INSIDE an accepted config; this one retries a config that was never accepted in the first place.
-- Different problem, same trigger (a roster change), so both get wired to it independently rather
-- than merged into one path.
local isPendingConfigThrottled = false
function LC.RetryPendingConfigThrottled()
    if isPendingConfigThrottled then return end
    isPendingConfigThrottled = true
    C_Timer.After(1, function()
        isPendingConfigThrottled = false
        LC.RetryPendingConfig()
    end)
end

-- Applies a raid-config broadcast (called from KASC's dispatcher via the LC_CONFIG handler
-- registered near the bottom of this file). See TryAcceptConfig above for the acceptance predicate.
function LC.HandleConfig(payload, senderKey)
    local accepted, reason = TryAcceptConfig(payload, senderKey)
    if accepted then
        LC.OnConfigAccepted()
        return
    end

    -- Warn straight away for the reasons that will never heal. "no-sender" gets the benefit of the
    -- doubt instead: it is normal while a raid is still filling up, so the retry below is given its
    -- budget first and only warns if it runs out (see LC.RetryPendingConfig).
    -- "not-leader" is silent too: it is a legitimate ignore, not a misconfiguration. Nobody but the
    -- raid leader broadcasts an empty-field config in the first place, so it only shows up across a
    -- leader change or from an older client, and neither is the receiver's problem to report.
    if reason ~= "no-sender" and reason ~= "not-leader" and reason ~= "weaker-claim" then
        WarnConfigRejected(reason)
    end

    -- Only "no-sender" is worth remembering. It means the sender isn't resolvable on this client
    -- YET -- normal while a raid is still forming -- and resolves itself as the roster settles.
    --
    -- The other two are permanent by nature: "parse-fail" is a malformed payload that will never
    -- parse, and "lootmaster-mismatch" means the sender broadcast somebody else's name, which is a
    -- misconfiguration on their end that no amount of waiting on ours will change. Retrying either
    -- would only let noise evict a legitimate pending payload.
    if reason == "no-sender" then
        if LC.pendingConfig and LC.pendingConfig.timer then LC.pendingConfig.timer:Cancel() end
        LC.pendingConfig = { payload = payload, senderKey = senderKey, attempts = 0 }
        ScheduleNextPendingConfigAttempt()
    end
end

-- GROUP_ROSTER_UPDATE fires in bursts during mass-invite/raid formation, and re-scanning every
-- pending entry on every single firing burns CPU for no benefit — same leading-edge throttle
-- pattern as KART.HandleAutoPromoteThrottled in GroupLogic.lua.
local isPendingResolutionThrottled = false
function LC.RetryPendingResolutionsThrottled()
    if isPendingResolutionThrottled then return end
    isPendingResolutionThrottled = true
    C_Timer.After(1, function()
        isPendingResolutionThrottled = false
        LC.RetryPendingResolutions()
    end)
end

-- Re-attempts resolution for every council-list/lootmaster entry still stuck on plain text (see
-- KASC.Identity.IsResolvedKey), and migrates any KART_LCOfficerNotes entry still under its legacy
-- short-name key — both cases just mean "this person hadn't been seen yet" at the time they were
-- first parsed. Promotes them to a real key in place; still-unresolvable entries are left alone
-- and retried again next time the roster changes.
function LC.RetryPendingResolutions()
    -- Our own config first: LC.IsConfigOwner needs our own lootmaster entry to resolve, which it
    -- can't while solo on a cold cache — so the ApplyOwnConfig at login may have no-opped and left
    -- us with no council table at all. Re-running it here rebuilds it the moment the roster makes
    -- the name resolvable. No-ops for anyone who isn't the owner, so this is free for everyone else.
    LC.ApplyOwnConfig()

    -- Collect first, mutate second — Lua's pairs()/next() traversal is undefined if a new key
    -- (not already present) is added to the table mid-loop, which LC.CouncilNamesTable[key] = true
    -- below would otherwise do for every newly-resolved entry.
    local pendingCouncilEntries = {}
    for pendingText in pairs(LC.CouncilNamesTable) do
        if not KASC.Identity.IsResolvedKey(pendingText) then
            table.insert(pendingCouncilEntries, pendingText)
        end
    end
    for _, pendingText in ipairs(pendingCouncilEntries) do
        local key = LC.ResolveConfigName(pendingText)
        if key and KASC.Identity.IsResolvedKey(key) then
            LC.CouncilNamesTable[pendingText] = nil
            LC.CouncilNamesTable[key] = true
        end
    end

    if LC.raidConfig.lootmaster and not KASC.Identity.IsResolvedKey(LC.raidConfig.lootmaster) then
        local key = LC.ResolveConfigName(LC.raidConfig.lootmaster)
        if key and KASC.Identity.IsResolvedKey(key) then
            LC.raidConfig.lootmaster = key
        end
    end

    -- Same collect-first reasoning: LC.MigrateOfficerNoteKey adds a new key to KART_LCOfficerNotes
    -- on a successful migration, which is unsafe to do while pairs() is still traversing that
    -- same table.
    local legacyOfficerNoteKeys = {}
    for oldKey in pairs(KART_LCOfficerNotes) do
        table.insert(legacyOfficerNoteKeys, oldKey)
    end
    for _, oldKey in ipairs(legacyOfficerNoteKeys) do
        KART.LC.OfficerNotes.MigrateOfficerNoteKey(oldKey)
    end
end

-- Answers an "LC_STATE_REQ" broadcast from a joining/reloading peer with the current session flag
-- and, if a session is active, the full raid config — a one-shot pull instead of waiting for the
-- owner's own roster-change handler to happen to fire (see LC.CheckRaidJoin).
-- requester: the full "Name-Realm" of whoever asked (CHAT_MSG_ADDON sender).
--
-- The reply is WHISPERED to them, never broadcast. Broadcasting was actively harmful: LC_ACTIVE:0
-- makes every receiver run LC.ClearAllRolls, so one late joiner asking for state while the owner's
-- own sessionActive is still false (the state a fresh /reload starts in, until they answer the
-- session prompt) would wipe the in-flight rolls of the entire raid. The requester is the only client
-- that needs the answer, and they have no roll state to lose.
function LC.HandleStateRequest(requester, requesterKey)
    if not (IsInGroup() and requester) then return end
    -- The requester is the person we believe owns the session, and ours is running: they have just
    -- reloaded and lost it. Tell them, because nobody else can — LC.HandleStateRequest's own replies
    -- below are the loot owner's to send, and after a reload that is the client doing the asking.
    -- Left unanswered, they come back believing there is no session while twenty other clients are
    -- still in one: they force-win nothing, every Auto-Pass raider keeps passing, and the item goes
    -- to a green roll (backlog B30).
    --
    -- Council and the raid leader answer at once, so the usual reload costs a handful of whispers
    -- rather than one per raider. EVERY other raider answers too, just a few seconds later.
    --
    -- Restricting it to council was a message-volume decision, and it failed on exactly the raid
    -- that needs it most: two council members ported out and the third had reloaded a moment ago,
    -- so its own sessionActive was false as well. The only clients that still KNEW the session was
    -- running were ordinary raiders, and they were not allowed to say so -- the lootmaster stayed
    -- outside the session for the rest of the evening, force-winning nothing while every Auto-Pass
    -- raider kept passing. Found by tests/test_lc_soak.lua, seed 87.
    --
    -- Cheap, because none of this happens unless the requester IS the loot owner, which means a
    -- lootmaster reload and nothing else. Safe to repeat, because the claim is accepted only by the
    -- person it is about and only while their session is off (see LC.HandleSessionResume), so the
    -- late whispers that arrive after a successful resume do nothing at all. Jittered so twenty
    -- clients do not answer in the same instant and lose the lot to the chat throttle.
    --
    -- Sent to ANY asker, not only to the loot owner. The owner's own LC_ACTIVE below is the fast,
    -- authoritative answer and stays the normal path — but it is the only one, and when the owner
    -- is the unstable part (gone, just arrived, mid-reload) a joiner asked and asked and never
    -- learned there was a session at all. This is the backstop for that, and it is why the receiver
    -- now accepts it from anyone who does not yet know (see LC.HandleSessionResume).
    if LC.sessionActive and requesterKey and not LC.IsLootOwner() then
        -- Council and the raid leader answer at once when the asker is the owner themselves; that
        -- is the reload case, and it is the one that must not wait. Everyone else, and every other
        -- asker, comes a few seconds behind, by which time the owner's own answer has usually made
        -- this a no-op.
        if (LC.IsCouncil() or UnitIsGroupLeader("player"))
            and requesterKey == LC.GetLootOwnerKey() then
            LC.SendLC("LC_SESSION_RESUME", requester)
        else
            C_Timer.After(3 + math.random() * 4, function()
                -- Re-checked on arrival: we may have left, lost the session, or become the owner
                -- ourselves in the meantime.
                if LC.sessionActive and not LC.IsLootOwner() then
                    LC.SendLC("LC_SESSION_RESUME", requester)
                end
            end)
        end
    end
    -- Two owners answer here: the session flag belongs to the loot owner (only they can toggle it,
    -- see LC.SetSessionActive/HandleActive), the config to whoever the lootmaster field names (see
    -- LC.IsConfigOwner). Normally the same person, in which case this sends both.
    --
    -- Config first, then the session flag — same ordering requirement as LC.SetSessionActive: the
    -- requester validates LC_ACTIVE against the lootmaster it knows, and a fresh joiner knows none
    -- until this config lands. Sent the other way round, a lootmaster who isn't the raid leader had
    -- their reply dropped and the joiner sat out the session.
    if LC.sessionActive and LC.IsConfigOwner() then
        LC.BroadcastRaidConfig(requester)
    elseif LC.sessionActive then
        -- Nobody owns the config -- the lootmaster left for good. Hand on what the raid settled on
        -- rather than let the asker run the evening on their own vote buttons (B65). Whoever is
        -- running the loot flow and the council answer at once; everyone else a few seconds behind,
        -- by which time one of those has usually made it a no-op. Jittered so a raid full of
        -- raiders does not answer in the same instant and lose the lot to the chat throttle.
        if LC.IsLootOwner() or LC.IsCouncil() then
            LC.RelayRaidConfig(requester)
        else
            C_Timer.After(3 + math.random() * 4, function() LC.RelayRaidConfig(requester) end)
        end
    end
    -- Only when our flag is an answer rather than a starting value (see LC.sessionStateKnown). A
    -- freshly reloaded loot owner is still the loot owner, so without this they replied "session
    -- off" to every peer that asked, and each recipient ran LC.ClearAllRolls — one whisper per
    -- asker, until the session the raid was in had been ended for all of them by the one client
    -- that had simply not caught up yet.
    if LC.IsLootOwner() and LC.sessionStateKnown then
        LC.SendLC("LC_ACTIVE:" .. (LC.sessionActive and "1" or "0"), requester)
    end
    -- Last, and only from the loot owner: the items still on the table, for a client that was deaf
    -- when they were announced (B66). After the session flag, because a client that does not know
    -- there is a session has nothing to hang them on.
    --
    -- The key goes with the name now: a state request is also what a late JOINER sends, and the rule
    -- settled on 2026-08-03 is that they do not get a running item. Who was here when each item
    -- dropped is recorded at the source (LC.rollEligible), and this is where it is applied (B118, B79).
    LC.SendOpenRolls(requester, requesterKey)
end

-- The rolls still open, listed to one client that has just asked for the raid's state (B66).
--
-- A drop is announced once, in the LC_DROP the loot owner sends when the collection window closes,
-- and never re-requested. A client is deaf at that instant for two ordinary reasons -- it is still coming back
-- from a reload, or Blizzard's chat throttle swallowed the message -- and it then had no way back to
-- that item at all: no vote row, no answer from it, and a council waiting on somebody who never saw
-- the thing.
--
-- Capped, because this is a burst of whispers on top of the two replies already going out, and a
-- raid decides a handful of items at a time, not thirty.
local ROLL_CATCHUP_MAX = 5

-- What an item looks like on the wire, for the two messages that announce a real drop (LC_START and
-- its catch-up). The full item string, so a client that never saw Blizzard's own roll can rebuild the
-- SAME item rather than the base version of it -- an itemID alone carries no bonus ids, so the whole
-- raid read "Item Level 44" off a 285 item on 2026-08-03 (B119).
--
-- Falls back to the bare itemID only when there is no real link to take a string from at all.
--
-- It used to fall back a second time, for any string long enough to push the message past 255 bytes,
-- to keep a catch-up burst inside one chunk each. That trade was wrong, and #35 is what said so: 3.3.1
-- fixed the base-item bug on LC_DROP and left this path alone, so the clients being REPAIRED -- the
-- ones that missed the original announcement and are the whole reason the message exists -- kept
-- receiving the base version. Item level 44 instead of 285, wrong tooltip stats, empty upgrade
-- column. And the length it was avoiding stopped being a limit when the transport moved onto AceComm:
-- anything over the cap is split and reassembled whole (see KASC:Send). Every Midnight drop carrying
-- a full upgrade track is over it, so this was not the exception it reads as -- it was the norm.
--
-- The cost is one extra chunk per caught-up item, bounded by ROLL_CATCHUP_MAX.
function LC.ItemPayload(link, itemID)
    return KAUtil.GetItemString(link)
        or itemID or (type(link) == "string" and link:match("item:(%d+)")) or ""
end

-- The other direction, for the handlers that read one of those payloads back. The bare id is what
-- everything downstream compares on -- PurgeStaleRoll, the dismissal note (LC.rollDismissed), the
-- stale-result guards -- because it is the only part two clients can be relied on to agree about: the
-- same item reaches them as different STRINGS, since bonus ids differ per drop. "" when the payload
-- carries no item at all, which is what a pre-3.3.1 sender or a truncated string leaves behind.
function LC.PayloadItemID(itemPart)
    itemPart = itemPart or ""
    return itemPart:match("^item:(%d+)") or itemPart:match("^(%d+)$") or ""
end

-- Who was in the raid when this roll was announced, by identity key. Written by the loot owner only,
-- at the moment it announces, and it is the whole of the rule the maintainer settled on 2026-08-03:
--
--     a late arrival is not handed a running item -- "der ist ja nicht mal lootberechtigt".
--
-- Until now that rule was enforced by asking BLIZZARD: a catch-up was only applied if this client had
-- the same roll open, which proves it was there. That proof fails for exactly the people the catch-up
-- exists for (dead, released, out of range -- Blizzard gave them no roll either) and cannot exist at
-- all for a manually added item, which is why B79 was stuck. Recording the roster at the source
-- answers it for both, and answers it on the client that actually knows.
LC.rollEligible = LC.rollEligible or {}

local function SnapshotEligible(rollID)
    local set = {}
    for unit in KAUtil.EachGroupUnit() do
        local key = (KASC.Identity.ResolvePlayer(unit))
        -- Pending text keys are kept deliberately: a raider whose name has not resolved yet was still
        -- standing there, and refusing them later would be the same silent exclusion this fixes.
        if key and key ~= "" then set[key] = true end
    end
    LC.rollEligible[rollID] = set
end
LC.SnapshotEligible = SnapshotEligible

-- Whether we may hand rollID's details to this asker. Nothing recorded means the roll predates this
-- mechanism (an owner mid-upgrade, or a roll restored from a snapshot written by an older build), and
-- the old proof stands in for it: a client Blizzard gave the same roll to was demonstrably there.
function LC.MayCatchUp(rollID, askerKey)
    local set = LC.rollEligible[rollID]
    if not set then return nil end
    return set[askerKey] == true
end

-- THE RULE, stated once and used by every place that asks "is this roll still askable": an item is
-- askable for as long as it is still ON THE TABLE here, not only while its voting timer runs.
--
-- It used to be "deadline > now", and at the default lcVoteSeconds of 20 that made the repair path
-- unreachable. The first heartbeat naming a roll only stamps LC.rollReqSent; the escalation to
-- LC_ROLLS_REQ needs another ROLL_REQ_COOLDOWN on top of it, i.e. t >= 32 even now that the drop is
-- announced within two seconds of itself — on a rollID that stopped being listed at t = 20, and the
-- gap was wider still while the heartbeat ticked every ten seconds. The lootmaster ports out
-- mid-distribution, a raider's LC_ROLLS chunk is dropped, the whisper that first ask makes is refused
-- by the stand-in (LC.MayCatchUp, B118), and by the time the group-wide ask was due there was nothing
-- left to trigger it.
--
-- The council DECIDES after the timer expires, while the item is still tabbed and waiting to be
-- assigned. That is exactly when a client that lost the item or its numbers needs repairing, so that
-- is how long it stays askable. Accepted side effect: a missing ITEM stays catchable after voting
-- closed too — same question for the other half, same answer (see LC.HandleStart's expired branch for
-- what the receiver does with one).
--
-- "Still on the table" is deliberately not a new flag: it is exactly what Trade.ClearRollState
-- removes — a deadline entry plus a known item — so a roll this client has forgotten cannot be
-- heartbeat forever, and nothing has to be cleared by hand. Note what that means per client: a plain
-- raider is not tabbing anything, so Vote.PruneExpiredRolls frees an expired roll a second after its
-- deadline and this widening changes nothing for them. It reaches the loot owner and the council —
-- precisely the clients that still have a decision to make.
function LC.RollTracked(rollID)
    return rollID ~= nil and not LC.IsTestRoll(rollID)
        and (LC.rollDeadlines or {})[rollID] ~= nil and LC.rollItems[rollID] ~= nil
end

function LC.SendOpenRolls(target, targetKey)
    if not (IsInGroup() and target and LC.sessionActive and LC.IsLootOwner()) then return end
    local now, sent = GetTime(), 0
    for rollID, deadline in pairs(LC.rollDeadlines or {}) do
        if sent >= ROLL_CATCHUP_MAX then break end
        local link = LC.rollItems[rollID]
        local itemID = type(link) == "string" and link:match("item:(%d+)") or nil
        -- Only rolls still on the table (LC.RollTracked — the one rule, stated there), and only once
        -- the item is actually known: an unresolved one would arrive as a question mark the receiver
        -- could not repair, which is the state LC.HandleStart exists to avoid.
        --
        -- And only to somebody who was here for it. A state request is also what a late JOINER sends,
        -- which is why this used to lean on the receiver's own Blizzard roll to sort the two apart.
        -- Strictly "yes", not "not no". A roll with no record at all is one this client cannot vouch
        -- for -- announced by a previous owner before the role moved, or restored from an older
        -- build's snapshot -- and the rule settled on 2026-08-03 does not have a maybe in it. The cost
        -- of being wrong here is a raider who has to be told about an item by voice; the cost of
        -- guessing the other way is somebody who was not in the raid taking part in its loot.
        if itemID and LC.RollTracked(rollID)
            and LC.MayCatchUp(rollID, targetKey) == true then
            -- 0 means "voting on this one is already over" — see LC.HandleStart, which is what turns
            -- it into tracking without a vote row rather than into a one-second window.
            local secs = math.max(0, math.floor(deadline - now))
            LC.SendLC("LC_ROLL_CATCHUP:" .. rollID .. ":" .. secs .. ":"
                .. LC.ItemPayload(link, itemID), target)
            sent = sent + 1
        end
    end
end

-- The receiving half. Entitlement is now decided by the SENDER, which is the only client that knows
-- who was standing there when the item dropped (see LC.rollEligible) -- so this no longer demands
-- that Blizzard gave us the same roll.
--
-- That demand was the bug B118 kept running into: a client that was dead, released or out of range
-- has no roll of its own, which is precisely why it needed catching up, and the guard threw the
-- catch-up away on exactly those clients. A manually added item never has a Blizzard roll at all.
--
-- Deliberately does NOT roll 1-100 on their behalf. The roll belongs to the moment the item dropped;
-- inventing one now would put a number in the council's tally that never existed, and the column
-- showing "-" for somebody who was disconnected is the honest reading.
function LC.HandleRollCatchup(payload, senderKey)
    local rollID = tonumber(payload:match("^(%d+):"))
    if not rollID then return end
    if LC.rollItems[rollID] then return end        -- already have it; nothing to catch up
    -- Nor one we put away ourselves (LC.rollDismissed) -- while it is still the item we put away. We
    -- stopped asking the moment the tab was closed, but an answer to the LAST ask can still be in
    -- flight, and taking it would reopen the panel for an item this client is finished with -- the
    -- exact thing the note exists to stop.
    --
    -- The note remembers WHICH item, so a repeat and a REUSE can be told apart right here (B132):
    -- Blizzard hands the same rollID to an unrelated item within seconds on trash, and nobody ever
    -- dismissed that one. A different item is therefore taken, and PurgeStaleRoll inside
    -- LC.HandleStart drops the note on the way through -- which is what keeps that clear honest:
    -- everything reaching LC.HandleStart under a dismissed rollID is a genuinely new roll.
    --
    -- Refused whenever the two cannot be compared -- a dismissal of an item this client never
    -- resolved (stored as `true`), or a payload carrying no item -- which is the id-only refusal this
    -- used to make in every case.
    local dismissed = LC.rollDismissed[rollID]
    if dismissed then
        local itemID = LC.PayloadItemID(payload:match("^%d+:%d+:?(.*)$"))
        if itemID == "" or type(dismissed) ~= "string" or dismissed == itemID then return end
    end
    -- LC.HandleStart re-stamps the BoP trade clock from time() on purpose (see its comment): for an
    -- announcement that is accurate to within the collection window, because the owner sends LC_DROP
    -- at most DROP_COLLECT (half a second) after the loot event, and the transport adds a little more.
    -- It is not accurate here. A catch-up arrives whenever this client got round to asking,
    -- and since an item stays askable for as long as it is tracked (LC.RollTracked) that can be
    -- minutes after the drop -- so dating the four-hour trade window from the repair would let the
    -- reminder outlive the real deadline by exactly how late the repair was, and promise a hand-over
    -- that can no longer happen.
    --
    -- A stamp already sitting under this ID is the one this client took when the item actually
    -- dropped: Vote.PruneExpiredRolls frees an expired roll but deliberately leaves the stamp behind
    -- (Trade.PruneExpiredLootStamps owns its lifetime), which is precisely the state a raider is in
    -- when a closed item is caught up. It cannot be told apart from a PREVIOUS roll's stamp under a
    -- reused ID -- nothing is tracked under the ID here, so PurgeStaleRoll has nothing to compare --
    -- and that case is accepted: it is bounded by the four-hour prune and it errs towards a reminder
    -- that ends early, which is the safe direction for a promise about a trade.
    local lootedAt = LC.rollLootedAt and LC.rollLootedAt[rollID]
    LC.HandleStart(payload, senderKey)
    if lootedAt then LC.rollLootedAt[rollID] = lootedAt end
end

-- ==========================================================================
--  B118: the table, said out loud
-- ==========================================================================
--
-- Every message that puts an item on the table or takes it off is sent exactly once, with no
-- acknowledgement and nothing that notices the silence. On 2026-08-03 that cost a raid four separate
-- things in one evening: a raider never learned an item existed and lost it outright, and a council
-- member kept three rounds of cards because End Round never reached him.
--
-- So the loot owner says what is on the table, over and over, while there is anything on it, and a
-- client missing one of those rolls asks for it. One message per change to that table plus one every
-- half-minute, from one client in the raid -- and unlike a retry it also repairs the client that was
-- not even listening when the original went out.
--
-- IT ONLY EVER ADDS. The obvious other half -- "you are holding a card I did not list, drop it" --
-- was designed, written, and taken back out before it ever ran, because it can lose a whole
-- distribution in the case this guild has every raid: the lootmaster ports out mid-round and the raid
-- leader stands in. The stand-in's own table is empty at that moment. One heartbeat from them would
-- have told every council member to drop the items they are voting on, which is C5 and C11 broken by
-- the very mechanism meant to protect them. Deletion has to come from somebody deciding it, never
-- from somebody else's silence -- so End Round repeats its own message instead (see LC.EndRound).
--
-- WHEN it goes out is polled, never pushed. The tick builds the message it WOULD send and sends it
-- only if that differs from the last one, so no call site has to remember to say "the table changed"
-- -- and there is no fourth mutation site for somebody to forget, which is how the hand-maintained
-- list failed three times before this. Two seconds is the resolution a change is noticed at; a string
-- compare that often is nothing next to the messages it saves.
local TABLE_POLL_SECONDS = 2
-- An UNCHANGED table is repeated this often anyway, because the message also has to reach a client
-- that was not listening when the last one went out: a reload, a late invite, a chunk the transport
-- dropped. Thirty seconds is what ROLL_REQ_COOLDOWN below is sized against.
local TABLE_RESEND_SECONDS = 30
-- Enough for any real distribution (a boss drops a handful), and short enough that the message stays
-- far inside the transport's cap. Nothing is inferred from an item's ABSENCE here, so a truncated
-- list costs a slower catch-up for whatever it drops -- and LC.OpenRollIDs sorts ASCENDING, so what
-- it drops is the HIGHEST rollIDs: the newest drops on the table, not "the twelfth item". Whether
-- that is the right end to lose is a separate question from this budget and has not been decided.
--
-- Unchanged when the message started naming items as well (B132), because it still fits: an entry is
-- a rollID, "=" and an itemID, and the widest rollID this addon can produce is six digits
-- (MANUAL_ROLL_ID_BASE + a five-digit remainder), so twelve entries and their commas is 167 bytes,
-- about 180 with the token and the count in front -- inside one 255-byte addon message with room to
-- spare, but not the "about 160" first recorded here. AceComm would split a longer one rather than lose
-- it, but a heartbeat that costs three chunks every time it repeats, for the rest of the evening, is a
-- bad trade for a message whose whole point is to be cheap enough to repeat. That budget is why the item
-- travels as an itemID and never as a link: an itemID is six digits, and the same item's LINK is
-- fifty-plus bytes and differs per drop by its bonus ids, which is exactly the comparison this
-- message must not make (see LC.PayloadItemID).
local TABLE_MAX_IDS = 12
-- A client re-asks for the same missing roll at most this often. What it now throttles is the
-- CHANGE-driven half of the heartbeat, which is where the bursts are: a boss dropping four items puts
-- four different tables on the wire inside a few seconds, and without this a client missing one of
-- them would ask again on every one. Against the forced repeat it throttles nothing any more --
-- TABLE_RESEND_SECONDS is the same thirty seconds -- and that is the rate this was always aiming for:
-- one ask per roll per half-minute, for as long as the answer really is missing.
local ROLL_REQ_COOLDOWN = 30

-- What this client CHOSE to be finished with -- the one thing the repair path cannot work out for
-- itself. "I closed this on purpose" and "I never received this" leave a client in exactly the same
-- state: no item, no deadline, nothing tracked. The catch-up read both as the second one, and once an
-- item stayed askable for as long as it is tracked (LC.RollTracked) rather than only while its timer
-- ran, that mistake reached the ordinary end-of-item gesture -- award, then close the tab -- for a
-- whole distribution. The owner still holds its own tab, so its heartbeat kept naming the roll, this
-- client kept asking for it, and the answer put the tab back on screen every thirty seconds, clearing
-- LC.councilPanelDismissed and un-minimizing the panel with it. That is B123's complaint through a new
-- door. Only the client that closed the thing knows which of the two happened, so it is the one that
-- remembers.
--
-- Set ONLY where a person got rid of a roll on purpose, which is Council.CloseCouncilTab and nothing
-- else: the tab's own "x", the panel's "No Winner", the peer side of somebody else's "No Winner", and
-- a manual re-decision revoking an award. A roll that goes because it EXPIRED
-- (Vote.PruneExpiredRolls), because a reused rollID was purged (PurgeStaleRoll) or because the round
-- ended (LC.ClearAllRolls) is not a dismissal and must never be recorded here -- those are precisely
-- the clients that still have to be repairable.
--
-- Runtime-only, like LC.rollReqSent and LC.rollsAnswerAt beside it and for the same kind of reason:
-- after a reload this client has no panel open and nothing on screen it put away, so a restored note
-- could only ever refuse a repair that should have happened. Deliberately NOT part of
-- Trade.ClearRollState's per-roll state either -- it has to OUTLIVE the roll it names, which is its
-- entire job -- so it is in neither of the two lists tests/test_lc_persistedtables.lua keeps in step,
-- and belongs in neither.
--
-- [rollID] = the itemID that was dismissed, or `true` when this client never resolved what it was
-- holding ("???"). WHAT was put away, not merely that something was: a raider dismisses an ITEM and
-- the rollID is only how it was addressed, and Blizzard hands that number to an unrelated item within
-- seconds on trash (B132). Remembering the number alone left this client refusing the NEXT item under
-- it as well -- deaf to a drop nobody here ever decided about. Everything that reads this compares on
-- truthiness for the gate and on the item for the question "is this still the roll I closed".
LC.rollDismissed = LC.rollDismissed or {}

-- The dismissal is about an item, so any message that names a DIFFERENT item under a dismissed
-- rollID is proof Blizzard reused the number: the roll that was put away no longer exists and the
-- note about it must not gate the new one (B132). Called from the paths that carry both halves --
-- LC.HandleRolls and Trade.HandleResult; a roll START clears the note outright (PurgeStaleRoll), and
-- the catch-up decides for itself because it has to REFUSE the other case rather than just pass it.
--
-- Silent when there is nothing to compare: a payload with no item, or a dismissal of an item this
-- client never resolved, leaves the note exactly as it was.
function LC.ForgetDismissalIfReused(rollID, itemID)
    local dismissed = rollID and LC.rollDismissed[rollID]
    if type(dismissed) == "string" and itemID and itemID ~= "" and dismissed ~= itemID then
        LC.rollDismissed[rollID] = nil
    end
end

local tableTicker
local lastTableWasEmpty = true
-- The message last put on the wire, and when. The tick compares against the STRING it would send, not
-- against a count or a hash of it, so "changed" means exactly "a receiver would read something else".
local lastTablePayload, lastTablePayloadAt = nil, 0

-- Everything still on the table here, by LC.RollTracked's rule — which is where the "why not the
-- deadline" reasoning lives. The name is historical: "open" means still tracked and undecided, not
-- "still inside its voting window".
function LC.OpenRollIDs()
    local ids = {}
    for rollID in pairs(LC.rollDeadlines or {}) do
        if LC.RollTracked(rollID) then
            ids[#ids + 1] = rollID
        end
    end
    table.sort(ids)
    return ids
end

-- The message this client would send right now, and whether the table behind it is empty. Split out
-- from the send so the tick can build it WITHOUT sending, and compare the real thing rather than a
-- stand-in for it: anything cheaper to compare -- the id list, a count -- would miss the case B132
-- added, where the ids are unchanged and an itemID under one of them is not.
local function TablePayload()
    local ids = LC.OpenRollIDs()
    -- "<rollID>=<itemID>", comma-separated, behind the count of what is REALLY on the table (which
    -- can be more than TABLE_MAX_IDS lists). Nothing reads that count -- one thing briefly did, and
    -- LC.HandleTable says at its foot why that reader is gone -- and it stays on the wire because the
    -- FIELD is load-bearing even though its value is not: the receiver splits on "^(%d+):?(.*)$", so
    -- dropping the count would feed it "980=249331,981=..." and it would swallow the first entry
    -- whole, reading 980 as the count and "=249331,981=..." as the list. (The reason first written
    -- here -- "it tells a receiver its list was truncated" -- is inert: no 3.3.1 reader looks at it,
    -- and the 3.3.0 reader's `shown == total` guard can never hold against a doubled list.) It also
    -- keeps the payload's leading field the same shape a 3.3.0 client parses.
    --
    -- "=0" for a roll whose item this client cannot name, which happens: an LC_START that carried no
    -- itemID leaves "???" tracked here (B40). It is still listed, deliberately -- a roll the owner is
    -- vague about is exactly the one a receiver most needs to hear exists -- and the receiver reads it
    -- as "unknown", never as a mismatch.
    local shown = {}
    for i = 1, math.min(#ids, TABLE_MAX_IDS) do
        local rollID = ids[i]
        local link = LC.rollItems[rollID]
        local itemID = type(link) == "string" and link:match("item:(%d+)") or nil
        shown[i] = rollID .. "=" .. (itemID or 0)
    end
    return "LC_TABLE:" .. #ids .. ":" .. table.concat(shown, ","), #ids == 0
end

function LC.SendTableHeartbeat()
    if not (IsInGroup() and LC.sessionActive and LC.IsLootOwner()) then return end
    local payload, isEmpty = TablePayload()
    -- One empty heartbeat after the table clears, then silence. That message is what lets a client
    -- which missed End Round drop its cards; sending it forever would be noise on an idle raid.
    if isEmpty and lastTableWasEmpty then return end
    lastTableWasEmpty = isEmpty
    lastTablePayload, lastTablePayloadAt = payload, GetTime()
    LC.SendLC(payload)
end

-- Started by the loot owner when it announces a roll, and it stops itself once the table has been
-- reported empty. Cheap either way: the send below returns immediately on any client that is not the
-- owner, which is what keeps a role change mid-round from producing two broadcasters.
--
-- The tick asks the question the send would answer -- "is what I would say now different from what I
-- last said?" -- and stays quiet unless it is, or unless the last one is TABLE_RESEND_SECONDS old.
-- The owner check is repeated here rather than left to the send alone because a client that is not
-- the owner must not build a payload it will never put on the wire, and must not have a stale
-- lastTablePayload compared against later.
function LC.EnsureTableTicker()
    if tableTicker then return end
    lastTableWasEmpty = false
    lastTablePayload, lastTablePayloadAt = nil, 0
    tableTicker = C_Timer.NewTicker(TABLE_POLL_SECONDS, function()
        if IsInGroup() and LC.sessionActive and LC.IsLootOwner() then
            local payload = TablePayload()
            if payload ~= lastTablePayload
                or (GetTime() - lastTablePayloadAt) >= TABLE_RESEND_SECONDS then
                LC.SendTableHeartbeat()
            end
        end
        if lastTableWasEmpty and tableTicker then
            tableTicker:Cancel()
            tableTicker = nil
        end
    end)
end

function LC.StopTableTicker()
    if tableTicker then tableTicker:Cancel() end
    tableTicker = nil
    lastTableWasEmpty = true
    lastTablePayload, lastTablePayloadAt = nil, 0
end

-- The receiving half of the heartbeat: ask for what we are missing, and nothing else. Deliberately
-- has no branch that removes anything -- see the comment above the constants for what that branch
-- would cost the first time the loot role moves mid-round.
function LC.HandleTable(payload, senderKey, sender)
    if not LC.IsSenderLootOwner(senderKey) then
        LC.diag.refusedSender = LC.diag.refusedSender + 1
        return
    end
    local _, list = payload:match("^(%d+):?(.*)$")

    -- Asked for one at a time, only from the owner, and at most once every ROLL_REQ_COOLDOWN per
    -- roll -- so the burst of heartbeats a changing table produces cannot become a burst of requests
    -- while an answer is already on its way, and a raid that all missed the same announcement does not
    -- answer itself into another burst.
    LC.rollReqSent = LC.rollReqSent or {}
    local now = GetTime()
    for entry in tostring(list):gmatch("[^,]+") do
        local id, item = entry:match("^(%d+)=?(%d*)$")
        local rollID = tonumber(id)
        -- "the owner cannot name this one either", in both spellings it can arrive in: "=0" from a
        -- 3.3.1 owner holding "???", and a bare id from a 3.3.0 owner, whose heartbeat carried no
        -- items at all. Unknown is not a mismatch -- it says nothing about the item under that
        -- number, so every comparison below is simply skipped and the ask still happens, which is
        -- what makes a mixed-version raid degrade to exactly the old behaviour rather than to a
        -- wrong one.
        local itemID = (item ~= "" and item ~= "0") and item or nil

        -- What the owner says is under that number, against what this client has under it -- held, or
        -- merely remembered as dismissed. A DIFFERENT item is proof Blizzard handed the number on and
        -- this client missed the LC_START that said so (B132), and that is the transition
        -- PurgeStaleRoll already owns: it drops the dismissal note, the previous item's votes, tab and
        -- vote row, and leaves the numbers that were cast for the item now arriving. Called rather
        -- than reimplemented, so there is one answer to "this id belongs to a different item now" and
        -- not two that can drift.
        --
        -- Only ever on a proven difference, and a difference needs a COMPARABLE PAIR on both sides.
        -- Two things follow from that:
        --
        -- * PurgeStaleRoll clears the dismissal unconditionally at its top, which is right for a roll
        --   START and wrong for a heartbeat repeating the item this client deliberately closed -- that
        --   is the tab that must stay closed (B131).
        -- * A held "???" is NOT evidence of a reuse here, and must not purge. PurgeStaleRoll's other
        --   callers are roll starts and re-track the arriving item in the lines right after it
        --   returns, which is the premise its B40 branch states for itself: a new item IS arriving
        --   under this ID. A heartbeat states the opposite -- it is a REPEAT of the same roll -- and
        --   re-tracks nothing, so "we cannot read what we hold" would there mean throwing away this
        --   client's whole card for the item, the raid's votes included, and depending on a round trip
        --   a stand-in can refuse (LC.MayCatchUp wants an LC.rollEligible snapshot only the announcing
        --   client ever takes). The item is named right here instead -- see the repair below.
        --
        -- And what comparing at all costs, so the next reader knows it: this message is now
        -- AUTHORITATIVE about which item a number belongs to. Before B132 no heartbeat could touch a
        -- tracked item or a dismissal note at all -- it could only ever cause an ask. Now an owner
        -- that is ITSELF stale (it missed the LC_START for a reuse and still tracks the previous item)
        -- names the old item, and a client that dismissed or holds the NEW one drops that and asks
        -- again on the strength of it. Narrow and self-limiting -- the answer to that ask is whatever
        -- is really on the table, and both clients agree again on the next heartbeat -- but it is a
        -- new channel for one client's staleness to reach the rest of the raid.
        if rollID and itemID then
            local link = LC.rollItems[rollID]
            local held = type(link) == "string" and link:match("item:(%d+)") or nil
            local dismissed = LC.rollDismissed[rollID]
            if (link ~= nil and held ~= nil and held ~= itemID)
                or (type(dismissed) == "string" and dismissed ~= itemID) then
                -- The ask further down is about a DIFFERENT item than the one that stamped this, so
                -- the previous roll's cooldown must not defer it. PurgeStaleRoll cannot do it: on the
                -- dismissal-only path it returns at "nothing tracked under this ID" long before
                -- Trade.ClearRollState, which is the only other clearer -- and while peers are still
                -- escalating LC_ROLLS_REQ for that number LC.HandleRollsRequest keeps pushing the
                -- stamp forward, so the deferral is not bounded by ROLL_REQ_COOLDOWN either. Clearing
                -- also resets the escalation state below, which is right: nobody has been asked about
                -- THIS item yet, so the owner gets the first question.
                LC.rollReqSent[rollID] = nil
                LC.PurgeStaleRoll(rollID, itemID)
            elseif link ~= nil and held == nil then
                -- We hold something we never managed to identify -- "???" from an LC_START that
                -- carried no itemID either (B40) -- and the owner can name it. Repaired IN PLACE from
                -- the id that just arrived, exactly as Trade.HandleResult rebuilds one at award time:
                -- the full link once the item is cached, the bare item string until then, which still
                -- renders a name and an icon.
                --
                -- Nothing is cleared, deliberately. The votes cast on this card, its council tab, its
                -- vote row and its deadline all belong to this same roll -- the heartbeat has just
                -- confirmed it is still the one on the table -- and they are what a purge would cost.
                -- Votes stamped with the item now match instead of merely being unrefutable
                -- (LC.VoteIsForItem), so the repair only ever sharpens what is already here.
                LC.rollItems[rollID] = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
                -- The rows are the whole point: an unreadable card that stays unreadable on screen is
                -- what this repair exists to end. Same refresh the link resolver does when it wins.
                LC.Vote.RefreshVoteListRows()
                if LC.councilPanel and LC.councilPanel:IsShown() then
                    KART.LC.Council.RefreshCouncilRows()
                    KART.LC.Council.RefreshCouncilTabs()
                end
            end
        end

        -- Two reasons to ask, and the second is new: the item itself is missing, or the item is here
        -- but its roll table never arrived. The table travels as one message for the whole raid, so
        -- losing it costs everybody's numbers at once -- which is exactly why it has to be askable.
        -- Read AFTER the purge above, so a reuse this client just learned about is asked for on the
        -- same heartbeat rather than the next one.
        local needItem  = rollID and not LC.rollItems[rollID]
        local needRolls = rollID and LC.rollItems[rollID] and LC.GetRollsEnabled()
                          and not LC.rolls[rollID]
        -- ...and one reason not to ask at all: a roll this client threw away itself
        -- (LC.rollDismissed). It gates BOTH asks deliberately. Stopping only the item request would
        -- leave this client asking the raid for the numbers of something it wants nothing to do with,
        -- every thirty seconds for the rest of the round -- the same pointless traffic, just with
        -- nothing on screen to notice it by.
        --
        -- A note that survives the purge above is one the heartbeat has just confirmed: the item
        -- under that number is still the item this client closed. So the gate reads on truthiness
        -- alone, and it is no longer the blind reader it used to be (B132).
        if (needItem or needRolls) and not LC.rollDismissed[rollID]
            and (now - (LC.rollReqSent[rollID] or -ROLL_REQ_COOLDOWN)) >= ROLL_REQ_COOLDOWN then
            local askedBefore = LC.rollReqSent[rollID] ~= nil
            LC.rollReqSent[rollID] = now
            if needRolls and askedBefore then
                -- The owner had its turn and the table still is not here -- it may be gone, or it may
                -- be a stand-in who never had the snapshot to vouch for us (B118, B131). The numbers
                -- are not secret: anybody still holding them may hand them over.
                LC.SendLC("LC_ROLLS_REQ:" .. rollID)
            else
                LC.SendLC("LC_ROLL_REQ:" .. rollID, sender)
            end
        end
    end
    -- No sweep over the unlisted ids, deliberately. One stood here and read "the owner no longer
    -- names this number" as "the roll it was about is over, so the note may go" -- which needed
    -- guards against an empty list and a truncated one, and STILL could not see the case it was
    -- guarding against: a stand-in's list is short because it holds only what that client itself
    -- announced, and nothing in the message says so. The rule above needs none of that, because
    -- absence is no longer evidence of anything: a note goes when an item is NAMED under its number
    -- and it is a different one. That covers everything the sweep covered -- a number that leaves the
    -- table and comes back for a new item is named on the very next heartbeat -- and it covers the
    -- reuse the sweep could not, where the number never left the table at all.
end

-- Somebody asking for a roll they are missing. The eligibility rule lives here, on the one client
-- that knows who was in the raid when the item dropped.
function LC.HandleRollRequest(payload, senderKey, sender)
    if not (LC.sessionActive and LC.IsLootOwner()) then return end
    local rollID = tonumber(payload:match("^(%d+)$"))
    if not rollID then return end
    local link = LC.rollItems[rollID]
    local itemID = type(link) == "string" and link:match("item:(%d+)") or nil
    if not itemID or not LC.RollTracked(rollID) then return end
    local deadline = LC.rollDeadlines[rollID]
    -- The rule, and the only place it is decided: somebody who was not in the raid when this was
    -- announced does not get it now. Strictly "yes" -- see LC.SendOpenRolls for why a roll with no
    -- record at all is refused rather than given the benefit of the doubt.
    if LC.MayCatchUp(rollID, senderKey) ~= true then return end
    -- Same 0-means-closed convention as LC.SendOpenRolls; the receiver's half is in LC.HandleStart.
    LC.SendLC("LC_ROLL_CATCHUP:" .. rollID .. ":" .. math.max(0, math.floor(deadline - GetTime()))
        .. ":" .. LC.ItemPayload(link, itemID), sender)
    -- The rolls go with it, whispered to the asker alone. LC.MayCatchUp above has already decided
    -- that this person was standing here when the item dropped, and the same decision governs both
    -- halves of the answer -- there is no state where somebody is entitled to the item but not to
    -- its numbers.
    local rollsMsg = LC.SerializeRollTable(rollID)
    if rollsMsg then LC.SendLC(rollsMsg, sender) end
end

-- A council member (or the raid leader) telling us the session we own is still running, because we
-- reloaded and it is not running for us. Sent only in reply to our own LC_STATE_REQ, and only by
-- someone who believes WE own it — see LC.HandleStateRequest.
--
-- Accepted only by the person the claim is about: it can turn a session on for the loot owner and
-- nothing else. Deliberately one-directional — there is no "resume" that turns a session OFF, since
-- the damage the two directions can do is not remotely symmetric.
function LC.HandleSessionResume(senderKey)
    if LC.sessionActive or not IsInGroup() then return end
    -- The sender has to be someone actually in our group, and the claim has to be about us.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    -- Originally the loot owner and nobody else, because the loot owner is the only client that can
    -- ASSERT the flag. But they are also the only client that could ever LEARN it: LC_ACTIVE is
    -- answered by the owner alone, so when the owner is the unstable part -- gone, just arrived, or
    -- reloading -- a joiner asked and asked and never found out there was a session at all.
    --
    -- Widened to anyone who does not yet know, which keeps the property that matters: this can only
    -- ever turn a session ON. There is deliberately no resume that turns one off, because the damage
    -- the two directions do is not remotely comparable. A client that already KNOWS the state (it
    -- heard the owner) is not talked out of it by a peer's stale claim -- except the loot owner
    -- itself, whose own knowledge after a reload is exactly what is missing.
    if LC.sessionStateKnown and not LC.IsLootOwner() then return end
    -- No council-membership check on the sender, deliberately, and it was tried: the client
    -- receiving this has just reloaded, so its council list is empty and it cannot verify anybody.
    -- The check refused every legitimate resume and would not have caught the case that actually
    -- worries me — a client that MISSED an LC_ACTIVE:0 and still believes a session is running is
    -- as likely to be a council member as anyone. Staleness is the risk here, not authority, and a
    -- membership test does nothing about staleness. The broadcast below is what addresses it.

    LC.sessionActive     = true
    LC.sessionStateKnown = true
    -- Same as LC.HandleActive: learned, not decided.
    LC.sessionStartedByUs = false
    -- Somebody answered, so nothing we are holding back is a guess any more (B69).
    -- The session was never ours to be asked about: it is already running.
    LC.promptedThisSession = true
    LC.HideSessionPrompt()
    -- A reload left LC.raidConfig and LC.CouncilNamesTable empty — including on ourselves, since our
    -- own broadcast is not processed by us. A NAMED lootmaster has to put that back or they come
    -- home to no council list and no vote-button config, which is the silent half-session B33
    -- describes.
    --
    -- Only a named one, though. A raid leader standing in for an absent lootmaster is the loot owner
    -- but NOT the config owner (see LC.IsConfigOwner), and their own Lootmaster field is empty by
    -- definition — broadcasting here would push their settings, usually an empty council list and
    -- rolls off, over the whole raid, unattended, with nothing but "session resumed" on screen.
    if LC.IsMe(LC.ResolveConfigName(KART_Settings and KART_Settings.lcLootmaster)) then
        LC.BroadcastRaidConfig()
    end
    -- Say it back to the raid. We are the only client entitled to assert the session flag, and until
    -- now nothing ever re-asserted it: LC_ACTIVE is sent once, has no acknowledgement and no retry,
    -- so anyone who missed the original was out for the evening. This turns a claim we accepted from
    -- one peer into something the whole raid converges on — and if the claim was stale, everybody
    -- gets a session that is visibly on and can be ended, instead of the owner quietly force-winning
    -- into their bags while nineteen clients have no session at all.
    -- Only the loot owner may assert the flag, and only their assertion is accepted (see
    -- LC.HandleActive). An ordinary raider resumed by a peer has learned something, not become an
    -- authority: it keeps the session for itself and says nothing.
    if LC.IsLootOwner() then LC.SendLC("LC_ACTIVE:1") end
    print("|cff00ff00KART:|r " .. KART.L.LC_SESSION_RESUMED)
end

-- Whispers the sender's current Loot Council raid-wide-authority settings to targetName as a
-- sync request; the receiver decides via a confirm popup whether to apply them (Core.lua
-- CHAT_MSG_ADDON -> LC.HandleSyncRequest). Same 255-byte payload budget and council-list
-- truncation approach as LC.BroadcastRaidConfig above.
function LC.SendSettingsSync(targetName)
    local minQ = KART_Settings.lcMinQuality or 4
    local buttons = KART_Settings.lcButtonLabels or ""
    local rolls = KART_Settings.lcRollsEnabled and "1" or "0"
    -- Full "Name-Realm" text, not realm-stripped — same cross-realm consistency reason as
    -- LC.BroadcastRaidConfig above.
    local lootmaster = KAUtil.TrimString(KART_Settings.lcLootmaster or "")
    local voteSeconds = KART_Settings.lcVoteSeconds or 20
    local council = KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_SYNC_REQUEST:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":" .. voteSeconds .. ":"
    local payload = BuildCouncilPayload(prefix, council)
    if not payload then return end
    KASC:Send(payload, "WHISPER", targetName)
    -- Remember who we asked, so only their reply prints (see LC.HandleSyncAccept/Decline). These two
    -- messages are deliberately not group-gated — the whole feature targets someone outside the
    -- group — which without this would let anyone spam a line into our chat frame at will.
    LC.syncRequestSentTo = KAUtil.CaseFold(KAUtil.TrimString(targetName or ""))
end

function LC.ShowSyncTargetDialog()
    KART.UI:ShowInputDialog({
        title = KART.L.LC_SYNC_TARGET_PROMPT,
        maxLetters = 48,
        emptyMessage = KART.L.LC_SYNC_TARGET_EMPTY,
        okLabel = KART.L.BTN_ACCEPT,
        cancelLabel = KART.L.BTN_CANCEL,
        onAccept = function(text) LC.SendSettingsSync(text) end,
    })
end

-- Runs when a sync-request whisper arrives (Core.lua CHAT_MSG_ADDON -> LC_SYNC_REQUEST:). Shows
-- a confirm popup naming the sender; settings are only applied if the user explicitly accepts.
-- sender is the raw, realm-qualified whisper-reply target; senderShort is for the popup text.
function LC.HandleSyncRequest(payload, sender, senderShort)
    local minQ, buttons, rolls, lootmaster, voteSeconds, council =
        payload:match("^(%d+):([^:]*):([01]):([^:]*):(%d+):(.*)$")
    if not minQ then return end

    StaticPopupDialogs["KART_LC_SYNC_REQUEST"].text = KART.L.LC_SYNC_REQUEST_TEXT
    StaticPopup_Show("KART_LC_SYNC_REQUEST", senderShort, nil, {
        sender = sender,
        minQuality = tonumber(minQ),
        buttonLabels = buttons,
        rollsEnabled = (rolls == "1"),
        lootmaster = lootmaster,
        -- Clamped to the range the slider itself allows (5-180, see SldVoteTimer in
        -- LootCouncilSettings.lua). This is the one inlet that takes a vote length from another
        -- player's whisper, and the field is no longer just a duration: 0 is the control value meaning
        -- "voting on this one is already over" (LC.SendOpenRolls writes it, LC.HandleStart reads it).
        -- A 0 accepted here would be handed on by every LC_START this client later sends, silently
        -- telling the whole raid that every item is closed the moment it drops.
        voteSeconds = math.min(180, math.max(5, tonumber(voteSeconds))),
        councilMembers = council,
    })
end

-- Only the player we actually sent a sync request to may print here (LC.syncRequestSentTo). The
-- target was typed by hand, so it may or may not carry a realm — compare on the short name, which
-- both forms reduce to.
local function IsExpectedSyncReply(senderShort)
    local expected = LC.syncRequestSentTo
    if not expected or not senderShort then return false end
    return KAUtil.CaseFold(expected:match("^([^%-]+)") or expected) == KAUtil.CaseFold(senderShort)
end

function LC.HandleSyncAccept(senderShort)
    if not IsExpectedSyncReply(senderShort) then return end
    LC.syncRequestSentTo = nil
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_SYNC_ACCEPTED_MSG, senderShort))
end

function LC.HandleSyncDecline(senderShort)
    if not IsExpectedSyncReply(senderShort) then return end
    LC.syncRequestSentTo = nil
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_SYNC_DECLINED_MSG, senderShort))
end

KART.UI:RegisterStaticPopup("KART_LC_SYNC_REQUEST", {
    text = "Raidlead-Only Settings Sync from Player %s", -- overwritten with KART.L.LC_SYNC_REQUEST_TEXT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        KART_Settings.lcMinQuality = data.minQuality
        KART_Settings.lcButtonLabels = data.buttonLabels
        KART_Settings.lcRollsEnabled = data.rollsEnabled
        KART_Settings.lcLootmaster = data.lootmaster
        KART_Settings.lcVoteSeconds = data.voteSeconds
        KART_Settings.lcCouncilMembers = data.councilMembers
        KART.SyncSettingsToUI()
        KASC:Send("LC_SYNC_ACCEPT", "WHISPER", data.sender)
    end,
    OnCancel = function(self, data)
        KASC:Send("LC_SYNC_DECLINE", "WHISPER", data.sender)
    end,
})

-- Raised by LC.CheckStandIn when the configured lootmaster has left and we hold raid lead. Accepting
-- is what actually moves ownership (see LC.IsLootOwner) — declining leaves everything as it was.
KART.UI:RegisterStaticPopup("KART_LC_STAND_IN", {
    text = "The lootmaster has left the raid. Take over loot distribution?", -- overwritten with KART.L.LC_STAND_IN_TEXT before every show
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
    -- Only the loot flow moves. Deliberately no config broadcast: the raid's settings still belong to
    -- the absent lootmaster (see LC.IsConfigOwner), and pushing our own over them would erase the very
    -- name that hands the role back when they walk in again.
    OnAccept = function()
        LC.standInAccepted = true
        -- The departed lootmaster's own ticker dies with them -- nobody else ever started one, so
        -- items they announced before the handover would otherwise never be heartbeat again at all,
        -- and a peer could never be prompted to repair a table for one of them (B131). Idempotent:
        -- a no-op if a ticker from an earlier announcement is already running.
        LC.EnsureTableTicker()
        print("|cff00ff00KART:|r " .. KART.L.LC_STAND_IN_ACCEPTED)
    end,
})

LC.IsRealItemLink = KAUtil.IsRealItemLink -- kept as LC.* alias; call sites across the LC modules use this name

-- Pulls the (r,g,b) quality colour for an item link/coloured string. The leading colour escape is
-- tried first (|cAARRGGBB, decoded directly) — this is the only form test mode's fake
-- coloured-string items ever use, so that path alone still covers them. A real item link can
-- instead carry a *named* escape (|cnIQ4:, see KAUtil.EachItemLink) that has no hex triple to
-- decode at all; for that form, the item's actual quality is looked up via C_Item.GetItemInfo
-- instead of trying to parse meaning out of the escape's name. Falls back to grey when neither
-- resolves (a non-item test string, or a real item not yet in the client's item cache).
function LC.ParseItemColor(link)
    if type(link) ~= "string" then return 0.5, 0.5, 0.5 end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex then
        return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
    end
    if KAUtil.IsRealItemLink(link) then
        local _, _, quality = C_Item.GetItemInfo(link)
        local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] ---@diagnostic disable-line: undefined-global
        if c then return c.r, c.g, c.b end
    end
    return 0.5, 0.5, 0.5
end

-- Refresh the council panel after a vote/assignment mutation, but only when it's actually open: the
-- row list only matters for the currently-active tab, while the per-tab vote-count badges stay live
-- on every tab. This exact guard was copy-pasted across the handlers that mutate vote/assignment
-- state. Handlers that only ever touch the active roll's rows, or refresh unconditionally, keep
-- their own narrower guard on purpose.
function LC.RefreshCouncilIfShown(rollID)
    if not (LC.councilPanel and LC.councilPanel:IsShown()) then return end
    if LC.activeRollID == rollID then KART.LC.Council.RefreshCouncilRows() end
    KART.LC.Council.RefreshCouncilTabs()
end

-- Sets an item icon texture: the item's real icon when the link resolves, otherwise a generic
-- question-mark placeholder tinted with the item's quality colour (r,g,b — pass what
-- LC.ParseItemColor returned, which the caller usually also needs for the surrounding border/strip).
function LC.SetItemIcon(icon, link, r, g, b)
    -- GetItemIconByID answers from a plain itemID as well as from a full link, and LC.HandleStart
    -- rebuilds exactly such a string from the LC_START payload for clients that had no roll of their
    -- own. Accepting it here is what makes those rows show the real icon straight away instead of
    -- the question mark they were reported with (#12, #13, #16) — the icon needs only the ID, while
    -- the name has to wait for the item to be cached.
    local lookup = LC.IsRealItemLink(link) and link
        or (type(link) == "string" and link:match("^item:(%d+)"))
    local iconTexture = lookup and C_Item.GetItemIconByID(lookup)
    if iconTexture then
        icon:SetTexture(iconTexture)
        icon:SetVertexColor(1, 1, 1)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetVertexColor(r, g, b)
    end
end

-- Counts how many people have voted on rollID so far, and a rough denominator (current group
-- size, at least 1) for a "voted/total" badge. The denominator is approximate — not everyone in
-- the group necessarily has KART or is eligible — but good enough for an at-a-glance indicator.
function LC.CountVotes(rollID)
    local voted = 0
    -- Votes cast for a DIFFERENT item under this same reused rollID are not this item's votes, so
    -- they must not inflate the "x of y have answered" badge either (B46).
    for _, v in pairs(LC.votes[rollID] or {}) do
        if LC.VoteIsForItem(v, rollID) then voted = voted + 1 end
    end
    return voted, math.max(GetNumGroupMembers(), 1)
end

-- Colored label for an item quality index (0=Poor .. 5=Legendary), used by the min-quality filter UI.
function LC.QualityLabel(q)
    local name = (KART.L and KART.L["LC_QUALITY_" .. q]) or tostring(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] ---@diagnostic disable-line: undefined-global
    if c then
        return c.hex .. name .. "|r"
    end
    return name
end

-- Localized label for the "voted item display" button (KART_Settings.lcVotedItemDisplay) —
-- mirrors LC.QualityLabel's lookup pattern, just without quality-color coding (there's no
-- natural color axis for full/shrink/hide the way there is for item quality).
function LC.VotedItemDisplayLabel(mode)
    return (KART.L and KART.L["LC_VOTED_DISPLAY_" .. (mode or "full"):upper()]) or mode or "full"
end

-- =====================================================================
--  Session Prompt  (shown to RL when joining a raid)
-- =====================================================================

-- Takes the prompt off screen whenever a session starts, from wherever. The frame is created once
-- and reused, and only its own two buttons and Escape ever hid it — so it could sit there through a
-- whole round waiting to be clicked by someone tidying their screen. The button handlers re-check
-- their own preconditions anyway; this just stops the stale dialog being there in the first place.
function LC.HideSessionPrompt()
    if LC.sessionPromptFrame then LC.sessionPromptFrame:Hide() end
end

function LC.ShowSessionPrompt()
    -- Asking whether to start a session that is already running is never right, and the caller's
    -- own check happens up to three seconds before this runs.
    if LC.sessionActive or not LC.IsLootOwner() then return end
    LC.sessionPromptAnswered = false
    if LC.sessionPromptFrame then
        LC.sessionPromptFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "KART_LCSessionPrompt", UIParent, "BackdropTemplate")
    f:SetSize(310, 115)
    f:SetPoint("CENTER", 0, 120)
    LC.RegisterWindow(f, true)
    KART.UI:ApplyPopupArtwork(f)
    KART.RegisterEscapeFrame(f)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText(KART.L.LC_PROMPT_TITLE)

    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.desc:SetPoint("TOP", 0, -36)
    f.desc:SetText(KART.L.LC_PROMPT_TEXT)
    f.desc:SetWidth(285)
    f.desc:SetWordWrap(true)

    local btnYes = KART.UI:CreateModernButton(f, KART.L.LC_PROMPT_YES)
    btnYes:SetSize(135, 28)
    btnYes:SetPoint("BOTTOMLEFT", 15, 12)
    btnYes:SetScript("OnClick", function()
        LC.sessionPromptAnswered = true
        LC.SetSessionActive(true)
        f:Hide()
    end)

    local btnNo = KART.UI:CreateModernButton(f, KART.L.LC_PROMPT_NO)
    btnNo:SetSize(135, 28)
    btnNo:SetPoint("BOTTOMRIGHT", -15, 12)
    btnNo:SetScript("OnClick", function()
        -- Re-checked HERE, not just where the prompt is opened. This frame is created once and
        -- reused; nothing but these two buttons and Escape ever closes it, so a dialog left sitting
        -- on screen can be clicked long after the state that justified it has gone. Without this
        -- check, tidying away a forgotten prompt ran SetSessionActive(false) in the middle of a
        -- running round -- locally wiping tabs, votes and winner highlights, and broadcasting
        -- LC_ACTIVE:0 to a raid that was mid-boss.
        --
        -- Declining still broadcasts when it genuinely applies, and that is deliberate: it is what
        -- resolves the split where the raid believes a session runs and this client does not. Not
        -- the only way out -- "Yes" resolves it too, and non-destructively -- but the honest answer
        -- for someone who does not want a session at all.
        LC.sessionPromptAnswered = true
        if LC.IsLootOwner() and not LC.sessionActive then
            LC.SetSessionActive(false)
        end
        f:Hide()
    end)

    -- Escape closes anything registered in UISpecialFrames, and it runs NEITHER button handler. The
    -- "already asked" latch is set before this prompt is even scheduled (see LC.CheckRaidJoin), so
    -- dismissing it that way used to mean no session for the rest of the evening and no second
    -- question — the loot owner force-winning nothing while every Auto-Pass raider passed. Pressing
    -- Escape to clear the screen before a pull is not an answer; put the question back.
    f:SetScript("OnHide", function()
        if LC.sessionActive or LC.sessionPromptAnswered then return end
        LC.promptedThisSession = false
    end)

    LC.sessionPromptFrame = f

    -- Same reasoning as Council.CreateCouncilPanel (see B2 in BACKLOG.md): btnYes/btnNo just
    -- registered above with KART.UI, but this prompt is built lazily on first login-time trigger,
    -- after the last KART.UpdateStyles() call already ran. Re-apply once so they pick up the
    -- chosen font instead of keeping their Blizzard-default creation-time one. One-shot is enough
    -- here too — nothing else ever registers with this frame after this point.
    if KART.UpdateStyles then KART.UpdateStyles() end
end

-- Forgets every tracked roll and closes both LC windows. Shared by the leader ending the session
-- (SetSessionActive) and a peer receiving LC_ACTIVE:0, so both sides converge to a clean slate
-- instead of the peer keeping stale tabs/votes/showall state around.
function LC.ClearAllRolls()
    -- The batch still waiting out its collection window goes with them. Nothing else cancels it, so
    -- End Round, a session ending and an LC_ACTIVE:0 all used to leave the timer armed and announce,
    -- half a second later, items this client has just stopped tracking: every peer opens a card for a
    -- roll the owner no longer has, and since the owner's heartbeat never names it, that card sits
    -- there until its vote window runs out. The timer itself is left to fire and find nothing (see
    -- FlushPendingDrop), which is cheaper than carrying a handle around for it.
    LC.pendingDrop = nil
    for i = #LC.councilTabs, 1, -1 do
        LC.Trade.ClearRollState(LC.councilTabs[i])
    end
    for i = #LC.voteListRolls, 1, -1 do
        LC.Trade.ClearRollState(LC.voteListRolls[i])
    end
    wipe(LC.councilTabs)
    wipe(LC.voteListRolls)
    -- Sweep per-roll state that the two lists above can't reach. Two ways it gets orphaned:
    -- LC.HandleRolls deliberately accepts a table for a not-yet-known rollID (see the comment there),
    -- and Trade.HandleResult drops a decided roll from the vote list without calling ClearRollState.
    --
    -- This MUST cover the same tables as Trade.ClearRollState — keep the two in sync. Wiping only
    -- some of them is worse than wiping none: PurgeStaleRoll detects a reused rollID by looking at
    -- LC.rollItems, so clearing that while leaving votedByMe/assignedWinners behind blinds the
    -- detector and lets the leftovers attach themselves to whatever item Blizzard next hands that
    -- same rollID — showing a stale "you voted" badge that hides the vote buttons, and a stale gold
    -- winner highlight on the council panel.
    --
    -- LC.rollLootedAt is the one deliberate exception, and nothing below touches it: it is the BoP
    -- trade-timeout clock for entries in LC.pendingTrades/LC.owedToMe, which are long-lived
    -- obligations that intentionally survive a session end. It outlives roll tracking on purpose and
    -- is bounded by age instead — see Trade.PruneExpiredLootStamps, which the ClearRollState loops
    -- above already ran.
    wipe(LC.votes)
    wipe(LC.rolls)
    wipe(LC.rollsFor)
    wipe(LC.councilVotes)
    wipe(LC.rollItems)
    wipe(LC.rollDeadlines)
    wipe(LC.rollDurations)
    wipe(LC.assignedWinners)
    wipe(LC.assignedDeliberate)
    wipe(LC.votedByMe)
    wipe(LC.votedFpByMe)
    wipe(LC.relevanceHandled)
    wipe(LC.hiddenIrrelevant)
    wipe(LC.autoVotedByMe)
    -- Wiped here even though Trade.ClearRollState deliberately leaves it alone per roll (see the
    -- comment there): a session ending ends every roll at once, so nothing it still holds can be live.
    wipe(LC.relevanceSnapshot)
    wipe(LC.votedNoteByMe)
    wipe(LC.councilTabsNew)
    wipe(LC.rollNotInOurBags)
    wipe(LC.rollAnnounced)
    wipe(LC.rollAnnouncedBy)
    wipe(LC.rollSeenHere)
    -- Keyed by encounter and loot list rather than by rollID, so it is not one of the per-roll tables
    -- ClearRollState walks -- but a session ending ends every drop it could still be about.
    if LC.lostRollReported then wipe(LC.lostRollReported) end
    if LC.equipRequestedRolls then wipe(LC.equipRequestedRolls) end
    if LC.rollsPendingSince then wipe(LC.rollsPendingSince) end
    if LC.pendingItemLoads then wipe(LC.pendingItemLoads) end
    if LC.rollEligible then wipe(LC.rollEligible) end
    if LC.rollReqSent then wipe(LC.rollReqSent) end
    -- Same block, same convention as everything above it -- and it was missing. A planned LC_ROLLS_REQ
    -- answer surviving an End Round makes this client refuse a genuine request for a rollID Blizzard
    -- has since reused, because LC.HandleRollsRequest reads a leftover stamp as "we are already about
    -- to answer that".
    if LC.rollsAnswerAt then wipe(LC.rollsAnswerAt) end
    -- Same block, same convention. The round is over for the whole raid, so there is nothing left for
    -- this client to be refusing to ask about -- and a flag kept past that would silence the repair
    -- for whatever rollID Blizzard hands out next (LC.rollDismissed).
    if LC.rollDismissed then wipe(LC.rollDismissed) end
    -- Nothing left on the table, so nothing left to say about it (B118). The ticker also stops itself
    -- after one empty heartbeat; this is the direct route for the case that skips that -- a session
    -- ending, or the round being cleared from under it.
    if LC.StopTableTicker then LC.StopTableTicker() end
    LC.showAllOverride = nil
    LC.activeRollID = nil
    if LC.councilPanel then LC.councilPanel:Hide() end
    if LC.voteListFrame then LC.voteListFrame:Hide() end
end

-- ==========================================================================
--  The tracked rolls survive a reload (B81)
-- ==========================================================================
--
-- Everything above this point is runtime state, and a /reload throws all of it away. Measured on
-- 2026-08-01, one drop and one client reloading:
--
--   * the LOOT OWNER is answered by nobody. LC.SendOpenRolls opens with `LC.IsLootOwner()` and says
--     so -- "only from the loot owner" -- which is the right rule for ANNOUNCING an item and the
--     wrong one for a REPLY, because the client that most needs the reply is the loot owner coming
--     back. Reported from the live test: two items added, reload, `/kart lc` opens nothing while
--     `/kart status` correctly reports the session running.
--   * everyone else loses the item outright once the vote timer has run out, since the catch-up only
--     lists rolls with `deadline > now`. That is most of a distribution: the vote window is twenty
--     seconds and the council takes as long as it takes.
--   * the one client that did recover a row got it back with an EMPTY tally -- votes were never part
--     of the catch-up.
--   * a `/kart add` item can never come back that way even in principle. LC.HandleRollCatchup proves
--     entitlement by asking Blizzard for the roll, and a manual item has no Blizzard roll at all.
--
-- So it is not fixed by messages. Each client keeps its OWN tracked rolls in SavedVariables and
-- picks them back up at load: no protocol change, no question of which peer to believe, no rule to
-- rewrite about late arrivals -- a client can only ever restore what it already had -- and the
-- manual half comes along for free. Same shape as KART_LCTrades, which already carries the trade
-- obligations and the BoP clock across a reload (B34).
--
-- Two bounds decide whether a snapshot is still the one this raid is in the middle of. Neither is
-- about the data being valid; both are about it being CURRENT:
--   * the session it belonged to must not have been ended. Ending a session is how the raid says "we
--     are done", and a reload must not undo that;
--   * age, in wall clock, because that is the clock that survives a logout (the same reasoning as
--     the BoP trade stamp). An hour covers a distribution that drags; a raid the next evening starts
--     clean without anybody having to remember to.
local SESSION_RESTORE_MAX = 60 * 60

-- How long the restored items wait for the raid to confirm the session before giving up on
-- themselves. See the end of LC.RestoreSessionSnapshot for what it is protecting against.
local RESTORE_CONFIRM_SECONDS = 60

-- The per-roll tables worth carrying across. This is Trade.ClearRollState's list -- the addon's own
-- definition of "everything tracked under a rollID" -- minus two that are persisted elsewhere and
-- three that must NOT come back:
--   * LC.rollDeadlines -- stored separately below, converted to wall clock;
--   * LC.rollLootedAt -- already persisted, by KART_LCTrades.
--   * LC.equipRequestedRolls, LC.rollsPendingSince, LC.pendingItemLoads -- in-flight markers, not
--     state. Nothing is in flight after a reload, and restoring "we already asked" would stop the
--     question being asked again: the equipped column would stay empty for the rest of the session.
-- (LC.relevanceSnapshot is not in ClearRollState at all -- it is swept on its own schedule -- and is
-- deliberately not carried either: it is Blizzard's live verdict, meaningless once the client
-- restarts, which is the whole reason it gets snapshotted in the first place.)
--
-- Add to ClearRollState and this list wants the same entry -- held by
-- tests/test_lc_persistedtables.lua, which reads both lists out of the source and compares them, so
-- a new table has to be decided about rather than forgotten. The values are numbers, strings,
-- booleans and one flat table of those (LC.votes), all of which SavedVariables round-trips.
local PERSISTED_ROLL_TABLES = {
    "votes", "rolls", "rollsFor", "councilVotes", "rollItems", "rollDurations",
    "assignedWinners", "assignedDeliberate", "votedByMe", "votedFpByMe", "votedNoteByMe",
    "rollNotInOurBags", "rollAnnounced", "rollAnnouncedBy", "rollSeenHere", "relevanceHandled",
    "hiddenIrrelevant", "autoVotedByMe", "councilTabsNew",
    -- Owner-side, and load-bearing across a reload: without it a lootmaster who reloads mid-round can
    -- no longer tell who was in the raid when each item dropped, and refuses every catch-up for the
    -- items still on the table (B118).
    "rollEligible",
}

-- Called from PLAYER_LOGOUT, which the client raises for /reload, a logout and a quit alike -- so
-- one write site covers every ordinary way a session is interrupted. A crash or a pulled cable is
-- not covered, and cannot be: nothing runs then.
function LC.SaveSessionSnapshot()
    KART_LCSession = KART_LCSession or {}
    local store = KART_LCSession
    -- Wiped first, unconditionally: a snapshot must never outlive the moment it describes, and every
    -- early return below means "there is nothing to come back to".
    wipe(store)

    -- Deliberately NOT gated on LC.sessionActive. Ending a session already clears every tracked roll
    -- (LC.SetSessionActive and LC.HandleActive both call LC.ClearAllRolls), so the empty check below
    -- says the same thing -- while the flag says something else as well, and getting it wrong costs
    -- the item: a client that has just restored a snapshot holds the rolls with the flag still off,
    -- because whether the raid is in a session is the raid's answer and arrives on the next roster
    -- change. Reloading twice in that window would have thrown away exactly what the first reload
    -- had just rescued.
    --
    -- What is on screen is what there is to lose. Anything tracked but on neither list is state the
    -- client could not show the player anyway.
    local ids, seen = {}, {}
    for _, list in ipairs({ LC.councilTabs, LC.voteListRolls }) do
        for _, id in ipairs(list) do
            if not seen[id] and not LC.IsTestRoll(id) then seen[id] = true ids[#ids + 1] = id end
        end
    end
    if #ids == 0 then return end

    store.savedAt      = time()
    -- Which tab the panel was on. Without it a council member comes back to a panel full of tabs
    -- and no rows, because every row list is drawn for LC.activeRollID.
    store.activeRollID = (LC.activeRollID and seen[LC.activeRollID]) and LC.activeRollID or nil
    store.councilTabs  = {}
    store.voteListRolls = {}
    for _, id in ipairs(LC.councilTabs) do
        if seen[id] then table.insert(store.councilTabs, id) end
    end
    for _, id in ipairs(LC.voteListRolls) do
        if seen[id] then table.insert(store.voteListRolls, id) end
    end

    -- Deadlines in WALL clock. LC.rollDeadlines is GetTime()-based, and GetTime() counts from when
    -- the client process started -- it survives a /reload and does not survive a logout, which is
    -- exactly the difference that would put a twenty-second timer hours into the future.
    store.expiresAt = {}
    local now = GetTime()
    for _, id in ipairs(ids) do
        local deadline = LC.rollDeadlines[id]
        if deadline then store.expiresAt[tostring(id)] = time() + (deadline - now) end
    end

    store.tables = {}
    for _, name in ipairs(PERSISTED_ROLL_TABLES) do
        local src, out = LC[name], {}
        if src then
            -- rollIDs are stringified on the way out: a SavedVariables file is Lua source, and a
            -- table with numeric keys round-trips as an array with holes. Read back with tonumber.
            for _, id in ipairs(ids) do
                if src[id] ~= nil then out[tostring(id)] = src[id] end
            end
        end
        store.tables[name] = out
    end
end

-- Called from ADDON_LOADED, in the same place and for the same reason as
-- Trade.RestorePersistedTrades.
function LC.RestoreSessionSnapshot()
    local store = KART_LCSession
    if type(store) ~= "table" or type(store.savedAt) ~= "number" then return end
    if (time() - store.savedAt) >= SESSION_RESTORE_MAX then wipe(store) return end
    if type(store.tables) ~= "table" then wipe(store) return end

    local now = GetTime()
    for _, name in ipairs(PERSISTED_ROLL_TABLES) do
        local saved = store.tables[name]
        if type(saved) == "table" and LC[name] then
            for key, value in pairs(saved) do
                local id = tonumber(key)
                if id then LC[name][id] = value end
            end
        end
    end
    for key, expiresAt in pairs(type(store.expiresAt) == "table" and store.expiresAt or {}) do
        local id = tonumber(key)
        -- A deadline already past is restored as past rather than dropped: the roll then expires on
        -- the first sweep, which is what would have happened had the client never restarted.
        if id and type(expiresAt) == "number" then
            LC.rollDeadlines[id] = now + (expiresAt - time())
        end
    end
    for _, id in ipairs(type(store.councilTabs) == "table" and store.councilTabs or {}) do
        if tonumber(id) then table.insert(LC.councilTabs, tonumber(id)) end
    end
    for _, id in ipairs(type(store.voteListRolls) == "table" and store.voteListRolls or {}) do
        if tonumber(id) then table.insert(LC.voteListRolls, tonumber(id)) end
    end
    -- Only if it is one of the tabs that actually came back, so a malformed file cannot point the
    -- panel at a roll it has no rows for.
    for _, id in ipairs(LC.councilTabs) do
        if id == tonumber(store.activeRollID) then LC.activeRollID = id break end
    end
    if not LC.activeRollID then LC.activeRollID = LC.councilTabs[1] end
    -- The rolls are back but the session flag is NOT set here: whether the raid is still in a session
    -- is the raid's answer, not ours, and the existing recovery already asks for it (LC_STATE_REQ ->
    -- LC_ACTIVE / LC_SESSION_RESUME). If the answer comes back "no", LC.ClearAllRolls removes exactly
    -- what was just restored, which is the correct outcome and needs no special case.
    if #LC.voteListRolls > 0 then LC.Vote.EnsurePruneTicker() end
    -- And the vote heartbeat, for the same reason and with the same lifetime. LC.votes came back with
    -- the rolls, so this client may hold an answer the council is still missing -- and Vote.CastVote
    -- is the ONLY other place that arms this ticker, so a vote cast before the reload would never be
    -- repeated again. Armed on the rolls rather than on the votes: at ADDON_LOADED UnitGUID("player")
    -- is not necessarily there yet, so "do I hold a vote" cannot honestly be asked here. A client
    -- that turns out to hold none simply sends nothing and the ticker stops with the rolls.
    LC.Vote.EnsureVoteHeartbeat()
    -- A snapshot carries whatever LC.rollItems held, which for a client that had not cached the item
    -- yet is a bare "item:12345" string. Nothing else would ever look at that roll again.
    if LC.ResolveTrackedItemLinks then LC.ResolveTrackedItemLinks() end

    -- If no answer comes at all, the items are last night's. That is the ordinary shape of logging
    -- back in shortly after a raid -- inside the age bound, but with nobody left to ask -- and
    -- leaving them would put a stale tab in tonight's council panel, which is a failure this addon
    -- has already paid for once ("stale tabs after next boss"). The wait is generous on purpose: a
    -- reloaded loot owner is the SLOWEST client to hear back, because their session has to be handed
    -- to them by a peer rather than simply confirmed (LC_SESSION_RESUME), and it is measured in tens
    -- of seconds, not tens of minutes.
    C_Timer.After(RESTORE_CONFIRM_SECONDS, function()
        if LC.sessionActive then return end
        LC.ClearAllRolls()
    end)
end

-- ==========================================================================
--  B62: a raider on an older release cannot take part, and says nothing about it
-- ==========================================================================
--
-- LC_SESSION_RESUME, LC_CONFIG_RELAY and LC_ROLL_CATCHUP are new tokens, and an older client drops
-- an unknown token without a word. Worse since the ownership rework (docs/OWNERSHIP.md): an older
-- client still derives config ownership from "does my own Lootmaster field name me?", so it rejects
-- the raid leader's config outright and runs the whole evening on its own vote buttons, minimum
-- quality and roll setting -- with nothing printed on either side.
--
-- Nothing here can repair that -- the broken half is running code we cannot change. What it can do
-- is stop it being a mystery: name the raiders concerned, on the one screen that can act on it,
-- before the first boss rather than during it.
LC.PROTOCOL_VERSION = "3.3.1" -- release whose loot-council wire protocol this client requires of peers
LC.outdatedWarned = LC.outdatedWarned or {} -- short name -> true, so a raid is named once, not per hello

-- Group members whose KART is older than the protocol above, sorted. Skipped on purpose:
--   * ourselves -- we never process our own version broadcast, so PlayerVersions has no entry
--   * a member with no entry at all -- either no KART or simply no hello yet, both of which the
--     council panel already marks per row and neither of which this warning can tell apart
--   * a member whose Loot Council module is off -- their client neither sends nor rejects anything,
--     so their version cannot break the flow for anybody
function LC.OutdatedRaiders()
    local out = {}
    if not IsInGroup() then return out end
    for unit in KAUtil.EachGroupUnit() do
        local fullName = UnitName(unit)
        if fullName and not UnitIsUnit(unit, "player") then
            local short = fullName:match("([^%-]+)")
            local ver = short and KART.PlayerVersions and KART.PlayerVersions[short]
            local lcOn = not (KART.PlayerLCEnabled and KART.PlayerLCEnabled[short] == false)
            if ver and lcOn and KART.IsOlderVersion(ver, LC.PROTOCOL_VERSION) then
                out[#out + 1] = short
            end
        end
    end
    table.sort(out)
    return out
end

-- Called when a session starts and again whenever a peer's version arrives (Core.lua's KASC:OnPeer
-- handler) -- versions land asynchronously after a roster change, so the join itself is too early to
-- ask. Only the loot owner is told: everyone else would be reading a warning they cannot act on.
function LC.WarnOutdatedRaiders()
    if not LC.IsLootOwner() then return end
    local fresh = {}
    for _, short in ipairs(LC.OutdatedRaiders()) do
        if not LC.outdatedWarned[short] then
            LC.outdatedWarned[short] = true
            fresh[#fresh + 1] = short
        end
    end
    if #fresh == 0 then return end
    print("|cffff0000KART:|r " .. string.format(KART.L.LC_OUTDATED_PEERS,
        LC.PROTOCOL_VERSION, table.concat(fresh, ", ")))
end

function LC.SetSessionActive(active)
    LC.sessionActive = active
    -- We decided it, so our flag is now an answer and may be quoted to peers (see LC.sessionStateKnown).
    LC.sessionStateKnown = true
    -- And we decided it, which is what entitles a raid leader with an empty Lootmaster field to
    -- distribute their own settings as the raid's (see LC.IsConfigOwner).
    LC.sessionStartedByUs = active and true or false

    if active then
        LC.HideSessionPrompt()
        -- Before the first item, while there is still time to tell them to update (B62).
        LC.WarnOutdatedRaiders()
        -- Anything Blizzard already put a roll window up for, before we knew we were in a session.
        LC.ReplaySeenWhileUnaware()
    end
    -- CONFIG BEFORE LC_ACTIVE, and this order matters. A peer validates LC_ACTIVE with
    -- LC.IsSenderLootOwner, which needs to already know who the lootmaster is; a client that has
    -- never received a config has lootmaster == "" and falls back to "is the sender the raid
    -- leader?". For a lootmaster who ISN'T the leader that fallback says no, so the very first
    -- LC_ACTIVE:1 of the raid — the one that starts the session — was rejected by everyone, and
    -- nothing ever re-sent it. Addon messages arrive in send order, so shipping the config first
    -- means the lootmaster is known by the time LC_ACTIVE is evaluated.
    if active then
        LC.BroadcastRaidConfig()
        -- BroadcastRaidConfig sends nothing unless IsConfigOwner() is true, and that reads OUR OWN
        -- Lootmaster field and requires it to resolve to us. Leave that field empty -- a documented,
        -- supported setup, since the raid leader stands in as loot owner -- and nobody owns the
        -- config, so no client ever receives one. Every raider then falls back to their own local
        -- values for settings that are supposed to be raid-wide: their own vote-button labels, their
        -- own minimum quality, and their own roll setting, which defaults to off. That is a whole
        -- raid silently not rolling while the person who started the session does, and it cost this
        -- guild an evening before anyone worked out why (backlog B33; the real fix is the ownership
        -- design, this is only the missing sentence). Say it out loud instead.
        -- Who is starting the session decides what is worth saying, and under the ownership rule
        -- (docs/OWNERSHIP.md) that is one of exactly two people: the raid leader, who owns the
        -- config, or the person they designated, who owns the loot flow.
        --
        -- Trimmed, because ResolveConfigName trims too: a field holding only spaces is empty as far
        -- as the designation is concerned and must be reported that way.
        local field = KAUtil.TrimString(KART_Settings.lcLootmaster or "")
        if LC.IsConfigOwner() then
            if field == "" then
                -- We hand out the loot ourselves. Supported, and worth one line: whoever is promoted
                -- next inherits that, and the raid switches to their settings with it.
                print("|cffff0000KART:|r " .. KART.L.LC_LOOTMASTER_EMPTY_WARN)
            -- IsResolvedKey, not merely non-nil: KASC.Identity.ResolvePlayer does not return nil for
            -- a name it cannot place, it returns a PENDING TEXT key -- "Akuri" comes back as "akuri".
            -- That is truthy, so a plain nil check reads an unplaceable name as placed and says
            -- nothing, which is the exact shape B59 was filed for.
            elseif not KASC.Identity.IsResolvedKey(LC.ResolveConfigName(field) or "") then
                -- B59's residue, and the last place it could still hide. We typed a name and our own
                -- client cannot place it -- so the designation does not take, and LC.GetLootmaster
                -- falls back to us. Handing out the loot ourselves is the safe outcome, but it is NOT
                -- what was asked for, and the only trace used to be a label in a settings tab nobody
                -- opens. Ours is the client that can fix it, and this is the moment we are looking.
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_LOOTMASTER_UNRESOLVED, field))
            end
        elseif next(LC.raidConfig) == nil then
            -- The designated lootmaster, starting the session without ever having received a config.
            -- Their own Lootmaster field is not consulted any more, so saying anything about it would
            -- be noise -- what matters is that the raid leader's settings have not arrived, which
            -- leaves every raider on their own vote buttons and roll setting.
            print("|cffff0000KART:|r " .. KART.L.LC_NO_CONFIG_YET)
        end
    end
    LC.SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if not active then
        -- Ending the session forgets every tracked roll so the next boss starts clean instead of
        -- showing leftover tabs/votes from this one (see LC.ClearAllRolls / LC.Trade.ClearRollState).
        LC.ClearAllRolls()
        -- A pending B12 retry (see LC.RetryPendingConfig) belongs to the session that's ending.
        LC.CancelPendingConfig()
    end
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end

-- Ends the CURRENT distribution only — clears every tracked roll/tab/vote/winner-highlight on
-- every client (see LC.ClearAllRolls) but leaves LC.sessionActive untouched. This is what the
-- council panel's "End Round" button does; turning the whole session off is what
-- LC.SetSessionActive is for (the settings-tab toggle, and the leave-raid path in
-- LC.CheckRaidJoin). Mirrors LC.SetSessionActive's broadcast-then-clear shape, minus the LC_ACTIVE
-- flip and the config re-broadcast, since neither the session flag nor the config changes here.
-- Sent more than once, on purpose (B118). This is the message a council member did not get on
-- 2026-08-03: his cards from the previous round stayed, the next /kart add put the same items on top
-- of them, and his panel finished the evening showing three rounds at once.
--
-- Repetition rather than an acknowledgement, and rather than peers inferring the end from a heartbeat
-- that stops listing an item: receiving this twice does exactly what receiving it once does
-- (LC.ClearAllRolls is idempotent), while inferring deletion from somebody else's silence can wipe a
-- live distribution the moment the loot role moves. Three copies over five seconds is two more
-- chances at a message that costs a raid an evening when it goes missing.
local END_ROUND_REPEATS = { 2, 5 }

function LC.EndRound()
    LC.SendLC("LC_END_ROUND")
    for _, delay in ipairs(END_ROUND_REPEATS) do
        C_Timer.After(delay, function()
            -- The round has restarted -- an item dropped inside those five seconds -- so the repeat
            -- is no longer about anything that is still true. Sending it would clear the NEW item off
            -- every peer while the sender, which already ran its own ClearAllRolls once, keeps it:
            -- half a raid voting on something the other half cannot see. Found by the convergence
            -- soak at seed 93, on the first run after this repeat was added.
            if next(LC.rollItems) ~= nil then return end
            -- Only while we still have the standing to say it: the role can move in those five
            -- seconds, and a message the raid would now reject is not worth sending. Council rather
            -- than loot owner, matching exactly who the receiving side accepts this from (B57).
            if LC.IsCouncil() then LC.SendLC("LC_END_ROUND") end
        end)
    end
    LC.ClearAllRolls()
end

-- Deliberately the BARE IsInRaid(), which reports only the HOME party category.
--
-- This briefly asked both categories, on the theory that a group-finder raid reads as "no raid". The
-- theory was never verified, and widening it here alone opened something much worse: everything that
-- actually moves data still asks the bare form -- LC.SendLC's IsInGroup guard, KASC:DefaultChannel,
-- and KAUtil.EachGroupUnit, which decides the roster scan is solo and yields only "player". So the
-- widened gate let a session start in a group where no message could leave and no sender could be
-- resolved: "session on", nothing broadcast, the loot owner force-winning every drop with no council
-- and no vote windows anywhere. Refusing to start, which is what 3.2.1 did, is far better.
--
-- If the group-finder case ever turns out to be real, the transport goes first and this follows --
-- see "Voraussetzung, separat auszuliefern" in the ownership design doc.
local function InAnyRaid()
    return IsInRaid()
end

-- How long to wait before believing a negative raid check. A real raid exit is delayed by this and
-- nothing else happens in between; a blip costs the session everything, so the trade is one-sided.
local RAID_EXIT_CONFIRM_DELAY = 3

-- Seconds between attempts to find out whether a session is running. Bounded and backing off: a raid
-- where nobody can answer must not have twenty clients asking forever.
-- The first retry comes quickly on purpose. Everything between losing the state and getting it back
-- is time this client spends believing there is no session -- and for the LOOTMASTER that is not a
-- cosmetic gap: LC.OnStartLootRoll returns early, so a boss dying in that window is force-won by
-- nobody and the item leaves on a normal roll. One request can be lost (Blizzard's chat throttle
-- drops the overflow silently), so the interval that matters is the one before the second attempt.
-- It stays a backoff after that: a raid where nobody can answer must not have twenty clients asking
-- forever.
local STATE_REQ_BACKOFF = { 2, 5, 15, 45 }

-- Asks the raid for the session state, and keeps asking until we actually learn it.
--
-- One request used to be the whole strategy, latched by LC.stateSyncRequested and never re-armed
-- inside a raid. That was survivable only as long as the answer always arrived — and it does not.
-- LC_CONFIG carries a twelve-attempt retry; the LC_ACTIVE that travels with it carries none, and
-- both are rejected by the same condition (a sender this client cannot resolve yet, normal while a
-- raid is still forming). So the config would land on the retry and the session flag would not, and
-- nothing would ever ask again.
--
-- That client then holds a perfect config with sessionActive false. LC.HandleStart has no session
-- gate, so it still shows vote windows and everything LOOKS right — while LC.OnStartLootRoll returns
-- early, so it never auto-passes and rolls Need in Blizzard's window against the lootmaster's forced
-- win. An item can leave the loot flow entirely and the only visible trace is a dash in one column.
-- True while a retry chain is still scheduled, so a roster change starts a new one instead of
-- stacking a second on top of a live one. NOT a "we already asked once" latch: that is what
-- LC.stateSyncRequested used to be, and it never came back off — see LC.CheckRaidJoin.
local stateReqInFlight = false

-- What a state request is still FOR. Two things travel in every reply and only one of them used to
-- gate the asking: a client that learned the session flag and missed the config stopped asking, and
-- spent the evening on its own vote buttons with no way to notice. A running session with no config
-- at all is an anomaly by construction -- the config goes out before the flag, from
-- LC.SetSessionActive and from every reply in LC.HandleStateRequest -- which is what keeps this from
-- turning into a raid full of clients asking forever.
local function StateStillNeeded()
    if not LC.sessionStateKnown then return true end
    if not LC.sessionActive then return false end
    if next(LC.raidConfig) == nil then return true end
    -- A config we INVENTED for ourselves is not an answer from the raid, and treating it as one is
    -- how a client stops asking while running the wrong settings.
    --
    -- After a reload the table is empty, the raid-leader fallback in LC.IsConfigOwner goes live, and
    -- LC.ApplyOwnConfig writes this client's OWN settings in with fromSelf set. From that moment
    -- `next(LC.raidConfig) ~= nil` is true, so the question above answered "nothing left to ask" --
    -- and nobody ever corrected it, because nothing else re-sends a config to a client that has not
    -- asked. Measured in tests/test_lc_soak.lua: a raider who reloads late spends the rest of the
    -- evening on their own roll setting while the raid is on the other one, which decides whether
    -- they roll at all (B25's cost, arrived at from a different direction).
    --
    -- Same predicate LC.HandleConfigRelay uses to decide whether a relay may overwrite what we hold
    -- (see there): fromSelf AND no lootmaster named in our own settings. A leader who typed their
    -- own name in the field owns that config on purpose and is not asking anybody about it.
    local ownField = LC.ResolveConfigName(KART_Settings and KART_Settings.lcLootmaster)
    return (LC.raidConfig.fromSelf and not ownField) or false
end

local function RequestSessionState(attempt)
    if not StateStillNeeded() or KART_Settings.lcModuleEnabled == false then
        stateReqInFlight = false
        return
    end
    -- Reading as ungrouped for a moment is exactly when this is needed, and returning here used to
    -- end the whole sequence: a two-second blip on the wrong attempt cost every remaining one, and
    -- nothing asked again for the rest of the evening. Skip the send, keep the chain.
    if IsInRaid() then LC.SendLC("LC_STATE_REQ") end
    local delay = STATE_REQ_BACKOFF[attempt]
    stateReqInFlight = delay ~= nil
    if delay then
        C_Timer.After(delay, function() RequestSessionState(attempt + 1) end)
    end
end

local function TearDownForRaidExit()
    local wasActive = LC.sessionActive
    LC.promptedThisSession = false
    LC.sessionActive = false
    LC.sessionStateKnown = false
    LC.sessionStartedByUs = false
    LC.standInAccepted = false
    LC.standInAsked = false
    -- The raid's config belongs to the raid we just left. It survived before, so the same client
    -- walked into the next raid still naming a lootmaster who was never in it — the cross-raid half
    -- of B29, and a config nobody could displace because that stale name made IsSenderLootOwner
    -- reject the new raid's owner.
    wipe(LC.raidConfig)
    LC.CouncilNamesTable = {}
    LC.historySyncRequested = false
    LC.stateSyncRequested = false
    -- Whoever was named was named for the raid we just left; the next one is a different roster (B62).
    wipe(LC.outdatedWarned)
    -- Leaving the raid ends the session for us as well, so drop the tracked rolls the same way
    -- SetSessionActive(false) and an incoming LC_ACTIVE:0 do. Without this the council panel and
    -- vote window keep last raid's tabs, votes and winner highlights, and those low rollIDs are
    -- exactly the ones Blizzard hands out first in the next raid — an immediate collision.
    if wasActive then LC.ClearAllRolls() end
    -- Any B12 retry (see LC.RetryPendingConfig) was for this raid's config; it's meaningless in
    -- whatever we join next, regardless of whether a session was active.
    LC.CancelPendingConfig()
end

-- Either we hold the name and can see they are gone, or a relay told us the raid's lootmaster is not
-- here without naming them (B130). Both are the same situation for the person being asked.
local function LootmasterGone()
    return LootmasterAbsent() or LC.raidConfig.relayLootmaster == "0"
end

-- The raid's lootmaster is gone and we are the raid leader, so the role falls to us. Ask before
-- it does (see LC.IsLootOwner for why): standing in means every council-eligible item is force-won
-- into our own bags from the next drop onwards.
--
-- Both latches are cleared the moment the lootmaster is back, so this is not a one-way door — someone
-- who ported out and came back takes their role with them, and a leader who declined is asked again
-- the next time it genuinely happens.
function LC.CheckStandIn()
    if not LootmasterGone() then
        LC.standInAccepted = false
        LC.standInAsked    = false
        return
    end
    if LC.standInAccepted or LC.standInAsked then return end
    if not UnitIsGroupLeader("player") then return end
    StaticPopupDialogs["KART_LC_STAND_IN"].text = KART.L.LC_STAND_IN_TEXT
    -- Latch only once the question is actually on screen. StaticPopup_Show returns nil when it could
    -- not show — Blizzard's popup pool is four slots wide and this addon is not the only thing using
    -- it — and latching first meant a question nobody ever saw was never asked again, leaving the
    -- raid with no loot owner at all for the rest of the evening and nothing printed anywhere.
    if StaticPopup_Show("KART_LC_STAND_IN") then
        LC.standInAsked = true
    end
end

function LC.CheckRaidJoin()
    if not InAnyRaid() then
        -- NEVER tear down on a single negative reading. This runs on every GROUP_ROSTER_UPDATE, and
        -- the group APIs report inconsistent state for a moment while a roster change is being
        -- applied — one such blip used to end the session for the whole raid and wipe every tracked
        -- roll mid-boss. It also re-armed the start prompt, because LC.promptedThisSession is reset
        -- in here and nowhere else at runtime: that reappearing prompt is what identified this path
        -- from a live raid report ("no session opened for the boss, and afterwards it asked again").
        -- Confirm the departure once more before believing it.
        if LC.raidExitPending then return end
        -- A cancellable timer, not a bare flag and C_Timer.After. The flag alone was the only thing
        -- tying a pending confirmation to the departure that armed it, and the rejoin branch below
        -- cleared the flag without stopping the timer — so a second blip arming a second
        -- confirmation could be resolved by the FIRST one still in flight, seconds early. That
        -- shortens the confirmation to whatever is left of the older countdown and tears the session
        -- down mid-boss, which is the exact outcome this delay exists to prevent.
        LC.raidExitPending = C_Timer.NewTimer(RAID_EXIT_CONFIRM_DELAY, function()
            LC.raidExitPending = nil
            if InAnyRaid() then return end -- it was a blip; the session was never in danger
            TearDownForRaidExit()
        end)
        return
    end
    -- Back in, or never left. Either way a confirmation still in flight is moot — it re-checks before
    -- acting, so clearing the flag only stops it blocking a genuine exit later on.
    --
    -- But a negative reading DID happen, and this branch cannot tell a two-second API blip from
    -- actually leaving and being re-invited inside the confirm window. In the second case the
    -- teardown is skipped, and with it the only runtime reset of these three latches — so the client
    -- would spend the whole next raid never asking for the session state, never catching up on loot
    -- history, and never being offered the prompt again. Re-arm them here instead: asking twice
    -- costs one addon message and one dialog, being unable to ask at all costs the evening.
    if LC.raidExitPending then
        LC.raidExitPending:Cancel()
        LC.raidExitPending      = nil
        LC.promptedThisSession  = false
        LC.stateSyncRequested   = false
        LC.historySyncRequested = false
    end
    if KART_Settings.lcModuleEnabled == false then return end

    -- Ask peers (once per raid join) for any loot-history entries logged while we weren't around.
    if not LC.historySyncRequested then
        LC.historySyncRequested = true
        KART.LH.RequestHistorySync()
    end

    -- Ask the raid for the current session-active flag and raid-wide config, so a late joiner or a
    -- /reload'd client is never stuck on stale defaults until somebody happens to notice a roster
    -- change (see LC.HandleStateRequest below) — same request/response shape as the loot-history
    -- catch-up above.
    --
    -- Gated on whether we still need the answer and whether a chain is already running, NOT on
    -- "have we ever asked". LC.stateSyncRequested was that latch and it never came back off: a
    -- client whose whole backoff was swallowed — Blizzard's chat throttle, or a blip on the wrong
    -- attempt — never asked again, and sat outside a session the rest of the raid was in for the
    -- whole evening. Every roster change is now another chance, which is what a roster change was
    -- always meant to be.
    if StateStillNeeded() and not stateReqInFlight then
        RequestSessionState(1)
    end

    LC.CheckStandIn()

    -- Re-broadcast the authoritative config on every roster change so late joiners get it too.
    --
    -- ABOVE the loot-owner gate below, and that is the whole point: the config belongs to the raid
    -- LEADER and the loot flow to whoever they designate, and those are different people in the
    -- normal split setup (one person leads, another hands out the loot -- see docs/OWNERSHIP.md).
    -- Behind that gate, a leader who had designated somebody else stopped re-broadcasting entirely,
    -- so nobody in the raid re-sent the config on a roster change and every late arrival was left on
    -- their own vote buttons, minimum quality and roll setting. It was invisible while an empty
    -- Lootmaster field still made the leader the loot owner as well; B76 took that coincidence away
    -- and the soak went from 4 disagreements in 30000 runs to 2885 in 8000.
    --
    -- BroadcastRaidConfig self-gates on LC.IsConfigOwner, so this needs no ownership test of its own.
    if LC.sessionActive then LC.BroadcastRaidConfig() end

    -- The loot owner, not the raid leader (see LC.IsLootOwner): they open and close the session, so
    -- they are also the one who gets asked whether to start one.
    if not LC.IsLootOwner() then return end

    if LC.promptedThisSession then return end
    LC.promptedThisSession = true
    -- Small delay so the roster is fully settled before showing the prompt.
    -- Never ask while a session is already running: becoming loot owner mid-raid (the lootmaster
    -- field being filled in later, or a leader change) used to pop this question over a live
    -- session, and answering "no" then ended it for the whole raid.
    C_Timer.After(3, function()
        if InAnyRaid() and LC.IsLootOwner() and not LC.sessionActive then
            LC.ShowSessionPrompt()
        end
    end)
end

-- =====================================================================
--  START_LOOT_ROLL handler  (called from Core.lua)
-- =====================================================================

-- GetLootRollItemLink(rollID) can return nil for a moment right when the roll starts (most common
-- for a brand-new item whose data hasn't finished propagating client-side yet). Retries a handful
-- of times with backoff instead of permanently giving up — bails early if rollID's entry was
-- resolved by some other path in the meantime, or cleared entirely (tab closed/session ended, see
-- LC.Trade.ClearRollState), so a long-since-irrelevant timer never resurrects a forgotten roll.
-- Two sources, because the two callers have different information available. OnStartLootRoll has a
-- live Blizzard roll and no itemID; HandleStart has an itemID from the payload and no roll at all
-- (that is the whole reason it exists). The bare "item:12345" string HandleStart leaves behind is
-- therefore also a retry target, not a finished answer: it renders, but it is not a real link, and
-- once the client caches the item this upgrades it to one. Reading the ID back out of that string
-- avoids carrying yet another per-roll table that every cleanup path would have to remember.
local function ResolveRollItemLink(rollID, attempt)
    local current = LC.rollItems[rollID]
    if current == nil or LC.IsRealItemLink(current) then return end
    attempt = attempt or 1
    local link = GetLootRollItemLink(rollID)
    if not link then
        -- The parked value itself, not the id inside it: what LC.HandleStart leaves behind is the
        -- item STRING it was sent, bonus ids and all, and asking about the id alone would resolve it
        -- into the base version of the item (B119).
        local parked = tostring(current):match("^(item:.+)$") or tostring(current):match("item:(%d+)")
        if parked then link = select(2, C_Item.GetItemInfo(parked)) end
    end
    if link then
        LC.rollItems[rollID] = link
        LC.Vote.RefreshVoteListRows()
        if LC.councilPanel and LC.councilPanel:IsShown() then
            KART.LC.Council.RefreshCouncilRows()
            KART.LC.Council.RefreshCouncilTabs()
        end
    elseif attempt < 8 then
        C_Timer.After(0.25 * attempt, function() ResolveRollItemLink(rollID, attempt + 1) end)
    else
        -- Polling has given up (~7s). When all we hold is a bare item string, ask the client to tell
        -- us the moment it caches that item instead — the same escape LootCouncilPanel already uses
        -- for the bare strings in the equipped-gear cache. Without it an item still uncached after
        -- seven seconds keeps rendering as "item:249364" for the rest of the session, which is not
        -- the "name and icon" this path promises. One-shot: it fires once per roll at most, because
        -- it only runs after the retry budget is spent.
        local itemID = tonumber(tostring(current):match("item:(%d+)"))
        if itemID then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                -- Only if this roll is still the same unresolved item — the ID may well have been
                -- cleared or replaced during the wait (session end, tab close, reused rollID).
                local now = LC.rollItems[rollID]
                if now ~= current then return end
                -- Loaded BY id (that is what the loader takes), resolved by the string we are
                -- holding: the load is about the item being in the cache at all, the lookup is about
                -- which variant of it we want back (B119).
                local full = select(2, C_Item.GetItemInfo(current))
                if not full then return end
                LC.rollItems[rollID] = full
                LC.Vote.RefreshVoteListRows()
                if LC.councilPanel and LC.councilPanel:IsShown() then
                    KART.LC.Council.RefreshCouncilRows()
                    KART.LC.Council.RefreshCouncilTabs()
                end
            end)
        end
    end
end

-- Restarts the resolver for anything currently tracked that is not a real link yet. Only caller is
-- LC.RestoreSessionSnapshot (B81): a snapshot carries whatever LC.rollItems held at logout, and what
-- LC.HandleStart leaves behind until the client caches an item is a bare "item:12345" string. A
-- reload is exactly when that cache is coldest, and nothing else would ever look at the roll again —
-- so a restored item would render as "item:249293" instead of a name for the whole distribution,
-- which is the shape of GitHub #12, #13 and #16.
--
-- Reached through LC rather than the local above because the restore is defined earlier in this
-- file; by the time it runs (ADDON_LOADED) this assignment has long happened.
function LC.ResolveTrackedItemLinks()
    for _, list in ipairs({ LC.councilTabs, LC.voteListRolls }) do
        for _, rollID in ipairs(list) do
            if not LC.IsRealItemLink(LC.rollItems[rollID]) then ResolveRollItemLink(rollID) end
        end
    end
end

-- Claims rollID by whatever roll type is actually available, strongest first — used only for the
-- designated lootmaster (see LC.GetLootmaster), who must win every item so they can hand it to
-- whoever the council actually decided on via trade (see LC.pendingTrades). Never passes.
local function ForceWinRoll(rollID)
    local _, _, _, _, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if canNeed then
        RollOnLoot(rollID, 1)
    elseif canGreed then
        RollOnLoot(rollID, 2)
    elseif canDisenchant then
        RollOnLoot(rollID, 3)
    elseif canTransmog then
        RollOnLoot(rollID, 4) -- roll type 4 = Transmog; Blizzard doesn't expose a named constant for it
    end
end

-- Blizzard's rollID can be reused for a genuinely different item before the previous roll's
-- state (votes, deadline, tab / vote-list entry) under that same ID has been cleared — most
-- commonly several trash corpses looted within the same second. Called with the incoming roll's
-- bare itemID whenever a roll starts (locally via OnStartLootRoll, or via a received LC_START);
-- if a DIFFERENT real item is already tracked under this rollID, wipes its stale state first so
-- the new roll starts clean instead of silently inheriting old votes or reusing an old tab/row
-- for the wrong item. newItemID == "" means "not resolved yet" — never purge on unresolved data,
-- only on a confirmed different item (see the LC_RESULT-side fix this complements, in
-- Trade.HandleResult, for the other half of this same rollID-collision class of bug).
-- How long roll data for an untracked rollID stays trusted. LC.HandleRolls accepts a table before
-- LC_START arrives (see its comment); that gap is one addon-message round trip, so anything still
-- unmatched after this is left over from an earlier roll that used the same ID.
local ROLL_ORPHAN_GRACE = 15

-- [rollID] = the itemID the rolls currently stored under it were cast for. Blizzard reuses a rollID
-- for a genuinely different drop within seconds on trash, and every client purged the old state when
-- it processed its own START_LOOT_ROLL -- but back when every client drew and broadcast its own
-- number, peers broadcast theirs at that same instant, so a client that had already RECEIVED some of
-- them wiped them a moment later with its own purge. Whoever ran their handler first lost the rolls
-- of everybody behind them, and the council scored a tie-break on a partial set. Found by the soak
-- once it learned to reuse a rollID. The single-writer draw this module moved to does not have that
-- race, but PurgeStaleRoll's keepRolls still needs to know which item the current rolls belong to.
LC.rollsFor = LC.rollsFor or {}

-- Blizzard's roll range is 1-100, and a group cannot hold more than 40 players, so a pool of this
-- size is never exhausted by LC.DrawRollTable's draw-without-replacement below.
local ROLL_MAX = 100

local LibDeflate = LibStub("LibDeflate")

-- Packed only when the MESSAGE would otherwise be split, which is why this is handed the assembled
-- message and not the payload. AceComm sends one part iff the whole string is 255 bytes or less
-- (AceComm-3.0's SendCommMessage), and the head is part of that string: "LC_DROP:20:r:" is 13 bytes,
-- "LC_ROLLS:" is 9. Deciding on the payload alone left a band -- a payload of 243-254 bytes on
-- LC_DROP, 247-254 on LC_ROLLS -- where the message went out split AND unpacked, which is the one
-- outcome this exists to prevent: a ten-man group's catch-up roll table cost two chunks where one
-- would do. The head length could be passed as a number instead, and that is exactly the arithmetic
-- that was got wrong once: it is a second place to update whenever a head changes. The assembled
-- string cannot drift from itself.
--
-- Below that, packing buys nothing and costs a wire log nobody can read while debugging a raid night.
-- Measured at 25 raiders: six items are 1478 bytes and six chunks, 437 and two when packed; a roll
-- table for 25 is 620 and three, 168 and one.
--
-- Level 1 deliberately: measured against level 9 it produces the same CHUNK count on every message
-- this addon sends, 30-50% faster (0.07-0.22ms against 0.1-0.4ms). Chunks are what the transport
-- charges for, so a smaller byte count that does not cross a chunk boundary is worth nothing.
--
-- EncodeForWoWAddonChannel is not optional: an addon message cannot carry a null byte, and a deflate
-- block routinely contains them. It costs 0-3 bytes -- it escapes, it does not re-encode.
local PACK_MAX_MESSAGE = 255
local PACK_LEVEL = { level = 1 }

-- The largest block we will even hand to the decompressor, and the only bound there is on what one
-- arrives as. AceComm reassembles a multipart message of any length, so before this a group member
-- could send a small block that expands to megabytes on every client in the raid -- memory and frame
-- time -- where plain text cost the raid exactly what it weighed. Not an open door (a guild-mandatory
-- addon, and ChatThrottleLib caps the sender's own throughput), but the cheap half of the fix is one
-- comparison, so it is defence in depth rather than a hole left open.
--
-- Sized against the largest block WE can produce, measured with LibDeflate at PACK_LEVEL:
--   25 raiders, six items, real item strings ...........  234 bytes  (the ordinary raid night)
--   40 raiders (the group cap), TABLE_MAX_IDS = 12 items,
--   every item string at LC.ItemPayload's own 195-byte
--   ceiling -- the most this protocol can ever say ...... 1081 bytes
-- 2048 is that worst case with room to spare. What it buys: deflate cannot expand by more than about
-- 1032:1, so a 2048-byte block decompresses to at most ~2.1 MB rather than to whatever the sender
-- felt like (measured with LibDeflate's own encoder, the realistic ceiling is ~400:1, ~800 KB).
local PACK_MAX_BLOCK = 2048

local function Pack(message, plain)
    if #message <= PACK_MAX_MESSAGE then return nil end
    -- No nil check on the result: CompressDeflate errors on a bad argument and returns a string for
    -- every string, so a guard here would be handling a case that cannot occur.
    return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(plain, PACK_LEVEL))
end

-- nil when the block will not come back as a string at all: too large to be ours, truncated, foreign,
-- or damaged badly enough that the deflate stream itself no longer parses. Every caller treats that as
-- "this message says nothing" rather than storing half of it, and counts it --
-- LC.diag.packedUnreadable -- because the alternative is a client that quietly loses a whole boss's
-- items with nothing to read on either end.
--
-- What it is NOT is an integrity check, and deliberately so. Raw deflate carries no checksum, so a
-- block damaged in a way that still parses comes back as altered plaintext and this cannot tell.
-- That is not a hole this shape opened: a corrupted PLAIN message has the identical exposure, the
-- guards below catch both the same way, and the addon channel delivers reliably in the first place.
local function Unpack(blob)
    if #blob > PACK_MAX_BLOCK then return nil end
    local decoded = LibDeflate:DecodeForWoWAddonChannel(blob)
    if not decoded then return nil end
    return LibDeflate:DecompressDeflate(decoded)
end

-- Exposed for LootCouncilVote.lua's vote heartbeat, which sends a bundled message of the same shape
-- (a plain head, one marker, the block last) and must not carry a second copy of these ceilings:
-- PACK_MAX_MESSAGE and PACK_MAX_BLOCK are the numbers, and a copy of them would drift the day one of
-- them moves. Same functions, a name another file can see.
LC.PackPayload, LC.UnpackPayload = Pack, Unpack

-- The wire form, kept in one place because two callers need it: the draw below, and the catch-up
-- answer that re-sends a table somebody lost (LC.HandleRollRequest).
--
-- Packed, this is LC_ROLLS:P:<block> -- the same form LC_DROP uses: a plain head, one letter that
-- says what follows, and the block as the LAST field, where the arbitrary bytes it contains cannot
-- split anything else. There is no state letter on the plain form and deliberately so: it is the
-- payload LC.HandleDrop hands the handler directly (it rebuilds this exact shape per entry), and a
-- letter no sender there could produce would be a second spelling of the same thing. "P" cannot be
-- mistaken for a plain payload, which always opens with the rollID's digits.
function LC.SerializeRollTable(rollID)
    local rolls = LC.rolls[rollID]
    if not rolls or next(rolls) == nil then return nil end
    local parts = {}
    for key, value in pairs(rolls) do parts[#parts + 1] = key .. "=" .. value end
    -- Sorted so the message is byte-identical for the same table, which is what makes a retry
    -- comparable to the original in the harness -- pairs() order is not stable across runs.
    table.sort(parts)
    local plain = rollID .. ":@" .. (LC.rollsFor[rollID] or "") .. ":" .. table.concat(parts, ",")
    local message = "LC_ROLLS:" .. plain
    local blob = Pack(message, plain)
    if blob then
        return "LC_ROLLS:P:" .. blob
    end
    return message
end

-- ==========================================================================
--  The one rule LC_DROP has to keep
-- ==========================================================================
--
--   THE HEAD LIST AND EVERY ENTRY'S NUMBERS COME FROM ONE SET, AND THAT SET IS WHATEVER THE
--   NUMBERS WERE ACTUALLY DRAWN AGAINST.
--
-- Breaking it is silent, and it is expensive. The head names the participants once and every entry
-- lists its numbers in that order, so a head built against a different set than the draw shifts every
-- position after the first difference onto somebody else's raider -- or, in the shape this keeps
-- taking, hands a raider the head names but the draw never covered a roll of 0 that nobody cast.
-- Arriving from the recorded announcer, that 0 is authoritative: nothing refuses it, no diagnostic
-- counts it, and the council scores its tie-break on it.
--
-- It has been broken three times, in three different places, and every time for the same reason: the
-- two halves were computed INDEPENDENTLY and compared afterwards, and a comparison can be forgotten
-- at the next site. So the head is no longer computed at all. It is DERIVED from the numbers, here,
-- and every caller that needs one asks this function. A derivation cannot drift.
--
-- The authority is LC.rolls[rollID] and NOT LC.rollEligible[rollID] -- the trap all three instances
-- fell into. The two agree at the instant LC.DrawRollTable runs and can part company immediately
-- after: Blizzard re-raises START_LOOT_ROLL for a roll still in progress, SnapshotEligible re-runs
-- against a fresh identity walk of the roster, and LC.DrawRollTable deliberately refuses to redraw a
-- table the raid has already been shown. A key resolving from a pending text form to a GUID between
-- two raises is enough to part them, and so is somebody walking in or porting out.
--
-- With rolls switched off raid-wide there is no table, so this answers with an EMPTY list -- which is
-- exactly what the format asks for (design §B and §F: no numbers, and no name list either).
--
-- Second return: a COPY of the numbers the head was derived from, for the caller to keep (B135). A
-- batch entry is written now and serialized up to half a second later, and LC.rolls[rollID] is shared
-- mutable state that a peer's table for the same id can replace in between (the B130 disagreement
-- corner) -- so an entry that read it at send time could ship numbers this client never drew, at a
-- length the receiver's check cannot tell apart. Handed out from HERE, next to the head, so the two
-- still come from one read of one set: a caller that keeps both keeps a pair that cannot have drifted.
function LC.DrawnKeys(rollID)
    local src = LC.rolls[rollID]
    local keys, rolls = {}, nil
    if src then
        rolls = {}
        for key, roll in pairs(src) do
            keys[#keys + 1] = key
            rolls[key] = roll
        end
    end
    -- Sorted for the same reason LC.DrawRollTable sorts its own walk: the receiver matches numbers to
    -- this list BY POSITION, so both sides have to walk it the same way -- and pairs() over a set of
    -- GUIDs has no defined order, in the game or in the harness.
    table.sort(keys)
    return keys, rolls
end

-- One message for everything that dropped at once.
--
-- Shape: LC_DROP:<secs>:<kind>:<key>,<key>,...;<rollID>#<roll>,<roll>,...#<itemString>;<rollID>#...
--
-- The head names the participants ONCE; each entry then lists its numbers in that order. That is the
-- whole saving: six items in a 25-man raid used to repeat the same 25 identity keys six times, which
-- was three quarters of the traffic.
--
-- kind: "r" for a real drop, "m" for manually added items (/kart add). A message is always one or the
-- other, and the receiver routes each entry into the handling that token had before -- a manual item
-- has no Blizzard roll behind it, is open to the whole raid, and nobody has to win it.
--
-- The separators are not free: an item string contains colons AND commas (see LC.ItemPayload and
-- B119, which is why the full string travels at all). So ";" separates sections and entries, "#"
-- separates an entry's fields, "," stays for lists -- and the item string is the LAST field of an
-- entry, where nothing it contains can split anything else.
local DROP_ENTRY_SEP, DROP_FIELD_SEP = ";", "#"

function LC.SerializeDrop(kind, secs, keys, entries)
    local parts = {}
    for _, e in ipairs(entries) do
        local nums = {}
        -- No table at all -- rolls are switched off raid-wide -- leaves the field EMPTY, which is what
        -- the receiver reads as "this item has no numbers". Filling it with zeros instead would hand
        -- every raider a roll of 0 for an item the raid deliberately does not roll on.
        --
        -- The entry's OWN copy, taken when the entry was created (B135), not LC.rolls[e.rollID] as it
        -- stands now: this runs up to half a second after the entry was written, and by then that
        -- table can be a peer's rather than this client's.
        local rolls = e.rolls
        if rolls then
            -- The last gate on the invariant above, and the reason there is no `or 0` here any more.
            -- The caller derives the head from LC.DrawnKeys and splits the batch the moment an entry
            -- needs a different one, so a mismatch at this point is a programming error -- but the
            -- cost of writing one out is a number nobody drew, accepted as authoritative by the whole
            -- raid. So the entry loses its numbers ENTIRELY rather than half of them: an empty field
            -- is a gap the heartbeat's repair path fills (LC.HandleRolls refuses a partial table for
            -- exactly this reason), while a 0 is a lie no client can see.
            local n = 0
            for _ in pairs(rolls) do n = n + 1 end
            if n == #keys then
                for i, key in ipairs(keys) do
                    if rolls[key] == nil then nums = {} break end
                    nums[i] = rolls[key]
                end
            end
        end
        parts[#parts + 1] = e.rollID .. DROP_FIELD_SEP .. table.concat(nums, ",")
            .. DROP_FIELD_SEP .. e.itemString
    end
    local plain = table.concat(keys, ",") .. DROP_ENTRY_SEP .. table.concat(parts, DROP_ENTRY_SEP)
    local message = "LC_DROP:" .. secs .. ":" .. kind .. ":" .. plain
    local blob = Pack(message, plain)
    -- The packed block carries arbitrary bytes -- colons, semicolons, control characters -- so it can
    -- only ever be the LAST field, behind a head that stays plain. The kind letter says which it is:
    -- lower case plain, upper case packed. A client that does not know the upper-case form drops the
    -- message as an unknown shape instead of reading it wrong.
    if blob then
        return "LC_DROP:" .. secs .. ":" .. kind:upper() .. ":" .. blob
    end
    return message
end

-- The whole raid's rolls, drawn once by the client that announces the item.
--
-- Every client used to draw its own number and broadcast it, which is three problems in one: 25
-- messages in the same instant for one drop (the biggest burst this addon makes, and it lands in the
-- window the encounter restriction has just opened), 25 separate things to lose with no way to ask
-- for one back, and regular ties, because 25 independent draws out of 1-100 collide often.
--
-- Drawn WITHOUT replacement, so no two raiders can be handed the same number and the council never
-- has to break a tie the addon invented. A group cannot hold more than 40 players, so a pool of 100
-- is never exhausted.
--
-- The set of participants is LC.rollEligible[rollID] -- the roster snapshot SnapshotEligible already
-- takes when announcing. One answer to "who was standing there", used both for who gets a number and
-- for who may be caught up later (LC.MayCatchUp).
-- silent: draw and store, but do not send -- the numbers travel inside LC_DROP instead, where the
-- participant list is written once for the whole batch rather than once per item. Everything else
-- about the draw is identical, and that is the point: there is one place that decides who gets which
-- number, whichever message carries the result.
function LC.DrawRollTable(rollID, itemID, silent)
    if not LC.GetRollsEnabled() then return end
    -- Blizzard re-raises START_LOOT_ROLL for a roll still in progress -- OnStartLootRoll runs again,
    -- PurgeStaleRoll sees the SAME item and deliberately keeps the rolls already cast for it (see its
    -- comment), and the call site right after it reaches this function a second time regardless. A
    -- second draw would replace a number the raid has already been shown, which is the one thing a
    -- tie-breaker must never do -- RollForSelf carried this exact guard before the draw became a
    -- single table; it did not stop mattering when the draw moved to one client instead of everybody.
    -- A rollID reused for a genuinely DIFFERENT item must still redraw: PurgeStaleRoll has already
    -- emptied LC.rolls[rollID] for that case by the time this runs, so the itemID comparison below is
    -- what tells the two apart, not the emptiness check alone.
    if LC.rolls[rollID] and next(LC.rolls[rollID]) ~= nil and LC.rollsFor[rollID] == (itemID or "") then
        return
    end
    local set = LC.rollEligible[rollID]
    if not set then return end

    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    -- Sorted before drawing, so the same seed produces the same table in the harness. pairs() over a
    -- set of GUIDs has no defined order, and the soak's whole premise is that a seed reproduces.
    table.sort(keys)

    local pool = {}
    for i = 1, ROLL_MAX do pool[i] = i end

    local rolls = {}
    for _, key in ipairs(keys) do
        rolls[key] = table.remove(pool, math.random(#pool))
    end

    LC.rolls[rollID] = rolls
    LC.rollsFor[rollID] = itemID or ""

    -- The sender does not process its own message (KASC drops the echo in Dispatch), so the table is
    -- written locally above rather than on the way back.
    if silent then return end
    local msg = LC.SerializeRollTable(rollID)
    if msg then LC.SendLC(msg) end
end

-- Receives the whole raid's rolls for an item and writes them wholesale rather than one entry at a
-- time, which is the point of the change: one writer instead of 25, so there is no longer a state
-- where two clients know a different number of rolls and neither of them can tell.
--
-- Who may write this item's numbers, strongest first:
--   1. whoever announced this item to us -- the numbers belong to that announcement, and this is
--      the only client whose claim survives a disagreement about who is lootmaster right now
--      (B130: two clients disagreeing about who is lootmaster right now used to mean two different
--      "owners" each convinced they could overwrite the other's table, reachable for a few seconds
--      around any lead change -- see HandleConfigRelay's fromSelf comment);
--   2. anybody in our group, but only into a VOID -- the "fills a gap, never replaces" rule
--      LC.HandleConfigRelay uses. Without it, a client whose ownership view disagrees with the real
--      owner's refuses the table and is left with nothing for that item, permanently:
--      LC.HandleTable, the only path that could otherwise prompt it to ask again, gates on
--      LC.IsSenderLootOwner too and would refuse the very heartbeat that could fix it (B129, B131);
--   3. nobody else.
-- Group membership is enforced upstream by KASC's dispatcher (this token is registered with
-- group = true), so case 2 needs no check of its own.
--
-- Deliberately NOT gated on LC.rollItems[rollID], for the same reason the old per-client handler was
-- not: the table is sent right after the announcement, and a client that learns of the roll only
-- from LC_START can legitimately see the two in either order.
--
-- Same numbers, twice: NOT a refusal. Since B131 every answer to an LC_ROLLS_REQ is a group
-- broadcast, so one repair in a 25-man raid lands on 24 clients that already hold that exact table.
-- Counting those bumped LC.diag.refusedSender by 24 per repair and buried the one diagnostic that
-- exists to surface an ownership disagreement (B129/B130) under entirely expected traffic.
local function SameRolls(a, b)
    if a == nil or b == nil then return false end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function LC.HandleRolls(payload, senderKey)
    -- Same rule as LC.HandleDrop: unpack first so every guard below reads the one shape, and refuse
    -- the message outright when the block will not come back rather than storing a partial table --
    -- which is the very thing the empty-table check further down exists to keep out.
    local blob = payload:match("^P:(.*)$")
    if blob then
        payload = Unpack(blob)
        if not payload then
            LC.diag.packedUnreadable = LC.diag.packedUnreadable + 1
            return
        end
    end
    local rollID, itemID, list = payload:match("^(%d+):@(%d*):(.*)$")
    rollID = tonumber(rollID)
    if not rollID then return end

    -- Somebody else answered a request we were about to answer too. Before the sender check on
    -- purpose: a table we will not STORE is still proof that the group has been answered, so there is
    -- nothing left for us to add.
    LC.rollsAnswerAt[rollID] = nil

    -- Read for the same reason and just as early: a table drawn for a DIFFERENT item than the one we
    -- dismissed under this id names a roll nobody here ever decided about, whether or not we go on to
    -- store the numbers (B132). This is the message that repairs the case in practice -- it reaches
    -- the whole raid, so a client that missed the announcement hears the reuse from it and starts
    -- asking for the item again on the next heartbeat.
    LC.ForgetDismissalIfReused(rollID, itemID)

    local rolls = {}
    for key, value in list:gmatch("([^=,]+)=(%d+)") do rolls[key] = tonumber(value) end

    local isAnnouncer = LC.rollAnnouncedBy[rollID] == senderKey
    local isVoid = LC.rolls[rollID] == nil
    if not isAnnouncer and not isVoid then
        -- A peer's table for an item we already hold. Expected traffic when it AGREES (see SameRolls
        -- above) -- silent, because it is not a refusal in any sense a diagnostic should report.
        --
        -- When it disagrees it is the opposite: this is the first place in the addon that can PROVE
        -- two clients hold different numbers for one item. Nothing else notices -- the raid simply
        -- scores a tie-break on numbers half of it does not have. So it gets its own counter rather
        -- than sharing one with "the sender is not who I expected", which is a different question.
        if not SameRolls(LC.rolls[rollID], rolls) then
            LC.diag.rollsConflict = LC.diag.rollsConflict + 1
        end
        return
    end

    -- Same orphan stamp the old handler set: a table for a roll this client never hears about would
    -- otherwise sit here forever, and PurgeStaleRoll needs to tell "arrived a moment early" from
    -- "left over from a previous drop under the same id".
    if not LC.rollItems[rollID] then
        LC.rollsPendingSince = LC.rollsPendingSince or {}
        LC.rollsPendingSince[rollID] = LC.rollsPendingSince[rollID] or GetTime()
    end

    -- An empty table is still a TABLE, and LC.rolls[rollID] == nil is exactly what needRolls (and the
    -- isVoid check above) uses to mean "nothing held yet". Storing one here would be indistinguishable
    -- from a real draw and would permanently stop this client from ever asking for the real numbers.
    -- LC.SerializeRollTable cannot currently produce such a payload (it refuses to serialize an empty
    -- LC.rolls[rollID] in the first place), so this is a defence against a message shape that does not
    -- happen today, not a fix for one that does.
    if next(rolls) == nil then return end
    LC.rolls[rollID] = rolls
    LC.rollsFor[rollID] = itemID or ""

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        KART.LC.Council.RefreshCouncilRows()
    end
end

-- Every client in the raid holds the same table, so a request could be answered by all of them at
-- once -- which is the message storm this rework exists to remove. Spread across a window so answers
-- land apart in time.
--
-- Tried first, and measured to not hold: a hash of each client's own NAME (the construction KASC's
-- handshake already uses for the same problem). Simulated at raid size -- 25 random names, 20,000
-- trials, the exact hash below -- 26% of full rosters produced two clients scheduled within a few
-- milliseconds of each other, well inside ordinary addon-message jitter under ChatThrottleLib
-- congestion, which is exactly when this fires. A hash spreads by luck, and luck is what collides.
--
-- What every client in the group CAN see identically is the roster itself: sorted resolved identity
-- keys. A client's slot is its POSITION in that order, which divides the window among N clients into
-- N EQUAL gaps by construction -- gap = ROLLS_ANSWER_SPREAD / N, guaranteed, not merely likely.
--
-- What that requires is stronger than anything the addon needed before, and it is worth naming rather
-- than leaning on LC.DrawRollTable as a precedent: DrawRollTable sorts ONE snapshot on ONE client and
-- only has to be stable there, while this needs every client in the raid to independently produce the
-- SAME list. It does not, always: identity keys resolve at different moments (KASC.Identity), so a
-- client whose view of a raider is still a pending text key sorts them somewhere else, and two clients
-- can briefly disagree about the roster's membership entirely. When that happens the ordering is not
-- shared and the spacing degrades to what a hash gave -- two clients may land on the same slot. That
-- is the whole of the damage: the stand-down below is an OPTIMISATION, not a correctness rule. Two
-- answers to one request means one extra group broadcast, and the second one is an agreeing duplicate
-- the receiver now ignores in silence (see SameRolls in LC.HandleRolls). Nothing is lost, nobody is
-- counted as refused, and the asker is repaired either way.
--
-- The honest margin, since 250ms was claimed here and is not what the code has: at the addon's own
-- maximum group size (40 -- see LC.DrawRollTable's comment on why its roll pool is sized that way) the
-- gap is 10000ms / 40 = 250ms, and at this guild's 25 it is 400ms. A busy loot round's message queue
-- can add tens to hundreds of milliseconds, so at a full 40-man the gap is the same order as the
-- jitter it has to beat and the stand-down will sometimes lose the race. Widening the window was the
-- alternative and was not taken: it would delay every repair by seconds to buy margin against an
-- outcome that costs one duplicate broadcast.
local ROLLS_ANSWER_SPREAD = 10
LC.rollsAnswerAt = LC.rollsAnswerAt or {} -- [rollID] = true while an answer of ours is scheduled

-- The pure half: given the sorted identity keys currently in the group, one of them, and the window
-- to spread across, the slot it gets. Kept apart from SelfAnswerSlot below so a test can prove the
-- spacing at a full raid's size without spinning up a simulated one -- this needs no roster, no
-- client, nothing but the two lists.
--
-- The window is an argument because there are two callers with different ones: the roll table's ten
-- seconds, and the vote heartbeat's four (which has to stay under its own five-second period, or the
-- last client's phase slides into the next tick). The reasoning above about POSITION rather than a
-- hash is what both of them rest on and is stated there once.
function LC.AnswerSlot(keys, ownKey, spread)
    local n = math.max(#keys, 1)
    -- Last, not first, when we cannot find ourselves in the roster. A client that cannot resolve its
    -- own key is the one least able to agree with anybody else about the ordering, so it is the one
    -- that should be beaten to the answer by a client that can -- and it will still answer if none of
    -- them does. Defaulting to slot 1 made the least-coordinated client the most eager.
    local index = n
    for i, key in ipairs(keys) do
        if key == ownKey then index = i break end
    end
    return ((index - 1) / n) * spread
end

function LC.RollsAnswerSlot(keys, ownKey)
    return LC.AnswerSlot(keys, ownKey, ROLLS_ANSWER_SPREAD)
end

-- Our own slot against the group as it looks right now. Exposed (rather than file-local, as it was
-- while the roll table was the only caller) because LootCouncilVote.lua needs the identical roster
-- gathering for the vote heartbeat, and two copies of it would be two answers to "who is in the
-- raid" that could disagree.
function LC.SelfAnswerSlot(spread)
    local keys = {}
    for unit in KAUtil.EachGroupUnit() do
        local key = (KASC.Identity.ResolvePlayer(unit))
        if key then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return LC.AnswerSlot(keys, (KASC.Identity.ResolvePlayer("player")), spread)
end

local function SelfAnswerSlot()
    return LC.SelfAnswerSlot(ROLLS_ANSWER_SPREAD)
end

function LC.HandleRollsRequest(payload)
    local rollID = tonumber(payload:match("^(%d+)$"))
    if not rollID then return end
    if not (LC.rolls[rollID] and next(LC.rolls[rollID]) ~= nil) then
        -- Nothing to give -- and somebody else is asking for a table we are missing too. The answer
        -- is a group broadcast we will receive anyway, so push our own ask out by a full cooldown
        -- instead of adding a duplicate question to the same burst. That matters now that a roll
        -- stays askable for as long as it is tracked (LC.RollTracked): a table NOBODY in the raid
        -- still holds would otherwise have every client asking the group every ROLL_REQ_COOLDOWN for
        -- the rest of the round, forever, with no answer possible.
        --
        -- Only pushed FORWARD, never created: LC.HandleTable also reads the presence of this stamp as
        -- "the owner has already had its turn" and escalates on the strength of it. Somebody else's
        -- request says nothing about whether OUR owner has been asked yet.
        LC.rollReqSent = LC.rollReqSent or {}
        if LC.rollReqSent[rollID] then LC.rollReqSent[rollID] = GetTime() end
        return
    end
    -- We are already about to give it.
    if LC.rollsAnswerAt[rollID] then return end

    -- One walk of the roster and one identity resolution per member, not two: the slot is decided
    -- once and the stamp is a plain "an answer of ours is pending", which is all anything reads.
    local slot = SelfAnswerSlot()
    LC.rollsAnswerAt[rollID] = true
    C_Timer.After(slot, function()
        -- Somebody faster already answered; LC.HandleRolls clears this when a table lands.
        if not LC.rollsAnswerAt[rollID] then return end
        LC.rollsAnswerAt[rollID] = nil
        local msg = LC.SerializeRollTable(rollID)
        if msg then LC.SendLC(msg) end
    end)
end

local function PurgeStaleRoll(rollID, newItemID)
    -- A roll is STARTING under this ID, so whatever this client once put away under it is over: this
    -- is a different item, Blizzard having reused the integer. Cleared before every guard below,
    -- because "nothing tracked under this ID" is exactly the state a dismissal leaves behind and the
    -- staleness checks further down cannot see this case at all. Both callers are roll starts
    -- (LC.OnStartLootRoll, LC.HandleStart), and a catch-up only reaches them under a dismissed rollID
    -- when it names a DIFFERENT item -- LC.HandleRollCatchup still refuses a repeat of the item that
    -- was dismissed, and a different one IS the reuse this clear exists for (B132).
    LC.rollDismissed[rollID] = nil
    -- Orphaned roll data first, and before the newItemID guard below: this case has no tracked item
    -- to compare against, which is exactly why the itemID check can't see it. Left in place, those
    -- numbers would render as the NEW item's rolls on the council panel.
    local pendingSince = LC.rollsPendingSince and LC.rollsPendingSince[rollID]
    if pendingSince and (GetTime() - pendingSince) > ROLL_ORPHAN_GRACE then
        LC.rolls[rollID] = nil
    end
    -- The wait ends here whether or not it timed out: reaching this function means a roll under this
    -- ID is being processed right now, so nothing is waiting for one any more. Clearing it only in
    -- the branch above left the stamp behind on the path that matters most -- an LC_START arriving
    -- INSIDE the grace window, where the function returns a few lines down at "nothing tracked under
    -- this ID". The stamp then sat there for the rest of the session, and the next time Blizzard
    -- reused the ID the sweep above read it as "waiting for twenty minutes" and wiped -- except the
    -- table no longer held the orphan, it held the rolls peers had just broadcast for the NEW item.
    -- Only the clients that had missed that LC_START were hit, so the raid disagreed about who
    -- rolled what and the council scored its tie-break on a partial set (B71).
    if LC.rollsPendingSince then LC.rollsPendingSince[rollID] = nil end

    if not newItemID or newItemID == "" then return end
    local oldLink = LC.rollItems[rollID]
    -- Match on the itemID, whatever form the tracked value is in. Requiring a full "|Hitem:" link
    -- here meant a roll still parked as the bare "item:NNN" placeholder -- the state LC.HandleStart
    -- leaves it in until the item is cached -- could not be recognised as stale at all. A reused
    -- rollID then kept the previous item's votes, council tab and vote row, and a result for the old
    -- roll was accepted onto the live one, taking the new item's vote row off a raider's screen
    -- before they had voted. Narrow window, and rollID reuse within seconds is exactly what this
    -- function exists for.
    -- Nothing tracked under this ID at all, so there is nothing that could be stale.
    if oldLink == nil then return end

    local oldItemID = type(oldLink) == "string" and oldLink:match("item:(%d+)") or nil
    if oldItemID == newItemID then return end
    -- oldItemID nil past this point means we are holding something we never managed to identify --
    -- "???" from an LC_START that carried no itemID either (B40). That used to return, which left
    -- the detector blind for the rest of the session: every per-roll table survived into the next
    -- item under the same reused ID, so a raider's row showed a vote for an item they had never seen
    -- and they could never vote again.
    --
    -- A new item IS arriving under this ID and what we hold cannot be shown to be the same one -- it
    -- cannot be shown to be anything. Clearing it is the safe direction: losing votes for a roll
    -- nobody could read beats keeping votes that belong to a different item, on the screen that
    -- decides who gets it.

    for i = #LC.voteListRolls, 1, -1 do
        if LC.voteListRolls[i] == rollID then table.remove(LC.voteListRolls, i) end
    end
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    if LC.activeRollID == rollID then LC.activeRollID = nil end
    -- LC.rollLootedAt is not cleared here even though this IS the rollID-reuse case. Both callers
    -- (LC.OnStartLootRoll, LC.HandleStart) re-stamp it right after this returns -- but no longer
    -- unconditionally, as this comment used to claim: LC.HandleRollCatchup puts a stamp it saved back
    -- afterwards, on purpose, because a repair can land minutes after the drop and dating the
    -- four-hour trade window from the repair would promise a hand-over that can no longer happen.
    --
    -- So a reused rollID CAN keep the previous roll's stamp, in the one case where this function is
    -- blind anyway: a catch-up finds nothing tracked under the ID and returns below at "nothing
    -- tracked", with no old link to compare. Accepted, because the error only ever runs one way. A
    -- preserved stamp is older than the true drop, never newer, so the reminder ends early rather than
    -- late -- and an early end to a promise about a trade is the safe direction. Age bounds it
    -- regardless: see Trade.PruneExpiredLootStamps for why the stamp outlives Trade.ClearRollState.
    -- NOTHING THAT ENTERED A BATCH MAY DISAPPEAR UNSENT, and this is the one place that could take
    -- something out of one.
    --
    -- Reaching here means the number is being REUSED, so an entry still waiting out the collection
    -- window under it (LC.pendingDrop) is the previous item's -- and Trade.ClearRollState below takes
    -- it out of the batch along with everything else this client tracks under the id. It would then
    -- never be announced at all: the lootmaster force-won it before the batch was even built, so the
    -- raid would simply never see a card for an item sitting in his bags, with nothing on any screen
    -- to notice it by. Blizzard reusing a number within seconds is exactly what this function exists
    -- for, so the window is not an exotic place for it to happen.
    --
    -- Flushed rather than kept, because one number cannot carry two items in one message either: the
    -- receiving side runs this same purge, so it would drop whichever of the two it read first. Same
    -- answer as a batch whose head changed (see LC.DrawnKeys) -- an ambiguous batch is
    -- closed and the arriving item opens a new one.
    --
    -- Deliberately HERE and not in Trade.ClearRollState. That function is also how a council member
    -- withdraws an item from an un-sent batch by closing its tab, which is meant to work (see
    -- tests/test_lc_chrome.lua), and it cannot tell "the owner dropped this" from "the number is
    -- being reused". This can.
    local pending = LC.pendingDrop
    if pending then
        for _, e in ipairs(pending.entries) do
            if e.rollID == rollID then LC.FlushPendingDrop() break end
        end
    end

    -- Rolls already cast FOR THE ITEM NOW ARRIVING survive the purge. Everything else about this
    -- rollID belongs to the previous item and goes.
    local keepRolls = (LC.rollsFor[rollID] == newItemID) and LC.rolls[rollID] or nil
    LC.Trade.ClearRollState(rollID)
    if keepRolls then
        LC.rolls[rollID] = keepRolls
        LC.rollsFor[rollID] = newItemID
    end
end
-- Exposed for LC.HandleTable, which sits far above this in the file and now meets the same
-- transition from the other side: the heartbeat names a different item under a number this client
-- still holds, or still remembers dismissing (B132). Called through LC.* rather than forward-declared
-- because the call happens at runtime, long after both halves have loaded.
LC.PurgeStaleRoll = PurgeStaleRoll

-- How often LC.OnStartLootRoll re-checks for the item link before giving up, and the per-attempt
-- backoff — same schedule as ResolveRollItemLink, for the same reason (see the retry block there).
--
-- Deliberately long. The old budget was eight attempts at a quarter-second step — about seven
-- seconds — after which the handler returned having done NOTHING AT ALL: no force-win, no forced
-- pass, no LC_START, no vote window anywhere. The boss dropped and nothing happened, on every client
-- in the raid, with nothing printed. Blizzard's own roll timer runs for minutes, so waiting longer
-- costs nothing and is far more likely to work than any guess: deciding without the link would mean
-- deciding without a classID, and a freshly dropped MOUNT would then read as ordinary gear and be
-- force-won — the exact thing the standing rule forbids, and how housing decor was won once already.
local START_ROLL_MAX_ATTEMPTS = 20
local START_ROLL_RETRY_STEP   = 0.25
local START_ROLL_RETRY_MAX    = 2

-- ==========================================================================
--  B63: one broadcaster, and Auto-Pass that did not depend on it
-- ==========================================================================
--
-- A real drop is announced from exactly one place, the LC_DROP the loot owner's own START_LOOT_ROLL
-- handler collects the item into. The owner is subject to the same conditions as everyone else -- out of
-- range, dead, released, ineligible -- and there is no second broadcaster. Auto-Pass, meanwhile, ran
-- on every other client whether or not the owner had acted, so the whole raid passed on an item
-- nobody had force-won: the item went to whichever raider is NOT running KART, or to nobody at all,
-- and no vote window opened anywhere.
--
-- A fallback broadcaster was considered and rejected. Announcing an item the owner never rolled on
-- produces a vote whose winner can never be handed the item -- a decision nobody can execute, which
-- is the same trap the collectible carve-out exists to avoid. What is safe is the other direction:
-- pass only once the council has actually taken the item up, and otherwise leave Blizzard's window
-- alone so the raid can roll on it the way it would without this addon.
--
-- Known cost, accepted deliberately: a client whose LC_START was swallowed by the chat throttle now
-- keeps its roll window instead of passing, so an Auto-Pass raider could in principle click Need on
-- an item the lootmaster has already force-won. Bounded -- the owner rolled Need too, and an
-- Auto-Pass raider is by definition someone who does not click loot windows -- and much smaller than
-- an item silently lost by the whole raid passing at once. B66's catch-up covers the deaf client
-- when a state request follows.
LC.rollAnnounced = LC.rollAnnounced or {} -- [rollID] = true once the LOOT OWNER's LC_START landed here
LC.rollSeenHere  = LC.rollSeenHere  or {} -- [rollID] = true once WE have processed our own START_LOOT_ROLL

-- Rolls Blizzard raised on this client while it did not yet know a session was running, so that
-- LC.OnStartLootRoll can be run for them once it does. See LC.ReplaySeenWhileUnaware.
--
-- Why this is needed at all: LC.OnStartLootRoll returns on its second line while LC.sessionActive is
-- false, and that early return is the ONLY writer of LC.rollSeenHere -- which AutoPassAnnounced
-- requires. LC.HandleStart has no such gate, so the announcement still builds a vote row. The result,
-- reported from a live raid on 2026-08-05: a raider whose client restarted mid-session had four vote
-- rows, a status line reading "Session: on (told)", and four unanswered Blizzard roll windows, with
-- nothing anywhere saying why. Every reload, every disconnect and every relog inside a session lands
-- in this window; the state request that closes it takes seconds (see STATE_REQ_BACKOFF), and a boss
-- dying inside those seconds used to cost the whole round's auto-passing.
--
-- An in-flight marker, not state: deliberately not persisted across a reload (the roll windows are
-- gone with the client anyway) and not in ClearRollState.
LC.rollsSeenWhileUnaware = LC.rollsSeenWhileUnaware or {}

-- How many of them to hold at once. A client sitting in a raid with no session running still sees
-- every BoP roll of the evening, and none of them is worth remembering past the boss it belongs to.
-- Well above what a boss can drop, far below anything that matters as a table.
local SEEN_WHILE_UNAWARE_MAX = 40

-- [rollID] = the identity key of whoever announced this item to us. NOT the same question as "who
-- hands out the loot": that one is about the raid right now, this one is about a moment in the past,
-- and the numbers belong to that moment. Keeping them apart is what stops a client that disagrees
-- about the current lootmaster from also disagreeing about the rolls (B130).
LC.rollAnnouncedBy = LC.rollAnnouncedBy or {}

-- How long to wait for that announcement before saying it never came. Derived from the owner's own
-- link retry above rather than picked: they can legitimately spend that whole budget before sending
-- anything, and a message that fires on a raid which was merely slow is worse than no message.
local ANNOUNCE_WAIT = START_ROLL_MAX_ATTEMPTS * START_ROLL_RETRY_MAX + 5

-- Runs the roll handler for everything that arrived while this client did not know there was a
-- session (see LC.rollsSeenWhileUnaware). Called the moment the state stops being a guess -- from
-- LC.SetSessionActive, which is us deciding, and from LC.HandleActive, which is being told.
--
-- Idempotent by construction: the list is taken and emptied before anything runs, and
-- LC.OnStartLootRoll is safe to run twice for one roll anyway (Blizzard re-raises START_LOOT_ROLL for
-- a roll still in progress, which is the same call).
-- Only rolls the council has demonstrably taken up, which is the same condition Auto-Pass itself
-- answers to (B63) -- and, less obviously, the thing that keeps this repair from breaking the
-- catch-up. LC.HandleRollCatchup refuses a roll this client already has an item for, and
-- LC.OnStartLootRoll writes LC.rollItems: replaying a roll whose announcement had NOT arrived left
-- the client holding the item with no vote row and no way to be sent one, which is worse than the
-- missing pass. With the announcement already in, LC.HandleStart has written those tables anyway and
-- the replay adds nothing but the flag it exists for.
--
-- A roll still waiting for its announcement therefore stays in the list, and LC.HandleStart picks it
-- up from there when the announcement lands.
local function ReplayOne(rollID)
    if not LC.rollAnnounced[rollID] then return false end
    LC.rollsSeenWhileUnaware[rollID] = nil
    -- Only rolls that are still live. A nil texture means Blizzard's window is gone -- expired, or
    -- answered by hand in the meantime -- and there is nothing left to pass or force-win.
    if GetLootRollItemInfo(rollID) then LC.OnStartLootRoll(rollID) end
    return true
end

function LC.ReplaySeenWhileUnaware(rollID)
    if not LC.sessionActive then return end
    if rollID then ReplayOne(rollID) return end
    -- Sorted, so a client replaying three rolls handles them in the order they dropped rather than
    -- in table order, which differs between clients.
    local ids = {}
    for id in pairs(LC.rollsSeenWhileUnaware) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do ReplayOne(id) end
end

-- Passes Blizzard's roll for a council item, but only once the owner has announced it. Called from
-- both roll-start paths: whichever of the two runs SECOND is the one that finds both halves true, so
-- the order the event and the message arrive in does not matter.
local function AutoPassAnnounced(rollID)
    if not KART_Settings.lcAutoPass then return end
    if not LC.rollAnnounced[rollID] then return end
    -- The owner force-wins instead of passing, and never processes their own LC_START anyway.
    if LC.IsLootOwner() then return end
    -- Not before this client has run its OWN roll handler. Answering a roll makes Blizzard's API go
    -- blank for it, so passing from a message that beat the local event -- which the harness produces
    -- and the game may -- left OnStartLootRoll with no quality, no bind flag and no link, so it bailed
    -- at the council-eligibility test and skipped the 1-100 roll entirely. Whichever path runs second
    -- passes; this is what makes "second" mean second.
    if not LC.rollSeenHere[rollID] then return end
    -- No roll of our own to answer: this client was never eligible, or has already answered it.
    -- GetLootRollItemInfo goes blank in both cases, which is what keeps this from passing twice.
    if not GetLootRollItemInfo(rollID) then return end
    RollOnLoot(rollID, 0)
end

-- Armed by a non-owner when a council item drops; says so if the announcement never arrives.
-- Only for Auto-Pass users: they are exactly the people whose expectation -- "KART deals with loot
-- windows for me" -- has quietly not been met, and who are now looking at a window they have to
-- answer themselves. Anyone else was going to click it regardless and does not need the line.
local function WaitForAnnouncement(rollID, link)
    if not KART_Settings.lcAutoPass then return end
    C_Timer.After(ANNOUNCE_WAIT, function()
        if LC.rollAnnounced[rollID] then return end
        -- Blizzard reuses rollIDs within seconds (see PurgeStaleRoll). Naming the wrong item is
        -- worse than saying nothing.
        if LC.rollItems[rollID] ~= link then return end
        -- Gone: expired, or answered by hand in the meantime. Nothing left to explain.
        if not GetLootRollItemInfo(rollID) then return end
        print("|cffff0000KART:|r " .. string.format(KART.L.LC_ROLL_UNANNOUNCED, link or "?"))
    end)
end

-- attempt is internal (see the link-retry block below); Core.lua's START_LOOT_ROLL handler passes
-- only rollID.
-- What has dropped since the window opened, and when it closes. A boss hands its items over in one
-- moment, so the first one starts a short window and whatever else arrives inside it goes into the
-- same message. Half a second is chosen against what it costs: this message carries ALERT because the
-- raid is waiting for it, but half a second is nothing next to what the encounter restriction holds
-- back anyway, and the raid is looking at Blizzard's own roll windows in exactly that moment.
--
-- A single item waits too. One code path, one format, and the shared participant list applies always.
local DROP_COLLECT = 0.5
-- { id = n, secs = n, keys = {…}, entries = { { rollID = n, rolls = {…}, itemString = s }, … } }
LC.pendingDrop = nil
local pendingDropSeq = 0

-- Whether this roll's own head is the one the batch already names. Both sides come from
-- LC.DrawnKeys, so this compares like with like -- two sorted lists, walked -- rather than a snapshot
-- against a head, which is the comparison that went wrong three times. See the invariant on
-- LC.DrawnKeys for why they can differ inside one boss's half second at all.
local function SameHead(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- id: the batch this timer was armed for. A batch flushed EARLY (its participants changed, see
-- OnStartLootRoll) leaves its own timer behind, and that timer must not cut the next batch's window
-- short. Called without an id -- the split path, and LC.FlushPendingDrop -- it flushes whatever is
-- pending, which is exactly what those callers mean.
local function FlushPendingDrop(id)
    local drop = LC.pendingDrop
    if id and (not drop or drop.id ~= id) then return end
    LC.pendingDrop = nil
    if not drop or #drop.entries == 0 then return end
    -- Before the send, and that is a deliberate change of order -- the old block called this AFTER
    -- both of its sends. A receiver's expiry sweep is started by the announcement it receives, so the
    -- sweep and this heartbeat are two tickers of the same period anchored to the same instant, and at
    -- a vote window that is a whole number of heartbeats (the default 20s against 10s) they fall due on
    -- the same second for the rest of the round. Which of them runs first is decided by which was
    -- created first, and sweep-first is the bad half: the client frees the roll, the heartbeat a
    -- moment later finds it missing, it asks, and the owner hands back an item it was about to expire
    -- anyway. Creating the heartbeat first puts it on the safe side of every one of those collisions.
    LC.EnsureTableTicker()
    LC.SendLC(LC.SerializeDrop("r", drop.secs, drop.keys, drop.entries))
end
LC.FlushPendingDrop = FlushPendingDrop

function LC.OnStartLootRoll(rollID, attempt)
    if KART_Settings.lcModuleEnabled == false then return end
    if not LC.sessionActive then
        -- Remember it instead of forgetting it. Everything below -- the force-win, the announcement,
        -- Auto-Pass, and above all LC.rollSeenHere -- is unreachable until the session is known, and
        -- the roll window Blizzard put on screen outlives that wait by minutes. See
        -- LC.rollsSeenWhileUnaware for what this cost in a live raid.
        --
        -- Counted rather than measured with # : the table is keyed by rollID, so it is not a
        -- sequence, and dropping the oldest is not possible without an order nobody has. Once it is
        -- full the newest is dropped instead, which is the safe direction -- a client that has been
        -- collecting forty of these is not in a session at all.
        local n = 0
        for _ in pairs(LC.rollsSeenWhileUnaware) do n = n + 1 end
        if n < SEEN_WHILE_UNAWARE_MAX then LC.rollsSeenWhileUnaware[rollID] = true end
        return
    end

    -- Quality/bind data first — the lootmaster branch below depends on it. bindOnPickUp comes
    -- from GetLootRollItemInfo (reliable even for uncached items); classID via GetItemInfoInstant,
    -- which needs the link (GetItemInfo returns nil until the item is cached, GetItemInfoInstant
    -- doesn't, but both need something to look the item up by).
    -- First return is the TEXTURE, not the name — used here purely as an "is this roll still live?"
    -- probe for the retry below (it goes nil once the roll expires or has been rolled).
    local rollTexture, _, _, quality, bindOnPickUp = GetLootRollItemInfo(rollID)
    local itemLink = GetLootRollItemLink(rollID)

    -- The link can be nil for a moment right at roll start, most often for a brand-new item whose
    -- data hasn't propagated client-side yet (see ResolveRollItemLink). Deciding without it would
    -- silently break the collectible carve-out below: with no link there's no classID, a freshly
    -- dropped MOUNT would read as ordinary Bind-on-Pickup gear, and KART would force-win it for the
    -- lootmaster while every Auto-Pass client passed on it — the exact outcome the standing rule
    -- forbids, and inconsistent across the raid since only some clients would still be waiting.
    -- So retry instead of guessing. Blizzard's roll timer runs for minutes, so the few hundred ms
    -- cost nothing. A nil texture means the roll itself is gone (expired or already rolled) — stop.
    if rollTexture and not itemLink then
        attempt = attempt or 1
        if attempt < START_ROLL_MAX_ATTEMPTS then
            C_Timer.After(math.min(START_ROLL_RETRY_STEP * attempt, START_ROLL_RETRY_MAX), function()
                LC.OnStartLootRoll(rollID, attempt + 1)
            end)
        elseif LC.IsLootOwner() then
            -- Out of attempts, and the roll is still live. There is nothing safe left to do — the
            -- item cannot be identified, so it cannot be told apart from a mount — but the loot
            -- owner has to know an item went past the council rather than find out from a raider
            -- afterwards. Blizzard's own window is still up for everybody; this says so.
            print("|cffff0000KART:|r " .. KART.L.LC_ROLL_UNIDENTIFIED)
        end
        return
    end

    local itemID, classID, subclassID
    if LC.IsRealItemLink(itemLink) then
        local iid, _, _, _, _, cid, scid = C_Item.GetItemInfoInstant(itemLink)
        itemID, classID, subclassID = iid, cid, scid
    end
    local isCollectible = LC.IsCollectibleItem(itemID, classID, subclassID)

    -- Two tiers, and the outer one decides whether KART touches this roll AT ALL.
    --
    -- STANDING DECISION (maintainer, 2026-07-25): collectibles — mounts, pets, toys, housing items —
    -- and Bind-on-Equip drops must NEVER enter Loot Council, under any rarity. This is deliberate,
    -- not an oversight: do not re-flag it, and do not "fix" it by letting the council vote on a mount
    -- again. Anything that changes which items reach Council has to keep this rule.
    --
    -- councilEligible = Bind-on-Pickup, non-collectible gear. Collectibles and anything that isn't
    -- BoP are deliberately outside the whole addon: Blizzard's own roll window handles them exactly
    -- as it would without KART — no force-win, no forced pass, and Auto-Pass stays out of it too.
    -- The lootmaster can't hand out through the BoP trade window what he never physically holds, so
    -- running Council on those produced a decision nobody could execute (the mount went to whoever
    -- won Blizzard's roll) plus a trade reminder for an item that was never in his bags. And since
    -- Auto-Pass is ON by default, force-passing them for every KART user would have handed each
    -- mount to whichever raider ISN'T running the addon.
    --
    -- councilEngages narrows that further by the raid's rarity threshold. Auto-Pass deliberately
    -- ignores THAT one — a raider's "don't make me click loot windows" preference is their own call,
    -- not the raid leader's (reviewed; do not re-tie Auto-Pass to min quality).
    --
    -- ONE NAMED EXCEPTION, and it is an exception to both halves of the rule above (maintainer,
    -- 2026-08-06, out of #34): a RECIPE goes to Council whatever it is bound as, and whatever the
    -- raid's minimum quality says. In this guild a recipe always ends up with the lootmaster, and
    -- until now nothing made that happen -- the Bind-on-Equip rule kept every one of them out, so
    -- the vote window had nothing to show and the reporter had nothing to click.
    --
    -- The quality half of the carve-out is not tidiness: most recipes are Rare, the raid's threshold
    -- is Epic, and without it the exception would do nothing for exactly the items it was asked for.
    --
    -- It costs the guarantee the rule was written for, and the cost is stated rather than hidden: a
    -- raider not running KART can still win Blizzard's roll on a recipe, and then the lootmaster does
    -- not hold it and the council decides something nobody can hand over. Accepted because KART is
    -- mandatory here -- an assumption about people, not a guarantee from the code. If that ever stops
    -- holding, this is the first line to re-examine.
    local isRecipe        = classID == ITEM_CLASS_RECIPE
    local councilEligible = (bindOnPickUp or isRecipe) and not isCollectible
    local councilEngages  = councilEligible
                            and (isRecipe or not (quality and quality < LC.GetRaidMinQuality()))

    -- Set before the branch below, because the Auto-Pass arm consults it (see AutoPassAnnounced), and
    -- only for rolls the council actually tracks -- those are the ones LC.Trade.ClearRollState and
    -- LC.ClearAllRolls sweep, and an entry for anything else would never be collected.
    if councilEngages then LC.rollSeenHere[rollID] = true end

    -- IsLootOwner, not a bare lootmaster test: while no lootmaster is configured the raid leader
    -- stands in and holds the items instead (see LC.IsLootOwner).
    local isLootmaster = LC.IsLootOwner()
    if isLootmaster and councilEngages then
        -- The lootmaster physically wins everything Council decides on, so he can hand it over
        -- through Blizzard's BoP trade window afterwards.
        ForceWinRoll(rollID)
        -- We rolled Need on it ourselves, so from here on this roll counts as ours to hand out even
        -- if a previous round left a stale mark under the same rollID (Blizzard reuses them).
        LC.rollNotInOurBags[rollID] = nil
    elseif isLootmaster and councilEligible then
        -- Council-eligible but below the rarity threshold: nothing for him to hand out, and it
        -- shouldn't pile up in his bags either. Always passes, deliberately independent of his own
        -- Auto-Pass setting.
        RollOnLoot(rollID, 0)
    elseif KART_Settings.lcAutoPass and councilEligible and not councilEngages then
        -- Below the raid's rarity threshold: the council never announces these, so there is nothing
        -- to wait for and the lootmaster passes on them too.
        RollOnLoot(rollID, 0)
    elseif KART_Settings.lcAutoPass and councilEngages then
        -- An item the council WILL take up -- but only once it demonstrably has (B63). If the owner's
        -- announcement came in first this passes right here; if it has not arrived yet, HandleStart
        -- does it when it does; if it never arrives, we deliberately never pass.
        AutoPassAnnounced(rollID)
    end

    -- Not Council's business (collectible, BoE, or below the raid-wide minimum rarity): let
    -- Blizzard's own roll UI handle it, untouched.
    if not councilEngages then return end

    local newItemID = LC.IsRealItemLink(itemLink) and (itemLink:match("item:(%d+)") or "") or ""
    PurgeStaleRoll(rollID, newItemID)

    -- Blizzard's Bind-on-Pickup trade window opens the moment the item is looted, not whenever
    -- Council later decides a winner — LC.CheckTradeTimeouts and Trade.RestorePersistedTrades both
    -- measure from this stamp. Taken on EVERY client, not just the lootmaster's: the winner's own
    -- "you're owed this" entry (Trade.HandleResult) needs the same clock, and only clients that saw
    -- the roll start know when that was — it used to fall back to time() at award time there, which
    -- started the 4-hour countdown minutes late and kept dead entries alive across a reload.
    -- time() (wall clock), NOT GetTime() (seconds since client start): these stamps are persisted,
    -- and GetTime() resets to ~0 on every reload, which would make a restored entry look freshly looted.
    LC.rollLootedAt = LC.rollLootedAt or {}
    LC.rollLootedAt[rollID] = time()

    -- Keep any still-valid link we already had if this event's link is unresolved (PurgeStaleRoll
    -- above deliberately didn't purge on unresolved data) — clobbering it with "???" would blank a
    -- roll that was showing fine. Mirrors HandleStart's fallback chain.
    LC.rollItems[rollID] = itemLink or LC.rollItems[rollID] or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
    LC.votes[rollID]     = LC.votes[rollID] or {}

    -- The announcement and the roll table travel together in LC_DROP: a client that never gets its
    -- own START_LOOT_ROLL (dead, out of range, ineligible, or its session/min-quality state made
    -- OnStartLootRoll return early) only learns the roll exists from that message.
    --
    -- Sent by the LOOT OWNER, not the raid leader (see LC.IsLootOwner). Exactly one client
    -- broadcasts, so no duplicate tabs: while a lootmaster is configured it's them, otherwise the
    -- leader. Tying this to the leader meant a leader who reloaded mid-raid (sessionActive back to
    -- false until they re-answered the prompt) silently stopped every roll broadcast for the whole
    -- raid, while the lootmaster kept force-winning items nobody could vote on.
    local secs = KART_Settings.lcVoteSeconds or 20
    if isLootmaster then
        -- Who is standing here right now, before anything else: this is what decides later who may be
        -- handed this roll after missing its announcement, and who joined too late for it (B118).
        SnapshotEligible(rollID)
        -- The sender does not process its own announcement (KASC drops the echo, see Dispatch), so
        -- this client records its own the moment it decides to make it.
        LC.rollAnnouncedBy[rollID] = (KASC.Identity.ResolvePlayer("player"))
        -- Silent: the numbers ride inside LC_DROP, next to the participant list they are ordered by.
        LC.DrawRollTable(rollID, newItemID, true)

        -- The head this item's numbers require, taken FROM those numbers (see the invariant on
        -- LC.DrawnKeys) and not from LC.rollEligible[rollID]. A re-raised START_LOOT_ROLL re-snapshots
        -- the roster a line above while LC.DrawRollTable keeps the table it has already shown the
        -- raid, so the snapshot is the one thing here that is allowed to be out of date.
        --
        -- The numbers come back with it and travel in the entry (B135): the message is serialized
        -- when the window closes, and LC.rolls[rollID] is not guaranteed to still be this client's
        -- table by then.
        local keys, rolls = LC.DrawnKeys(rollID)

        -- This item's own head against the one the batch already names. They can differ inside one
        -- boss's half second, and the message cannot carry both -- so the batch is closed here and
        -- this item opens a new one. Split rather than reconciled: two messages are cheap, and the
        -- alternative is a number attributed to the wrong raider.
        if LC.pendingDrop and not SameHead(keys, LC.pendingDrop.keys) then
            FlushPendingDrop()
        end

        if not LC.pendingDrop then
            pendingDropSeq = pendingDropSeq + 1
            local id = pendingDropSeq
            LC.pendingDrop = { id = id, secs = secs, keys = keys, entries = {} }
            C_Timer.After(DROP_COLLECT, function() FlushPendingDrop(id) end)
        end

        local entry = {
            rollID = rollID,
            rolls = rolls,
            -- The full string, not LC.ItemPayload's cap-driven fallback: this message is split and
            -- reassembled by the transport, so there is no 255-byte cliff to degrade against, and a
            -- bare itemID would lose the bonus ids B119 is about.
            itemString = KAUtil.GetItemString(itemLink) or LC.ItemPayload(itemLink, newItemID),
        }
        -- Replaced, not appended a second time. Blizzard re-raises START_LOOT_ROLL for a roll that is
        -- still running, and LC.DrawRollTable's own guard returns before redrawing -- but nothing here
        -- would stop the same rollID being serialized twice in one message, which is duplicated bytes
        -- and nothing else -- there is no second timer of any kind this could start.
        --
        -- Only ever the SAME item reaches this: a re-raise carrying a different one is the number being
        -- reused, and PurgeStaleRoll has already closed the batch over it a few lines up rather than
        -- let one number carry two items. So replacing and skipping are the same thing here, and
        -- replacing is written because it stays correct if that ever stops being true.
        local entries = LC.pendingDrop.entries
        for i = 1, #entries do
            if entries[i].rollID == rollID then entries[i] = entry entry = nil break end
        end
        if entry then entries[#entries + 1] = entry end
    end

    -- Nobody but the owner broadcasts, so a non-owner has no way of knowing the difference between
    -- "the announcement is still coming" and "it is never coming" except by waiting (B63).
    if not isLootmaster then WaitForAnnouncement(rollID, LC.rollItems[rollID]) end

    -- The broadcaster does not process their own LC_START, so they open their own windows here —
    -- same treatment HandleStart gives every other client, gated the same way (council gets the
    -- panel, everyone gets the vote popup), otherwise the loot owner would be the one council
    -- member who couldn't cast their own vote.
    if isLootmaster then
        if LC.IsCouncil() then
            KART.LC.Council.ShowCouncilPanel(rollID, secs)
        end
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs)
    end
end

-- [rollID] = true when we learned this roll existed from somebody else's LC_START rather than from
-- our own force-win. It is the one thing that separates "I am the loot owner" from "I am holding
-- this item", and those are not the same client as soon as the role moves mid-round -- which is the
-- normal case here, not an edge one: the lootmaster ports out during distribution and the raid
-- leader stands in. See the trade-obligation guards in LootCouncilTrade.lua.
--
-- Deliberately records the NEGATIVE. A table of "rolls I won" would be empty after a reload and the
-- lootmaster would silently stop getting trade reminders for items genuinely in their bags; an empty
-- table here means "assume held", which is exactly what the code did before this existed.
LC.rollNotInOurBags = LC.rollNotInOurBags or {}

-- ==========================================================================
--  The lootmaster losing Blizzard's roll (B60)
-- ==========================================================================
--
-- ForceWinRoll rolls Need and never reads the outcome. A raider not running KART can out-roll the
-- lootmaster: the council still awards, Trade.AddPendingTrade records an obligation for an item the
-- lootmaster does not have, and Trade.OnTradeClosed later reads "not in my bags" as "already traded"
-- and tidies the reminder away. The lootmaster believes it is done, the winner never receives
-- anything, and the loot history says they won it.
--
-- The outcome IS readable: C_LootHistory carries the winner of every drop, and
-- LOOT_HISTORY_UPDATE_DROP fires when one resolves. What it does not carry is Blizzard's rollID --
-- the loot-history id space (encounterID + lootListID) and the group-loot rollID never meet, not in
-- this addon and not in Blizzard's own LootHistory frame, which works purely in the former. So the
-- match is on the item link.
--
-- Which is why this only ever SAYS something. Two identical tokens off one boss would match the same
-- link, and marking the wrong roll as not-held would take a trade reminder away from an item the
-- lootmaster really is holding -- turning a rare miss into a routine one. A false positive here costs
-- a glance in the bags; a false negative is exactly the state before this existed. Nothing about the
-- distribution is decided from here.
LC.lostRollReported = LC.lostRollReported or {} -- ["encounterID:lootListID"] = true, one line per drop

function LC.HandleLootHistoryDrop(encounterID, lootListID)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    -- Only the person who force-wins has anything to lose here.
    if not LC.IsLootOwner() then return end

    local key = tostring(encounterID) .. ":" .. tostring(lootListID)
    if LC.lostRollReported[key] then return end

    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    -- No winner yet, everybody passed, or we won it after all: nothing to report in any of those.
    if not (info and info.winner) or info.winner.isSelf then return end
    local link = info.itemHyperlink
    -- Compared as an item STRING, never as a raw link. The two sides come from different producers
    -- -- ours from GetLootRollItemLink, theirs from C_LootHistory -- and a link carries a colour
    -- escape and a display name that different client versions write differently (see
    -- KAUtil.GetItemString, and the shift-click forms documented next to it). Raw equality would
    -- make this feature a silent no-op on any client whose escape does not match ours, which is
    -- indistinguishable from the state before it existed and so would never be reported.
    local wanted = KAUtil.GetItemString(link)
    if not wanted then return end

    -- Two records can say "this client force-won that item", and the obvious one is not enough on
    -- its own: Vote.PruneExpiredRolls frees LC.rollItems once the VOTE window is over -- twenty
    -- seconds by default -- for any client that holds no council tab for the roll, and tabs exist
    -- only for council members. A lootmaster who is not in the council list is an ordinary setup,
    -- and Blizzard resolves its roll long after that. The trade obligation outlives both: it is the
    -- promise this warning is actually about, it carries the item link, and it lives for the four
    -- hours the trade window does.
    local function HeldByUs()
        -- rollNotInOurBags records the NEGATIVE (see the comment above it), so "not marked" is what
        -- "we force-won this" looks like.
        for rollID, tracked in pairs(LC.rollItems or {}) do
            if KAUtil.GetItemString(tracked) == wanted and not LC.rollNotInOurBags[rollID] then
                return true
            end
        end
        for _, entry in ipairs(LC.pendingTrades or {}) do
            if KAUtil.GetItemString(entry.itemLink) == wanted then return true end
        end
        return false
    end

    if not HeldByUs() then return end
    LC.lostRollReported[key] = true
    print("|cffff0000KART:|r " .. string.format(KART.L.LC_FORCEWIN_LOST,
        link, info.winner.playerName or "?"))
end

LC.votedByMe = LC.votedByMe or {} -- [rollID] = the buttonIdx WE cast (truthy = voted; tracked by
                                   -- rollID, not by row, since rows get recycled/reindexed as items expire)
-- [rollID] = the button-set fingerprint OUR vote was cast against (B45). Without it the voter's own
-- badge is resolved against whatever the list says now, so a mid-roll label edit told them they had
-- voted something they never did.
LC.votedFpByMe = LC.votedFpByMe or {}
LC.votedNoteByMe = LC.votedNoteByMe or {} -- [rollID] = the note text WE typed before voting, kept
                                   -- around purely so the "you voted" state can still show it —
                                   -- otherwise it vanishes the moment the note box hides, even
                                   -- though the raider clearly remembers writing it.

-- rollID -> shortName of whoever this roll has already been awarded to (guards against accidental
-- double-assignment when the assign menu is used more than once for the same item).
LC.assignedWinners = LC.assignedWinners or {}
-- [rollID] = true when the winner above was set by a DELIBERATE reassignment -- somebody read a
-- dialog naming both players and confirmed. It is the rank the clash rule in Trade.HandleResult
-- compares (B35), and the one thing a receiver cannot work out for itself.
LC.assignedDeliberate = LC.assignedDeliberate or {}

KART.UI:RegisterStaticPopup("KART_LC_REASSIGN_CONFIRM", { ---@diagnostic disable-line: undefined-global
    text = "Already assigned.", -- unconditionally overwritten with KART.L.LC_REASSIGN_CONFIRM_TEXT in LC.Trade.AssignWinner below
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
})

-- =====================================================================
--  Addon Message Handlers  (called from Core.lua CHAT_MSG_ADDON)
-- =====================================================================

function LC.HandleActive(value, senderKey)
    -- Only the loot owner may flip the session flag (see LC.IsLootOwner) — otherwise any group
    -- member could turn Loot Council off for the whole raid with a forged LC_ACTIVE. On a client
    -- that hasn't received a config yet the lootmaster reads "" and IsSenderLootOwner falls back to
    -- the leader, which is the bootstrap path anyway.
    if not LC.IsSenderLootOwner(senderKey) then LC.diag.refusedSender = LC.diag.refusedSender + 1 return end
    local wasActive = LC.sessionActive
    LC.sessionActive = (value == "1")
    -- The owner told us, so our flag is an answer now (see LC.sessionStateKnown).
    LC.sessionStateKnown = true
    -- ...and a config we were holding back for want of an answer is no longer a guess: either this
    -- raid has an owner other than us, in which case IsConfigOwner says no anyway, or it does not
    -- and ours stands (B69).
    -- Told, not decided: this is somebody else's session, so the raid-leader fallback in
    -- LC.IsConfigOwner must not push our own settings over whatever the raid already agreed.
    LC.sessionStartedByUs = false
    -- A session started elsewhere makes our own "start one?" question obsolete; leaving the dialog
    -- up invites someone to answer a question that no longer applies.
    if LC.sessionActive then LC.HideSessionPrompt() end
    -- The moment this client stops guessing. Anything Blizzard raised a roll window for while it was
    -- still asking is picked up here -- the reload/relog/disconnect case, which is most of them.
    if LC.sessionActive then LC.ReplaySeenWhileUnaware() end
    -- A peer receiving the owner's session-end must also drop its tracked rolls and close its
    -- windows, exactly like the owner's own SetSessionActive(false) — otherwise stale tabs, votes
    -- and a leftover /kart showall override survive into the next session.
    if wasActive and not LC.sessionActive then
        LC.ClearAllRolls()
        -- Same reasoning as LC.SetSessionActive(false): a pending B12 retry belongs to the session
        -- that just ended (see LC.RetryPendingConfig).
        LC.CancelPendingConfig()
    end
    -- No "and if we own the config, broadcast it" branch here, deliberately: config ownership and
    -- loot ownership can never be split across two people. LC.IsConfigOwner() true means our own
    -- lcLootmaster names US, which makes LC.GetLootmaster() return our own key, which makes the
    -- IsSenderLootOwner check above reject every sender but ourselves — and we do not process our own
    -- messages. So such a branch is unreachable by construction. The config reaches the raid from
    -- LC.SetSessionActive (sent before LC_ACTIVE) and LC.HandleStateRequest instead.
end

-- Peer side of LC.EndRound. Same authority as LC_ACTIVE (see LC.HandleActive) — only the loot
-- owner may wipe every tracked roll/tab/vote/winner-highlight in the raid with one click.
--
-- A v3.0.0 client has no handler for this token at all: KASC's dispatcher silently drops an
-- unrecognized token (see its handler lookup), so that client's cards simply never clear — it
-- keeps showing whatever it was already tracking until its own session ends or it upgrades.
-- Accepted from any COUNCIL member, not just the loot owner (B57, GitHub #15).
--
-- The two sides judged this differently and both stayed silent about it. The button is enabled by
-- the presser's own LC.IsLootOwner, which falls back to the raid leader whenever their client has no
-- config naming somebody else -- normal after a reload while the config is slow, or in a raid where
-- it never reached them. Their peers judge the incoming message with IsSenderLootOwner, and THEY do
-- have a config naming the real lootmaster, so they rejected it. The presser's own window cleared,
-- every other window kept the previous boss's items, and nothing was printed anywhere.
--
-- Council rather than loot owner is the right width for what this does: it clears the current
-- round's tabs and vote rows and does not touch the session, and a council member can already assign
-- an item outright, which is far more authority than clearing a list. IsSenderCouncil accepts the
-- loot owner too, so this is strictly wider than what it replaces.
function LC.HandleEndRound(senderKey)
    if not LC.IsSenderCouncil(senderKey) then LC.diag.refusedSender = LC.diag.refusedSender + 1 return end
    LC.ClearAllRolls()
end

-- Returns whether the payload described an item this client could act on AT ALL -- which is what
-- LC.HandleDrop needs to know before applying the numbers that travelled beside it in the same entry.
--
-- Deliberately NOT "was the announcement accepted". A refusal on OWNERSHIP grounds still answers yes,
-- because the numbers have their own, weaker rule for exactly that case and it is load-bearing: see
-- the "fills a void, never replaces" arm of LC.HandleRolls. A client whose ownership view disagrees
-- with the real owner's refuses the announcement here and would then be left with no numbers for that
-- item, permanently, since the heartbeat that could prompt it to ask again gates on the same check
-- (B129, B131 -- and tests/test_lc_rolltable.lua holds that disagreement open on purpose). The two
-- halves of one message therefore share one verdict about what the message SAID, and keep their own
-- answers about who may say it, which is the design and not an oversight.
function LC.HandleStart(payload, senderKey)
    -- Only the loot owner announces a drop (see OnStartLootRoll; it arrives inside LC_DROP, or as a
    -- catch-up for one item) — reject forgeries that would pop fake vote windows on every client.
    if not LC.IsSenderLootOwner(senderKey) then
        LC.diag.refusedSender = LC.diag.refusedSender + 1
        return true
    end
    -- payload = "rollID:seconds:item", where item is the full item string ("item:249326::…:11946,…")
    -- since 3.3.1 and a bare itemID before it. Both are accepted: during a rollout the raid runs both
    -- builds for an evening, and refusing the old shape would take the item away from everyone still
    -- on it — the exact failure this whole message is being changed for.
    local rollID, secs, itemPart = payload:match("^(%d+):(%d+):?(.*)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID then return false end
    itemPart = itemPart or ""
    -- The bare id is what everything downstream compares on (PurgeStaleRoll, the duplicate ordinal,
    -- the stale-result guards); the string is what the item is REBUILT from.
    local itemID = LC.PayloadItemID(itemPart)
    local itemString = (itemPart:match("^item:") and itemPart)
        or (itemID ~= "" and ("item:" .. itemID))
        or nil

    PurgeStaleRoll(rollID, itemID)

    -- Somebody else announced this item, which means they are the one who force-won it, not us. If
    -- the loot role later moves to this client -- the lootmaster ports out mid-distribution and the
    -- raid leader stands in -- we must not then record a trade obligation for an item that is in
    -- somebody else's bags. See LC.rollNotInOurBags.
    LC.rollNotInOurBags[rollID] = true

    -- Same BoP trade clock as LC.OnStartLootRoll, for clients that never got their own
    -- START_LOOT_ROLL (dead, out of range, ineligible). LC_DROP goes out at most DROP_COLLECT after
    -- the owner's own roll handler collected the item, so it lands within about a second of the
    -- loot — accurate enough for a 4-hour window.
    --
    -- Overwrites unconditionally (this used to keep an existing stamp as "closer to the truth").
    -- The stamp now deliberately outlives the roll it belonged to (see Trade.PruneExpiredLootStamps)
    -- and Blizzard reuses rollIDs, so a stamp already sitting under this ID may well be the PREVIOUS
    -- roll's — PurgeStaleRoll above can only detect that when it still has the old link to compare.
    -- Keeping it would date a brand-new roll from the old one; the accuracy it bought in the normal
    -- case was under a second, since the owner sends LC_DROP within the collection window.
    LC.rollLootedAt = LC.rollLootedAt or {}
    LC.rollLootedAt[rollID] = time()

    LC.votes[rollID]     = LC.votes[rollID] or {}
    -- GetLootRollItemLink answers only for a roll that exists on THIS client, and this handler is
    -- specifically for clients where it does not: dead, released, out of range, or ineligible for
    -- Blizzard's roll. Those clients used to park "???" here, retry the same nil-returning API eight
    -- times and give up — leaving a question-mark icon and no name for the whole vote, reported from
    -- a live raid by three people at once (GitHub #12, #13, #16), and worst on a boss that dropped
    -- the same item twice, where two identical "???" rows cannot be told apart at all.
    --
    -- The payload carried the itemID the entire time; it was parsed above for PurgeStaleRoll and then
    -- thrown away. Rebuild from it, exactly as Trade.HandleResult already does at award time — full
    -- link once the item is cached, bare item string until then, which still renders a name and icon.
    --
    -- Rebuilt from the WHOLE string, not from the id inside it (B119). Asking the client about an
    -- itemID answers with the base version of that item: base item level, base stats, no upgrade — so
    -- every raider who did not get Blizzard's own roll window was voting on a different item than the
    -- one on the floor, and the Droptimizer column next to it stayed empty because that lookup is
    -- variant-exact. The string carries the bonus ids; the id alone never did.
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID]
    if not LC.IsRealItemLink(LC.rollItems[rollID]) and itemString then
        LC.rollItems[rollID] = select(2, C_Item.GetItemInfo(itemString)) or itemString
    end
    LC.rollItems[rollID] = LC.rollItems[rollID] or "???"
    if not LC.IsRealItemLink(LC.rollItems[rollID]) then ResolveRollItemLink(rollID) end

    -- The council demonstrably has this item, which is the whole precondition for passing on it
    -- (B63). Auto-Pass used to run only in OnStartLootRoll, unconditionally; it now runs from
    -- whichever of the two paths completes the pair. A client with no roll of its own -- dead,
    -- released, out of range -- has nothing to pass and AutoPassAnnounced returns without acting.
    LC.rollAnnounced[rollID] = true
    LC.rollAnnouncedBy[rollID] = senderKey
    -- The other half of the reload repair: this client saw Blizzard raise the roll while it still had
    -- no idea a session was running, so its own handler returned early and never set LC.rollSeenHere
    -- -- which AutoPassAnnounced below requires. Now that the announcement is here, that handler can
    -- run for real. Does nothing in the ordinary case, where the list is empty.
    if LC.rollsSeenWhileUnaware[rollID] then LC.ReplaySeenWhileUnaware(rollID) end
    AutoPassAnnounced(rollID)

    -- secs == 0 is a catch-up for an item whose voting time has already run out — reachable since a
    -- roll stays askable for as long as it is tracked rather than only while its timer runs (see
    -- LC.RollTracked). It cannot be handled as "one second left": that would flash a vote row up and
    -- have Vote.PruneExpiredRolls tear the whole roll back down a tick later, taking the numbers that
    -- arrive with it — the repair undoing itself.
    --
    -- What a client actually needs from a closed item is to TRACK it: the link, the roll table that
    -- follows this message, and — if it is council — the tab the decision is made on, since the
    -- council scores AFTER the timer expires. What it must not be handed is a vote it can no longer
    -- cast. So the deadline is set into the past and the vote row is skipped; a council member gets
    -- the item on the panel with its timer already run out, which is exactly what the clients that
    -- were there are looking at.
    -- A clock this item is already running keeps running. The seconds in the payload say how long the
    -- OWNER thinks is left, and every announcement carries them -- including the second and third one
    -- for an item that is already on the table. Blizzard re-raises START_LOOT_ROLL for a roll still in
    -- progress (see LC.DrawRollTable, which has carried its own guard against exactly that for
    -- longer), so the owner announces again and every receiver restarted the countdown.
    --
    -- What that looked like from a raid, reported as #28: "die Items verschwinden immer wieder und
    -- tauchen dann im LC wieder auf, die Zeit wird immer wieder zurückgesetzt". Both halves are this
    -- line. The timer visibly jumped back, and an item whose row had already expired and been swept
    -- (Vote.PruneExpiredRolls) was handed a fresh twenty seconds and reappeared -- on a screen where
    -- the raider had finished with it.
    --
    -- Safe to trust a surviving deadline: PurgeStaleRoll ran above, and for a rollID Blizzard reused
    -- for a DIFFERENT item it has already cleared this table via Trade.ClearRollState. So a deadline
    -- still standing here belongs to the item being announced.
    local running = LC.rollDeadlines[rollID]
    if running then secs = math.max(0, math.floor(running - GetTime())) end

    if secs == 0 then
        LC.rollDeadlines[rollID] = GetTime()
        if LC.IsCouncil() then KART.LC.Council.ShowCouncilPanel(rollID, 0) end
        return true
    end

    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
    end
    -- Council members also get the vote window now (review #29): a council member who is in the raid
    -- can declare their own BIS like any raider. The popup shows for everyone; council additionally
    -- gets the panel above.
    LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    -- Both of those set the deadline from whole seconds, so handing them the remainder of a clock
    -- that is already running would still shave the fraction off it on every repeat. Put the exact
    -- value back.
    if running then LC.rollDeadlines[rollID] = running end
    return true
end

-- Entry point for /kart add <item1> <item2> ... — lets the designated lootmaster hand item(s)
-- they're currently holding back to Council for a (re)decision, without a real Blizzard loot
-- roll behind them. Only the lootmaster may do this — same person ForceWinRoll makes physically
-- win every real drop, so they're always the one actually holding whatever they manually add too.
-- Voids an earlier award of the same item before it goes back to the council, so the previous
-- winner's "you're owed this" entry, the lootmaster's pending trade and the history line naming them
-- all disappear — otherwise a re-decided item leaves a ghost obligation to someone who never gets it,
-- and (since the re-decision runs under a fresh rollID) history would list the same physical item
-- twice with two different winners.
--
-- Matched by itemID, which is deliberately NOT enough on its own: two copies of one item can be in
-- play at once (see the "(1/2)"/"(2/2)" duplicate marking). Revoking the wrong copy's award would be
-- worse than doing nothing, so an ambiguous match revokes nothing and says so — the lootmaster then
-- picks the right tab and uses "No Winner" by hand.
local function RevokePriorAward(itemLink)
    local itemID = LC.IsRealItemLink(itemLink) and itemLink:match("item:(%d+)")
    if not itemID then return end

    -- Both tables are searched, because neither covers the realistic case alone.
    --
    -- LC.pendingTrades is the durable one and the reason this works at all: an award is normally
    -- followed by closing the tab (or "Close Session"), and Council.CloseCouncilTab runs
    -- Trade.ClearRollState, which nils LC.assignedWinners[rollID] while deliberately leaving the
    -- pending trade alone. Pending trades also survive a full relog (KART_LCTrades) and carry their
    -- own itemLink, so they still match long after LC.rollItems was cleared.
    --
    -- LC.assignedWinners covers the one case pendingTrades can't: the lootmaster awarding the item
    -- to themselves, where Trade.AddPendingTrade returns early and no obligation is ever recorded.
    local seen, matches = {}, {}
    local function consider(rid, link)
        if type(rid) ~= "number" or seen[rid] or LC.IsTestRoll(rid) then return end
        if LC.IsRealItemLink(link) and link:match("item:(%d+)") == itemID then
            seen[rid] = true
            matches[#matches + 1] = { rollID = rid, link = link }
        end
    end
    for _, e in ipairs(LC.pendingTrades or {}) do
        consider(e.rollID, e.itemLink)
    end
    for rid, winnerKey in pairs(LC.assignedWinners) do
        if winnerKey and winnerKey ~= "NONE" then consider(rid, LC.rollItems[rid]) end
    end

    if #matches == 0 then return end
    if #matches > 1 then
        print("|cffff0000KART:|r " .. string.format(KART.L.LC_MANUAL_AMBIGUOUS_REVOKE, itemLink))
        return
    end

    -- Same three steps the council panel's "No Winner" button runs: tell the raid, then do the peer
    -- side's cleanup locally too, since we do not process our own broadcast.
    local m = matches[1]
    -- Trade.AnnounceResult reads the link back out of LC.rollItems to carry the itemID peers use to
    -- reject a result for a stale rollID. After a relog that table is empty while the obligation is
    -- not, so put the link the pending trade remembered back before announcing.
    if not LC.IsRealItemLink(LC.rollItems[m.rollID]) then LC.rollItems[m.rollID] = m.link end

    LC.Trade.AnnounceResult(m.rollID, "NONE")
    KART.LH.RemoveHistoryForRoll(m.rollID, LC.rollItems[m.rollID])
    LC.Trade.ClearWinnerObligations(m.rollID)
    KART.LC.Council.CloseCouncilTab(m.rollID)
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_MANUAL_REVOKED, itemLink))
end

function LC.StartManualRoll(itemsText)
    if not LC.IsLootOwner() then
        print("|cffff0000KART:|r " .. KART.L.LC_NOT_LOOTMASTER)
        return
    end

    local seconds = KART_Settings.lcVoteSeconds or 20
    local startedAny = false
    local entries, keys = {}, nil

    -- Matches each complete item hyperlink (|Hitem:...|h[Name]|h|r, with either a hex or named
    -- colour escape in front of it — different client versions shift-click different forms)
    -- regardless of how many are pasted in one command or how much whitespace separates them — a
    -- plain word-split would break apart item names that contain spaces (e.g.
    -- "[Sulfuras, Hand von Ragnaros]").
    local capped = 0
    for itemLink in KAUtil.EachItemLink(itemsText) do
        startedAny = true

        -- One LC_DROP message can only carry TABLE_MAX_IDS entries -- LC.HandleDrop stops reading
        -- past that cap on every peer (see the comment there). Refusing the surplus HERE, before any
        -- roll is created or window opened, is what keeps this client's own state from drifting ahead
        -- of what the raid will actually receive; opening windows for items that never leave this
        -- computer would be worse than not adding them. Splitting into a second LC_DROP was the other
        -- option, but it would need a second roster snapshot and a second DrawnKeys head, and /kart
        -- add is a typed command, not a boss -- nobody pastes 13 links by accident.
        if #entries >= TABLE_MAX_IDS then
            capped = capped + 1
        else
        -- Before anything else: the item is being handed back for a new decision, so whatever was
        -- decided about it last time has to stop being true first.
        RevokePriorAward(itemLink)

        local rollID = LC.nextManualRollID
        LC.nextManualRollID = LC.nextManualRollID + 1

        LC.rollItems[rollID] = itemLink
        LC.votes[rollID]     = {}
        -- Start the BoP trade-timeout clock at roll creation rather than at assign time
        -- (AddPendingTrade's fallback): we can't know a manually-added item's real Blizzard loot
        -- time, but roll creation is the earliest, most conservative moment we control.
        -- Wall clock, same reason as in OnStartLootRoll above.
        LC.rollLootedAt = LC.rollLootedAt or {}
        LC.rollLootedAt[rollID] = time()

        -- Same roster snapshot a real drop takes, and the reason B79 could never be answered before:
        -- a manually added item has no Blizzard roll behind it, so there was nothing to prove with
        -- who was in the raid at the time. Now there is (B118).
        SnapshotEligible(rollID)

        -- The sender does not process its own LC_DROP (KASC drops the echo, see Dispatch), so this
        -- client has to record its own announcement here rather than through LC.HandleManualStart.
        LC.rollAnnouncedBy[rollID] = (KASC.Identity.ResolvePlayer("player"))
        -- Silent: the numbers ride inside LC_DROP, next to the participant list they are ordered by.
        LC.DrawRollTable(rollID, (itemLink:match("item:(%d+)")), true)
        -- The head, derived from the numbers just drawn rather than from the snapshot (see the
        -- invariant on LC.DrawnKeys). Taken once, from the first item: /kart add runs inside one
        -- synchronous loop, so nothing can walk in between two items and every one of them draws
        -- against the same roster. Rolls switched off raid-wide therefore leaves the head empty too,
        -- which is what design §B asks for -- it used to carry the whole roster for nothing.
        -- The numbers ride in the entry, from the same read as the head (B135) -- this path serializes
        -- in the same breath, so nothing can move underneath it, but there is one entry shape and one
        -- rule about where an entry's numbers come from.
        local itemKeys, rolls = LC.DrawnKeys(rollID)
        keys = keys or itemKeys
        entries[#entries + 1] = {
            rollID = rollID,
            rolls = rolls,
            -- The full string, not the old 255-byte fallback: this message is split and reassembled
            -- by the transport, so there is no cliff left to degrade against, and a bare item string
            -- would lose the bonus ids (B119).
            itemString = KAUtil.GetItemString(itemLink) or itemLink,
        }

        -- KASC drops our own message when it comes back (see Dispatch), so the lootmaster has to open
        -- their own window locally, same as HandleStart does for every other client.
        if LC.IsCouncil() then
            KART.LC.Council.ShowCouncilPanel(rollID, seconds)
        end
        -- Council also gets the vote window (review #29) — see the same pattern in LC.HandleStart.
        LC.Vote.ShowVotePopup(rollID, itemLink, seconds)
        end
    end

    if #entries > 0 then
        LC.SendLC(LC.SerializeDrop("m", seconds, keys, entries))
        LC.EnsureTableTicker()
    end

    if not startedAny then
        print("|cffff0000KART:|r " .. KART.L.LC_MANUAL_ADD_USAGE)
    elseif capped > 0 then
        print("|cffff0000KART:|r " .. string.format(KART.L.LC_MANUAL_ADD_CAPPED, TABLE_MAX_IDS, capped))
    end
end

-- Peer side of LC.StartManualRoll — mirrors LC.HandleStart, minus the GetLootRollItemLink call
-- (there's no real Blizzard roll behind a manually-added item, so the link always arrives intact
-- in the payload itself). LC.StartManualRoll no longer sends LC_MANUAL_START itself — the whole
-- list travels as one LC_DROP (kind "m") — but this handler stays: LC.HandleDrop calls it once per
-- entry, rebuilding the same per-item payload this used to receive off the wire directly.
function LC.HandleManualStart(payload, senderKey)
    -- Only the loot owner legitimately sends manual rolls (see LC.StartManualRoll).
    -- IsSenderLootOwner also handles the GUID-vs-pending-text race: senderKey is always a resolved
    -- GUID, but the stored lootmaster can still be pending config text if they weren't in our roster
    -- when LC_CONFIG was parsed, which would drop a legitimate manual roll inside the
    -- GROUP_ROSTER_UPDATE throttle window (LC_STATE_REQ only covers a fresh raid join).
    if not LC.IsSenderLootOwner(senderKey) then
        LC.diag.refusedSender = LC.diag.refusedSender + 1
        -- Same verdict, same reason as LC.HandleStart's: refusing the announcer does not refuse the
        -- numbers. See the comment there.
        return true
    end
    local rollID, secs, itemLink = payload:match("^(%d+):(%d+):(.*)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    -- No item at all, so there is nothing to announce and nothing the numbers could belong to. A
    -- manual item has no Blizzard roll behind it to rebuild a link from -- unlike a real drop, which
    -- legitimately arrives with an empty item part and resolves it locally -- so this is the one entry
    -- shape whose numbers would be stored against an item that can never appear on any screen.
    if not rollID or not itemLink or itemLink == "" then return false end
    -- The sender may have sent a compact item string instead of the full link (oversized-link
    -- fallback, see LC.StartManualRoll). Rebuild a full link when the item is cached so it displays.
    if not LC.IsRealItemLink(itemLink) and itemLink:match("^item:") then
        itemLink = select(2, C_Item.GetItemInfo(itemLink)) or itemLink
    end

    LC.votes[rollID]     = LC.votes[rollID] or {}
    -- The payload link is always authoritative for a manual roll (there's no Blizzard roll behind
    -- it, so it arrives intact) — take it unconditionally rather than preferring possibly-stale
    -- state left over from an earlier roll that reused this ID.
    LC.rollItems[rollID] = itemLink
    LC.rollAnnouncedBy[rollID] = senderKey

    -- Same BoP trade clock LC.HandleStart sets for a real roll. The SENDER stamps this in
    -- LC.StartManualRoll, but the receiving side was missing it entirely, so the winner's owedToMe
    -- entry (Trade.HandleResult) fell back to time() at AWARD time — their 4-hour countdown started
    -- when the council finished instead of when the item was added, and the reminder outlived the
    -- real deadline by however long the vote took. Wall clock, same reason as everywhere else.
    LC.rollLootedAt = LC.rollLootedAt or {}
    LC.rollLootedAt[rollID] = time()

    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
    end
    -- Council members also get the vote window now (review #29): a council member who is in the raid
    -- can declare their own BIS like any raider. The popup shows for everyone; council additionally
    -- gets the panel above.
    LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    -- Taken. Same verdict LC.HandleStart returns, and for the same reason -- see the comment there.
    return true
end

-- The receiving half, and deliberately thin: it rebuilds the two payloads the existing handlers
-- already read and calls them. Every guard those grew -- the sender check, PurgeStaleRoll, the reuse
-- rule, the dismissal note (B132), the announcer record (B130) -- therefore applies unchanged, and
-- there is no second copy of any of it to drift.
function LC.HandleDrop(payload, senderKey)
    local secs, kind, rest = payload:match("^(%d+):([rmRM]):(.*)$")
    if not secs then return end
    -- Unpacked before anything is read out of it, so everything below sees the one shape it always
    -- saw. A block that will not come back -- truncated, foreign, damaged -- drops the WHOLE message:
    -- half a batch is half a boss, announced to a raid that has no way to notice the rest is missing.
    if kind == "R" or kind == "M" then
        rest = Unpack(rest)
        if not rest then
            LC.diag.packedUnreadable = LC.diag.packedUnreadable + 1
            return
        end
        kind = kind:lower()
    end
    local head, entries = rest:match("^([^;]*);(.*)$")
    if not entries then return end

    local keys = {}
    for key in head:gmatch("[^,]+") do keys[#keys + 1] = key end

    local seen = 0
    for entry in entries:gmatch("[^;]+") do
        -- One message used to be one item, so one message was one popup. It is now a list, and an
        -- unbounded list opens as many windows as the sender cares to write.
        --
        -- Bounded by TABLE_MAX_IDS deliberately, rather than by a number of its own. That is how many
        -- rolls the table heartbeat can name at once, which makes it the most items this raid can hold
        -- a shared view of: a batch longer than that describes a table the repair path could never
        -- re-state, so the entries past it are ones no client could be brought back into agreement
        -- about anyway. A boss drops a handful, and /kart add is a line somebody types, so nothing
        -- legitimate comes near it -- and tying the two means a future change to the heartbeat's
        -- budget cannot leave this one behind.
        seen = seen + 1
        if seen > TABLE_MAX_IDS then
            LC.diag.dropCapped = LC.diag.dropCapped + 1
            break
        end
        -- The item string is the last field precisely so that its own colons and commas cannot reach
        -- this pattern.
        local rollID, nums, itemString = entry:match("^(%d+)#([^#]*)#(.*)$")
        if rollID then
            local startPayload = rollID .. ":" .. secs .. ":" .. itemString
            -- One verdict for the whole entry: whether it described an item at all. The two halves of
            -- an entry are one message and must not disagree about THAT -- numbers stored under a
            -- rollID whose announcement half found nothing to announce are an orphan table no screen
            -- can ever show and no repair can ever resolve. What the two halves keep separate, on
            -- purpose, is who may write each of them; see the comment on LC.HandleStart.
            local usable
            if kind == "m" then
                usable = LC.HandleManualStart(startPayload, senderKey)
            else
                usable = LC.HandleStart(startPayload, senderKey)
            end
            -- After the announcement, never before it: LC.HandleRolls accepts a table from the
            -- ANNOUNCER of that item, and the call above is what records who that is.
            if usable and nums ~= "" then
                local drawn = {}
                for n in nums:gmatch("[^,]+") do drawn[#drawn + 1] = n end
                -- One number per participant, or none of them. The head names the participants once
                -- and the entry lists its numbers in that order, so a length that does not match means
                -- the two halves were built against different rosters -- and then every position after
                -- the first difference names somebody else's raider. The sender splits its batch
                -- exactly so this cannot happen (see LC.DrawnKeys); this is the half that makes a
                -- sender which does it anyway -- an older build, a future one -- detectable instead of
                -- silent.
                --
                -- Refused WHOLE rather than stored up to the gap, for the reason LC.HandleRolls
                -- refuses an empty table: LC.rolls[rollID] ~= nil is what "we hold the numbers" means
                -- everywhere else, so a partial table is indistinguishable from a real draw and would
                -- permanently stop this client asking for the real one. Refusing leaves the gap
                -- visible, and the heartbeat's repair path fetches the table it is missing.
                if #drawn == #keys then
                    for i = 1, #drawn do drawn[i] = keys[i] .. "=" .. drawn[i] end
                    LC.HandleRolls(rollID .. ":@" .. LC.PayloadItemID(itemString) .. ":"
                        .. table.concat(drawn, ","), senderKey)
                end
            end
        end
    end
end

-- =====================================================================
--  Addon-message registrations
-- =====================================================================
-- group = true on every LC message that carries authority or writes tracked state. The sender's
-- resolved key alone is NOT proof of membership: Identity resolution is short-name based (see
-- KASC.Identity), so an out-of-group player sharing a short name with a council member would
-- otherwise resolve onto their GUID and pass IsSenderCouncil/IsSenderGroupLeader. The three
-- LC_SYNC_* messages are deliberately left ungated below — that feature is an explicit whisper to
-- someone outside the group, and the receiver confirms it via popup before anything is applied.
KASC:RegisterMessage("LC_ACTIVE", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleActive(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_DROP", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleDrop(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_START", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleStart(payload, ctx:Key()) end)
-- No shipping version SENDS this any more (/kart add travels as LC_DROP with kind "m"), and
-- LC.HandleManualStart is reached through LC.HandleDrop instead. The registration stays as rollout
-- tolerance, for the same reason as the GUARANTEED_TOKENS entry: a client on the previous build can
-- still put one on the wire, and dropping it would take the item off this client's screen entirely.
KASC:RegisterMessage("LC_MANUAL_START", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleManualStart(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_CONFIG", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleConfig(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_CONFIG_RELAY", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleConfigRelay(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_ROLL_CATCHUP", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleRollCatchup(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_ROLLS", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleRolls(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_TABLE", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleTable(payload, ctx:Key(), ctx.sender) end)
KASC:RegisterMessage("LC_ROLL_REQ", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleRollRequest(payload, ctx:Key(), ctx.sender) end)
KASC:RegisterMessage("LC_ROLLS_REQ", { payload = true, group = true, enabled = lcEnabled },
    function(payload) LC.HandleRollsRequest(payload) end)
KASC:RegisterMessage("LC_STATE_REQ", { payload = false, group = true, enabled = lcEnabled },
    function(_, ctx) LC.HandleStateRequest(ctx.sender, ctx:Key()) end)
KASC:RegisterMessage("LC_SESSION_RESUME", { payload = false, group = true, enabled = lcEnabled },
    function(_, ctx) LC.HandleSessionResume(ctx:Key()) end)
KASC:RegisterMessage("LC_END_ROUND", { payload = false, group = true, enabled = lcEnabled },
    function(_, ctx) LC.HandleEndRound(ctx:Key()) end)
-- LC_SYNC_REQUEST keeps the enabled gate but no group gate, for the reason above.
KASC:RegisterMessage("LC_SYNC_REQUEST", { payload = true, enabled = lcEnabled },
    function(payload, ctx) LC.HandleSyncRequest(payload, ctx.sender, ctx.shortName) end)
-- LC_SYNC_ACCEPT/DECLINE carry neither gate: a decline must still print even if the receiver just
-- disabled the module, and the sync feature is an explicit whisper to someone outside the group.
KASC:RegisterMessage("LC_SYNC_ACCEPT", {}, function(_, ctx) LC.HandleSyncAccept(ctx.shortName) end)
KASC:RegisterMessage("LC_SYNC_DECLINE", {}, function(_, ctx) LC.HandleSyncDecline(ctx.shortName) end)

-- =====================================================================
--  Test Function
-- =====================================================================

-- mode: "looter" = always show vote popup; "master" = always show council panel; nil = auto-detect
function LC.StartTest(mode)
    local buttons = LC.GetButtonConfig()

    local showCouncil
    if mode == "looter" then
        showCouncil = false
    elseif mode == "master" then
        showCouncil = true
    else
        -- Auto: follow actual role
        showCouncil = LC.IsCouncil() and IsInGroup()
    end

    -- A test session is "active" if EITHER window still has test rolls tracked. If so, this
    -- click just adds/refreshes the OTHER window on top of it — it must never reset the shared
    -- item/vote data, since that data is exactly what the already-open window is displaying.
    -- Clicking "Test Looter" while "Test Master" is still showing its tabs (or vice versa) used
    -- to wipe LC.councilTabs/LC.voteListRolls out from under the other, already-visible window
    -- without ever telling it to re-render — the stale tabs would then only get cleaned up (i.e.
    -- appear to "vanish") whenever something else happened to trigger a refresh later, such as a
    -- vote coming in, which made it look like voting itself was breaking the council panel.
    local sessionActive = false
    for _, rid in ipairs(LC.voteListRolls) do
        if LC.IsTestRoll(rid) then sessionActive = true break end
    end
    if not sessionActive then
        for _, rid in ipairs(LC.councilTabs) do
            if LC.IsTestRoll(rid) then sessionActive = true break end
        end
    end

    -- sessionActive alone isn't enough to decide whether to keep old test data: every click (see
    -- the ShowVotePopup/ShowCouncilPanel loop below) refreshes each test item's deadline to
    -- now+seconds regardless of sessionActive, so a test roll never actually expires as long as
    -- someone keeps clicking a Test button — sessionActive would stay true forever, permanently
    -- skipping the reset below and making every vote "stick" across restarts of the SAME window.
    -- Only suppress the reset when a DIFFERENT window's mode is what's actually keeping the
    -- session alive (the looter+master-open-simultaneously scenario this check exists for, per
    -- the comment above) — re-clicking the SAME mode is always an explicit "start a fresh test".
    local suppressReset = sessionActive and LC.testSessionShowCouncil ~= nil and LC.testSessionShowCouncil ~= showCouncil
    LC.testSessionShowCouncil = showCouncil

    if not suppressReset then
        for itemIdx, testItem in ipairs(TEST_ITEMS) do
            local testRollID = TEST_ROLL_ID + (itemIdx - 1)

            LC.rollItems[testRollID]       = testItem
            LC.votes[testRollID]           = {}
            LC.rolls[testRollID]           = {}
            LC.councilVotes[testRollID]    = {}
            LC.assignedWinners[testRollID] = nil -- fresh test run, forget any winner assigned in a previous one
            LC.votedByMe[testRollID]       = nil -- forget our own vote from a previous test run too
            LC.relevanceHandled[testRollID]  = nil
            LC.hiddenIrrelevant[testRollID]  = nil
            LC.autoVotedByMe[testRollID]     = nil
            LC.relevanceSnapshot[testRollID] = nil
            -- Cleared like the rest: Council.RequestEquipForRoll dedups per roll, so a second Test
            -- run reused the first run's answers and kept showing gear the player had since swapped.
            if LC.equipRequestedRolls then LC.equipRequestedRolls[testRollID] = nil end
            LC.councilTabsNew[testRollID]  = nil

            local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
            local myKey    = (KASC.Identity.ResolvePlayer("player"))
            local rollsOn  = LC.GetRollsEnabled()
            if rollsOn and myShort ~= "" then
                LC.rolls[testRollID][myKey] = math.random(1, 100)
            end

            -- Pre-fill votes (and, if enabled, rolls) from current group members so the council
            -- panel looks populated
            if IsInGroup() then
                -- Offset per item so the fake votes aren't identical across items, but wrap into the
                -- valid 1..#buttons range from the start — with fewer than TEST_ITEM_COUNT buttons a
                -- bare itemIdx seed would be out of range and render as "-".
                local voteIdx = ((itemIdx - 1) % #buttons) + 1
                for unit in KAUtil.EachGroupUnit() do
                    local name = UnitName(unit)
                    if name then
                        local short = name:match("([^%-]+)")
                        if short and short ~= myShort then
                            local key = (KASC.Identity.ResolvePlayer(unit))
                            LC.votes[testRollID][key] = {idx = voteIdx, note = ""}
                            voteIdx = (voteIdx % #buttons) + 1
                            if rollsOn then LC.rolls[testRollID][key] = math.random(1, 100) end
                        end
                    end
                end
            end
        end
    end

    -- Kick off all test items at once: the vote list shows every one as its own row, and the
    -- council panel gets a tab per item — exactly like multiple real items dropping from a boss
    -- at nearly the same time.
    for itemIdx = 1, TEST_ITEM_COUNT do
        local testRollID = TEST_ROLL_ID + (itemIdx - 1)
        if showCouncil then
            KART.LC.Council.ShowCouncilPanel(testRollID, KART_Settings.lcVoteSeconds or 20)
        end
        -- Match live: council now sees both windows (review #29), so a master-mode test does too.
        LC.Vote.ShowVotePopup(testRollID, LC.rollItems[testRollID], KART_Settings.lcVoteSeconds or 20)
    end

    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_TEST_STARTED, TEST_ITEM_COUNT))
end
