[English](CHANGELOG.md) | **Deutsch**

# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Behoben
- **Minimap-Button nicht mehr schwarz:** Das Minimap- und AddOn-Compartment-Icon zeigten nach der PNG-Umstellung noch auf die alte JPG-Datei (WoW kann keine JPG-Texturen laden). Beide nutzen jetzt das PNG.
- **Pull-Timer und Weltmarker-Löschen funktionieren jetzt für alle:** Die Raidlead-Bar-Buttons nutzten den `/pull`-Befehl (existiert nur mit installiertem BigWigs/DBM) und `/cwm all` (das "all"-Schlüsselwort ist lokalisiert und schlug daher auf nicht-englischen Clients fehl). Der Pull-Button startet jetzt den nativen WoW-Countdown und der Lösch-Button entfernt jeden Marker einzeln per Nummer — beides funktioniert damit unabhängig von installierten Addons und Client-Sprache.

## [1.18.0] - 2026-07-18
### Neu
- **Gilden-Logo in der Titelleiste:** Das KA-Logo wird jetzt neben dem Titel des Hauptfensters angezeigt. Das Logo wurde außerdem von JPG zu PNG konvertiert — das repariert auch das Addon-Icon in der AddOns-Liste des Spiels (WoW kann keine JPG-Texturen laden).
- **Einstellbare Fenster-Ebene:** Ein neuer "Fenster-Ebene"-Regler in den Einstellungen steuert, auf welcher UI-Ebene (Frame-Strata) alle KART-Fenster gezeichnet werden — höher stellen, damit andere UI das Addon nicht verdeckt, oder niedriger, damit es im Hintergrund bleibt. Bestätigungs-Popups liegen immer eine Ebene darüber, damit sie nicht verschwinden.

### Geändert
- **Design-Updates:** modernisierter Look in allen Fenstern — abgerundete Ecken, überarbeitete Buttons, Checkboxen und Slider.

## [1.17.0] - 2026-07-17
### Neu
- **Droptimizer-Gewinn% jetzt auch im Vote-Fenster:** Jede Item-Karte im persönlichen Vote-Popup zeigt jetzt den eigenen gesyncten Droptimizer-Gewinn% für dieses Item an (farbcodiert, wie in der Gewinn-Spalte des Loot-Council-Fensters), sofern Sim-Daten dafür vorliegen — kein Wechsel mehr ins Council-Fenster nötig, nur um vor dem Voten zu checken, ob ein Item überhaupt ein Upgrade ist.

## [1.16.1] - 2026-07-15
### Behoben
- **Der Gem-Check im Advanced-Tab meldet keine Fehlalarme mehr:** Er verließ sich auf `C_Item.GetItemStats`, das für ein bereits im laufenden Spielsession bestücktes Item weiterhin einen `EMPTY_SOCKET_*`-Stat melden kann (der gecachte Item-Link stammt noch von vor dem Sockeln). Die Prüfung liest den Sockel-Status jetzt stattdessen aus einem versteckten Tooltip-Scan aus — das entspricht exakt dem, was beim Drüberhovern im Tooltip zu sehen ist, sodass bereits bestückte Teile nicht mehr als fehlend gezählt werden.

## [1.16.0] - 2026-07-15
### Neu
- **Northern Sky Raid Tools Nickname-Unterstützung:** Das Lootmaster-Feld, die Liste der weiteren Council-Mitglieder und die Auto-Promote-Namensliste akzeptieren jetzt zusätzlich zum Charakter-Kurznamen auch einen NSRT-Nickname. Ein eingetragener Nickname (z.B. "Kandera") gilt für alle Charaktere mit diesem Nickname — funktioniert also automatisch weiter, wenn diese Person den Charakter wechselt, ganz ohne manuelles Nachtragen. Fällt automatisch auf den klassischen Charakternamen-Abgleich zurück, wenn NSRT nicht installiert ist oder kein Nickname gesetzt wurde. Setzt ein installiertes Northern Sky Raid Tools voraus; KART bringt kein eigenes Nickname-System mit.
- **NSRT-Nicknames im Loot-Council-Fenster anzeigen:** Ein neuer persönlicher Schalter zeigt im Council-/Lootmaster-Panel den NSRT-Nickname statt des Charakternamens an. Standardmäßig aus; fällt automatisch auf den Charakternamen zurück, wo kein Nickname verfügbar ist.
- **Gilden-Rang-Spalte im Loot-Council-Fenster:** Eine neue Spalte direkt hinter dem Spielernamen zeigt den Gilden-Rang jedes Kandidaten an, damit Alts leichter zu erkennen sind.

## [1.15.0] - 2026-07-15
### Neu
- **Einstellbare Layouts für das Loot-Council-Vote-Fenster:** Ein neuer Schalter bietet zwei unterschiedliche Layouts: "Geräumig" (neue Voreinstellung) zeigt ein breites Fenster mit größeren Vote-Karten und einem in der Item-Qualitätsfarbe getönten Akzentbalken pro Item; "Kompakt" nutzt einzeilige Zeilen mit Icon-only-Vote-Chip-Buttons für kleinere Fläche. Die Wahl wird pro Charakter gespeichert.

