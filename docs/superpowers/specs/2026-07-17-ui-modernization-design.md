# UI-Modernisierung: einheitliches, modernes Theme für alle KART-Fenster

**Datum:** 2026-07-17
**Status:** Zur Review

## Problem

Das Interface ist reines WoW-Frame-API (`CreateFrame`/`BackdropTemplate`, keine echte
CSS-fähige UI-Lib). Es funktioniert und ist bereits dunkel gehalten, wirkt aber flach und
technisch datiert:

- Alle Flächen sind scharfkantige Rechtecke aus `Interface\Buttons\WHITE8X8` mit 1px-Rand.
- Buttons/Checkboxen/Slider wechseln bei Hover hart die Farbe statt sanft überzublenden.
- Checkboxen sind Quadrate mit Häkchen-Textur, Slider-Thumbs sind Klötze.
- Einstellungsgruppen liegen frei auf dem Panel-Hintergrund, keine visuelle Gruppierung.
- Aktiver Tab unterscheidet sich nur durch Textfarbe vom Rest der Sidebar.
- Von den 121 Stellen im Code, die eigenes `SetBackdrop`/Styling machen, laufen nur ein
  Bruchteil über die gemeinsamen Fabrikfunktionen in `Utils.lua` — der Rest (v. a.
  `LootCouncil.lua` mit 41 Stellen) baut sich eigene, leicht inkonsistente Bausteine.

Ziel: ein spürbar moderneres, in sich konsistentes Erscheinungsbild über alle Fenster hinweg,
ohne neue Grafik-Assets (kein Bildgenerierungs-Tool verfügbar) und ohne das bestehende
Farb-Anpassungssystem (Akzent-/Hintergrundfarbe per Color-Picker) zu verlieren.

## Entscheidung

Ein zentrales Theme-Set aus wiederverwendbaren Primitiven in `Utils.lua`, das alle
verbrauchenden Dateien (`MainFrame.lua`, `BuffChecker.lua`, `LootCouncil.lua`,
`LootHistory.lua`, `RaidleadBar.lua`, `Invite.lua`, `Core.lua`, `Droptimizer.lua`) nutzen,
statt eigene `SetBackdrop`-Aufrufe zu bauen. Stilrichtung: ElvUI-artig flach/minimalistisch,
aber mit dezenter Eckenrundung über WoW-Textur-Masken (`SetMask`) für einen weicheren,
moderneren Eindruck als klassisches ElvUI.

Verworfen:
- **Nur Fabrikfunktionen aufhübschen, Ad-hoc-Stellen unangetastet lassen** — schneller, aber
  neue Buttons sähen neben alten Boxen (z. B. im Loot-Council-Panel) inkonsistent aus. Der
  Nutzer hat explizit "alles inkl. Spezialfenster" gewählt, das widerspricht dieser Abkürzung.
- **Custom-Icon-Set** — abgelehnt, da kein Bildgenerierungs-Tool zur Verfügung steht und WoW
  BLP/TGA-Assets nicht ohne externe Tools erzeugt werden können.
- **Feste Palette ohne Color-Picker** — abgelehnt, Nutzer wollen weiterhin z. B. Gilden-/
  Klassenfarben als Akzent setzen können.

## Design-Tokens (neu in Utils.lua)

Ein kleiner `KART.Theme`-Tabelle als einzige Quelle für Maße/Farb-Ableitungen, damit
`UpdateStyles()` (bereits vorhanden, reagiert auf Farb-/Font-Änderungen) diese zentral
weiterreichen kann:

- `KART.Theme.CORNER_RADIUS_LG = 6` (Panels/Cards/Hauptfenster)
- `KART.Theme.CORNER_RADIUS_SM = 3` (Buttons, Checkboxen, Slider-Thumb)
- `KART.Theme.CORNER_RADIUS_MIN_SIZE = 16` — Elemente kleiner als das (Höhe oder Breite)
  bekommen keine Rundung (Maske würde bei z. B. 12px-Elementen visuell kaputt aussehen)
- Statusfarben fix (nicht user-anpassbar): `SUCCESS = {0.35, 0.75, 0.35}`,
  `WARNING = {0.9, 0.7, 0.2}`, `DANGER = {0.85, 0.3, 0.3}` — für Trade-Reminder,
  KART-Status-Warnung, Vote-Ergebnisse etc.
- Zustands-Ableitung aus der bestehenden Akzent-/Hintergrundfarbe:
  `KART.Theme.Lighten(r,g,b, amount)` / `KART.Theme.Darken(r,g,b, amount)` — Hover = Akzent
  `Lighten(0.08)`, Pressed = Akzent `Darken(0.08)`, Disabled = Hintergrund `Lighten(0.03)` mit
  50 % Alpha. Ersetzt die aktuellen hart kodierten Hover-Farben (z. B. `0.2,0.2,0.2` in
  `CreateModernButton`).

## Rundungs-Mechanik

Neuer Helper `KART.ApplyRoundedMask(frame, radius)`:
- Erzeugt/holt eine generische quadratische Rundungs-Maskentextur (eine gemeinsame, per Code
  generierte `MaskTexture`, keine externe Bilddatei nötig — WoW's `CreateMaskTexture` mit einer
  bestehenden Blizzard-Rundungs-Maske, z. B. `Interface\\Masks\\CircleMaskScalable` auf die
  Ecken zugeschnitten, oder falls das visuell nicht passt: 4 kleine Eck-Texturen aus
  `WHITE8X8` mit Alpha-Gradient als Fallback).
