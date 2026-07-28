# Irrelevante Vote-Items ausblenden und automatisch beantworten — Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zwei persönliche Schalter im KART-Vote-Fenster, die Items, die die eigene Klasse nicht anlegen kann, ausblenden bzw. automatisch mit Transmog beantworten, wenn das Aussehen noch fehlt.

**Architecture:** Die gesamte Entscheidungslogik zieht in eine neue Datei `LootCouncilRelevance.lua`. Ihr Kern ist eine reine Funktion ohne WoW-Zugriff, die aus vier Fakten die Antwort ableitet — die ist kopflos testbar. Drumherum liegen die Fakten-Beschaffer, die Blizzards Rolldaten und `C_TransmogCollection` befragen. Aufgerufen wird das an genau einer Stelle: oben in `Vote.RefreshVoteListRows`, bevor gerendert wird.

**Tech Stack:** Lua 5.1 / LuaJIT, WoW Retail Addon API (Midnight, 12.x), `luacheck`, kopflose Testsuite unter `tests/`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-28-loot-council-irrelevant-items-design.md` — bei Widerspruch gilt der Spec.
- **Sprache:** Code-Kommentare, Commit-Messages und `CHANGELOG.md`/`README.md` auf **Englisch**. `Locales/deDE.lua`-Werte und `CHANGELOG-de.md` auf Deutsch. Siehe `CLAUDE.md`.
- **Changelog:** ein Eintrag = **eine Zeile** (max. zwei bei großen Änderungen), fetter Lead plus kurze Wirkungsaussage. Keine Ursachen, keine Implementierungsdetails.
- **Blizzards Loot-Roll bleibt unangetastet.** `LC.OnStartLootRoll`, `ForceWinRoll` und `lcAutoPass` werden von diesem Plan nicht verändert.
- **Beide neuen Einstellungen sind persönlich** und werden nie über `LC_CONFIG` synchronisiert.
- **Beide Defaults sind `false`.** Ohne Zutun des Nutzers ändert das Update nichts.
- **Unbekannt zählt nie als irrelevant.** Wo eine Fakteneinschätzung `nil` ist, wird das Item normal angezeigt.
- **Gates nach jeder Aufgabe:** `luacheck .` und `luajit tests/run.lua` müssen grün sein, ausgeführt im Repository-Root.

---

## Dateiübersicht

| Datei | Rolle |
|---|---|
| `LootCouncilRelevance.lua` | **neu.** Reine Entscheidungsfunktion + Fakten-Beschaffer. Kein UI-Code. |
| `tests/test_lc_relevance.lua` | **neu.** Kopflose Tests der reinen Entscheidungsfunktion. |
| `tests/run.lua` | Registriert die neue Testdatei. |
| `KeineAhnungRaidTools.toc` | Lädt die neue Datei vor `LootCouncilVote.lua`. |
| `LootCouncil.lua` | Fester Transmog-Button in `GetButtonConfig`, eigene Farbe und Icon, Index-Helfer. |
| `LootCouncilVote.lua` | Aufrufpunkt in `RefreshVoteListRows`, zweiter Ausblendgrund in `GetVisibleRolls`, Entsperrung automatischer Stimmen in `CastVote`. |
| `LootCouncilPanel.lua` | Reicht das Button-Def an `GetVoteIconTexture` weiter. |
| `LootCouncilSettings.lua` | Zwei neue Checkboxen im persönlichen Einstellungs-Card. |
| `Utils.lua` | Zwei neue Keys in `KART.Defaults`. |
| `Locales/enUS.lua`, `Locales/deDE.lua` | Neue Strings. |
| `CHANGELOG.md`, `CHANGELOG-de.md` | Release-Einträge. |

**Reihenfolge-Begründung:** Der Transmog-Button muss existieren, bevor irgendetwas automatisch auf ihn abstimmen kann (Task 1). Die Einstellungen müssen existieren, bevor die Logik sie liest (Task 2). Die reine Logik wird vor ihrer Verdrahtung getestet (Task 3 vor 4).

---

## Task 1: Fester Transmog-Button als letzte Antwort

`LC.GetButtonConfig` ist die einzige Quelle für die Antwort-Buttons — Vote-Fenster, Council-Panel, Trade-Erinnerung und Historie lesen alle daraus. Ein dort angehängter Eintrag erscheint automatisch überall.

**Files:**
- Modify: `LootCouncil.lua:145-153` (Farben), `LootCouncil.lua:161-173` (Icons), `LootCouncil.lua:201-228` (`GetButtonConfig`)
- Modify: `LootCouncilVote.lua:577`, `LootCouncilVote.lua:838`, `LootCouncilPanel.lua:1379` (Icon-Aufrufe)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Produces:
  - `LC.GetButtonConfig() -> table` — Liste von `{label=string, r=number, g=number, b=number, transmog=boolean|nil, icon=string|nil}`. Der letzte Eintrag hat immer `transmog = true`.
  - `LC.GetTransmogButtonIndex() -> number` — Index des Transmog-Eintrags.
  - `LC.GetPassButtonIndex() -> number|nil` — Index des letzten frei konfigurierten Labels, `nil` wenn es keines gibt.
  - `LC.GetVoteIconTexture(index, def) -> string` — `def.icon` hat Vorrang vor der positionsbasierten Liste.

- [ ] **Step 1: Neue Locale-Strings anlegen**

In `Locales/enUS.lua`, direkt unter `LC_DEFAULT_BUTTONS` (Zeile 229):

```lua
    LC_BUTTON_TRANSMOG     = "Transmog",
