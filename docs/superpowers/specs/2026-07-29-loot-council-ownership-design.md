# Loot Council: Besitz und Session als überprüfte Tatsache

**Datum:** 2026-07-29
**Status:** Zur Review
**Schließt:** B29, B30, B31, B32, B33 aus `docs/BACKLOG.md`

## Problem

Besitz (wer Loot verteilen darf, wem die raid-weite Konfiguration gehört) und Session-Zustand
(läuft gerade eine Council-Runde) sind über bis zu 30 Clients verteilt, ohne dass irgendwo
festgehalten wäre, wer recht hat. Fünf Fehler im Backlog, eine Wurzel.

Konkret gibt es heute **drei** Besitz-Ableitungen, die sich widersprechen:

- `LC.IsConfigOwner()` liest `KART_Settings.lcLootmaster` roh, ohne Rückfallebene.
- `LC.IsLootOwner()` liest `LC.GetLootmaster()` — eigene Einstellung, sonst synchronisierter Wert,
  sonst Raidleiter.
- `LC.IsSenderLootOwner()` leitet dasselbe pro eingehender Nachricht noch einmal ab.

Keine davon prüft, ob die genannte Person überhaupt noch da ist. `LC.raidConfig.lootmaster` ist ein
String, den kein Codepfad je zurücksetzt — und weil er *nicht leer* ist, wird die Raidleiter-
Rückfallebene unerreichbar. Das ist B29 in einem Satz.

Der Session-Zustand hat die zweite Hälfte: er ändert sich nur auf einer Nachrichten-*Kante*. Eine
verpasste Kante ist dauerhaft verpasst, ein Reload setzt ihn auf `false` zurück, und der einzige
Wiederherstellungsweg ist eine Frage, die ausgerechnet nur der Fragende beantworten dürfte.

## Zwei Annahmen, die sich beim Entwerfen als falsch erwiesen

Beides festgehalten, damit es nicht neu hergeleitet wird:

- **Es gibt in Retail keine Blizzard-Lootmaster-Rolle mehr.** `GetLootMethod` wird im Repo nirgends
  aufgerufen, und das ist richtig so — `ForceWinRoll` existiert genau deshalb: der Lootmaster muss
  Blizzards Gruppenwurf *gewinnen*, um das Item physisch zu halten. Als beobachtbare Rolle bleibt
  nur `UnitIsGroupLeader`.
- **„Ableiten statt speichern" geht nicht vollständig auf.** Wer Lootmaster ist, ist eine Tatsache
  über eine *andere Maschine* (`KART_Settings.lcLootmaster` auf deren Installation). Sie kommt über
  die Leitung und ist gespeichert, sobald sie ankommt. Rein ableiten ließe sie sich nur aus
  Raidlead — was die stehende Entscheidung vom 2026-07-25 ausschließt.

Die tragfähige Umformulierung lautet deshalb nicht „nicht speichern", sondern:

> Ein gespeicherter Schlüssel darf keine **Antwort** mehr sein, sondern nur noch **Eingabe** für
> eine Prüfung, die bei jedem Lesen gegen das aktuelle Roster läuft.

## Modell

### Eine Ableitung statt drei

Alle Besitzfragen laufen über eine einzige Funktion:

```
GetLootOwnerKey()
  1. Meine eigene Einstellung nennt mich, und ich bin da        -> ich
  2. Der synchronisierte Wert ist gesetzt UND diese Person
     ist im Roster auffindbar                                   -> diese Person
  3. Sonst: der Raidleiter
  4. Keine Gruppe                                               -> ""
```

Alles andere wird zur Projektion: `GetLootmaster()`, `IsLootOwner()`, `IsSenderLootOwner(k)` — und
**`IsConfigOwner()` wird zu `IsLootOwner()`**. Alle drei unabhängigen Entwürfe kamen auf dieselbe
Zusammenlegung; sie allein schließt B33.

Das tragende Wort in Schritt 2 ist **„und diese Person ist im Roster auffindbar"**. Eine Bedingung,
keine Nachricht, kein neuer Zustand, keine Mitwirkung anderer Clients.