## [1.14.0] - 2026-07-14
### Neu
- **Vom Raidleiter festgelegter Lootmaster:** Ein neues Feld in den Loot-Council-Einstellungen erlaubt es dem Raidleiter, einen Spieler festzulegen, der jede Roll gewinnen muss (Need, oder Gier/Entzaubern falls Need nicht verfügbar ist), statt zu passen — damit er jedes Item physisch erhält und an denjenigen weitergibt, den das Council tatsächlich ausgewählt hat. Das überschreibt die eigene Auto-Pass-Einstellung dieses Spielers — es wird wie die Council-Mitgliederliste vom Raidleiter synchronisiert, kein persönlicher Schalter, den man sich selbst ausschalten kann.

## [1.13.0] - 2026-07-14
### Neu
- **Das Loot-Council-Fenster lässt sich jetzt minimieren:** Ein neuer "-"-Button neben dem Schließen-Button klappt das Fenster auf nur noch Titelleiste + Item-Name zusammen, damit es während des normalen Raidens auf dem Bildschirm bleiben kann, ohne mit der vollen Kandidatenliste im Weg zu stehen. Tabs, Stimmen und alles andere bleiben im Hintergrund erhalten, während minimiert ist, und das Fenster klappt sich automatisch wieder auf, sobald ein wirklich neues Item eine Abstimmung startet — damit nichts übersehen wird.
- **Optischer Refresh für beide Loot-Council-Fenster:** Vote-Buttons und Council-Zeilen zeigen jetzt zusätzlich zur bestehenden Farbcodierung ein kleines Icon pro Vote-Kategorie (Blizzards eigene Standard-Loot-Icons, keine eigene Grafik); das Icon des gerade gerollten Items bekommt einen in der Item-Qualitätsfarbe getönten Akzentrahmen und einen nativen radialen Countdown-Wipe (dasselbe `Cooldown`-Widget, das schon jeder Fähigkeiten-Button nutzt); Council-Zeilen zeigen ein rundes Klassen-Icon, ein iLvl-+/--Delta gegenüber dem gerollten Item, und Rolls ≥85 leuchten golden; der Council-Stimmen-Zähler-Button füllt sich jetzt proportional statt nur eine nackte Zahl zu zeigen; der aktive Tab bekommt einen goldenen Akzent-Glow; und das Vote-Fenster zeigt einen laufenden "X/Y abgestimmt"-Zähler neben dem Timer.

### Geändert
- **Das Loot-Council-Fenster ist spürbar breiter:** Namens- und Vote-Spalte haben bei der alten festen Breite echte Spielernamen und Vote-Bezeichnungen abgeschnitten oder umgebrochen — das passiert jetzt nicht mehr, auch mit den neu hinzugekommenen Icon-Spalten.
- **Die Zeile des Gewinners ist jetzt gold statt grün hervorgehoben:** Grün ist gleichzeitig die Farbe der "Upgrade"-Stimme, wodurch eine Zeile uneindeutig beides zugleich sein konnte; Gold kollidiert mit keiner Vote-Kategorie.
- **Der eigene Kommentar eines Raiders bleibt jetzt auch nach dem Abstimmen sichtbar, nicht nur davor:** Das Vote-Fenster hat die Notiz bisher versteckt, sobald abgestimmt wurde; das "Du hast gewählt"-Badge zeigt sie jetzt zusammen mit der gewählten Kategorie an (bei langen Notizen gekürzt), statt sie aus der Ansicht zu verlieren.
- **Tooltips in den Council-Zeilen sind jetzt gezielter:** Der Hover über das Ausrüstungs-Icon (Item-Vergleich) zeigt nicht mehr zusätzlich die Spieler- oder Offizier-Notiz an — die haben jetzt ihren eigenen Tooltip direkt an den Notiz-/Offi-Notiz-Symbolen, damit ein normaler Gear-Vergleich nicht jedes Mal jemandes Kommentar mit anzeigt. Der Hover über einen Tab in der linken Leiste löst außerdem nicht mehr Blizzards eigenen Gear-Vergleichs-Tooltip aus — der ist dort nicht hilfreich, es geht nur um "welches Item ist das".

### Behoben
- **Der Minimieren-Button im Council-Fenster überlappte den Timer/"Fertig"-Text im Titelbalken:** Der Timer war mit einem festen Pixel-Abstand vom Fensterrand verankert, der das neue Minimieren-Symbol nicht berücksichtigt hat; er hängt jetzt stattdessen direkt am Button selbst.

## [1.12.5] - 2026-07-14
### Sicherheit
- **Loot Council vertraut nicht mehr ungeprüften Absendern bei Konfiguration, Ergebnissen und Officer-Notizen:** Drei Addon-Message-Handler übernahmen ihre Nutzdaten von jedem Absender, ohne zu prüfen, wer sie wirklich geschickt hat — ein gefälschter `LC_CONFIG`-Broadcast konnte den eigenen Namen des Absenders auf jedem Client in die Council-Liste eintragen, ein gefälschtes Loot-Ergebnis konnte einen Fake-Eintrag in die Loot-Historie aller Spieler schreiben und ein falsches "Du hast gewonnen"-Popup auslösen, und eine gefälschte Officer-Notiz konnte die Notiz eines beliebigen Spielers ohne jede Berechtigungsprüfung überschreiben. Alle drei prüfen jetzt gegen den aktuellen Roster, ob der Absender wirklich der aktuelle Raid-/Gruppenleiter (Konfiguration) bzw. ein Council-Mitglied (Ergebnisse, Officer-Notizen) ist, bevor sie handeln — das schließt auch den Flüstern-Angriffsweg, da ein Absender, der nicht in der eigenen Gruppe steht, diese Prüfung nie bestehen kann.