```

In `Locales/deDE.lua` an derselben Stelle denselben Wert (der Begriff ist im deutschen Client identisch):

```lua
    LC_BUTTON_TRANSMOG     = "Transmog",
```

- [ ] **Step 2: Eigene Farbe und Icon für den Transmog-Eintrag definieren**

In `LootCouncil.lua`, direkt nach dem `BUTTON_COLORS`-Block (nach Zeile 153):

```lua
-- The fixed Transmog response is appended by GetButtonConfig as the LAST entry, so its position
-- shifts with however many labels the raid leader configured. Colour and icon therefore travel
-- with the entry itself instead of being looked up by index — otherwise the same response would
-- render yellow in a raid with three labels and purple in one with five.
local TRANSMOG_COLOR = {r = 0.85, g = 0.5, b = 1.0}
local TRANSMOG_ICON  = "Interface\\MINIMAP\\TRACKING\\Transmogrifier"
```

- [ ] **Step 3: `GetVoteIconTexture` um das Def erweitern**

`LootCouncil.lua:168-173` ersetzen durch:

```lua
function LC.GetVoteIconTexture(index, def)
    -- An entry that carries its own icon (the fixed Transmog response) wins: its position is not
    -- fixed, so the position-keyed list below cannot describe it.
    if def and def.icon then return def.icon end
    -- Out-of-range index (labels allow up to 5 configurable buttons plus Transmog, this list holds
    -- the 5 default semantics) falls back to the neutral catch-all icon (4), NOT Pass (the last
    -- entry, 5) — otherwise a configured 5th button would render with the green Pass chip.
    return VOTE_ICON_TEXTURES[index] or VOTE_ICON_TEXTURES[4]
end
```

- [ ] **Step 4: Die drei Icon-Aufrufer das Def mitgeben lassen**

`LootCouncilVote.lua:577` und `LootCouncilVote.lua:838` — in beiden Fällen steht `def` bereits als lokale Variable der Schleife zur Verfügung:

```lua
                btn.iconTex:SetTexture(LC.GetVoteIconTexture(bi, def))
```

`LootCouncilPanel.lua:1379` — `m.voteDef` wird zwei Zeilen darüber bereits benutzt:

```lua
            row.voteIcon:SetTexture(LC.GetVoteIconTexture(tonumber(m.voteIdx), m.voteDef))
