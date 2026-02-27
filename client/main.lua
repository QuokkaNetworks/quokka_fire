local fireConfig = Config.FireJob or {}

local promptId, promptText
local savedCivilianOutfit
local spawnedVehiclePlates = {}
local spawnedPeds = {}
local pedControllers = {}
local targetZones = {}

local dutyPoints = {}
local cloakroomPoints = {}
local garagePoints = {}

local useTarget = false
local targetSystem

local function notify(message, notifyType)
    if exports.qbx_core then
        exports.qbx_core:Notify(message, notifyType or 'inform')
        return
    end

    lib.notify({
        description = message,
        type = notifyType or 'inform',
    })
end

local function trim(value)
    return (value or ''):gsub('%s+', '')
end

local function normalizePlate(plate)
    return trim(string.upper(plate or ''))
end

local function tableContains(tbl, value)
    if type(tbl) ~= 'table' then return false end

    for key, entry in pairs(tbl) do
        if key == value or entry == value then
            return true
        end
    end

    return false
end

local function getAllowedJobs()
    if type(fireConfig.jobs) == 'table' and next(fireConfig.jobs) ~= nil then
        return fireConfig.jobs
    end

    return { 'fire' }
end

local function isConfiguredJob(jobName)
    if not jobName then return false end
    return tableContains(getAllowedJobs(), jobName)
end

local function canUseLock(jobLock, jobName)
    if jobLock == nil or jobLock == false then
        return true
    end

    if type(jobLock) == 'string' then
        return jobLock == jobName
    end

    if type(jobLock) == 'table' then
        return tableContains(jobLock, jobName)
    end

    return false
end

local function getCurrentJob()
    return QBX and QBX.PlayerData and QBX.PlayerData.job or nil
end

local function isLoggedIn()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn
end

local function showPrompt(id, text)
    if promptId == id and promptText == text then
        return
    end

    if promptId then
        lib.hideTextUI()
    end

    lib.showTextUI(text)
    promptId = id
    promptText = text
end

local function hidePrompt()
    if not promptId then return end
    lib.hideTextUI()
    promptId = nil
    promptText = nil
end

local function snapshotOutfit(ped)
    local outfit = {
        model = GetEntityModel(ped),
        clothing = {},
        props = {}
    }

    for component = 0, 11 do
        outfit.clothing[#outfit.clothing + 1] = {
            component = component,
            drawable = GetPedDrawableVariation(ped, component),
            texture = GetPedTextureVariation(ped, component),
            palette = GetPedPaletteVariation(ped, component),
        }
    end

    for prop = 0, 7 do
        local drawable = GetPedPropIndex(ped, prop)
        outfit.props[#outfit.props + 1] = {
            component = prop,
            drawable = drawable,
            texture = drawable >= 0 and GetPedPropTextureIndex(ped, prop) or 0,
        }
    end

    return outfit
end

local function applyOutfit(ped, outfit)
    if not outfit then return false end

    if outfit.model and outfit.model ~= GetEntityModel(ped) then
        return false
    end

    for _, part in ipairs(outfit.clothing or {}) do
        SetPedComponentVariation(
            ped,
            part.component or 0,
            part.drawable or 0,
            part.texture or 0,
            part.palette or 0
        )
    end

    for prop = 0, 7 do
        ClearPedProp(ped, prop)
    end

    for _, prop in ipairs(outfit.props or {}) do
        if (prop.drawable or -1) >= 0 then
            SetPedPropIndex(
                ped,
                prop.component or 0,
                prop.drawable or 0,
                prop.texture or 0,
                true
            )
        end
    end

    return true
end

local function resolveUniformVariant(uniform)
    if type(uniform) ~= 'table' then return nil end

    local ped = cache.ped or PlayerPedId()
    local model = GetEntityModel(ped)

    if model == `mp_m_freemode_01` then
        return uniform.male or uniform.female
    end

    if model == `mp_f_freemode_01` then
        return uniform.female or uniform.male
    end

    return uniform.male or uniform.female