### Behoben
- **Antworten auf Versionsabfragen per Whisper kamen nie an:** `SendAddonMessage` benötigt bei Whispers ein explizites Ziel, das der Antwort fehlte; eine per Whisper gestellte Versionsabfrage bekommt jetzt tatsächlich eine Antwort.
- **Fehlende Sockel wurden nur auf englischen/deutschen Clients erkannt:** Die Leerer-Sockel-Erkennung des Gear-Checks hat Tooltip-Text in bestimmten Sprachen abgeglichen statt Item-Stats direkt zu lesen, wodurch fehlende Gems auf jeder anderen unterstützten Sprache still unterschätzt wurden. Jetzt sprachunabhängig.
- **Ein fehlerhafter Droptimizer-Cache-Eintrag konnte die gesamte Loot-Council-Kandidatenliste zum Absturz bringen:** Gewinn-%/Itemlevel-Werte aus der externen KART-Companion-App wurden nicht auf tatsächliche Zahlen geprüft, bevor sie verwendet wurden; ein fehlerhafter Eintrag wird jetzt übersprungen, statt die ganze Zeilenliste abstürzen zu lassen.
- **Ein Loot-Historie-Eintrag mit fehlendem Zeitstempel konnte die Aktualisierung der Historie-Liste stoppen:** Dasselbe Fallback ergänzt, das an anderer Stelle in der Datei bereits verwendet wird.
- **Spielernamen im Buff-Checker konnten optisch in das Ready-Check-Begründungs-Icon hineinlaufen:** Die Namensspalte hatte eine feste Pixelbreite, die weder eine größere Content-Schriftgröße (in den Einstellungen anpassbar) noch lange Name-Realm-Strings berücksichtigte — WoW schneidet Text, der die gesetzte Breite eines FontStrings überschreitet, nicht automatisch ab. Zu lange Namen werden jetzt mit "…" gekürzt, um immer in die Spalte zu passen.
- **Die Ausrüstungs-Itemlevel- und Rüstungseignungs-Spalten eines Loot-Council-Kandidaten konnten für eine ganze Rollrunde leer bleiben:** Frisch gedroppte Items sind oft noch nicht clientseitig gecacht, und nichts hat es erneut versucht, sobald die Daten tatsächlich geladen waren. Das Panel lädt fehlende Item-Daten jetzt im Hintergrund nach und aktualisiert sich automatisch, sobald sie verfügbar sind.
- **Ein erneut zugestelltes Loot-Ergebnis konnte denselben Gewinn doppelt in die Loot-Historie eintragen:** Ein kurzes Dedup-Zeitfenster ergänzt, analog zur bereits vorhandenen Absicherung im Historie-Sync.

### Geändert
- **Die Loot-Council-Konfiguration eines Raidleiters mit sehr langer Council-Mitgliederliste wird jetzt gekürzt, statt eine stille Beschädigung zu riskieren:** Vote-Button-Beschriftungen plus eine lange Council-Liste konnten zusammen das Größenlimit für Addon-Nachrichten überschreiten, wodurch andere Clients die Konfiguration teils still gar nicht übernommen haben. Sie wird jetzt auf das Passende gekürzt, mit einer Warnung an den Leiter, damit er sie kürzt.
- **Visueller Politur-Durchgang:** Hauptfenster und Buff-Checker faden jetzt sanft ein, statt sofort aufzupoppen; Panel-Hintergründe haben jetzt einen dezenten Farbverlauf statt komplett flach zu sein (abgeleitet von deiner bestehenden Hintergrundfarbe, eigene Themes bleiben also erhalten); die Schließen-Buttons in Loot-Historie/Loot-Council nutzen jetzt die gewählte UI-Schrift statt immer die Standard-Blizzard-Schrift.

## [1.12.1] - 2026-07-13
### Geändert
- **Droptimizer-Gewinne haben keinen eigenen Einstellungs-Tab mehr:** Der Schalter "Droptimizer-Gewinn % im Loot Council anzeigen" ist jetzt in den Loot-Council-Einstellungen (neben Auto-Pass), und der Sync-Status (zuletzt synchronisiert, Spieleranzahl) ist jetzt in den Allgemeinen Einstellungen — ein Tab weniger, um zwei Einstellungen zu finden, die inhaltlich zu den Funktionen gehören, die sie betreffen.

