-- The raid-wide settings box: what it shows, and what it lets you type into.
--
-- Every rule in here was paid for. B20 -- a raider staring at empty Council and Lootmaster boxes
-- with "5 names not resolved yet" printed underneath, because the counter read the effective config
-- while the boxes read their own dormant one. And the dead end where a departed lootmaster left the
-- field locked behind his own config showing "?", so no replacement could name themselves and the
-- raid had no loot flow until somebody reloaded.
--
-- LootCouncilSettings.lua was the last addon file the harness did not load at all.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- Build the real widgets once per client that needs them: everything below reads what a human would
-- see in those boxes, which is the whole point.
-- The one thing the builder needs from MainFrame.lua, which the harness does not load: a fixed
-- header FontString for the tab. Stubbed rather than dragging fifty kilobytes of frame construction
-- in behind it -- what is under test here is which boxes show what and which of them accept typing.
local function WithPanel(client)
    RaidSim.As(client, function()
        client.KART.CreateTabTitle = client.KART.CreateTabTitle or function() end
        if not client.KART.LC.LootmasterEditBox then
            client.KART.LC.BuildSettingsPanel(CreateFrame("Frame"))
        end
    end)
    return client.KART.LC
end

local function Refresh(client)
    RaidSim.As(client, function() client.KART.LC.RefreshRaidWideFields() end)
end

local function Text(eb) return eb and eb:GetText() or nil end

do
    local _, lm = F.NewRaid()
    local LC = WithPanel(lm)
    Refresh(lm)
    T.eq(Text(LC.LootmasterEditBox), "Bramor", "the config owner sees their own field")
    T.eq(Text(LC.CouncilMembersEditBox), "Bramor;Merrit;Corvin", "and their own council list")
    T.truthy(LC.CouncilMembersEditBox:IsKeyboardEnabled(), "and can edit it")
end

do
    -- A raider under somebody else's config: the boxes show the RAID's values, not their own dormant
    -- ones, and they are read-only because editing them would change nothing for the raid while
    -- silently discarding what the viewer had typed for themselves.
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "BIS;Zweitspec;Transmog"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    local alric = sim.byName.Alric
    alric.env.KART_Settings.lcCouncilMembers = "meine;eigene;liste"
    alric.env.KART_Settings.lcButtonLabels = "meine;buttons"
    local LC = WithPanel(alric)
    Refresh(alric)

    T.eq(Text(LC.CouncilMembersEditBox), "Bramor;Merrit;Corvin",
        "a peer sees the raid's council list rather than their own")
    T.eq(Text(LC.LootmasterEditBox), "Bramor", "and the raid's lootmaster, by name and not as a key")
    T.eq(Text(LC.ButtonLabelEditBox), "BIS;Zweitspec;Transmog",
        "and the raid's vote buttons -- the field that decides what a click MEANS to everyone else")
    T.truthy(not LC.CouncilMembersEditBox:IsKeyboardEnabled(),
        "the borrowed fields are read-only")
    T.truthy(not LC.LootmasterEditBox:IsKeyboardEnabled(),
        "including the lootmaster field, while its owner is here")

    T.eq(alric.env.KART_Settings.lcCouncilMembers, "meine;eigene;liste",
        "and their own setting is untouched underneath -- it comes back when no foreign config applies")
end

do
    -- The dead end: the configured lootmaster leaves for good. Nobody satisfies IsLootOwner any more,
    -- so the only way back is for a replacement to type their own name in -- which needs that one
    -- field to become editable again, even though a foreign config is still in force.
    -- A SPLIT raid on purpose: Corvin leads, Bramor hands out the loot. In the default fixture
    -- the two are the same person, so once they leave the next client becomes raid leader and
    -- therefore the legitimate config owner -- editable fields then, and correctly so, which would
    -- make this assert about the wrong thing entirely.
    local sim = F.NewSplitRaid()
    local alric = sim.byName.Alric
    alric.env.KART_Settings.lcLootmaster = "Alric"
    local LC = WithPanel(alric)
    Refresh(alric)
    T.truthy(not LC.LootmasterEditBox:IsKeyboardEnabled(), "locked while the lootmaster is present")

    RaidSim.Leave(sim, "Bramor")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(1)
    Refresh(alric)

    T.truthy(LC.LootmasterEditBox:IsKeyboardEnabled(),
        "editable again once the configured lootmaster is gone, or the raid has no way back")
    T.eq(Text(LC.LootmasterEditBox), "Alric",
        "showing what this client typed rather than a '?' that would fight whoever is typing")
    T.truthy(not LC.CouncilMembersEditBox:IsKeyboardEnabled(),
        "while the other raid-wide fields stay borrowed and read-only")
