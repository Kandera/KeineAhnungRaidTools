local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

KART.LC.OfficerNotes = KART.LC.OfficerNotes or {}
local OfficerNotes = KART.LC.OfficerNotes
local LC = KART.LC

-- =====================================================================
--  Officer Notes  (persistent, per-player — not tied to any one item/roll)
-- =====================================================================
-- Distinct from the per-vote note a raider attaches to their own vote: this is a standing
-- council note about a PERSON (e.g. "already has BIS trinket", "missed the last two items"),
-- visible on every item they show up on. Saved locally (KART_LCOfficerNotes, survives reload)
-- and broadcast on edit so every currently-online council member's client converges — there's
-- no catch-up sync on raid join the way loot history has, so someone who was offline when a
-- note was written won't see it until it's edited again while they're online.
function OfficerNotes.SetOfficerNote(playerKey, noteText)
    -- Strip colons: they're the LC_ONOTE payload separator, so a note containing one would shift
    -- the receiver's capture. Same colon-safety rule the synced council/lootmaster fields follow
    -- (LootCouncilSettings.StripColons). Pipes go too: this note is rendered raw into the council
    -- row's tooltip AND persisted in KART_LCOfficerNotes forever, so a "|c"/"|H"/"|T" escape would
    -- inject coloured text, a fake hyperlink or a texture into every council member's UI for good.
    -- Both stripped before the local store and the broadcast, so every client keeps identical text.
    noteText = (KAUtil.TrimString(noteText or ""):gsub("[:|]", ""))
    KART_LCOfficerNotes[playerKey] = (noteText ~= "") and noteText or nil
    LC.SendLC("LC_ONOTE:" .. playerKey .. ":" .. noteText)
    KART.LC.Council.RefreshCouncilRows()
end

function OfficerNotes.HandleOfficerNote(payload, senderKey)
    if not LC.IsSenderCouncil(senderKey) then return end
    local subjectKey, noteText = payload:match("^([^:]+):(.*)$")
    if not subjectKey then return end
    -- Escape pipes even though SetOfficerNote already strips them: this arrives over the wire, so a
    -- client that didn't strip must not be able to write escape sequences into a SavedVariable that
    -- is rendered raw in the council tooltip from then on.
    noteText = (noteText:gsub("|", "||"))
    KART_LCOfficerNotes[subjectKey] = (noteText ~= "") and noteText or nil

    if LC.councilPanel and LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
    end
end

-- Re-resolves one legacy (short-name-text-keyed) KART_LCOfficerNotes entry to a GUID-based key,
-- if the named player can currently be resolved (live in the group, or previously cached — see
-- KASC.Identity.ResolvePlayer). Returns true if it migrated the entry, false if it's still
-- unresolvable (left untouched, never deleted, so no note is ever silently lost — retried again
-- next time this runs, see the GROUP_ROSTER_UPDATE hook that calls this).
function OfficerNotes.MigrateOfficerNoteKey(oldKey)
    if KASC.Identity.IsResolvedKey(oldKey) then return false end -- already migrated
    local newKey, isPending = KASC.Identity.ResolvePlayer(oldKey)
    if isPending then return false end
    -- Don't clobber a note already written under the resolved GUID key (e.g. edited normally after
    -- the legacy entry went stale) with the older text-keyed one — keep the newer GUID note.
    if KART_LCOfficerNotes[newKey] == nil then
        KART_LCOfficerNotes[newKey] = KART_LCOfficerNotes[oldKey]
    end
    KART_LCOfficerNotes[oldKey] = nil
    return true
end

function OfficerNotes.ShowOfficerNoteDialog(playerKey, playerDisplayName)
    KART.UI:ShowInputDialog({
        title = string.format(KART.L.LC_OFFICER_NOTE_PROMPT, playerDisplayName),
        maxLetters = 120,
        initialText = KART_LCOfficerNotes[playerKey] or "",
        allowEmpty = true, -- empty input clears the note (see SetOfficerNote)
        okLabel = OKAY, ---@diagnostic disable-line: undefined-global
        cancelLabel = KART.L.BTN_CANCEL,
        onAccept = function(text) OfficerNotes.SetOfficerNote(playerKey, text) end,
    })
end

KASC:RegisterMessage("LC_ONOTE", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) OfficerNotes.HandleOfficerNote(payload, ctx:Key()) end)
