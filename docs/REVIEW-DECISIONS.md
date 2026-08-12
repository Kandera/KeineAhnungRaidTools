# Review Decisions — deliberately-not-fixed findings

Record of findings raised in the full-addon review (2026-07) that we **decided not to
change**, so a future review doesn't re-flag them as new. Each entry names the file/line, the
original concern, and why it stays as-is. When a decision is tied to a specific code spot, that
spot also carries a short `-- Reviewed 2026-07:` inline comment pointing here.

## Excluded by decision

- **Flask detection has no German "Phiole" term** (BuffChecker.lua, `flask` entry).
  Phiole is a Dragonflight-era name; we are past Dragonflight, so the missing term is moot.
  Flask detection stays name-based ("Fläschchen"/"Flask") without a Phiole branch.

- **Oil name fallback marks any oil as "best"** (BuffChecker.lua `isOil` handling).
  Resolved 2026-07-25: only the current rank's enchantIDs count as "best" — the three Midnight oils
  plus the two blacksmithing stones. Class mechanics sharing the weapon slot (shaman imbues, rogue
  poisons, paladin Holy Armaments) are neutral, everything else is reported as wrong rank.
  Superseded the same day: the name fallback (`find("Oil")/"Öl"`) was **removed entirely**, not
  changed to "wrong". As a bare substring it also matched "Coil", "Turmoil", "Wölfe" and "Höllen…",
  and because `MergeBuffState` only lets "best" beat "wrong", one such aura pinned the column red for
  a shaman with a legitimate imbue or any raider without KART. An oil is a temporary weapon enchant
  and never appears as an aura at all, so the fallback could only ever add false positives. The
  enchantID pass is now the sole writer of the oil state. **Do not re-add a name fallback.**

- **Manual rolls don't purge stale state on a rollID collision** (LootCouncil.lua
  `LC.HandleManualStart`). Kept 2026-07-25. `LC.HandleStart` calls `PurgeStaleRoll` because Blizzard
  reuses server rollIDs constantly; manual IDs are self-issued from a per-client seed
  (`MANUAL_ROLL_ID_BASE + time() % 100000`), so a collision needs the lootmaster role to change
  mid-raid between two people who logged in seconds apart AND both to have used `/kart add`. Only the
  lootmaster can issue these at all and they are rare by nature. Not worth the extra purge path on a
  code path that would otherwise stay untested. `LC.rollItems[rollID]` is already overwritten
  unconditionally, so the item itself is always right; only `LC.votes[rollID]` could carry over.

- **`vantus` buff matched name-only, English "Vantus"** (BuffChecker.lua, `vantus` entry).
  Resolved 2026-07-25: the 12.0 and 12.1 spellIDs are now the primary detection path, with the
  English name kept as a fallback for future rune versions.

- **`bronze` `nameMatch = "Bronze"` English-only** (BuffChecker.lua, `bronze` entry).
  Kept. spellIDs are the primary detection path; the single-language name is a fallback only.

- **Hardcoded UI micro-strings** kept as-is:
  - `"CV"` council-votes column header (LootCouncilPanel.lua).
  - `"iLvl"`, `"Item Level "`, `"s"` seconds suffix (LootCouncilPanel.lua).
  - `"s"` seconds suffix in the vote timer (LootCouncilVote.lua).
  These are compact, universally-understood labels; not worth a locale key.

- **Clear-World-Markers macro uses `/cwm <n>`** (RaidleadBar.lua).
  Verified fine — the command exists on the clients we target. No change.