```

- [ ] **Step 5: `GetButtonConfig` auf 5 konfigurierbare Labels kappen und Transmog anhängen**

`LootCouncil.lua:208-227` (vom `local parts = ...` bis vor das `return result`) ersetzen durch:

```lua
    local parts = KAUtil.SplitString(raw, ";")
    local result = {}
    for _, label in ipairs(parts) do
        local trimmed = KAUtil.TrimString(label)
        -- 5, not 6: the sixth slot is now permanently the fixed Transmog response appended below.
        if trimmed ~= "" and #result < 5 then
            -- Color by the COMPACTED position (#result+1), not the raw split index, so it matches the
            -- vote icon (chosen by the returned button's index). A whitespace-only label between real
            -- ones is dropped from result but would otherwise advance the split index, desyncing the
            -- two.
            local col = BUTTON_COLORS[#result + 1] or BUTTON_COLORS[6]
            table.insert(result, {label = trimmed, r = col.r, g = col.g, b = col.b})
        end
    end
    if #result == 0 then
        for i, label in ipairs(KAUtil.SplitString(KART.L.LC_DEFAULT_BUTTONS, ";")) do
            if i <= 5 then
                local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
                table.insert(result, {label = label, r = col.r, g = col.g, b = col.b})
            end
        end
    end
    -- The Transmog response is not leader-configurable: the auto-transmog setting votes with it, and
    -- a renamed or missing button would make that setting silently vote something else. Always last,
    -- never the raid config's business.
    table.insert(result, {
        label    = KART.L.LC_BUTTON_TRANSMOG,
        r        = TRANSMOG_COLOR.r, g = TRANSMOG_COLOR.g, b = TRANSMOG_COLOR.b,
        transmog = true,
        icon     = TRANSMOG_ICON,
    })
    return result
```

- [ ] **Step 6: Index-Helfer ergänzen**

In `LootCouncil.lua` direkt hinter `GetButtonConfig` einfügen:

```lua
-- Index of the fixed Transmog response. Always the last entry (see GetButtonConfig), so this is a
-- length lookup rather than a search — but named, because callers should not encode "last" themselves.
function LC.GetTransmogButtonIndex()
    return #LC.GetButtonConfig()
end

-- Index of the last FREELY CONFIGURED label, which the hide-irrelevant setting votes with. That is
-- "Pass" in the default configuration and in every configuration this guild has used. A raid leader
-- who renames the last label to something that is not a pass makes that setting vote it instead —
-- documented in the setting's own tooltip, deliberately not guessed at from the label text.
-- nil when the config holds nothing but the appended Transmog entry, which cannot happen through the
-- settings UI (an empty field falls back to the defaults) but is cheap to be honest about.
function LC.GetPassButtonIndex()
    local n = #LC.GetButtonConfig() - 1
    if n < 1 then return nil end
    return n
end
```

- [ ] **Step 7: Statische Gates**

```bash
luacheck .
luajit tests/run.lua
```

Erwartet: beide grün, unveränderte Assertion-Zahl.

- [ ] **Step 8: Im Spiel prüfen**

WoW neu starten (neue Datei-Inhalte in `LootCouncil.lua` reichen zwar ein `/reload`, aber Task 4 fügt später eine neue Datei hinzu — siehe `kart-wow-testing`). Dann `/kart test`:

- Jede Vote-Karte zeigt einen zusätzlichen letzten Button „Transmog" in Violett.
- Sein Icon rendert als Bild, **nicht** als grüner oder schwarzer Platzhalter. Rendert es falsch, ist `TRANSMOG_ICON` der falsche Pfad — dann auf `"Interface\\Icons\\INV_Misc_Cape_18"` ausweichen und den Kommentar entsprechend anpassen.
- Ein Klick darauf trägt „Transmog" als eigene Stimme ein.
- Trägt man im Raid-weiten Feld sechs Labels ein, erscheinen nur die ersten fünf plus Transmog.

- [ ] **Step 9: Commit**

```bash
git add LootCouncil.lua LootCouncilVote.lua LootCouncilPanel.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add a fixed Transmog vote response as the last button (#11)"
```

---

## Task 2: Die zwei persönlichen Einstellungen

**Files:**
- Modify: `Utils.lua:46-66` (Defaults)
- Modify: `LootCouncilSettings.lua:142` (Card-Höhe), nach `LootCouncilSettings.lua:256` (neue Checkboxen)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Consumes: nichts aus Task 1.
- Produces: `KART_Settings.lcHideIrrelevant` (boolean), `KART_Settings.lcAutoTransmogVote` (boolean).

**Platzierung, abweichend vom Spec-Wortlaut:** Der Spec sagt „direkt unter Auto-Pass". Die Slots dazwischen sind belegt und einer davon (`-75`) gehört Droptimizer in einer anderen Datei; ein Einschub würde sechs Positionswerte und fünf erklärende Kommentare verschieben. Die beiden Checkboxen kommen daher ans **Ende desselben persönlichen Cards**, unter die Skalierungs-Slider. Persönlich statt raid-weit — der eigentliche Punkt — bleibt gewahrt.

- [ ] **Step 1: Defaults ergänzen**

In `Utils.lua`, direkt hinter `lcVotedItemDisplay = "full",` (Zeile 58):

```lua
    lcHideIrrelevant = false,
    lcAutoTransmogVote = false,
```

- [ ] **Step 2: Locale-Strings ergänzen**

In `Locales/enUS.lua`, hinter `LC_DESC_AUTOPASS` (Zeile 203):

```lua
    LC_SET_HIDE_IRRELEVANT  = "Hide items my class cannot equip",
    LC_DESC_HIDE_IRRELEVANT = "Items your class cannot wear or wield disappear from your vote window, and your last configured response — \"Pass\" by default — is sent for them automatically, so the council sees you as done instead of waiting out the timer. Bring a hidden item back with /kart showall; an automatic vote can still be changed afterwards. If your raid leader renames the last button to something that is not a pass, this setting votes that instead.",
    LC_SET_AUTO_TRANSMOG    = "Vote Transmog on items I cannot equip but whose appearance I still need",
    LC_DESC_AUTO_TRANSMOG   = "Appearances can be collected across armor types, so a drop you cannot wear may still be worth having. When an item is not equippable by your class and its appearance is missing from your collection, KART votes Transmog for you instead of hiding it. Takes precedence over hiding. Rings, necks and trinkets have no appearance and are never affected.",
```

In `Locales/deDE.lua` an derselben Stelle:

```lua
    LC_SET_HIDE_IRRELEVANT  = "Items ausblenden, die meine Klasse nicht anlegen kann",
    LC_DESC_HIDE_IRRELEVANT = "Items, die deine Klasse weder tragen noch führen kann, verschwinden aus deinem Vote-Fenster, und deine letzte konfigurierte Antwort — standardmäßig \"Pass\" — wird automatisch abgeschickt. Der Council sieht dich damit sofort als erledigt statt bis zum Ablauf der Zeit zu warten. Ausgeblendete Items holst du mit /kart showall zurück; eine automatische Stimme lässt sich danach noch ändern. Benennt dein Raidleiter den letzten Button in etwas um, das kein Pass ist, stimmt diese Einstellung damit ab.",
    LC_SET_AUTO_TRANSMOG    = "Transmog wählen bei Items, die ich nicht anlegen kann, deren Aussehen mir aber fehlt",
    LC_DESC_AUTO_TRANSMOG   = "Erscheinungen sind über Rüstungstypen hinweg sammelbar — ein Drop, den du nicht tragen kannst, kann sich also trotzdem lohnen. Kann deine Klasse ein Item nicht anlegen und fehlt dir sein Aussehen noch, stimmt KART für dich mit Transmog ab, statt das Item auszublenden. Hat Vorrang vor dem Ausblenden. Ringe, Hälse und Schmuckstücke haben kein Aussehen und sind nie betroffen.",
```

- [ ] **Step 3: Card-Höhe anheben**

`LootCouncilSettings.lua:142`:

```lua
    prefsCard:SetSize(500, 425) -- 215 -> 260 for the font-size slider, -> 350 for the scale/layer pair, -> 425 for the two irrelevant-item switches
```

- [ ] **Step 4: Die beiden Checkboxen anlegen**

In `LootCouncilSettings.lua` direkt hinter dem `SldStrata:HookScript("OnShow", UpdateLCStrataText)`-Block (nach Zeile 256) einfügen:

```lua
    -- Personal preferences, same reasoning as CbAutoPass above — which items YOUR OWN vote window
    -- bothers you with is your call, never the raid leader's. Slots -350/-380: the next free steps
    -- below SldStrata, inside this card (height bumped 350 -> 425 above to fit both).
    KART.LC.CbHideIrrelevant = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCHideIrrelevant", label = L.LC_SET_HIDE_IRRELEVANT,
        store = SettingsStore, key = "lcHideIrrelevant", y = -350,
        onChanged = function() LC.Vote.RefreshVoteListRowsIfShown() end,
        tooltip = L.LC_DESC_HIDE_IRRELEVANT,
    })

    KART.LC.CbAutoTransmogVote = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCAutoTransmogVote", label = L.LC_SET_AUTO_TRANSMOG,
        store = SettingsStore, key = "lcAutoTransmogVote", y = -380,
        onChanged = function() LC.Vote.RefreshVoteListRowsIfShown() end,
        tooltip = L.LC_DESC_AUTO_TRANSMOG,
    })
