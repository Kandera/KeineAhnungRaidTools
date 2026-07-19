# Settings Profiles — Design

## Purpose

`KART_Settings` is a single account-wide table — every character on the account shares one set
of settings. Users want multiple named settings configurations they can switch between manually
(e.g. a "Raid" profile vs a "Mythic+" profile, or one profile per character's role), similar to
WeakAuras/ElvUI profiles.

Out of scope: automatic per-character profiles (would require `SavedVariablesPerCharacter`, a
bigger storage-model change); renaming an existing profile (delete + re-save covers it); merging
or diffing profiles.

## Storage

New SavedVariable `KART_Profiles`, added to `KeineAhnungRaidTools.toc`'s `## SavedVariables:` line:

```lua
KART_Profiles = {
    ["Raid"] = { <deep copy of a KART_Settings table> },
    ["Mythic+"] = { <deep copy of a KART_Settings table> },
}
```

Each profile is a full, independent deep copy of `KART_Settings` at the time it was saved — no
partial/whitelisted subset, no exceptions for window-position fields. This is the simplest rule
to implement correctly and matches how WeakAuras/ElvUI profiles behave (everything is part of
the profile).

`KART_Settings.activeProfile` (a plain string) tracks which profile name is currently loaded, for
UI display only — it has no effect on which values are active (those are whatever's currently in
`KART_Settings`); it only lets the settings card show "Profile: Raid" instead of nothing. If unset
(fresh install, or the active profile was deleted), the button shows a neutral "No Profile" label.

## Deep copy helper

New function `KART.DeepCopy(t)` in `Utils.lua` (no existing deep-copy utility in the codebase —
confirmed by grep). Plain recursive table copy, no metatable/function value handling needed since
`KART_Settings` only ever contains strings, numbers, booleans, and plain nested tables (edit-box
text, toggles, sliders, the `keybinds` and `minimap` sub-tables).

## Switching mechanism

`Core.lua`'s `ADDON_LOADED` handler currently does three things in one block: (1) load
`KART_Settings`/merge `KART.Defaults`, (2) push those values into every settings widget and
refresh dependent module caches (`KART.UpdateCache()`, `KART.LC.UpdateCouncilCache()`,
`KART.DT.RebuildIndex()`, `KART.UpdateStyles()`, `KART.UpdateMinimapButton()`,
`KART.UpdateRaidleadBarVisibility()`, `KART.ApplyKeybinds()`, and the individual widget
`SetChecked`/`SetValue`/`SetText` sync loop), (3) one-time initialization (register with
`AddonCompartmentFrame`, `hooksecurefunc("ConfirmReadyCheck", ...)`, minimap icon registration).

Part (2) is extracted into a new function `KART.SyncSettingsToUI()`, callable both from
`ADDON_LOADED` (replacing the inline code there) and from profile switching. Part (3) stays
inline in `ADDON_LOADED` only — it must never run twice (re-registering the same
`AddonCompartmentFrame` entry or re-hooking `ConfirmReadyCheck` a second time would be a bug, not
a feature).

**Loading a profile:**
1. `wipe(KART_Settings)`
2. Copy every key from `KART.DeepCopy(KART_Profiles[name])` into `KART_Settings`
3. Re-run the existing defaults-merge (`for k, v in pairs(KART.Defaults) do if KART_Settings[k]
   == nil then KART_Settings[k] = v end end`) — covers a profile saved before a newer KART version
   added a new setting key
4. `KART_Settings.activeProfile = name`
5. `KART.SyncSettingsToUI()`

**Saving (new or overwrite):** `KART_Profiles[name] = KART.DeepCopy(KART_Settings)`, then set
`KART_Settings.activeProfile = name` (a "Save As New" while a different profile was active makes
the new one the active one).

**Deleting:** `KART_Profiles[name] = nil`. If the deleted profile was the active one, clear
`KART_Settings.activeProfile` (leave `KART_Settings` itself untouched — deleting a profile doesn't
change your currently-loaded settings, it just removes the saved snapshot and the "currently
loaded from X" label).

## UI

New card on the Settings tab (Tab 4 in `MainFrame.lua`), below the existing cards.

- A `CreateModernButton`-style button labeled `"Profile: " .. (KART_Settings.activeProfile or
  L.PROFILE_NONE)`. Left-click opens a `MenuUtil.CreateContextMenu` (same mechanism already used
  by `KART.BtnFont` for font selection) listing every key in `KART_Profiles`, alphabetically;
  clicking a name loads that profile (per the switching mechanism above) and updates the button
  label.
- **Save As New** button: opens a new `StaticPopupDialogs` entry (`KART_PROFILE_SAVE_NEW`) with
  `hasEditBox = true` (Blizzard's native text-input popup, not previously used in this codebase —
  every existing `StaticPopupDialogs` entry here is confirm-only; this is the same native API with
  one added field). `OnAccept` reads the edit box text, rejects empty/whitespace-only names
  (re-shows the popup with an error, does not silently no-op), warns via a nested confirm popup if
  the name already exists in `KART_Profiles` ("Overwrite existing profile 'X'?") before saving,
  then saves and switches to it per the saving mechanism above.
- **Save** button: only enabled (not grayed out — WoW buttons here don't currently support a
  disabled visual state per the existing button factory, so instead: no-ops with nothing shown)
  when `KART_Settings.activeProfile` is set; overwrites `KART_Profiles[KART_Settings.activeProfile]`
  with the current settings, no popup needed (this is an explicit, deliberate overwrite of a
  profile the user is already looking at).
- **Delete** button: opens a confirm-only `StaticPopupDialogs` entry (`KART_PROFILE_DELETE_CONFIRM`,
  same pattern as `KART_LH_CLEAR_CONFIRM`) naming the active profile; only meaningful when a
  profile is active.

## Fresh-install / no-profile state

A brand-new install has `KART_Profiles = {}` and `KART_Settings.activeProfile = nil`. The button
shows `L.PROFILE_NONE` ("No Profile"). This is a fully valid, ordinary state — nothing forces the
user to create a profile; profiles are purely an optional convenience layer on top of the
always-present `KART_Settings`.

## Testing

Manual (no automated test suite in this project): `/reload`, open `/kart` Settings tab, confirm
the new card renders with "No Profile". Change a few settings, Save As New "Test A", confirm
button now reads "Profile: Test A". Change more settings, Save As New "Test B". Switch back to
"Test A" via the dropdown, confirm the earlier settings are restored (checkboxes/sliders reflect
Test A's values, not Test B's). Delete "Test B", confirm it's gone from the dropdown. `/reload`
again, confirm `KART_Settings.activeProfile` and its values persisted correctly across reload.
