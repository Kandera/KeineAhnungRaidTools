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
    -- Language is only applied once at load (Core.lua) and the language picker itself reloads to
    -- switch it, so a profile that stored a different language needs the same reload to take effect.
    local prevLang = KART_Settings.language
    local prevOwned = KART_Settings.autoLogOwned -- runtime log ownership, restored below (not a preference)
    -- LibDBIcon holds a REFERENCE to the minimap sub-table it was registered with (Core.lua
    -- ADDON_LOADED) — keep that table's identity across profile loads, otherwise icon position
    -- changes are written into an orphaned table until the next reload.
    local minimapTbl = KART_Settings.minimap
    wipe(KART_Settings)
    for k, v in pairs(KART.DeepCopy(snapshot)) do
        KART_Settings[k] = v
    end
    KART.MergeDefaults(KART_Settings, KART.Defaults)
    if minimapTbl then
        local loaded = KART_Settings.minimap
        wipe(minimapTbl)
        if type(loaded) == "table" then
            for k, v in pairs(loaded) do minimapTbl[k] = v end
        end
        KART_Settings.minimap = minimapTbl
    end
    KART_Settings.activeProfile = name
    -- autoLogOwned is runtime state, not a preference — it only means "KART started the log that is
    -- running right now". A snapshot taken while KART was logging would otherwise restore a true
    -- claim over a log this session never started (or over no log at all), and AutoLog.Evaluate
    -- would later stop a log the player started by hand. Re-derive it from what's actually running.
    KART_Settings.autoLogOwned = prevOwned and LoggingCombat() or false
    if KART_Settings.language ~= prevLang then
        ReloadUI() -- language change needs a reload; the reload re-runs SyncSettingsToUI on load
        return
    end
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

function KART.ShowSaveProfileDialog()
    KART.ShowInputDialog({
        title = KART.L.PROFILE_SAVE_NEW_TEXT,
        maxLetters = 32,
        emptyMessage = KART.L.PROFILE_NAME_EMPTY,
        onAccept = function(name)
            if KART_Profiles[name] then
                local dlg = StaticPopupDialogs["KART_PROFILE_OVERWRITE_CONFIRM"]
                dlg.text = KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT
                dlg.button1, dlg.button2 = KART.L.BTN_ACCEPT, KART.L.BTN_CANCEL
                StaticPopup_Show("KART_PROFILE_OVERWRITE_CONFIRM", name, nil, { name = name })
            else
                KART.SaveProfile(name)
                KART.RefreshProfileButton()
            end
        end,
    })
end

KART.RegisterStaticPopup("KART_PROFILE_OVERWRITE_CONFIRM", {
    text = "A profile named '%s' already exists. Overwrite it?", -- overwritten with KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        KART.SaveProfile(data.name)
        KART.RefreshProfileButton()
    end,
})

KART.RegisterStaticPopup("KART_PROFILE_DELETE_CONFIRM", {
    text = "Really delete profile '%s'?", -- overwritten with KART.L.PROFILE_DELETE_CONFIRM_TEXT before every StaticPopup_Show call
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        KART.DeleteProfile(data.name)
        KART.RefreshProfileButton()
    end,
})
