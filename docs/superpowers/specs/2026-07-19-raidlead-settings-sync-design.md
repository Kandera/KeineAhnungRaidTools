# Raidlead-Only Settings Sync — Design

## Purpose

Let a player push their Loot Council raid-lead-authority settings to one named target character,
who explicitly accepts or declines before anything changes locally. Distinct from two existing
mechanisms in this codebase:

- The existing `LC_CONFIG` broadcast (`LootCouncil.lua`'s `LC.BroadcastRaidConfig`/`LC.HandleConfig`)
  is automatic, raid-wide, and only writes to the ephemeral `LC.raidConfig` runtime table — it
  never touches `KART_Settings` and never persists, so it does not overwrite anyone's personal
  settings. It solves "everyone in this raid right now interprets votes identically."
- The just-built Profiles feature is local snapshot save/switch, no network transfer.

This feature solves a different problem: handing a specific person your Loot Council configuration
(e.g. onboarding a new officer) when you are not necessarily in the same raid, with their explicit
consent, persisted into their own `KART_Settings`.

Out of scope: broadcasting to multiple targets at once, a leader-only gate on sending (sending is a
deliberate one-to-one action the recipient must accept — no accidental raid-wide effect, so no
permission check is needed on the sending side), any settings outside the fixed 6-field set below.

## Synced field set

Exactly the "Raid-Wide Authority" fields from this addon's README, plus the vote timer (present in
raid-wide authority conceptually but not currently part of the existing `LC_CONFIG` broadcast
payload — this feature's payload is a separate, independent message format and includes it):

- `lcMinQuality`
- `lcButtonLabels`
- `lcRollsEnabled`
- `lcLootmaster`
- `lcVoteSeconds`
- `lcCouncilMembers`

No other `KART_Settings` keys are touched.

## Wire format

New addon-message prefixes, whispered via `C_ChatInfo.SendAddonMessage("KART", <msg>, "WHISPER",
<targetName>)` — the existing `"KART"` prefix is already registered by every KART client at
`ADDON_LOADED`, so no new prefix registration is needed.

**Request** (sender → target):
```
LC_SYNC_REQUEST:<minQuality>:<buttonLabels>:<rollsEnabled 0|1>:<lootmaster>:<voteSeconds>:<councilMembers>
```
Colon-delimited, `councilMembers` last (same reasoning as the existing `LC_CONFIG` format: it's
free text that may itself contain characters other than colons, so it's captured greedily as
everything after the 5th colon). Subject to the same 255-byte `SendAddonMessage` payload cap as
`LC_CONFIG` — reuse the existing truncation approach: if the fixed fields plus council list would
exceed the budget, trim the council list to whole semicolon-separated entries and warn the sender
locally that it was truncated.

**Reply** (target → sender, sent automatically after the target's popup choice):
```
LC_SYNC_ACCEPT
LC_SYNC_DECLINE
```
No payload needed — the sender already knows which target and which values it sent.

## Sender flow

New button in `LootCouncil.lua`'s raid-wide settings box (`raidBox`, same section as the existing
"Toggle Session" button), labeled "Sync Settings to Player...". Clicking it opens a
`StaticPopupDialogs` entry with `hasEditBox = true` (same pattern as the Profiles feature's
"Save As New" popup) prompting for a target character name. On accept, the sender reads its own
current `KART_Settings` values for the 6 fields, builds the `LC_SYNC_REQUEST` payload (applying
truncation if needed), and whispers it to the entered name.

No client-side validation that the name is online, real, or spelled correctly beyond non-empty —
`SendAddonMessage` to an invalid/offline target simply has no effect (WoW's own behavior, not
something this addon needs to detect or report).

## Receiver flow

`Core.lua`'s existing `CHAT_MSG_ADDON` dispatcher (the `elseif event == "CHAT_MSG_ADDON" and arg1
== "KART" then` branch) gets two new message-type branches, following the existing chain's
`msg:sub(1, N) == "PREFIX:"` style:

- `LC_SYNC_REQUEST:` → parse the 6 fields, show a `StaticPopupDialogs` confirm entry (not
  `hasEditBox`) with text `"Raidlead-Only Settings Sync from Player %s"` (formatted with the
  sender's short name via `text_arg1`), listing what it contains isn't required in the popup body
  itself (the settings names are technical, not meaningful to a raider deciding whether to trust a
  person) — the decision is about trusting the sender, not reviewing each field.
  - **Accept:** write all 6 fields directly into `KART_Settings`, call `KART.SyncSettingsToUI()`
    (already exists, from the Profiles feature's `Core.lua` refactor) to refresh every dependent
    widget/cache, whisper `LC_SYNC_ACCEPT` back to the sender.
  - **Decline:** whisper `LC_SYNC_DECLINE` back to the sender. Nothing else happens.
- `LC_SYNC_ACCEPT` / `LC_SYNC_DECLINE` → the original sender prints a chat line naming the target
  and the outcome (e.g. `"KART: <Target> accepted your raidlead settings sync."` /
  `"...declined..."`), so the sender gets closure without needing the target to say anything in
  chat.

## Security note

`CHAT_MSG_ADDON`'s `sender` argument is supplied by the WoW client itself from the actual message
origin — it cannot be spoofed by another addon or a crafted payload (unlike, say, a player-name
field inside a message body, which is just text). This is different from the existing `LC_CONFIG`
handler's leader-check, which exists because that message applies automatically with no human
decision point — a non-leader could otherwise self-promote onto the council with a forged broadcast.
This feature always requires an explicit human Accept click naming the real, unforgeable sender, so
no additional trust check is needed before showing the popup.

## Testing

Manual (no automated test suite in this project): two WoW clients (or the existing addon's Test
Mode pattern doesn't apply here — this needs a second real character, in-game, to whisper). Sender
changes a Loot Council setting, clicks "Sync Settings to Player...", enters the second character's
name, confirms. Second client sees the request popup naming the first character, clicks Accept —
confirm all 6 settings now match on the second client's Loot Council settings UI, and the first
client's chat shows an acceptance line. Repeat with Decline — confirm nothing changes on the second
client and the first client's chat shows a decline line. Test with a long council-member list to
confirm truncation behavior matches `BroadcastRaidConfig`'s existing pattern.
