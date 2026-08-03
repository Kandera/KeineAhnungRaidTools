[English](CHANGELOG.md) | **Deutsch**

# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unveröffentlicht]
### Behoben
- **Items zeigen jetzt bei allen das echte Itemlevel und die echten Werte** — auch bei Raidern, die kein eigenes Würfelfenster von Blizzard bekommen haben.
- **Raider werden nicht mehr den ganzen Abend als „Kein KART erkannt" angezeigt** — die Versionsabfrage repariert sich jetzt selbst.

### Hinzugefügt
- **`/kart status` meldet jetzt verworfene Nachrichten und eigene, die nie rausgingen.**

## [3.3.0] - 2026-08-02
### Behoben
- **Das Ausblenden von Items, die deine Klasse nicht nutzen kann, ist wieder verfügbar** — und nimmt dir kein Off-Spec-Upgrade mehr weg.
- **Die automatische Transmog-Stimme ist wieder verfügbar** — und stimmt nie für ein Aussehen, das dein Charakter nicht lernen kann.
- **Ein für dich beantwortetes Item bleibt sichtbar**, damit du die Antwort noch ändern kannst.
- **Beide Einstellungen wirken jetzt auch auf die Items, die schon vor dir liegen** — nicht erst ab dem nächsten Boss.
- **Items laufen auch ab, während dein Vote-Fenster leer ist** — statt später mit aktiven Vote-Buttons zurückzukommen.
- **`/kart lc` öffnet das Fenster mit dem, was gerade läuft** — nicht mit dem Bild von vorhin.
- **`/kart trade` und `/kart owed` zeigen, was jetzt offen ist** — nicht, was beim Schließen offen war.
- **Die Council-Mitgliederliste sagt, wer wirklich im Council ist.** Der Raidleiter ist nicht automatisch drin — trag dich ein, wenn du mitentscheidest.
- **Die Items auf dem Tisch überstehen einen Reload.** Wer den Loot verteilt, hat sie vorher komplett verloren — alle anderen, sobald der Vote-Timer abgelaufen war.
- **Die Loot-Historie zu löschen hält jetzt.** Vorher hat sie ein anderer Client direkt wieder reingesynct; alles, was nach dem Löschen vergeben wird, kommt weiterhin an.
- **Ein Raider von einem anderen Realm bekommt in der Gain-Spalte nicht mehr die Sim-Zahl eines gleichnamigen Charakters.**
- **Der Report fehlender Buffs kommt auch dann im Raid an, wenn vielen etwas fehlt.** Bei langer Namensliste ist er vorher stillschweigend verschwunden.
- **Auto-Promote greift jetzt auch bei Namen im Format "Name-Realm" für den eigenen Realm.** Bisher traf diese Schreibweise ausschließlich Leute von anderen Realms.
- **Ein Bulk-Invite kann wieder aus dem Stand einen Raid aufmachen.** Ein Klick auf Einladen ohne Gruppe sagte „du bist nicht der Anführer" und tat nichts.
- **Das automatische Kampflog startet nicht mehr in der offenen Welt.** Es prüft jetzt, ob du wirklich in einer Instanz bist, statt nur auf die gemeldete Schwierigkeit zu schauen.
- **Die Loot-Historie nach einem Spieler zu filtern zeigt dessen komplette Historie** — statt sie auf zwei gleich aussehende Einträge zu verteilen.
- **Ausgetretene Raider stehen im Historien-Filter mit Namen**, nicht als rohe ID.
- **Alle zu entfernen, die nicht auf der Boss-Liste stehen, fragt jetzt vorher** — und sagt, um wie viele Leute es geht.
- **Ein beschädigtes Einstellungsprofil reißt deine Einstellungen nicht mehr mit.** Es wird abgelehnt statt halb geladen.
- **Eine von Hand korrigierte Stimme verschwindet mit ihrem Item** — statt beim nächsten Drop als Antwort aufzutauchen.
- **Mindestqualität und Würfe des Raids lassen sich nicht anklicken, solange fremde Einstellungen gelten.** Ein Klick hat vorher deine eigenen überschrieben.
- **Das Entfernen von Spielern prüft beim Bestätigen erneut.** Verlierst du währenddessen die Leitung oder wird gepullt, wird jetzt niemand mehr rausgeworfen.
- **Eine Vergabe mit langem Vote-Grund landet auch in der Loot-Historie der anderen.** Vorher fehlte sie dort kommentarlos.
- **Eine Vergabe, die während des Startens deines Clients angekündigt wurde, landet doch noch in deiner Loot-Historie.**
- **Wer den Loot verteilt, wird gewarnt, wenn ein Item doch an jemand anderen ging** — statt ein Item zuzusagen, das er gar nicht hat.

