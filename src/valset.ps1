<#
  VALSET — твои настройки VALORANT на любом аккаунте.

  valset             меню: стрелки или цифры (ярлык «VALSET» в Пуске); новое окно заменяет старое
  valset pros / more консольное меню сразу на этом экране
  valset list <pros|accounts|backups|history|diff|code:КОД|pro:НИК|loadouts|loadout:ID|skins|skin:СПЕЦ|collections|collection:ID|coll:ID> списки для панели приложения (одна строка JSON)
  valset lib         (для приложения) только загрузить функции: Invoke-Core state|list|do|watch → строка JSON, без exit
  valset state       (для приложения) состояние одной строкой JSON
  valset do ДЕЙСТВИЕ (для приложения) apply|binds|applyperm|save|savebinds|untemp|undo|gfxsave|share[:skins]|code:КОД|pro:НИК|restore:ID|history:ID|set:КЛЮЧ=ЗНАЧЕНИЕ|account:PUUID:ДЕЙСТВИЕ|loadout:…|skin:…|coll:ID — без вопросов, ответ JSON
  valset save        сохранить настройки текущего аккаунта как мои (-BindsOnly — только бинды)
  valset gfxsave     сохранить только графику (можно при запущенной игре)
  valset apply       перенести мои настройки на текущий аккаунт (всё; -BindsOnly — только бинды)
  valset status      аккаунт, совпадают ли настройки, автоперенос
  valset watch       (служебное) слежение за входом — запускает сторож автопереноса
  valset gfxwait     (служебное) дождаться выхода из игры и записать отложенную графику
  valset install     установить (папка, ярлыки, команда valset) — из собранного valset.cmd
  valset uninstall   убрать программу и ярлыки (мои настройки и бэкапы остаются)

  Переносить до запуска VALORANT: игра берёт настройки из облака при старте.
  Исходники — модули рядом (dot-source); для передачи build.ps1 склеивает всё в dist\valset.cmd.
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'save', 'gfxsave', 'apply', 'status', 'watch', 'gfxwait', 'install', 'uninstall', 'state', 'do', 'pros', 'more', 'list', 'lib')]
    [string]$Command = 'menu',
    [Parameter(Position = 1)]
    [string]$Action = '',
    [switch]$BindsOnly,
    [switch]$AfterGame,
    [switch]$Yes,
    [int]$Interval = 3
)
$ErrorActionPreference = 'Stop'
$Version = '2.1.0'
$script:Fancy = $Command -notin 'watch', 'gfxwait', 'state', 'do', 'list', 'lib'   # скрытые режимы — без оформления
$script:Quiet = $Command -in 'state', 'do', 'list', 'lib'   # stdout этих команд — ровно одна строка JSON: журнал на экран не пишем
$script:Lib = $Command -eq 'lib'   # режим библиотеки: только функции (приложение держит ядро в своём runspace, зовёт Invoke-Core), без exit и вопросов

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
. (Join-Path $PSScriptRoot 'cloud.ps1')
. (Join-Path $PSScriptRoot 'keys.ps1')
. (Join-Path $PSScriptRoot 'graphics.ps1')
. (Join-Path $PSScriptRoot 'schema.ps1')
. (Join-Path $PSScriptRoot 'crosshair.ps1')
. (Join-Path $PSScriptRoot 'diff.ps1')
. (Join-Path $PSScriptRoot 'backups.ps1')
. (Join-Path $PSScriptRoot 'guest.ps1')
. (Join-Path $PSScriptRoot 'accounts.ps1')
. (Join-Path $PSScriptRoot 'agent.ps1')
. (Join-Path $PSScriptRoot 'session.ps1')
. (Join-Path $PSScriptRoot 'menu.ps1')
. (Join-Path $PSScriptRoot 'pros.ps1')
. (Join-Path $PSScriptRoot 'codes.ps1')
. (Join-Path $PSScriptRoot 'codec.ps1')
. (Join-Path $PSScriptRoot 'codeparts.ps1')
. (Join-Path $PSScriptRoot 'share.ps1')
. (Join-Path $PSScriptRoot 'loadout.ps1')
. (Join-Path $PSScriptRoot 'sets.ps1')
. (Join-Path $PSScriptRoot 'skins.ps1')
. (Join-Path $PSScriptRoot 'collections.ps1')
. (Join-Path $PSScriptRoot 'range.ps1')
. (Join-Path $PSScriptRoot 'shareskins.ps1')
. (Join-Path $PSScriptRoot 'more.ps1')
. (Join-Path $PSScriptRoot 'do.ps1')
. (Join-Path $PSScriptRoot 'doextra.ps1')
. (Join-Path $PSScriptRoot 'report.ps1')
. (Join-Path $PSScriptRoot 'lists.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'app.ps1')
. (Join-Path $PSScriptRoot 'install.ps1')
. (Join-Path $PSScriptRoot 'update.ps1')

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
    if (-not $script:Fancy -and -not $script:Quiet) { Write-Host $line }
    New-Item -ItemType Directory -Force $Root | Out-Null
    Add-Content $LogPath $line -Encoding UTF8
}

