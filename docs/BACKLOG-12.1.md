# Backlog 12.1 — prepared for the Midnight patch, nothing changed yet

Everything here was measured on the 12.1 PTR while the guild still raids on 12.0.7. **Nothing in this
file is applied until that raid is over** — a client-version fix landing before the last 12.0.7 raid
buys nothing and risks the evening.

Separate from `docs/BACKLOG.md` on purpose: those are defects in KART's own behaviour on the current
client, these are things the *client underneath* changes on a known date. Entries are numbered `P1`,
`P2`, … so they never collide with the `Bnn` numbers. Same status rule as `BACKLOG.md` — the status
word lives in the heading, anything without one is open.

An entry is deleted once it is fixed and verified in-game on 12.1; the code and `git log --grep=Pn`
carry it from then on.

## Sources, and how to re-check them

- [Patch 12.1.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes)
- `gh api repos/Ketho/BlizzardInterfaceResources/compare/12.0.7...12.1.0` — `Resources/GlobalAPI.lua`
  is the removed/added global list, `Resources/CVars.lua` the CVar defaults.
- `gh api repos/Gethe/wow-ui-source/compare/12.0.7...12.1.0` — the FrameXML source itself.

One trap, paid for once while diagnosing P1: **GitHub's compare API returns at most 300 files.** This
diff has more, so "the file is not in the list" proves nothing. Fetch the file at both tags and diff
it locally instead:

```sh
gh api repos/Gethe/wow-ui-source/contents/<path>?ref=12.0.7 --jq .content | base64 -d > a.lua
gh api repos/Gethe/wow-ui-source/contents/<path>?ref=12.1.0 --jq .content | base64 -d > b.lua
diff -u a.lua b.lua
```

---

# Tier 0 — breaks a core function the moment 12.1 goes live

## Measured on 12.1.0 (interface 120100), 2026-08-06 — solo PTR, `/kart ptr`

The first pass with the whole addon actually loaded on the new client, rather than read out of diffs.

**KART loads on 12.1 with no Lua error, and `/kart status` runs clean.** That was simply unknown
before and is the single most useful line here.

| | measured | consequence |
|---|---|---|
| `ActionButtonUseKeyDown` | `"1"` via `C_CVar.GetCVar` -- **and the bar was still dead** | P1 was real and is not explained by the CVar reading. Fixed by not depending on it, verified in-game 2026-08-06, entry deleted per this file's rule (`git log --grep=P1`) |
| `GetWeaponEnchantInfo` | **present**, returns `true / 7180552` | P2's premise is wrong for this build |
| own aura `name` / `spellId` | usable, not secret | P3 narrowed to OTHER units |
| `UnitIsGroupLeader("player")` | ordinary boolean | as expected; the group half is untouched |

**What a solo login cannot answer, and therefore what is still open:** every question in P3 and P4 is
about reading ANOTHER unit. The player's own identity is never secret, so a solo probe answers the
easy half of both and neither of the hard ones. Both need a group on 12.1.

## P2 — DEPRECATED, NOT REMOVED — `GetWeaponEnchantInfo` is dropped from the API list in 12.1

**Measured 2026-08-06 on 12.1.0: the function is still there and still answers** (`true / 7180552`
for a main hand carrying an oil). The evidence below is a diff of Blizzard's `Resources/GlobalAPI.lua`,
which is the documented list rather than the client -- being struck from the list is the step before
removal, not the removal. The oil column therefore works on 12.1 as shipped.

That drops this out of "must be done before the next raid" and into ordinary migration work: the
replacement exists, the old call will stop answering at some point, and doing it early costs nothing.
The signature question below is still the blocker for actually writing it.

### Original entry


`Resources/GlobalAPI.lua` drops it in the 12.0.7→12.1.0 diff. The replacement added in the same diff
is `C_PaperDollInfo.GetTemporaryEnchantmentInfo`. Blizzard migrated their own callers the same way
(`SecureTemplates.lua` now calls `C_PaperDollInfo.GetInventorySlotInfo` and
`C_PaperDollInfo.CancelTemporaryEnchantment`).

Four live call sites, all reading main-hand/off-hand temporary enchants:

- `Utils.lua:176`
- `BuffChecker.lua:995`
- `Libs/KAGS-1.0/KAGS-1.0.lua:222`
- `Libs/KASC-1.0/KASC-1.0.lua:358`

Plus the harness stub at `tests/wow_stubs.lua:638`, which has to move with them or the suite will
keep proving the old signature.

**MEASURED 2026-08-06 on 12.1.0**, two characters, same shape both times:

```
C_PaperDollInfo.GetTemporaryEnchantmentInfo(16)
  -> { enchantID = 8052, hasExpirationTime = true, remainingTimeMs = 6527852, chargesRemaining = 0 }
```