### Anwesenheit heißt „im Roster", nicht „online"

`FindUnitForKey` findet auch einen Spieler mit Verbindungsabbruch — er steht weiter im Raid,
`UnitGUID` antwortet. Das ist Absicht. Würde `UnitIsConnected` mitgeprüft, wanderte der Besitz bei
jedem Verbindungshüpfer zum Raidleiter und zurück, während der eigentliche Lootmaster Items in den
Taschen hält, von denen die Handelsliste des Vertreters nichts weiß. Ein Verbindungsabbruch ist
vorübergehend, ein Raid-Austritt nicht.

### Ein bewusster Zwischenspeicher

`GetLootOwnerKey` durchsucht bis zu 40 Einheiten und wird aus Panel-Refreshpfaden aufgerufen. Das
Ergebnis wird pro **Roster-Generation** gemerkt — ein Zähler, der in `Core.lua`s
`GROUP_ROSTER_UPDATE`-Zweig hochgezählt wird und bei jedem Schreiben auf
`LC.raidConfig.lootmaster` oder `KART_Settings.lcLootmaster`.

Das ist ein Cache, und er wird ausdrücklich so benannt. Er unterscheidet sich von der Ursache von
B29 dadurch, dass sein Invalidierungsvertrag *jede* seiner Eingaben abdeckt und alle lokal und
ereignisgestützt sind. Der Vertrag gehört als Kommentar an das Feld, nicht nur an den Cache.

### Session: eine Entscheidung, dauerhaft dort abgelegt, wo sie getroffen wurde

Der Session-Zustand lässt sich nicht ableiten — geprüft und verworfen wurden: „läuft, wenn wir in
einer Raidinstanz sind" (nein, ein Trashfarm-Abend unterscheidet sich), „läuft, wenn Rolls verfolgt
werden" (zirkulär, `OnStartLootRoll` steigt bei ausgeschalteter Session vorher aus), „läuft, wenn
das Modul an ist" (das ist eine Installationseinstellung, keine Abendentscheidung).

Er wird also gespeichert — und zwar **nicht in `KART_Settings`**. `KART.LoadProfile`
(`Profiles.lua:23`) macht `wipe(KART_Settings)`; ein Profilwechsel mitten im Raid würde die Session
für den ganzen Raid stillschweigend beenden. Die Datei trägt den Präzedenzfall selbst: `autoLogOwned`
wird zwei Zeilen darüber ausdrücklich gerettet, mit dem Kommentar „runtime log ownership, not a
preference". Dieselbe Regel, eigene Tabelle:

```
KART_LCState = { active = <bool>, at = <time()> }
```

Neu in `## SavedVariables` der `.toc`. Genau zwei Werte, beide vor Gebrauch geprüft.

### Nach dem Reload: behaupten statt fragen

Heute fragt der nachladende Lootmaster den Raid nach dem Session-Zustand, und
`LC.HandleStateRequest` erlaubt die Antwort nur dem Loot-Owner — also ihm selbst. Das ist kein
Fehler in der Funktion, das ist, was diese Form zwangsläufig tut.

Künftig stellt der Besitzer beim Laden seinen eigenen Zustand aus `KART_LCState` wieder her und
**sendet ihn als Aussage** über den bestehenden `LC_ACTIVE`-Weg. Er ist der Besitzer — die Ableitung
sagt das auf seinem Client wie auf jedem anderen, weil er im Roster steht. Niemand muss antworten.

Die Wiederherstellung ist an drei Bedingungen geknüpft, die alle *abgeleitet* und keine gespeichert
sind:

1. `LC.InAnyRaid()` ist jetzt wahr, **und**
2. `LC.IsLootOwner()` ist jetzt wahr, **und**
3. `time() - at < 2h`.

Die gespeicherte Entscheidung darf also nur sprechen, solange sie das Jetzt noch plausibel
beschreiben kann.

