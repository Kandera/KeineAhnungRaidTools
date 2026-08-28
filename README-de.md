[English](https://github.com/Kandera/KeineAhnungRaidTools/blob/main/README.md) | **Deutsch**

# Keine Ahnung Raid Tools (KART)

Ein leichtgewichtiges, modulares World of Warcraft Addon für Raid- und Gruppenleiter. Einladungen, Bereitschaft, kompakte Raidlead-Leiste, Co-Tank, und ab 4.1 Load & Send der nächsten [Northern-Sky](https://github.com/Reloe/NorthernSkyRaidTools)-Shared-Note nach einem Kill.

## Funktionen

### 1. Automation
Alle automatischen Gruppen-Funktionen in einem Tab:
*   **Keyword-Invite:** Reagiert auf konfigurierbare Schlagworte (z. B. "inv", "+") auf den Kanälen, die du einschaltest: Flüstern, Battle.net, Gilde und Offizier. Gilde und Offizier sind standardmäßig aus, damit normaler Chat nicht einlädt. Wenn ein Stichwort passte, die Einladung aber nicht rausging, antwortet KART auf demselben Kanal (auch Battle.net).
*   **Auto-Promote:** Befördert vordefinierte Spieler zu Assistenten, sobald sie beitreten. Jeder Eintrag ist ein Charaktername oder ein NSRT-Nickname, gilt also auch nach einem Alt-Wechsel. Befördern wartet, bis der Kampf vorbei ist.
*   **Auto-Raid:** Wandelt die Gruppe in einen Schlachtzug um, sobald ein 6. Spieler um eine Einladung bittet; eine volle 5er-Gruppe bleibt eine Gruppe.

### 2. Raidlead-Leiste
Eine kompakte, verschiebbare Leiste:
*   **Schlachtzugs-Symbole** und **Welt-Marker.** Rechtsklick auf einen Marker in der Leiste löscht genau diesen Marker.
*   **Ready-Check** und ein nativer **Pull-Timer** (kein BigWigs/DBM; Standard 10 Sekunden).
*   **Look:** Skalierung, Button-Größe, Deckkraft und Ebene (auch unter der Weltkarte). Optional automatisch im Kampf ausblenden. Optional Blizzards Raid-Manager ausblenden, solange die Leiste an ist; Northern Sky bleibt.
*   **Tastenbelegung** im Raidlead-Tab (Ready-Check, Welt-Marker löschen, Pull-Timer, Buff-Checker). Einmal gesetzt, funktionieren die Bindings auch während einer Kampfsperre.

### 3. Erweiterter Ready-Check
*   Wenn Spieler auf "Nicht bereit" klicken, wählen sie einen kurzen Grund (Bio, Trinken, 1 Min) oder Freitext. Der Lead sieht das im Chat und als Hinweis-Icon im Buff-Checker (voller Text beim Hovern).

### 4. Buff-Checker & KART Sync
Fenster zur Raid-Vorbereitung:
*   **Stat-Check:** Intelligenz, Ausdauer, Mal der Wildnis, Schlachtruf, Segen der Bronze und Himmelszorn.
*   **Verbrauchsgüter:** Essen, Fläschchen, Runen, plus **Gesundheitsstein** (Stein in den Taschen) und **Seelenstein**.
*   **Erweiterte Ansicht (Gear-Check):** Item-Level, fehlende Verzauberungen und Edelsteine, mit Tooltip für die Slots.
*   **Waffenöl & KART Sync:** Versteckte Addon-Nachrichten lesen Öl auch, wenn der Spieler zu weit weg ist.
*   **Haltbarkeit** (braucht *LibDurability*). **Bericht** postet fehlende Buffs in Raid oder Gruppe; Umschalt-Klick auf Posten flüstert Fläschchen und Essen an alle, denen etwas fehlt.
*   Öffnet sich bei einer Bereitschaftsabfrage. Lässt sich deaktivieren, um CPU zu sparen; der Hintergrund-Sync (Öl/ilvl/Gear für andere) bleibt an.
*   **Advanced** zeigt, ob RC, NSRT und WowUtils aktuell, veraltet oder fehlend sind. **Addon-Versionen prüfen** unter Settings schickt Raidern, die hinterherhinken, ein Fenster.
*   Der freie Slot unter Buff Check öffnet Rollenabfrage, Umwandeln und Ping-Einschränkung.

### 5. Co-Tank-Fenster
*   Aus, bis du es im Co-Tank-Tab einschaltest. Der Tab zeigt eine Vorschau in der Stadt. Der Testmodus lässt die erfundene Zeile nach dem Schließen stehen.
*   Live: Leben, Debuffs und Buffs des anderen Tanks. Optionale Gruppen-/Instanzfilter (Dungeons bleiben aus; Raids standardmäßig an). Entsperren zum Platzieren ohne Gruppe. Linksklick zielt den anderen Tank an.
*   Look, Text und Auren öffnen sich in einem Begleitfenster (Balkentextur und optionaler Verlauf, LibSharedMedia wenn installiert).
*   Optional: eigenen Taunt sagen, ein **Übernehmen**-Button (oder Aktionsleisten-Makro) und eine kurze Taunt-Swap-Zeile beim anderen Tank. Alles aus, bis du es einschaltest. Testmodus für die Zeile in der Stadt.

### 6. NSRT Notes
Nach einem Kill — und wenn der Lead den Raid betritt — lädt KART die nächste Northern-Sky-**Shared-Note** und sendet sie, damit Heiler nicht auf dem vorherigen Boss hängen bleiben.
*   Geteilte Notizen auf dem **Notes**-Tab einfügen. **Notizen löschen** neben Import leert die NSRT-Shared-Library und das Paste-Feld.
*   Die Liste startet in Encounter-Journal-Reihenfolge, danach Extra-Notizen. Ziehen zum Umsortieren (Zielzeile leuchtet), auslassen oder einen Boss anklicken, um dort zu starten. Jede Zeile zeigt die Schwierigkeit; Einladen und Entfernen tauschen den importierten Roster dieses Bosses.
*   Ein **Notiz-Operator** (oft Caller von draußen) besitzt die Liste, wenn er in der Gruppe ist, Assistent ist und nicht veraltet. Nur der Raidlead setzt den Operatornamen. Der Lead sendet, wenn der Operator fehlt oder kein KART hat.
*   **Teilen jetzt** wartet, solange der Raid im Kampf ist, auch wenn du draußen bist. In der Stadt gilt die veröffentlichte Schwierigkeit des Leads, kein lokales Raten. Die Statuszeile zeigt, wer senden würde.

### 7. RCLootCouncil-Begleiter
KART bringt keinen eingebauten Loot Council mit. **Installiere [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil)** für Session, Abstimmung, Trade-UI und Loot-Historie. **WowUtils** (Addon + Bridge) malt Sim-Spalten ins RC-Abstimmungsfenster.

KART ergänzt drei Hooks:

*   **Council per Nickname:** Unter Settings trägt der Raidlead Council als NSRT-Nicknames (oder Charakternamen) ein. KART schreibt nur die GUIDs von Mitgliedern, deren aktueller Alt im Raid steht, in RCs Council-Liste.
*   **Award-Weiterleitung:** Council klickt Award in RC; KART flüstert dem Raidlead, dessen Client RCs `Award()` aufruft, während der Lead weiter handelt.
*   **Trade-Erinnerung für Gewinner:** Wenn du ein Item gewinnst, listet ein kleines Fenster, was dir noch zusteht, damit du zum Lead laufen kannst. Der Lead nutzt weiter RCs Trade-UI. Schalter unter Settings (standardmäßig an); `/kart owed` öffnet die Liste erneut.

In dieser Gilde ist KART raidpflichtig. Alle anderen brauchen weiterhin RCLootCouncil und WowUtils (Addon + Bridge). Die alte Desktop-App **KART Companion** ist eingestellt; das ist nicht die WowUtils-Bridge.

### 8. Anpassung (Settings)
*   Farben, Transparenz, Schriftarten. Fenster und Textfelder schließen oder abwählen mit ESC.
*   Deutsch und Englisch. Minimap-Icon oder Addon Compartment.
*   **Bearbeiten-Modus** dunkelt die Welt ab mit einem Fertig-Banner, damit jedes eingeschaltete Modul-Fenster in der Stadt platziert werden kann, ohne gespeicherte Sperren zu ändern.
*   Changelog-Panel im Spiel; Footer-Links für CurseForge, Wago und GitHub (Box zum Kopieren).
*   Versionscheck: `/kart v`. Buff-Checker lässt sich deaktivieren.

## Voraussetzungen

*   **[Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools)** — Shared Notes (Notes-Tab) und Nicknames für Auto-Promote und die RC-Council-Liste. Charakternamen gelten, wenn kein Nickname da ist.
*   **RCLootCouncil** — Loot Council (für Loot-Features erforderlich).
*   **WowUtils-Addon** — Spalten im RC-Abstimmungsfenster.
*   **WowUtils-Bridge** — WowUtils-Datenpipe (nicht die eingestellte KART-Companion-Tray-App).

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
