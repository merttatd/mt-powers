local QBCore = exports['qb-core']:GetCoreObject()

local selectedPower = nil
local currentPowerIndex = 1

local activeBlackouts = {}
local isBlackoutActive = false

local isShadowForm = false
local shadowJumpLock = false

local activeTelekinesis = {}
local localTelekinesisActive = false
local telekinesisDistance = Config.Telekinesis.DefaultHoldDistance

local function Notify(message, notifyType)
    notifyType = notifyType or 'inform'

    if Config.UseMtUiNotify then
        local success = pcall(function()
            exports['mt-ui']:Notify({
                title = 'Güç',
                message = message,
                type = notifyType,
                duration = 3500
            })
        end)

        if success then return end
    end

    QBCore.Functions.Notify(message, notifyType, 3500)
end

local function LoadPtfx(dict)
    RequestNamedPtfxAsset(dict)
    while not HasNamedPtfxAssetLoaded(dict) do Wait(10) end
end

local function GetPowerLabel(powerId)
    for _, power in ipairs(Config.Powers) do
        if power.id == powerId then
            return power.label
        end
    end

    return powerId
end

local function GetPowerIndex(powerId)
    for index, power in ipairs(Config.Powers) do
        if power.id == powerId then
            return index
        end
    end

    return 1
end

local function SetSelectedPower(powerId)
    selectedPower = powerId
    currentPowerIndex = GetPowerIndex(powerId)
end

local function CyclePower()
    if not Config.Powers or #Config.Powers <= 0 then return end

    currentPowerIndex = currentPowerIndex + 1

    if currentPowerIndex > #Config.Powers then
        currentPowerIndex = 1
    end

    local newPower = Config.Powers[currentPowerIndex]
    if not newPower then return end

    SetSelectedPower(newPower.id)
    TriggerServerEvent('mt-powers:server:setSelectedPower', newPower.id)

    Notify(Config.Messages.PowerChanged .. newPower.label, 'success')
end

RegisterCommand(Config.CyclePowerCommand, function()
    CyclePower()
end, false)

RegisterKeyMapping(
    Config.CyclePowerCommand,
    'Güçler Arasında Geçiş Yap',
    'keyboard',
    Config.CyclePowerKey
)

RegisterNetEvent('mt-powers:client:setSelectedPower', function(power)
    SetSelectedPower(power)
    Notify(Config.Messages.PowerChanged .. GetPowerLabel(power), 'inform')
end)

RegisterNetEvent('mt-powers:client:notify', function(message, notifyType)
    Notify(message, notifyType)
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('mt-powers:server:getSelectedPower')
end)

local function RotationToDirection(rotation)
    local adjustedRotation = {
        x = math.rad(rotation.x),
        y = math.rad(rotation.y),
        z = math.rad(rotation.z)
    }

    return vector3(
        -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.sin(adjustedRotation.x)
    )
end

local function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot(2)
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = cameraCoord + direction * distance

    local rayHandle = StartShapeTestRay(
        cameraCoord.x,
        cameraCoord.y,
        cameraCoord.z,
        destination.x,
        destination.y,
        destination.z,
        -1,
        PlayerPedId(),
        0
    )

    local _, hit, endCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 then
        return true, endCoords, entityHit
    end

    return false, destination, entityHit
end