end

local function restoreCivilianOutfit()
    local ped = cache.ped or PlayerPedId()

    if not savedCivilianOutfit then
        notify('No civilian outfit has been saved yet.', 'error')
        return
    end

    if not applyOutfit(ped, savedCivilianOutfit) then
        notify('Could not restore the saved outfit because your player model changed.', 'error')
    end
end

local function wearUniform(uniform)
    local ped = cache.ped or PlayerPedId()
    local variant = resolveUniformVariant(uniform)

    if not variant then
        notify('No compatible uniform is configured for this ped model.', 'error')
        return
    end

    if not savedCivilianOutfit then
        savedCivilianOutfit = snapshotOutfit(ped)
    end

    applyOutfit(ped, variant)
end

local function gradeAllowsUniform(minGrade, jobGrade)
    if minGrade == false or minGrade == nil then return true end
    return (jobGrade or 0) >= (tonumber(minGrade) or 0)
end

local function sortedNumericKeys(tbl)
    local keys = {}

    for key in pairs(tbl or {}) do
        local numeric = tonumber(key)
        if numeric then
            keys[#keys + 1] = numeric
        end
    end

    table.sort(keys)
    return keys
end

local function getGradeVehicleOptions(options, gradeLevel)
    if type(options) ~= 'table' then return {} end

    local currentGrade = tonumber(gradeLevel) or 0

    if type(options[currentGrade]) == 'table' then
        return options[currentGrade]
    end

    if type(options[currentGrade + 1]) == 'table' then
        return options[currentGrade + 1]
    end

    local keys = sortedNumericKeys(options)
    local bestKey

    for _, key in ipairs(keys) do
        if key <= currentGrade then
            bestKey = key
        end
    end

    if bestKey and type(options[bestKey]) == 'table' then
        return options[bestKey]
    end

    if keys[1] and type(options[keys[1]]) == 'table' then
        return options[keys[1]]
    end

    return {}
end

local function randomPlate()
    local prefix = string.upper((fireConfig.vehiclePlatePrefix or 'FIRE'):gsub('[^%w]', ''))
    prefix = prefix:sub(1, 4)
    local value = math.random(0, 9999)
    return string.format('%-4s%04d', prefix, value)
end

local function tryGiveKeys(plate)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    TriggerEvent('qb-vehiclekeys:client:AddKeys', plate)
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
end

local function isSpawnBlocked(coords)
    local radius = fireConfig.garageBlockRadius or 4.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - coords) <= radius then
            return true
        end
    end
    return false
end

local function storeCurrentVehicle()
    local ped = cache.ped or PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        notify('You are not in a vehicle.', 'error')
        return
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('Only the driver can store this vehicle.', 'error')
        return
    end

    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not fireConfig.allowStoreAnyVehicle and not spawnedVehiclePlates[plate] then
        notify('This vehicle was not spawned from this garage.', 'error')
        return
    end

    spawnedVehiclePlates[plate] = nil
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)

    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end

    notify('Vehicle stored.', 'success')
end

