# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) 
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.4.0] - 2026-07-01
### Hinzugefügt
- **Loot Council:** Neues Modul (`LootCouncil.lua`) für die koordinierte Lootverteilung im Raid.
  - Beim Betreten eines Raids wird der Raidleiter gefragt, ob der Loot Council für diese Session aktiviert werden soll – für Spaßruns einfach ablehnen.
  - **Raider-Abstimmung:** Sobald ein Item zur Verteilung ansteht (`START_LOOT_ROLL`), erscheint bei allen KART-Nutzern gleichzeitig ein Popup mit konfigurierbaren Vote-Buttons (Standard: BIS / Upgrade / Offspec / Sonstiges / Pass). Die Abstimmungszeit ist einstellbar (Standard: 20 Sek).
  - **Council-Panel:** Raidleiter und Assistenten sehen stattdessen ein scrollbares Panel mit allen Raidern und deren Votes (klassengefärbt). Ein Klick auf einen Spieler wählt ihn als Gewinner.
  - **Gewinner-Benachrichtigung:** Der ausgewählte Spieler erhält ein grünes Hinweisfenster. Die Entscheidung wird automatisch im Raid- bzw. Gruppenchat angekündigt.
  - **Auto-Pass:** Optionaler Haken – wenn aktiv, passen alle Nicht-Gewinner mit KART sofort und ohne Rückfrage.
  - **Konfigurierbare Buttons:** Anzahl und Bezeichnung der Vote-Buttons frei einstellbar (Semikolon-getrennt, bis zu 6 Buttons).
  - **Manueller Toggle:** Session lässt sich jederzeit über den neuen Tab „Loot Council" im Hauptfenster oder per Schaltfläche umschalten.
  - **Erweiterte Council-Mitglieder:** Neben Raidleiter und Assistenten können beliebige Spieler per Namen in den Council berufen werden – sie sehen das Council-Panel, ohne Assistenten-Rang zu benötigen.
  - **Test-Funktion:** „Test starten" simuliert den kompletten LC-Ablauf mit einem Classic-Dummy-Item. Im Raid werden vorhandene Gruppenmitglieder mit zufälligen Teststimmen vorbelegt; solo erscheint das Vote-Popup zur Überprüfung des Button-Layouts.
- **Neuer Tab:** „Loot Council" in der Sidebar des Hauptfensters mit allen zugehörigen Einstellungen.
- **Lokalisierung:** Alle neuen Texte auf Deutsch und Englisch übersetzt.

## [1.3.0] - 2026-06-12
### Hinzugefügt
- **Erweiterte Ansicht:** Der Buff-Checker besitzt nun einen Button, um zwischen "Ready Check" (Standard-Buffs) und "Erweitert" umzuschalten.
- **Ausrüstungs-Check:** In der erweiterten Ansicht werden nun das exakte Item-Level, Waffenöl sowie fehlende Verzauberungen und Edelsteine über den KART-Sync angezeigt.
- **Gear-Tooltips:** Wenn ein Spieler fehlende Verzauberungen oder Edelsteine hat, zeigt ein Tooltip im Buff-Checker beim Hovern exakt an, auf welchen Rüstungs-Slots diese fehlen.
- **Scrollbares Textfeld:** Das Eingabefeld für den Bulk-Invite (Raid-Zusammenstellung) wurde vergrößert und mit einem dynamischen Scrollbalken versehen.

### Geändert
- **Standardeinstellungen:** Die Raidlead-Leiste und der Buff-Checker sind bei Erstinstallation nun standardmäßig deaktiviert, um das Interface aufgeräumt zu halten.
- **ESC-Taste:** Das Hauptfenster und alle Texteingabefelder lassen sich nun standardkonform mit der ESC-Taste abwählen bzw. schließen.

### Behoben
- **Netzwerk-Traffic:** Die Abfragen für die "Erweitert"-Ansicht (iLvl, Gear, Öl) werden nicht mehr im Hintergrund gespammt, sondern laden nur beim Wechseln der Ansicht oder beim Klick auf "Aktualisieren".

## [1.2.0] - 2026-06-12
### Hinzugefügt
- **Erweiterter Ready-Check:** Wenn Spieler auf "Nicht bereit" klicken, öffnet sich nun ein kleines Fenster zur Angabe von Gründen (Bio, Trinken, 1 Min oder freier Text). Die Gründe werden dem Raidlead im Chat und direkt im Buff-Checker angezeigt.

