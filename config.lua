Config = {}

Config.Debug = false
Config.UseMtUiNotify = true

Config.CyclePowerCommand = 'gucdegistir'
Config.CyclePowerKey = 'RSHIFT'

Config.UsePowerCommand = 'guckullan'
Config.UsePowerKey = 'B'

Config.Powers = {
    { id = 'electric', label = 'Elektrik Gücü' },
    { id = 'shadow', label = 'Gölge Gücü' },
    { id = 'telekinesis', label = 'Telekinezi Gücü' },
    { id = 'illusion', label = 'İllüzyon Gücü' }
}

Config.Electric = {
    CommandName = 'electricblackout',
    Key = 'N',

    TargetDistance = 160.0,
    Radius = 145.0,
    Duration = 30,

    NPCFearRadius = 125.0,

    Effects = {
        EnablePlayerElectricEffect = true,
        PlayerElectricEffectDuration = 2500,
        EnableSparkSound = true,
        SparkSoundInterval = 450
    }
}

Config.Shadow = {
    EffectDuration = 1200,
    RunMultiplier = 1.49,
    MoveRateOverride = 2.35,
    JumpForce = 9.5
}

Config.Telekinesis = {
    TargetDistance = 35.0,
    SelectRadius = 7.0,
    MaxTargets = 3,
    DefaultSelectedTargets = 1,

    DefaultHoldDistance = 9.0,
    MinHoldDistance = 3.0,
    MaxHoldDistance = 25.0,
    ScrollStep = 1.2,

    HoldHeight = 1.2,
    MoveStrength = 0.24,

    ThrowForce = 42.0,
    ThrowUpForce = 5.0,

    Crosshair = {
        Enabled = true,
        ShowTargetText = true,
        Color = { r = 155, g = 90, b = 255, a = 220 },
        TargetColor = { r = 80, g = 255, b = 160, a = 230 }
    },

    EntityTypes = {
        Vehicles = true,
        Objects = false,
        Peds = true,
        Players = true
    }
}

Config.Illusion = {
    MaxClones = 5,
    TargetDistance = 25.0,

    BaseDelay = 450,
    DelayPerClone = 250,

    CloneHealth = 180,
    SmokeDuration = 1200,
    SmokeScale = 1.4,

    ShapeshiftCommand = 'illusionform',
    ShapeshiftKey = 'H',
    ShapeshiftTargetDistance = 12.0
}

Config.Messages = {
    PowerChanged = 'Aktif güç değiştirildi: ',
    TargetTooFar = 'Hedef çok uzakta.',

    ElectricActivated = 'Elektrik akımı bozuldu.',

    ShadowActivated = 'Gölge formuna geçtin.',
    ShadowEnded = 'Gölge formundan çıktın.',

    TelekinesisStarted = 'Telekinezi aktif.',
    TelekinesisThrown = 'Nesneleri fırlattın.',
    TelekinesisStopped = 'Telekinezi bırakıldı.',
    TelekinesisNoTarget = 'Telekinezi için uygun hedef yok.',
    TelekinesisCountChanged = 'Telekinezi hedef sayısı: ',

    IllusionCloneCreated = 'İllüzyon kopyası oluşturuldu.',
    IllusionLimit = 'Daha fazla kopya oluşturamazsın.',
    IllusionNoPlayer = 'Dönüşmek için baktığın yerde oyuncu yok.',
    IllusionShifted = 'İllüzyon formuna büründün.',
    IllusionReverted = 'Normal formuna döndün.'
}
