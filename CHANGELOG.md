# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.1] - 2026-07-07
### Behoben
- **Lua-Fehler beim Login:** `BuildSettingsPanel` in LootCouncil.lua griff beim Aufbau der Oberfläche direkt auf `KART_Settings.lcMinQuality` zu — zu diesem Zeitpunkt existiert die SavedVariable aber noch nicht (sie wird erst bei `ADDON_LOADED` initialisiert). Der Mindest-Qualitäts-Button verwendet jetzt einen Platzhaltertext beim Aufbau; der echte gespeicherte Wert wird wie vorgesehen unmittelbar danach nachgezogen.

## [1.9.0] - 2026-07-06
### Hinzugefügt
- **Modul-Schalter für Loot Council, Buff-Checker und WoWUtils:** Jedes Modul lässt sich jetzt einzeln komplett deaktivieren — praktisch während der Testphase (z. B. bei Konflikten mit RCLootCouncil) oder um CPU zu sparen, wenn Raider bestimmte Funktionen nicht brauchen.
  - Beim Deaktivieren von Loot Council werden keinerlei Nachrichten anderer KART-Nutzer mehr verarbeitet, kein Auto-Pass, keine Popups.
  - Beim Deaktivieren des Buff-Checkers bleibt der Hintergrund-KART-Sync (Öl/ilvl/Gear-Antworten für andere) bewusst aktiv — nur das eigene Fenster wird abgeschaltet, damit der Raidleiter weiterhin korrekte Daten über diesen Spieler sieht.
- **Warnsymbol im Council-Panel:** Zeigt pro Raider ein rotes „!“ (mit Tooltip), wenn kein KART erkannt wurde, eine veraltete Version läuft oder der Spieler Loot Council lokal deaktiviert hat.

### Geändert
- **Raid-weite Autorität für Loot Council:** Abstimmungs-Timer, Vote-Buttons, zusätzliche Council-Mitglieder und Mindest-Itemqualität gelten jetzt immer gemäß den Einstellungen des Raidleiters — nicht mehr die lokalen Einstellungen jedes einzelnen Spielers. Verhindert, dass jemand z. B. die Abstimmungszeit lokal verkürzt oder sich selbst über die eigene Council-Liste unbefugt Zuweisungsrechte verschafft.
  - **Auto-Pass bleibt davon unberührt** und ist weiterhin eine rein persönliche Einstellung.
  - Die betroffenen Einstellungen sind im Options-Menü jetzt visuell in einer eigenen Box abgegrenzt, inklusive Live-Anzeige, ob die eigenen Einstellungen gerade wirksam sind („Du bist Raidleiter“ / „Einstellungen des Raidleiters gelten“).

## [1.8.1] - 2026-07-06
### Geändert
- **Buff-Checker Design:** Ready-Check-Begründungen werden nicht mehr als Inline-Text angezeigt, sondern als kleines goldenes Info-Icon direkt nach dem Namen — der volle Text erscheint im Tooltip beim Hovern. Das Layout bleibt dadurch unabhängig von der Textlänge stabil, ganz ohne Fenster-Resize.

### Behoben
- **Addon-Symbol in der WoW-Addonliste:** Der TOC-Datei fehlte das `## IconTexture`-Feld, wodurch in der Blizzard-Addonliste (ESC → AddOns) statt des Icons ein Fragezeichen-Platzhalter angezeigt wurde. Das Minimap-Icon war davon nicht betroffen (eigener Mechanismus über LibDBIcon). Jetzt wird `KAimg.jpg` auch dort korrekt referenziert; sichtbar nach einem vollständigen Client-Neustart bzw. beim nächsten Login-Bildschirm.
- **Buff-Checker: Ready-Check-Begründungen überlappten Buff-Icons:** Lange "Nicht bereit"-Texte (z. B. AFK-Gründe) wurden bisher direkt als Text hinter den Spielernamen gehängt, in einer Spalte mit fester Breite ohne Zeilenumbruch. Dadurch überlappten längere Texte sofort die Buff-Icons, bis man das Fenster manuell breiter zog.

## [1.8.0] - 2026-07-06
### Geändert
- **Tab „Auto-Invite" entfernt, Tab „Auto-Promote" → „Automation":** Da die Keyword-basierte Auto-Invite-Funktion (Whisper/Gildenchat/Battle.net) ihren einzigen verbleibenden Zweck erfüllt, wurde sie in den Auto-Promote-Tab verschoben. Da dieser Tab jetzt mehrere Automatisierungs-Funktionen bündelt (Auto-Invite per Keyword, Auto-Promote, Auto-Raid-Convert), wurde er in „Automation" umbenannt.
- **„Automatisch in Raid umwandeln":** Die Einstellung ist aus dem Settings-Tab in den neuen Automation-Tab gewandert, direkt neben die anderen automatischen Gruppen-Funktionen.

