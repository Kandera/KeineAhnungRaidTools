[English](https://github.com/Kandera/KeineAhnungRaidTools/blob/main/README.md) | **Deutsch**

# Keine Ahnung Raid Tools (KART)

Ein leichtgewichtiges und modulares World of Warcraft Addon, das speziell für Raid- und Gruppenleiter entwickelt wurde. Es vereinfacht das Einladungsmanagement, die Kontrolle der Schlachtzugsvorbereitung und bietet schnellen Zugriff auf wichtige Raidlead-Funktionen.

## Funktionen

### 1. Automation
Alle automatischen Gruppen-Funktionen gebündelt in einem Tab:
*   **Keyword-Invite:** Reagiert auf konfigurierbare Schlagworte (z. B. "inv", "+") im Flüstern, Gildenchat oder über das Battle.net. Der Gildenchat-Trigger ist ein eigener Schalter (standardmäßig deaktiviert), um versehentliche Invites durch normale Gildenchat-Gespräche zu vermeiden.
*   **Auto-Promote:** Befördert vordefinierte Spieler automatisch zu Assistenten, sobald sie der Gruppe beitreten. Ideal für Co-Leiter und feste Rollen im Raid. Jeder Eintrag akzeptiert wahlweise einen Charakternamen oder einen [Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools) (NSRT) Nickname, sodass er automatisch weitergilt, auch wenn diese Person auf einen anderen Charakter wechselt.
*   **Auto-Raid:** Wandelt die Gruppe automatisch in einen Schlachtzug um, sobald ein 6. Spieler um eine Einladung bittet; eine volle 5er-Gruppe bleibt eine Gruppe.

### 2. Raidlead-Leiste
Eine kompakte, verschiebbare Leiste für den schnellen Zugriff auf:
*   **Schlachtzugs-Symbole:** Setzen von Markern auf Ziele.
*   **Welt-Marker:** Platzieren von farbigen Säulen im Gelände.
*   **Ready-Check:** Startet sofort eine Bereitschaftsabfrage.
*   **Pull-Timer:** Anpassbarer Countdown für den Kampfbeginn (nativer WoW-Countdown, kein BigWigs/DBM nötig; Standard: 10 Sekunden).
*   **Tastenbelegung:** Ready-Check, Welt-Marker löschen, Pull-Timer und der Buff-Checker-Umschalter lassen sich jeweils im Raidlead-Einstellungstab auf eine Taste legen (Bind-Button klicken, dann die Taste drücken; die Taste wird dabei der Aktion entzogen, die sie zuvor belegt hatte, genau wie bei Blizzards eigener Tastenbelegung). Einmal gesetzt, funktionieren die Bindings auch während einer Kampfsperre weiter.

### 3. Erweiterter Ready-Check
*   Wenn Spieler auf "Nicht bereit" klicken, öffnet sich ein modernes Fenster, in dem sie schnelle Gründe (Bio, Trinken, 1 Min) oder einen eigenen Freitext angeben können. Diese Gründe werden dem Raidlead im Chat gepostet und im Buff-Checker über ein kleines Hinweis-Icon neben dem Namen angezeigt (voller Text im Tooltip beim Hovern) — unabhängig von der Textlänge, ohne dass das Layout überläuft.

### 4. Buff-Checker & KART Sync
Ein detailliertes Fenster zur Überprüfung der Raid-Vorbereitung:
*   **Stat-Check:** Überprüft Intelligenz, Ausdauer, Mal der Wildnis, Schlachtruf, Segen der Bronze und Himmelszorn.
*   **Verbrauchsgüter:** Zeigt an, wer Essen (Food), Fläschchen (Flask) oder Runen aktiv hat.
*   **Erweiterte Ansicht (Gear-Check):** Eine spezielle Ansicht zeigt das genaue Item-Level sowie fehlende Verzauberungen und Edelsteine. Ein interaktiver Tooltip verrät exakt, auf welchen Rüstungsslots diese fehlen.
*   **Waffenöl & KART Sync:** Über versteckte Addon-Nachrichten zwischen KART-Nutzern wird der exakte Status von Waffenöl ausgelesen, selbst wenn Spieler zu weit entfernt sind.
*   **Haltbarkeit:** Zeigt den Reparaturstatus der Ausrüstung (erfordert *LibDurability*).
*   **Bericht-Funktion:** Postet fehlende Buffs direkt in den Raid- oder Gruppenchat.
*   **Ready-Check Integration:** Öffnet sich automatisch bei einer Bereitschaftsabfrage.
*   **Modul-Schalter:** Der Buff-Checker lässt sich komplett deaktivieren, um CPU zu sparen, wenn man ihn nicht braucht. Der Hintergrund-KART-Sync (Öl/ilvl/Gear-Antworten für andere) bleibt davon unberührt aktiv, damit der Raidleiter trotzdem korrekte Daten über diesen Spieler sieht.

### 5. Loot Council
Koordinierte Lootverteilung direkt im Addon, ohne externe Tools:
*   **Session-Aktivierung:** Beim Betreten eines Raids wird der Lootmaster gefragt — oder, falls keiner festgelegt ist, der Raidleiter —, ob der Loot Council für diese Session aktiviert werden soll (für Spaßruns einfach ablehnen). Lässt sich jederzeit manuell umschalten.
*   **Raider-Abstimmung:** Sobald ein Item zur Verteilung ansteht, erscheint bei allen Raidern gleichzeitig eine Liste mit bis zu fünf konfigurierbaren Vote-Buttons (Standard: BIS / Upgrade / Offspec / Sonstiges / Pass) plus einem festen Transmog-Button sowie einem optionalen Notizfeld für Kommentare zur eigenen Stimme. Droppen mehrere Items gleichzeitig (der Normalfall bei den meisten Bossen), bekommt jedes Item seine eigene Zeile mit eigenem Countdown — alle Drops sind gleichzeitig sichtbar, sodass sich pro Item unabhängig entscheiden lässt (z. B. BIS auf das eine, Pass auf das andere), statt ein Item erst abhaken zu müssen, bevor das nächste überhaupt sichtbar wird. Eine Zeile markiert sich sofort nach der Stimmabgabe als erledigt und verschwindet, sobald ihre eigene Abstimmungszeit abgelaufen ist. Ein persönlicher Schalter wechselt diese Liste zwischen einem geräumigen Layout (größere Karten, Standard) und einem kompakten (kleinere einzeilige Zeilen mit Icon-only-Vote-Chips) für einen deutlich kleineren Fensterbedarf. Ein weiterer, unabhängiger persönlicher Schalter bestimmt, was mit einer Zeile passiert, sobald du für sie abgestimmt hast: Sie kann normal groß bleiben, kleiner werden oder ganz verschwinden (`/kart showall` holt sie zurück). Zwei weitere persönliche Schalter halten Items, die die eigene Klasse nicht anlegen kann, aus dem Weg: einer blendet sie aus und beantwortet sie mit der letzten konfigurierten Antwort, der andere stimmt für sie mit Transmog ab, solange das Aussehen in der eigenen Sammlung noch fehlt — beide sind standardmäßig aus, und `/kart showall` holt ein ausgeblendetes Item zurück.
*   **Council-Panel:** Die vom Raidleiter eingetragenen Council-Mitglieder — plus wer den Loot verteilt, der immer im Council ist — sehen ein bewegbares, scrollbares Panel mit allen Abstimmungen (klassengefärbt), sortiert nach Vote-Priorität. Zusätzlich wird pro Spieler die Item-Stufe (inkl. Icon) des aktuell getragenen Vergleichsitems im passenden Slot angezeigt, damit direkt ersichtlich ist, wer ein Upgrade bekommt, sowie eine Gilden-Rang-Spalte direkt neben dem Namen, damit Alts eines Spielers auf einen Blick erkennbar sind. Ein Minimieren-Button klappt das Panel auf nur noch Titelleiste und Item-Name zusammen, damit es während des normalen Raidens auf dem Bildschirm bleiben kann, ohne dass eine laufende Abstimmung im Hintergrund verloren geht. Ein optionaler persönlicher Schalter zeigt hier statt des Charakternamens den NSRT-Nickname jedes Kandidaten an — fällt automatisch auf den Charakternamen zurück, wo kein Nickname gesetzt ist. Laufen mehrere Rolls gleichzeitig, bekommt jedes Item einen eigenen Tab am linken Rand (eingefärbt in der Itemqualität, mit "Stimmen/Gesamt"-Anzeige) — ein Klick wechselt die Ansicht, ohne dass eine Zuweisung den Tab automatisch schließt, sodass sich in Ruhe zwischen den Items vergleichen und ggf. umentscheiden lässt. Hovern über einen Tab zeigt sofort die komplette Stimmverteilung aller Spieler für dieses Item, auch ohne umzuschalten; ein neu ankommender Tab bekommt nur einen kleinen "neu"-Punkt, statt den aktuell betrachteten Tab wegzureißen.
*   **Lootmaster:** Der Raidleiter kann einen Spieler festlegen — per Charaktername oder per NSRT-Nickname —, der jede Roll gewinnen muss (Need, oder Gier/Entzaubern falls Need nicht verfügbar ist), statt zu passen, damit er jedes Item physisch erhält und an denjenigen weitergibt, den das Council ausgewählt hat. Überschreibt die eigene Auto-Pass-Einstellung dieses Spielers; wird wie die Council-Mitgliederliste unten vom Raidleiter gesteuert, kein Schalter, den man sich selbst ausschalten kann.
*   **1-100 Zufalls-Rolls:** Optional per Einstellung aktivierbar (Raidleiter-Einstellung). Ist die Option an, bekommt jeder Raider, der in dem Moment für das Item berechtigt ist, in dem es zur Abstimmung ansteht, einen einzigartigen Wert von 1-100 zugeteilt — ohne Zurücklegen aus einem gemeinsamen Pool gezogen, sodass keine zwei Raider je dieselbe Zahl bekommen können (ein Raider, der erst nach der Ankündigung des Items beitritt, bekommt dafür keine Zahl) — als eigene Spalte im Council-Panel sichtbar, rein informativ und ohne automatische Auswirkung auf die Zuweisung.
*   **Council-Stimmen-Zähler:** Jede Zeile im Council-Panel hat einen "CV"-Button, mit dem jedes Council-Mitglied seinen persönlichen Favoriten markieren kann; die Zahl daneben zeigt die Gesamtzahl der Council-Stimmen für diesen Spieler. Rein zur Orientierung – die eigentliche Zuweisung läuft weiterhin ausschließlich über Rechtsklick → Zuweisen.
*   **Persistente Spieler-Notizen:** Über "Notiz bearbeiten" im Rechtsklick-Menü lässt sich eine dauerhafte Notiz zu einem Spieler hinterlegen (z. B. "hat schon BIS-Trinket"), sichtbar bei jedem Item, nicht nur bei einem einzelnen — anders als die Vote-Notiz eines Raiders. Wird an alle gerade online befindlichen Council-Mitglieder verteilt und übersteht Reloads.
*   **Rüstungsklassen-Hinweis:** Zeilen von Spielern, die die Rüstungsart des aktuellen Items gar nicht tragen können (z. B. Platte auf einem Magier), werden abgedunkelt angezeigt — rein visuell, Zuweisen per Rechtsklick funktioniert für jede Zeile trotzdem.
*   **Zuweisung per Rechtsklick:** Ein Rechtsklick auf eine Raider-Zeile öffnet ein Menü mit drei Optionen — **Zuweisen** (übernimmt die abgegebene Stimme als Grund) und **Ohne Grund zuweisen** (praktisch, wenn niemand das Item will, ohne die Loot-Historie zu verfälschen) vergeben das Item; eine Sperre mit Bestätigungsdialog verhindert dabei versehentliche Doppelzuweisungen. **Vote ändern** (Untermenü mit allen konfigurierten Vote-Buttons) ist rein kosmetisch und vergibt nichts — damit lässt sich nur der angezeigte Vote eines Spielers manuell korrigieren, z. B. wenn jemand per Whisper statt per Klick abgestimmt hat. Eine Zuweisung schließt den zugehörigen Tab nicht automatisch — das „×" direkt auf dem Tab dismisst gezielt nur dieses eine Item, „Kein Gewinner" schließt seinen Tab automatisch mit, und der „Schließen"-Button bzw. das „×" oben rechts minimiert nur das ganze Fenster (alle Tabs bleiben erhalten und tauchen beim nächsten Item wieder auf).
*   **Gewinner-Benachrichtigung:** Der ausgewählte Spieler erhält ein grünes Hinweisfenster; die Entscheidung wird automatisch im Raid- bzw. Gruppenchat angekündigt.
*   **Trade-Erinnerung mit Auto-Trade:** Nach einer Zuweisung an einen anderen Spieler merkt sich KART, wer noch was getradet bekommen muss, und zeigt ein kleines, verschiebbares Erinnerungsfenster mit allen offenen Trades (inkl. manuellem Abhaken-Button). Öffnet man ein Handelsfenster mit genau dem richtigen Spieler, wird das passende Item automatisch aus den eigenen Taschen ins Handelsfenster gelegt — bestätigt werden muss der Handel weiterhin manuell. Jeder offene Trade wird gegen das echte 4-Stunden-Bind-on-Pickup-Handelsfenster des Items mitgezählt; KART warnt 20 Minuten bevor es abläuft und entfernt den Eintrag still, sobald es so weit ist, statt ein nicht mehr handelbares Item in der Liste stehen zu lassen.
*   **Auto-Pass:** Optionaler Haken – sobald eine Loot-Roll beginnt, passen alle KART-Nutzer sofort, damit niemand versehentlich Need/Gier/Transmog anklickt, während der Council abstimmt. Diese Einstellung ist immer rein persönlich und unabhängig von der Mindest-Itemqualität.
*   **Raid-weite Autorität:** Abstimmungs-Timer, Vote-Buttons, die Council-Mitgliederliste, Mindest-Itemqualität und die Zufalls-Rolls-Option gelten für den gesamten Raid immer gemäß den Einstellungen des Raidleiters — nicht die lokalen Einstellungen jedes einzelnen Spielers. Verhindert, dass sich jemand z. B. selbst unbefugt ins Council einträgt oder die Abstimmungszeit zum eigenen Vorteil verkürzt. Im Options-Menü visuell in einer eigenen Box abgegrenzt, mit einer Live-Statusanzeige für einen von drei Zuständen: die eigenen Einstellungen gelten für den Raid (du bist Raidleiter), stattdessen gelten die Einstellungen des Raidleiters, oder — falls du den Namen einer anderen Person ins Lootmaster-Feld eingetragen hast — deine Einstellungen wirken sich bislang nirgends aus, bis du sie über "Settings an Spieler senden..." unten hinüberschickst. Council-Mitglieder lassen sich, genau wie der Lootmaster oben, jeweils als Charaktername oder als NSRT-Nickname eintragen.
*   **Mindest-Itemqualität:** Items unterhalb der gewählten Qualität (Standard: Episch) lösen den Loot Council gar nicht erst aus — das normale WoW-Würfelfenster greift stattdessen.
*   **Loot-Historie:** Vollständig synchronisiertes, durchsuchbares Protokoll der neuesten 500 Zuweisungen (Item, Spieler, Grund, Raid-Difficulty, Zeitpunkt; ist das Protokoll voll, wird der jeweils älteste Eintrag verworfen). Filter nach Spieler, Grund und Item-Name, Button zum Leeren der Historie. Jeder KART-Nutzer führt automatisch dieselbe Historie mit — nicht nur der Lootmaster. Betritt jemand einen Raid nach einer verpassten Session erneut, gleichen Clients fehlende Einträge still über den Addon-Kanal ab, ohne dass im Chat etwas sichtbar wird. Das Historie-Fenster paginiert, sobald es für eine Seite zu lang wird, und ein Export-JSON-Button speichert die aktuell gefilterten Einträge in eine Datei — Item-, Grund-, Instanz- und Slot-Felder werden dabei unabhängig von der Client-Sprache auf Englisch vereinheitlicht, sodass ein mehrsprachiger Raid trotzdem einen einheitlichen Export liefert, und zwar im selben Feldformat, das auch ein RCLootCouncil-Export verwendet, sodass Tools, die für dieses Format gebaut wurden, ihn ebenfalls lesen können.
*   **Modul-Schalter:** Loot Council lässt sich komplett deaktivieren (z. B. während der Testphase oder bei Konflikten mit einem anderen Loot-Addon wie RCLootCouncil) — dann werden keinerlei Nachrichten anderer KART-Nutzer mehr verarbeitet, kein Auto-Pass, keine Popups.
*   **KART-Status-Warnung:** Im Council-Panel zeigt ein rotes Symbol pro Raider an, wenn kein KART erkannt wurde, eine veraltete Version läuft oder der Spieler Loot Council lokal deaktiviert hat (Details im Tooltip).
*   **Test-Modus:** Zwei Testbuttons simulieren den Ablauf aus Sicht des Looters (Vote-Liste) und aus Sicht des Lootmasters (Council-Panel mit Tabs), unabhängig von der eigenen Raid-Rolle — und spielen dabei zusammen: Ein im Looter-Testfenster abgegebener Vote erscheint sofort im offenen Master-Testpanel, auch komplett solo ohne Gruppe. Es werden dabei gleich 4 echte (aber folgenlose) Items gleichzeitig verteilt (drei Waffen + ein Ring, damit auch der Zwei-Slot-Vergleich bei Ringen/Trinkets mitgetestet wird), damit sich auch das Verhalten bei mehreren gleichzeitigen Drops (Vote-Liste bzw. Tab-Leiste) durchtesten lässt — inklusive echter Itemsymbole, Tooltips, Rüstungsklassen-Hinweis und Ausrüstungsvergleich. Testrolls bleiben dabei rein lokal (kein Broadcast, keine Raidchat-Ankündigung, kein Eintrag in der echten Loot-Historie, keine Trade-Erinnerung).

### 6. WoWUtils Import
*   Raid-Zusammenstellungen lassen sich direkt aus WoWUtils per Copy-Paste importieren (Boss-für-Boss-Format mit Encounter, Difficulty und Invite-Liste).
*   Für jeden importierten Boss erscheint eine eigene Zeile mit Spieleranzahl und zwei Buttons:
    *   **Einladen:** Lädt alle Spieler der Boss-Liste ein, die noch nicht im Raid sind (bereits anwesende Mitglieder werden übersprungen).
    *   **Entfernen:** Kickt alle aktuellen Raid-Mitglieder, die NICHT auf der Boss-Liste stehen – ideal zum schnellen Umbau zwischen Bosskompositionen.
*   Mehrere Imports werden zusammengeführt statt überschrieben: Fügst du z. B. erst die Normal- und danach die Heroic-Zusammenstellung ein, bleiben beide Difficulties gleichzeitig in der Liste (Abgleich anhand Encounter + Difficulty). Ein **Zurücksetzen**-Button (mit Bestätigung) leert die Liste komplett.
*   **Split-Raids:** Importierst du für denselben Boss und dieselbe Difficulty ein zweites Mal ein anderes Roster (z. B. Team A und Team B bei einem Split), wird das nicht überschrieben, sondern als eigene Zeile ergänzt und automatisch als "Bossname A" / "Bossname B" usw. unterscheidbar benannt.
*   Der Import wird sitzungsübergreifend gespeichert und beim Login automatisch geladen.
*   **Modul-Schalter:** Lässt sich komplett deaktivieren, falls nicht benötigt.

### 7. Droptimizer-Gewinne
*   Zeigt eine **Gewinn**-Spalte im Loot-Council-Panel mit dem simulierten %DPS/HPS-Gewinn jedes Kandidaten durch das gerade gewürfelte Item, basierend auf Droptimizer-Sims, die bereits in WoWUtils importiert wurden (Raidbots oder QE Live).
*   Benötigt die separate **[KART Companion](https://github.com/Kandera/KART-Companion)**-App — ein kleines Tray-Tool in einem eigenen Repository, da WoW-Addons nicht selbst ins Internet können. Die meisten Raider brauchen es nicht: Nur eine Person, typischerweise der Lootmaster/Officer, muss es ausführen, da der WoWUtils-Group-Key bereits Zugriff auf die Sim-Daten des gesamten Rosters gewährt.
*   Der Companion synct in einem Intervall (oder auf Knopfdruck) in eine eigene SavedVariable, die das Addon bei `/reload` einliest — deine normalen Einstellungen oder die Loot-Historie werden dabei nie berührt.
*   Beim Hovern über das kleine Ausrüstungs-Icon eines Kandidaten werden das gewürfelte Item und dessen aktuell angelegtes Item nebeneinander angezeigt.
*   **Modul-Schalter:** Standardmäßig aus; aktivierbar über "Droptimizer-Gewinn % im Loot Council anzeigen" in den Loot-Council-Einstellungen. Der Sync-Status (zuletzt synchronisiert, Spieleranzahl) wird in den Allgemeinen Einstellungen angezeigt.

### 8. Anpassung (Settings)
*   Vollständig anpassbares Interface (Farben, Transparenz, Schriftarten). Die beiden Loot-Council-Fenster haben zusätzlich eigene Regler für Skalierung, Schriftgröße und Fensterebene, unabhängig vom Hauptfenster.
*   Standardkonforme Steuerung: Fenster und Textfelder lassen sich bequem mit der ESC-Taste schließen oder abwählen.
*   Unterstützung für Deutsch und Englisch.
*   Zugriff über Minimap-Icon oder das Addon Compartment Frame.
*   Versions-Checker: Prüfe, ob alle Raider die neueste KART-Version nutzen (`/kart v`).
*   **Modulare Deaktivierung:** Loot Council, Buff-Checker, WoWUtils und Droptimizer-Gewinne lassen sich jeweils einzeln komplett abschalten — praktisch während Testphasen oder um CPU bei Raidern zu sparen, die einzelne Funktionen nicht benötigen.

## Slash-Befehle

| Befehl | Beschreibung |
| :--- | :--- |
| `/kart` | Öffnet oder schließt das Hauptkonfigurationsfenster. |
| `/kart version` (`/kart v`) | Fragt die KART-Version aller Mitglieder deiner aktuellen Gilde, deines Raids oder deiner Gruppe ab und gibt die Antworten aus. |
| `/kart add <Item-Link(s)>` | Nur Lootmaster. Startet manuell eine Loot-Council-Abstimmung für ein oder mehrere eingefügte Item-Links, so als wären die Items gerade gedroppt. |
| `/kart lc` | Öffnet das Loot-Council-Abstimmungs-/Council-Fenster erneut, falls noch eine Roll aktiv ist. |
| `/kart trade` | Öffnet das Trade-Erinnerungsfenster erneut, falls noch ein Trade offen ist. |
| `/kart owed` | Öffnet die Liste der Items, die dir noch zustehen, erneut — der einzige Weg zurück, nachdem ihr eigenes "×" sie geschlossen hat. |
| `/kart showall` | Zeigt Roll-Zeilen, die aktuell durch deine persönlichen Anzeige-Einstellungen ausgeblendet sind (Anzeige abgestimmter Items oder "Items ausblenden, die meine Klasse nicht anlegen kann"). |
| `/kart status` | Gibt einen lokalen Diagnoseblock aus (Modul-Status, Session-Status, Lootmaster, Vote-Buttons, aktuell verfolgte Rolls und mehr), um nachzuvollziehen, warum ein Item bei jemandem nicht richtig angezeigt wird. |
| `/kart ench [raid]` | **Wartungswerkzeug, nicht für den normalen Spielbetrieb.** Gibt die Enchant-IDs aus, die dieser Client (bzw. mit `raid` die gesamte Gruppe) tatsächlich meldet — dient dazu, die Enchant-Prüfdaten des Addons jedes Tier aktuell zu halten. |
| `/kart help` (`/kart h`) | Gibt diese Befehlsliste aus. |

## Installation
1. Lade den Ordner `KeineAhnungRaidTools` herunter.
2. Kopiere ihn in dein World of Warcraft Verzeichnis: `_retail_\Interface\AddOns\`.
3. Starte das Spiel und aktiviere das Addon in der Addon-Liste.

## Mitwirkende
*   **Autor:** Kandera

## Fremde Bibliotheken
Unverändert mitgeliefert, jede unter ihrer eigenen Lizenz:

*   **[Ace3](https://www.wowace.com/projects/ace3)** (AceComm-3.0, CallbackHandler-1.0) — © Ace3 Development Team, BSD-artige Lizenz.
*   **ChatThrottleLib** von Mikk — gemeinfrei (Public Domain).
*   **[LibDeflate](https://github.com/SafeteeWoW/LibDeflate)** von Haoqian He — zlib-Lizenz.

## Lizenz
Dieses Projekt lizenziert unter der MIT-Lizenz - siehe die LICENSE.md Datei für Details.

*Erstellt für die Gilde "Keine Ahnung".*
