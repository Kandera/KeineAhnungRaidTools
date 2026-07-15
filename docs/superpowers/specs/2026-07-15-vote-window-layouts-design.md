# Vote-Fenster Redesign: zwei wählbare Layout-Stile

**Datum:** 2026-07-15
**Status:** Zur Review

## Problem

`LC.RefreshVoteListRows` (LootCouncil.lua) stapelt jedes aktive Item als eigenen Block
untereinander: Icon, Timer, bis zu 5 Vote-Buttons in einem 3-Spalten-Raster, Notizfeld. Der
Abstand zwischen Blöcken ist nur 12px, das Fenster fix 380px breit. Bei mehreren gleichzeitigen
Rolls (z. B. Bosskill mit 3 Item-Drops) wirkt das laut Nutzer-Feedback "eng, gequetscht,
komisch" — die Blöcke hängen optisch aneinander statt sich klar voneinander abzusetzen.

Mockups mit den echten Farben/Maßen aus dem Code: <https://claude.ai/code/artifact/284ff918-b018-430e-abfc-53a04432add3>

## Entscheidung

Zwei Layout-Stile, als **persönliche Einstellung** (nicht raidweit synchronisiert — analog zu
`lcAutoPass`), per Checkbox umschaltbar:

1. **Geräumig** ("Kasten-Stapel") — neuer Standard, ersetzt das heutige Layout
2. **Kompakt** ("Icon-Chip-Liste") — Alternative für wenig Bildschirmplatz

Verworfen: ein 2-Spalten-Karten-Raster (braucht 620px Breite ohne echten Zusatznutzen gegenüber
"Geräumig") und ein horizontales Kartenband (900px breit, überlappt in der Praxis oft
Actionbars/Partyframes, erzwingt bei 4+ Items Scrollen während der Timer läuft).

## Stil 1: Geräumig (Standard)

Bleibt einspaltig (kein Breitenmehrbedarf durch ein Raster), aber jeder Item-Block wird zu einer
klar umrandeten eigenen Karte:

- Fensterbreite 380px → **540px** (genug, damit alle Vote-Buttons in *einer* Reihe statt zwei
  Platz haben)
- Abstand zwischen Karten 12px → **22px**
- Jede Karte bekommt eine eigene Hintergrundfläche (`SetBackdropColor` hell abgesetzt vom
  Fenster-Hintergrund) plus einen **3-4px Akzentstreifen oben** in der Item-Qualitätsfarbe
  (`ParseItemColor`, bereits vorhanden für den Icon-Rahmen)
- Icon 18px → 46px, Item-Name 12,5px → 15,5px, Buttons 26px → 34px Höhe — größere Elemente, weil
  jede Karte jetzt die volle Fensterbreite für sich hat statt sich eine Spalte zu teilen
- Notizfeld bleibt wie heute im Standard sichtbar (kein Toggle) — das Mockup hatte testweise
  einen Toggle, aber das kollabiert die Notiz-Sichtbarkeit unnötig; die gewonnene Höhe kommt
  bereits aus der einreihigen Button-Anordnung

Rendering bleibt in `LC.RefreshVoteListRows`, nur mit den oben genannten Maßen/Farben statt der
heutigen. Kein neuer Rendering-Pfad nötig — dieselben Frames (`row.itemIcon`, `row.btnArea`,
`row.noteBox` etc.) werden nur anders dimensioniert/gestylt.

## Stil 2: Kompakt (Alternative)

Eigener, deutlich kürzerer Rendering-Pfad, da strukturell anders (Buttons werden zu Icon-Chips
statt Text-Buttons):

- Fensterbreite bleibt **~430px**
- Jede Zeile ~44-56px hoch statt der heutigen ~130-150px pro Item
- Die 5 Vote-Buttons werden zu kleinen quadratischen Icon-Chips (24x24px, dieselben
  `VOTE_ICON_TEXTURES` wie heute schon als Button-Chip verwendet) direkt in der Zeile — ein Klick
  stimmt sofort ab, kein Ausklappen. Label als Tooltip beim Hover (`OnEnter`/`OnLeave`, analog zum
  bestehenden `row.itemHover`-Tooltip-Muster)
- Notiz: Stift-Icon, das bei Klick das bestehende `noteBox` einblendet (statt es immer zu zeigen)

## Architektur

- Neue Personal-Setting: `KART_Settings.lcVoteLayoutCompact` (boolean, Default `false` = Geräumig)
- Neue Checkbox in `LC.BuildSettingsPanel` (LootCouncil.lua, ~Zeile 2812), analog zu
  `KART.LC.CbAutoPass`:
  ```lua
  KART.LC.CbCompactVoteLayout = KART.CreateSettingsCheckbox(
      parent, "KART_LCCompactVoteLayout",
      L.LC_SET_COMPACT_VOTE_LAYOUT, "lcVoteLayoutCompact", <yOffset>,
      LC.RefreshVoteListRows, L.LC_DESC_COMPACT_VOTE_LAYOUT)
  ```
  **Offen für die Implementierung:** der Slot-Bereich zwischen `CbAutoPass` (-80) und dem
  reservierten Droptimizer-Slot (-110) bzw. dem Start der `raidBox` (-150) ist eng — die neue
  Checkbox braucht entweder einen eigenen Y-Offset unterhalb von -110 mit entsprechend
  verschobener `raidBox`, oder eine zweite Spalte. Wird beim Bauen final festgelegt.
- `LC.RefreshVoteListRows` verzweigt früh anhand von `KART_Settings.lcVoteLayoutCompact` in zwei
  Teilfunktionen (`LC.RefreshVoteListRows_Spacious` / `LC.RefreshVoteListRows_Compact`), die sich
  beide dieselben Datenquellen (`LC.voteListRolls`, `LC.rollItems`, `LC.rollDeadlines`,
  `LC.votes`, `LC.votedByMe`) teilen — kein doppelter State, nur doppeltes Rendering
- Der gemeinsame Ticker (`f.ticker`) bleibt unverändert; er aktualisiert nur Timer-Text pro Row,
  unabhängig vom gewählten Stil
- Beide Stile nutzen ausschließlich Mittel, die der Code heute schon hat: `BackdropTemplate`,
  `KART.CreateGradientOverlay`, farbige 1px-Ränder, `CooldownFrameTemplate`-Ring. Keine
  Schlagschatten/weichen Kanten — das waren HTML-Annäherungen im Mockup, in WoW bleibt es bei
  flachen Rechtecken

## Lokalisierung

Neue Strings in `Locales/enUS.lua` und `Locales/deDE.lua`:
`LC_SET_COMPACT_VOTE_LAYOUT`, `LC_DESC_COMPACT_VOTE_LAYOUT`

## Testing

Über den bestehenden `StartTest`-Mechanismus (mehrere simulierte Items gleichzeitig, siehe
`TEST_ITEM_COUNT`) beide Stile mit 1, 3 und 5+ gleichzeitigen Rolls durchklicken — insbesondere
der Umschlagpunkt, ab dem beim geräumigen Stil die Scrollbar greift.

## Out of Scope

- Karten-Raster- und Horizontales-Band-Layout (verworfen, s.o.)
- Änderungen am Council-Panel (`LC.RefreshCouncilRows`) — betrifft nur das Vote-Fenster der
  Nicht-Council-Raider