local function spawnVehicle(point, modelName, vehicleData)
    local approved, categoryOrError = lib.callback.await(
        'quokka_fire:server:canSpawnVehicle',
        false,
        point.locationName,
        point.garageIndex,
        modelName
    )

    if not approved then
        notify(categoryOrError or 'You are not authorized to take this vehicle.', 'error')
        return
    end

    local category = vehicleData.category or categoryOrError or 'land'
    local spawnPoint = point.spawn and point.spawn[category]

    if not spawnPoint or not spawnPoint.coords then
        notify(('No %s spawn point configured for this garage.'):format(category), 'error')
        return
    end

    if isSpawnBlocked(spawnPoint.coords) then
        notify('Spawn point is blocked.', 'error')
        return
    end

    local modelHash = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(modelHash) then
        notify('Vehicle model is not valid on this server.', 'error')
        return
    end

    if not lib.requestModel(modelHash, 10000) then
        notify('Vehicle model could not be loaded.', 'error')
        return
    end

    local heading = spawnPoint.heading or 0.0
    local vehicle = CreateVehicle(modelHash, spawnPoint.coords.x, spawnPoint.coords.y, spawnPoint.coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(modelHash)

    if vehicle == 0 then
        notify('Vehicle spawn failed.', 'error')
        return
    end

    local plate = randomPlate()
    local normalizedPlate = normalizePlate(plate)
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleOnGroundProperly(vehicle)

    spawnedVehiclePlates[normalizedPlate] = true
    tryGiveKeys(plate)

    local ped = cache.ped or PlayerPedId()
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
end

local function openCloakroom(point, job)
    local gradeLevel = job.grade and job.grade.level or 0
    local options = {
        {
            title = 'Civilian Clothes',
            description = 'Switch back to your previously saved outfit.',
            onSelect = restoreCivilianOutfit
        }
    }

    local keys = sortedNumericKeys(point.uniforms)
    for _, key in ipairs(keys) do
        local uniform = point.uniforms[key]
        if uniform and gradeAllowsUniform(uniform.minGrade, gradeLevel) then
            options[#options + 1] = {
                title = uniform.label or ('Uniform %s'):format(key),
                onSelect = function()
                    wearUniform(uniform)
                end
            }
        end
    end

    if #options == 1 then
        notify('No uniforms are configured for your grade.', 'error')
        return
    end

    lib.registerContext({
        id = 'quokka_fire_cloakroom',
        title = 'Fire Cloakroom',
        options = options
    })

    lib.showContext('quokka_fire_cloakroom')
end

local function openGarage(point, job)
    local gradeLevel = job.grade and job.grade.level or 0
    local gradeVehicles = getGradeVehicleOptions(point.options, gradeLevel)
    local options = {}

    for modelName, vehicleData in pairs(gradeVehicles) do
        if type(vehicleData) == 'table' then
            options[#options + 1] = {
                title = vehicleData.label or modelName,
                description = ('Category: %s'):format(vehicleData.category or 'land'),
                onSelect = function()
                    spawnVehicle(point, modelName, vehicleData)
                end
            }
        end
    end

    if #options == 0 then
        notify('No vehicles are configured for your grade.', 'error')
        return
    end

    table.sort(options, function(a, b)
        return a.title < b.title
    end)

    lib.registerContext({
        id = 'quokka_fire_garage',
        title = 'Fire Garage',
        options = options
    })

    lib.showContext('quokka_fire_garage')
end

local function deletePedById(id)
    local ped = spawnedPeds[id]
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
    spawnedPeds[id] = nil
end

local function clearSpawnedPeds()
    for id in pairs(spawnedPeds) do
        deletePedById(id)
    end
end

local function stopPedControllers()
    for id, controller in pairs(pedControllers) do
        controller.active = false
        pedControllers[id] = nil
    end
end

local function startPedController(id, pedData)
    if not pedData or not pedData.model or not pedData.coords or pedControllers[id] then
        return
    end

    pedControllers[id] = { active = true }

    CreateThread(function()
        local spawnDistance = fireConfig.pedSpawnDistance or 35.0
        local despawnDistance = fireConfig.pedDespawnDistance or (spawnDistance + 5.0)
        local controller = pedControllers[id]

        while controller and controller.active do
            local playerPed = cache.ped or PlayerPedId()
            if not isLoggedIn() or not DoesEntityExist(playerPed) then
                deletePedById(id)
                Wait(1000)
            else
                local distance = #(GetEntityCoords(playerPed) - pedData.coords)
                if distance <= spawnDistance and not spawnedPeds[id] then
                    local modelHash = type(pedData.model) == 'number' and pedData.model or joaat(pedData.model)
                    if IsModelInCdimage(modelHash) and lib.requestModel(modelHash, 10000) then
                        local ped = CreatePed(4, modelHash, pedData.coords.x, pedData.coords.y, pedData.coords.z, pedData.heading or 0.0, false, false)
                        SetModelAsNoLongerNeeded(modelHash)
                        if ped ~= 0 then
                            FreezeEntityPosition(ped, true)
                            SetEntityInvincible(ped, true)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            if pedData.scenario then
                                TaskStartScenarioInPlace(ped, pedData.scenario, 0, true)
                            end
                            spawnedPeds[id] = ped
                        end
                    end
                elseif distance >= despawnDistance and spawnedPeds[id] then
                    deletePedById(id)
                end
                Wait(distance <= spawnDistance and 500 or 1000)
            end
            controller = pedControllers[id]
        end

        deletePedById(id)
        pedControllers[id] = nil
    end)
end

local function getTargetSystem()
    local cfg = fireConfig.target or {}
    if not cfg.enabled then
        return nil
    end

    if cfg.system == 'ox' and GetResourceState('ox_target') == 'started' then
        return 'ox'
    end

    if cfg.system == 'qb' and GetResourceState('qb-target') == 'started' then
        return 'qb'
    end

    if cfg.system and cfg.system ~= 'auto' then
        return nil
    end

    if GetResourceState('ox_target') == 'started' then
        return 'ox'
    end

    if GetResourceState('qb-target') == 'started' then
        return 'qb'
    end

    return nil
end

local function clearTargetZones()
    for i = #targetZones, 1, -1 do
        local zone = targetZones[i]
        if zone.system == 'ox' and GetResourceState('ox_target') == 'started' then
            pcall(function()
                exports.ox_target:removeZone(zone.id)
            end)
        elseif zone.system == 'qb' and GetResourceState('qb-target') == 'started' then
            pcall(function()
                exports['qb-target']:RemoveZone(zone.id)
            end)
        end
    end
    targetZones = {}
end

local function canInteractPoint(kind, point)
    if not isLoggedIn() then return false end

    local job = getCurrentJob()
    if not job or not job.name or not isConfiguredJob(job.name) then
        return false
    end

    if not canUseLock(point.jobLock, job.name) then
        return false
    end

    if kind == 'garage' and fireConfig.requireOnDuty and fireConfig.requireOnDuty.garage and not job.onduty then
        return false
    end

    if kind == 'cloakroom' and fireConfig.requireOnDuty and fireConfig.requireOnDuty.cloakroom and not job.onduty then
        return false
    end

    return true
end

local function getTargetDefaults()
    local target = fireConfig.target or {}
    local size = target.size or {}

    return {
        width = size.x or 1.8,
        length = size.y or 1.8,
        height = size.z or 2.5,
        distance = target.distance or 2.0,
        debug = target.debug or false,
    }
end

local function handlePointInteraction(point, job)
    if point.kind == 'duty' then
        TriggerServerEvent('quokka_fire:server:toggleDuty')
        return
    end

    if point.kind == 'cloakroom' then
        openCloakroom(point.data, job)
        return
    end

    if point.kind == 'garage' then
        local ped = cache.ped or PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            storeCurrentVehicle()
            return
        end

        openGarage(point.data, job)
    end
end

local function onTargetInteract(kind, point)
    if not canInteractPoint(kind, point) then return end
    local job = getCurrentJob()
    if not job then return end

    handlePointInteraction({ kind = kind, data = point }, job)
end

local function addTargetZone(kind, point)
    if not useTarget or not targetSystem then return end

    local defaults = getTargetDefaults()
    local width = point.targetWidth or defaults.width
    local length = point.targetLength or defaults.length
    local height = point.targetHeight or defaults.height
    local heading = point.targetHeading or 0.0
    local distance = point.targetDistance or defaults.distance
    local label = point.targetLabel or point.label
    local icon = kind == 'duty' and 'fa-solid fa-user-check'
        or (kind == 'cloakroom' and 'fa-solid fa-shirt' or 'fa-solid fa-truck')

    if targetSystem == 'ox' then
        local zoneId = exports.ox_target:addBoxZone({
            coords = point.coords,
            size = vec3(width, length, height),
            rotation = heading,
            debug = defaults.debug,
            options = {
                {
                    name = point.id,
                    icon = icon,
                    label = label,
                    onSelect = function()
                        onTargetInteract(kind, point)
                    end,
                    canInteract = function()
                        return canInteractPoint(kind, point)
                    end,
                }
            }
        })

        targetZones[#targetZones + 1] = { system = 'ox', id = zoneId }
        return
    end

    local zoneName = ('quokka_fire_%s'):format(point.id)
    exports['qb-target']:AddBoxZone(
        zoneName,
        point.coords,
        length,
        width,
        {
            name = zoneName,
            heading = heading,
            debugPoly = defaults.debug,
            minZ = point.coords.z - (height / 2.0),
            maxZ = point.coords.z + (height / 2.0),
        },
        {
            options = {
                {
                    icon = icon,
                    label = label,
                    action = function()
                        onTargetInteract(kind, point)
                    end,
                    canInteract = function()
                        return canInteractPoint(kind, point)
                    end,
                }
            },
            distance = distance,
        }
    )

    targetZones[#targetZones + 1] = { system = 'qb', id = zoneName }
end

local function getPromptForPoint(point)
    if point.kind ~= 'garage' then
        return point.data.label
    end

    local ped = cache.ped or PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return point.data.returnLabel
    end

    return point.data.label
end

local function applyEntryTargetSettings(point, entry)
    if type(entry) ~= 'table' or type(entry.target) ~= 'table' then return end

    local target = entry.target
    point.targetLabel = target.label
    point.targetHeading = target.heading
    point.targetWidth = target.width
    point.targetLength = target.length
    point.targetHeight = target.height
    point.targetDistance = target.distance
end

local function refreshTargetMode()
    targetSystem = getTargetSystem()
    useTarget = targetSystem ~= nil
end

local function registerInteractionPoints()
    dutyPoints = {}
    cloakroomPoints = {}
    garagePoints = {}

    clearTargetZones()
    stopPedControllers()
    clearSpawnedPeds()
    refreshTargetMode()

    for locationName, location in pairs(Config.Locations or {}) do
        local duty = location.clockInAndOut
        if duty and duty.enabled then
            for index, entry in ipairs(duty.locations or {}) do
                if entry.coords then
                    local point = {
                        id = ('duty_%s_%d'):format(locationName, index),
                        coords = entry.coords,
                        radius = duty.distance or 2.5,
                        label = duty.label or '[E] - Go On/Off Duty',
                        jobLock = entry.jobLock,
                    }
                    applyEntryTargetSettings(point, entry)
                    dutyPoints[#dutyPoints + 1] = point

                    if entry.ped then
                        startPedController(point.id, {
                            model = entry.ped,
                            coords = entry.coords,
                            heading = entry.heading or 0.0,
                            scenario = entry.scenario or fireConfig.defaultPedScenario,
                        })
                    end
                end
            end
        end

        local cloakroom = location.Cloakroom
        if cloakroom and cloakroom.Enabled then
            for index, entry in ipairs(cloakroom.locations or {}) do
                if entry.coords then
                    local point = {
                        id = ('cloak_%s_%d'):format(locationName, index),
                        coords = entry.coords,
                        radius = cloakroom.Range or 2.5,
                        label = cloakroom.Label or '[E] - Change Clothes',
                        jobLock = entry.jobLock,
                        uniforms = cloakroom.Uniforms or {},
                    }
                    applyEntryTargetSettings(point, entry)
                    cloakroomPoints[#cloakroomPoints + 1] = point

                    if entry.ped then
                        startPedController(point.id, {
                            model = entry.ped,
                            coords = entry.coords,
                            heading = entry.heading or 0.0,
                            scenario = entry.scenario or fireConfig.defaultPedScenario,
                        })
                    end
                end
            end
        end

        local garages = location.Vehicles
        if garages and garages.Enabled then
            for garageIndex, garage in ipairs(garages.locations or {}) do
                if garage.Zone and garage.Zone.coords then
                    local point = {
                        id = ('garage_%s_%d'):format(locationName, garageIndex),
                        locationName = locationName,
                        garageIndex = garageIndex,
                        coords = garage.Zone.coords,
                        radius = garage.Zone.range or 5.0,
                        label = garage.Zone.label or '[E] - Access Garage',
                        returnLabel = garage.Zone.return_label or '[E] - Return Vehicle',
                        jobLock = garage.jobLock,
                        spawn = garage.Spawn or {},
                        options = garage.Options or {},
                        targetHeading = garage.Zone.heading,
                        targetWidth = garage.Zone.width,
                        targetLength = garage.Zone.length,
                        targetHeight = garage.Zone.height,
                    }
                    garagePoints[#garagePoints + 1] = point
                end
            end
        end
    end

    if useTarget then
        for _, point in ipairs(dutyPoints) do
            addTargetZone('duty', point)
        end

        for _, point in ipairs(cloakroomPoints) do
            addTargetZone('cloakroom', point)
        end

        for _, point in ipairs(garagePoints) do
            addTargetZone('garage', point)
        end
    end
end

local function findClosestPoint(job, playerCoords)
    local closestPoint
    local closestDistance
    local requireGarageDuty = fireConfig.requireOnDuty and fireConfig.requireOnDuty.garage
    local requireCloakroomDuty = fireConfig.requireOnDuty and fireConfig.requireOnDuty.cloakroom

    if not isConfiguredJob(job.name) then
        return nil
    end

    for _, point in ipairs(dutyPoints) do
        if canUseLock(point.jobLock, job.name) then
            local distance = #(playerCoords - point.coords)
            if distance <= point.radius and (not closestDistance or distance < closestDistance) then
                closestPoint = {
                    kind = 'duty',
                    data = point,
                    distance = distance
                }
                closestDistance = distance
            end
        end
    end

    for _, point in ipairs(cloakroomPoints) do
        if canUseLock(point.jobLock, job.name) and (not requireCloakroomDuty or job.onduty) then
            local distance = #(playerCoords - point.coords)
            if distance <= point.radius and (not closestDistance or distance < closestDistance) then
                closestPoint = {
                    kind = 'cloakroom',
                    data = point,
                    distance = distance
                }
                closestDistance = distance
            end
        end
    end

    for _, point in ipairs(garagePoints) do
        if canUseLock(point.jobLock, job.name) and (not requireGarageDuty or job.onduty) then
            local distance = #(playerCoords - point.coords)
            if distance <= point.radius and (not closestDistance or distance < closestDistance) then
                closestPoint = {
                    kind = 'garage',
                    data = point,
                    distance = distance
                }
                closestDistance = distance
            end
        end
    end

    return closestPoint
end

CreateThread(function()
    registerInteractionPoints()

    while true do
        if useTarget then
            hidePrompt()
            Wait(1000)
        elseif not isLoggedIn() then
            hidePrompt()
            Wait(1000)
        else
            local job = getCurrentJob()
            if not job or not job.name then
                hidePrompt()
                Wait(500)
            else
                local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())
                local point = findClosestPoint(job, playerCoords)

                if point then
                    local text = getPromptForPoint(point)
                    showPrompt(point.data.id, text)

                    if IsControlJustReleased(0, fireConfig.interactKey or 38) then
                        handlePointInteraction(point, job)
                        Wait(300)
                    else
                        Wait(0)
                    end
                else
                    hidePrompt()
                    Wait(250)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hidePrompt()
    clearTargetZones()
    stopPedControllers()
    clearSpawnedPeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    hidePrompt()
    savedCivilianOutfit = nil
end)

RegisterNetEvent('QBCore:Client:SetDuty', function()
    hidePrompt()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    hidePrompt()
end)