local function PlayElectricSparkSound(duration)
    if not Config.Electric.Effects.EnableSparkSound then return end

    CreateThread(function()
        local endTime = GetGameTimer() + duration

        while GetGameTimer() < endTime do
            PlaySoundFrontend(-1, 'Short_Circuit', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
            Wait(Config.Electric.Effects.SparkSoundInterval)
        end
    end)
end

local function PlayPlayerElectricEffect()
    if not Config.Electric.Effects.EnablePlayerElectricEffect then return end

    local ped = PlayerPedId()

    LoadPtfx('core')

    local endTime = GetGameTimer() + Config.Electric.Effects.PlayerElectricEffectDuration

    PlayElectricSparkSound(Config.Electric.Effects.PlayerElectricEffectDuration)

    CreateThread(function()
        while GetGameTimer() < endTime do
            ped = PlayerPedId()

            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntity(
                'ent_dst_elec_fire_sp',
                ped,
                0.0, 0.0, 0.2,
                0.0, 0.0, 0.0,
                2.2,
                false,
                false,
                false
            )

            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntity(
                'ent_dst_elec_fire_sp',
                ped,
                0.35, 0.0, 0.65,
                0.0, 0.0, 0.0,
                1.7,
                false,
                false,
                false
            )

            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntity(
                'ent_dst_elec_fire_sp',
                ped,
                -0.35, 0.0, 0.65,
                0.0, 0.0, 0.0,
                1.7,
                false,
                false,
                false
            )

            Wait(130)
        end
    end)
end

local function DisableVehicleCompletely(vehicle)
    if not DoesEntityExist(vehicle) then return end

    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleHandbrake(vehicle, true)
    SetVehicleForwardSpeed(vehicle, 0.0)
    SetVehicleBrakeLights(vehicle, true)
    SetVehicleLights(vehicle, 1)

    local driver = GetPedInVehicleSeat(vehicle, -1)

    if driver ~= 0 then
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
        DisableControlAction(0, 63, true)
        DisableControlAction(0, 64, true)
    end
end

local function StartVehicleShutdownLoop(blackoutId, coords, radius, duration)
    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        local affectedVehicles = {}

        while GetGameTimer() < endTime and activeBlackouts[blackoutId] do
            local vehicles = GetGamePool('CVehicle')

            for _, vehicle in pairs(vehicles) do
                if DoesEntityExist(vehicle) then
                    local distance = #(GetEntityCoords(vehicle) - coords)

                    if distance <= radius then
                        affectedVehicles[vehicle] = true
                        DisableVehicleCompletely(vehicle)
                    end
                end
            end

            Wait(150)
        end

        for vehicle in pairs(affectedVehicles) do
            if DoesEntityExist(vehicle) then
                SetVehicleUndriveable(vehicle, false)
                SetVehicleHandbrake(vehicle, false)
                SetVehicleBrakeLights(vehicle, false)
            end
        end
    end)
end

local function StunNearbyPlayers(coords, casterServerId)
    local players = GetActivePlayers()

    for _, player in pairs(players) do
        local targetServerId = GetPlayerServerId(player)

        if targetServerId ~= casterServerId then
            local ped = GetPlayerPed(player)
            local dist = #(GetEntityCoords(ped) - coords)

            if dist <= 8.0 then
                SetPedToRagdoll(
                    ped,
                    1500,
                    1500,
                    0,
                    false,
                    false,
                    false
                )
            end
        end
    end
end

local function RPNotify(coords)
    local players = GetActivePlayers()

    for _, player in pairs(players) do
        local ped = GetPlayerPed(player)
        local dist = #(GetEntityCoords(ped) - coords)

        if dist <= Config.Electric.Radius then
            TriggerEvent(
                'mt-powers:client:notify',
                'Havada yoğun bir elektriklenme hissediyorsun...',
                'inform'
            )
        end
    end
end

local function ScareNearbyNPCs(coords, radius)
    CreateThread(function()
        local peds = GetGamePool('CPed')

        for _, ped in pairs(peds) do
            if DoesEntityExist(ped)
                and not IsPedAPlayer(ped)
                and not IsPedDeadOrDying(ped, true)
            then
                local distance = #(GetEntityCoords(ped) - coords)

                if distance <= radius then
                    ClearPedTasksImmediately(ped)
                    SetPedFleeAttributes(ped, 0, false)
                    SetPedCombatAttributes(ped, 17, true)
                    TaskSmartFleeCoord(
                        ped,
                        coords.x,
                        coords.y,
                        coords.z,
                        radius + 80.0,
                        45000,
                        false,
                        false
                    )
                end
            end
        end
    end)
