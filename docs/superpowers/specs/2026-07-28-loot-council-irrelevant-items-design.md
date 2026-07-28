# Vote-Fenster: irrelevante Items ausblenden und automatisch abstimmen

**Datum:** 2026-07-28
**Status:** Zur Review
**Issue:** [#11 "Items usable"](https://github.com/Kandera/KeineAhnungRaidTools/issues/11)

## Problem

Gemeldet von Nara/Kevin: als Leder-Druide bekommt er im KART-Vote-Fenster jedes
Council-Item vorgelegt, auch Platte und Waffen, die seine Klasse nicht anlegen kann.
Er muss auf allem eine Stimme abgeben oder das Item auslaufen lassen. Sein Wunsch:
etwas wie RCLootCouncils Auto-Pass auf nicht tragbare Items.

Präzisierung durch den Reporter: die Grenze verläuft entlang der **Klasse**, nicht
des Specs. Ein Caster-Lederteil will er als Feral weiterhin sehen und bewerten
können ("ob Main oder Off spec"). Nur was er überhaupt nicht anlegen kann, ist für
ihn und für den Council unnötiger Clutter.

Zweiter Teil des Wunsches (vom Maintainer eingebracht): für ein nicht tragbares Item
kann ein Aussehen trotzdem interessant sein. Seit The War Within sind Transmog-
Erscheinungen **über Rüstungstypen hinweg sammelbar** — ein Lederträger, der ein
Plattenteil gewinnt, bekommt das Aussehen gutgeschrieben. Ein automatischer
Transmog-Vote auf nicht tragbare Items ist damit sinnvoll, aber nur solange das
Aussehen noch fehlt.

**Nicht betroffen:** Blizzards eigenes Loot-Roll-Fenster. Der bestehende Ablauf —
Lootmaster gewinnt per `ForceWinRoll`, alle anderen passen per `lcAutoPass`
(`LootCouncil.lua:1490-1501`) — bleibt unverändert. Dieses Feature wirkt
ausschließlich im KART-Vote-Fenster.

## Verhalten

Zwei neue persönliche Schalter, beide standardmäßig **aus**:

1. **Irrelevante Items ausblenden**
2. **Automatisch Transmog wählen, wenn mir das Aussehen fehlt**

Entscheidungsreihenfolge, pro Item, auf jedem Client, bevor die Zeile gezeichnet wird:

1. Item ist relevant **oder** die Relevanz ist nicht ermittelbar → normal anzeigen.
   Unbekannt zählt nie als irrelevant — dieselbe Haltung wie
   `Council.IsArmorEligible` (`LootCouncilPanel.lua:256-264`), die im Zweifel
   niemanden ausblendet.
2. Item ist irrelevant:
   - Schalter 2 an **und** Aussehen noch nicht gesammelt → automatische
     **Transmog**-Stimme. Ab da ist es ein ganz normal abgestimmtes Item; die
     bestehende Einstellung `lcVotedItemDisplay` (full/shrink/hide) regelt die
     Sichtbarkeit.
   - Sonst, Schalter 1 an → automatische **Pass**-Stimme, Zeile ausgeblendet.
   - Sonst → normal anzeigen, heutiges Verhalten.

Bewusste Folge: mit **beiden** Schaltern an bleibt ein irrelevantes Item sichtbar,
wenn das Aussehen fehlt. Es ist dann kein Clutter mehr, sondern etwas, das der
Spieler haben will.

Warum Schalter 1 abstimmt statt still auszublenden: der Council sieht den Spieler
sonst über die volle Vote-Dauer als "hat noch nicht abgestimmt", der
Fortschrittszähler wird nie voll, und der Council wartet auf Stimmen, die nie
kommen. Eine sofortige Pass-Stimme macht die Runde schneller entscheidbar.

### Ausnahmen

- **Testrolls** (`LC.IsTestRoll`) durchlaufen den Filter nicht — sonst räumt sich
  das Testfenster selbst leer und der Test zeigt nichts.
- **Items mit noch unaufgelöstem Link** (`LC.rollItems[rollID] == "???"`) werden
  übersprungen, bis `ResolveRollItemLink` (`LootCouncil.lua:1329-1342`) nachliefert.
  Ohne Link ist keine der beiden Abfragen entscheidbar.

## Erkennung

Hybrid aus zwei Quellen, weil keine allein überall verfügbar ist.

**Irrelevant:**
- Wo der Client eigene Rolldaten hat: `canNeed == false` aus
  `GetLootRollItemInfo(rollID)`. Blizzards eigenes Urteil, deckt Rüstungstyp und
  Waffen ab und bleibt bei Klassen-Reworks automatisch korrekt.
- Sonst: Rüstungstyp aus dem Itemlink über `Council.GetItemArmorRank` +
  `Council.IsArmorEligible` (`LootCouncilPanel.lua:249-264`). Waffen werden in
  diesem Fall **nicht** erkannt — bewusst, um keine Waffenproficiency-Tabelle pro
  Klasse pflegen zu müssen.

Der Fallback ist nötig, weil ein Client, der kein eigenes `START_LOOT_ROLL` bekommt
(tot, außer Reichweite, ineligible — siehe den Kommentar in
`LootCouncil.lua:1528-1532`) das Item nur über `LC_START` kennt und lokal gar keinen
Roll hat. Auch `/kart add`-Items hatten nie einen Blizzard-Roll.

**Aussehen fehlt:**
- Wo Rolldaten vorhanden: `canTransmog` aus derselben API-Rückgabe. Das bedeutet
  bereits "sammelbar und noch nicht besessen".
- Sonst: `C_TransmogCollection` — das Item hat überhaupt eine Erscheinungsquelle
  **und** diese ist noch nicht gesammelt. Ringe, Hälse und Trinkets haben keine
  Quelle und fallen damit nie unter Schalter 2.

### Offene Annahme

Ob "ineligible" in Blizzards Sinn auch Rüstungsklassen-Ineligibilität einschließt —
also ob Kevin für ein Plattenteil überhaupt ein `START_LOOT_ROLL` erhält — ist nicht
kopflos beweisbar. Trifft es zu, greift der Rüstungs-Fallback statt `canNeed`, und
Waffen werden für ihn nicht gefiltert. Das ist kein Fehlverhalten, nur weniger
Filterung als möglich; eine `/run`-Sonde im nächsten Raid klärt es.

## Buttons

**Fester Transmog-Button.** `LC.GetButtonConfig` (`LootCouncil.lua:201-228`) kappt
die frei konfigurierbaren Labels künftig bei **5** statt 6 und hängt einen festen,
nicht umbenennbaren Transmog-Eintrag als **letzten** an. Bewusst "letzter" statt
starr Index 6: bei nur drei konfigurierten Labels entstünden sonst leere Buttons.

Der Button ist bei jedem Item anklickbar, nicht nur bei irrelevanten — wer ein Item
ausschließlich fürs Aussehen will, kann das damit auch von Hand sagen.

Zwei Nebenwirkungen, beide klein und für die Release Notes:
- Ein Raid, der heute sechs eigene Labels nutzt, verliert den sechsten.
- Der Raid nutzt aktuell einen selbst konfigurierten Transmog-Button auf Position 5
  vor Pass. Nach dem Update erscheinen kurzzeitig zwei Transmog-Buttons, bis der
  Raidleiter den eigenen aus der Konfiguration löscht.

**Pass.** Schalter 1 stimmt mit dem **letzten frei konfigurierten** Label ab, per
Default "Pass". Benennt ein Raidleiter den letzten Button in etwas um, das kein Pass
ist, stimmt der Schalter falsch ab. Bewusst in Kauf genommen; steht im Tooltip der
Einstellung.

**Versionsmischung** ist bereits abgesichert: jede Stimme trägt ihre `buttonCount`
mit (`Vote.CastVote`, `LootCouncilVote.lua:270-280`, siehe B25), sodass ein
Empfänger mit abweichender Buttonzahl "weiß ich nicht" anzeigt statt eines falschen
Labels. Der zusätzliche Transmog-Slot erbt diesen Schutz ohne Protokolländerung.

## Automatische Stimmen sind korrigierbar

`Vote.CastVote` (`LootCouncilVote.lua:251-253`) blockt heute jede zweite Stimme für
denselben Roll. Für eine **automatisch** gesetzte Stimme wird diese Sperre gelöst:
erkennt der Filter etwas falsch, holt der Spieler das Item per `/kart showall`
zurück und stimmt um. Die erste manuelle Stimme sperrt dann wie gewohnt.

Empfängerseitig kostet das nichts: `Vote.HandleVote`
(`LootCouncilVote.lua:947-948`) schreibt pro Absender in `LC.votes[rollID]` und
überschreibt eine frühere Stimme ohnehin.

## Einstellungen

Zwei Checkboxen im LC-Einstellungs-Tab, direkt unter Auto-Pass
(`LootCouncilSettings.lua:163-167`), **persönlich und nie synchronisiert** — wie
Auto-Pass selbst. Neue Keys in `KART.Defaults` (`Utils.lua:46-66`):

| Key                  | Default |
|----------------------|---------|
| `lcHideIrrelevant`   | `false` |
| `lcAutoTransmogVote` | `false` |

Beide aus, damit das Update für bestehende Nutzer ohne Zutun nichts ändert. Strings
in `Locales/enUS.lua` und `Locales/deDE.lua`.

## Code

**Neue Datei `LootCouncilRelevance.lua`** (~80 Zeilen) mit der gesamten
Entscheidungslogik: "ist das irrelevant für mich", "fehlt mir das Aussehen", "welche
Stimme folgt daraus". Die drei bestehenden LC-Dateien sind mit 1000–1900 Zeilen groß
genug; diese Logik ist eine klar abgrenzbare, reine Abfrage ohne UI-Bezug und damit
kopflos testbar. Eintrag in `KeineAhnungRaidTools.toc` vor `LootCouncilVote.lua`.

**Ein einziger Aufrufpunkt:** oben in `Vote.RefreshVoteListRows`
(`LootCouncilVote.lua:185`), vor dem Rendern. Dieser Pfad läuft bei jedem neuen
Roll, jeder Stimme, jedem Ablauf-Sweep und nach dem Nachladen eines Itemlinks —
also auch dann noch, wenn der Link beim Auftauchen des Items erst `"???"` war. Ein
Roll wird höchstens einmal automatisch beantwortet.

**`Vote.GetVisibleRolls`** (`LootCouncilVote.lua:172-183`) bekommt den zweiten
Ausblendgrund neben `lcVotedItemDisplay == "hide"`. `LC.showAllOverride`
(`/kart showall`) deckt beide gleichermaßen auf.

## Verifikation

**Kopflos:** neue `tests/test_lc_relevance.lua` gegen `tests/wow_stubs.lua`, nach dem
Muster von `tests/test_lc_votewire.lua`. Abgedeckt wird die volle
Entscheidungstabelle:

- relevant / irrelevant / Relevanz unbekannt
- Schalter 1 und 2 in allen vier Kombinationen
- Aussehen vorhanden / fehlend / keine Erscheinungsquelle
- Link noch nicht aufgelöst
- Testroll
- beide Erkennungspfade (mit und ohne lokale Rolldaten)

**Im Spiel:**
- `/kart test` zeigt weiterhin alle Testitems, unabhängig von den Schaltern.
- Mit beiden Schaltern aus verhält sich das Vote-Fenster exakt wie heute.
- Ein echter Raid klärt die offene Annahme oben und bestätigt, dass Kevins
  Plattenteile verschwinden bzw. als Transmog-Stimme durchgehen.

## Auslieferung

Patch-Release vor der Antwort im Issue, wie üblich: Commit, `.toc`-Version,
Changelog-Eintrag in `CHANGELOG.md` **und** `CHANGELOG-de.md` (eine Zeile, fetter
Lead), Tag, grüne CI. Issue #11 bleibt offen, bis Nara/Kevin es im Raid bestätigt.
