-----------------------------------
-- LSM Test: Claim Shield for the classic HNMs
--
-- Extends claim-shield behaviour to the six HNMs that stock claim_shield.lua does NOT
-- cover: Fafnir, Nidhogg, Behemoth, King Behemoth, Adamantoise and Aspidochelone.
--
-- Why this exists:
--   The LSM addon's Claim Shield feature is a sequence -- spawn announcement, then a
--   lottery result, then the kill. Stock claim_shield.lua covers 33 NMs but none of
--   these six, while lsm_test_spawn_announce.lua only covers these six. Without this
--   module no single mob can exercise announce -> lottery -> ToD as one chain, which
--   is the flow that actually runs in production.
--
--   Load this alongside lsm_test_spawn_announce.lua to get the complete chain on, for
--   example, Fafnir. Load it separately to isolate a lottery failure from an
--   announcement failure.
--
-- The lottery logic is adapted from modules/custom/lua/claim_shield.lua so that the
-- emitted strings stay identical to the ones the addon's text_parser.lua expects.
-- Kept as a separate file so the tracked upstream module stays untouched.
--
-- Test-only module. Not intended for upstream.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('lsm_test_claimshield_hnm')

local claimshieldTime = 7500

-- NOTE: These names are as they are as filenames, matching claim_shield.lua.
-- { zone name, mob name }
local nmsToShield =
{
    { 'Behemoths_Dominion', 'Behemoth'      },
    { 'Behemoths_Dominion', 'King_Behemoth' },
    { 'Dragons_Aery',       'Fafnir'        },
    { 'Dragons_Aery',       'Nidhogg'       },
    { 'Valley_of_Sorrows',  'Adamantoise'   },
    { 'Valley_of_Sorrows',  'Aspidochelone' },
}

-- Find the position of a target entity in a table, only if they have matching ids
local tableFindPosByID = function(t, target)
    for index, entity in ipairs(t) do
        if entity:getID() == target:getID() then
            return index
        end
    end

    return nil
end

-- Using entity ids: dedupe a table in-place
local dedupeByID = function(t)
    local seen = {}
    for index, entity in ipairs(t) do
        if seen[entity:getID()] then
            table.remove(t, index)
        else
            seen[entity:getID()] = true
        end
    end
end

-- Called when the claimshield period ends
local timerFunc = function(mob)
    local enmityList = mob:getEnmityList()

    -- Filter so that pets will only count as a single entry along with their masters
    local entries = {}
    for _, v in pairs(enmityList) do
        local entity = v['entity']
        local master = entity:getMaster()
        if
            not entity:isPC() and
            master and
            master:isPC()
        then
            table.insert(entries, master)
        else
            table.insert(entries, entity)
        end
    end

    -- Remove duplicates from entries table caused by pets or other shenanigans
    dedupeByID(entries)

    local numEntries = #entries

    mob:setMobMod(xi.mobMod.CLAIM_TYPE, xi.claimType.EXCLUSIVE)
    mob:setUnkillable(false)
    mob:setCallForHelpBlocked(false)

    mob:resetAI()
    mob:setHP(mob:getMaxHP())
    mob:delStatusEffectsByFlag(0xFFFF) -- Delete all effects with all flags

    -- Select a winner
    local claimWinner = utils.randomEntry(entries)
    if claimWinner then
        mob:updateClaim(claimWinner)

        -- Message winner and their party/alliance that they've won
        local alliance = claimWinner:getAlliance()
        for _, member in pairs(alliance) do
            local str = string.format('Your group has won the lottery for %s! (out of %i players)', mob:getPacketName(), numEntries)
            if #alliance == 1 then
                str = string.format('You have won the lottery for %s! (out of %i players)', mob:getPacketName(), numEntries)
            end

            member:printToPlayer(str, xi.msg.channel.SYSTEM_3, '')

            -- Remove from entries table
            local pos = tableFindPosByID(entries, member)
            if pos then
                table.remove(entries, pos)
            end
        end

        -- Everyone left in the entries table isn't part of the winning group, message them and
        -- clear them from the enmity list
        for _, member in pairs(entries) do
            local str = string.format('Your group was not successful in the lottery for %s. (out of %i players)', mob:getPacketName(), numEntries)
            if #alliance == 1 then
                str = string.format('Your were not successful in the lottery for %s. (out of %i players)', mob:getPacketName(), numEntries)
            end

            member:printToPlayer(str, xi.msg.channel.SYSTEM_3, '')
            mob:clearEnmityForEntity(member)
        end
    end
end

-- Apply the shield and start the lottery timer
local applyShield = function(mob)
    print(string.format('Applying Claimshield to %s for %ims', mob:getPacketName(), claimshieldTime))

    mob:setMobMod(xi.mobMod.CLAIM_TYPE, xi.claimType.UNCLAIMABLE)
    mob:setUnkillable(true)
    mob:setCallForHelpBlocked(true)
    mob:stun(claimshieldTime)

    mob:timer(claimshieldTime, timerFunc)
end

-- NOTE: We override onMobSpawn rather than onMobInitialize + a SPAWN listener (which is
--     : what claim_shield.lua does) because Fafnir, Nidhogg and Behemoth do not define
--     : onMobInitialize, which would leave `super` nil for those three.
for _, entry in pairs(nmsToShield) do
    m:addOverride(string.format('xi.zones.%s.mobs.%s.onMobSpawn', entry[1], entry[2]), function(mob)
        super(mob)

        applyShield(mob)
    end)
end

return m
