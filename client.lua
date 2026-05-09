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
local selectedTelekinesisCount = Config.Telekinesis.DefaultSelectedTargets or 1

local illusionClones = {}
local illusionHistory = {}

local isIllusionShifted = false
local originalAppearance = nil
local illusionLastHealth = nil

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
            StartParticleFxNonLoopedOnEntity('ent_dst_elec_fire_sp', ped, 0.0, 0.0, 0.2, 0.0, 0.0, 0.0, 2.2, false, false, false)

            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntity('ent_dst_elec_fire_sp', ped, 0.35, 0.0, 0.65, 0.0, 0.0, 0.0, 1.7, false, false, false)

            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedOnEntity('ent_dst_elec_fire_sp', ped, -0.35, 0.0, 0.65, 0.0, 0.0, 0.0, 1.7, false, false, false)

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
                SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
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
            TriggerEvent('mt-powers:client:notify', 'Havada yoğun bir elektriklenme hissediyorsun...', 'inform')
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
                    TaskSmartFleeCoord(ped, coords.x, coords.y, coords.z, radius + 80.0, 45000, false, false)
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
    if selectedPower ~= 'electric' then return end

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

local function DrawTelekinesisCrosshair()
    if not Config.Telekinesis.Crosshair.Enabled then return end
    if selectedPower ~= 'telekinesis' then return end

    local color = Config.Telekinesis.Crosshair.Color
    local targetColor = Config.Telekinesis.Crosshair.Color

    local _, _, entityHit = RayCastGamePlayCamera(Config.Telekinesis.TargetDistance)

    if entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        targetColor = Config.Telekinesis.Crosshair.TargetColor

        local coords = GetEntityCoords(entityHit)

        DrawMarker(
            2,
            coords.x,
            coords.y,
            coords.z + 1.2,
            0.0, 0.0, 0.0,
            0.0, 180.0, 0.0,
            0.35,
            0.35,
            0.35,
            targetColor.r,
            targetColor.g,
            targetColor.b,
            targetColor.a,
            false,
            true,
            2,
            false,
            nil,
            nil,
            false
        )
    end

    DrawRect(0.5, 0.5, 0.006, 0.0015, targetColor.r, targetColor.g, targetColor.b, targetColor.a)
    DrawRect(0.5, 0.5, 0.0015, 0.006, targetColor.r, targetColor.g, targetColor.b, targetColor.a)

    if Config.Telekinesis.Crosshair.ShowTargetText then
        SetTextFont(4)
        SetTextScale(0.32, 0.32)
        SetTextColour(255, 255, 255, 220)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(('Telekinezi Hedef: %s'):format(selectedTelekinesisCount))
        EndTextCommandDisplayText(0.5, 0.535)
    end
end

CreateThread(function()
    while true do
        if selectedPower == 'telekinesis' then
            Wait(0)
            DrawTelekinesisCrosshair()
        else
            Wait(400)
        end
    end
end)

local function SetTelekinesisCount(count)
    if selectedPower ~= 'telekinesis' then return end

    count = tonumber(count) or 1

    if count < 1 then count = 1 end
    if count > Config.Telekinesis.MaxTargets then count = Config.Telekinesis.MaxTargets end

    selectedTelekinesisCount = count

    Notify(Config.Messages.TelekinesisCountChanged .. tostring(selectedTelekinesisCount), 'inform')
end

RegisterCommand('tkcount1', function()
    SetTelekinesisCount(1)
end, false)

RegisterCommand('tkcount2', function()
    SetTelekinesisCount(2)
end, false)

RegisterCommand('tkcount3', function()
    SetTelekinesisCount(3)
end, false)

RegisterKeyMapping('tkcount1', 'Telekinezi Hedef Sayısı 1', 'keyboard', '1')
RegisterKeyMapping('tkcount2', 'Telekinezi Hedef Sayısı 2', 'keyboard', '2')
RegisterKeyMapping('tkcount3', 'Telekinezi Hedef Sayısı 3', 'keyboard', '3')

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

        -- Sadece ped / player / araç
        if entityType == 1 then
            if IsPedAPlayer(entity) and not Config.Telekinesis.EntityTypes.Players then return end
            if not IsPedAPlayer(entity) and not Config.Telekinesis.EntityTypes.Peds then return end
        elseif entityType == 2 then
            if not Config.Telekinesis.EntityTypes.Vehicles then return end
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

            if #selected >= selectedTelekinesisCount then
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

                    SetEntityVelocity(entity, diff.x * 4.0, diff.y * 4.0, diff.z * 4.0)

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