end

local function ApplyBlackoutVisuals(state)
    if state and not isBlackoutActive then
        isBlackoutActive = true
        SetArtificialLightsState(true)
        SetArtificialLightsStateAffectsVehicles(false)
    elseif not state and isBlackoutActive then
        isBlackoutActive = false
        SetArtificialLightsState(false)
        SetArtificialLightsStateAffectsVehicles(true)
    end
end

local function IsInsideBlackout()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local now = GetGameTimer()

    for k, v in pairs(activeBlackouts) do
        if now >= v.endTime then
            activeBlackouts[k] = nil
        else
            if #(coords - v.coords) <= v.radius then
                return true
            end
        end
    end

    return false
end

CreateThread(function()
    while true do
        Wait(500)
        ApplyBlackoutVisuals(IsInsideBlackout())
    end
end)

RegisterNetEvent('mt-powers:client:startBlackout', function(id, coords, radius, duration, casterServerId)
    coords = vector3(coords.x, coords.y, coords.z)

    activeBlackouts[id] = {
        coords = coords,
        radius = radius,
        endTime = GetGameTimer() + (duration * 1000)
    }

    StartVehicleShutdownLoop(id, coords, radius, duration)
    StunNearbyPlayers(coords, casterServerId)
    RPNotify(coords)
    ScareNearbyNPCs(coords, Config.Electric.NPCFearRadius)
end)

RegisterNetEvent('mt-powers:client:forceStopBlackout', function(id)
    activeBlackouts[id] = nil
end)

RegisterCommand(Config.Electric.CommandName, function()
    if selectedPower ~= 'electric' then
        return
    end

    local ped = PlayerPedId()

    if IsPedDeadOrDying(ped, true) then return end
    if IsPauseMenuActive() then return end

    local _, coords = RayCastGamePlayCamera(Config.Electric.TargetDistance)
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - coords)

    if distance > Config.Electric.TargetDistance + 5.0 then
        Notify(Config.Messages.TargetTooFar, 'error')
        return
    end

    PlayPlayerElectricEffect()

    TriggerServerEvent('mt-powers:server:tryElectricBlackout', {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })
end, false)

RegisterKeyMapping(
    Config.Electric.CommandName,
    'Elektrik Gücü Kullan',
    'keyboard',
    Config.Electric.Key
)

local function PlayShadowBurstOnPed(ped, duration)
    local dict = 'scr_rcbarry2'
    local effect = 'scr_clown_appears'

    LoadPtfx(dict)

    local endTime = GetGameTimer() + duration

    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(ped) do
            UseParticleFxAssetNextCall(dict)
            StartParticleFxNonLoopedOnEntity(effect, ped, 0.0, 0.0, -0.35, 0.0, 0.0, 0.0, 1.05, false, false, false)

            UseParticleFxAssetNextCall(dict)
            StartParticleFxNonLoopedOnEntity(effect, ped, 0.0, 0.0, 0.25, 0.0, 0.0, 0.0, 0.75, false, false, false)

            Wait(210)
        end
    end)
end

local function PlayShadowTrail(ped, duration)
    local dict = 'scr_rcbarry2'
    local effect = 'scr_clown_appears'

    LoadPtfx(dict)

    local endTime = GetGameTimer() + duration

    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(ped) do
            local coords = GetEntityCoords(ped)
            local forward = GetEntityForwardVector(ped)
            local trailCoords = coords - (forward * 0.85)

            UseParticleFxAssetNextCall(dict)
            StartParticleFxNonLoopedAtCoord(effect, trailCoords.x, trailCoords.y, trailCoords.z - 0.65, 0.0, 0.0, 0.0, 0.7, false, false, false)

            Wait(120)
        end
    end)
end

