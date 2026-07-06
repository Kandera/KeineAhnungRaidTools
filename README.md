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
*   Wenn Spieler auf "Nicht bereit" klicken, öffnet sich ein modernes Fenster, in dem sie schnelle Gründe (Bio, Trinken, 1 Min) oder einen eigenen Freitext angeben können. Diese Gründe werden dem Raidlead im Chat und direkt im Buff-Checker hinter dem Namen angezeigt.

### 4. Buff-Checker & KART Sync
Ein detailliertes Fenster zur Überprüfung der Raid-Vorbereitung:
*   **Stat-Check:** Überprüft Intelligenz, Ausdauer, Mal der Wildnis, Schlachtruf, Segen der Bronze und Himmelszorn.
*   **Verbrauchsgüter:** Zeigt an, wer Essen (Food), Fläschchen (Flask) oder Runen aktiv hat.
*   **Erweiterte Ansicht (Gear-Check):** Eine spezielle Ansicht zeigt das genaue Item-Level sowie fehlende Verzauberungen und Edelsteine. Ein interaktiver Tooltip verrät exakt, auf welchen Rüstungsslots diese fehlen.
*   **Waffenöl & KART Sync:** Über versteckte Addon-Nachrichten zwischen KART-Nutzern wird der exakte Status von Waffenöl ausgelesen, selbst wenn Spieler zu weit entfernt sind.
*   **Haltbarkeit:** Zeigt den Reparaturstatus der Ausrüstung (erfordert *LibDurability*).
*   **Bericht-Funktion:** Postet fehlende Buffs direkt in den Raid- oder Gruppenchat.
*   **Ready-Check Integration:** Öffnet sich automatisch bei einer Bereitschaftsabfrage.

### 5. Loot Council
Koordinierte Lootverteilung direkt im Addon, ohne externe Tools:
*   **Session-Aktivierung:** Beim Betreten eines Raids wird der Raidleiter gefragt, ob der Loot Council für diese Session aktiviert werden soll (für Spaßruns einfach ablehnen). Lässt sich jederzeit manuell umschalten.
*   **Raider-Abstimmung:** Sobald ein Item zur Verteilung ansteht, erscheint bei allen Raidern gleichzeitig ein Popup mit konfigurierbaren Vote-Buttons (Standard: BIS / Upgrade / Offspec / Sonstiges / Pass) sowie einem optionalen Notizfeld für Kommentare zur eigenen Stimme.
*   **Council-Panel:** Raidleiter, Assistenten und frei definierte Council-Mitglieder sehen ein bewegbares, scrollbares Panel mit allen Abstimmungen (klassengefärbt), sortiert nach Vote-Priorität. Zusätzlich wird pro Spieler die Item-Stufe des aktuell getragenen Items im passenden Slot angezeigt, damit direkt ersichtlich ist, wer ein Upgrade bekommt.
*   **Vergabe per Klick:** Linksklick vergibt den Loot und schließt das Panel; Rechtsklick vergibt neu, ohne das Panel zu schließen – ideal für schnelle Korrekturen. Die aktuelle Gewinner-Zeile wird grün hervorgehoben. Ein kleines Symbol zeigt an, wenn ein Raider eine Notiz hinterlassen hat (im Tooltip lesbar).
*   **Gewinner-Benachrichtigung:** Der ausgewählte Spieler erhält ein grünes Hinweisfenster; die Entscheidung wird automatisch im Raid- bzw. Gruppenchat angekündigt.
*   **Auto-Pass:** Optionaler Haken – sobald eine Loot-Roll beginnt, passen alle KART-Nutzer sofort, damit niemand versehentlich Need/Gier/Transmog anklickt, während der Council abstimmt.
*   **Konfigurierbar:** Anzahl und Bezeichnung der Vote-Buttons (bis zu 6), Abstimmungs-Timer sowie zusätzliche Council-Mitglieder per Namensliste frei einstellbar.
*   **Test-Modus:** Zwei getrennte Testbuttons simulieren den Ablauf aus Sicht des Looters (Vote-Popup) und aus Sicht des Lootmasters (Council-Panel), unabhängig von der eigenen Raid-Rolle.

### 6. WoWUtils Import
*   Raid-Zusammenstellungen lassen sich direkt aus WoWUtils per Copy-Paste importieren (Boss-für-Boss-Format mit Encounter, Difficulty und Invite-Liste).
*   Für jeden importierten Boss erscheint eine eigene Zeile mit Spieleranzahl und zwei Buttons:
    *   **Einladen:** Lädt alle Spieler der Boss-Liste ein, die noch nicht im Raid sind (bereits anwesende Mitglieder werden übersprungen).
    *   **Entfernen:** Kickt alle aktuellen Raid-Mitglieder, die NICHT auf der Boss-Liste stehen – ideal zum schnellen Umbau zwischen Bosskompositionen.
*   Der Import wird sitzungsübergreifend gespeichert und beim Login automatisch geladen.

### 7. Anpassung (Settings)
*   Vollständig anpassbares Interface (Farben, Transparenz, Schriftarten).
*   Standardkonforme Steuerung: Fenster und Textfelder lassen sich bequem mit der ESC-Taste schließen oder abwählen.
*   Unterstützung für Deutsch und Englisch.
*   Zugriff über Minimap-Icon oder das Addon Compartment Frame.
*   Versions-Checker: Prüfe, ob alle Raider die neueste KART-Version nutzen (`/kart v`).

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