# Запись через временный файл + замена: сбой посередине не оставит битый файл (эталон, аккаунты, исходные).
function Write-FileSafe([string]$path, [string]$text) {
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)   # .NET не знает текущую папку PowerShell
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $true))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
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
    Invoke-Step (L 'Подключаюсь к клиенту Riot' 'Connecting to the Riot Client') {
        $s = Get-Session
        if (-not $s) { throw $(if (Get-Process 'RiotClientServices' -ErrorAction SilentlyContinue) { L 'Войди в аккаунт в клиенте Riot.' 'Log into an account in the Riot Client.' } else { L 'Клиент Riot не запущен. Открой его и войди в аккаунт.' 'The Riot Client is not running. Open it and log in.' }) }
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

function Test-GameRunning { [bool](Get-Process $GameProc -ErrorAction SilentlyContinue) }

function Get-Source { if (Test-Path $SourcePath) { (Get-Content $SourcePath -Raw).Trim() } }

function Get-JsonPart($obj, [string]$key) { ConvertTo-Json -InputObject $obj.$key -Depth 32 -Compress }

# ── Эталон: сохранить / применить ────────────────────────────────────────────

# Эталон меняется по явному действию («Сохранить») и сам — правками из игры на аккаунтах с твоими настройками.
function Invoke-Save($s) {
    if (-not $s) { $s = Connect-Session }
    if ($script:Fancy -and (Test-Path $ProfilePath)) {
        $q = if (Test-NotMain $s) { L 'Всё равно сохранить настройки отсюда?' 'Save settings from here anyway?' } else { L "Заменить твои настройки настройками $(Get-AccountLabel $s.Puuid)?" "Replace your settings with those of $(Get-AccountLabel $s.Puuid)?" }
        if (-not (Confirm-Key $q)) { Write-Note (L 'Отменено' 'Cancelled'); return }
    }
    $json = Invoke-Step (L 'Читаю настройки' 'Reading the settings') { Get-Settings $s }
    Invoke-Step (L 'Сохраняю на ПК' 'Saving on this PC') {
        $null = $json | ConvertFrom-Json   # проверка, что это валидный JSON
        New-Item -ItemType Directory -Force $Root | Out-Null
        Save-UndoPoint 'profile' $s.Puuid
        New-HistoryPoint (L 'до «Сохранить → всё»' 'before “Save → all”')
        Write-FileSafe $ProfilePath $json
        Write-FileSafe $SourcePath $s.Puuid
        Set-SessionBase $s.Puuid $json   # дальше правки в игре здесь попадут в эталон сами
    }
    $gfx = Invoke-Step (L 'Сохраняю графику' 'Saving graphics') { Save-Graphics $s.Puuid }
    Log "мои настройки запомнены с аккаунта $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' (+ графика)' })"
    $script:LastOp = if ($gfx) { 'gfx' } else { 'done' }
    if ($script:Fancy) {
        Write-Ok (L "Твои настройки сохранены с аккаунта $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' вместе с графикой' })" "Your settings saved from $(Get-AccountLabel $s.Puuid)$(if ($gfx) { ' including graphics' })")
        if (-not $gfx) { Write-Note (L 'Графики нет: этот аккаунт ещё не запускал игру на этом ПК' 'No graphics: this account has not run the game on this PC yet') }
    }
    if ($gfx) { Write-QualityNote; Sync-Graphics $s.Puuid }
}

function Invoke-Apply($s, [switch]$BindsOnly, [switch]$Permanent) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Сначала сохрани свои настройки: «Сохранить».' 'Save your settings first: “Save”.') }
    if (-not $s) { $s = Connect-Session }

    $curJson = Invoke-Step (L 'Читаю настройки аккаунта' 'Reading the account settings') { Get-Settings $s }
    # правки в игре на этом аккаунте — сначала в эталон, иначе перенос их бы затёр
    $synced = Update-Reference $s $curJson
    if ($synced.Count -and $script:Fancy) { Write-Ok "$(L 'В твои настройки добавлено из игры' 'Added to your settings from the game'): $(Format-Changed $synced)" }
    $profJson = Get-Content $ProfilePath -Raw -Encoding UTF8
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
            if (-not $diff.Count) { Write-Note (L 'Отличий почти нет (мелочи вроде профилей прицела)' 'Almost no differences (small things like crosshair profiles)') }
            if ($script:CrosshairDropped) { Write-Note (L "В игре максимум $CrosshairMax прицелов, лишние прицелы аккаунта удалятся: $($script:CrosshairDropped)" "The game allows $CrosshairMax crosshairs max, extra crosshairs of this account will be deleted: $($script:CrosshairDropped)") }
            if (-not (Confirm-Key (L 'Перенести?' 'Apply?'))) { Write-Note (L 'Отменено, аккаунт не изменён' 'Cancelled, account unchanged'); return }
        }
        # Игра держит свою копию настроек и при их смене в игре пишет её в облако целиком — поверх нашей. Ждём выхода.
        if (Test-GameRunning) {
            $script:LastApply = @{ Queued = $true }
            Request-CloudAfterExit $s.Puuid $(if ($BindsOnly) { 'binds' } elseif ($Permanent) { 'perm' } else { 'apply' })
            if ($script:Fancy) { Write-Note (L 'Игра запущена. Перенесу, когда ты её закроешь (в этом же аккаунте)' 'The game is running. Will apply once you close it (on this same account)') }
            return
        }
        Save-UndoPoint 'account' $s.Puuid $curJson
        $bk = Invoke-Step (L 'Делаю бэкап' 'Backup') { New-Backup $s $curJson }
        if ($temp) { Save-TempOriginal $s.Puuid $curJson }   # до записи: упадёт посередине — исходные всё равно вернутся
        $newJson = ConvertTo-Json -InputObject $new -Depth 32 -Compress
        Invoke-Step (L 'Записываю настройки' 'Writing the settings') { Set-Settings $s $newJson }
        Invoke-Step (L 'Проверяю запись' 'Verifying') { Assert-Written $s $newJson (L 'перенос' 'apply') }
    }
    Set-SessionBase $s.Puuid $(if ($same) { $curJson } else { $newJson }) $(if ($BindsOnly) { 'binds' } else { 'all' })

    $gameRunning = Test-GameRunning
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
        if ($kept) { Write-Note (L "Прицелы аккаунта остались ($kept), активный твой" "The account's crosshairs kept ($kept), the active one is yours") }
        if ($gfx -gt 0) { Write-Ok (L 'Графика этого ПК записана' 'This PC''s graphics written') }
        if ($gfx -lt 0) { Write-Note (L 'Графика перенесётся сама, когда закроешь игру' 'Graphics will be applied once you close the game') }
        if ($gameRunning -and -not $same) { Write-Note (L 'Игра запущена: настройки появятся после её перезапуска' 'The game is running: settings take effect after restarting it') }
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
    if (-not (Test-Path $ProfilePath)) { throw (L 'Сначала сохрани свои настройки: «Сохранить» → «Всё».' 'Save your settings first: “Save → All”.') }
    if (-not $s) { $s = Connect-Session }
    $q = if (Test-NotMain $s) { L 'Всё равно сохранить графику отсюда?' 'Save graphics from here anyway?' } else { L "Заменить твою графику графикой аккаунта $(Get-AccountLabel $s.Puuid)?" "Replace your graphics with those of $(Get-AccountLabel $s.Puuid)?" }
    if ($script:Fancy -and -not (Confirm-Key $q)) { Write-Note (L 'Отменено' 'Cancelled'); return }
    New-HistoryPoint (L 'до «Сохранить → графику»' 'before “Save → graphics”')
    $ok = Invoke-Step (L 'Сохраняю графику' 'Saving graphics') { Save-Graphics $s.Puuid }
    if (-not $ok) { throw (L 'Графику не нашёл: этот аккаунт ещё не запускал игру на этом ПК.' 'No graphics found: this account has not run the game on this PC yet.') }
    Log "графика запомнена с аккаунта $(Get-AccountLabel $s.Puuid)"
    if ($script:Fancy) { Write-Ok "$(L 'Графика сохранена с аккаунта' 'Graphics saved from') $(Get-AccountLabel $s.Puuid)"; Write-QualityNote }
    Sync-Graphics $s.Puuid
}

