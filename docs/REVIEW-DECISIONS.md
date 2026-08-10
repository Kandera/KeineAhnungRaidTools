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
