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

StaticPopupDialogs["KART_PROFILE_SAVE_NEW"] = {
    text = "Enter a name for the new profile:", -- overwritten with KART.L.PROFILE_SAVE_NEW_TEXT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        name = name and name:match("^%s*(.-)%s*$") or ""
        if name == "" then
            UIErrorsFrame:AddMessage(KART.L.PROFILE_NAME_EMPTY, 1, 0.1, 0.1, 1, 3)
            StaticPopup_Show("KART_PROFILE_SAVE_NEW")
            return
        end
        if KART_Profiles[name] then
            StaticPopupDialogs["KART_PROFILE_OVERWRITE_CONFIRM"].text = KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT
            StaticPopup_Show("KART_PROFILE_OVERWRITE_CONFIRM", name, nil, { name = name })
        else
            KART.SaveProfile(name)
            KART.RefreshProfileButton()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        StaticPopupDialogs["KART_PROFILE_SAVE_NEW"].OnAccept(dialog)
        dialog:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