# «Сохранить» не с основного аккаунта: предупредить — так легко затереть свои настройки чужими. $true — не основной.
function Test-NotMain($s) {
    $main = Get-MainPuuid
    if (-not $script:Fancy -or -not $main -or $main -eq $s.Puuid -or -not (Test-Path $ProfilePath)) { return $false }
    Write-Note (L "Это не основной аккаунт: $(Get-AccountLabel $s.Puuid) (основной: $(Get-AccountLabel $main))" "This is not your main account: $(Get-AccountLabel $s.Puuid) (main: $(Get-AccountLabel $main))")
    $true
}

# Только бинды текущего аккаунта → в эталон; остальные настройки эталона не трогаются.
function Invoke-SaveBinds($s) {
    if (-not (Test-Path $ProfilePath)) { throw (L 'Сначала сохрани свои настройки: «Сохранить» → «Всё».' 'Save your settings first: “Save → All”.') }
    if (-not $s) { $s = Connect-Session }
    $acc = Invoke-Step (L 'Читаю бинды' 'Reading binds') { Get-Settings $s | ConvertFrom-Json }
    $p = Read-Profile
    $new = $p | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    foreach ($k in $BindKeys) { $new | Add-Member -NotePropertyName $k -NotePropertyValue $acc.$k -Force }
    $diff = Compare-Prefs $p $new -BindsOnly
    if ((Get-JsonPart $p 'actionMappings') -eq (Get-JsonPart $new 'actionMappings') -and (Get-JsonPart $p 'axisMappings') -eq (Get-JsonPart $new 'axisMappings')) {
        $script:LastOp = 'same'
        if ($script:Fancy) { Write-Ok (L "Твои бинды уже как на аккаунте $(Get-AccountLabel $s.Puuid)" "Your binds already match $(Get-AccountLabel $s.Puuid)") }
        return
    }
    if ($script:Fancy) {
        $null = Test-NotMain $s
        Show-Diff $diff
        if (-not $diff.Count) { Write-Note (L 'Отличий почти нет (мелочи вроде биндов агентов)' 'Almost no differences (small things like agent binds)') }
        if (-not (Confirm-Key (L "Сохранить бинды аккаунта $(Get-AccountLabel $s.Puuid) как мои?" "Save the binds of $(Get-AccountLabel $s.Puuid) as mine?"))) { Write-Note (L 'Отменено' 'Cancelled'); return }
    }
    Save-UndoPoint 'profile' $s.Puuid
    New-HistoryPoint (L 'до «Сохранить → бинды»' 'before “Save → binds”')
    Save-Profile $new
    Log "бинды запомнены с аккаунта $(Get-AccountLabel $s.Puuid) ($($diff.Count) изм.)"
    if ($script:Fancy) { Write-Ok (L "Бинды сохранены с аккаунта $(Get-AccountLabel $s.Puuid), остальное не изменилось" "Binds saved from $(Get-AccountLabel $s.Puuid), everything else unchanged") }
}