One table per SLOT (16 main hand, 17 off hand) where the old call returned eight flat values for both
hands at once. The mapping is mechanical: table present -> `hasMainHandEnchant`, `enchantID` ->
`mainHandEnchantID`, `remainingTimeMs` -> `mainHandExpiration`, `chargesRemaining` ->
`mainHandCharges`. 8052 is Thalassian Phoenix Oil, which matches the id already verified in
BuffChecker's bestSpells.

**Deliberately not migrated yet.** The old call still answers on 12.1 (see the heading), so this is
housekeeping with no deadline -- and two of the four sites are in shipped libraries, which means
version bumps. Touching KAGS and KASC for something that is not broken, in the fortnight before a
raid that decides whether the module survives, is the wrong trade. Do it after that raid.

**The original open question, now answered:** the return signature of
`C_PaperDollInfo.GetTemporaryEnchantmentInfo` had not been checked. The old call returns eight flat
values (`hasMH, mhExpiration, mhCharges, mhEnchantID, hasOH, …`); the `C_PaperDollInfo` namespace
returns structured tables elsewhere. Dump it on the PTR before writing any of the four call sites:

```
/dump C_PaperDollInfo.GetTemporaryEnchantmentInfo()
```

Two of the four sites are in shipped libraries (`KAGS-1.0`, `KASC-1.0`), so the fix carries a library
version bump.

## P3 — SOLVED 2026-08-06 — `C_UnitAuras.GetAuraDataByIndex` errors while auras are secret

**Measured on 12.1.0 with two people in a group, `/kart ptr`: another group member's
`aura.name` and `aura.spellId` are both usable.** Not secret, no error on comparison. The buff
checker reads exactly this for every group member, so the module works on 12.1 as shipped.

Note for anyone chasing #27 (buff food showing as missing): this is NOT that. The two looked alike
and they are unrelated -- #27 needs its own diagnosis.

### Original entry


12.1: *"C_UnitAura and C_TooltipInfo APIs that provide access to aura data via index, slot, or
instance ID will Lua error when called by addons while auras are secret."* APIs that go through spell
ID or spell name stay callable.

`BuffChecker.lua:891` is the one index-based call in the addon:

```lua
local aura = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
```

The existing `pcall(IsAuraSafe, aura)` two lines below does **not** cover this. It guards the
comparison against secret *values* inside an aura that was returned; 12.1 moves the error to the call
itself, before there is anything to guard. An error there aborts the whole row-update loop, so the
Buff-Checker window would stop populating rather than skip one player.

Blizzard names the condition: auras are secret *"during combat, encounters, M+, and PvP matches"*.
The Buff-Checker's real use is pre-pull and out of combat, so the question is only how often the
window is open when it is not.

### How to measure it, and the guard that falls out of it

There is a `C_Secrets` namespace that answers the condition directly instead of inferring it from an
error — and it exists **already on 12.0.7**, in both GlobalAPI dumps, not just on 12.1:

```
/dump C_Secrets.HasSecretRestrictions()
/dump C_Secrets.ShouldAurasBeSecret()
```

`HasSecretRestrictions` is documented as *"Returns true if this client build has secret value
restrictions enabled. If false, all APIs that are tagged as potentially returning secrets will never
do so."* Read it first, on whichever client is being measured: while it is `false`, every "works
fine" result below it is worthless.

`ShouldAurasBeSecret` is then the first candidate for the fix itself — skip or replace the index scan
while it is true. Because it ships on 12.0.7, that guard can be written and tested on the live client
before the patch, which is the only piece of this file that does not have to wait.

**Ungemessen:** whether the index call errors *only* when `ShouldAurasBeSecret()` is true, or already
under narrower conditions. Open the Buff-Checker window mid-pull on the PTR with both dumps next to
it.

### The shape of the fix

KART matches auras against spell IDs from `KART.BuffData` already, so the index loop is not load
bearing: a spell-ID query per configured buff stays legal in 12.1 and skips the 100-iteration scan
per player. That is a rewrite of the loop, not a wrapper, and it wants its own measurement of what
the spell-ID APIs return for a raid member rather than the player.

## P4 — SOLVED 2026-08-06 — unit APIs KART reads for authority return secrets when unit identity is secret

**Measured on 12.1.0 with two people in a group, `/kart ptr`: `UnitIsGroupLeader(raid2)` and
`UnitClass(raid2)` are both usable.** A group member's identity is not secret to their own group,
which was the open question and the one that decided whether this was nothing or Tier 0. It is
nothing.

The guard written before the answer (`KART.UnitLeads` / `KART.UnitAssists` in `Utils.lua`) stays, and
it is worth being clear that it is **not load-bearing**: nothing today needs it. It costs one pcall
per call and covers the contexts nobody has measured -- Blizzard's wording is "when the unit's
identity is secret", and a group member is only one kind of unit. Do not read its presence as
evidence that the raw API is unsafe here; it is not.