local function PlayCloneSmoke(coords)
    local dict = 'scr_rcbarry2'
    local effect = 'scr_clown_appears'

    LoadPtfx(dict)

    local endTime = GetGameTimer() + Config.Illusion.SmokeDuration

    CreateThread(function()
        while GetGameTimer() < endTime do
            UseParticleFxAssetNextCall(dict)

            StartParticleFxNonLoopedAtCoord(
                effect,
                coords.x,
                coords.y,
                coords.z - 0.4,
                0.0,
                0.0,
                0.0,
                Config.Illusion.SmokeScale,
                false,
                false,
                false
            )

            Wait(160)
        end
    end)
end

local function RemoveIllusionClone(index)
    local data = illusionClones[index]
    if not data then return end

    if DoesEntityExist(data.ped) then
        local coords = GetEntityCoords(data.ped)
        PlayCloneSmoke(coords)

        SetEntityAsMissionEntity(data.ped, true, true)
        DeleteEntity(data.ped)
    end

    table.remove(illusionClones, index)
end

local function SavePedAppearance(ped)
    local appearance = {
        components = {},
        props = {},
        hairColor = {},
        eyeColor = GetPedEyeColor(ped)
    }

    for i = 0, 11 do
        appearance.components[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end

    for i = 0, 7 do
        appearance.props[i] = {
            index = GetPedPropIndex(ped, i),
            texture = GetPedPropTextureIndex(ped, i)
        }
    end

    local hairColor, hairHighlight = GetPedHairColor(ped)
    appearance.hairColor = {
        color = hairColor,
        highlight = hairHighlight
    }

    return appearance
end

local function ApplyPedAppearance(ped, appearance)
    if not appearance then return end

    for i = 0, 11 do
        local component = appearance.components[i]

        if component then
            SetPedComponentVariation(
                ped,
                i,
                component.drawable,
                component.texture,
                component.palette
            )
        end
    end

    for i = 0, 7 do
        local prop = appearance.props[i]

        if prop then
            if prop.index ~= -1 then
                SetPedPropIndex(
                    ped,
                    i,
                    prop.index,
                    prop.texture,
                    true
                )
            else
                ClearPedProp(ped, i)
            end
        end
    end

    if appearance.hairColor then
        SetPedHairColor(ped, appearance.hairColor.color or 0, appearance.hairColor.highlight or 0)
    end

    if appearance.eyeColor then
        SetPedEyeColor(ped, appearance.eyeColor)
    end
end

local function ClonePlayerAppearance(sourcePed, clonePed)
    SetEntityHealth(clonePed, Config.Illusion.CloneHealth)
    SetPedArmour(clonePed, 0)

    local appearance = SavePedAppearance(sourcePed)
    ApplyPedAppearance(clonePed, appearance)
end

local function SpawnIllusionClone()
    if #illusionClones >= Config.Illusion.MaxClones then
        Notify(Config.Messages.IllusionLimit, 'error')
        return
    end

    local playerPed = PlayerPedId()
    local _, coords = RayCastGamePlayCamera(Config.Illusion.TargetDistance)

    local model = GetEntityModel(playerPed)

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end

    local clone = CreatePed(
        4,
        model,
        coords.x,
        coords.y,
        coords.z,
        GetEntityHeading(playerPed),
        true,
        true
    )

    ClonePlayerAppearance(playerPed, clone)

    SetEntityAsMissionEntity(clone, true, true)
    SetBlockingOfNonTemporaryEvents(clone, true)
    SetPedCanRagdoll(clone, true)
    SetPedFleeAttributes(clone, 0, false)
    SetPedCombatAttributes(clone, 46, true)
    SetEntityInvincible(clone, false)

    table.insert(illusionClones, {
        ped = clone,
        lastHealth = GetEntityHealth(clone),
        delay = Config.Illusion.BaseDelay + (#illusionClones * Config.Illusion.DelayPerClone)
    })

    Notify(Config.Messages.IllusionCloneCreated, 'success')
end

local function GetTargetPlayerPedForIllusion()
    local _, _, entityHit = RayCastGamePlayCamera(Config.Illusion.ShapeshiftTargetDistance)

    if entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) and IsPedAPlayer(entityHit) then
        return entityHit
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestPed = nil
    local closestDistance = Config.Illusion.ShapeshiftTargetDistance

    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)

        if targetPed ~= playerPed and DoesEntityExist(targetPed) then
            local distance = #(GetEntityCoords(targetPed) - playerCoords)

            if distance < closestDistance then
                closestDistance = distance
                closestPed = targetPed
            end
        end
    end

    return closestPed
end

