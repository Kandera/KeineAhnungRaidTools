# Raidlead Bar Keybinds — Design

## Purpose

Four Raidlead Bar actions (Ready Check, Clear World Markers, Pull Timer, Buff-Checker Toggle)
are currently mouse-click only. Raid leads want keyboard shortcuts for these so they don't
have to move the mouse to the bar mid-encounter.

Out of scope: individual raid target icons and individual world markers (16 buttons) —
too many to usefully keybind one-by-one; not requested.

## Mechanism

`SetOverrideBindingClick(ownerFrame, false, key, buttonName, "LeftButton")` simulates a real
click on a named button. This works uniformly for both secure buttons (Ready Check and Clear
World Markers use `SecureActionButtonTemplate` macros) and plain `OnClick` buttons (Pull Timer,
Buff-Checker Toggle) — no need for different binding paths per action type. Override bindings
also work during combat lockdown (they don't mutate protected state, just route a keypress to
a click), unlike direct calls to protected API.

Prerequisite: `SetOverrideBindingClick` addresses buttons by their **global frame name**. The
four target buttons in `RaidleadBar.lua` are currently created with `CreateFrame("Button", nil, ...)`
(anonymous). They need global names:

- `KART_RL_ReadyCheckBtn`
- `KART_RL_ClearWorldMarkersBtn`
- `KART_RL_PullTimerBtn`
- `KART_RL_BuffCheckToggleBtn`

No other RaidleadBar buttons change.

## Storage

New table in the existing `KART_Settings` SavedVariable (same table personal prefs like
`pullTimerDuration` already live in):

```lua
KART_Settings.keybinds = {
    readyCheck = nil,          -- e.g. "F5"
    clearWorldMarkers = nil,
    pullTimer = nil,           -- e.g. "ALT-P"
    buffCheckToggle = nil,
}
```

`nil` / absent key = not bound. Format is whatever `GetBindingText`/key-capture produces
(standard WoW binding string, e.g. `"SHIFT-F5"`).

## Applying bindings

`KART.ApplyKeybinds()`:
- Clears all four override bindings owned by the addon, then re-sets each one present in
  `KART_Settings.keybinds` to its target button.
- Called on `PLAYER_LOGIN` and on every successful bind/unbind from the settings UI.
- Must not run while `InCombatLockdown()` is true — mirrors the existing guard in
  `KART.UpdateRaidleadBarVisibility`. The settings UI refuses to start a bind capture or clear
  a binding while in combat (see below), so this function is only ever invoked out of combat.
  `PLAYER_LOGIN` is the only hook needed.

## UI: new card in Raidlead tab (Tab 2)

Placed below the existing Raidlead Bar settings card in `MainFrame.lua`. Four rows, one per
action: label + a bind-button styled like `KART.CreateModernButton`.

- Bind-button text shows current binding (e.g. `"F5"`) or a placeholder (`"Not Bound"`) when
  unset.
- **Left-click** the bind-button → enters capture mode: text changes to `"Press a key…"`, an
  invisible full-addon-window key listener frame is shown that reacts to the next `OnKeyDown`.
- Next physical key (including modifiers held: SHIFT/CTRL/ALT combine into the binding string)
  sets `KART_Settings.keybinds[action]`, exits capture mode, calls `KART.ApplyKeybinds()`,
  updates button text.
- **Escape** while capturing cancels — no change, exits capture mode, restores previous text.
- **Right-click** the bind-button (outside capture mode) clears that binding immediately, calls
  `KART.ApplyKeybinds()`, updates text to `"Not Bound"`.
- No conflict detection against other addons'/Blizzard's bindings — last bind wins, consistent
  with how most addon-owned bind UIs behave. Not building a collision checker (YAGNI).

## Combat handling

Binding UI checks `InCombatLockdown()` when a bind-button is clicked (both for starting capture
and for right-click-clear). If in combat, no capture starts / no clear happens; button briefly
shows `"Not in combat"` (reusing the existing tooltip-flash pattern used elsewhere in the
settings UI) instead of entering capture mode.

## Testing

Manual: bind each of the 4 actions to a free key, verify triggering the key fires the same
effect as clicking the corresponding bar button (including in combat, since override bindings
must survive lockdown); verify Escape cancels; verify right-click clears; verify bindings
persist across `/reload`; verify capture and clear are refused while `InCombatLockdown()`.
