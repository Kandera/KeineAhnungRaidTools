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

### 5. Co-Tank-Fenster
*   Im Co-Tank-Tab einschalten (standardmäßig aus). Der Tab zeigt eine Vorschau der Zeile, damit du sie in der Stadt einstellen kannst.
*   Testmodus lässt die erfundene Zeile nach dem Schließen stehen. Live: Tank-Rolle, optional nur Gruppe / nur Instanz (Dungeon und Raid standardmäßig an). Entsperren zum Platzieren ohne Gruppe.
*   Linksklick auf die Zeile zielt den anderen Tank an.
*   Optional: eigenen Taunt ansagen, damit der andere Tank es hört, plus ein Button (oder Aktionsleisten-Makro) der ihn zum Übernehmen auffordert. Beides aus, bis du es einschaltest.

### 6. RCLootCouncil-Begleiter
KART 4.0 bringt keinen eingebauten Loot Council mehr mit. **Installiere [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil)** für Session, Abstimmung, Trade-UI und Loot-Historie. **WowUtils** (Addon + Bridge) malt Sim-Spalten ins RC-Abstimmungsfenster.

KART ergänzt drei Hooks:

*   **Council per Nickname:** Auf dem Settings-Tab trägt der Raidleiter Council-Mitglieder als [Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools)-Nicknames (oder Charakternamen) ein. KART schreibt nur die GUIDs von Mitgliedern, deren aktueller Alt im Raid steht, bei Roster-Änderungen in RCs Council-Liste.
*   **Award-Weiterleitung:** Council-Mitglieder klicken Award im RC-Abstimmungsfenster; KART flüstert dem Raidlead zu, dessen Client RCs `Award()` aufruft, während der Lead weiter handelt.
*   **Trade-Erinnerung für Gewinner:** Wenn du ein Item gewinnst, listet ein kleines Fenster, was dir noch zusteht, damit du zum Raidlead laufen und den Handel öffnen kannst. Der Lead nutzt weiter die Trade-UI von RCLootCouncil. Persönlicher Schalter auf dem Settings-Tab (standardmäßig an); `/kart owed` öffnet die Liste erneut.

In dieser Gilde ist KART raidpflichtig. Alle anderen brauchen weiterhin RCLootCouncil und WowUtils (Addon + Bridge). Die alte Desktop-App **KART Companion** ist eingestellt; das ist nicht die WowUtils-Bridge.

### 7. WoWUtils-Roster per Paste
*   Raid-Zusammenstellungen lassen sich auf dem **WoWUtils**-Tab per Copy-Paste aus WoWUtils importieren (Boss-für-Boss-Format mit Encounter, Difficulty und Invite-Liste).
*   Pro Boss eine Zeile mit **Einladen**- und **Entfernen**-Buttons zum schnellen Umbau der Zusammensetzung.
*   Mehrere Imports werden nach Encounter + Difficulty zusammengeführt; **Zurücksetzen** leert die gespeicherte Liste.

### 8. Anpassung (Settings)
*   Vollständig anpassbares Interface (Farben, Transparenz, Schriftarten).
*   Standardkonforme Steuerung: Fenster und Textfelder lassen sich mit ESC schließen oder abwählen.
*   Deutsch und Englisch.
*   Zugriff über Minimap-Icon oder Addon Compartment Frame.
*   Versionscheck (`/kart v`).
*   **Modul-Schalter:** Der Buff-Checker lässt sich deaktivieren.

## Voraussetzungen

*   **RCLootCouncil** — Loot Council (für Loot-Features erforderlich).
*   **WowUtils-Addon** — Spalten im RC-Abstimmungsfenster.
*   **WowUtils-Bridge** — WowUtils-Datenpipe (nicht die eingestellte KART-Companion-Tray-App).
*   **Northern Sky Raid Tools** (optional) — Nicknames für Auto-Promote und RC-Council; sonst Charakternamen.

## Slash-Befehle

| Befehl | Beschreibung |
| :--- | :--- |
| `/kart` | Hauptfenster öffnen oder schließen. |
| `/kart version` (`/kart v`) | KART-Version von Gilden-/Raid-/Gruppenmitgliedern abfragen. |
| `/kart owed` | Liste der dir noch zustehenden Items erneut öffnen. |
| `/kart ench [raid]` | **Wartungswerkzeug.** Enchant-IDs für Tabellenpflege ausgeben. |
| `/kart help` (`/kart h`) | Diese Befehlsliste. |

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

## Lizenz
Dieses Projekt lizenziert unter der MIT-Lizenz - siehe die LICENSE.md Datei für Details.

*Erstellt für die Gilde "Keine Ahnung".*
