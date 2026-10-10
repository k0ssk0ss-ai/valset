<#
  VALSET — твои настройки VALORANT на любом аккаунте.

  valset             меню: стрелки или цифры (ярлык: Ctrl+Alt+V); новое окно заменяет старое
  valset save        запомнить настройки текущего аккаунта как мои (-BindsOnly — только бинды)
  valset gfxsave     запомнить только графику (можно при запущенной игре)
  valset apply       перенести мои настройки на текущий аккаунт (всё; -BindsOnly — только бинды)
  valset status      аккаунт, совпадают ли настройки, автоперенос
  valset watch       (служебное) слежение за входом — запускает сторож автопереноса
  valset gfxwait     (служебное) дождаться выхода из игры и записать отложенную графику
  valset install     установить (папка, ярлыки, команда valset) — из собранного valset.cmd
  valset uninstall   убрать программу и ярлыки (мои настройки и бэкапы остаются)

  Применять ДО запуска Valorant: игра берёт настройки из облака при старте.
  Исходники — модули рядом (dot-source); для передачи build.ps1 склеивает всё в dist\valset.cmd.
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'save', 'gfxsave', 'apply', 'status', 'watch', 'gfxwait', 'install', 'uninstall')]
    [string]$Command = 'menu',
    [switch]$BindsOnly,
    [switch]$AfterGame,
    [int]$Interval = 3
)
$ErrorActionPreference = 'Stop'
$Version = '1.0.1'
$script:Fancy = $Command -notin 'watch', 'gfxwait'   # скрытые режимы — без оформления

# Собранный valset.cmd передаёт свой путь через VALSET_FILE; при запуске из исходников — сам .ps1.
$Self        = if ($env:VALSET_FILE) { $env:VALSET_FILE } else { $PSCommandPath }
$Root        = if ($env:VALSET_ROOT) { $env:VALSET_ROOT } else { Join-Path $env:USERPROFILE 'valset' }   # VALSET_ROOT — для тестов
$ProfilePath = Join-Path $Root 'profile.json'   # сырые настройки Ares.PlayerSettings
$SourcePath  = Join-Path $Root 'source.txt'     # PUUID аккаунта, с которого сохранён эталон
$BackupDir   = Join-Path $Root 'backups'
$LogPath     = Join-Path $Root 'valset.log'
$MenuPidPath = Join-Path $Root 'menu.pid'
$InstalledCmd = Join-Path $Root 'valset.cmd'
$Lockfile    = Join-Path $env:LOCALAPPDATA 'Riot Games\Riot Client\Config\lockfile'
$BindKeys    = 'actionMappings', 'axisMappings'
$MenuLnk     = Join-Path ([Environment]::GetFolderPath('Programs')) 'VALSET.lnk'
$LaunchLnk   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'VALORANT (VALSET).lnk'   # WScript.Shell не умеет кириллицу в имени
$LaunchVbs   = Join-Path $Root 'launch.vbs'
$GameProc    = 'VALORANT-Win64-Shipping'
$WatchMutexName = 'Local\valset-watch'
$WatchStopName  = 'Local\valset-watch-stop'

# Язык интерфейса: VALSET_LANG (тесты) → config.json "lang" (выбор в справке) → русский, если в Windows есть
# русский / украинский / белорусский / казахский язык или раскладка, иначе английский. Журнал valset.log — на русском.
function Get-Lang {
    if ($env:VALSET_LANG -in 'ru', 'en') { return $env:VALSET_LANG }
    $cfg = Join-Path $Root 'config.json'
    if (Test-Path $cfg) { try { $l = (Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).lang; if ($l -in 'ru', 'en') { return $l } } catch {} }
    $langs = @((Get-ItemProperty 'HKCU:\Control Panel\International\User Profile' -Name Languages -ErrorAction SilentlyContinue).Languages) +
             @((Get-UICulture).Name)
    if ($langs | Where-Object { $_ -match '^(ru|uk|be|kk)(-|$)' }) { 'ru' } else { 'en' }
}
$script:Lang = Get-Lang
function L([string]$ru, [string]$en) { if ($script:Lang -eq 'en') { $en } else { $ru } }