### Original entry


12.1: *"A number of Unit APIs are being changed to return secret values when the unit's identity is
secret."* The list includes `UnitClass`, `UnitIsGroupLeader`, `UnitIsGroupAssistant`, `UnitInRaid`,
`UnitIsRaidOfficer`, `UnitGroupRolesAssigned` and `UnitRace`. KART reads three of them, and one of
those decides who is allowed to run a loot distribution.

**Calls on `"player"` are not the worry** — the player's own identity is never secret. That covers
`Core.lua:351`, `Core.lua:547`, `GroupLogic.lua:56`, `Invite.lua:201`, `LootCouncil.lua:689`,
`LootCouncil.lua:818`, `LootCouncil.lua:1606`, `LootCouncil.lua:2574`, `KAUtil-1.0.lua:54` and
`LootCouncilRelevance.lua:181`.

**Calls on another unit are what needs measuring:**

| site | reads | what it decides |
|---|---|---|
| `LootCouncil.lua:698`, `:721`, `:1100`, `:1224` | `UnitIsGroupLeader(unit)` | who owns the loot / whether a peer's message is authorised |
| `GroupLogic.lua:134` | `UnitIsGroupAssistant(unit)`, `UnitIsGroupLeader(unit)` | auto-promote |
| `BuffChecker.lua:845`, `:869`, `LootCouncilPanel.lua:1349`, `LootCouncilTrade.lua:70`, `:1097` | `UnitClass(unit)` | class colour, display only |

A secret used in an `if` errors. The `UnitIsGroupLeader(unit)` sites sit in KART's authority checks,
so if group members' identities ever become secret in combat this stops being cosmetic and takes the
Loot Council with it. The display sites would only lose a colour.

**What is not known:** whether a raid member's identity is ever secret for their own group. The
Midnight rules make hostile and unknown units secret in combat; group members are the case that
decides whether P4 is nothing or Tier 0.

### The measurement plan

Three preconditions, all of which invalidate the result if skipped:

1. **Build 68914 or newer.** The change shipped in PTR 7 (2026-07-23); every earlier PTR round only
   carried it as "Preview of PTR 7". `/dump select(2, GetBuildInfo())`.
2. **A second player in the group.** Solo there is no `party1`/`raid1`, and a group member's identity
   is the entire question. Any PTR character will do.
3. **`C_Secrets.HasSecretRestrictions()` must be `true`** on the client being measured — otherwise
   nothing returns secrets at all and every green result is meaningless.

State probes, read together at each step:

```
/dump C_Secrets.HasSecretRestrictions()
/dump C_Secrets.CanCompareUnitTokens()
/run print(pcall(function() return UnitIsGroupLeader("party1") and 1 or 0 end))
```

`CanCompareUnitTokens` reads like the direct answer to this entry, but its signature is not in the
12.0.1 annotations — dump it before trusting it, it may take arguments.

Walk the states in this order, because they are not the same rule: solo out of combat → grouped out
of combat → grouped in open-world combat → grouped inside an encounter → M+. Record each.

`true 1` / `true 0` everywhere — close P4 as NO DEFECT and write down which states were actually
reached. `false <error>` in any state — the Loot Council needs a design answer, because the leader
check cannot be replaced by a client-side guess.

## P5 — Feature — guild chat coming from Discord does not reach the invite keyword

12.1 links guild chat to Discord and adds the event `CHAT_MSG_GUILD_DISCORD`; `ChatMessageEventParams`
gains a `discordInfo` field. KART's invite-by-keyword listener registers `CHAT_MSG_GUILD` only
(`Core.lua:13`, handled at `Core.lua:286-287` behind `KART_Settings.inviteViaGuildChat`).

If the guild links a Discord channel, a raider typing the keyword from Discord is invisible to KART.
Nobody loses anything that works today, so this is a feature decision, not a defect.

**Ungemessen:** whether a Discord-sourced message also fires `CHAT_MSG_GUILD`. If it does, there is
nothing to do. Needs a linked Discord channel to test, so it cannot be answered from the PTR alone.

The fix, if wanted, is one more `RegisterEvent` and one more `elseif` branch into the same handler.

---

# Checked and clear — do not re-derive

- **The raid-marker path itself is untouched in 12.1.** `SLASH_COMMAND.TARGET_MARKER` and
  `SLASH_COMMAND.TARGET` in `Blizzard_ChatFrameBase/.../SlashCommands.lua`, `SetRaidTarget` (still in
  `GlobalAPI.lua`), `SecureCmdOptionParse`, and the `SLASH_*` strings in `GlobalStrings/deDE.lua` and
  `enUS.lua` are all unchanged. The macro `/target [@target,noexists] player` + `/tm N` is still
  correct: `/target` resolves `target == "target"` back to the parsed action, so it targets the
  player. Do not "fix" the macro while chasing P1.
