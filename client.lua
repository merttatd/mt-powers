local QBCore = exports['qb-core']:GetCoreObject()

local selectedPowers = {}
local shadowStates = {}
local telekinesisStates = {}

local blackoutCounter = 0

local function Notify(src, message, notifyType)
    TriggerClientEvent('mt-powers:client:notify', src, message, notifyType or 'inform')
end

local function GetDefaultPower()
    if Config.Powers and Config.Powers[1] then
        return Config.Powers[1].id
    end

    return 'electric'
end

local function IsValidPower(power)
    for _, data in ipairs(Config.Powers) do
        if data.id == power then
            return true
        end
    end

    return false
end

local function ValidateCoords(src, targetCoords, maxDistance)
    if type(targetCoords) ~= 'table' then return false end
    if not targetCoords.x or not targetCoords.y or not targetCoords.z then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)

    local coords = vector3(
        tonumber(targetCoords.x),
        tonumber(targetCoords.y),
        tonumber(targetCoords.z)
    )

    if #(playerCoords - coords) > maxDistance + 20.0 then
        return false
    end

    return true, coords
end

RegisterNetEvent('mt-powers:server:getSelectedPower', function()
    local src = source

    if not selectedPowers[src] then
        selectedPowers[src] = GetDefaultPower()
    end

    TriggerClientEvent('mt-powers:client:setSelectedPower', src, selectedPowers[src])
end)

RegisterNetEvent('mt-powers:server:setSelectedPower', function(power)
    local src = source

    if not IsValidPower(power) then return end

    selectedPowers[src] = power
    TriggerClientEvent('mt-powers:client:setSelectedPower', src, power)
end)

RegisterNetEvent('mt-powers:server:tryElectricBlackout', function(targetCoords)
    local src = source

    if selectedPowers[src] ~= 'electric' then return end

    local valid, coords = ValidateCoords(src, targetCoords, Config.Electric.TargetDistance)

    if not valid then
        Notify(src, Config.Messages.TargetTooFar, 'error')
        return
    end

    blackoutCounter = blackoutCounter + 1

    local blackoutId = ('blackout_%s_%s'):format(src, blackoutCounter)

    TriggerClientEvent('mt-powers:client:startBlackout', -1, blackoutId, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }, Config.Electric.Radius, Config.Electric.Duration, src)

    Notify(src, Config.Messages.ElectricActivated, 'success')

    SetTimeout(Config.Electric.Duration * 1000, function()
        TriggerClientEvent('mt-powers:client:forceStopBlackout', -1, blackoutId)
    end)
end)

RegisterNetEvent('mt-powers:server:toggleShadowForm', function()
    local src = source

    if selectedPowers[src] ~= 'shadow' then return end

    shadowStates[src] = not shadowStates[src]

    if shadowStates[src] then
        TriggerClientEvent('mt-powers:client:startShadowForm', -1, src)
        Notify(src, Config.Messages.ShadowActivated, 'success')
    else
        TriggerClientEvent('mt-powers:client:stopShadowForm', -1, src)
        Notify(src, Config.Messages.ShadowEnded, 'inform')
    end
end)

RegisterNetEvent('mt-powers:server:startTelekinesis', function(netIds)
    local src = source

    if selectedPowers[src] ~= 'telekinesis' then return end
    if telekinesisStates[src] then return end

    telekinesisStates[src] = true

    TriggerClientEvent('mt-powers:client:startTelekinesis', -1, src, netIds or {})
    Notify(src, Config.Messages.TelekinesisStarted, 'success')
end)

RegisterNetEvent('mt-powers:server:throwTelekinesis', function()
    local src = source

    if selectedPowers[src] ~= 'telekinesis' then return end
    if not telekinesisStates[src] then return end

    telekinesisStates[src] = false

    TriggerClientEvent('mt-powers:client:throwTelekinesis', -1, src)
    Notify(src, Config.Messages.TelekinesisThrown, 'success')
end)

RegisterNetEvent('mt-powers:server:stopTelekinesis', function()
    local src = source

    telekinesisStates[src] = false
    TriggerClientEvent('mt-powers:client:stopTelekinesis', -1, src)
end)

AddEventHandler('playerDropped', function()
    local src = source

    selectedPowers[src] = nil
    shadowStates[src] = nil
    telekinesisStates[src] = nil

    TriggerClientEvent('mt-powers:client:stopTelekinesis', -1, src)
end)
