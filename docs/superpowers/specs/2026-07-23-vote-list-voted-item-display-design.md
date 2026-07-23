# Vote-Fenster: Anzeige-Modus für bereits abgestimmte Items

**Datum:** 2026-07-23
**Status:** Zur Review

## Problem

Sobald ein Raider im Vote-Fenster (`LootCouncilVote.lua`, `KART.LC.Vote`) auf ein Item abstimmt,
bleibt die Karte/Zeile heute unverändert sichtbar — nur die Buttons verschwinden, ein Badge zeigt
die eigene Wahl. Bei mehreren gleichzeitigen Rolls (Bosskill mit 3 Drops) will ein Teil der
Spieler stattdessen: abgestimmtes Item verschwindet komplett aus dem Fenster, Fenster wird
kleiner, noch offene Items rutschen nach. Ein Slash-Befehl soll die versteckten Items bei Bedarf
wieder zurückholen. Nicht jeder Spieler will das — muss also opt-in, pro Spieler einstellbar sein.

Das überschneidet sich mit dem noch nicht umgesetzten Task 2 aus
`docs/superpowers/plans/2026-07-22-loot-council-features.md` ("Shrink a voted row in the Spacious
vote-list layout" — Karte wird kleiner, bleibt aber sichtbar, kein Toggle, nur Spacious-Layout).
Entscheidung dazu unten unter "Bezug zu Task 2".

## Entscheidung

Eine neue **persönliche Einstellung** (nicht raidweit synchronisiert — analog zu `lcAutoPass`,
`lcVoteLayoutCompact`), mit drei Werten statt eines einfachen Ein/Aus:

- **`full`** (Standard, heutiges Verhalten) — Karte/Zeile bleibt nach dem Abstimmen unverändert
  groß sichtbar, nur Buttons weg, Badge zeigt die Wahl.
- **`shrink`** — im Spacious-Layout schrumpft die Karte auf Kopfzeile + Badge (das ist der
  bisherige Task 2). Im Compact-Layout identisch zu `full` (die Zeile ist dort schon kompakt genug
  — kein zusätzlicher Verkleinerungs-Effekt, siehe unten).
- **`hide`** — Item verschwindet komplett aus der Liste (beide Layouts), Fenster wird kleiner.

Dazu ein neuer Slash-Befehl `/kart showall`, der bei `hide` alle aktuell aktiven Rolls wieder
zeigt (auch bereits abgestimmte). Bleibt aktiv, bis die komplette Rollliste leerläuft — nicht nur
ein einmaliger Snapshot.

## Bezug zu Task 2

Task 2 aus dem Feature-Plan geht komplett in diesem Task auf und wird dort gestrichen — sein
Verhalten wird zum `shrink`-Modus dieser neuen Einstellung, statt unconditional für alle. Die
Locate/Replace-Codeblöcke, die Task 2 bereits für `Vote.RefreshVoteListRows_Spacious` (Zeilenhöhe
pro Karte, laufender Y-Offset) beschreibt, werden 1:1 wiederverwendet — nur jetzt hinter
`KART_Settings.lcVotedItemDisplay == "shrink"` gated statt immer aktiv.

## Warum `shrink` im Compact-Layout nichts extra tut

Compact-Zeilen sind mit fester `rowH` (~78px, siehe `Vote.RefreshVoteListRows_Compact`) schon
deutlich kleiner als Spacious-Karten; nach dem Abstimmen wird dort bereits nur das Badge gezeigt
(`row.chipArea:SetShown(not voted)`), die Zeilenhöhe bleibt aber konstant. Ein zusätzliches
Schrumpfen würde kaum sichtbaren Gewinn bringen, aber eine zweite Höhen-Berechnung nötig machen.
`shrink` sieht in Compact deshalb identisch zu `full` aus — nur `hide` filtert dort wie in
Spacious komplett heraus.

## Architektur

### Sichtbare-Rolls-Filterung

Neue Funktion `Vote.GetVisibleRolls()`:

```lua
function Vote.GetVisibleRolls()
    if KART_Settings.lcVotedItemDisplay ~= "hide" or LC.showAllOverride then
        return LC.voteListRolls
    end
    local visible = {}
    for _, rollID in ipairs(LC.voteListRolls) do
        if not LC.votedByMe[rollID] then
            table.insert(visible, rollID)
        end
    end
    return visible
end
```

Ersetzt `LC.voteListRolls` überall dort, wo es heute für die **Anzeige** durchlaufen wird — nicht
dort, wo es die tatsächlich getrackte Roll-Menge ist:

- `Vote.RefreshVoteListRows_Spacious` / `_Compact`: Render-Loop, Tail-Hide-Loop
  (`for i = #LC.voteListRolls + 1, #f.rows do ...`), Höhen-Berechnung am Ende.
- Der geteilte Ticker in `Vote.CreateVoteList` (`f.ticker`): sein "schneller Pfad" (Timer-Text pro
  Zeile aktualisieren, ohne komplett neu zu rendern) matcht `pool[i]` gegen `LC.voteListRolls[i]`
  per Index — muss auf `Vote.GetVisibleRolls()[i]` umgestellt werden, sonst zeigt Zeile X den
  Timer von Item Y, sobald gefiltert wird.

**Bleibt unverändert auf der vollen `LC.voteListRolls`:** der Expiry-Teil desselben Tickers (räumt
abgelaufene Rolls aus `LC.voteListRolls` selbst), sowie jede reine State-Verwaltung
(`Vote.ShowVotePopup`, `Vote.RemoveVoteListItem`). Versteckte Items laufen im Hintergrund normal
weiter ab und verschwinden ganz normal, wenn ihr Timer abläuft — unabhängig davon, ob sie gerade
sichtbar sind.

Der Spacious-Renderer nutzt beim Rendern zusätzlich (unverändert von Task 2, nur jetzt gated)
`KART_Settings.lcVotedItemDisplay == "shrink"`, um pro Zeile zwischen normaler und geschrumpfter
Höhe zu wählen. Bei `hide` mit aktivem `showAllOverride` (also wieder eingeblendete, bereits
abgestimmte Items) werden diese in voller Höhe gezeigt — kein vierter visueller Zustand nötig.

### `/kart showall`

Neuer Branch in `SlashCmdList["KART"]` (Core.lua): setzt `LC.showAllOverride = true`, ruft danach
`LC.Vote.RefreshVoteListRows()` (die ungefilterte Variante, nicht `...RowsIfShown` — das Fenster
kann gerade komplett versteckt sein, wenn alle Items abgestimmt+ausgeblendet waren, und muss durch
den Befehl wieder erscheinen). Kein Effekt/keine Ausgabe, wenn nichts zu zeigen ist (gleiches
Schweige-Verhalten wie `/kart lc` / `/kart trade`).

`LC.showAllOverride` wird zurückgesetzt, sobald `LC.voteListRolls` leerläuft — Anschlussstelle:
der bestehende Early-Return in `Vote.RefreshVoteListRows`, wenn `#LC.voteListRolls == 0`. Damit
gilt "dauerhaft bis Rolls ablaufen" pro Batch gleichzeitiger Items; die nächste, komplett neue
Roll-Runde startet wieder normal im gewählten Anzeige-Modus.

### Settings-UI

Neuer Dropdown-Button (gleiches Muster wie `KART.LC.BtnMinQuality` — `KART.CreateModernButton` +
`MenuUtil.CreateContextMenu` mit drei Einträgen), in der persönlichen Einstellungs-Card
(`prefsCard` in `LootCouncil.lua`), direkt unter `KART.LC.CbShowNickNames`. Kein Checkbox-Muster,
da drei statt zwei Zustände.

## Lokalisierung

Neue Strings in `Locales/enUS.lua` und `Locales/deDE.lua`: Label + Tooltip für die neue
Dropdown-Einstellung, Beschriftungen der drei Menüpunkte (`full`/`shrink`/`hide`), sowie ein Eintrag
in der `/kart help`-Liste für `showall`.

## Testing

Über `StartTest` mit 3+ gleichzeitigen simulierten Items, für jeden der drei Modi: abstimmen und
prüfen, dass sich Fenster/Zeilen wie beschrieben verhalten (in beiden Layout-Stilen). Für `hide`
zusätzlich: alle Items abstimmen (Fenster schließt sich komplett), `/kart showall` ausführen
(Fenster erscheint wieder mit allen Items), warten bis alle Rolls ablaufen, neue Test-Runde
starten und prüfen, dass sie wieder normal versteckt.

## Out of Scope

- Council-Panel (`LootCouncilPanel.lua`, `KART.LC.Council`) — betrifft nur das Vote-Fenster der
  Nicht-Council-Raider, nicht die Entscheidungsansicht der Council-Mitglieder.
- Vierter Anzeige-Zustand für wieder eingeblendete Items unter `hide` (siehe oben — laufen als
  volle Höhe, kein Extra-Zustand).
