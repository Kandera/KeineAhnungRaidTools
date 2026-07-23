local addonName, KART = ...

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
    noteText = KART.TrimString(noteText or "")
    KART_LCOfficerNotes[playerKey] = (noteText ~= "") and noteText or nil
    LC.SendLC("LC_ONOTE:" .. playerKey .. ":" .. noteText)
    LC.RefreshCouncilRows()
end

function OfficerNotes.HandleOfficerNote(payload, senderKey)
    if not LC.IsSenderCouncil(senderKey) then return end
    local subjectKey, noteText = payload:match("^([^:]+):(.*)$")
    if not subjectKey then return end
    KART_LCOfficerNotes[subjectKey] = (noteText ~= "") and noteText or nil

    if LC.councilPanel and LC.councilPanel:IsShown() then
        LC.RefreshCouncilRows()
    end
end

-- Re-resolves one legacy (short-name-text-keyed) KART_LCOfficerNotes entry to a GUID-based key,
-- if the named player can currently be resolved (live in the group, or previously cached — see
-- KART.Identity.ResolvePlayer). Returns true if it migrated the entry, false if it's still
-- unresolvable (left untouched, never deleted, so no note is ever silently lost — retried again
-- next time this runs, see the GROUP_ROSTER_UPDATE hook that calls this).
function OfficerNotes.MigrateOfficerNoteKey(oldKey)
    if KART.Identity.IsResolvedKey(oldKey) then return false end -- already migrated
    local newKey, isPending = KART.Identity.ResolvePlayer(oldKey)
    if isPending then return false end
    KART_LCOfficerNotes[newKey] = KART_LCOfficerNotes[oldKey]
    KART_LCOfficerNotes[oldKey] = nil
    return true
end

-- A hand-rolled little dialog instead of StaticPopupDialogs — retail's StaticPopup system was
-- reworked (routes through Blizzard_StaticPopup_Game/GameDialog.lua now) and no longer reliably
-- exposes the edit box as `self.editBox` inside OnAccept (errored with "attempt to index field
-- 'editBox' (a nil value)" there, even though OnShow's `self.editBox` worked fine — the popup
-- frame passed to the two callbacks isn't consistently the same shape). Owning the whole frame
-- ourselves means the edit box reference is always exactly what we created it as.
function OfficerNotes.ShowOfficerNoteDialog(playerKey, playerDisplayName)
    if not LC.officerNoteDialog then
        local f = CreateFrame("Frame", "KART_LCOfficerNoteDialog", UIParent, "BackdropTemplate")
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

        f.editBox = KART.CreateStyledEditBox(f, "KART_LCOfficerNoteEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetMaxLetters(120)
        -- Fallback font until the next KART.UpdateStyles pass — this dialog is created lazily,
        -- long after the login-time style pass already ran.
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            if f.key then OfficerNotes.SetOfficerNote(f.key, f.editBox:GetText()) end
            f:Hide()
        end

        local btnOK = KART.CreateModernButton(f, OKAY) ---@diagnostic disable-line: undefined-global
        btnOK:SetSize(120, 26)
        btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        btnOK:SetScript("OnClick", accept)

        local btnCancel = KART.CreateModernButton(f, CANCEL) ---@diagnostic disable-line: undefined-global
        btnCancel:SetSize(120, 26)
        btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)

        LC.officerNoteDialog = f
    end

    local f = LC.officerNoteDialog
    f.key = playerKey
    f.title:SetText(string.format(KART.L.LC_OFFICER_NOTE_PROMPT, playerDisplayName))
    f.editBox:SetText(KART_LCOfficerNotes[playerKey] or "")
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end
