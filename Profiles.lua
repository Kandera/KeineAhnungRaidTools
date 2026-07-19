local addonName, KART = ...

-- Saves (or overwrites) a profile with the current KART_Settings and makes it the active one.
function KART.SaveProfile(name)
    KART_Profiles[name] = KART.DeepCopy(KART_Settings)
    KART_Settings.activeProfile = name
end

-- Replaces KART_Settings with a deep copy of the named profile, re-merges any settings keys the
-- profile predates (KART.Defaults), marks it active, and pushes the result into every widget.
function KART.LoadProfile(name)
    local snapshot = KART_Profiles[name]
    if not snapshot then return end
    wipe(KART_Settings)
    for k, v in pairs(KART.DeepCopy(snapshot)) do
        KART_Settings[k] = v
    end
    for k, v in pairs(KART.Defaults) do
        if KART_Settings[k] == nil then KART_Settings[k] = v end
    end
    KART_Settings.activeProfile = name
    KART.SyncSettingsToUI()
end

-- Removes a saved profile. Does not touch KART_Settings itself — deleting a profile only
-- removes the saved snapshot, never the currently-loaded values.
function KART.DeleteProfile(name)
    KART_Profiles[name] = nil
    if KART_Settings.activeProfile == name then
        KART_Settings.activeProfile = nil
    end
end

function KART.RefreshProfileButton()
    if not KART.BtnProfile then return end
    local name = KART_Settings and KART_Settings.activeProfile
    KART.BtnProfile.text:SetText(KART.L.PROFILE_LABEL_PREFIX .. (name or KART.L.PROFILE_NONE))
end

-- Hand-rolled dialog instead of StaticPopupDialogs' hasEditBox: retail's StaticPopup system
-- (routed through Blizzard_StaticPopup_Game/GameDialog.lua) doesn't reliably expose the edit box
-- as self.editBox to its callbacks — same fix already applied to LC.ShowOfficerNoteDialog in
-- LootCouncil.lua (see the comment there for the full "attempt to index field 'editBox' (a nil
-- value)" story). Owning the frame ourselves means the edit box reference always exists.
local saveProfileDialog

function KART.ShowSaveProfileDialog()
    if not saveProfileDialog then
        local f = CreateFrame("Frame", "KART_SaveProfileDialog", UIParent, "BackdropTemplate")
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

        f.editBox = KART.CreateStyledEditBox(f, "KART_SaveProfileEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetMaxLetters(32)
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            local name = f.editBox:GetText()
            name = name and name:match("^%s*(.-)%s*$") or ""
            if name == "" then
                UIErrorsFrame:AddMessage(KART.L.PROFILE_NAME_EMPTY, 1, 0.1, 0.1, 1, 3)
                return
            end
            f:Hide()
            if KART_Profiles[name] then
                StaticPopupDialogs["KART_PROFILE_OVERWRITE_CONFIRM"].text = KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT
                StaticPopup_Show("KART_PROFILE_OVERWRITE_CONFIRM", name, nil, { name = name })
            else
                KART.SaveProfile(name)
                KART.RefreshProfileButton()
            end
        end

        local btnOK = KART.CreateModernButton(f, ACCEPT)
        btnOK:SetSize(120, 26)
        btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        btnOK:SetScript("OnClick", accept)

        local btnCancel = KART.CreateModernButton(f, CANCEL)
        btnCancel:SetSize(120, 26)
        btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)

        saveProfileDialog = f
    end

    local f = saveProfileDialog
    f.title:SetText(KART.L.PROFILE_SAVE_NEW_TEXT)
    f.editBox:SetText("")
    f:Show()
    f.editBox:SetFocus()
end

StaticPopupDialogs["KART_PROFILE_OVERWRITE_CONFIRM"] = {
    text = "A profile named '%s' already exists. Overwrite it?", -- overwritten with KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        KART.SaveProfile(data.name)
        KART.RefreshProfileButton()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["KART_PROFILE_DELETE_CONFIRM"] = {
    text = "Really delete profile '%s'?", -- overwritten with KART.L.PROFILE_DELETE_CONFIRM_TEXT before every StaticPopup_Show call
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        KART.DeleteProfile(data.name)
        KART.RefreshProfileButton()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