local function PlayShadowWave(ped)
    CreateThread(function()
        local startTime = GetGameTimer()
        local duration = 750

        while GetGameTimer() - startTime < duration and DoesEntityExist(ped) do
            local progress = (GetGameTimer() - startTime) / duration
            local coords = GetEntityCoords(ped)
            local size = 0.45 + (progress * 2.45)
            local alpha = math.floor(115 - (progress * 95))

            DrawMarker(
                1,
                coords.x,
                coords.y,
                coords.z - 1.03,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                size,
                size,
                0.06,
                20,
                0,
                35,
                alpha,
                false,
                false,
                2,
                false,
                nil,
                nil,
                false
            )

            Wait(0)
        end
    end)
end

local function StartShadowTrailLoop()
    CreateThread(function()
        while isShadowForm do
            local ped = PlayerPedId()

            if IsPedSprinting(ped) or IsPedRunning(ped) then
                PlayShadowTrail(ped, 320)
            end

            Wait(380)
        end
    end)
end

local function StartShadowWaveLoop()
    CreateThread(function()
        while isShadowForm do
            local ped = PlayerPedId()

            if IsPedJumping(ped) or IsControlPressed(0, 22) then
                PlayShadowWave(ped)
                Wait(520)
            end

            Wait(80)
        end
    end)
end

local function TryShadowJumpBoost()
    if shadowJumpLock then return end

    local ped = PlayerPedId()

    if not IsPedOnFoot(ped) then return end

    if IsControlJustPressed(0, 22) then
        shadowJumpLock = true

        local forward = GetEntityForwardVector(ped)

        ApplyForceToEntity(
            ped,
            1,
            forward.x * 1.2,
            forward.y * 1.2,
            Config.Shadow.JumpForce,
            0.0,
            0.0,
            0.0,
            0,
            false,
            true,
            true,
            false,
            true
        )

        SetTimeout(700, function()
            shadowJumpLock = false
        end)
    end
end

local function StartLocalShadowBoost()
    local ped = PlayerPedId()

    isShadowForm = true

    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 40, false)
    SetPlayerInvincible(PlayerId(), true)

    StartShadowTrailLoop()
    StartShadowWaveLoop()

    CreateThread(function()
        while isShadowForm do
            ped = PlayerPedId()

            SetRunSprintMultiplierForPlayer(PlayerId(), Config.Shadow.RunMultiplier)
            SetSwimMultiplierForPlayer(PlayerId(), Config.Shadow.RunMultiplier)
            SetPedMoveRateOverride(ped, Config.Shadow.MoveRateOverride)
            SetSuperJumpThisFrame(PlayerId())
            TryShadowJumpBoost()

            Wait(0)
        end

        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        SetSwimMultiplierForPlayer(PlayerId(), 1.0)
        SetPedMoveRateOverride(PlayerPedId(), 1.0)

        SetPlayerInvincible(PlayerId(), false)
        SetEntityVisible(PlayerPedId(), true, false)
        ResetEntityAlpha(PlayerPedId())
    end)
end

RegisterNetEvent('mt-powers:client:startShadowForm', function(casterServerId)
    local player = GetPlayerFromServerId(casterServerId)
    if player == -1 then return end

    local ped = GetPlayerPed(player)
    if not DoesEntityExist(ped) then return end

    PlayShadowBurstOnPed(ped, Config.Shadow.EffectDuration)

    if casterServerId == GetPlayerServerId(PlayerId()) then
        PlayShadowWave(ped)
        StartLocalShadowBoost()
    else
        SetEntityAlpha(ped, 40, false)
    end
end)

RegisterNetEvent('mt-powers:client:stopShadowForm', function(casterServerId)
    local player = GetPlayerFromServerId(casterServerId)
    if player == -1 then return end

    local ped = GetPlayerPed(player)
    if not DoesEntityExist(ped) then return end

    PlayShadowBurstOnPed(ped, Config.Shadow.EffectDuration)
    PlayShadowWave(ped)

    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)

    if casterServerId == GetPlayerServerId(PlayerId()) then
        isShadowForm = false
    end
end)