- **Addon-Synchronisation (KART Sync):** KART kommuniziert nun unsichtbar mit anderen KART-Nutzern im Raid. Dadurch wird u.A. aufgetragenes Waffenöl exakt ausgelesen, auch wenn Blizzard die API limitiert.
- **Versions-Checker:** KART vergleicht Versionen innerhalb der Gilde/des Raids und gibt im Chat einen Hinweis aus, sobald eine neuere Version verfügbar ist. Über `/kart v` können die KART-Versionen der Mitspieler überprüft werden.
- **Tooltips für Raidlead-Leiste:** Die Tasten auf der Raidlead-Leiste (Bereitschaftscheck, Weltmarker löschen, Pull-Timer) erklären nun ihre Funktion, wenn man mit der Maus darüberfährt.
- **Addon Compartment Frame:** KART klinkt sich nun nahtlos in das moderne Minimap-Dropdown-Menü von WoW (Dragonflight/TWW) ein.
- **Schriftart-Auswahl:** Dank LibSharedMedia-Integration kann die Schriftart des gesamten Addons nun in den Einstellungen geändert werden.
- **Sprach-Auswahl:** Neues Dropdown-Menü in den Einstellungen, um die Addon-Sprache manuell zu überschreiben (Auto/Deutsch/Englisch).
- **Buff-Checker Vorschau:** Ein neuer "Vorschau umschalten"-Button erlaubt es, das Layout und die Farben des Buff-Checkers anhand von Spieldaten zu testen, ohne in einem Raid zu sein.

### Geändert
- **Buff-Checker Layout:** Das Buff-Checker Fenster hat keine feste Breite mehr und kann horizontal skaliert werden. Die Namensspalte und Buff-Icons passen sich dynamisch der neuen Breite an, sodass auch lange Ready-Check-Gründe lesbar sind.
- Die englischen Übersetzungen (enUS) wurden umfassend erweitert, um alle neuen Menüs und Gründe abzudecken.

### Behoben
- Layout-Fehler beim Ready-Check-Dialog behoben, der durch überlappende SetPoint-Befehle auftrat.
- Fehler behoben, bei dem die Sprachdatei `enUS.lua` asynchron zur `deDE.lua` lief.

## [1.1.1] - 2026-05-24
### Hinzugefügt
- Moderne Farbauswahl-API (ColorPickerFrame) für die Einstellungen hinzugefügt, um Abstürze beim Ändern der UI-Farben zu verhindern.

### Geändert
- Code-Bereinigung: Veraltete Datei `Minimap.lua` entfernt (Minimap-Logik wird nun sauberer über LibDBIcon gesteuert).

### Behoben
- **Sicherheit (Taint):** Die automatische Schlachtzugs-Umwandlung bei Keyword- und Bulk-Invites blockiert nun korrekt während des Kampfes (`InCombatLockdown`), um Lua-Fehler zu vermeiden.
- **Sicherheit (Taint):** Der Aktualisierungsprozess für den Pull-Timer-Button auf der Raidlead-Leiste wurde gegen Combat-Taints abgesichert (`GROUP_ROSTER_UPDATE`).
- **Lokalisierung:** Fehlender Fallback für Spiel-Clients mit anderen Sprachen (z. B. Französisch, Russisch) korrigiert. Das Addon fällt nun in diesen Fällen immer fehlerfrei auf Englisch (enUS) zurück.
- **Kritischer Fehler:** Die veraltete und in Retail WoW mittlerweile entfernte Funktion `table.wipe` im Buff-Checker wurde durch die moderne globale Funktion `wipe` ersetzt.

## [1.1.0] - 2026-05-21
### Hinzugefügt
- **Buff-Checker:** Neues Fenster zur Überprüfung von Raid-Buffs, Consumables und Haltbarkeit.
- **Raidlead-Leiste:** Interaktive Leiste für Marker, Weltmarker, Ready-Checks und Pull-Timer.
- **Lokalisierung:** Volle Unterstützung für Deutsch (deDE) und Englisch (enUS).
- **Minimap-Management:** Integration von LibDBIcon für ein verschiebbares Icon.
- **Moderner UI-Stil:** Komplett neue Slider und Checkboxen ohne Standard-WoW-Texturen.
- **Tooltips:** Detaillierte Beschreibungen für alle Einstellungsoptionen.

### Geändert
- Performance-Optimierungen durch Event-Throttling (Drosselung der Buff-Updates).
- Architektur verbessert: Frames werden nun erst bei Bedarf geladen (Load-on-Demand).
- Keyword-Suche auf Hash-Tabellen umgestellt für $O(1)$ Komplexität.

### Behoben
- Fehler bei der String-Verknüpfung in der Sprachauswahl behoben.
- "Table index is nil" Fehler in der Core-Initialisierung korrigiert.
- Automatisches Umwandeln in Raid blockiert nun korrekt während des Kampfes (Taint-Vermeidung).

## [1.0.0] - Initial Release
- Grundlegende Auto-Invite Funktionalität über Keywords.
- Bulk-Invite System für Raid-Zusammenstellungen.
- Auto-Promote System für Assistenten-Rollen.