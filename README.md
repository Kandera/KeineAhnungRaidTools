# Keine Ahnung Raid Tools (KART)

Ein leichtgewichtiges und modulares World of Warcraft Addon, das speziell für Raid- und Gruppenleiter entwickelt wurde. Es vereinfacht das Einladungsmanagement, die Kontrolle der Schlachtzugsvorbereitung und bietet schnellen Zugriff auf wichtige Raidlead-Funktionen.

## Funktionen

### 1. Automation
Alle automatischen Gruppen-Funktionen gebündelt in einem Tab:
*   **Keyword-Invite:** Reagiert auf konfigurierbare Schlagworte (z. B. "inv", "+") im Flüstern, Gildenchat oder über das Battle.net.
*   **Auto-Promote:** Befördert vordefinierte Spieler automatisch zu Assistenten, sobald sie der Gruppe beitreten. Ideal für Co-Leiter und feste Rollen im Raid.
*   **Auto-Raid:** Wandelt die Gruppe automatisch in einen Schlachtzug um, sobald mehr als 5 Mitglieder beitreten.

> Die frühere „Paste Raid Composition"-Funktion (Bulk-Invite per Copy-Paste) wurde entfernt und vollständig durch den [WoWUtils Import](#6-wowutils-import) ersetzt.

### 2. Raidlead-Leiste
Eine kompakte, verschiebbare Leiste für den schnellen Zugriff auf:
*   **Schlachtzugs-Symbole:** Setzen von Markern auf Ziele.
*   **Welt-Marker:** Platzieren von farbigen Säulen im Gelände.
*   **Ready-Check:** Startet sofort eine Bereitschaftsabfrage.
*   **Pull-Timer:** Anpassbarer Countdown für den Kampfbeginn (Standard: `/pull 10`).

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
*   **Session-Aktivierung:** Beim Betreten eines Raids wird der Raidleiter gefragt, ob der Loot Council für diese Session aktiviert werden soll (für Spaßruns einfach ablehnen). Lässt sich jederzeit manuell umschalten.
*   **Raider-Abstimmung:** Sobald ein Item zur Verteilung ansteht, erscheint bei allen Raidern gleichzeitig ein Popup mit konfigurierbaren Vote-Buttons (Standard: BIS / Upgrade / Offspec / Sonstiges / Pass) sowie einem optionalen Notizfeld für Kommentare zur eigenen Stimme.
*   **Council-Panel:** Raidleiter, Assistenten und frei definierte Council-Mitglieder sehen ein bewegbares, scrollbares Panel mit allen Abstimmungen (klassengefärbt), sortiert nach Vote-Priorität. Zusätzlich wird pro Spieler die Item-Stufe (inkl. Icon) des aktuell getragenen Vergleichsitems im passenden Slot angezeigt, damit direkt ersichtlich ist, wer ein Upgrade bekommt.
*   **Zuweisung per Rechtsklick:** Ein Rechtsklick auf eine Raider-Zeile öffnet ein Menü mit drei Optionen — **Zuweisen** (übernimmt die abgegebene Stimme als Grund), **Zuweisung ändern** (Untermenü mit allen konfigurierten Vote-Buttons, um den Grund nachträglich zu korrigieren) und **Ohne Grund zuweisen** (praktisch, wenn niemand das Item will, ohne die Loot-Historie zu verfälschen). Eine Sperre mit Bestätigungsdialog verhindert versehentliche Doppelzuweisungen. Das Panel schließt sich dabei nie von selbst — nur über den „Schließen"-Button oder das „×".
*   **Gewinner-Benachrichtigung:** Der ausgewählte Spieler erhält ein grünes Hinweisfenster; die Entscheidung wird automatisch im Raid- bzw. Gruppenchat angekündigt.
*   **Auto-Pass:** Optionaler Haken – sobald eine Loot-Roll beginnt, passen alle KART-Nutzer sofort, damit niemand versehentlich Need/Gier/Transmog anklickt, während der Council abstimmt. Diese Einstellung ist immer rein persönlich und unabhängig von der Mindest-Itemqualität.
*   **Raid-weite Autorität:** Abstimmungs-Timer, Vote-Buttons, zusätzliche Council-Mitglieder und Mindest-Itemqualität gelten für den gesamten Raid immer gemäß den Einstellungen des Raidleiters — nicht die lokalen Einstellungen jedes einzelnen Spielers. Verhindert, dass sich jemand z. B. selbst unbefugt ins Council einträgt oder die Abstimmungszeit zum eigenen Vorteil verkürzt. Im Options-Menü visuell in einer eigenen Box abgegrenzt, mit Live-Anzeige der aktuellen Rolle ("Du bist Raidleiter" / "Einstellungen des Raidleiters gelten").
*   **Mindest-Itemqualität:** Items unterhalb der gewählten Qualität (Standard: Episch) lösen den Loot Council gar nicht erst aus — das normale WoW-Würfelfenster greift stattdessen.
*   **Loot-Historie:** Vollständig synchronisiertes, durchsuchbares Protokoll aller Zuweisungen (Item, Spieler, Grund, Raid-Difficulty, Zeitpunkt). Filter nach Spieler, Grund und Item-Name, Button zum Leeren der Historie. Jeder KART-Nutzer führt automatisch dieselbe Historie mit — nicht nur der Lootmaster. Betritt jemand einen Raid nach einer verpassten Session erneut, gleichen Clients fehlende Einträge still über den Addon-Kanal ab, ohne dass im Chat etwas sichtbar wird.
*   **Modul-Schalter:** Loot Council lässt sich komplett deaktivieren (z. B. während der Testphase oder bei Konflikten mit einem anderen Loot-Addon wie RCLootCouncil) — dann werden keinerlei Nachrichten anderer KART-Nutzer mehr verarbeitet, kein Auto-Pass, keine Popups.
*   **KART-Status-Warnung:** Im Council-Panel zeigt ein rotes Symbol pro Raider an, wenn kein KART erkannt wurde, eine veraltete Version läuft oder der Spieler Loot Council lokal deaktiviert hat (Details im Tooltip).
*   **Test-Modus:** Zwei getrennte Testbuttons simulieren den Ablauf aus Sicht des Looters (Vote-Popup) und aus Sicht des Lootmasters (Council-Panel), unabhängig von der eigenen Raid-Rolle.