- **`SecureActionButtonTemplate` and `SECURE_ACTIONS.macro` are unchanged.** The whole
  `SecureTemplates.lua` diff is four hunks: `securecall("MacroFrame_SaveMacro")` →
  `securecallfunction(SaveMacro)`, the `C_PaperDollInfo` migration, whitespace, and in
  `SECURE_ACTIONS.click` a new `not delegate:HasAccessConstraints() and not
  delegate:HasAnyForbiddenAspects(Enum.ForbiddenAspect.ScriptedInput)` in place of
  `not delegate:IsForbidden()`. That last one cannot reach KART — the bar uses `type = "macro"`, never
  a `clickbutton` delegate.
- **The other globals removed in 12.1 are not used by KART:** `getglobal`, `setglobal`,
  `UIParentLoadAddOn`, `GetInventorySlotInfo`, `CancelItemTempEnchantment`,
  `GetInspectSpecialization`, `SetTableSecurityOption`, `CanSurrenderArena`,
  `C_Ping.GetContextualPingTypeForUnit`. Grepped across the addon and the bundled libraries.

- **The `## Interface:` line already lists `120100`.** No TOC change needed.
- **No event KART registers was removed or renamed.** The two removed in 12.1 are
  `BATTLETAG_INVITE_SHOW` and `HOUSING_LAYOUT_NUM_FLOORS_CHANGED`. Every event in `Core.lua:12-41`,
  `LootCouncilRelevance.lua:72` and `KASC-1.0.lua:309` survives unchanged.
- **The loot and ready-check APIs are untouched:** `RollOnLoot`, `ForceWinRoll`,
  `GetLootRollItemInfo`, `GetLootRollTimeLeft`, `ConfirmReadyCheck`, `DoReadyCheck`,
  `GetRaidTargetIndex` — none appear anywhere in the 12.1 change page.
- **Every `C_*` function KART calls is unchanged.** All 24 of them were checked by name against the
  change page: `C_AddOns`, `C_ChallengeMode`, `C_ChatInfo`, `C_Container`, `C_Item`, `C_LootHistory`,
  `C_MountJournal`, `C_PartyInfo`, `C_PetJournal`, `C_Timer`, `C_ToyBox`, `C_TransmogCollection`.
  The one hit, `C_BattleNet.GetAccountInfoByID` (`GroupLogic.lua:63`), is additive only —
  `BNetAccountInfo` gains `friendLevel`/`friendTags`, `BNetGameAccountInfo` gains `classFilename`,
  and KART reads `gameAccountInfo.characterName`/`realmName`, which stay.
- **`GetGuildInfo` losing compound unit tokens does not reach KART.** Both call sites
  (`LootCouncilPanel.lua:1082`, `:1117`) pass a plain token; the only tokens KART ever builds are
  `"raid"..i`, `"party"..i` and `"player"` (`BuffChecker.lua:844`, `KAUtil-1.0.lua:78`).
- **The forbidden-aspect rules cannot reach KART.** They apply to aura containers and aura buttons.
  KART creates neither, reparents no Blizzard frame, uses no `SecureAuraHeaderTemplate`, and its one
  `hooksecurefunc` (`LootCouncilSettings.lua:441`) hooks KART's own table.
- **KART reads no CVars in production code** — the only `GetCVar` in the tree is the harness stub
  (`tests/wow_stubs.lua:941`), so the CVar changes in 12.1 cannot move anything.

# How this sweep was run

So the next patch costs an hour rather than a day, and so nobody assumes more coverage than exists:

1. Removed symbols: every `-` line from `GlobalAPI`, `FrameXML`, `Mixins`, `Frames`, `Events`,
   `Templates`, `WidgetAPI`, `ScriptObjectAPI`, `CVars` and `LuaEnum` in the resources diff, minus
   everything re-added in the same diff — 220 names — each grepped against the whole addon including
   `Libs/`. **One hit: `GetWeaponEnchantInfo` (P2).**
2. Behaviour changes: the raw wikitext
   (`curl "https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes?action=raw"`) grepped against every
   API name KART calls, rather than reading the rendered page. That is what surfaced P3, P4 and P5.

**What this method cannot catch, and therefore is still open:** changes the page describes in prose
without naming the function — P3 was found that way only because the aura paragraph was read by hand
("APIs that provide access to aura data via index, slot, or instance ID"). Anything similarly worded
about frames, secure execution or item data would have been missed. The 12.1 PTR is also explicitly
incomplete: Blizzard's own note says the UnitAura changes and several aura-button protections were
not in the first PTR builds and land "over the next few weeks", so this file must be re-run against
the live 12.1 build before it can be called finished.