# Riot переносит сервер настроек — берём актуальный адрес из лога игры, иначе последний известный.
$PrefUrl     = 'https://player-preferences-usw2.pp.sgp.pvp.net/playerPref/v3'
$GameLog     = Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Logs\ShooterGame.log'
if (Test-Path $GameLog) {
    $m = Select-String -Path $GameLog -Pattern 'https://player-preferences[^/\s]*/playerPref/v3' -ErrorAction SilentlyContinue |
        Select-Object -Last 1
    if ($m) { $PrefUrl = $m.Matches[0].Value }
}

. (Join-Path $PSScriptRoot 'ui.ps1')
. (Join-Path $PSScriptRoot 'keys.ps1')
. (Join-Path $PSScriptRoot 'graphics.ps1')
. (Join-Path $PSScriptRoot 'schema.ps1')
. (Join-Path $PSScriptRoot 'crosshair.ps1')
. (Join-Path $PSScriptRoot 'diff.ps1')
. (Join-Path $PSScriptRoot 'backups.ps1')
. (Join-Path $PSScriptRoot 'guest.ps1')
. (Join-Path $PSScriptRoot 'accounts.ps1')
. (Join-Path $PSScriptRoot 'agent.ps1')
. (Join-Path $PSScriptRoot 'menu.ps1')
. (Join-Path $PSScriptRoot 'pros.ps1')
. (Join-Path $PSScriptRoot 'more.ps1')
. (Join-Path $PSScriptRoot 'install.ps1')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# У локального клиента Riot самоподписанный сертификат — доверяем ему только для 127.0.0.1.
# Компиляция C# стоит ~130 мс, поэтому сборка кешируется в DLL и дальше просто подгружается.
if (-not ('RiotLocalCert' -as [type])) {
    $certSrc = @'
using System.Net; using System.Net.Security;
public static class RiotLocalCert {
    public static void Install() {
        ServicePointManager.ServerCertificateValidationCallback = (s, c, ch, e) => {
            if (e == SslPolicyErrors.None) return true;
            var r = s as HttpWebRequest;
            return r != null && r.RequestUri.Host == "127.0.0.1";
        };
    }
}
'@
    $certDll = Join-Path $Root 'cache\riotcert-1.dll'
    try {
        if (-not (Test-Path $certDll)) {
            New-Item -ItemType Directory -Force (Split-Path $certDll) | Out-Null
            Add-Type -TypeDefinition $certSrc -OutputAssembly $certDll -OutputType Library
        }
        if (-not ('RiotLocalCert' -as [type])) { Add-Type -Path $certDll }
    } catch {
        Add-Type -TypeDefinition $certSrc
    }
}
[RiotLocalCert]::Install()

function Log([string]$msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $msg
    if (-not $script:Fancy) { Write-Host $line }
    New-Item -ItemType Directory -Force $Root | Out-Null
    Add-Content $LogPath $line -Encoding UTF8
}

function Short([string]$puuid) { if ($puuid) { $puuid.Substring(0, 8) } else { '-' } }

# ── Riot: локальный клиент и облако настроек ─────────────────────────────────

