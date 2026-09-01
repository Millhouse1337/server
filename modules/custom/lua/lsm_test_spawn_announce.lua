-----------------------------------
-- LSM Test: HNM Spawn Announcements
--
-- Emits the HNM spawn announcement strings that the LSM addon's Claim Shield watcher
-- matches against (constants.CLAIM_SHIELD_START_MESSAGE_INFO).
--
-- Stock LandSandBoat never emits these strings -- they originate on other private
-- servers -- so without this module the addon's spawn-detection path cannot be
-- exercised on an LSB server at all.
--
-- The addon matches these with find(line, message, 1, true), a plain substring
-- search, so the text below must stay byte-exact.
--
-- Test-only module. Not intended for upstream.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('lsm_test_spawn_announce')

-- NOTE: These names are as they are as filenames, matching claim_shield.lua.
-- Example: King Behemoth => King_Behemoth
-- { zone name, mob name, announcement }
local spawnAnnouncements =
{
    { 'Behemoths_Dominion', 'Behemoth',      'You hear the thundering roar of a monster in the distance'               },
    { 'Behemoths_Dominion', 'King_Behemoth', 'You hear a thundering roar of a great Behemoth in the distance'          },
    { 'Dragons_Aery',       'Fafnir',        'You hear an ominous roar off in the distance'                            },
    { 'Dragons_Aery',       'Nidhogg',       'You hear the roar of a great wyrm off in the distance'                   },
    { 'Valley_of_Sorrows',  'Adamantoise',   'You feel the ground shake as a large monster stomps in the distance'     },
    { 'Valley_of_Sorrows',  'Aspidochelone', 'You feel the ground split as an enormous monster stomps in the distance' },
}

-- Announce to every player currently in the mob's zone.
--
-- NOTE: printToArea() is PC-only -- it logs an error and bails on a mob entity -- so we
--     : fan out over the zone's players, the same way claim_shield.lua messages an alliance.
local announceToZone = function(mob, message)
    local zone = mob:getZone()
    if not zone then
        return
    end

    for _, player in pairs(zone:getPlayers()) do
        player:printToPlayer(message, xi.msg.channel.SYSTEM_3, '')
    end
end

-- NOTE: We override onMobSpawn rather than onMobInitialize + a SPAWN listener (which is
--     : what claim_shield.lua does) because Fafnir, Nidhogg and Behemoth do not define
--     : onMobInitialize, which would leave `super` nil for those three.
for _, entry in pairs(spawnAnnouncements) do
    local message = entry[3]

    m:addOverride(string.format('xi.zones.%s.mobs.%s.onMobSpawn', entry[1], entry[2]), function(mob)
        super(mob)

        announceToZone(mob, message)
    end)
end

return m
