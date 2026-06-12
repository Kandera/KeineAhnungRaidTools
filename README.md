# Keine Ahnung Raid Tools (KART)

Ein leichtgewichtiges und modulares World of Warcraft Addon, das speziell für Raid- und Gruppenleiter entwickelt wurde. Es vereinfacht das Einladungsmanagement, die Kontrolle der Schlachtzugsvorbereitung und bietet schnellen Zugriff auf wichtige Raidlead-Funktionen.

## Funktionen

### 1. Auto-Invite & Bulk-Invite
*   **Keyword-Invite:** Reagiert auf konfigurierbare Schlagworte (z. B. "inv", "+") im Flüstern, Gildenchat oder über das Battle.net.
*   **Bulk-Invite:** Ermöglicht das Einladen ganzer Schlachtzugszusammenstellungen durch einfaches Kopieren und Einfügen von Listen in ein großes, scrollbares Textfeld.
*   **Auto-Raid:** Wandelt die Gruppe automatisch in einen Schlachtzug um, sobald mehr als 5 Mitglieder beitreten.

### 2. Auto-Promote
*   Befördert vordefinierte Spieler automatisch zu Assistenten, sobald sie der Gruppe beitreten. Ideal für Co-Leiter und feste Rollen im Raid.

### 3. Raidlead-Leiste
Eine kompakte, verschiebbare Leiste für den schnellen Zugriff auf:
*   **Schlachtzugs-Symbole:** Setzen von Markern auf Ziele.
*   **Welt-Marker:** Platzieren von farbigen Säulen im Gelände.
*   **Ready-Check:** Startet sofort eine Bereitschaftsabfrage.
*   **Pull-Timer:** Anpassbarer Countdown für den Kampfbeginn (Standard: `/pull 10`).

### 4. Erweiterter Ready-Check
*   Wenn Spieler auf "Nicht bereit" klicken, öffnet sich ein modernes Fenster, in dem sie schnelle Gründe (Bio, Trinken, 1 Min) oder einen eigenen Freitext angeben können. Diese Gründe werden dem Raidlead im Chat und direkt im Buff-Checker hinter dem Namen angezeigt.

### 5. Buff-Checker & KART Sync
Ein detailliertes Fenster zur Überprüfung der Raid-Vorbereitung:
*   **Stat-Check:** Überprüft Intelligenz, Ausdauer, Mal der Wildnis, Schlachtruf, Segen der Bronze und Himmelszorn.
*   **Verbrauchsgüter:** Zeigt an, wer Essen (Food), Fläschchen (Flask) oder Runen aktiv hat.
*   **Erweiterte Ansicht (Gear-Check):** Eine spezielle Ansicht zeigt das genaue Item-Level sowie fehlende Verzauberungen und Edelsteine. Ein interaktiver Tooltip verrät exakt, auf welchen Rüstungsslots diese fehlen.
*   **Waffenöl & KART Sync:** Über versteckte Addon-Nachrichten zwischen KART-Nutzern wird der exakte Status von Waffenöl ausgelesen, selbst wenn Spieler zu weit entfernt sind.
*   **Haltbarkeit:** Zeigt den Reparaturstatus der Ausrüstung (erfordert *LibDurability*).
*   **Bericht-Funktion:** Postet fehlende Buffs direkt in den Raid- oder Gruppenchat.
*   **Ready-Check Integration:** Öffnet sich automatisch bei einer Bereitschaftsabfrage.

### 6. Anpassung (Settings)
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