# Текущая сессия клиента: $null, если клиент закрыт или вход не выполнен.
function Get-Session {
    if (-not (Test-Path $Lockfile)) { return $null }
    try {
        $fs = [IO.File]::Open($Lockfile, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs); $raw = $sr.ReadToEnd(); $sr.Close()
    } catch { return $null }
    $p = $raw.Split(':')   # name:pid:port:password:protocol
    if ($p.Count -lt 5) { return $null }
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("riot:$($p[3])"))
    try {
        $t = Invoke-RestMethod "https://127.0.0.1:$($p[2])/entitlements/v1/token" `
            -Headers @{ Authorization = "Basic $auth" } -TimeoutSec 5
    } catch { return $null }
    if (-not $t.subject -or -not $t.accessToken) { return $null }
    [pscustomobject]@{ Puuid = $t.subject; Token = $t.accessToken; Entitlement = $t.token; ClientPid = $p[1]; Port = $p[2]; Auth = "Basic $auth" }
}

function Connect-Session {
    Invoke-Step (L 'Подключение к клиенту Riot' 'Connecting to the Riot Client') {
        $s = Get-Session
        if (-not $s) { throw $(if (Get-Process 'RiotClientServices' -ErrorAction SilentlyContinue) { L 'Войди в аккаунт в клиенте Riot.' 'Log into an account in the Riot Client.' } else { L 'Клиент Riot не запущен — открой его и войди в аккаунт.' 'The Riot Client is not running — open it and log in.' }) }
        $null = Register-Account $s
        $s
    }
}

# Облако хранит настройки как base64(raw deflate(JSON)).
function Expand-Pref([string]$b64) {
    $ms = New-Object IO.MemoryStream(, [Convert]::FromBase64String($b64))
    $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
    $sr = New-Object IO.StreamReader($ds, [Text.Encoding]::UTF8)
    $s = $sr.ReadToEnd(); $sr.Close(); $s
}

function Compress-Pref([string]$json) {
    $ms = New-Object IO.MemoryStream
    $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Compress)
    $b = [Text.Encoding]::UTF8.GetBytes($json); $ds.Write($b, 0, $b.Length); $ds.Close()
    [Convert]::ToBase64String($ms.ToArray())
}

function Get-Headers($s) { @{ Authorization = "Bearer $($s.Token)"; 'X-Riot-Entitlements-JWT' = $s.Entitlement } }

function Get-Settings($s) {
    $r = Invoke-RestMethod "$PrefUrl/getPreference/Ares.PlayerSettings" -Headers (Get-Headers $s) -TimeoutSec 15
    if (-not $r.data) { throw (L 'Облако вернуло пустые настройки (аккаунт ни разу не заходил в Valorant?).' 'The cloud returned empty settings (has this account never played VALORANT?).') }
    $json = Expand-Pref $r.data
    Register-Actions $json
    $json
}

function Set-Settings($s, [string]$json) {
    $body = @{ type = 'Ares.PlayerSettings'; data = (Compress-Pref $json) } | ConvertTo-Json -Compress
    Invoke-RestMethod "$PrefUrl/savePreference" -Method Put -Headers (Get-Headers $s) `
        -Body $body -ContentType 'application/json' -TimeoutSec 15 | Out-Null
}

function Get-Source { if (Test-Path $SourcePath) { (Get-Content $SourcePath -Raw).Trim() } }

function Get-JsonPart($obj, [string]$key) { ConvertTo-Json -InputObject $obj.$key -Depth 32 -Compress }

# ── Эталон: сохранить / применить ────────────────────────────────────────────

# Эталон меняется только здесь и в редакторе — по явному действию.
function Invoke-Save($s) {
    if (-not $s) { $s = Connect-Session }
    if ($script:Fancy -and (Test-Path $ProfilePath)) {
        $q = if (Test-NotMain $s) { L 'Всё равно запомнить настройки отсюда?' 'Save settings from here anyway?' } else { L "Заменить твои настройки настройками $(Get-AccountLabel $s.Puuid)?" "Replace your settings with those of $(Get-AccountLabel $s.Puuid)?" }
        if (-not (Confirm-Key $q)) { Write-Note (L 'отменено' 'cancelled'); return }
    }
    $json = Invoke-Step (L 'Чтение настроек из облака Riot' 'Reading settings from the Riot cloud') { Get-Settings $s }
    Invoke-Step (L 'Запись на диск' 'Writing to disk') {
        $null = $json | ConvertFrom-Json   # проверка, что это валидный JSON
        New-Item -ItemType Directory -Force $Root | Out-Null
        New-HistoryPoint (L 'до «Запомнить как мои → всё»' 'before “Save as mine → all”')
        Set-Content $ProfilePath $json -Encoding UTF8
        Set-Content $SourcePath $s.Puuid -Encoding ASCII
    }
    $gfx = Invoke-Step (L 'Снимок графики с этого ПК' 'Snapshot of this PC''s graphics') { Save-Graphics $s.Puuid }
    Log "мои настройки запомнены с аккаунта $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' (+ графика)' })"
    if ($script:Fancy) {
        Write-Ok (L "Твои настройки запомнены с аккаунта $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' вместе с графикой' })" "Your settings saved from $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' including graphics' })")
        if (-not $gfx) { Write-Note (L 'графику не нашёл: этот аккаунт ещё не запускал игру на этом ПК' 'no graphics found: this account has not run the game on this PC yet') }
    }
    if ($gfx) { Write-QualityNote; Sync-Graphics $s.Puuid }
}