### Entfernt
- **Bulk-Invite ("Raid-Zusammenstellung einfügen"):** Die alte Copy-Paste-Funktion im Auto-Invite-Tab ist komplett entfernt worden — sie wurde vollständig durch den WoWUtils Import abgelöst, der dieselbe Aufgabe zuverlässiger und komfortabler löst.

## [1.7.0] - 2026-07-06
### Hinzugefügt
- **Mindest-Itemqualität für Loot Council:** Neue Einstellung (Standard: Episch) — Items unterhalb der gewählten Qualität lösen den Loot Council gar nicht erst aus; das normale WoW-Würfelfenster greift stattdessen. Verhindert unnötige Abstimmungs-Popups bei Trash-Loot.
- **Sperre gegen Doppelzuweisung:** Wird ein Item über das Zuweisungs-Menü ein zweites Mal vergeben (z. B. aus Versehen), erscheint vor der eigentlichen Zuweisung ein Bestätigungsdialog mit dem bisherigen und neuen Empfänger.
- **Vollständig synchronisierte Loot-Historie:** Jeder KART-Nutzer im Raid protokolliert nun automatisch dieselben Zuweisungen mit (Grund inklusive) — nicht mehr nur der Lootmaster. Dadurch hat jeder Spieler eine vollständige, gemeinsame Historie, unabhängig davon, wer gerade zuweist.
  - **Difficulty-Spalte:** Jeder Historien-Eintrag speichert jetzt zusätzlich die Raid-Schwierigkeitsstufe (z. B. Heroic, Mythic) zum Zeitpunkt der Vergabe.
  - **Automatischer Nachhol-Sync:** Betritt ein Spieler einen Raid erneut, nachdem er eine Session verpasst hat, fragt sein Client einmalig und still bei den anderen KART-Nutzern nach fehlenden Einträgen an. Antworten laufen ausschließlich über den unsichtbaren Addon-Kanal (kein Chat/Whisper sichtbar für den Spieler), sind auf die letzten 30 fehlenden Einträge bzw. 14 Tage begrenzt und werden leicht zeitversetzt beantwortet, um Traffic-Spitzen zu vermeiden.

