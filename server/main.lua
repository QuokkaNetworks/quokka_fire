local fireConfig = Config.FireJob or {}

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

local function getPlayerJob(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return nil, nil end
    return player, player.PlayerData.job
end

RegisterNetEvent('quokka_fire:server:toggleDuty', function()
    local src = source
    local player, job = getPlayerJob(src)
    if not player or not job then return end

    if not isConfiguredJob(job.name) then
        exports.qbx_core:Notify(src, 'You are not assigned to this department.', 'error')
        return
    end

    player.Functions.SetJobDuty(not job.onduty)
    exports.qbx_core:Notify(src, player.PlayerData.job.onduty and 'You are now on duty.' or 'You are now off duty.', 'success')
end)

lib.callback.register('quokka_fire:server:canSpawnVehicle', function(source, locationName, garageIndex, modelName)
    local _, job = getPlayerJob(source)
    if not job then
        return false, 'Player data unavailable.'
    end

    if not isConfiguredJob(job.name) then
        return false, 'You are not assigned to this department.'
    end

    if fireConfig.requireOnDuty and fireConfig.requireOnDuty.garage and not job.onduty then
        return false, 'You must be on duty to use the garage.'
    end

    local location = Config.Locations and Config.Locations[locationName]
    local garages = location and location.Vehicles and location.Vehicles.locations
    local garage = garages and garages[garageIndex]

    if not garage then
        return false, 'Garage configuration is invalid.'
    end

    if not canUseLock(garage.jobLock, job.name) then
        return false, 'You do not have access to this garage.'
    end

    local gradeLevel = job.grade and job.grade.level or 0
    local optionsForGrade = getGradeVehicleOptions(garage.Options, gradeLevel)
    local vehicleData = optionsForGrade and optionsForGrade[modelName]

    if not vehicleData then
        return false, 'This vehicle is not available for your grade.'
    end

    return true, vehicleData.category or 'land'
end)