function Invoke-Apply($s, [switch]$BindsOnly, [switch]$Permanent) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои».' 'Your settings are not saved yet — use “Save as mine” first.') }
    if (-not $s) { $s = Connect-Session }
    $profJson = Get-Content $ProfilePath -Raw -Encoding UTF8

    $curJson = Invoke-Step (L 'Чтение текущих настроек аккаунта' 'Reading the account''s current settings') { Get-Settings $s }
    $cur = $curJson | ConvertFrom-Json
    $prof = $profJson | ConvertFrom-Json
    $new = $prof
    if ($BindsOnly) {
        $new = $curJson | ConvertFrom-Json
        foreach ($k in $BindKeys) {
            if ($prof.PSObject.Properties[$k]) { $new | Add-Member -NotePropertyName $k -NotePropertyValue $prof.$k -Force }
        }
    }

    # Стандарт — на время: исходные сохраним и вернём после игры (guest.ps1). Основной и «мои» — насовсем.
    $temp = -not $Permanent -and (Test-TempDefault $s.Puuid)
    # Прицелы: на время — только твои; насовсем — прицелы аккаунта не стираем, дописываем твой.
    $kept = if ($BindsOnly) { 0 } else { Join-Crosshairs $cur $new $temp }

    # Предпросмотр: что поменяется. В меню — с подтверждением; автоматика пишет без вопросов.
    $same = Test-PrefsEqual $cur $new
    if (-not $same) {
        $diff = Compare-Prefs $cur $new -BindsOnly:$BindsOnly
        if ($script:Fancy) {
            Show-Diff $diff
            if (-not $diff.Count) { Write-Note (L 'отличия только служебные (профили прицела, агентские бинды и т. п.)' 'only internal differences (crosshair profiles, agent binds, etc.)') }
            if ($script:CrosshairDropped) { Write-Note (L "в игре максимум $CrosshairMax прицелов: $($script:CrosshairDropped) прицел(а) аккаунта не влезут и пропадут" "the game allows $CrosshairMax crosshairs max: $($script:CrosshairDropped) of this account's crosshair(s) won't fit and will be lost") }
            if (-not (Confirm-Key (L 'Применить?' 'Apply?'))) { Write-Note (L 'отменено, аккаунт не тронут' 'cancelled, account untouched'); return }
        }
        $bk = Invoke-Step (L 'Резервная копия' 'Backup') { New-Backup $s $curJson }
        Invoke-Step (L 'Запись в облако Riot' 'Writing to the Riot cloud') { Set-Settings $s (ConvertTo-Json -InputObject $new -Depth 32 -Compress) }
        Invoke-Step (L 'Проверка записи' 'Verifying') {
            $check = Get-Settings $s | ConvertFrom-Json
            $keys  = if ($BindsOnly) { $BindKeys } else { $BindKeys + 'floatSettings' + 'intSettings' }
            foreach ($k in $keys) {
                if ((Get-JsonPart $check $k) -ne (Get-JsonPart $prof $k)) { throw "в облаке '$k' не совпадает с твоими настройками" }
            }
        }
        if ($temp) { Save-TempOriginal $s.Puuid $curJson }
    }

    $gameRunning = [bool](Get-Process $GameProc -ErrorAction SilentlyContinue)
    $gfx = 0
    if (-not $BindsOnly -and (Test-GraphicsSaved)) { $gfx = Invoke-ApplyGraphics $s.Puuid }

    $what = if ($BindsOnly) { L 'Бинды' 'Binds' } else { L 'Все настройки' 'All settings' }
    $state = if ($same) { L 'уже совпадали с твоими' 'already matched yours' } else { L 'перенесены и проверены' 'applied and verified' }
    $script:LastApply = @{ Temp = ($temp -and (Test-Temp $s.Puuid)); Same = $same; Count = $(if ($same) { 0 } else { [Math]::Max(1, @($diff).Count) }) }
    if ($BindsOnly) { Set-AccountState $s.Puuid @{ applied = (Get-Stamp) } }
    else { Set-AccountState $s.Puuid @{ state = 'same'; diff = 0; checked = (Get-Stamp); applied = (Get-Stamp) } }
    Log "$what → $(Get-AccountLabel $s.Puuid): $state$(if (-not $same) { " ($($diff.Count) изм., бэкап $(Split-Path $bk -Leaf))" })"
    if ($gameRunning -and -not $same) { Log 'игра уже запущена: изменения будут после перезапуска Valorant' }
    if ($script:Fancy) {
        Write-Ok "$what $(L 'на аккаунте' 'on') $(Get-AccountLabel $s.Puuid): $state"
        if ($kept) { Write-Note (L "прицелы аккаунта не тронуты ($kept шт.), активный — твой" "the account's crosshairs kept ($kept), active one is yours") }
        if ($gfx -gt 0) { Write-Ok (L 'Графика этого ПК записана' 'This PC''s graphics written') }
        if ($gfx -lt 0) { Write-Note (L 'графика применится сама, когда закроешь игру' 'graphics will be applied once you close the game') }
        if ($gameRunning -and -not $same) { Write-Note (L 'игра запущена — облачные настройки появятся после её перезапуска' 'the game is running — cloud settings take effect after restarting it') }
        if ($temp -and (Test-Temp $s.Puuid)) { Write-TempNote }
    }
}