## [1.12.0] - 2026-07-13
### Hinzugefügt
- **Loot-Historie kann jetzt als JSON exportiert werden:** Ein neuer "JSON exportieren"-Button im Loot-Historie-Fenster öffnet einen kopierbaren JSON-Dump der aktuell gefilterten Einträge, im selben Feldformat/-reihenfolge wie RCLootCouncils eigener "Standard JSON output"-Export, sodass er in jedes Tool eingefügt werden kann, das für einen RCLootCouncil-Export gebaut wurde. KART trackt nicht alles, was RCLootCouncil trackt (Boss, Instanzname, Stimmenzahl, ersetzte Gear-Links, vergebender Loot Master) — diese Felder werden daher leer/genullt statt erfunden exportiert.
- **Droptimizer-Gewinn % im Loot Council:** Eine neue "Gewinn"-Spalte im Loot-Council-Panel zeigt je Kandidat den simulierten %DPS/HPS-Gewinn durch das gerade gewürfelte Item, basierend auf Droptimizer-Sims, die bereits in WoWUtils importiert wurden (Raidbots oder QE Live). Dafür wird die neue [**KART Companion**](https://github.com/Kandera/KART-Companion)-App benötigt (ein eigenständiges Projekt — ein Tray-Tool, das die meisten Nutzer nicht brauchen), die auf dem PC eines Officers läuft, da das Addon selbst keine Internetverbindung herstellen kann; der Companion synct die Daten in eine neue SavedVariable, die das Addon bei `/reload` einliest. Neuer Schalter "Droptimizer-Gewinn % im Loot Council anzeigen" (standardmäßig aus) im neuen Droptimizer-Einstellungstab.

### Behoben
- **Hovern über eine Loot-Council-Zeile zeigte überall einen Item-Vergleichstooltip, nicht nur über dem Ausrüstungs-Icon:** Blizzards eigenes Tooltip-System vergleicht automatisch jedes in einem `GameTooltip` angezeigte Item mit der eigenen angelegten Ausrüstung, was mit dem eigenen (anderen) Vergleich des Addons gegen die Ausrüstung des Raid-Kandidaten kollidierte und dazu führte, dass er bei fast jeder Mausbewegung über eine Zeile erschien und die Spalten Roll/CV/Gewinn verdeckte. Tooltips erscheinen jetzt nur noch beim Hovern über das kleine Ausrüstungs-Icon und zeigen das gewürfelte Item und die Ausrüstung des Kandidaten nebeneinander über ein eigenes Tooltip-Frame statt über Blizzards gemeinsames.

## [1.11.1] - 2026-07-13
### Geändert
- **Kompatibilität mit Retail-Patch 12.1 erklärt:** Interface-Version `120100` zur TOC hinzugefügt.

### Behoben
- **"×"-Button zum Schließen eines Loot-Council-Tabs war nicht klickbar und flackerte beim Hovern:** Der Schließen-Button liegt als Kindframe über dem Tab, wodurch das Bewegen der Maus auf den Button auch das `OnLeave` des Tabs auslöste (WoW verfolgt den Mausfokus nur für das oberste Frame, nicht für Elternframes). Das hat den Button sofort ausgeblendet, wodurch die Maus wieder über dem Tab lag, was erneut `OnEnter` und damit das Wiedereinblenden auslöste — eine Endlosschleife aus Ein-/Ausblenden, die dabei auch jeden Klick verschluckte, bevor er ankam. Der Button bleibt jetzt sichtbar, solange die Maus über dem Tab oder dem Button selbst ist, und der Tooltip blendet sich stattdessen aus, statt sich mit dem Button um den Platz zu streiten.
- **Zeilen der Trade-Erinnerung zeigten ein leeres Kästchen statt eines Pfeils:** `"%s → %s"` verwendete ein Unicode-Pfeilzeichen, das von WoWs Standard-Spielschriftarten nicht abgedeckt wird, wodurch zwischen Item und Gewinner-Namen ein leeres Kästchen erschien — dieselbe Art von Fehler, die für das Häkchen-Symbol bereits umgangen wurde. Ersetzt durch ein einfaches ASCII `->`.

## [1.11.0] - 2026-07-09
### Hinzugefügt
- **Auto-Invite über Gildenchat kann jetzt separat abgeschaltet werden:** Die Keyword-Invite-Funktion (z.B. "inv" oder "+" tippen) funktionierte sowohl in Flüster-Nachrichten als auch im Gildenchat, was zu versehentlichen Invites durch normale Gildenchat-Gespräche führen konnte. Eine neue Checkbox ("Auto-Invite über Gildenchat erlauben") in den Automation-Einstellungen erlaubt es, den Gildenchat-Trigger abzuschalten, während Invites per Flüstern weiterhin funktionieren.

### Geändert
- **Mehrere Standardwerte für Neuinstallationen wurden angepasst:** Auto-Invite über Gildenchat, das Buff-Checker-Modul, Loot Council, der WoWUtils Import, Auto-Raid-Convert und das automatische Ausblenden der Raidlead-Leiste im Solo-Modus sind jetzt standardmäßig **deaktiviert**; Auto-Pass bei Loot Council ist jetzt standardmäßig **aktiviert**. Dies betrifft nur Neuinstallationen und "Standardwerte zurücksetzen" — bestehende Konfigurationen bleiben unverändert.

## [1.10.2] - 2026-07-09
### Behoben
- **CurseForge-Upload lief nie tatsächlich:** Der Release-Workflow übergab den API-Key an den BigWigsMods-Packager als `CF_API_TOKEN`, der Packager erkennt aber nur `CF_API_KEY`. Dadurch meldete jeder automatisierte Release-Job (auch 1.10.1) Erfolg, während der CurseForge-Upload lautlos übersprungen wurde — es kam nie eine Datei bei CurseForge an. Der Workflow übergibt den Key jetzt unter dem vom Packager erwarteten Namen.

## [1.10.1] - 2026-07-09
### Behoben
- **Addon-Symbol fehlte im Release-Zip:** Der GitHub-Release-Workflow schloss `*.jpg`/`*.png`-Dateien aus dem gepackten Zip aus — dadurch fehlte auch `KAimg.jpg`, die Datei, auf die `IconTexture` im TOC verweist. Wer aus einem GitHub/CurseForge-Release installierte (statt aus einem Git-Checkout), sah ein leeres Symbol in der AddOn-Liste. Der Ausschluss ist entfernt, Bilddateien sind wieder enthalten.

## [1.10.0] - 2026-07-08
### Hinzugefügt
- **Loot Council zeigt jetzt alle gleichzeitig gedroppten Items auf einmal statt nacheinander:**
  - **Looter-Ansicht:** Aus dem einzelnen Abstimmungs-Popup ist eine Liste geworden — jedes aktuell laufende Item bekommt seine eigene Zeile mit eigenen Vote-Buttons, eigener Notiz und eigenem Countdown. So sieht man alle Drops auf einen Blick und kann pro Item unabhängig entscheiden (z. B. BIS auf das eine, Pass auf das andere), statt ein Item erst abhaken zu müssen, bevor das nächste überhaupt sichtbar wird.
  - **Council-/Lootmaster-Ansicht:** Das Panel hat jetzt einen vertikalen Tab-Streifen am linken Rand — ein Tab pro aktuell laufendem Item, mit dem echten Itemsymbol und einer "Stimmen/Gesamt"-Anzeige. Ein Rechtsklick-Vergeben schließt den Tab nicht automatisch, man kann also in Ruhe zwischen den Items hin- und herwechseln und sich ggf. umentscheiden. Hovern über einen Tab zeigt sofort die komplette Stimmverteilung aller Spieler für dieses Item, ganz ohne umzuschalten. Ein neuer Tab reißt dabei nie den aktuell betrachteten weg — er bekommt nur einen kleinen roten "neu"-Punkt und wartet. Das „×" zum Schließen eines einzelnen Tabs erscheint erst beim Hovern (statt permanent in der Ecke zu sitzen), damit ein normaler Klick zum Umschalten nicht aus Versehen den Tab wegklickt. Die grüne Gewinner-Markierung einer Zeile ist jetzt außerdem pro Item statt global — vorher blieb ein bereits zugewiesener Spieler beim Wechsel auf ein anderes Item fälschlich weiter grün markiert.
  - Beide Test-Buttons ("Test Looter" / "Test Master") verteilen jetzt testweise 4 simulierte Items gleichzeitig, damit sich genau dieses Verhalten auch ohne echten Raid durchspielen lässt. Die Test-Items sind jetzt echte (aber folgenlose) Item-Links (Sulfuras, Thunderfury, Corrupted Ashbringer, Hand of Justice) statt Fantasie-Strings — dadurch zeigen die Tabs echte Itemsymbole, Tooltips funktionieren, und auch der Rüstungsklassen-Hinweis sowie der Ausrüstungsvergleich lassen sich im Test-Modus durchspielen. Das Trinket deckt dabei gezielt den Zwei-Slot-Vergleich ab (Ringe/Trinkets prüfen beide Slots und zeigen das schwächere Stück) — die drei Waffen sind alle einslotig. Ein Klick auf den jeweils anderen Test-Button setzt dabei nicht mehr die bereits laufende Testrunde zurück — vorher konnte das Öffnen von "Test Looter" bei bereits offenem "Test Master" (oder umgekehrt) die Tabs des anderen Fensters im Hintergrund unbemerkt aus der Datengrundlage reißen; sichtbar wurde das erst beim nächsten Vote, der dann fälschlich so aussah, als würde eine Stimmabgabe die Tabs zum Verschwinden bringen und den eigenen Vote verschlucken.
- **Test-Buttons im Loot-Council-Tab spielen jetzt zusammen:** Ein im Looter-Testfenster abgegebener Vote trägt sich sofort ins Master-Testpanel ein, auch komplett solo ganz ohne Gruppe — so lässt sich die komplette Lootvergabe alleine durchspielen, inklusive Zuweisung und lokalem "Du hast gewonnen"-Popup. Testrolls bleiben dabei strikt lokal: kein Broadcast an die Gruppe, keine Raidchat-Ankündigung und kein Eintrag in der echten (persistenten) Loot-History — vorher konnte ein Testlauf während eines laufenden Raids versehentlich eine echte Gewinner-Ankündigung im Raidchat auslösen und einen Fake-Eintrag in der Loot-History aller Mitspieler hinterlassen.
- **1-100 Zufalls-Rolls im Loot Council (analog zu RCLootCouncil):** Neue Option in den Raid-weiten Einstellungen ("1-100 Zufalls-Rolls anzeigen", nur wirksam als Raidleiter). Ist sie aktiv, würfelt jeder berechtigte Raider automatisch einen Wert von 1-100, sobald ein Item zur Abstimmung ansteht — ganz ohne eigenes Zutun, wie RCLootCouncils Need-Roll. Der Wert erscheint als eigene Spalte im Council-Panel und ist rein informativ, er beeinflusst keine Zuweisung automatisch.
- **Council-Stimmen-Zähler im Council-Panel:** Jede Zeile hat jetzt einen "CV"-Button (Council Votes), mit dem jedes Council-Mitglied für den favorisierten Kandidaten stimmen kann (ein Klick auf den gleichen Kandidaten macht die Stimme wieder rückgängig, ein Klick auf einen anderen ersetzt sie). Die Zahl daneben zeigt, wie viele Council-Mitglieder aktuell für diesen Spieler gestimmt haben — rein zur Orientierung, die tatsächliche Zuweisung läuft weiterhin ausschließlich über Rechtsklick → Zuweisen.
- **Persistente Spieler-Notizen im Council-Panel:** Rechtsklick auf eine Zeile → "Notiz bearbeiten" öffnet ein Textfeld für eine dauerhafte Notiz zu diesem Spieler (z. B. "hat schon BIS-Trinket", "ging die letzten zwei Items leer aus") — anders als die Vote-Notiz eines Raiders ist diese nicht an ein einzelnes Item gebunden, sondern taucht bei jedem Item auf, bei dem der Spieler in der Liste steht. Wird an alle gerade online befindlichen Council-Mitglieder verteilt und bleibt über Reloads erhalten (eigene SavedVariable); ein Abgleich für Council-Mitglieder, die beim Schreiben der Notiz offline waren, findet aktuell nicht statt. Das Eingabefenster ist ein eigenes kleines Fenster statt eines Blizzard-StaticPopups — Retails überarbeitetes StaticPopup-System (läuft mittlerweile über `Blizzard_StaticPopup_Game/GameDialog.lua`) stellte das Eingabefeld in `OnAccept` nicht mehr zuverlässig als `self.editBox` bereit und warf beim Bestätigen einen Lua-Fehler.
- **Rüstungsklassen-Hinweis im Council-Panel:** Zeilen von Spielern, die die Rüstungsart des aktuellen Items gar nicht tragen können (z. B. Platte auf einem Magier), werden abgedunkelt dargestellt, mit Tooltip-Hinweis. Rein visuell — Zuweisen per Rechtsklick funktioniert für jede Zeile unverändert, für den Fall, dass die Erkennung mal danebenliegt.
- **Trade-Erinnerung mit Auto-Trade für Loot Council:** Nach einer Zuweisung an einen anderen Spieler merkt sich KART, wer noch was getradet bekommen muss, und zeigt dafür ein kleines, verschiebbares Erinnerungsfenster ("Noch zu tradende Items") mit einer Liste aller offenen Trades (Häkchen-Button zum manuellen Abhaken). Öffnet man daraufhin ein Handelsfenster mit genau dem richtigen Spieler, wird das passende Item automatisch aus den eigenen Taschen ins Handelsfenster gelegt — bestätigt werden muss der Handel weiterhin manuell. Bricht automatisch ab (Item bleibt in der Erinnerung stehen), wenn das Item nicht mehr in den eigenen Taschen gefunden wird oder gerade etwas anderes am Mauszeiger hängt.
- **Reset-Button im WoWUtils-Tab:** Setzt die importierte Boss-Liste komplett zurück (mit Bestätigungsdialog).

### Geändert
- **Item-Icon in der Vote-Liste:** Vor dem Item-Namen steht jetzt auch im Looter-Fenster ein kleines Icon (echtes Itemsymbol bei echten Items, eingefärbter Platzhalter sonst) — analog zum Council-Panel.
- **Vote-Liste im Looter-Fenster überarbeitet, weniger zusammengedrängt:** Fenster und Abstände vergrößert (mehr Innenabstand pro Item, größerer Abstand zwischen den einzelnen Item-Blöcken, mehr Luft um das Notizfeld), Vote-Buttons etwas größer mit dezenterer statt sehr kräftiger Rahmenfarbe — vorher saß alles nahezu ohne Abstand aneinander und wirkte wie eine Wand aus Kästchen, besonders bei mehreren gleichzeitig laufenden Items.
- **Vote-Zeile schließt/markiert sich nach der Stimmabgabe sofort:** Statt eines "Stimme abgegeben!"-Zwischenzustands mit 2,5 Sekunden Verzögerung zeigt die Zeile sofort "✓ Gewählt: <Option>" an — bei mehreren gleichzeitig laufenden Items geht dadurch keine Zeit verloren.
- **WoWUtils-Import über mehrere Difficulties hinweg:** Ein erneuter Import (z. B. erst die Normal-, dann die Heroic-Zusammenstellung einfügen) überschreibt nicht mehr die komplette Liste. Einträge werden jetzt anhand von EncounterID + Difficulty zusammengeführt, sodass mehrere Difficulties desselben Bosses gleichzeitig in der Liste stehen bleiben. Zum vollständigen Leeren dient der neue Reset-Button.
- **Split-Raid-Unterstützung im WoWUtils-Import:** Wird für denselben Boss und dieselbe Difficulty ein zweiter Import mit anderem Roster eingefügt (z. B. Team A / Team B bei Splits), wird dieser nicht mehr überschrieben, sondern als eigener Eintrag ergänzt. Gleichnamige Einträge werden dabei automatisch als "Bossname A", "Bossname B", usw. unterscheidbar gemacht.

### Behoben
- **Leere Kästchen statt Symbolen im Council-Panel:** Die neuen Symbole (★ ☆ ● ✓) für den Council-Stimmen-Button, die Notiz-Markierung und die Trade-Erinnerung wurden von WoWs Standard-Spielschriftarten nicht unterstützt und dadurch als leeres Kästchen ("Tofu") dargestellt. Ersetzt durch reinen ASCII-Text (z. B. "CV" statt ★) bzw. durch eine echte Textur bei der Trade-Erinnerung.
- **Spaltenüberschriften im Council-Panel nicht auf Höhe der Werte darunter:** Die Header (Player/iLvl/Vote/Roll/CV) waren ohne feste Breite und Ausrichtung positioniert, während die Werte darunter teils zentriert in fester Breite sitzen (z. B. Roll-Zahl, iLvl) — dadurch liefen Überschrift und Wert sichtbar auseinander. Jede Überschrift hat jetzt exakt dieselbe Breite, Ausrichtung und X-Position wie ihre Spalte.
- **1-100 Rolls blieben unsichtbar, obwohl aktiviert:** `LC.GetRollsEnabled()` prüfte nur `UnitIsGroupLeader("player")`, was ohne Gruppe (z. B. beim Solo-Testen) `false` zurückgibt — dadurch griff immer der (nie synchronisierte) Raid-Wert statt der eigenen Einstellung, und die Rolls-Spalte blieb ausgeblendet. Nutzt jetzt denselben Fallback wie `GetButtonConfig`: die eigene Einstellung gilt auch, wenn (noch) keine Raid-Konfiguration vorliegt.
- **Gleichzeitig gedroppte Items überschrieben sich gegenseitig im Loot Council:** Vote-Popup und Council-Panel konnten bisher immer nur genau einen Roll gleichzeitig anzeigen — droppte ein Boss mehrere Items auf einmal (der Normalfall, nicht die Ausnahme), riss jeder neue Roll das Fenster des vorherigen sofort weg, bevor überhaupt abgestimmt bzw. zugewiesen werden konnte. Siehe die neue Listen-/Tab-Ansicht oben, die dieses Problem grundlegend behebt statt nur zu kaschieren.
- **Vergleich mit dem aktuell getragenen Item im Council-Panel funktionierte nie:** `C_Item.GetItemInfo()` liefert eine Liste einzelner Werte zurück, kein Table — der Code hat aber nur den ersten Rückgabewert (den Item-Namen, einen reinen String) in einer Variablen gespeichert und anschließend mit `["equipLoc"]` bzw. `["itemLevel"]` darauf zugegriffen. Ein String liefert bei so einem Zugriff still `nil` zurück, wodurch für kein einziges Item jemals ein passender Ausrüstungsslot gefunden wurde — betraf nicht nur den Test-Modus, sondern jede echte Lootvergabe. Icon und Itemstufe des aktuell getragenen Vergleichsitems werden jetzt korrekt angezeigt.
- **"Zuweisung ändern" im Council-Panel löste fälschlich eine Neuzuweisung aus:** Das Untermenü fragte beim Rechtsklick (wenn das Item bereits vergeben war) mit dem "erneut zuweisen?"-Bestätigungsdialog nach, obwohl es eigentlich nur den angezeigten Vote eines Spielers korrigieren sollte (z. B. wenn jemand per Whisper statt per Klick abgestimmt hat). Der Menüpunkt heißt jetzt "Vote ändern" und ändert wirklich nur den Vote — ohne Zuweisung, Ankündigung oder Bestätigungsdialog. Tatsächliches Zuweisen (inkl. Neuzuweisung mit Bestätigung) läuft ausschließlich über "Zuweisen" bzw. "Ohne Grund zuweisen".
- **Komplette Neuordnung der "Raid-weite Einstellungen"-Box (Loot Council):** Die Box (Titel, Rollen-Status, Trennlinie, Vote-Timer-Slider, alle Labels/Eingabefelder/Buttons) positioniert sich jetzt vollständig selbst: Jedes Element hängt am tatsächlich gemessenen unteren Rand des vorherigen Elements statt an hartkodierten Pixelwerten. Das behebt mehrere zusammenhängende Bugs auf einen Schlag:
  - Labels mit längerem (v. a. deutschem) Text ragten über den rechten Rand der Box hinaus → jetzt feste Breite mit Wortumbruch.
  - Nach einem Font-/Größenwechsel über `KART.UpdateStyles()` (läuft erst nach dem Bau des Panels) verschob sich der Zeilenumbruch nachträglich und überschnitt die Eingabefelder → Layout wird jetzt automatisch neu berechnet, sowohl nach `UpdateStyles()` als auch nach jedem Wechsel des Rollen-Status-Texts (Raidleiter/Mitglied).
  - Die Test-Buttons und der Loot-History-Button darunter ragten in die Box hinein, weil sie an einer fixen Höhe hingen, die von der alten statischen Boxhöhe ausging → jetzt am tatsächlichen unteren Rand der Box verankert.
  - Die Box ist außerdem etwas breiter (280→295px) und nutzt so vorhandenen Platz besser aus; der scrollbare Bereich im Hauptfenster wurde vorsorglich vergrößert (600→750px), damit bei größeren Schriftgrößen nichts unten aus dem sichtbaren/scrollbaren Bereich herausfällt.

## [1.9.2] - 2026-07-07
### Behoben
- **Überlappender Text im Loot-Council-Tab:** In der neuen "Raid-weite Einstellungen"-Box standen Titel und Rollen-Status (z. B. "Du bist Raidleiter") nebeneinander auf derselben Zeile in einer nur 280px breiten Box und kollidierten dadurch in der Mitte. Beide Texte stehen jetzt untereinander und wurden deutlich gekürzt; alle darunterliegenden Elemente wurden entsprechend neu positioniert.

### Entfernt
- **`Minimap.lua`:** Tote Datei, die seit Version 1.1.1 nicht mehr in der TOC geladen wurde (ersetzt durch LibDBIcon), aber nie tatsächlich aus dem Projekt gelöscht wurde. Enthielt u. a. eine zweite, nie ausgeführte Version von `KART.UpdateMinimapButton()`.
- **Verwaiste Lokalisierungs-Strings:** `BC_REPORT_ENCHANTS`, `BC_REPORT_GEMS`, `BC_REPORT_OIL` (nie mit einem Report-Feld verknüpft), `LC_DESC_COUNCIL` (nie als Tooltip verdrahtet), `LC_NO_VOTE` (Code nutzt stattdessen einen hartcodierten Platzhalter) und `SET_TITLE_SIZE` (Duplikat von `LABEL_FONT_SIZE_TITLE`).

### Sonstiges
- **Fehlende deutsche Übersetzungen ergänzt:** `DESC_LANGUAGE`, `DESC_SELECT_FONT` und `RC_REASON_SEND` fielen bisher automatisch auf Englisch zurück und sind jetzt vollständig übersetzt.

## [1.9.1] - 2026-07-07
### Behoben
- **Lua-Fehler beim Login:** `BuildSettingsPanel` in LootCouncil.lua griff beim Aufbau der Oberfläche direkt auf `KART_Settings.lcMinQuality` zu — zu diesem Zeitpunkt existiert die SavedVariable aber noch nicht (sie wird erst bei `ADDON_LOADED` initialisiert). Der Mindest-Qualitäts-Button verwendet jetzt einen Platzhaltertext beim Aufbau; der echte gespeicherte Wert wird wie vorgesehen unmittelbar danach nachgezogen.

## [1.9.0] - 2026-07-06
### Hinzugefügt
- **Modul-Schalter für Loot Council, Buff-Checker und WoWUtils:** Jedes Modul lässt sich jetzt einzeln komplett deaktivieren — praktisch während der Testphase (z. B. bei Konflikten mit RCLootCouncil) oder um CPU zu sparen, wenn Raider bestimmte Funktionen nicht brauchen.
  - Beim Deaktivieren von Loot Council werden keinerlei Nachrichten anderer KART-Nutzer mehr verarbeitet, kein Auto-Pass, keine Popups.
  - Beim Deaktivieren des Buff-Checkers bleibt der Hintergrund-KART-Sync (Öl/ilvl/Gear-Antworten für andere) bewusst aktiv — nur das eigene Fenster wird abgeschaltet, damit der Raidleiter weiterhin korrekte Daten über diesen Spieler sieht.
- **Warnsymbol im Council-Panel:** Zeigt pro Raider ein rotes „!" (mit Tooltip), wenn kein KART erkannt wurde, eine veraltete Version läuft oder der Spieler Loot Council lokal deaktiviert hat.

### Geändert
- **Raid-weite Autorität für Loot Council:** Abstimmungs-Timer, Vote-Buttons, zusätzliche Council-Mitglieder und Mindest-Itemqualität gelten jetzt immer gemäß den Einstellungen des Raidleiters — nicht mehr die lokalen Einstellungen jedes einzelnen Spielers. Verhindert, dass jemand z. B. die Abstimmungszeit lokal verkürzt oder sich selbst über die eigene Council-Liste unbefugt Zuweisungsrechte verschafft.
  - **Auto-Pass bleibt davon unberührt** und ist weiterhin eine rein persönliche Einstellung.
  - Die betroffenen Einstellungen sind im Options-Menü jetzt visuell in einer eigenen Box abgegrenzt, inklusive Live-Anzeige, ob die eigenen Einstellungen gerade wirksam sind („Du bist Raidleiter" / „Einstellungen des Raidleiters gelten").

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

[Unreleased]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.10.0...HEAD
[1.10.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.2...v1.10.0
[1.9.2]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.1...v1.9.2
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
