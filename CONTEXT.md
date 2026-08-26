# KART

Raid-lead addon and RCLootCouncil companion. Loot session, vote, trade and history stay RC's; KART must not hinder that flow.

## Language

**Companion**:
KART's 4.0 loot role: nick-stable council push, award relay, owed reminder. Not a second loot council.
_Avoid_: built-in LC, lootmaster field

**Co-Tank**:
The other tank's row: health, auras, taunt ask. Raid-only; off in dungeons, arenas and BGs.
_Avoid_: offtank frame, CT frame, party tank

**World row**:
The Co-Tank row on the world frame, shown in a raid when you are a tank and another tank exists.
_Avoid_: live row, unit frame

**Hosted preview**:
The Co-Tank row parented into the Co-Tank settings tab, for look/aura tweaks in town. Opening the tab does not force the world row.
_Avoid_: test mode (that's a separate invent-snapshot switch), dummy row

**Settings sync**:
After load and profile switch, the file that built a settings widget paints it from `KART_Settings`. Core only fans out.
_Avoid_: one Core map of every widget key

**Buff scan**:
`ScanBuffRoster` reads auras into a roster snapshot and `MissingBuffs`. The Buff Check window paints that snapshot; the tonight strip counts flask/food from it. Preview rows do not scan.
_Avoid_: a second flask/food loop for the strip