# Бэкап настроек аккаунта перед записью; хранятся последние 30.
function New-Backup($s, [string]$json) {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $path = Join-Path $BackupDir ('{0}_{1:yyyyMMdd-HHmmss}.json' -f (Short $s.Puuid), (Get-Date))
    Set-Content $path $json -Encoding UTF8
    Get-ChildItem $BackupDir -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -SkipLast 30 | Remove-Item
    $path
}

# Только графика эталона — с текущего аккаунта. Работает и при запущенной игре: она пишет файлы сразу после смены настроек.
function Invoke-SaveGraphics($s) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои» → всё.' 'Your settings are not saved yet — use “Save as mine → all” first.') }
    if (-not $s) { $s = Connect-Session }
    $q = if (Test-NotMain $s) { L 'Всё равно запомнить графику отсюда?' 'Save graphics from here anyway?' } else { L "Заменить твою графику графикой аккаунта $(Get-AccountLabel $s.Puuid)?" "Replace your graphics with those of $(Get-AccountLabel $s.Puuid)?" }
    if ($script:Fancy -and -not (Confirm-Key $q)) { Write-Note (L 'отменено' 'cancelled'); return }
    New-HistoryPoint (L 'до «Запомнить → графику»' 'before “Save → graphics”')
    $ok = Invoke-Step (L 'Снимок графики с этого ПК' 'Snapshot of this PC''s graphics') { Save-Graphics $s.Puuid }
    if (-not $ok) { throw (L 'Графику не нашёл: этот аккаунт ещё не запускал игру на этом ПК.' 'No graphics found: this account has not run the game on this PC yet.') }
    Log "графика запомнена с аккаунта $(Get-AccountLabel $s.Puuid)"
    if ($script:Fancy) { Write-Ok "$(L 'Графика запомнена с аккаунта' 'Graphics saved from') $(Get-AccountLabel $s.Puuid)"; Write-QualityNote }
    Sync-Graphics $s.Puuid
}