## [1.6.0] - 2026-07-06
### Hinzugefügt
- **Loot-Historie:** Neues Modul (`LootHistory.lua`), das jede über den Loot Council vergebene Beute dauerhaft protokolliert (SavedVariable `KART_LootHistory`, max. 500 Einträge).
  - Neues Fenster mit Datum, klassengefärbtem Spielernamen, Item (Icon + Hover-Tooltip) und Grund.
  - **Filter:** Freitextsuche über den Item-Namen, Dropdown-Filter nach Spieler, Dropdown-Filter nach Grund (inkl. „Ohne Grund"), sowie ein Reset-Button.
  - Fußzeile zeigt „X von Y Einträgen"; **„Verlauf leeren"**-Button mit Bestätigungsdialog.
  - Fenster ist bewegbar, Position wird gespeichert; über einen neuen Button „Loot-Historie" im Loot-Council-Optionsmenü erreichbar.
- **Zuweisungs-Menü im Council-Panel:** Rechtsklick auf eine Raider-Zeile öffnet jetzt ein Kontextmenü statt sofort zuzuweisen:
  - **Zuweisen:** Vergibt das Item mit der aktuell abgegebenen Stimme des Spielers als Grund.
  - **Zuweisung ändern:** Untermenü mit allen konfigurierten Vote-Buttons, um den Grund nachträglich zu korrigieren (z. B. von BIS auf Upgrade).
  - **Ohne Grund zuweisen:** Vergibt das Item ohne Grundangabe — praktisch, wenn niemand das Item will, aber die Loot-Historie nicht verfälscht werden soll.
  - Das Panel schließt sich dabei nie von selbst; nur der „Schließen"-Button oder das „×" schließen es.

### Geändert
- **Linksklick im Council-Panel:** Hat jetzt keine Funktion mehr (verhinderte versehentliche Zuweisungen); alle Aktionen laufen über das neue Rechtsklick-Menü.
- **Item-Icon im Council-Panel:** Jede Raider-Zeile zeigt zusätzlich zur Item-Stufe das Icon des aktuell getragenen Vergleichs-Items im passenden Slot.
- **Echte Item-Tooltips:** Der Item-Name im Vote-Popup und im Council-Panel ist jetzt hoverbar und zeigt den vollständigen Item-Tooltip; im Council-Panel wird zusätzlich das getragene Item des jeweiligen Raiders per nativem Vergleichs-Tooltip (`ShoppingTooltip`) gegenübergestellt.
- **Lootmaster-Fenster schließt nicht mehr automatisch** beim Zuweisen — ermöglicht Korrekturen ohne erneutes Öffnen.

## [1.5.0] - 2026-07-01
### Hinzugefügt
- **WoWUtils Import:** Neues Modul (`Invite.lua`) und neuer Tab „WoWUtils" in der Sidebar.
  - Raid-Setups können direkt aus WoWUtils in das Addon eingefügt werden (Boss-für-Boss-Format mit `EncounterID`, `Difficulty`, `Name` und `invitelist`).
  - Nach dem Importieren erscheint für jeden Boss eine eigene Zeile mit der Spieleranzahl.
  - **[Einladen]:** Lädt alle Spieler der jeweiligen Boss-Liste in den Raid ein — Mitglieder die bereits im Raid sind werden übersprungen (Ausgabe: „X eingeladen. (Y bereits im Raid)").
  - **[Entfernen]:** Kickt alle aktuellen Raid-Mitglieder, die NICHT in der Boss-Liste stehen — ideal zum schnellen Umbau zwischen Bosskompositionen.
  - Der Import wird sitzungsübergreifend gespeichert; beim Login wird er automatisch geparst.
  - Scrollbalken im Eingabefeld folgt dem Addon-Farbschema.

### Geändert
- **Auto-Pass:** Wird jetzt sofort beim Start einer Loot-Roll ausgelöst (`START_LOOT_ROLL`), nicht erst nach der Gewinner-Bekanntgabe — verhindert versehentliche Need/Gier/Transmog-Klicks des Raidleiters.
- **Notizfeld im Vote-Popup:** Raider können ihrer Stimme einen optionalen Freitext-Kommentar hinzufügen (max. 80 Zeichen). Die Notiz ist für Council-Mitglieder im Hover-Tooltip der jeweiligen Zeile sichtbar.
- **Bewegbare Fenster mit Positionsspeicherung:** Vote-Popup und Council-Panel sind jetzt per Drag verschiebbar; die Position wird in den SavedVariables gespeichert und beim nächsten Öffnen wiederhergestellt.
- **Sortierung im Council-Panel:** Zeilen werden nach Button-Index aufsteigend sortiert (BIS zuerst, dann Upgrade usw.); Nicht-Abstimmer landen am Ende.
- **Rechtsklick zum Neu-Vergeben:** Ein Rechtsklick auf eine Zeile im Council-Panel vergibt den Loot neu, ohne das Panel zu schließen — für schnelle Korrekturen ohne erneutes Öffnen.
- **Gewinner-Hervorhebung:** Die zuletzt gewählte Gewinner-Zeile wird grün hinterlegt und bleibt markiert, bis das Panel geschlossen oder ein neuer Gewinner gewählt wird.
- **Test-Modus getrennt:** Der einzelne „Test starten"-Button wurde durch zwei separate Buttons ersetzt:
  - **Test: Looter** — zeigt das Vote-Popup inkl. Notizfeld, unabhängig von der eigenen Rolle.
  - **Test: Lootmaster** — zeigt das Council-Panel inkl. vorbefüllter Votes (aus aktuellen Gruppenmitgliedern), unabhängig von der eigenen Rolle.
- **Versionsnummer im Titel:** Die Anzeige „v1.3.0" im Hauptfenster-Titel wird jetzt immer aus den Addon-Metadaten gelesen und ist damit immer korrekt.

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
### Geändert
- Code-Bereinigung: Veraltete Datei `Minimap.lua` entfernt (Minimap-Logik wird nun sauberer über LibDBIcon gesteuert).

### Behoben
- **Absturz beim Ändern der UI-Farben:** Die veraltete Farbauswahl-API wurde durch die moderne `ColorPickerFrame`-API ersetzt, die keine Abstürze mehr verursacht.
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
### Hinzugefügt
- Grundlegende Auto-Invite Funktionalität über Keywords.
- Bulk-Invite System für Raid-Zusammenstellungen.
- Auto-Promote System für Assistenten-Rollen.

[Unreleased]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.1...HEAD
[1.9.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.5.0...v1.8.1
[1.5.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.3.0...v1.5.0
[1.3.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Kandera/KeineAhnungRaidTools/releases/tag/v1.0.0

<!--
Hinweis: 1.4.0, 1.6.0, 1.7.0 und 1.8.0 haben keinen eigenen Git-Tag (in der Historie
nicht als eigenständiger Commit-Stand nachweisbar) und sind daher hier nicht verlinkt.
Ab v1.8.1 wird jede Version konsequent getaggt, sodass zukünftige Einträge vollständig
verlinkt werden können.
-->
