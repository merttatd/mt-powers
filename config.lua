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
    { id = 'telekinesis', label = 'Telekinezi Gücü' }
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

    DefaultHoldDistance = 9.0,
    MinHoldDistance = 3.0,
    MaxHoldDistance = 25.0,
    ScrollStep = 1.2,

    HoldHeight = 1.2,
    MoveStrength = 0.24,

    ThrowForce = 42.0,
    ThrowUpForce = 5.0,

    EntityTypes = {
        Vehicles = true,
        Objects = true,
        Peds = true,
        Players = true
    }
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
    TelekinesisNoTarget = 'Telekinezi için uygun hedef yok.'
}