local function GetClosestTelekinesisTargets()
    local _, aimCoords, entityHit = RayCastGamePlayCamera(Config.Telekinesis.TargetDistance)
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)

    if #(playerCoords - aimCoords) > Config.Telekinesis.TargetDistance + 5.0 then
        return {}
    end

    local candidates = {}

    local function TryAddEntity(entity)
        if not entity or entity == 0 then return end
        if not DoesEntityExist(entity) then return end
        if entity == ped then return end

        local entityType = GetEntityType(entity)

        if entityType == 1 then
            if IsPedAPlayer(entity) and not Config.Telekinesis.EntityTypes.Players then return end
            if not IsPedAPlayer(entity) and not Config.Telekinesis.EntityTypes.Peds then return end
        elseif entityType == 2 then
            if not Config.Telekinesis.EntityTypes.Vehicles then return end
        elseif entityType == 3 then
            if not Config.Telekinesis.EntityTypes.Objects then return end
        else
            return
        end

        local distance = #(GetEntityCoords(entity) - aimCoords)

        if distance <= Config.Telekinesis.SelectRadius then
            NetworkRequestControlOfEntity(entity)

            local netId = NetworkGetNetworkIdFromEntity(entity)

            if netId and netId ~= 0 then
                candidates[#candidates + 1] = {
                    entity = entity,
                    netId = netId,
                    distance = distance
                }
            end
        end
    end

    TryAddEntity(entityHit)

    for _, vehicle in pairs(GetGamePool('CVehicle')) do
        TryAddEntity(vehicle)
    end

    for _, object in pairs(GetGamePool('CObject')) do
        TryAddEntity(object)
    end

    for _, targetPed in pairs(GetGamePool('CPed')) do
        TryAddEntity(targetPed)
    end

    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)

    local selected = {}
    local used = {}

    for _, data in ipairs(candidates) do
        if not used[data.netId] then
            selected[#selected + 1] = data.netId
            used[data.netId] = true

            if #selected >= Config.Telekinesis.MaxTargets then
                break
            end
        end
    end

    return selected
end

local function StartLocalTelekinesisLoop(casterServerId, netIds)
    activeTelekinesis[casterServerId] = {
        netIds = netIds,
        distance = Config.Telekinesis.DefaultHoldDistance
    }

    if casterServerId ~= GetPlayerServerId(PlayerId()) then
        return
    end

    localTelekinesisActive = true
    telekinesisDistance = Config.Telekinesis.DefaultHoldDistance

    CreateThread(function()
        while localTelekinesisActive and activeTelekinesis[casterServerId] do
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)

            if IsDisabledControlJustPressed(0, 14) then
                telekinesisDistance = math.min(
                    Config.Telekinesis.MaxHoldDistance,
                    telekinesisDistance + Config.Telekinesis.ScrollStep
                )
            end

            if IsDisabledControlJustPressed(0, 15) then
                telekinesisDistance = math.max(
                    Config.Telekinesis.MinHoldDistance,
                    telekinesisDistance - Config.Telekinesis.ScrollStep
                )
            end

            local camCoords = GetGameplayCamCoord()
            local camRot = GetGameplayCamRot(2)
            local direction = RotationToDirection(camRot)
            local baseHoldCoords = camCoords + (direction * telekinesisDistance)

            for index, netId in ipairs(netIds) do
                local entity = NetworkGetEntityFromNetworkId(netId)

                if DoesEntityExist(entity) then
                    NetworkRequestControlOfEntity(entity)

                    local offsetX = (index - 2) * 1.6

                    local targetCoords = vector3(
                        baseHoldCoords.x + offsetX,
                        baseHoldCoords.y,
                        baseHoldCoords.z + Config.Telekinesis.HoldHeight
                    )

                    local currentCoords = GetEntityCoords(entity)
                    local diff = targetCoords - currentCoords

                    if GetEntityType(entity) == 1 then
                        SetPedToRagdoll(entity, 1000, 1000, 0, false, false, false)
                    end

                    SetEntityVelocity(
                        entity,
                        diff.x * 4.0,
                        diff.y * 4.0,
                        diff.z * 4.0
                    )

                    ApplyForceToEntity(
                        entity,
                        1,
                        diff.x * Config.Telekinesis.MoveStrength,
                        diff.y * Config.Telekinesis.MoveStrength,
                        diff.z * Config.Telekinesis.MoveStrength + 0.08,
                        0.0,
                        0.0,
                        0.0,
                        0,
                        false,
                        true,
                        true,
                        false,
                        true
                    )
                end
            end

            Wait(0)
        end
    end)
