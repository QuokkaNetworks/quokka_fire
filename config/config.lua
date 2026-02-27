Config = {}

Config.FireJob = {
    jobs = { 'fire' },
    interactKey = 38, -- E
    vehiclePlatePrefix = 'FIRE',
    allowStoreAnyVehicle = false,
    garageBlockRadius = 4.0, -- Spawn blocking radius for fire garage
    pedSpawnDistance = 35.0, -- Distance to spawn optional configured peds
    pedDespawnDistance = 40.0, -- Distance to despawn optional configured peds
    defaultPedScenario = 'WORLD_HUMAN_CLIPBOARD',
    target = {
        enabled = false, -- Requires ox_target or qb-target
        system = 'auto', -- auto / ox / qb
        distance = 2.0,
        debug = false,
        size = {
            x = 1.8,
            y = 1.8,
            z = 2.5,
        },
    },
    requireOnDuty = {
        garage = true,
        cloakroom = false,
    },
}

-- Fire department item list (for inventory/shop integration).
Config.FireItems = {
    { item = 'fire_extinguisher', label = 'Fire Extinguisher', price = 0 },
    { item = 'fire_blanket', label = 'Fire Blanket', price = 0 },
    { item = 'medbag', label = 'Medical Bag', price = 0 },
    { item = 'medikit', label = 'First Aid Kit', price = 0 },
    { item = 'bandage', label = 'Bandage', price = 0 },
    { item = 'radio', label = 'Emergency Radio', price = 0 },
}

Config.Locations = {
    FireHQ = {
        clockInAndOut = {
            enabled = true,
            locations = {
                { coords = vec3(334.75, -580.24, 43.28), jobLock = 'fire' },
                { coords = vec3(349.73, -586.19, 27.80), jobLock = 'fire' },
            },
            label = '[E] - Go On/Off Duty',
            distance = 3.0,
        },

        Cloakroom = {
            Enabled = true,
            locations = {
                {
                    coords = vec3(300.74, -597.77, 42.41),
                    jobLock = 'fire',
                    -- Optional cloakroom ped:
                    -- ped = 's_m_y_fireman_01',
                    -- heading = 70.0,
                    -- scenario = 'WORLD_HUMAN_CLIPBOARD',
                },
            },
            Label = '[E] - Change Clothes',
            HotKey = 38,
            Range = 3.0,
            Uniforms = {
                [1] = {
                    label = 'Firefighter',
                    minGrade = 0,
                    male = {
                        clothing = {
                            { component = 3, drawable = 85, texture = 0 },
                            { component = 4, drawable = 153, texture = 0 },
                            { component = 6, drawable = 24, texture = 0 },
                            { component = 8, drawable = 20, texture = 0 },
                            { component = 10, drawable = 134, texture = 0 },
                            { component = 11, drawable = 423, texture = 0 },
                        },
                        props = {},
                    },
                    female = {
                        clothing = {
                            { component = 11, drawable = 15, texture = 0 },
                            { component = 8, drawable = 58, texture = 0 },
                            { component = 4, drawable = 35, texture = 0 },
                            { component = 6, drawable = 24, texture = 0 },
                            { component = 3, drawable = 15, texture = 0 },
                        },
                        props = {},
                    },
                },
            },
        },

        Vehicles = {
            Enabled = true,
            locations = {
                {
                    Zone = {
                        coords = vec3(316.04, -578.12, 27.80),
                        range = 5.5,
                        label = '[E] - Access Fire Garage',
                        return_label = '[E] - Return Vehicle',
                        heading = 250.76, -- Optional target heading override
                        width = 2.0, -- Optional target width override
                        length = 2.0, -- Optional target length override
                        height = 2.8, -- Optional target height override
                    },
                    Spawn = {
                        land = {
                            coords = vec3(316.04, -578.12, 27.80),
                            heading = 250.76,
                        },
                        air = {
                            coords = vec3(351.85, -587.93, 73.16),
                            heading = 234.72,
                        },
                    },
                    jobLock = 'fire',
                    Options = {
                        [0] = {
                            ['sprinter19'] = { label = 'Fire Rescue Sprinter', category = 'land' },
                            ['sprinter19b'] = { label = 'Fire Command Sprinter', category = 'land' },
                        },
                        [1] = {
                            ['sprinter19'] = { label = 'Fire Rescue Sprinter', category = 'land' },
                            ['sprinter19b'] = { label = 'Fire Command Sprinter', category = 'land' },
                            ['aw139'] = { label = 'Fire Rescue AW139', category = 'air' },
                        },
                        [2] = {
                            ['sprinter19'] = { label = 'Fire Rescue Sprinter', category = 'land' },
                            ['sprinter19b'] = { label = 'Fire Command Sprinter', category = 'land' },
                            ['aw139'] = { label = 'Fire Rescue AW139', category = 'air' },
                        },
                    },
                },
            },
        },
    },
}
