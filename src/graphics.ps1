# graphics.ps1 — графика. В облако Riot она не попадает: живёт в локальной папке
# каждого аккаунта на этом ПК (%LOCALAPPDATA%\VALORANT\Saved\Config\<puuid>-<регион>\).
# Подключается из valset.ps1 (dot-source).

$ConfigRoot = Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Config'
$GfxDir     = Join-Path $Root 'graphics'
$GfxIni     = Join-Path $GfxDir 'GameUserSettings.ini'          # разрешение, режим экрана, заполнение, VSync
$GfxRiot    = Join-Path $GfxDir 'RiotUserSettings.graphics.txt' # графические строки из RiotUserSettings.ini
# Графические ключи RiotUserSettings.ini. Нет ключа — стандартное значение игры.
$GfxPattern = '^EAres\w+SettingName::(\w*Quality|AntiAliasing|Anisotropic\w*|ImproveClarity|\w*Framerate\w*|NvidiaReflex\w*|Bloom\w*|Distortion\w*|\w*Shadow\w*|Vignette\w*|\w*Sharpen\w*|\w*VSync\w*)='

function Get-AccountDirs {
    if (-not (Test-Path $ConfigRoot)) { return @() }
    @(Get-ChildItem $ConfigRoot -Directory |
        Where-Object { $_.Name -match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}-\w+$' })
}

function Get-AccountDir([string]$puuid) {
    Get-AccountDirs | Where-Object { $_.Name.StartsWith("$puuid-") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Test-GraphicsSaved { Test-Path $GfxIni }

# Снимок графики аккаунта с этого ПК в эталон. $false — аккаунт ещё не запускал игру здесь.
function Save-Graphics([string]$puuid) {
    $dir = Get-AccountDir $puuid
    if (-not $dir) { return $false }
    $ini  = Join-Path $dir.FullName 'WindowsClient\GameUserSettings.ini'
    $riot = Join-Path $dir.FullName 'Windows\RiotUserSettings.ini'
    if (-not (Test-Path $ini)) { return $false }
    New-Item -ItemType Directory -Force $GfxDir | Out-Null
    Copy-Item $ini $GfxIni -Force
    $lines = @(if (Test-Path $riot) { Get-Content $riot -Encoding UTF8 | Where-Object { $_ -cmatch $GfxPattern } })
    [IO.File]::WriteAllLines($GfxRiot, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    $true
}

# Записывает графику эталона в папку аккаунта; прошлые файлы — рядом с суффиксом .valset.bak.
function Set-GraphicsFor([string]$dir) {
    $win = Join-Path $dir 'Windows'; $wc = Join-Path $dir 'WindowsClient'
    New-Item -ItemType Directory -Force $win, $wc | Out-Null

    $ini = Join-Path $wc 'GameUserSettings.ini'
    if (Test-Path $ini) { Copy-Item $ini "$ini.valset.bak" -Force }
    Copy-Item $GfxIni $ini -Force

    $riot = Join-Path $win 'RiotUserSettings.ini'
    $want = @(Get-Content $GfxRiot -Encoding UTF8 | Where-Object { $_ })
    $bom = $false
    if (Test-Path $riot) {
        Copy-Item $riot "$riot.valset.bak" -Force
        $bom = ((Get-Content $riot -Encoding Byte -TotalCount 3) -join ',') -eq '239,187,191'
        $lines = @(Get-Content $riot -Encoding UTF8 | Where-Object { $_ -cnotmatch $GfxPattern })
        $hdr = [Array]::IndexOf([string[]]$lines, '[Settings]')
        if ($hdr -lt 0) { $lines = @('[Settings]') + $want + $lines }
        elseif ($hdr -eq $lines.Count - 1) { $lines = $lines + $want }
        else { $lines = $lines[0..$hdr] + $want + $lines[($hdr + 1)..($lines.Count - 1)] }
    } else {
        $lines = @('[Settings]') + $want
    }
    [IO.File]::WriteAllLines($riot, [string[]]$lines, (New-Object Text.UTF8Encoding $bom))
}

# $puuid пустой — все аккаунты, которые уже запускали игру на этом ПК.
function Invoke-ApplyGraphics([string]$puuid) {
    if (-not (Test-GraphicsSaved)) { throw (L 'Графика не сохранена — «Запомни как мои» на аккаунте, который играл на этом ПК.' 'Graphics not saved — use “Save as mine” on an account that has played on this PC.') }
    if (Get-Process $GameProc -ErrorAction SilentlyContinue) { Request-GraphicsAfterExit $puuid; return -1 }
    if ($puuid) {
        $all = @(Get-AccountDirs | Where-Object { $_.Name.StartsWith("$puuid-") })  # все регионы аккаунта (-eu, -ap)
        $dirs = if ($all) { @($all.FullName) } else {
            # аккаунт ещё не запускал игру здесь — готовим папки заранее во всех регионах этого ПК: регион аккаунта
            # отсюда не узнать, а угаданный по эталону промахивается (игра создала -eu, а графика легла в -ap)
            $regions = @(Get-AccountDirs | ForEach-Object { $_.Name.Substring(37) } | Sort-Object -Unique)
            if (-not $regions) { $regions = @('eu') }
            @($regions | ForEach-Object { Join-Path $ConfigRoot "$puuid-$_" })
        }
    } else {
        $dirs = @(Get-AccountDirs | ForEach-Object { $_.FullName })
    }
    foreach ($dir in $dirs) {
        Invoke-Step "$(L 'Графика' 'Graphics') → $(Split-Path $dir -Leaf)" { Set-GraphicsFor $dir }
    }
    Log "графика записана в аккаунты: $(($dirs | ForEach-Object { (Split-Path $_ -Leaf).Substring(0, 8) }) -join ', ')"
    $dirs.Count
}

# ── Отложенная графика ───────────────────────────────────────────────────────
# Пока игра запущена, она держит графику в памяти и перепишет файлы при следующем сохранении.
# Поэтому запись ставится в очередь, а скрытый процесс ждёт выхода из игры и записывает её. Живёт только до этого момента.

$GfxQueue     = Join-Path $Root 'gfx-pending.txt'   # PUUID по строке или * (все аккаунты)
$GfxWaitMutex = 'Local\valset-gfxwait'

function Test-GfxWaiting {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting($GfxWaitMutex, [ref]$m)) { $m.Dispose(); return $true }
    $false
}

function Request-GraphicsAfterExit([string]$puuid) {
    New-Item -ItemType Directory -Force $Root | Out-Null
    Add-Content $GfxQueue $(if ($puuid) { $puuid } else { '*' }) -Encoding ASCII
    if (-not (Test-GfxWaiting)) {
        if ($Self -like '*.cmd') { Start-Process $env:ComSpec -ArgumentList '/c', "`"`"$Self`" gfxwait`"" -WindowStyle Hidden }
        else { Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Self`"", 'gfxwait' -WindowStyle Hidden }
    }
    Log "графика ($(if ($puuid) { Short $puuid } else { 'все аккаунты' })) — запишется после выхода из игры"
}

function Invoke-GfxWait {
    $mutex = New-Object Threading.Mutex($false, $GfxWaitMutex)
    try { $got = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { return }
    try {
        do {
            while (Get-Process $GameProc -ErrorAction SilentlyContinue) { Start-Sleep 3 }
            Start-Sleep 5   # игра дописывает файлы при выходе
        } while (Get-Process $GameProc -ErrorAction SilentlyContinue)
        $t = @(Get-Content $GfxQueue -ErrorAction SilentlyContinue | Where-Object { $_ } | Sort-Object -Unique)
        Remove-Item -LiteralPath $GfxQueue -ErrorAction SilentlyContinue
        if ('*' -in $t) { $t = @('') }
        foreach ($p in $t) { $null = Invoke-ApplyGraphics $p }
    } catch {
        Log "отложенная графика: ошибка: $($_.Exception.Message)"
    } finally {
        $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}

# Шкала качества проверена в игре (NOTES.md). Незнакомое значение в снимке — Riot могли поменять шкалу.
$QualityKnown = @{ MaterialQuality = '0', '2'; UIQuality = '0', '1'; DetailQuality = '0', '1'; TextureQuality = '0', '1' }
function Get-QualityOddities {
    @(Get-Content $GfxRiot -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '::(\w+Quality)=(.*)$' -and $QualityKnown.ContainsKey($Matches[1]) -and $Matches[2] -notin $QualityKnown[$Matches[1]]) {
            "$($Matches[1])=$($Matches[2])"
        }
    })
}

# После «Запомнить» и правки графики: во все аккаунты этого ПК (в игре — после выхода) или только в текущий.
# Если на ПК больше одного аккаунта (общий ПК, брат, клуб) — один раз спросить, ответ в config.json (gfxAll).
function Sync-Graphics([string]$current = '') {
    if (-not (Test-GraphicsSaved)) { return }
    $n = @(Get-AccountDirs).Count
    $all = $true
    if ($n -gt 1) {
        $cfg = Get-Config
        if ($null -eq $cfg.gfxAll) {
            if (-not $script:Fancy) { $all = $false }
            else {
                Write-Host ''
                Write-Note (L "графика хранится на этом ПК, а не в облаке; аккаунтов на этом ПК: $n" "graphics live on this PC, not in the cloud; accounts on this PC: $n")
                $all = Confirm-Key (L 'Записывать твою графику во все аккаунты этого ПК? (n — только в тот, где ты сейчас)' 'Write your graphics to all accounts on this PC? (n — only the current one)')
                Set-Config 'gfxAll' $all
                Write-Note (L 'передумаешь — «Аккаунты» → «Графика на этом ПК»' 'change later — “Accounts” → “Graphics on this PC”')
            }
        } else { $all = [bool]$cfg.gfxAll }
    }
    if (-not $all -and -not $current) { return }
    $c = Invoke-ApplyGraphics $(if ($all) { '' } else { $current })
    if (-not $script:Fancy) { return }
    $where = if ($all) { L "во все аккаунты этого ПК ($c)" "to all accounts on this PC ($c)" } else { L 'в текущий аккаунт' 'to the current account' }
    if ($c -lt 0) { Write-Note (L "графика запишется $(if ($all) { 'во все аккаунты этого ПК' } else { 'в текущий аккаунт' }) после выхода из игры" "graphics will be written $(if ($all) { 'to all accounts on this PC' } else { 'to the current account' }) after you exit the game") }
    else { Write-Ok "$(L 'Графика записана' 'Graphics written') $where" }
}

function Read-GraphicsValues {
    $v = @{}
    foreach ($line in (Get-Content $GfxIni -Encoding UTF8) + (Get-Content $GfxRiot -Encoding UTF8)) {
        if ($line -match '^(?:EAres\w+::)?([\w\.]+)=(.*)$') { $v[$Matches[1]] = $Matches[2].Trim('"') }
    }
    $v
}

# Меняет значения в GameUserSettings.ini эталона (все пары сразу).
function Set-GfxIni([hashtable]$pairs) {
    Protect-Profile (L 'до правки в «Изменить»' 'before editing in “Edit”')
    $lines = [Collections.Generic.List[string]](Get-Content $GfxIni -Encoding UTF8)
    foreach ($k in $pairs.Keys) {
        $i = -1
        for ($n = 0; $n -lt $lines.Count; $n++) { if ($lines[$n].StartsWith("$k=")) { $i = $n; break } }
        if ($i -ge 0) { $lines[$i] = "$k=$($pairs[$k])" } else { $lines.Insert(1, "$k=$($pairs[$k])") }
    }
    [IO.File]::WriteAllLines($GfxIni, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}

# Меняет графический ключ RiotUserSettings эталона; $value = $null — убрать (стандарт игры).
function Set-GfxRiot([string]$enum, $value) {
    Protect-Profile (L 'до правки в «Изменить»' 'before editing in “Edit”')
    $name = $enum -replace '^.*::', ''
    $lines = @(Get-Content $GfxRiot -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch "::$name=" })
    if ($null -ne $value) { $lines += "$enum=$value" }
    [IO.File]::WriteAllLines($GfxRiot, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}