```

- [ ] **Step 5: Statische Gates**

```bash
luacheck .
luajit tests/run.lua
```

Erwartet: beide grün.

- [ ] **Step 6: Im Spiel prüfen**

`/reload`, dann Einstellungen → Loot Council:

- Beide Checkboxen stehen unter den Slidern, beide **aus**.
- Der Raid-weite (bernsteinfarbene) Kasten darunter überlappt nicht — er ist an die Card-Unterkante gehängt und rutscht mit.
- Tooltips erscheinen und sind vollständig lesbar.
- Ein Haken überlebt `/reload`.

- [ ] **Step 7: Commit**

```bash
git add Utils.lua LootCouncilSettings.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add personal switches for hiding and auto-answering irrelevant items (#11)"
```

---

## Task 3: Reine Entscheidungsfunktion mit kopflosen Tests

Nur dieser Teil ist ohne laufendes WoW testbar, deshalb steckt die gesamte Fallunterscheidung hier drin und die Fakten kommen als einfache Tabelle herein. Die Testdatei zieht die Funktion per Textextraktion aus der Quelle und kompiliert sie einzeln — dasselbe Verfahren wie `tests/test_lc_votewire.lua`, damit der Test nicht an einer Kopie vorbeiläuft, die später auseinanderdriftet.

**Files:**
- Create: `LootCouncilRelevance.lua`
- Create: `tests/test_lc_relevance.lua`
- Modify: `tests/run.lua:54`
- Modify: `KeineAhnungRaidTools.toc:30`

**Interfaces:**
- Consumes: nichts.
- Produces:
  - `local function DecideAutoResponse(facts) -> "transmog" | "pass" | nil` — rein, extrahierbar.
    `facts = {irrelevant = boolean|nil, needsAppearance = boolean|nil, hideIrrelevant = boolean, autoTransmog = boolean}`.
    `nil` bei `irrelevant`/`needsAppearance` heißt „nicht ermittelbar".
  - `LC.Relevance.DecideAutoResponse` — dieselbe Funktion, für Task 4 nach außen gereicht.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

`tests/test_lc_relevance.lua` neu anlegen:

```lua
-- The auto-response decision for an item in the vote window.
--
-- The offline harness loads libraries, not addon files -- LootCouncilRelevance.lua needs the addon's
-- vararg table to load at all. So this lifts DecideAutoResponse out of the source and compiles just
-- that function, the same way test_lc_votewire.lua does with ParseVotePayload. Testing a copy pasted
-- in here would pass forever after the real one changed, which is worse than no test.
--
-- What makes this worth testing: "not determinable" is a third state next to true and false, and it
-- must behave like "relevant" -- never like "irrelevant". Collapsing nil into false would silently
-- pass away items the player was eligible for.

local source = assert(io.open("LootCouncilRelevance.lua", "r"))
local text = source:read("*a")
source:close()

local fn = text:match("\nlocal function DecideAutoResponse%(facts%).-\nend\n")
T.truthy(fn, "DecideAutoResponse was found in LootCouncilRelevance.lua")

local chunk = assert(loadstring(fn .. "\nreturn DecideAutoResponse"))
local DecideAutoResponse = chunk()
T.eq(type(DecideAutoResponse), "function", "DecideAutoResponse compiles standalone")

local function check(label, facts, expected)
    T.eq(DecideAutoResponse(facts), expected, label)
end

-- Relevant items are never touched, whatever the switches say ------------------------------------
check("relevant, both off",   {irrelevant = false, needsAppearance = true,  hideIrrelevant = false, autoTransmog = false}, nil)
check("relevant, both on",    {irrelevant = false, needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  nil)
check("relevant, hide on",    {irrelevant = false, needsAppearance = false, hideIrrelevant = true,  autoTransmog = false}, nil)

-- Unknown relevance behaves exactly like relevant --------------------------------------------------
check("unknown, both on",     {irrelevant = nil,   needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  nil)
check("unknown, hide on",     {irrelevant = nil,   needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = false}, nil)

-- Irrelevant with both switches off is today's behaviour -------------------------------------------
check("irrelevant, both off", {irrelevant = true,  needsAppearance = true,  hideIrrelevant = false, autoTransmog = false}, nil)

-- Hiding alone --------------------------------------------------------------------------------------
check("hide, mog needed",     {irrelevant = true,  needsAppearance = true,  hideIrrelevant = true,  autoTransmog = false}, "pass")
check("hide, mog owned",      {irrelevant = true,  needsAppearance = false, hideIrrelevant = true,  autoTransmog = false}, "pass")
check("hide, mog unknown",    {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = false}, "pass")

-- Auto-transmog alone -------------------------------------------------------------------------------
check("mog on, needed",       {irrelevant = true,  needsAppearance = true,  hideIrrelevant = false, autoTransmog = true},  "transmog")
check("mog on, owned",        {irrelevant = true,  needsAppearance = false, hideIrrelevant = false, autoTransmog = true},  nil)
-- Unknown appearance must not vote: a wrong Transmog vote is a claim on an item, not just a hidden row.
check("mog on, unknown",      {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = false, autoTransmog = true},  nil)

-- Both switches: transmog wins when the appearance is missing, hiding takes over otherwise ----------
check("both, mog needed",     {irrelevant = true,  needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  "transmog")
check("both, mog owned",      {irrelevant = true,  needsAppearance = false, hideIrrelevant = true,  autoTransmog = true},  "pass")
check("both, mog unknown",    {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = true},  "pass")
```

`tests/run.lua:54` — hinter der bestehenden Zeile ergänzen:

```lua
dofile("tests/test_lc_relevance.lua")
```

- [ ] **Step 2: Test laufen lassen und Fehlschlag bestätigen**

```bash
luajit tests/run.lua
```

Erwartet: Abbruch mit `LootCouncilRelevance.lua: No such file or directory` aus dem `assert(io.open(...))`. Das ist der gewünschte rote Zustand.

- [ ] **Step 3: Die minimale Implementierung schreiben**

`LootCouncilRelevance.lua` neu anlegen:

```lua
local ADDON_NAME, KART = ...
local LC = KART.LC

-- =====================================================================
--  Vote-window relevance  (which items are worth showing to THIS player)
-- =====================================================================
-- Two personal settings decide what happens to an item the player's class cannot equip: hide it
-- (voting the last configured response, so the council is not left waiting on a vote that will
-- never come) and/or vote Transmog on it while its appearance is still missing. Blizzard's own
-- loot roll is not involved anywhere in this file.

LC.Relevance = LC.Relevance or {}

-- Pure decision core, deliberately free of any WoW API call so tests/test_lc_relevance.lua can
-- compile it standalone. facts.irrelevant and facts.needsAppearance are three-state: true, false,
-- or nil for "could not be determined".
--
-- nil must behave like "relevant" and like "appearance owned" -- never the other way round. Both
-- automatic answers are claims made on the player's behalf, and a wrong one is expensive: hiding
-- passes away an item they were eligible for, and voting Transmog puts their name on an item they
-- may already have the appearance of.
local function DecideAutoResponse(facts)
    if facts.irrelevant ~= true then return nil end
    if facts.autoTransmog and facts.needsAppearance == true then return "transmog" end
    if facts.hideIrrelevant then return "pass" end
    return nil
end

LC.Relevance.DecideAutoResponse = DecideAutoResponse
```

`KeineAhnungRaidTools.toc:30` — die neue Datei **vor** `LootCouncilVote.lua` einhängen, weil dessen Refresh-Pfad sie in Task 4 aufruft:

```
LootCouncil.lua
LootCouncilOfficerNotes.lua
LootCouncilRelevance.lua
LootCouncilVote.lua
```

- [ ] **Step 4: Test laufen lassen und Erfolg bestätigen**

```bash
luajit tests/run.lua
luacheck .
```

Erwartet: 18 zusätzliche Assertions, 0 Fehler. `luacheck` grün — `ADDON_NAME` ist ungenutzt, folgt aber dem Muster jeder anderen Addon-Datei und wird von `.luacheckrc` bereits toleriert; schlägt es hier trotzdem an, `local _, KART = ...` schreiben.

- [ ] **Step 5: Commit**

```bash
git add LootCouncilRelevance.lua tests/test_lc_relevance.lua tests/run.lua KeineAhnungRaidTools.toc
git commit -m "feat: add the auto-response decision core for irrelevant vote items (#11)"
```

---

## Task 4: Fakten beschaffen und im Vote-Fenster verdrahten

**Files:**
- Modify: `LootCouncilRelevance.lua` (Fakten-Beschaffer + Anwendung)
- Modify: `LootCouncilVote.lua:172-183` (`GetVisibleRolls`), `LootCouncilVote.lua:185` (`RefreshVoteListRows`)

**Interfaces:**
- Consumes: `LC.Relevance.DecideAutoResponse(facts)` (Task 3), `LC.GetTransmogButtonIndex()` / `LC.GetPassButtonIndex()` (Task 1), `KART_Settings.lcHideIrrelevant` / `.lcAutoTransmogVote` (Task 2).
- Produces:
  - `LC.Relevance.ApplyToPendingRolls()` — läuft über `LC.voteListRolls`, beantwortet jeden noch unbeantworteten Roll höchstens einmal.
  - `LC.hiddenIrrelevant` — `[rollID] = true`, zweiter Ausblendgrund für `GetVisibleRolls`.
  - `LC.autoVotedByMe` — `[rollID] = true`, von Task 5 gelesen.

- [ ] **Step 1: Fakten-Beschaffer und Anwendung ergänzen**

Ans Ende von `LootCouncilRelevance.lua` anfügen:

```lua
-- Rolls this file has already answered, so a refresh (which runs several times a second during
-- active looting) cannot vote twice or re-hide a row the player brought back with /kart showall.
LC.relevanceHandled = LC.relevanceHandled or {}

-- [rollID] = true for a row hidden because the player cannot use the item. Read by
-- Vote.GetVisibleRolls next to the lcVotedItemDisplay == "hide" case.
LC.hiddenIrrelevant = LC.hiddenIrrelevant or {}

-- [rollID] = true when the vote on that roll was cast by this file rather than by the player.
-- Vote.CastVote lets an automatic vote be overridden once; a manual one still locks.
LC.autoVotedByMe = LC.autoVotedByMe or {}

-- Can this player's class not equip the item at all?  true / false / nil when undecidable.
--
-- GetLootRollItemInfo is the accurate answer -- it is Blizzard's own eligibility verdict and covers
-- weapons as well as armor, with no per-class table to maintain across expansions. It is only
-- available while a real roll is live on THIS client, which is the normal case: Blizzard fires
-- START_LOOT_ROLL even for an item the class cannot use (confirmed by the maintainer, 2026-07-28).
-- The armor fallback below exists for the rest: /kart add items, which never had a Blizzard roll at
-- all, and clients that missed the roll through death or distance and only learned of the item
-- through LC_START. That path cannot judge weapons, so it returns nil for them rather than guessing.
local function IsIrrelevantForMe(rollID, itemLink)
    if rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, canNeed = GetLootRollItemInfo(rollID)
        -- A nil texture means there is no live roll under this ID on our client, not that we are
        -- ineligible -- fall through instead of reading canNeed's nil as "cannot use".
        if texture then return not canNeed end
    end
    if not LC.IsRealItemLink(itemLink) then return nil end
    local rank = KART.LC.Council.GetItemArmorRank(itemLink)
    if not rank then return nil end -- jewellery, weapons, shields: no armor-weight restriction
    local _, classFile = UnitClass("player")
    return not KART.LC.Council.IsArmorEligible(classFile, rank)
end

-- Does the player still need this item's appearance?  true / false / nil when undecidable.
--
-- canTransmog from the live roll already means "collectible by me and not yet owned", so it is used
-- wherever it exists. Without a roll, C_TransmogCollection answers the same question in two steps:
-- an item with no appearance source (rings, necks, trinkets) can never be needed, and one with a
-- source is needed exactly while it is uncollected.
local function NeedsAppearance(rollID, itemLink)
    if rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, _, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        if texture then return not not canTransmog end
    end
    if not LC.IsRealItemLink(itemLink) then return nil end
    if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then return nil end
    local appearanceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID then return false end -- no appearance to collect
    if not C_TransmogCollection.PlayerHasTransmogByItemInfo then return nil end
    return not C_TransmogCollection.PlayerHasTransmogByItemInfo(itemLink)
end

-- Answers every pending roll that has not been answered yet. Called once per vote-list refresh,
-- which covers a fresh roll, a cast vote, an expiry sweep and -- the case that needs it -- the
-- refresh ResolveRollItemLink triggers once a link that started out as "???" has arrived.
function LC.Relevance.ApplyToPendingRolls()
    local hide = KART_Settings and KART_Settings.lcHideIrrelevant
    local mog  = KART_Settings and KART_Settings.lcAutoTransmogVote
    if not (hide or mog) then return end

    for _, rollID in ipairs(LC.voteListRolls) do
        -- Test rolls are exempt: /kart test exists to show what the window looks like, and a filter
        -- that empties it defeats that. Already-voted and already-handled rolls are left alone so a
        -- refresh cannot vote twice.
        if not LC.IsTestRoll(rollID) and not LC.votedByMe[rollID] and not LC.relevanceHandled[rollID] then
            local itemLink = LC.rollItems[rollID]
            -- Nothing is decidable without a link; leave the roll pending and try again on the
            -- refresh that ResolveRollItemLink fires once it has one.
            if LC.IsRealItemLink(itemLink) then
                local answer = LC.Relevance.DecideAutoResponse({
                    irrelevant      = IsIrrelevantForMe(rollID, itemLink),
                    needsAppearance = NeedsAppearance(rollID, itemLink),
                    hideIrrelevant  = hide and true or false,
                    autoTransmog    = mog and true or false,
                })
                if answer then
                    local idx = (answer == "transmog") and LC.GetTransmogButtonIndex() or LC.GetPassButtonIndex()
                    if idx then
                        LC.relevanceHandled[rollID] = true
                        LC.autoVotedByMe[rollID]    = true
                        if answer == "pass" then LC.hiddenIrrelevant[rollID] = true end
                        LC.Vote.CastVote(rollID, idx, nil)
                    end
                end
            end
        end
    end
end
```

- [ ] **Step 2: `GetVisibleRolls` um den zweiten Ausblendgrund erweitern**

`LootCouncilVote.lua:172-183` ersetzen durch:

```lua
function Vote.GetVisibleRolls()
    local hideVoted = (KART_Settings and KART_Settings.lcVotedItemDisplay) == "hide"
    if LC.showAllOverride then return LC.voteListRolls end
    -- Two independent reasons a row can be missing: the player has voted on it and asked for voted
    -- items to disappear, or they cannot use it at all and asked for those to disappear. Both are
    -- lifted together by /kart showall.
    local hidden = LC.hiddenIrrelevant or {}
    if not hideVoted then
        local anyIrrelevant = false
        for _, rollID in ipairs(LC.voteListRolls) do
            if hidden[rollID] then anyIrrelevant = true break end
        end
        if not anyIrrelevant then return LC.voteListRolls end
    end
    local visible = {}
    for _, rollID in ipairs(LC.voteListRolls) do
        if not hidden[rollID] and not (hideVoted and LC.votedByMe[rollID]) then
            table.insert(visible, rollID)
        end
    end
    return visible
end
```

- [ ] **Step 3: Aufrufpunkt in `RefreshVoteListRows` setzen**

`LootCouncilVote.lua:185-186` — direkt hinter der Funktionszeile, **vor** der `#LC.voteListRolls == 0`-Prüfung:

```lua
function Vote.RefreshVoteListRows()
    -- Before anything is measured or drawn: an item answered automatically here changes both the
    -- visible-row set and the window height that follows from it.
    LC.Relevance.ApplyToPendingRolls()
    if #LC.voteListRolls == 0 then
```

- [ ] **Step 4: Aufräumen an den zwei bestehenden Stellen ergänzen**

`LC.votedByMe` wird an genau zwei Stellen geleert; die drei neuen Tabellen müssen überall mit. Ohne das wachsen sie über eine Raidnacht mit, und ein wiederverwendeter `rollID` erbt den Zustand seines Vorgängers — dieselbe Fehlerklasse, gegen die `PurgeStaleRoll` existiert.

`LootCouncilTrade.lua:307` (in `Trade.ClearRollState`, dem echten Aufräumpfad) — direkt hinter `LC.votedNoteByMe[rollID] = nil`:

```lua
    LC.relevanceHandled[rollID] = nil
    LC.hiddenIrrelevant[rollID] = nil
    LC.autoVotedByMe[rollID]    = nil
```

`LootCouncil.lua:1915` (Reset eines Testlaufs) — direkt hinter `LC.votedByMe[testRollID] = nil`:

```lua
            LC.relevanceHandled[testRollID] = nil
            LC.hiddenIrrelevant[testRollID] = nil
            LC.autoVotedByMe[testRollID]    = nil
```

- [ ] **Step 5: Statische Gates**

```bash
luacheck .
luajit tests/run.lua
```

Erwartet: beide grün, Assertion-Zahl unverändert gegenüber Task 3.

- [ ] **Step 6: Im Spiel prüfen**

Voller WoW-Neustart (neue Datei in der `.toc`, ein `/reload` reicht nicht — siehe `kart-wow-testing`). Dann:

- Beide Schalter aus: `/kart test` und ein echter Loot-Roll verhalten sich exakt wie vorher.
- Nur „Ausblenden" an, echter Raid: ein Item, das die eigene Klasse nicht anlegen kann, verschwindet; auf dem Council-Panel steht für einen sofort die letzte Antwort („Pass"), der Fortschrittszähler zählt ihn mit.
- `/kart showall` holt das Item zurück.
- Nur „Transmog" an: ein nicht tragbares Item, dessen Aussehen fehlt, zeigt „Transmog" als eigene Stimme; ein bereits gesammeltes bleibt normal stehen.
- `/kart test` zeigt weiterhin alle vier Testitems, egal wie die Schalter stehen.

- [ ] **Step 7: Commit**

```bash
git add LootCouncilRelevance.lua LootCouncilVote.lua LootCouncil.lua
git commit -m "feat: hide and auto-answer vote items the player's class cannot equip (#11)"
```

---

## Task 5: Automatische Stimmen dürfen überschrieben werden

Erkennt der Filter etwas falsch, muss der Spieler das korrigieren können. Ohne diese Aufgabe ist eine automatische Stimme so endgültig wie eine geklickte.

**Files:**
- Modify: `LootCouncilVote.lua:251-253` (`CastVote`)

**Interfaces:**
- Consumes: `LC.autoVotedByMe` (Task 4).
- Produces: keine neuen Namen.

- [ ] **Step 1: Die Sperre für automatische Stimmen lösen**

`LootCouncilVote.lua:251-253` ersetzen durch:

```lua
function Vote.CastVote(rollID, buttonIdx, noteBox)
    -- A vote the player clicked is final. One that LC.Relevance cast on their behalf is not: the
    -- relevance check can be wrong, and the player's own correction has to win over it. HandleVote
    -- stores per sender and overwrites, so the council simply sees the corrected vote -- no protocol
    -- change and no double counting.
    if LC.votedByMe[rollID] and not LC.autoVotedByMe[rollID] then return end
    LC.autoVotedByMe[rollID] = nil
    LC.votedByMe[rollID] = buttonIdx
```

**Achtung:** `LC.Relevance.ApplyToPendingRolls` setzt `LC.autoVotedByMe[rollID] = true` **vor** dem `CastVote`-Aufruf, und diese Zeile löscht es sofort wieder. Die Reihenfolge muss deshalb umgedreht werden — in `LootCouncilRelevance.lua` das Setzen **hinter** den Aufruf ziehen:

```lua
                        LC.relevanceHandled[rollID] = true
                        if answer == "pass" then LC.hiddenIrrelevant[rollID] = true end
                        LC.Vote.CastVote(rollID, idx, nil)
                        LC.autoVotedByMe[rollID] = true
```

- [ ] **Step 2: Statische Gates**

```bash
luacheck .
luajit tests/run.lua
```

Erwartet: beide grün.

- [ ] **Step 3: Im Spiel prüfen**

Echter Raid oder ein zweiter Account, mit „Ausblenden" an:

- Ein nicht tragbares Item wird ausgeblendet und automatisch beantwortet.
- `/kart showall` holt es zurück, die Antwort-Buttons sind anklickbar, ein Klick ersetzt die automatische Stimme.
- Auf dem Council-Panel eines anderen Spielers steht danach die neue Antwort, nicht die alte.
- Ein zweiter Klick auf dieselbe Zeile ändert nichts mehr — die manuelle Stimme sperrt wie gewohnt.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilVote.lua LootCouncilRelevance.lua
git commit -m "feat: let a player override a vote KART cast for them (#11)"
```

---

## Task 6: Release

**Files:**
- Modify: `KeineAhnungRaidTools.toc` (Version), `CHANGELOG.md`, `CHANGELOG-de.md`

- [ ] **Step 1: Changelog-Einträge**

In `CHANGELOG.md` oben ein Abschnitt für die neue Version, im Stil der bestehenden Einträge — eine Zeile pro Eintrag, fetter Lead:

```markdown
- **Items your class cannot equip can now be hidden from the vote window.** They are answered with your last configured response automatically, so the council is not left waiting.
- **KART can vote Transmog for you on items you cannot equip but whose appearance you still need.**
- **A fixed Transmog button is now always the last vote response.** Freely configurable labels drop from six to five.
```

In `CHANGELOG-de.md` dieselben drei Einträge auf Deutsch:

```markdown
- **Items, die deine Klasse nicht anlegen kann, lassen sich jetzt aus dem Vote-Fenster ausblenden.** Sie werden automatisch mit deiner letzten konfigurierten Antwort beantwortet, damit der Council nicht wartet.
- **KART kann für dich Transmog wählen bei Items, die du nicht anlegen kannst, deren Aussehen dir aber fehlt.**
- **Ein fester Transmog-Button ist jetzt immer die letzte Antwort.** Frei konfigurierbare Labels sinken von sechs auf fünf.
```

- [ ] **Step 2: Version anheben**

`KeineAhnungRaidTools.toc` — `## Version:` auf die nächste Minor-Version setzen (Feature, kein Patch): `3.2.0`.

- [ ] **Step 3: Gates ein letztes Mal**

```bash
bash tests/check-moved.sh
luacheck .
luajit tests/run.lua
```

Erwartet: alle drei grün — dieselben drei Prüfungen, die die CI fährt.

- [ ] **Step 4: Commit und Tag**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "release: 3.2.0"
git tag v3.2.0
```

Erst nach **grüner CI** pushen, dann Issue #11 beantworten. Das Issue bleibt offen, bis Nara/Kevin die Wirkung im Raid bestätigt — siehe die Antwortregeln in `docs/` und die Projektkonventionen.

- [ ] **Step 5: Antwort im Issue entwerfen**

Auf Deutsch, an Kevin gerichtet, zur Freigabe vorlegen bevor sie gepostet wird. Inhalt: was die beiden Schalter tun, dass beide standardmäßig aus sind und wo sie stehen, dass Offspec-Items bewusst weiterhin erscheinen, und die Bitte, es im nächsten Raid zu bestätigen.

---

## Offene Punkte für den Maintainer

- Der eigene Transmog-Button auf Position 5 muss nach dem Update aus der raid-weiten Konfiguration entfernt werden, sonst stehen zwei nebeneinander. Der Maintainer erledigt das, sobald das Update testbar ist.
- Der Icon-Pfad `Interface\MINIMAP\TRACKING\Transmogrifier` ist nicht verifiziert. Task 1, Step 8 prüft ihn und nennt den Ausweichpfad.
