# schema.ps1 — мои настройки (profile.json) и человеческие подписи облачных настроек для предпросмотра (diff.ps1).
# Подключается из valset.ps1 (dot-source).

$Inv = [Globalization.CultureInfo]::InvariantCulture

function Read-Profile {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои».' 'Your settings are not saved yet — use “Save as mine” first.') }
    Get-Content $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-Profile($prof) {
    Set-Content $ProfilePath (ConvertTo-Json -InputObject $prof -Depth 32 -Compress) -Encoding UTF8
}

function O([string]$label, $value) { [pscustomobject]@{ L = $label; V = $value } }
function New-Setting([hashtable]$h) { [pscustomobject]$h }

$Show = @((O (L 'показывать' 'show') $true), (O (L 'скрыть' 'hide') $false))
# Порядок вариантов как в игре: скрыть / текст / график / текст и график.
$PerfShow = @((O (L 'скрыть' 'hide') 0), (O (L 'текст' 'text') 1), (O (L 'график' 'graph') 2), (O (L 'текст и график' 'text and graph') 3))

# Enum — settingEnum облака; Opts — подписи значений (без них число как есть); Format: pct — доля → %, pct100 — уже в %.
$SettingDefs = @(
    New-Setting @{ Label = (L 'Чувствительность' 'Sensitivity'); Enum = 'EAresFloatSettingName::MouseSensitivity' }
    New-Setting @{ Label = (L 'Снайперский прицел' 'Sniper scope'); Enum = 'EAresBoolSettingName::HoldInputForSniperScopes'
        Opts = @((O (L 'удержание' 'hold') $true), (O (L 'переключение' 'toggle') $false)) }
    New-Setting @{ Label = (L 'Размер миникарты' 'Minimap size'); Enum = 'EAresFloatSettingName::MinimapSize' }
    New-Setting @{ Label = (L 'Кровь' 'Blood'); Enum = 'EAresBoolSettingName::ShowBlood'; Opts = $Show }
    New-Setting @{ Label = (L 'Тела убитых' 'Corpses'); Enum = 'EAresBoolSettingName::ShowCorpses'; Opts = $Show }
    New-Setting @{ Label = (L 'Громкость музыки' 'Music volume'); Enum = 'EAresFloatSettingName::AllMusicOverallVolume'; Format = 'pct' }
    New-Setting @{ Label = (L 'Голосовой чат' 'Voice chat'); Enum = 'EAresIntSettingName::VoiceVolume'; Format = 'pct100' }
    New-Setting @{ Label = 'FPS'; Enum = 'EAresIntSettingName::PlayerPerfShowFrameRate'; Opts = $PerfShow }
    New-Setting @{ Label = (L 'Разброс при стрельбе' 'Firing error'); Enum = 'EAresIntSettingName::PlayerPerfShowFiringErrors'; Opts = $PerfShow }
    New-Setting @{ Label = (L 'Джиттер сети' 'Network jitter'); Enum = 'EAresIntSettingName::PlayerPerfShowNetworkJitter'; Opts = $PerfShow }
    New-Setting @{ Label = (L 'Потеря пакетов' 'Packet loss'); Enum = 'EAresIntSettingName::PlayerPerfShowPacketLossPercentage'; Opts = $PerfShow }
)

function Test-SameValue($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
    $x = 0.0; $y = 0.0
    if ([double]::TryParse("$a", [Globalization.NumberStyles]::Float, $Inv, [ref]$x) -and
        [double]::TryParse("$b", [Globalization.NumberStyles]::Float, $Inv, [ref]$y)) { return [Math]::Abs($x - $y) -lt 0.0001 }
    "$a" -eq "$b"
}