- Wendet die Maske auf Backdrop-Textur und ggf. Gradient-Overlay an.
- Fällt automatisch auf ungerundete Ecken zurück, wenn `frame:GetWidth()` oder `GetHeight()`
  unter `CORNER_RADIUS_MIN_SIZE` liegt (`OnSizeChanged`-Hook prüft das einmalig beim ersten
  Layout).
- Technisches Risiko: `SetMask`-API-Details variieren leicht zwischen Client-Versionen; analog
  zu `KART.SetGradientOverlayColor` wird der Aufruf in `pcall` gekapselt, damit ein API-Mismatch
  nur die Rundung wegfallen lässt statt die UI zu brechen.

## Primitive (Utils.lua)

- **`CreateModernButton`** (überarbeitet): abgerundet, Hover/Pressed über
  `KART.Theme.Lighten/Darken` statt Festwerten, sanfter Farb-Fade via kurze Alpha-/Color-
  Animation (gleiches Animation-System wie `AddShowFade`) statt Instant-Wechsel.
- **`CreateSettingsCheckbox`** (überarbeitet): Toggle-Switch-Optik — Pillenform (Breite 34,
  Höhe 16, volle Rundung da unter `CORNER_RADIUS_MIN_SIZE`, also eigene volle Pill-Maske statt
  Eckenradius), ein runder Punkt-Texture wandert per kurzer Positions-Animation zwischen
  Aus-/An-Zustand.
- **`CreateSettingsSlider`** (überarbeitet): dünnere Schiene (Höhe 4 statt 14), runder Thumb
  (12px Kreis-Maske), Glow-Textur (Akzentfarbe, niedrige Alpha) die bei `OnEnter`/`OnMouseDown`
  eingeblendet wird.
- **`CreateCard`** (neu): abgerundetes Panel mit zweiter, 2px versetzter, dunklerer
  Hintergrund-Textur dahinter als einfacher "Schatten" (kein echtes Blur möglich, aber
  ausreichender Tiefeneffekt). Nimmt optional einen Titel-String für eine dünne
  Karten-Kopfzeile.
- **`CreateTabButton`** (neu, ersetzt Sidebar-Button-Erzeugung in `MainFrame.lua`): aktiver Tab
  bekommt 3px Akzent-Leiste links (eigene Textur) + Hintergrund `Theme.Lighten` statt nur
  Textfarbwechsel.

Alle fünf Funktionen sind bereits vorhandene bzw. neue globale `KART.*`-Funktionen — keine neue
Datei, keine neue Abhängigkeit.

## Betroffene Fenster / Umsetzungsreihenfolge

Reihenfolge so gewählt, dass nach jedem Schritt ein lauffähiger Zustand existiert (kein Big-Bang-Commit):

1. `Utils.lua` — Theme-Tokens, Rundungs-Helper, fünf Primitive; isoliert testbar, da
   `CreateModernButton` etc. bereits an vielen Stellen aufgerufen werden und sofort sichtbar
   sind, sobald `/kart` geöffnet wird.
2. `MainFrame.lua` — Sidebar/Tabs auf `CreateTabButton`, Settings-Panels (Raidlead, BuffCheck,
   Automation, Settings) profitieren automatisch von den überarbeiteten Primitiven, zusätzlich
   Card-Gruppierung für zusammengehörige Einstellungsblöcke.
3. `BuffChecker.lua` — Fenster-Rahmen + Zeilen-Layout auf Card/Rundung, Status-Icons auf feste
   Statusfarben.
4. `LootHistory.lua` — Tabellen-Header/-Zeilen, Filter-Controls.
5. `RaidleadBar.lua`, `Invite.lua`, `Core.lua` (Ready-Check-Popup), `Droptimizer.lua` — kleinere
   Fenster/Controls, gleiche Primitive.
6. `LootCouncil.lua` (größter Block, 41 Ad-hoc-Stellen; Vote-Fenster und Council-Panel wurden erst
   kürzlich in einem eigenen Redesign überarbeitet — siehe
   `docs/superpowers/plans/2026-07-15-vote-window-layouts.md` — deshalb bewusst ans Ende gestellt,
   damit dieses Redesign nicht sofort wieder angefasst wird) — Council-Panel, Vote-Listen-Karten
   (Stil "Geräumig"/"Kompakt" bleiben erhalten, nur Rundung/Farben angeglichen), Tab-Leiste links,
   Raid-Wide-Settings-Box.

Jede Datei wird einzeln umgestellt und die bestehenden Test-Mode-Buttons (Loot Council hat
bereits welche) genutzt, um ohne echten Raid zu verifizieren, dass nichts kaputt geht.

## Nicht-Ziele

- Keine neue Grafik-Assets/Icons (siehe oben).
- Keine Änderung an Funktionslogik — reines Styling/Layout.
- Kein Wechsel des UI-Frameworks (bleibt natives WoW-Frame-API, kein Ace3-GUI o. ä.).
- Bestehende Nutzer-Einstellungen (Fontgröße, Farben, Fensterpositionen) bleiben unverändert
  kompatibel — `KART.Defaults`/`KART_Settings`-Schema wird nicht erweitert, nur wie bestehende
  Werte visuell verarbeitet werden ändert sich.