### 6. WoWUtils Import
*   Raid-Zusammenstellungen lassen sich direkt aus WoWUtils per Copy-Paste importieren (Boss-für-Boss-Format mit Encounter, Difficulty und Invite-Liste).
*   Für jeden importierten Boss erscheint eine eigene Zeile mit Spieleranzahl und zwei Buttons:
    *   **Einladen:** Lädt alle Spieler der Boss-Liste ein, die noch nicht im Raid sind (bereits anwesende Mitglieder werden übersprungen).
    *   **Entfernen:** Kickt alle aktuellen Raid-Mitglieder, die NICHT auf der Boss-Liste stehen – ideal zum schnellen Umbau zwischen Bosskompositionen.
*   Der Import wird sitzungsübergreifend gespeichert und beim Login automatisch geladen.
*   **Modul-Schalter:** Lässt sich komplett deaktivieren, falls nicht benötigt.

### 7. Anpassung (Settings)
*   Vollständig anpassbares Interface (Farben, Transparenz, Schriftarten).
*   Standardkonforme Steuerung: Fenster und Textfelder lassen sich bequem mit der ESC-Taste schließen oder abwählen.
*   Unterstützung für Deutsch und Englisch.
*   Zugriff über Minimap-Icon oder das Addon Compartment Frame.
*   Versions-Checker: Prüfe, ob alle Raider die neueste KART-Version nutzen (`/kart v`).
*   **Modulare Deaktivierung:** Loot Council, Buff-Checker und WoWUtils lassen sich jeweils einzeln komplett abschalten — praktisch während Testphasen oder um CPU bei Raidern zu sparen, die einzelne Funktionen nicht benötigen.

## Slash-Befehle

| Befehl | Beschreibung |
| :--- | :--- |
| `/kart` | Öffnet oder schließt das Hauptkonfigurationsfenster. |

## Installation
1. Lade den Ordner `KeineAhnungRaidTools` herunter.
2. Kopiere ihn in dein World of Warcraft Verzeichnis: `_retail_\Interface\AddOns\`.
3. Starte das Spiel und aktiviere das Addon in der Addon-Liste.

## Mitwirkende
*   **Autor:** Kandera

## Lizenz
Dieses Projekt lizenziert unter der MIT-Lizenz - siehe die LICENSE.md Datei für Details.

*Erstellt für die Gilde "Keine Ahnung".*