- **`GOOD_ENCHANTS` is a hardcoded list with no opt-out** (Utils.lua). Intended. Anything not on the
  list is reported as "(wrong enchant)", so a wrong ID or a patch adding new enchants shows every
  correctly-enchanted player as red — that loud failure is accepted deliberately, in exchange for
  catching an outdated enchant at all. The lists are a per-patch maintenance item. The only built-in
  softening stays as-is: a slot whose list is missing or empty falls back to a presence-only check
  (`IsGoodEnchant`'s `#good == 0` branch), so slots can be filled in one at a time. Do not propose a
  settings toggle for this.

## Design rules

- **The advanced Buff-Checker panel is never chat-reported.** Oil, enchants, and gems live on the
  separate, opt-in advanced panel (`page = "advanced"` in `KART.BuffData`); their missing state must
  never be posted to raid chat via the Report button. The dead "gear check → report" code path
  (which used to build a `Name (-N)` string) was removed, and `KART.ReportMissingBuffs`' feed is
  gated on `buff.report and buff.page ~= "advanced"`. Do not wire advanced-panel items into the
  report.

## Verified, no change needed

- **An expiry note stamped `true` can never be cleared by the heartbeat** (LootCouncil.lua,
  `LC.HandleTable`'s expiry-note purge). Raised 2026-08-06. A client whose "???"-tracked roll
  expired holds `LC.rollExpiredHere[rollID] = true`, and the different-item clear requires a string
  on both sides — so if it then also misses a reuse's own announcement, it stays silent about the
  new item until round end. Requires the owner to have been unable to name the item all the way to
  expiry (otherwise the B40 in-place repair resolves the link first) plus a lost announcement on
  top. The comment above the purge chooses "erring towards silence" explicitly, mirroring the
  settled dismissal-note shape. Bounded by the round-end wipe. Kept.

- **`itemID ~= "0"` in the expiry-note purge is dead** (LootCouncil.lua, same block). The receiver
  normalizes a heartbeat's `"0"`/`""` itemID to nil before the purge runs, so the condition can
  never see the string "0". Harmless defensive redundancy that reads as a live branch; noted here
  instead of removed — deleting it invites re-adding it on the next read of the sender's "=0"
  convention.

- **`LC_CONFIG` colon-in-button-label desync** (LootCouncil.lua BroadcastRaidConfig / HandleConfig).
  Already mitigated: the button-labels, council-members, and lootmaster edit boxes all strip
  colons at input via `StripColons` (LootCouncilSettings.lua). No colon can enter these synced
  fields, so the payload separator is safe. Not a live bug.

- **AutoLog M+ keystone detection** (AutoLog.lua `MatchContent`).
  `C_ChallengeMode.GetActiveKeystoneInfo()` returns 0/nil outside an active run; worst case is
  logging a few seconds early on zone-in, which is harmless. The difficultyID path guards
  independently. Kept as-is.

- **Any group member can inject an `LC_VOTE`/`LC_ROLL`** inflating straw-poll counts
  (LootCouncilVote.lua). By design: votes are keyed by resolved GUID (self-key only), so they
  can't be forged for another player. The council straw poll is informational and never drives an
  assignment automatically. No trust-model change.

- **Repair/durability shows 100% for a churn `UNKNOWN` name** (BuffChecker.lua UpdateBuffCheck).
  The cache miss defaults to 100% ("no data = assume fine", intended to avoid false alarms). The
  `UNKNOWN` edge is transient and self-corrects on the next update tick; not worth risking the
  repair renderer (which needs a number) to special-case it.

- **Raidlead bar visibility during combat** (RaidleadBar.lua `UpdateRaidleadBarVisibility`).
  The in-combat early-return is correct (protected calls), and Core.lua already re-calls this on
  `PLAYER_REGEN_ENABLED`, so visibility IS reconciled when combat ends. Not a bug.

- **`Trade.ResolveColorForReason` compares config labels across locales, and `GetDuplicateOrdinal`
  counts test items** (LootCouncilTrade.lua). Both are fallback/test-only paths: the color compare
  only runs when a peer sent no packed color (colorPacked is the primary path), and the ordinal
  test-item overlap is only reachable while a test session is active. Left as-is.

- **Static labels not refreshed on a live language switch** (LootCouncilPanel/Settings, MainFrame
  council headers, no-winner/close/quality/voted-display buttons) and the hardcoded `"Friz Quadrata"`
  font-fallback label. Kept: the language picker always triggers `ReloadUI` (see DESC_LANGUAGE), so
  these are rebuilt on reload — registering them for live refresh would be dead code with no live
  effect. "Friz Quadrata" is a font proper noun.

## Verified, no change needed (2026-08 review of v3.3.2..HEAD)

- **A merged vote card's "(2x)" disagrees with the council's "(1/3)"** (LootCouncilVote.lua
  `Vote.CardItemSuffix` vs LootCouncilTrade.lua `Trade.GetDuplicateOrdinal`). Raised as a defect,
  withdrawn on reading. The two answer different questions on purpose: the ordinal's denominator counts
  every copy in `LC.rollItems`, closed and awarded ones included, while the card's count is
  `DuplicateGroup`'s set -- the copies still answerable on this client, which is exactly the set
  `Vote.CastVote` fans the answer out to. So the number on the card is the number of rolls the click
  answers, and a card reading "2x" beside three council tabs is correct. Both comments now say so.
  Do not "reconcile" the two numbers.

- **`CollapseCopies` picks a survivor the ordinal does not call (1/N)** (same file). The comment claimed
  it did; corrected rather than the code. What the merge needs is that clients holding the same
  answerable copies pick the same one, which the lowest answerable rollID gives. A closed copy with a
  lower number makes the survivor (2/N) in the ordinal, and nothing rests on those agreeing.

- **A second catch-up request inside `HISTORY_FULL_COOLDOWN` can return nothing at all**
  (LootHistory.lua `LH.AnswerHistoryRequest`). Measured in round three of the 2026-08 review and kept.
  The floor at `if sinceTime < lastFull then sinceTime = lastFull end` is deliberate -- an asker whose
  own copy is behind an earlier full answer would otherwise read as "send me everything again", which is
  the repeat the cooldown exists to prevent -- so a hole that predates the last full answer, or one that
  answer failed to deliver, waits the hour out. The hour is itself the chosen recovery bound for exactly
  that case (maintainer's ruling, 2026-08-07: "an hour lets that client recover the same evening
  instead"). What keeps it from mattering is redundancy, not this branch: every peer holding the entry
  answers, so a full answer is several independent whispers. The misleading half of the comment ("you
  get the incremental answer") is corrected; the behaviour is not.

- **Several peers answer one catch-up request** (LootHistory.lua `LH.HandleHistoryRequest`). By design,
  asserted as such in `tests/test_lc_churn.lua` ("more than one peer answered the catch-up"), and the
  award id deduplicates the copies. Measured at four answering peers in a five-client raid; the B135/B139
  message counts were taken against 30 clients on this same code. Not a traffic defect.

- **`ENCHANTED_TOOLTIP` does not handle a positional insertion either** (Utils.lua
  `EnchantNameForSlot`). The third site of B163's defect class, found by sweeping for it. This one
  escapes correctly and then turns `%%s` into a capture, which is the right order -- but a locale
  writing `%1$s` survives the escaping as `%%1$s`, no capture is ever made, the pattern matches
  nothing and the function answers nil. Left as-is, and the reason is reachability rather than
  correctness: it has exactly one caller, `KART.PrintEnchantDump` behind `/kart ench`, which is a
  maintenance tool the maintainer runs on their own client; both shipped locales write the plain form;
  and the failure is a "?" in a printed dump. `ENCHANTED_TOOLTIP` is not even in the harness, so fixing
  it means building stub support for a maintenance command. B163 was fixed instead of recorded because
  it sits in the loot path and runs on every drop -- that is the difference, not the pattern.

- **A client that loses BOTH an award and the reconcile answer stays short until the next raid**
  (LootHistory.lua `LH.AnswerHistoryRequest`, the `HISTORY_FULL_COOLDOWN` branch). Measured and left,
  2026-08-10, on the maintainer's reasoning.

  The sequence needs two independent losses on ONE client in one window: the `LC_RESULT` for an award,
  and then the `LC_HIST_BATCH` that B171's round-end reconcile pulls in to repair it. Every peer stamps
  its full-answer allowance on the SEND (nothing acknowledges a batch), so all of them fall back to the
  incremental answer, which is floored at that stamp -- and the missing rows are older than the floor.
  Measured at 9 of 12 awards over a four-boss evening, silently, and it does not recover inside the
  evening because past the cooldown nothing asks again.

  **Why it is left:** measured, it heals at the next raid.

  ```
  after the evening:   lm=3  raider=0
  after the next raid: lm=3  raider=3
  assigner ever short? false
  ```

  A raid JOIN asks, the hour is long gone by then, and a full answer lands. What is short in between is
  one raider's own history WINDOW. It is not what reaches WoWUtils: that comes from the Companion, fed
  by the client that exports, and the exporting client is the assigner -- which logs its own award
  locally and cannot be short one by this path at all.

  **The fix that was built and reverted:** one extra full answer per cooldown window when the asker's
  checksum still differs after the first, which is evidence the first never landed. It works (12/12) and
  it does NOT touch the relog storm the cooldown was written for -- measured, a genuine relog keeps its
  SavedVariables and its checksum matches exactly (`171759418` before and after), so five relogs in a row
  produce zero full answers even with the rule active. It was still reverted: the gain is a display
  window between two raids, and the cost is reopening a maintainer ruling ("an hour, and deliberately not
  an evening") plus rewriting the test that encodes it.

  Note the test in question models its relog by emptying `KART_LootHistory`, which is not what a relog
  does. If this is ever revisited, that construction is the thing to look at first.

- **B171's own value, stated correctly.** The same measurement re-prices the round-end reconcile that
  shipped: a single lost `LC_RESULT` would also have healed at the next raid join. What B171 buys is
  WHEN -- the end of the round rather than days later -- and that C7 holds as written, "every client
  names the same winner", rather than eventually. At +20 chunks and +684 bytes per evening that is worth
  having, but the justification is the Manifest's wording and not data the raid would otherwise lose.
  The first write-up of it implied the latter; it should not be read that way.

## Verified, no change needed (2026-08-12 review of the Auto-Raid conversion fix)

- **A deferred bulk-invite conversion is skipped for good if combat is active when the party fills
  up** (`KART.pendingBulkRaidConvert`, set in Invite.lua's bulk WoWUtils invite). It is only read on
  `GROUP_ROSTER_UPDATE` (Core.lua:401); `PLAYER_REGEN_ENABLED` (Core.lua:496) never touches it, so a
  flag armed while in combat is never re-checked once combat ends, and the 120-second timer
  (Invite.lua:209) clears it silently in the meantime. Deliberate: this fails closed rather than
  retrying the conversion after combat.

- **The 120-second expiry timer on that same flag is not generation-counted per invite**
  (Invite.lua:205-209). A second bulk invite started within 120 seconds of the first inherits the
  remainder of the first invite's window instead of getting its own. Deliberate -- the flag is
  one-shot and cheap, not worth a generation counter.