# «Запомнить» не с основного аккаунта: предупредить — так легко затереть свои настройки чужими. $true — не основной.
function Test-NotMain($s) {
    $main = Get-MainPuuid
    if (-not $script:Fancy -or -not $main -or $main -eq $s.Puuid -or -not (Test-Path $ProfilePath)) { return $false }
    Write-Note (L "это не основной аккаунт: $(Get-AccountLabel $s.Puuid) (основной — $(Get-AccountLabel $main))" "this is not your main account: $(Get-AccountLabel $s.Puuid) (main — $(Get-AccountLabel $main))")
    $true
}

# Только бинды текущего аккаунта → в эталон; остальные настройки эталона не трогаются.
function Invoke-SaveBinds($s) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Твои настройки ещё не запомнены — сначала «Запомнить как мои» → всё.' 'Your settings are not saved yet — use “Save as mine → all” first.') }
    if (-not $s) { $s = Connect-Session }
    $acc = Invoke-Step (L 'Чтение биндов из облака Riot' 'Reading binds from the Riot cloud') { Get-Settings $s | ConvertFrom-Json }
    $p = Read-Profile
    $new = $p | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    foreach ($k in $BindKeys) { $new | Add-Member -NotePropertyName $k -NotePropertyValue $acc.$k -Force }
    $diff = Compare-Prefs $p $new -BindsOnly
    if ((Get-JsonPart $p 'actionMappings') -eq (Get-JsonPart $new 'actionMappings') -and (Get-JsonPart $p 'axisMappings') -eq (Get-JsonPart $new 'axisMappings')) {
        if ($script:Fancy) { Write-Ok (L "Твои бинды уже как на аккаунте $(Get-AccountLabel $s.Puuid)" "Your binds already match $(Get-AccountLabel $s.Puuid)") }
        return
    }
    if ($script:Fancy) {
        $null = Test-NotMain $s
        Show-Diff $diff
        if (-not $diff.Count) { Write-Note (L 'отличия только в агентских биндах или осях' 'differences only in agent binds or axes') }
        if (-not (Confirm-Key (L "Запомнить бинды аккаунта $(Get-AccountLabel $s.Puuid) как мои?" "Save the binds of $(Get-AccountLabel $s.Puuid) as mine?"))) { Write-Note (L 'отменено' 'cancelled'); return }
    }
    New-HistoryPoint (L 'до «Запомнить → бинды»' 'before “Save → binds”')
    Save-Profile $new
    Log "бинды запомнены с аккаунта $(Get-AccountLabel $s.Puuid) ($($diff.Count) изм.)"
    if ($script:Fancy) { Write-Ok (L "Бинды запомнены с аккаунта $(Get-AccountLabel $s.Puuid), остальное не тронуто" "Binds saved from $(Get-AccountLabel $s.Puuid), everything else untouched") }
}

function Write-QualityNote {
    $odd = Get-QualityOddities
    if (-not $odd) { return }
    Log "незнакомые значения качества: $($odd -join ', ')"
    if ($script:Fancy) { Write-Note "незнакомые значения качества ($($odd -join ', ')) — Riot могли поменять шкалу, проверь в игре" }
}

try {
    switch ($Command) {
        'menu'      { Invoke-InstallOffer; Show-Menu }
        'save'      { Write-Screen (L 'ЗАПОМНИТЬ КАК МОИ' 'SAVE AS MINE'); if ($BindsOnly) { Invoke-SaveBinds } else { Invoke-Save } }
        'gfxsave'   { Write-Screen (L 'ЗАПОМНИТЬ: ГРАФИКУ' 'SAVE: GRAPHICS'); Invoke-SaveGraphics }
        'apply'     { Write-Screen (L 'ПЕРЕНОС МОИХ НАСТРОЕК' 'APPLY MY SETTINGS'); Invoke-Apply -BindsOnly:$BindsOnly }
        'status'    { Write-Banner; Write-State (Get-MenuState) }
        'watch'     { Invoke-Watch -AfterGame:$AfterGame }
        'gfxwait'   { Invoke-GfxWait }
        'install'   { Invoke-Install }
        'uninstall' { Invoke-Uninstall }
    }
} catch {
    Log "ошибка: $($_.Exception.Message)"
    if ($script:Fancy) { Write-Fail $_.Exception.Message }
    exit 1
}