local function RevertIllusionForm()
    if not isIllusionShifted then return end

    local ped = PlayerPedId()

    ApplyPedAppearance(ped, originalAppearance)

    isIllusionShifted = false
    originalAppearance = nil
    illusionLastHealth = nil

    PlayCloneSmoke(GetEntityCoords(ped))
    Notify(Config.Messages.IllusionReverted, 'inform')
end

local function ShapeshiftToTargetPlayer()
    if selectedPower ~= 'illusion' then return end

    if isIllusionShifted then
        RevertIllusionForm()
        return
    end

    local ped = PlayerPedId()
    local targetPed = GetTargetPlayerPedForIllusion()

    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
        Notify(Config.Messages.IllusionNoPlayer, 'error')
        return
    end

    originalAppearance = SavePedAppearance(ped)
    local targetAppearance = SavePedAppearance(targetPed)

    PlayCloneSmoke(GetEntityCoords(ped))
    ApplyPedAppearance(ped, targetAppearance)

    isIllusionShifted = true
    illusionLastHealth = GetEntityHealth(ped)

    Notify(Config.Messages.IllusionShifted, 'success')
end

RegisterCommand(Config.Illusion.ShapeshiftCommand, function()
    ShapeshiftToTargetPlayer()
end, false)

RegisterKeyMapping(
    Config.Illusion.ShapeshiftCommand,
    'İllüzyon: Başka Oyuncuya Dönüş',
    'keyboard',
    Config.Illusion.ShapeshiftKey
)

CreateThread(function()
    while true do
        if isIllusionShifted then
            local ped = PlayerPedId()
            local currentHealth = GetEntityHealth(ped)

            if illusionLastHealth and currentHealth < illusionLastHealth then
                RevertIllusionForm()
            else
                illusionLastHealth = currentHealth
            end

            Wait(250)
        else
            Wait(800)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(100)

        local ped = PlayerPedId()

        table.insert(illusionHistory, {
            time = GetGameTimer(),
            coords = GetEntityCoords(ped),
            heading = GetEntityHeading(ped),
            running = IsPedRunning(ped) or IsPedSprinting(ped),
            walking = IsPedWalking(ped),
            jumping = IsPedJumping(ped),
            shooting = IsPedShooting(ped)
        })

        while #illusionHistory > 80 do
            table.remove(illusionHistory, 1)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)

        for i = #illusionClones, 1, -1 do
            local data = illusionClones[i]
            local clone = data.ped

            if not DoesEntityExist(clone) then
                table.remove(illusionClones, i)
            else
                local currentHealth = GetEntityHealth(clone)

                if IsEntityDead(clone) or currentHealth < data.lastHealth then
                    RemoveIllusionClone(i)
                else
                    data.lastHealth = currentHealth

                    local targetTime = GetGameTimer() - data.delay
                    local selectedState = nil

                    for h = #illusionHistory, 1, -1 do
                        if illusionHistory[h].time <= targetTime then
                            selectedState = illusionHistory[h]
                            break
                        end
                    end

                    if selectedState then
                        SetEntityHeading(clone, selectedState.heading)

                        if selectedState.running then
                            TaskGoStraightToCoord(
                                clone,
                                selectedState.coords.x,
                                selectedState.coords.y,
                                selectedState.coords.z,
                                3.0,
                                500,
                                selectedState.heading,
                                0.0
                            )
                        elseif selectedState.walking then
                            TaskGoStraightToCoord(
                                clone,
                                selectedState.coords.x,
                                selectedState.coords.y,
                                selectedState.coords.z,
                                1.0,
                                500,
                                selectedState.heading,
                                0.0
                            )
                        else
                            TaskStandStill(clone, 300)
                        end

                        if selectedState.jumping then
                            TaskJump(clone, true)
                        end

                        if selectedState.shooting then
                            local forward = GetEntityForwardVector(clone)
                            local cloneCoords = GetEntityCoords(clone)

                            TaskShootAtCoord(
                                clone,
                                cloneCoords.x + forward.x * 10.0,
                                cloneCoords.y + forward.y * 10.0,
                                cloneCoords.z + 0.8,
                                500,
                                GetHashKey('FIRING_PATTERN_FULL_AUTO')
                            )
                        end
                    end
                end
            end
        end
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

    if selectedPower == 'illusion' then
        SpawnIllusionClone()
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

    if isIllusionShifted then
        ApplyPedAppearance(PlayerPedId(), originalAppearance)
    end

    localTelekinesisActive = false
    activeTelekinesis = {}

    for i = #illusionClones, 1, -1 do
        if DoesEntityExist(illusionClones[i].ped) then
            DeleteEntity(illusionClones[i].ped)
        end
    end

    illusionClones = {}
    illusionHistory = {}
end)