end

do
    -- The other two raid-wide controls (B103). The read-only rule above is written for EditBoxes,
    -- and the box holds two things that are not: the minimum-quality menu button and the rolls
    -- checkbox. Both write straight into the viewer's OWN settings, and the broadcast that follows
    -- refuses to send because they do not own the config -- so the click discards a setting of
    -- theirs, changes nothing for the raid, and the display snaps back on the next roster change
    -- with no sign anything happened. It surfaces later, when this client becomes the config owner
    -- and the raid quietly runs on the value they never meant to set.
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcMinQuality = 4
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    local alric = sim.byName.Alric
    alric.env.KART_Settings.lcMinQuality = 3
    alric.env.KART_Settings.lcRollsEnabled = false
    local LC = WithPanel(alric)
    Refresh(alric)

    T.truthy(not LC.BtnMinQuality:IsMouseEnabled(),
        "the borrowed minimum-quality button does not take clicks")
    T.truthy(not LC.CbRollsEnabled:IsMouseEnabled(),
        "and neither does the borrowed rolls checkbox")

    -- ...and clicking it does not open the menu at all, so the viewer's own value survives.
    -- KARTTEST.Click, not the OnClick script directly: a frame with the mouse disabled never
    -- receives a click in the game, and calling its handler is a stronger act than a player can
    -- perform -- which would make this assert about a path that does not exist.
    T.truthy(not RaidSim.As(alric, function() return KARTTEST.Click(LC.BtnMinQuality) end),
        "a click on it does not reach the menu")
    T.eq(alric.env.KART_Settings.lcMinQuality, 3,
        "so their own minimum quality is not overwritten by a value they cannot set for the raid")

    -- The owner's own box is untouched by all of this: their controls are the raid's.
    local LCowner = WithPanel(lm)
    Refresh(lm)
    T.truthy(LCowner.BtnMinQuality:IsMouseEnabled(), "the config owner can still set it")
    T.truthy(LCowner.CbRollsEnabled:IsMouseEnabled(), "and still toggle rolls")
end

do
    -- The role label is the one line that tells somebody why the box below is doing nothing.
    local sim, lm = F.NewRaid()
    local LC = WithPanel(lm)
    RaidSim.As(lm, function() lm.KART.LC.UpdateRoleStatusLabel() end)
    T.eq(LC.RoleStatusLabel:GetText(), lm.KART.L.LC_ROLE_STATUS_OWNER,
        "the config owner is told the raid runs on their settings")

    local alric = sim.byName.Alric
    local LCa = WithPanel(alric)
    alric.env.KART_Settings.lcLootmaster = ""
    RaidSim.As(alric, function() alric.KART.LC.UpdateRoleStatusLabel() end)
    T.eq(LCa.RoleStatusLabel:GetText(), alric.KART.L.LC_ROLE_STATUS_MEMBER,
        "a plain member is told somebody else's settings apply")

    -- Naming somebody else makes the whole box inert -- not just for the raid but locally, since
    -- ApplyOwnConfig no-ops for a non-owner. The plain "the lootmaster's settings apply" would read
    -- as if it were taken care of.
    alric.env.KART_Settings.lcLootmaster = "Wuusch"
    RaidSim.As(alric, function() alric.KART.LC.UpdateRoleStatusLabel() end)
    T.eq(LCa.RoleStatusLabel:GetText(), alric.KART.L.LC_ROLE_STATUS_FOREIGN,
        "and somebody who named a third party is told what is actually missing")
end

do
    -- Colons are the LC_CONFIG payload separator. One inside a synced field makes every receiver's
    -- pattern fail silently and leaves the whole raid on stale config.
    local _, lm = F.NewRaid()
    local LC = WithPanel(lm)
    RaidSim.As(lm, function()
        LC.CouncilMembersEditBox:SetText("Bramor:Merrit;Corvin")
        local script = LC.CouncilMembersEditBox:GetScript("OnTextChanged")
        if script then script(LC.CouncilMembersEditBox) end
    end)
    T.truthy(not (Text(LC.CouncilMembersEditBox) or ""):find(":", 1, true),
        "a colon typed into a synced field is stripped at input")
end