Nicht-Besitzer stellen bewusst **nicht** aus ihrer eigenen SavedVariable wieder her — die
Entscheidung gehört ihnen nicht. Sie fragen wie bisher, und der Besitzer antwortet wie bisher; genau
dieser Fall war nie kaputt.

### Rollenübergabe

Beim Eintragen eines Nachfolgers sendet der abgebende Besitzer **vor** dem Aufräumen seines eigenen
Zustands ein `LC_RESIGN` (ohne Nutzlast). Empfänger prüfen es mit `IsSenderLootOwner` und leeren
daraufhin nur `LC.raidConfig.lootmaster` — jeder fällt damit sofort auf den Raidleiter zurück, bis
die eigene Konfiguration des Nachfolgers eintrifft.

Ein neues Token, kein leeres `LC_CONFIG`: ein alter Client würde ein `LC_CONFIG` mit leerem
Lootmaster-Feld annehmen und den **Abgebenden** als Lootmaster eintragen — schlechter als nichts zu
tun. Unbekannte Token verwirft KASCs Dispatcher stillschweigend.

### Übernahme durch den Raidleiter: mit Rückfrage

Verlässt der Lootmaster den Raid, greift Schritt 3 der Ableitung und der Raidleiter wird Besitzer.
Das passiert **nicht stillschweigend**: der künftige Besitzer bekommt eine Rückfrage („Der
Lootmaster ist weg. Lootverteilung übernehmen?"). Wer nicht bestätigt, ändert nichts an seinem
Verhalten.

Begründung, festgehalten: der Übernehmende beginnt, **jedes** council-fähige Item force zu gewinnen.
Dass sich jemandem unangekündigt die Taschen mit BoP-Loot füllen, ist keine Nebenwirkung, die man
per Chatzeile nachreicht.

### Namenskonflikt bleibt ungelöst, absichtlich

Tragen sich zwei Leute als Lootmaster ein, bleibt es bei der Entscheidung vom 2026-07-27: KART rät
nicht, sondern warnt. Nichts auf der Leitung sagt, wer wirklich verteilt. Die Warnung wird nur
zuverlässiger — sie wird zurückgesetzt, wenn der Konflikt verschwindet (bereits am 2026-07-29
behoben), und sie darf nur feuern, wenn das eigene Feld überhaupt gefüllt ist, sonst warnte jeder
Raidleiter mit leerem Feld über den echten Lootmaster.

## Zwei Änderungen an der Annahme von Konfigurationen

Beide ohne Änderung am Nachrichtenformat:

1. `TryAcceptConfig` trägt `raidConfig.lootmaster` **nur bei nicht-leerem Feld** ein. Eine
   Konfiguration mit leerem Feld wird angenommen (Labels, Mindestqualität, Würfe, Council-Liste
   gelten), lässt den Besitz aber abgeleitet. Ohne das würde die Zusammenlegung von `IsConfigOwner`
   und `IsLootOwner` dazu führen, dass der Raidleiter sendet, überall als Lootmaster eingetragen
   wird und der Besitz nach einem Leiterwechsel am *alten* Leiter klebt — eine Regression, die es
   heute nicht gibt. **Diese Falle steckt in der Zusammenlegung und darf nicht übersprungen werden.**
2. Eine Konfiguration mit leerem Lootmaster-Feld wird nur vom **aktuellen Raidleiter** angenommen.
   Auf der Empfängerseite selbst prüfbar, kein gespeicherter Zustand — dieselbe Rückfallebene, die
   `IsSenderLootOwner` heute schon kennt.

## Wiederherstellung ohne Einmal-Riegel

`LC.stateSyncRequested`, `LC.historySyncRequested` und `LC.promptedThisSession` sind gespeicherte
Antworten auf „habe ich das schon getan?", deren Gegenstand — *diese Raidmitgliedschaft* — sie nie
benennen. Zurückgesetzt werden sie nur beim bestätigten Austritt, weshalb B31s Ablauf sie dauerhaft
unverbraucht zurücklässt.

- Die Zustandsabfrage wird aus dem **Fehlen** abgeleitet statt aus einem gemerkten Ereignis: senden,
  solange wir im Raid sind, nicht Besitzer sind und keine Konfiguration haben. Begrenzt auf drei
  Versuche mit Rückstufung (5 s / 15 s / 45 s), zurückgesetzt bei bestätigtem Eintritt oder
  Leiterwechsel. Ohne Begrenzung würde in einem Raid ohne Konfiguration jeder ewig fragen.
- `PLAYER_ENTERING_WORLD` ruft `LC.CheckRaidJoin()` auf — das eine Ereignis, das ein Reload immer
  liefert. Hinter einer kurzen Beruhigungsverzögerung, weil Roster-APIs über einen Ladebildschirm
  hinweg unzuverlässig sind.
- `LC.promptedThisSession` wird symmetrisch zurückgesetzt: beim bestätigten Eintritt *und* Austritt.

## Warum jeder Fehler strukturell verschwindet

**B29.** `GetLootOwnerKey` kann in Schritt 2 keinen Schlüssel liefern, der die Roster-Prüfung nicht
besteht — die Prüfung steht *in* der Funktion, und alle Besitzfragen sind Projektionen davon. Die
zugesicherte Eigenschaft ist nicht mehr „wir haben daran gedacht, den Schlüssel auf jedem Pfad zu
löschen, der ihn veralten lassen kann" (eine offene Verpflichtung), sondern „der Schlüssel wird im
Moment seiner Verwendung gegen das Roster geprüft" (eine geschlossene). Die raid-übergreifende
Hälfte schließt separat, indem `TearDownForRaidExit` `LC.raidConfig` mit leert.

**B30.** Der nachladende Besitzer braucht keine Antwort mehr. Sein Zustand kommt von der eigenen
Platte, und er *sagt* ihn. Die Kategorie „Nachricht, die nur einer beantworten darf, und dieser eine
ist der Fragende" existiert im Ablauf nicht mehr.

**B31.** Zwei unabhängige Schließungen. Die Anfrage hängt nicht mehr an einem Riegel, den ein
verschlucktes Ereignis unverbraucht lassen kann, sondern an einer Bedingung, die so lange wahr
bleibt, bis sie erfüllt ist. Und der Wiederherstellungsweg hängt nicht mehr an einer einzigen
Ereignisklasse. Damit es noch hängt, müssten *beide* Ereignisse ausfallen **und** der Client bereits
eine Konfiguration besitzen.

**B32.** Das Fenster, in dem niemand Besitzer ist, wird von beiden Seiten geschlossen. `LC_RESIGN`
feuert aus genau dem Zweig, der die Übergabe schon heute erkennt — vor dem Aufräumen, das sie heute
verstummen lässt. Und selbst wenn die Nachricht verloren geht, führt der Austritt des Abgebenden zur
Präsenzprüfung aus B29 statt in den Dauerstillstand.

**B33.** `IsConfigOwner` liest `KART_Settings.lcLootmaster` nicht mehr. Es *ist* `IsLootOwner`, das
bei leerem Feld auf den Raidleiter fällt. Es gibt keinen Zustand mehr, in dem die Ableitung
„niemand" liefert: in einer Gruppe löst Schritt 3 immer jemanden auf. Damit sind
`ApplyOwnConfig`/`BroadcastRaidConfig` nie mehr ohne Besitzer, `CouncilNamesTable` ist immer
irgendwo gefüllt, und der B25-Label-Konflikt auf diesem Weg schließt mit.

## Voraussetzung, separat auszuliefern

`KASC:DefaultChannel()` (`Libs/KASC-1.0/KASC-1.0.lua:36-38`) ist
`IsInRaid() and "RAID" or "PARTY"` — ein blankes `IsInRaid()`, das nur die HOME-Kategorie sieht. In
einer Gruppenfinder-Gruppe gehen dadurch **alle** Addon-Nachrichten an „PARTY". Eine Zeile,
unabhängig von diesem Entwurf, und sie liegt unter allem anderen. Sie gehört **vor** diese Arbeit,
nicht hinein.

## Gemischte Versionen

Die stärkste Eigenschaft des Modells: **vier der fünf Reparaturen sind einseitig.**

- **Neuer Client, alles andere alt.** B29, B31, B33 und B32-aus-Sicht-dieses-Clients sind vollständig
  behoben — alle vier sind lokale Prüfungen. B30 ist behoben, wenn *dieser* Client der Besitzer ist,
  denn seine eigene SavedVariable stellt ihn wieder her.
- **Alter Client, neuer Lootmaster.** Der alte Client behält seinen veralteten Schlüssel und ignoriert
  `LC_RESIGN`. Das ist das heutige Verhalten, nicht schlechter, und es heilt, sobald die
  Konfiguration des neuen Besitzers eintrifft.
- **Alter Client, der selbst der nachladende Besitzer ist.** Weiterhin B30. Dagegen kann kein anderer
  Client etwas ausrichten.
- **Keine Nachricht eines neuen Clients kann einem alten schaden.** `LC_RESIGN` wird als unbekannt
  verworfen.

## Was das ausdrücklich nicht löst

- **B34** — ein Reload mitten im Roll verliert das Item weiterhin. Nur die Session wird dauerhaft,
  nicht die Rolls. Unentschiedene Rolls zu persistieren ist ein eigener Entwurf mit eigener
  Veralterungsfläche.
- **B35** — Doppelvergabe. Anderes Nebenläufigkeitsproblem; Vergeben ist per stehender Entscheidung
  bewusst nicht exklusiv.
- **Veraltete Council-Mitgliedschaft.** Ein ausgetretenes Council-Mitglied bleibt in
  `CouncilNamesTable`. Derselbe Präsenztrick würde wirken, ändert aber, wer Panels sieht und wer
  vergeben darf — eigene Entscheidung, eigener Abend.
- **Rückfall auf einen Raidleiter ohne KART.** Heutiges Verhalten, unverändert.

## Risiken

- **Stiller Besitzwechsel.** Entschärft durch die Rückfrage. Wer nicht bestätigt, ändert nichts.
- **Der Zwischenspeicher.** Schreibt eine künftige Änderung `raidConfig.lootmaster` auf einem Pfad,
  der die Roster-Generation nicht hochzählt, kehrt B29 in neuer Verkleidung zurück. Der
  Invalidierungsvertrag gehört als Kommentar an das Feld.
- **Das Wiederherstellungsfenster.** Wer innerhalb von zwei Stunden einem *anderen* Raid als
  Lootmaster beitritt, bekommt eine Session wiederhergestellt, die er vielleicht nicht wollte. Die
  Rückfrage hätte ihn ohnehin gefragt, aber es ist eine echte Verhaltensänderung und gehört ins
  Changelog.
- **Konfigurationen mit leerem Feld kommen jetzt vom Leiter.** Kleine neue Fläche: ein beförderter
  Assistent kann nicht senden, und ein Leiter kann keinen echten Lootmaster überschreiben, weil
  Schritt 2 vor Schritt 3 gewinnt.

## Verifikation

Kopflos testbar, nach dem Muster von `tests/test_lc_buttonconfig.lua` (Funktion aus der Quelle
extrahieren, Umgebung als Präambel stellen):

- `GetLootOwnerKey` über alle vier Schritte, insbesondere: gesetzter Schlüssel + Person nicht im
  Roster ⇒ Raidleiter, nicht „niemand".
- `IsConfigOwner() == IsLootOwner()` in jeder Konstellation.
- `TryAcceptConfig` mit leerem Lootmaster-Feld: Inhalte übernommen, Besitz nicht eingetragen,
  Annahme nur vom Leiter.
- Die Wiederherstellungsbedingung: außerhalb des Zeitfensters, nicht im Raid, nicht Besitzer — je
  keine Wiederherstellung.

Im Spiel nicht kopflos prüfbar und deshalb ausdrücklich benannt: die Rückfrage beim Besitzwechsel,
das Verhalten über einen echten Reload hinweg, und ob `LC_RESIGN` in einem gemischten Raid tut, was
es soll.