## [3.2.2] - 2026-08-01
### Behoben
- **Ein Council-Mitglied, dessen Einstellungen spät ankommen, bekommt die schon laufenden Items trotzdem.**
- **Wer sich selbst ein Item zuweist, wird jetzt auch daran erinnert.**
- **Handelserinnerungen verschwinden, sobald das Item nicht mehr übergeben werden kann**, statt weiter aktuell auszusehen.
- **Einen Vote-Button mitten im Wurf umzubenennen ändert nicht mehr die Beschriftung bereits abgegebener Stimmen.**
- **Eine vom Netzwerk verzögerte Stimme kann nicht mehr beim nächsten Item landen, das dieselbe Wurf-ID bekommt.**
- **Das Council sieht bei einem Item, das eine schon vergebene Wurf-ID erbt, die Würfe aller** — statt den Gleichstand auf einem Teil des Raids zu entscheiden.
- **Wer mitten im Raid dazukommt, behält die bereits vergebenen Items im Log**, statt sie beim nächsten Item mit derselben Wurf-ID zu verlieren.
- **Ein Raidlead, der neu lädt, bekommt die Council-Liste des Raids zurück** — statt von jemandem beantwortet zu werden, der ebenfalls gerade neu geladen hat, womit die Hälfte des Raids nichts mehr vergeben konnte.
- **Ein Item nach einem Reload neu zuzuweisen funktioniert wieder.** Der Raid behielt den alten Gewinner, während auf deinem Bildschirm der neue stand.
- **Ein kurzer Verbindungshänger kostet einen Raider nicht mehr seine Stimme.** Kurz bevor das Council entscheidet, werden die Stimmen zu einem Item noch einmal eingesammelt.
- **Raidlead zu übernehmen nimmt dem Raid nicht mehr den Lootmaster.** Ein leeres Lootmaster-Feld heißt jetzt „noch nicht gesetzt“ statt „niemand“.
- **Die Raid-Einstellungen erreichen wieder alle, wenn der Lootmaster nicht der Raidlead ist.** Bisher hat sie niemand nachgeschickt — wer später dazukam, lief auf seinen eigenen Vote-Buttons, seiner Mindestqualität und seiner Wurf-Einstellung.
- **Das × an einer Council-Karte lässt sich wieder anklicken.** Es verschwand, sobald die Maus die Karte verließ, und wurde bei jeder eintreffenden Stimme unter dem Cursor ausgeblendet.
- **`/kart status` zeigt, wen dein Client für den Raidlead hält.** Dass zwei Leute das unterschiedlich lesen, steckt hinter fast jedem Einstellungsproblem.
- **„Dir steht das zu“ verschwindet, sobald du das Item tatsächlich bekommst.** Bisher blieb es stehen, bis du es selbst abgehakt hast.
- **KART-Fenster lassen sich nicht mehr aus dem Bildschirm schieben** — im Fenstermodus mit zweitem Monitor ging das leicht.
- **Wenn zwei Council-Mitglieder dasselbe Item gleichzeitig vergeben, ist sich der Raid trotzdem einig, wer gewonnen hat** — und es wird angesagt.
- **Ein Lootmaster-Name, den KART niemandem zuordnen kann, wird gemeldet statt still übergangen.**
- **Der Raidlead besitzt jetzt die raidweiten Loot-Council-Einstellungen**, und das Lootmaster-Feld sagt, wer den Loot verteilt.
- **Ein Lootmaster, dessen Nickname niemand lesen kann, kostet den Raid nicht mehr seine Einstellungen.**
- **Wer Raidlead übernimmt, erfährt, dass der Raid ab jetzt auf seinen Einstellungen läuft.**
- **Blizzards eigene Bestätigungsdialoge funktionieren wieder.** Das Aufwerten eines Items konnte bis zum nächsten Reload komplett verweigert werden.
- **Wer die Lootverteilung macht, erfährt jetzt, welche Raider ein zu altes KART haben**, statt dass deren Clients die ganze Verteilung stillschweigend ignorieren.
- **Ein Item, das das Loot Council nie aufgenommen hat, wird nicht mehr automatisch gepasst.** Blizzards Würfelfenster bleibt offen, damit der Raid darauf würfeln kann, und KART sagt Bescheid.
- **Die Handelsfrist eines Items übersteht einen Reload**, statt ihre vier Stunden erst ab der Entscheidung des Councils zu zählen.
- **Eine Session mit leerem Lootmaster-Feld zu starten warnt jetzt.** Der Raid behält diese Einstellungen nur, solange du Raidlead hast.
- **KARTs eigene Bestätigungsdialoge sind wieder sichtbar**, statt hinter dem Fenster aufzugehen, das sie geöffnet hat.
- **Set-Tokens laufen wieder über das Loot Council**, statt von niemandem normal ausgewürfelt zu werden.
- **Spielzeuge bleiben aus dem Loot Council heraus**, statt vom Lootmaster einkassiert zu werden.
- **Die beiden Relevanz-Schalter sind vorerst ausgegraut.** Irrelevantes ausblenden und die automatische Transmog-Stimme bleiben aus, bis die bekannten Fehler darin behoben sind.
- **Wer die Lootverteilung übernimmt, bekommt keine Handelserinnerungen mehr für Items, die er nie hatte.** KART sagt es an, statt die Erinnerung stillschweigend wegzulassen.
- **Items zeigen ihr Symbol auch bei Spielern, deren Client keinen eigenen Loot-Roll hatte**, und ihren Namen sobald das Item bekannt ist, statt die ganze Abstimmung lang ein Fragezeichen.
- **Ein Item verschwindet aus dem Vote-Fenster desjenigen, der es vergeben hat.**
- **Transmog-Stimmen stehen über den Spielern, die gepasst haben.**
- **Ein Bei- oder Austritt beendet die Session nicht mehr.**
- **Der Start-Prompt kann keine bereits laufende Session mehr beenden.**
- **Das Lootmaster-Feld bleibt bearbeitbar, wenn der Lootmaster den Raid verlassen hat**, damit ein Ersatz eingetragen werden kann.
- **Beim Start einer Session wird gewarnt, wenn kein Lootmaster eingetragen ist**, statt stillschweigend jeden Raider auf seinen eigenen Vote-Buttons und seiner eigenen Würfe-Einstellung sitzen zu lassen.
- **Ein Lootmaster, der neu lädt, übernimmt die laufende Session wieder**, statt sie für jeden zu beenden, der bei ihm nachfragt.
- **Zonenwechsel und Reload stellen die Session wieder her**, ohne auf einen Bei- oder Austritt warten zu müssen.
- **Ein Raid mit leerem Lootmaster-Feld bekommt wieder eine raidweite Konfiguration**, damit niemand auf seinen eigenen Vote-Buttons und seiner eigenen Würfe-Einstellung sitzen bleibt.
- **Die Raid-Konfiguration erreicht auch Spieler, deren Client keine Northern-Sky-Nicknames lesen kann.**
- **Ein Lootmaster, der den Raid verlässt, blockiert die Lootverteilung nicht mehr für alle.** Der Raidleiter wird gefragt und übernimmt nach Bestätigung.
- **Das Eintragen eines Nachfolgers im Lootmaster-Feld wird dem Raid mitgeteilt**, statt alle weiter auf den Abgebenden zeigen zu lassen.
- **Ein Raidleiter mit leerem Lootmaster-Feld kann den eingetragenen Lootmaster nicht mehr verdrängen.**
- **Den Start-Prompt mit Escape zu schließen lässt die Frage offen**, statt still „keine Session" für den ganzen Abend zu bedeuten.
- **Eine Session, die dich nie erreicht hat, wird erneut angefragt** — nicht nur ein einziges Mal.
- **Das Zurücknehmen einer Vergabe löscht keine fremde Vergabe aus einem früheren Raid mehr.**
- **Auf ein Item, dessen Daten spät eintreffen, wird gewartet**, statt es kommentarlos zu überspringen.
- **Ein Raidleiter, der ohne eingetragenen Lootmaster verteilt, behält die Hoheit über die raidweiten Einstellungen**, statt sie im Moment des Sendens zu verlieren.
- **Die Übergabe der Lootmaster-Rolle erreicht den Raid wieder.**
- **Wer später dazukommt, bekommt die vollständige Loot-History** — bisher fehlte eines von zwei gleichen Items, die an dieselbe Person gingen.
- **Ein Lootmaster, der neu lädt, bekommt die Session auch dann zurück, wenn kein Council-Mitglied da ist, das es ihm sagen kann** — statt den Rest des Abends nichts mehr zu erzwingen.
- **Ein Client, der die Session verloren hat, fragt schneller nach** — und bei jeder Rosteränderung erneut, statt nach der ersten Versuchsreihe endgültig aufzugeben.
- **Wer dazukommt, nachdem der Lootmaster den Raid verlassen hat, bekommt trotzdem die Vote-Buttons, Mindestqualität und Würfe-Einstellung des Raids** — statt still auf seine eigenen zurückzufallen.
- **Ein Raidleiter, der neu lädt, überschreibt die Einstellungen des Raids nicht mehr mit seinen eigenen** — vorher saß danach die Hälfte des Raids auf anderen Vote-Buttons und ohne Würfe.
- **Die Session bestätigt jeder Raider, der sie kennt** — nicht nur der eine Client, der die Lootverteilung führt.
- **Ein Item, das während deines Reloads gedroppt ist, erreicht dich trotzdem** — du kannst noch abstimmen und das Council wartet nicht vergeblich.
- **End Round räumt die Runde für den ganzen Raid**, nicht nur bei dem, der gedrückt hat. (#15)

## [3.2.1] - 2026-07-29
### Behoben
- **Die beiden Schalter für irrelevante Items behalten ihren Zustand nach einem Reload**, statt sich als aus anzuzeigen und trotzdem zu greifen.
- **Beide Schalter folgen einem Sprachwechsel** wie jede andere Einstellung.

## [3.2.0] - 2026-07-28
### Hinzugefügt
- **Items, die deine Klasse nicht anlegen kann, lassen sich jetzt aus dem Vote-Fenster ausblenden.** Sie werden automatisch mit deiner letzten konfigurierten Antwort beantwortet, damit der Council nicht wartet.
- **KART kann für dich Transmog wählen bei Items, die du nicht anlegen kannst, deren Aussehen dir aber fehlt.**
- **Ein fester Transmog-Button ist jetzt immer die letzte Antwort.** Frei konfigurierbare Labels sinken von sechs auf fünf.

## [3.1.1] - 2026-07-28
### Behoben
- **Fenster- und Buttonrahmen werden bei jeder UI-Skalierung durchgezogen**, statt auf einer für einen größeren Bildschirm skalierten Oberfläche stückweise wegzubrechen.

## [3.1.0] - 2026-07-28
### Hinzugefügt
- **`/kart status` zeigt den Loot-Council-Zustand, den der eigene Client wirklich benutzt** — Lootmaster, Council, Rolls und Vote-Buttons.
- **Die Loot-Council-Fenster haben eine eigene Skalierung und Ebene**, unabhängig vom Rest des Addons.

### Geändert
- **Slider-Werte lassen sich eintippen**, nicht nur ziehen.
- **Ein KART-Fenster kommt beim Anklicken nach vorn**, damit sich zwei überlappende Fenster umsortieren lassen.
- **Die Nachfrage nach dem Ready-Check-Grund erscheint nur noch im Raid**, nicht vor jedem Mythisch+-Pull.

### Behoben
- **Die Loot-Council-Einstellungen des Raids kommen jetzt bei allen an.** Wessen Client den Nickname des Lootmasters nicht lesen konnte, behielt stillschweigend seine eigenen Vote-Buttons, Roll-Einstellung und Council-Liste — seine Stimmen erschienen unter dem falschen Label und er würfelte nie.
- **Eine abgelehnte Raid-Config meldet sich**, statt lautlos zu scheitern.
- **Eine Stimme trägt den Button mit, auf den sie abgegeben wurde.** Zwei Clients mit unterschiedlichen Button-Listen zeigen einander nicht mehr die falsche Wahl.
- **Eine zu lange Council-Config wird abgelehnt statt abgeschnitten verschickt**, was vorher den ganzen Raid auf veralteten Einstellungen zurückließ.
- **Allein kann man wieder sein eigener Lootmaster sein** — die Bedienelemente bleiben außerhalb einer Gruppe nutzbar.
- **Raider sehen die tatsächlich geltenden Loot-Council-Einstellungen**, nicht ihre eigenen ungesendeten.
- **Die Status-Markierung der Mitspieler aktualisiert sich**, statt auf ihrem ersten Stand einzufrieren.
- **Ausrüstungs- und Haltbarkeitsdaten von Spielern, die die Gruppe verlassen haben, werden verworfen.**
- **Zwei identische Items im Abstand von Sekunden ergeben zwei Verlaufseinträge**, nicht einen.
- **Die Datenantworten sind gedrosselt und Aktualisieren entprellt**, ein Klick flutet den Raid nicht mehr.
- **Die Hintergrund-Deckkraft erreicht die Loot-Council-Fenster.**
- **Der Item-Tooltip deckt im Vote-Fenster das ganze Symbol ab.** (#7, #8)
- **Ein Council-Tab schließt sich nicht mehr, wenn man zu ihm wechseln wollte.** (#9)
- **Das WoW-Utils-Einfügefeld nimmt über die ganze Höhe den Fokus an.**
- **Auto-Promote erkennt einen Realm-Namen in beiden Schreibweisen.**
- **Das Minimap-Symbol bleibt ausgeschaltet** — über Reload und neue Sitzung hinweg.
- **Ein Bestätigungsdialog öffnet sich immer vor dem Fenster, das ihn ausgelöst hat** — unabhängig von der eingestellten Ebene.
- **Ein nach dem letzten Stilwechsel gebautes Element benutzt die gewählte Schrift** statt der Blizzard-Standardschrift.
- **`/kart v` zählt nur Antworten**, keine stummen Clients.
- **Eine per Profilwechsel geänderte Einstellung greift jetzt**, statt gespeichert und ignoriert zu werden.

## [3.0.2] - 2026-07-27
### Behoben
- **Der erweiterte Ready-Check funktioniert wieder.** Wer ablehnt, bekommt die Grund-Buttons und das Textfeld.
- **Der Buff-Checker behält Ready-Check-Ergebnis und Gründe nach dem Check**, statt beides genau dann zu leeren, wenn es gebraucht wird.

### Hinzugefügt
- **Die Grund-Abfrage lässt sich abschalten**, unter Raidlead-Werkzeuge — für alle, die einfach nur ablehnen wollen.

## [3.0.1] - 2026-07-27
### Geändert
- **"Session beenden" heißt jetzt "Runde beenden".** Es leert die aktuelle Runde bei allen, ohne die Loot-Council-Session insgesamt abzuschalten.
- **Der Schriftgrößen-Regler für Loot Council ist jetzt in der persönlichen Einstellungskarte**, direkt bei den anderen persönlichen Anzeigeoptionen.

### Behoben
- **Das rote "!"-Warnsymbol bei einer Council-Zeile zeigt jetzt beim Hovern an, was es bedeutet.**
- **Loot-Council-Einstellungen (Button-Beschriftungen, Mindestqualität, Council-Liste) erreichen jetzt jeden Spieler in einem gerade erst formierten Raid, noch bevor NSRT den Spitznamen des Lootmasters synchronisiert hat.**

## [3.0.0] - 2026-07-27
### Geändert
- **Versionsprüfung neu gebaut.** Clients mit 2.9 oder älter erscheinen erst nach einem Update wieder in der Liste.
- **Dieses Release enthält eine große interne Überarbeitung.** Alles, was du gespeichert hast, bleibt erhalten — Einstellungen, Loot-Historie, Officer-Notizen, Profile und ausstehende Trades.

### Behoben
- **`/kart add` funktioniert wieder mit per Shift-Klick eingefügten Items.**
- **Der Schließen-Button der Fenster ist größer und leichter zu treffen.**
- **Die Loot-Council-Fenster folgen jetzt der Schriftart-Einstellung.**

## [2.9.0] - 2026-07-25
### Hinzugefügt
- **Die gesamte Oberfläche folgt jetzt der Spracheinstellung** — inklusive Hauptfenster, Einstellungen und Tooltips.
- **Council-Mitglieder können jetzt selbst abstimmen.**
- **Der Loot-Verlauf ist jetzt seitenweise blätterbar.**
- **Das Council-Panel zeigt jetzt, was jeder Kandidat im Slot des gedroppten Items trägt** — inklusive Item-Level-Differenz.
- **Die Vantus-Rune wird jetzt am Zauber erkannt**, nicht am Buff-Namen.
- **Der Buff-Checker meldet jetzt auch veraltete Verzauberungen**, nicht nur fehlende — der Tooltip nennt den Slot mit der falschen. Nur die beste Handwerksqualität zählt.
- **Öl vom falschen Rang wird jetzt als falsch angezeigt** — die aktuellen Öle und Schleifsteine gelten als gut, Schamanen-Imbues werden nicht angemahnt.
- **`/kart add <Item-Link>` gibt ein Item zur Entscheidung an Loot Council zurück**, ohne echten Lootwurf. Ein bereits vergebenes Item wird dabei zuerst wieder freigegeben.
- **Klick auf einen Namen in der Trade-Erinnerung zielt auf die Person und öffnet den Handel** (mit Reichweitenprüfung).
- **Ein neues Erinnerungsfenster zeigt dir, wenn du noch den Lootmaster für ein gewonnenes Item traden musst**, mit demselben Ein-Klick-Handel.
- **Der Abstimmungs-Timer kann jetzt auf bis zu 3 Minuten eingestellt werden**, vorher 1 Minute.
- **Die Loot-Council-Fenster haben jetzt eine eigene Schriftgrößen-Einstellung**, die jetzt tatsächlich überall darin greift.
- **Trade-Abschluss wird jetzt direkt bestätigt**, nicht mehr nur aus deinen Taschen geraten.
- **Du wirst gewarnt, wenn du ein zugewiesenes Item an die falsche Person tradest.**
- **Du wirst gewarnt, bevor das 4-Stunden-Handelsfenster eines ausstehenden Trades abläuft** — der Timer läuft auch weiter, während du offline bist.
- **Wenn das gleiche Item doppelt gleichzeitig droppt, wird jedes jetzt mit "(1/2)"/"(2/2)" markiert**, damit du sie unterscheiden kannst.
- **Wähle, was mit einem Item in deinem Abstimmungsfenster passiert, sobald du abgestimmt hast**: normal groß bleiben (Standard), kleiner werden, oder komplett ausblenden. Neue Einstellung in den Loot-Council-Einstellungen.
- **`/kart showall`** holt ausgeblendete Items zurück.
- **`/kart owed`** öffnet die Liste der Items, die dir noch zustehen.
- **`/kart ench`** gibt die eigenen Enchant-IDs aus, um die Enchant-Prüfung aktuell zu halten.

### Geändert
- **Beide Waffen werden jetzt auf Öl geprüft** — wer mit zwei Waffen kämpft und nur eine geölt hat, wird gemeldet; eine leere Schildhand oder ein Schild wird nicht verlangt.
- **Handels-Erinnerungen und ausstehende Items überleben jetzt einen Reload oder Relog.**
- **Neuer "Session beenden"-Button im Council-Panel** beendet die Session und räumt alle offenen Items auf einmal ab. Nur für den Lootmaster.
- **Nur der eingetragene Lootmaster setzt die Loot-Council-Konfiguration des Raids** — ein Lead-Wechsel überschreibt sie nicht mehr. Zum Übergeben den Sync-Button nutzen.
- **Mounts, Pets, Spielzeuge, Housing-Items und Bind-on-Equip-Drops laufen nie über den Loot Council** — sie werden normal ausgewürfelt und Auto-Pass lässt sie in Ruhe.
- **Der Lootmaster steuert den kompletten Loot-Ablauf** — Session, Rolls und Vergaben. Der Raidleiter springt nur ein, solange kein Lootmaster gesetzt ist.
- **Interne Aufräumarbeiten:** toter Code entfernt, doppelte Logik zusammengeführt, Addon-Nachrichten-Verarbeitung restrukturiert.

### Behoben
- **Der Buff-Checker prüft jetzt die Verzauberung der Schildhand** — nur bei einer zweiten Waffe, Schilde und Zauberer-Schildhände nehmen keine.
- **Ein Buff, in dessen Namen bloß „Öl" vorkommt, löst keine falsche Öl-Warnung mehr aus.**
- **Items aus `/kart add` würfeln jetzt wie ein normaler Drop** — die Wurf-Spalte im Council blieb für sie leer.
- **Ein erneut hinzugefügtes Item wird jetzt auch dann freigegeben, wenn sein Council-Tab schon zu war** — also im Regelfall.
- **Eine Taste, die schon eine andere Raidlead-Aktion belegt, wird dieser jetzt weggenommen**, statt bei beiden zu stehen und nur bei einer zu wirken.
- **Namen und Nicknames mit Akzenten matchen jetzt** überall dort, wo Umlaute es schon taten.
- **Eine Einhandwaffe wird jetzt mit der Waffe des Kandidaten verglichen**, nicht mit dessen Schild oder Nebenhand.
- **Die Equipped-Spalte im Council vertraut einer kaputten Antwort** eines Mitspielers nicht mehr.
- **Eine geschlossene Trade- oder Owed-Erinnerung bleibt zu**, wenn ein Eintrag wegfällt — nur ein neuer Gewinn öffnet sie wieder.
- **„Kein Gewinner" entfernt das Item jetzt auch aus der Loot-Historie**, statt es dem widerrufenen Gewinner gutzuschreiben.
- **Ein Item mit zwei Sockeln meldet jetzt beide leeren Sockel**, nicht nur einen.
- **Das Starten einer Session erreicht jetzt den Raid, wenn der Lootmaster nicht Raidleiter ist** — auch für alle, die später dazukommen.
- **Ein Reload des Raidleiters mitten im Raid stoppt nicht mehr die Vote-Fenster des Raids**, während weiter Items gewonnen werden.
- **Die Gewinnerzeile wird sofort gold** — auch bei dem, der zugewiesen hat, nicht nur bei allen anderen.
- **Der Loot-Council-Einstellungstab geht beim Login nicht mehr kaputt.**
- **Der Lootmaster funktioniert wieder, wenn er nicht gleichzeitig Raidleiter ist** — Rolls gewinnen, `/kart add`, Handels-Erinnerungen, Council-Panel und Session beenden waren für ihn alle tot.
- **Der Lootmaster muss nicht mehr als Councilmitglied eingetragen sein**, um das Council-Panel zu bekommen und dass seine Vergaben zählen.
- **Ein Mount, dessen Daten noch nicht geladen sind, rutscht nicht mehr in den Loot Council.**
- **Das Council-Panel warnt in deiner eigenen Zeile nicht mehr, dass dir KART fehlt.**
- **Ein entschiedenes Item behält seinen Council-Tab auf jedem Client**, nicht nur bei dem, der zugewiesen hat.
- **Vote-Notizen und Officer-Notizen können keine Farbcodes oder Links mehr** in fremde Tooltips schmuggeln.
- **Das Council-Panel ruckelt nicht mehr, während Loot verteilt wird.**
- **Der "Dir steht noch zu"-Timer startet jetzt beim Drop**, nicht erst bei der Entscheidung des Councils.
- **Die Box mit den raid-weiten Einstellungen zeigt jetzt korrekt an, ob deine Einstellungen für den Raid gelten** — und wie sie dorthin kommen, wenn nicht.
- **Der Buff-Checker wirft keinen Fehler mehr bei einer kaputten Gear-Antwort** eines anderen Raiders.
- **Abbrechen im Akzentfarben-Picker stellt exakt die alte Farbe wieder her**, und eine Auswahl macht sie nicht mehr minimal dunkler.
- **Ausrüstungs-, Item-Level- und Ready-Check-Sync funktioniert wieder für alle auf dem eigenen Realm.**
- **Ein später Raid-Beitritt löscht nicht mehr die laufenden Loot-Würfe des ganzen Raids.**
- **Das Zurücknehmen eines Gewinners löscht die Handels-Erinnerung überall** — auch beim Zurücknehmenden selbst.
- **Der Loot-Zustand eines Raids wird nicht mehr** in den nächsten Raid oder die nächste Sitzung übernommen.
- **Der Loot-Verlauf-Button unten im Loot-Council-Tab ist wieder erreichbar.**
- **Das Minimieren des Council-Panels lässt es nicht mehr über den Bildschirm springen.**
- **Das Schließen eines Council-Tabs öffnet das Abstimmungsfenster nicht mehr erneut** und hinterlässt dort auch keinen hängenden Eintrag.
- **Die Buff-Checker-Vorschau verschwindet nicht mehr**, während du die Regler bedienst.
- **Die Fenster-Deckkraft setzt sich nicht mehr zurück**, wenn du das Fenster erneut öffnest.
- **Die Raidlead-Leiste erscheint nach einem Reload nicht mehr mitten im Kampf.**
- **Ein Profilwechsel wendet jetzt die Auto-Kampflog-Einstellungen an.**
- **Ein Bosslisten-Import dupliziert die Liste nicht mehr** — weder beim erneuten Import noch nach dem Login.
- **Zurücksetzen fragt jetzt nach**, bevor alle Einstellungen gelöscht werden.
- **Würfe gehen nicht mehr verloren** bei Spielern, die für das Item nicht berechtigt waren.
- **Ausrüstungs-, Item-Level- und Ready-Check-Daten können nicht mehr von Spielern außerhalb deiner Gruppe abgefragt oder gefälscht werden.**
- **Die Bossliste folgt jetzt dem aktiven Profil**, statt sich aufzustapeln, und ein Reset überlebt den Reload.
- **Leere Sockel nennen jetzt den richtigen Slot** — inklusive Handschuhe, Gürtel, Schmuck und Umhang.
- **Ein minimiertes Council-Panel bleibt minimiert**, während Stimmen eingehen.
- **Das Auto-Kampflog läuft nach einem Reload im Raid nicht mehr endlos weiter.**
- **Tastenbelegungen der Raidlead-Leiste werden freigegeben**, wenn die Leiste versteckt oder deaktiviert ist.
- **Außerhalb des Bildschirms gespeicherte Fenster kommen wieder zurück** — Buff-Check, Raidlead-Leiste und die Council-Fenster.
- **Der Loot-Verlauf wird nicht mehr an Spieler außerhalb deiner Gruppe gesendet.**
- **Officer-Notiz-Tooltips erscheinen wieder beim Überfahren.**
- **"Kein Gewinner" leert das Item jetzt beim gesamten Council**, nicht nur beim Klickenden.
- **Manuelle Rolls und Loot-Ergebnisse gehen nicht mehr gelegentlich verloren**, kurz nachdem jemand dem Raid beitritt.
- **Der Ausrüstungsvergleich bricht nicht mehr** bei sehr langen Item-Links.
- **Das Auto-Kampflog stoppt kein Log mehr, das du selbst gestartet hast.**
- **Lange Namen mit Umlauten werden im Buff-Check nicht mehr kaputt dargestellt.**
- **Entfernen-für-Boss riskiert nicht mehr, dich selbst aus dem Raid zu werfen.**
- **Eine volle Boss-Gruppe solo einzuladen wandelt jetzt in einen Raid um**, damit jede Einladung ankommt.
- **Droptimizer-Gewinne werden jetzt auch für Spieler auf mehrwortigen oder Apostroph-Realms angezeigt.**
- **Pull-Timer- und Buff-Check-Tastenbelegungen lösen jetzt zuverlässig aus.**
- **Massen-Invite und -Entfernen matchen Namen jetzt korrekt auf deutschen Realms.**
- **Keine Phantom-"Dir steht ein Item zu"-Erinnerung mehr**, wenn kein Lootmaster gesetzt ist.
- **Ein sechster eigener Vote-Button zeigt nicht mehr das Pass-Icon.**
- **Massen-Invites aus WoWUtils wandeln jetzt automatisch in einen Raid um**, damit Rosters über fünf Spieler auch voll werden.
- **Der Spieler-Filter im Loot-Verlauf fasst die Einträge einer Person jetzt zusammen** — auch über Nickname und Charakternamen hinweg.
- **Himmelszorn wird auf deutschen Clients jetzt korrekt erkannt.**
- **Das Abstimmungsfenster zeigt kein leeres Badge mehr**, wenn der Raidleiter die Vote-Buttons nach deiner Stimme kürzt.
- **Profile übernehmen jetzt neuere Standardeinstellungen** beim Laden.
- **Login-Fehler behoben** für Charaktere, die den Loot-Council-Schriftgrößen-Regler nie benutzt haben.
- **Haltbarkeitsdaten laden jetzt automatisch beim Ready-Check.**
- **Standardwerte-Reset setzt jetzt alles zurück**, inklusive Fensterpositionen und Tastenbelegung.
- **Zuweisungs-Menü und Ausrüstungs-Tooltip zeigen jetzt Nicknames**, wenn diese Einstellung aktiv ist, statt immer den Kurznamen.
- **Loot Council ist jetzt ausdrücklich Raid-only.**
- **Session-, Roll-Start- und History-Sync-Nachrichten werden jetzt auf ihren Absender geprüft.**
- **Auto-Trade für Cross-Realm-Gewinner repariert.**
- **Minimap-Icon-Position wird nach Profilwechsel wieder korrekt gespeichert.**
- **Raid-Marker-Buttons lösen nicht mehr doppelt pro Klick aus.**
- **Übriggebliebener Haken-Button beim Abhaken von Trade-Erinnerungen behoben.**
- **Der Loot-Verlauf dupliziert keine Einträge mehr zwischen deutschen und englischen Clients**, und die Schwierigkeit wird jetzt einheitlich auf Englisch gespeichert.
- **Fern- und Einhandwaffen zeigen jetzt das getragene Item** im Council-Panel.
- **Tastenbelegungen greifen jetzt auch nach einem Reload oder Login im Kampf.**
- **Die Einstellungssuche springt jetzt zur passenden Einstellung.**
- **Battle.net-Flüster-Einladungen laden jetzt tatsächlich ein.**
- **Auto-Umwandlung in einen Raid greift jetzt bei voller 5er-Gruppe.**
- **Manuelle Rolls nach einem `/reload` zeigen kein altes Item mehr.**
- **Die "du bekommst noch"-Erinnerung verschwindet jetzt bei Neuvergabe** und stapelt keine Duplikate mehr.
- **Ein Klick auf den Trade-Partner im Kampf meldet nicht mehr fälschlich "außer Reichweite".**
- **Beide Kopien eines doppelten Drops werden jetzt in den Trade gelegt.**
- **Spieler werden nur noch als veraltet markiert, wenn sie wirklich eine ältere Version haben.**
- **Die Verlaufssuche findet jetzt auch Items, deren Name mit einem Umlaut beginnt.**
- **Buff-Check-Meldungen listen jetzt die richtigen fehlenden Spieler.**
- **Raid-Assistenten können jetzt Spieler für einen Boss entfernen** — wie beim Einladen.
- **Uninvite trifft jetzt den richtigen Charakter**, wenn zwei über Realms hinweg denselben Namen haben.
- **Der Loot-Council-Schriftgrößen-Regler überlappt nicht mehr die Rolls-Checkbox.**
- **Ready-Check- und Buff-Check-Fenster schließen nicht mehr zu früh**, wenn sie kurz hintereinander erneut ausgelöst werden.
- **Die Tastenbelegungs-Aufnahme hängt nicht mehr am falschen Button** und läuft nach dem Schließen nicht weiter.
- **Droptimizer wählt jetzt den richtigen Upgrade-Track**, wenn ein Item auf mehreren simuliert wurde.
- **Officer-Notizen wachsen nicht mehr unbegrenzt.**
- **Gut-gesättigt-Foodbuffs werden jetzt auf deutschen Clients erkannt.**
- **Spielernamen mit Umlauten werden jetzt korrekt aufgelöst** — für Council, Lootmaster und Auto-Promote.
- **Loot, den ein spät beigetretenes Council-Mitglied gewinnt, wird nicht mehr als "???" protokolliert.**
- **Der Council-Straw-Poll-Balken füllt sich jetzt korrekt.**
- **Einstellungs-Regler zeigen ihren Wert jetzt sofort** statt leer zu bleiben, bis man sie einmal zieht.
- **Das Laden eines Profils übernimmt jetzt dessen gespeicherte Sprache.**
- **Der Loot Council verwechselt keine zwei Spieler mehr, die sich einen Charakternamen über verbundene Realms teilen.** Votes, Council-Mitgliedschaft, Item-Zuweisungen und Officer-Notizen werden jetzt pro Spieler verfolgt.
- **Der Loot-Council-Sitzungsstatus (An/Aus, Mindestqualität, Stimm-Labels, Opt-in-Würfe) synchronisiert sich jetzt sofort beim Beitreten/`/reload`**, statt erst bei der nächsten Rosteränderung.
- **Das automatische Need/Greed des Lootmasters beansprucht jetzt auch reine Transmog-Würfe**, statt nichts zu tun.
- **Rechtsklick-Zuweisung und Loot-Historie verwechseln Items nicht mehr zwischen Bossen**, und eine Neuzuteilung ersetzt den alten Historieneintrag statt ihn zu duplizieren.
- **Frisch gedroppte Beute bleibt nicht mehr dauerhaft bei "???" hängen** im Abstimmungsfenster oder Council-Panel.
- **Die Auto-Trade-Erinnerung funktioniert jetzt korrekt, wenn Raidleiter und Lootmaster unterschiedliche Personen sind**, und löscht einen Eintrag erst, wenn der Trade wirklich abgeschlossen ist.
- **Loot-Council- und Auto-Trade-Fenster lassen sich mit `/kart lc` und `/kart trade`** nach dem Schließen wieder öffnen.
- **Council-Panel und Loot-Historie lassen sich jetzt an der Titelleiste ziehen**, nicht nur am Fensterkörper.
- **Spielzeuge, Begleiter, Mounts und Wohnungsdeko werden nicht mehr von der Mindestqualitäts-Regel herausgefiltert.**
- **Der Schließen-Button im Abstimmungsfenster ist größer und leichter zu treffen.**
- **Der KART-Status eines Spielers zeigt nach dem Beitreten nicht mehr fälschlich "nicht installiert" an.**

## [2.4.0] - 2026-07-19
### Added
- **Einstellungen-Suche:** ein neuer Suche-Button im Hauptfenster — Einstellungsnamen eintippen und direkt dorthin springen, mit passendem Tab und kurzem Highlight.

## [2.3.0] - 2026-07-19
### Added
- **Raidleiter-Settings-Sync:** sende deine Loot-Council-Raid-Einstellungen an einen bestimmten Spieler per Namen im Loot-Council-Tab — er sieht ein Bestätigungsfenster und muss zustimmen, bevor sich etwas ändert.

## [2.2.0] - 2026-07-19
### Added
- **Profile-Einstellungen:** aktuelle Einstellungen als benanntes Profil speichern, zwischen gespeicherten Profilen wechseln und sie löschen — über eine neue Card im Einstellungen-Tab.

## [2.1.0] - 2026-07-19
### Added
- **Tastenbelegung für Bereitschaftscheck, Weltmarkierungen löschen, Pull-Timer und Buff-Checker ein/aus:** einstellbar in einer neuen Tastenbelegung-Card im Raidlead-Tab.

## [2.0.0] - 2026-07-18
### Geändert
- **Hauptfenster mit neuem Artwork-Hintergrund gestaltet** — Sidebar, Titel und Schließen-Button sind Teil des neuen Looks.
- **Freies Fenster-Resizing ersetzt durch einen „Fenster-Skalierung"-Regler in den Einstellungen.**
- **Hauptfenster ist standardmäßig größer und jeder Tab gruppiert seine Einstellungen in Cards.**
- **Einstellungs-Beschriftungen nutzen jetzt denselben weißen Textstil wie das Menü.**
- **Eingabefelder an die Card-Optik angepasst** — abgerundet, mit Rand in Akzentfarbe während der Eingabe.
- **Buff-Checker-Fenster mit eigenem Artwork-Hintergrund gestaltet** — Akzentlinie im Kopf, passende Schließen- und Resize-Ecken.
- **Loot-Verlauf, Vote-Fenster, Council-Panel und alle kleineren Dialoge im neuen Artwork-Look.**

### Entfernt
- **Einstellungen für Hintergrundfarbe und Titel-Schriftgröße.**

## [1.19.0] - 2026-07-18
### Hinzugefügt
- **Auto-Combat-Log:** Neue Karte im Automation-Tab startet/stoppt das Combat-Logging automatisch für ausgewählten Content (Raid-Schwierigkeiten, Mythisch+ ab Mindest-Keystufe, Dungeons, Tiefen).

### Geändert
- **Settings-Tab ans Ende der Sidebar verschoben.**

### Behoben
- **"NSRT-Nicknames anzeigen"- und "Kompaktes Vote-Fenster"-Schalter stehen nach einem Reload nicht mehr auf aus.**

## [1.18.1] - 2026-07-18
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