end

local function ThrowLocalTelekinesis(casterServerId)
    local data = activeTelekinesis[casterServerId]

    if not data then return end

    local camRot = GetGameplayCamRot(2)
    local direction = RotationToDirection(camRot)

    for _, netId in ipairs(data.netIds) do
        local entity = NetworkGetEntityFromNetworkId(netId)

        if DoesEntityExist(entity) then
            NetworkRequestControlOfEntity(entity)

            if GetEntityType(entity) == 1 then
                SetPedToRagdoll(entity, 2500, 2500, 0, false, false, false)
            end

            SetEntityVelocity(
                entity,
                direction.x * Config.Telekinesis.ThrowForce,
                direction.y * Config.Telekinesis.ThrowForce,
                direction.z * Config.Telekinesis.ThrowForce + Config.Telekinesis.ThrowUpForce
            )

            ApplyForceToEntity(
                entity,
                1,
                direction.x * Config.Telekinesis.ThrowForce,
                direction.y * Config.Telekinesis.ThrowForce,
                direction.z * Config.Telekinesis.ThrowForce + Config.Telekinesis.ThrowUpForce,
                0.0,
                0.0,
                0.0,
                0,
                false,
                true,
                true,
                false,
                true
            )
        end
    end

    activeTelekinesis[casterServerId] = nil

    if casterServerId == GetPlayerServerId(PlayerId()) then
        localTelekinesisActive = false
    end
end

RegisterNetEvent('mt-powers:client:startTelekinesis', function(casterServerId, netIds)
    StartLocalTelekinesisLoop(casterServerId, netIds)
end)

RegisterNetEvent('mt-powers:client:throwTelekinesis', function(casterServerId)
    ThrowLocalTelekinesis(casterServerId)
end)

RegisterNetEvent('mt-powers:client:stopTelekinesis', function(casterServerId)
    activeTelekinesis[casterServerId] = nil

    if casterServerId == GetPlayerServerId(PlayerId()) then
        localTelekinesisActive = false
    end
end)

RegisterCommand(Config.UsePowerCommand, function()
    local ped = PlayerPedId()

    if IsPedDeadOrDying(ped, true) then return end
    if IsPauseMenuActive() then return end

    if selectedPower == 'shadow' then
        TriggerServerEvent('mt-powers:server:toggleShadowForm')
        return
    end

    if selectedPower == 'telekinesis' then
        if localTelekinesisActive then
            TriggerServerEvent('mt-powers:server:throwTelekinesis')
            return
        end

        local netIds = GetClosestTelekinesisTargets()

        if #netIds <= 0 then
            Notify(Config.Messages.TelekinesisNoTarget, 'error')
            return
        end

        TriggerServerEvent('mt-powers:server:startTelekinesis', netIds)
        return
    end
end, false)

RegisterKeyMapping(
    Config.UsePowerCommand,
    'Seçili Gücü Kullan',
    'keyboard',
    Config.UsePowerKey
)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    SetArtificialLightsState(false)
    SetArtificialLightsStateAffectsVehicles(true)

    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetSwimMultiplierForPlayer(PlayerId(), 1.0)
    SetPedMoveRateOverride(PlayerPedId(), 1.0)

    SetPlayerInvincible(PlayerId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    ResetEntityAlpha(PlayerPedId())

    localTelekinesisActive = false
    activeTelekinesis = {}
end)