function Write-QualityNote {
    $odd = Get-QualityOddities
    if (-not $odd) { return }
    Log "незнакомые значения качества: $($odd -join ', ')"
    if ($script:Fancy) { Write-Note "Незнакомые значения качества ($($odd -join ', ')): Riot мог поменять шкалу, проверь в игре" }
}

try {
    switch ($Command) {
        'menu'      { if (-not (Invoke-InstallOffer)) { Show-Menu } }
        'save'      { Write-Screen (L 'Сохранить как мои' 'Save as mine'); if ($BindsOnly) { Invoke-SaveBinds } else { Invoke-Save } }
        'gfxsave'   { Write-Screen (L 'Сохранить графику' 'Save graphics'); Invoke-SaveGraphics }
        'apply'     { Write-Screen (L 'Перенести мои настройки' 'Apply my settings'); Invoke-Apply -BindsOnly:$BindsOnly }
        'status'    { Write-Banner; Write-State (Get-MenuState) }
        'watch'     { Invoke-Watch -AfterGame:$AfterGame }
        'gfxwait'   { Invoke-GfxWait }
        'install'   { if ($Yes) { Invoke-InstallQuiet } else { Invoke-Install } }   # -Yes — тихо поверх установленного (do update, update.ps1)
        'uninstall' { Invoke-Uninstall }
        'pros'      { Show-OneScreen 'pros' }
        'more'      { Show-OneScreen 'more' }
        'state'     { Write-StateJson }
        'list'      { Write-ListJson $Action }
        'lib'       { }
        'do'        { Write-DoJson $Action; if (-not $script:DoOk) { exit 1 } }
    }
} catch {
    Log "ошибка: $($_.Exception.Message)"
    if ($script:Fancy) { Write-Fail $_.Exception.Message }
    exit 1
}
