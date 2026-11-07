# run-tests.ps1 — проверки без записи в облако и без трогания настоящих данных:
# эталон и папки аккаунтов — подставные, во временной папке (VALSET_ROOT).
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  ✓ $name" -ForegroundColor Green }
    else     { $script:fail++; Write-Host "  ✖ $name  $detail" -ForegroundColor Red }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('valset-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$env:VALSET_ROOT = Join-Path $tmp 'root'
$env:VALSET_LANG = 'ru'   # подписи в проверках — русские; английский проверяется отдельно ниже
New-Item -ItemType Directory -Force "$env:VALSET_ROOT\graphics" | Out-Null
$fx = Join-Path $PSScriptRoot 'fixtures'
Copy-Item "$fx\profile.json" $env:VALSET_ROOT
Copy-Item "$fx\GameUserSettings.ini", "$fx\RiotUserSettings.graphics.txt" "$env:VALSET_ROOT\graphics"

try {
    Write-Host 'исходники'
    # install.ps1 запускают как `irm … | iex`: BOM попал бы в начало текста и сломал команду — у него BOM нет.
    $inst = "$proj\install.ps1"
    Check 'install.ps1 без BOM (иначе irm | iex падает)' (((Get-Content $inst -Encoding Byte -TotalCount 3) -join ',') -ne '239,187,191')
    $tk = $null; $er = $null
    [void][Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($inst, [Text.Encoding]::UTF8), [ref]$tk, [ref]$er)
    Check 'install.ps1 разбирается без ошибок' (-not $er) "$($er | Select-Object -First 1)"
    # “ ” для PowerShell — те же кавычки, что ": внутри строки в двойных кавычках обрывают её без ошибки разбора.
    $sq = foreach ($f in Get-ChildItem "$proj\src\*.ps1", $inst) {
        $tk = $null; $er = $null
        [void][Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($f.FullName), [ref]$tk, [ref]$er)
        foreach ($x in $tk) { if ($x.Kind -in 'StringExpandable', 'HereStringExpandable' -and $x.Text -match '(?<!`)[“”„]') { "$($f.Name):$($x.Extent.StartLineNumber)" } }
    }
    Check 'типографские кавычки в строках "…" экранированы' (-not $sq) "$sq"
    foreach ($f in Get-ChildItem "$proj\src\*.ps1", "$proj\*.ps1", "$PSScriptRoot\*.ps1" | Where-Object Name -ne 'install.ps1') {
        $bom = ((Get-Content $f.FullName -Encoding Byte -TotalCount 3) -join ',') -eq '239,187,191'
        Check "$($f.Name): UTF-8 с BOM (иначе PowerShell 5.1 ломает кириллицу)" $bom
    }

    # Windows 10 открывает меню в старой консоли (Consolas / Lucida Console) без подстановки шрифтов:
    # символа нет в шрифте — человек видит квадратик.
    Add-Type -AssemblyName PresentationCore
    $fonts = foreach ($n in 'consola.ttf', 'lucon.ttf') { New-Object Windows.Media.GlyphTypeface ([Uri]"$env:WINDIR\Fonts\$n") }
    $missing = @{}
    foreach ($f in Get-ChildItem "$proj\src\*.ps1") {
        foreach ($ch in [IO.File]::ReadAllText($f.FullName).ToCharArray()) {
            $c = [int]$ch
            if ($c -le 127 -or $c -eq 0xFEFF -or ($c -ge 0xD800 -and $c -le 0xDFFF)) { continue }
            foreach ($g in $fonts) { if (-not $g.CharacterToGlyphMap.ContainsKey($c)) { $missing['U+{0:X4}' -f $c] = 1 } }
        }
    }
    Check 'все символы есть в шрифтах консоли Windows 10' (-not $missing.Count) ($missing.Keys -join ' ')
    # загрузка всех функций; status только печатает (вывод глушим)
    . "$proj\src\valset.ps1" -Command status *> $null
    $script:Fancy = $false

    Write-Host 'облако: упаковка'
    $j = Get-Content $ProfilePath -Raw -Encoding UTF8
    Check 'deflate+base64 туда и обратно' ((Expand-Pref (Compress-Pref $j)) -eq $j)

    Write-Host 'подписи в предпросмотре'
    Check 'чувствительность — число'      ((Format-PrefValue 'EAresFloatSettingName::MouseSensitivity' 0.35) -eq '0.35')
    Check 'снайперский — удержание'       ((Format-PrefValue 'EAresBoolSettingName::HoldInputForSniperScopes' $true) -eq 'удержание')
    Check 'FPS — текст и график'          ((Format-PrefValue 'EAresIntSettingName::PlayerPerfShowFrameRate' 3) -eq 'текст и график')
    Check 'музыка — в процентах'          ((Format-PrefValue 'EAresFloatSettingName::AllMusicOverallVolume' 0.4) -eq '40%')
    Check 'голосовой чат — в процентах'   ((Format-PrefValue 'EAresIntSettingName::VoiceVolume' 75) -eq '75%')
    Check 'нет значения → стандарт'       ((Format-PrefValue 'EAresIntSettingName::VoiceVolume' $null) -eq 'стандарт')
    Check 'способность C названа «Способность 1»' ((Get-ActionLabel 'Activate_GrenadeAbility') -like 'Способность 1*')
    Write-Host 'графика: запись в папку аккаунта'
    $acc = Join-Path $tmp 'acc'
    New-Item -ItemType Directory -Force "$acc\Windows", "$acc\WindowsClient" | Out-Null
    [IO.File]::WriteAllLines("$acc\Windows\RiotUserSettings.ini",
        [string[]]@('[Settings]', 'EAresStringSettingName::CrosshairProfileName=тест', 'EAresIntSettingName::ShadowQuality=9', 'EAresIntSettingName::PlayerPerfShowFrameRate=3'),
        (New-Object Text.UTF8Encoding $true))
    Set-GraphicsFor $acc
    $after = Get-Content "$acc\Windows\RiotUserSettings.ini" -Encoding UTF8
    Check 'старый графический ключ убран'     (-not ($after -match 'ShadowQuality'))
    Check 'не-графика сохранена'              (($after -match 'CrosshairProfileName=тест').Count -eq 1)
    Check 'статистика FPS не считается графикой' (($after -match 'PlayerPerfShowFrameRate').Count -eq 1)
    Check 'графика эталона записана'           (($after -match 'MaxFramerateAlways=240').Count -eq 1)
    Check 'BOM файла сохранён'                 (((Get-Content "$acc\Windows\RiotUserSettings.ini" -Encoding Byte -TotalCount 3) -join ',') -eq '239,187,191')
    Check 'GameUserSettings.ini скопирован'    ((Get-FileHash "$acc\WindowsClient\GameUserSettings.ini").Hash -eq (Get-FileHash $GfxIni).Hash)
    Check 'копия старого файла рядом'          (Test-Path "$acc\Windows\RiotUserSettings.ini.valset.bak")

    # Аккаунт ещё не играл на этом ПК: регион не знаем — графика заранее во все регионы ПК (игра создала -eu, а угадали -ap).
    $ConfigRoot = Join-Path $tmp 'cfgroot'; $GameProc = 'valset-test-no-such-process'
    New-Item -ItemType Directory -Force "$ConfigRoot\3303fe2d-0000-0000-0000-000000000000-ap", "$ConfigRoot\3303fe2d-0000-0000-0000-000000000000-eu" | Out-Null
    $np = 'dd2f12fb-0000-0000-0000-000000000000'
    $n = Invoke-ApplyGraphics $np *> $null; $n = @(Get-ChildItem $ConfigRoot -Directory -Filter "$np-*").Count
    Check 'новый аккаунт: графика во все регионы ПК' ($n -eq 2 -and (Test-Path "$ConfigRoot\$np-eu\Windows\RiotUserSettings.ini")) "папок: $n"
    $ConfigRoot = Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Config'; $GameProc = 'VALORANT-Win64-Shipping'

    Write-Host 'слежение'
    $WatchMutexName = "Local\valset-watch-test-$PID"   # не путать с настоящим слежением на этом ПК
    Check 'не запущено' (-not (Test-WatchRunning))
    $m = New-Object Threading.Mutex($false, $WatchMutexName)
    Check 'видно по блокировке' (Test-WatchRunning)
    $m.Dispose()

    Write-Host 'предпросмотр'
    $a = Read-Profile
    $b = $a | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    Check 'одинаковые наборы — без записи' (Test-PrefsEqual $a $b)
    ($b.actionMappings | Where-Object { $_.name -eq 'Ping' -and [int]$_.bindIndex -eq 0 } | Select-Object -First 1).key = 'G'
    $sens = $b.floatSettings | Where-Object settingEnum -like '*MouseSensitivity' | Select-Object -First 1
    $before = $sens.value
    $sens.value = 0.5
    $d = Compare-Prefs $a $b
    $many = Compare-Prefs ([pscustomobject]@{ floatSettings = @(1..60 | ForEach-Object { @{ settingEnum = "EAresFloatSettingName::T$_"; value = 1 } }) }) ([pscustomobject]@{})
    Check 'отличия — массив: @() не падает (PowerShell 5.1 и List[object])' ($many -is [array] -and @($many).Count -ge 0)
    Check 'видно 2 отличия' ($d.Count -eq 2) "получено $($d.Count): $(($d | ForEach-Object What) -join '; ')"
    Check 'бинд подписан по-человечески' (@($d | Where-Object { $_.What -like 'Пинг*' -and $_.New -eq 'G' }).Count -eq 1)
    Check "чувствительность $before → 0.5" (@($d | Where-Object { $_.What -eq 'Чувствительность' -and $_.New -eq '0.5' }).Count -eq 1)
    Check 'только бинды — 1 отличие' ((Compare-Prefs $a $b -BindsOnly).Count -eq 1)


    Write-Host 'прицелы'
    $mk = { param([string[]]$names, [int]$cur, [string]$tag = '')
        $ps = @($names | ForEach-Object { [pscustomobject][ordered]@{ profileName = $_; primary = [pscustomobject]@{ c = "$_$tag" } } })
        [pscustomobject]@{ stringSettings = @([pscustomobject]@{ settingEnum = $CrosshairEnum
            value = (ConvertTo-Json -InputObject ([pscustomobject][ordered]@{ currentProfile = $cur; profiles = $ps }) -Depth 20 -Compress) }) } }
    $ref = & $mk @('A', 'B') 1; $acc = & $mk @('A', 'X') 0
    Check 'прицелы аккаунта сохранены (2)' ((Merge-Crosshairs $acc $ref) -eq 2)
    $x = Get-Crosshairs $ref
    Check 'итог: B, A, X, активный B' ((@($x.profiles | ForEach-Object profileName) -join ',') -eq 'B,A,X' -and $x.currentProfile -eq 0)
    $main = & $mk @('A', 'B', 'C') 0; $refC = & $mk @('C') 0
    $null = Merge-Crosshairs $main $refC
    $mc = Get-Crosshairs $refC
    Check 'основной аккаунт: порядок тот же, активный C, ничего лишнего' ((@($mc.profiles | ForEach-Object profileName) -join ',') -eq 'A,B,C' -and $mc.currentProfile -eq 2)
    $again = & $mk @('A', 'B') 1
    $null = Merge-Crosshairs $ref $again
    Check 'повторное применение — без записи' (Test-PrefsEqual $ref $again)
    $none = [pscustomobject]@{ stringSettings = @() }
    Check 'в эталоне прицелов нет — у аккаунта остаются' ((Merge-Crosshairs $acc $none) -eq 2 -and @((Get-Crosshairs $none).profiles).Count -eq 2)
    $ref = & $mk @('A', 'B') 1; $acc = & $mk @('B') 0 'другой'
    $null = Merge-Crosshairs $acc $ref
    Check 'одноимённый чужой — с пометкой (акк)' ((@((Get-Crosshairs $ref).profiles | ForEach-Object profileName) -join ',') -eq 'A,B,B (акк)')
    $ref = & $mk @(1..13 | ForEach-Object { "r$_" }) 0; $acc = & $mk @('x1', 'x2', 'x3', 'x4') 0
    $t1 = & $mk @('A', 'B', 'C') 0; $t2 = & $mk @('Z') 0
    Check 'на время: только твои прицелы' ((Join-Crosshairs $t1 $t2 $true) -eq 0 -and @((Get-Crosshairs $t2).profiles).Count -eq 1)
    Check 'насовсем: прицелы аккаунта сохранены' ((Join-Crosshairs $t1 (& $mk @('Z') 0) $false) -eq 3)
    Check 'лимит 15: дописано 2 из 4' ((Merge-Crosshairs $acc $ref) -eq 2 -and $script:CrosshairDropped -eq 2 -and @((Get-Crosshairs $ref).profiles).Count -eq 15)
    $d = Compare-Prefs (& $mk @('A') 0) (& $mk @('A', 'B') 1)
    Check 'предпросмотр: «Прицелы 1 шт. → 2 шт.»' (@($d | Where-Object { $_.What -eq 'Прицелы' -and $_.Old -like '1 шт.*' -and $_.New -like '2 шт.*«B»' }).Count -eq 1)

    Write-Host 'помощник'
    $cfg = Get-Config
    Check 'по умолчанию помощник выключен' (-not $cfg.notify -and -not $cfg.autoApply)
    Set-Content $ConfigPath '{"autoApply":true}' -Encoding UTF8
    $cfg = Get-Config
    Check 'config.json читается, недостающее — по умолчанию' ($cfg.autoApply -and -not $cfg.notify)

    Write-Host 'история моих настроек'
    $sens = { (@((Read-Profile).floatSettings) | Where-Object settingEnum -like '*MouseSensitivity').value }
    $before = & $sens
    New-HistoryPoint 'тест'
    $pp = Read-Profile; (@($pp.floatSettings) | Where-Object settingEnum -like '*MouseSensitivity').value = 0.777; Save-Profile $pp
    $v = (Get-HistoryPoints)[0]
    Copy-ProfileFiles $v.Dir $Root
    Check 'версия из истории возвращается' ([Math]::Abs((& $sens) - $before) -lt 0.0001) "сейчас $(& $sens), ждали $before"
    1..($HistoryMax + 2) | ForEach-Object { New-HistoryPoint "лишняя $_" }
    Check "хранится не больше $HistoryMax версий" (@(Get-HistoryPoints).Count -eq $HistoryMax)

    Set-Content $ConfigPath '{"gfxAll":false}' -Encoding UTF8
    Check 'выбор «графика только в текущий» запоминается' ((Get-Config).gfxAll -eq $false -and -not (Get-Config).notify)

    Write-Host 'на время (чужой аккаунт)'
    $gp = 'aaaaaaaa-1111-2222-3333-444444444444'
    Save-TempOriginal $gp '{"orig":1}'
    Save-TempOriginal $gp '{"mine":1}'
    Check 'исходные не затираются повторным переносом' ((Get-Content (Get-TempPath $gp) -Raw) -match 'orig')
    Check 'есть что вернуть' (Test-AnyTemp)
    Clear-Temp $gp
    Check 'после возврата — ничего не висит' (-not (Test-Temp $gp) -and -not (Test-AnyTemp))
    Check 'не основной аккаунт — по умолчанию на время' (Test-TempDefault $gp)
    Set-AccountState $gp @{ own = $true }
    Check 'помеченный «мой» — насовсем' (-not (Test-TempDefault $gp))
    Check 'основной — насовсем' (-not (Test-TempDefault (Get-MainPuuid)) -or -not (Get-MainPuuid))

    Write-Host 'имена аккаунтов'
    $bad = [Text.Encoding]::GetEncoding(28591).GetString([Text.Encoding]::UTF8.GetBytes('Ради Саши пиво#p1vo'))
    Check 'испорченная кириллица чинится' ((Repair-Utf8 $bad) -eq 'Ради Саши пиво#p1vo') (Repair-Utf8 $bad)
    Check 'нормальные имена не трогаются' ((Repair-Utf8 'Ради#ru') -eq 'Ради#ru' -and (Repair-Utf8 'Café#fr') -eq 'Café#fr' -and (Repair-Utf8 'K0SS#WHO') -eq 'K0SS#WHO')
    Set-AccountState $gp @{ name = $bad }
    Check 'старое имя в accounts.json читается исправленным' ((Read-Accounts)[$gp].name -eq 'Ради Саши пиво#p1vo')

    Write-Host 'надёжность записи'
    $fp = Join-Path $tmp 'safe\a.json'
    Write-FileSafe $fp 'один'; Write-FileSafe $fp 'два'
    Check 'запись через временный файл: новый и замена' ((Get-Content $fp -Raw -Encoding UTF8) -eq 'два' -and -not (Test-Path "$fp.tmp"))
    . "$PSScriptRoot\test-cloud.ps1"   # повторы запросов к Riot
    function Start-GfxWait {}   # без фонового процесса
    Request-CloudAfterExit 'p1aaaaaaaa' 'apply'; Request-CloudAfterExit 'p2aaaaaaaa' 'pro:TenZ'; Request-CloudAfterExit 'p1aaaaaaaa' 'binds'
    $cq = @(Get-Content $CloudQueue -Encoding UTF8)
    Check 'очередь после выхода из игры: на аккаунт — последнее действие' ($cq.Count -eq 2 -and ($cq -contains "p1aaaaaaaa`tbinds") -and ($cq -contains "p2aaaaaaaa`tpro:TenZ")) ($cq -join ' | ')
    Remove-Item $CloudQueue

    Write-Host 'сессионный эталон'
    $fe = 'EAresFloatSettingName::MouseSensitivity'; $fz = 'EAresFloatSettingName::Zoom'
    function New-Xh([string[]]$specs, [int]$act) {   # 'Имя:метка' → профиль прицела; строка JSON внутри stringSettings
        $ps = @($specs | ForEach-Object { $a = $_ -split ':'; [ordered]@{ profileName = $a[0]; mark = $a[1] } })
        $v = ConvertTo-Json -InputObject ([ordered]@{ currentProfile = $act; profiles = $ps }) -Depth 5 -Compress
        '{"settingEnum":"' + $CrosshairEnum + '","value":' + (ConvertTo-Json $v) + '}'
    }
    function New-Prof([string]$fl, [string]$xh = '', [string]$am = '[1]') {
        $s = if ($xh) { '"stringSettings":[' + $xh + '],' } else { '' }
        ('{' + $s + '"actionMappings":' + $am + ',"floatSettings":[' + $fl + ']}') | ConvertFrom-Json
    }
    $f1 = '{"settingEnum":"' + $fe + '","value":0.3}'; $f2 = '{"settingEnum":"' + $fz + '","value":1}'
    $fN = '{"settingEnum":"' + $fe + '","value":0.5}'
    $rf = New-Prof "$f1,$f2"; $bs = New-Prof "$f1,$f2"; $nw = New-Prof "$fN,$f2"
    $m = Merge-Reference $rf $bs $nw
    Check 'сессия: изменённое игроком попало в эталон' ($m.Ref.floatSettings.Where({ $_.settingEnum -eq $fe }).value -eq 0.5 -and $m.Changed -contains $fe -and $m.Changed.Count -eq 1)
    Check 'сессия: входной эталон не тронут' ($rf.floatSettings.Where({ $_.settingEnum -eq $fe }).value -eq 0.3)
    $m = Merge-Reference (New-Prof "$f1,$f2") (New-Prof '{"settingEnum":"EAresFloatSettingName::Other","value":9}') (New-Prof '{"settingEnum":"EAresFloatSettingName::Other","value":9}')
    Check 'сессия: нетронутое эталонное остаётся, даже если base отличается' ($m.Changed.Count -eq 0 -and @($m.Ref.floatSettings).Count -eq 2)
    $m = Merge-Reference (New-Prof "$f1,$f2") (New-Prof "$f1,$f2") (New-Prof $f2)
    Check 'сессия: пропавшее (стало стандартным) убирается из эталона' ($m.Changed -contains $fe -and @($m.Ref.floatSettings).Count -eq 1 -and $m.Ref.floatSettings[0].settingEnum -eq $fz)
    $m = Merge-Reference (New-Prof $f2) (New-Prof $f2) (New-Prof "$f1,$f2")
    Check 'сессия: новая настройка добавляется в эталон' ($m.Changed -contains $fe -and @($m.Ref.floatSettings).Count -eq 2)
    $m = Merge-Reference (New-Prof $f1) (New-Prof $f1) (New-Prof $f1 '' '[2,3]')
    Check 'сессия: actionMappings переписываются целиком' ($m.Changed -contains 'actionMappings' -and (ConvertTo-Json -InputObject $m.Ref.actionMappings -Compress) -eq '[2,3]')
    $m = Merge-Reference (New-Prof "$f1,$f2") (New-Prof "$f1,$f2") (New-Prof "$f1,$f2")
    Check 'сессия: без правок Changed пуст' ($m.Changed.Count -eq 0)
    $m = Merge-Reference (New-Prof $f1 '' '[1]') (New-Prof $f1 '' '[1]') (New-Prof $fN '' '[2]') 'binds'
    Check 'сессия: scope binds не трогает числа' ($m.Changed.Count -eq 1 -and $m.Changed[0] -eq 'actionMappings' -and $m.Ref.floatSettings[0].value -eq 0.3)

    $xr = New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)
    $xb = New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)
    $xn = New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1', 'Acc:1' 0)   # Acc — прицел владельца аккаунта: не должен просочиться
    $xr2 = New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0); $xb2 = New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)
    $m = Merge-Reference $xr2 $xb2 (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0))
    Check 'прицел: без правок — пусто' ($m.Changed.Count -eq 0)
    # аккаунтный прицел уже был в base (эталон его не содержит) — не переносится
    $m = Merge-Reference (New-Prof $f1 (New-Xh 'Mine:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'Acc:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'Acc:1' 0))
    Check 'прицел: чужой прицел аккаунта не просачивается в эталон' ($m.Changed.Count -eq 0 -and @((Get-Crosshairs $m.Ref).profiles).Count -eq 1)
    $m = Merge-Reference (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)) (New-Prof $f1 (New-Xh 'Mine:9', 'Mine2:1' 0))
    $xc = Get-Crosshairs $m.Ref
    Check 'прицел: изменённый свой обновлён' ($m.Changed -contains 'Crosshair:Mine' -and $xc.profiles[0].mark -eq '9' -and @($xc.profiles).Count -eq 2)
    $m = Merge-Reference (New-Prof $f1 (New-Xh 'Mine:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'New:1' 1))
    $xc = Get-Crosshairs $m.Ref
    Check 'прицел: новый добавлен в конец и стал активным' ($m.Changed -contains 'Crosshair:New' -and $xc.profiles[1].profileName -eq 'New' -and $xc.currentProfile -eq 1)
    $m = Merge-Reference (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 0)) (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 1))
    $xc = Get-Crosshairs $m.Ref
    Check 'прицел: смена активного переносится' ($xc.currentProfile -eq 1 -and $m.Changed -contains 'Crosshair:Mine2')
    $m = Merge-Reference (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 1)) (New-Prof $f1 (New-Xh 'Mine:1', 'Mine2:1' 1)) (New-Prof $f1 (New-Xh 'Mine2:1' 0))
    $xc = Get-Crosshairs $m.Ref
    Check 'прицел: удалённый убран, активный пересчитан' ($m.Changed -contains 'Crosshair:Mine' -and @($xc.profiles).Count -eq 1 -and $xc.profiles[0].profileName -eq 'Mine2' -and $xc.currentProfile -eq 0)
    $many = @(1..15 | ForEach-Object { "P${_}:1" })
    $m = Merge-Reference (New-Prof $f1 (New-Xh $many 0)) (New-Prof $f1 (New-Xh $many 0)) (New-Prof $f1 (New-Xh ($many + 'Extra:1') 0))
    Check 'прицел: больше 15 — лишние срезаются с конца' (@((Get-Crosshairs $m.Ref).profiles).Count -eq 15)

    Write-Host 'эталон: правки из игры'
    $sp = [pscustomobject]@{ Puuid = 'sessaaaaaaaa' }
    $refJ = Get-Content $ProfilePath -Raw -Encoding UTF8
    $sensE = 'EAresFloatSettingName::MouseSensitivity'
    $gameJ = ConvertTo-Json -InputObject (Join-ProPrefs ($refJ | ConvertFrom-Json) ([pscustomobject]@{ floatSettings = @([pscustomobject]@{ settingEnum = $sensE; value = 0.777 }) })) -Depth 32 -Compress
    Check 'без базы аккаунт не участвует' (@(Update-Reference $sp $gameJ).Count -eq 0)
    Set-SessionBase $sp.Puuid $refJ
    $got = @(Update-Reference $sp $gameJ)
    $sensNow = (@((Read-Profile).floatSettings) | Where-Object { $_.settingEnum -eq $sensE }).value
    Check 'сенса из игры — в эталоне' ($got.Count -ge 1 -and $sensNow -eq 0.777) "$($got -join ', ') / $sensNow"
    Check 'база сдвинулась — повторно не переносится' (@(Update-Reference $sp $gameJ).Count -eq 0 -and (Get-SessionBase $sp.Puuid).json -ceq $gameJ)
    Write-FileSafe $ProfilePath $refJ; Clear-SessionBase $sp.Puuid

    Write-Host 'настройки про'
    $pj = Join-Path $tmp 'pros.json'
    $ProsUrl = $pj
    Set-Content $pj '{"version":1,"pros":[]}' -Encoding UTF8
    $script:Pros = $null
    Check 'пустой список → пункта нет' ((Get-Pros).Count -eq 0)
    Set-Content $pj '{"version":1,"pros":[{"nick":"Pro1","dpi":1600,"prefs":{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.2}]}},{"nick":"Bad"}]}' -Encoding UTF8
    $script:Pros = $null
    $pl = Get-Pros
    Check 'запись без настроек отброшена' ($pl.Count -eq 1 -and $pl[0].nick -eq 'Pro1')
    $pp = (ConvertTo-Json -InputObject $pl[0].prefs -Depth 32) | ConvertFrom-Json
    Convert-ProSens $pp 1600 800
    Check 'eDPI: 1600×0.2 → 800×0.4' ($pp.floatSettings[0].value -eq 0.4)
    $cur = Read-Profile
    $pn = Join-ProPrefs $cur $pp
    $sv = @($pn.floatSettings | Where-Object { $_.settingEnum -eq $SensEnum })
    Check 'про наложен: одна чувствительность, его' ($sv.Count -eq 1 -and $sv[0].value -eq 0.4)
    Check 'остальное — как было' (@($pn.floatSettings).Count -eq (@($cur.floatSettings | Where-Object { $_.settingEnum -ne $SensEnum }).Count + 1) -and (Get-JsonPart $pn 'actionMappings') -eq (Get-JsonPart $cur 'actionMappings'))
    Check 'текущие не тронуты' ((Get-JsonPart $cur 'floatSettings') -eq (Get-JsonPart (Read-Profile) 'floatSettings'))
    Check 'pros.json в репозитории разбирается' ($null -ne (Get-Content "$proj\pros\pros-v2.json" -Raw | ConvertFrom-Json).pros)
    $all = @((Get-Content "$proj\pros\pros-v2.json" -Raw -Encoding UTF8 | ConvertFrom-Json).pros)
    $bad = @(foreach ($p in $all) {
        try {
            $n = Join-ProPrefs $cur $p.prefs
            if ($p.crosshair) { Add-ProCrosshair $n $p; $x = Get-Crosshairs $n; if ($x.profiles[0].profileName -ne $p.nick -or @($x.profiles).Count -gt 15) { $p.nick } }
            if (-not $p.dpi) { $p.nick }
        } catch { $p.nick }
    })
    Check "все про из pros.json применяются ($($all.Count))" ($all.Count -gt 0 -and $bad.Count -eq 0)
    if ($bad) { Write-Host "      не применились: $($bad -join ', ')" }
    $xp = $all | Where-Object { $_.crosshair } | Select-Object -First 1
    $n1 = Join-ProPrefs $cur $xp.prefs; Add-ProCrosshair $n1 $xp; Add-ProCrosshair $n1 $xp
    Check 'прицел про дважды — один, активный' (@((Get-Crosshairs $n1).profiles | Where-Object { $_.profileName -eq $xp.nick }).Count -eq 1 -and (Get-Crosshairs $n1).currentProfile -eq 0)

    Write-Host 'токен игры (выход из аккаунта прямо из игры)'
    $env:VALSET_GAME_TOKEN = '{"accessToken":"a","token":"e","subject":"' + $gp + '"}'
    $g = Get-GameTokenSession
    Check 'сессия из токена сторожа' ($g.Puuid -eq $gp -and $g.Token -eq 'a' -and $g.Entitlement -eq 'e')
    $env:VALSET_GAME_TOKEN = 'мусор'
    Check 'битый токен — нет сессии' ($null -eq (Get-GameTokenSession))
    Remove-Item Env:VALSET_GAME_TOKEN
    Check 'без токена — нет сессии' ($null -eq (Get-GameTokenSession))
    Check 'сторож держит токен в игре' ($AgentSrc.Contains('HoldToken();') -and $AgentSrc.Contains('VALSET_GAME_TOKEN'))

    Write-Host 'код прицела'
    # Пары «код из игры ↔ тот же прицел в облаке» — пять прицелов владельца (fixtures).
    $xc = @(Get-Content "$fx\crosshair-codes.txt" -Encoding UTF8 | Where-Object { $_ -and $_ -notlike '#*' })
    $xp = @((Get-Content "$fx\crosshair-profiles.json" -Raw -Encoding UTF8 | ConvertFrom-Json).profiles)
    $xn = 'точка', 'КРЕСТ', 'BIG точка', 'точка крутая', 'крестик'
    for ($i = 0; $i -lt 5; $i++) {
        $e = $xp | Where-Object { $_.profileName -eq $xn[$i] }
        if ($i -eq 4) {   # обводка выключена (h;0) — её прозрачность игра в код не пишет, остаётся по умолчанию
            $e = ConvertTo-Json $e -Depth 32 | ConvertFrom-Json
            $e.primary.outlineOpacity = 0.5
        }
        $a = ConvertTo-Json (ConvertFrom-CrosshairCode $xc[$i] $xn[$i]) -Depth 32 -Compress
        Check "код → «$($xn[$i])» как в облаке" ($a -eq (ConvertTo-Json $e -Depth 32 -Compress)) $xc[$i]
    }
    $xu = ConvertFrom-CrosshairCode '0;s;1;P;c;5;u;2AFF00FF;o;0;f;0;0l;2;0v;2;0g;1;0o;1;0a;1;0f;0;1b;0' 'про'
    Check 'свой цвет: u → colorCustom, c → цвет из палитры' ((ConvertTo-Json $xu.primary.colorCustom -Compress) -eq '{"b":0,"g":255,"r":42,"a":255}' -and $xu.primary.color.r -eq 0 -and -not $xu.primary.bUseCustomColor)
    Check 'свой цвет: вертикаль отдельно, обводка прозрачная' ($xu.primary.innerLines.bAllowVertScaling -and $xu.primary.outlineOpacity -eq 0 -and $xu.profileName -eq 'про')

    Write-Host 'шкала качества'
    Check 'знакомые значения — без предупреждения' (-not (Get-QualityOddities))
    $gr = [IO.File]::ReadAllText($GfxRiot)
    [IO.File]::WriteAllText($GfxRiot, $gr.TrimEnd() + "`r`nEAresIntSettingName::TextureQuality=2`r`n", (New-Object Text.UTF8Encoding $true))
    Check 'незнакомое значение замечено' ((Get-QualityOddities) -contains 'TextureQuality=2')
    [IO.File]::WriteAllText($GfxRiot, $gr, (New-Object Text.UTF8Encoding $true))

    Write-Host 'уведомления с кнопками'
    $tx = [xml](New-ToastXml 'A <b>' 'x & y' @(@{ label = 'Применить'; arg = 'apply' }, @{ label = 'Отменить'; arg = 'undo' }))
    $ac = @($tx.toast.actions.action)
    Check 'тост: кнопки — протокол valset:' ($ac.Count -eq 2 -and $ac[0].activationType -eq 'protocol' -and $ac[0].arguments -eq 'valset:apply' -and $ac[1].arguments -eq 'valset:undo' -and $ac[0].content -eq 'Применить')
    Check 'тост: текст экранируется' ($tx.toast.visual.binding.text[0] -eq 'A <b>' -and $tx.toast.visual.binding.text[1] -eq 'x & y')
    Check 'тост без кнопок — без <actions>' (-not ((New-ToastXml 'a' 'b') -match 'actions'))

    Write-Host 'приложение: state и do'
    Set-Content $ConfigPath '{"badge":false}' -Encoding UTF8
    Check 'config: app и badge (app по умолчанию вкл)' ((Get-Config).app -and -not (Get-Config).badge)
    Set-Content $ConfigPath '{}' -Encoding UTF8
    $script:Quiet = $true
    $GameProc = 'valset-test-no-such-process'
    function Invoke-ApplyGraphics { 0 }; function Save-Graphics { $false }; function Sync-Graphics {}; function Update-Agent {}
    $tp = 'bbbbbbbb-1111-2222-3333-444444444444'
    $script:sess = [pscustomobject]@{ Puuid = $tp; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }
    $script:cloud = '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.9}]}'
    $cloud0 = $script:cloud
    function Get-Session { $script:sess }
    function Get-Settings($s) { $script:cloud }
    function Set-Settings($s, [string]$json) { $script:cloud = $json }
    function Get-RiotId($s) { 'Тест#EU' }
    Write-FileSafe $SourcePath 'mainmainmain'
    $prof0 = Get-Content $ProfilePath -Raw -Encoding UTF8
    $stJ = Get-StateJson
    $stO = $stJ | ConvertFrom-Json
    $want = 'client game account puuid isMain have same diff diffList temp own pending synced suggested autoApply askAuto notify badge setsAuto overlay overlayHint lang error ver nSets nAccounts' -split ' '
    Check 'state: одна строка JSON с полями контракта' ($stJ -notmatch "[\r\n]" -and (($stO.PSObject.Properties.Name | Sort-Object) -join ' ') -eq (($want | Sort-Object) -join ' ')) $stJ.Substring(0, [Math]::Min(200, $stJ.Length))
    Check 'state: own = false на чужом, true на основном' ($stO.own -eq $false) $stJ
Check 'state: чужой аккаунт — предлагает apply' ($stO.puuid -eq $tp -and $stO.account -eq 'Тест#EU' -and -not $stO.isMain -and $stO.have -and $stO.same -eq $false -and $stO.diff -ge 1 -and $stO.diffList.Count -ge 1 -and $stO.suggested -eq 'apply' -and $stO.lang -eq 'ru' -and $stO.badge -and $stO.error -eq '')
    $script:sess = [pscustomobject]@{ Puuid = 'mainmainmain'; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }
    $mO = Get-StateJson | ConvertFrom-Json
    Check 'state: основной с расхождением — предлагает save' ($mO.isMain -and $mO.own -eq $true -and $mO.same -eq $false -and $mO.suggested -eq 'save')
    $script:sess = $null
    $nO = Get-StateJson | ConvertFrom-Json
    Check 'state: клиент закрыт — пустой аккаунт, same null' ($nO.puuid -eq '' -and $null -eq $nO.same -and $nO.account -eq '' -and ($nO.suggested -eq 'client' -or $nO.client))
    $script:sess = [pscustomobject]@{ Puuid = $tp; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }

    $r = Invoke-Do 'apply'
    $la = Get-Content $LastActionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Check 'do apply: ok, можно отменить, сообщение' ($r.ok -and $r.undo -and -not $r.queued -and $r.message -like 'Перенесено*') ($r | ConvertTo-Json -Compress)
    Check 'do apply: last-action.json — что было до' ($la.action -eq 'apply' -and $la.kind -eq 'account' -and $la.puuid -eq $tp -and $la.json -ceq $cloud0)
    Check 'do apply: облако изменилось, исходные на время сохранены' ($script:cloud -cne $cloud0 -and (Test-Temp $tp))
    $aO = Get-StateJson | ConvertFrom-Json
    Check 'state: после apply — совпадает, на время, предлагает untemp' ($aO.same -eq $true -and $aO.temp -and $aO.suggested -eq 'untemp')
    $applied = $script:cloud
    $r = Invoke-Do 'untemp'
    Check 'do untemp: исходные возвращены, отмена доступна' ($r.ok -and $r.undo -and $script:cloud -ceq $cloud0 -and -not (Test-Temp $tp)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после untemp: твои настройки и исходные на месте' ($r.ok -and -not $r.undo -and $script:cloud -ceq $applied -and (Test-Temp $tp) -and -not (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r1 = Invoke-Do 'untemp'; $r2 = Invoke-Do 'apply'; $r = Invoke-Do 'undo'
    Check 'do undo после apply: облако как было, исходных нет' ($r.ok -and $script:cloud -ceq $cloud0 -and -not (Test-Temp $tp) -and -not (Get-SessionBase $tp) -and -not (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo без действия — ошибка в JSON, не исключение' (-not $r.ok -and $r.message -like 'Нечего*')
    $r = Invoke-Do 'apply'
    $script:sess = [pscustomobject]@{ Puuid = 'dddddddd-0000'; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }
    $r = Invoke-Do 'undo'
    Check 'do undo: в другом аккаунте отказ, запись цела' (-not $r.ok -and (Test-Path $LastActionPath) -and $script:cloud -cne $cloud0)
    $script:sess = [pscustomobject]@{ Puuid = $tp; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }
    $null = Invoke-Do 'undo'

    $script:cloud = '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.123}]}'
    $GameProc = 'powershell'   # «игра запущена»
    $r = Invoke-Do 'apply'
    Check 'do apply при запущенной игре: в очереди, без отмены, облако не тронуто' ($r.ok -and $r.queued -and -not $r.undo -and $r.message -like 'Ждёт*' -and (Test-Path $CloudQueue) -and $script:cloud -like '*0.123*') ($r | ConvertTo-Json -Compress)
    Remove-Item $CloudQueue -ErrorAction SilentlyContinue
    $GameProc = 'valset-test-no-such-process'

    $r = Invoke-Do 'save'
    Check 'do save: эталон = облако аккаунта' ($r.ok -and $r.undo -and $r.message -like 'Сохранено*' -and (Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $script:cloud) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после save: прежний эталон и источник' ($r.ok -and (Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $prof0 -and (Get-Source) -eq 'mainmainmain' -and -not (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'savebinds'
    Check 'do savebinds + undo: эталон вернулся' ($r.ok -and ($r.undo -or $r.message -like '*совпадают*'))
    if ($r.undo) { $null = Invoke-Do 'undo' }
    Check 'после do эталон прежний' ((Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $prof0)
    $r = Invoke-Do 'взрыв'
    Check 'do: неизвестное действие — ok false' (-not $r.ok)
    $script:Fancy = $false; $script:Quiet = $true
    $cap = @(& { Write-DoJson 'save'; $null = Invoke-Do 'undo' } *>&1)
    Check 'do: в stdout ровно одна строка JSON, без шума' ($cap.Count -eq 1 -and $cap[0] -is [string] -and (($cap[0] | ConvertFrom-Json).ok)) ($cap -join ' | ')
    Write-FileSafe $ProfilePath $prof0; Remove-LastAction
    $script:Quiet = $false

    Write-Host 'приложение: list и остальные do'
    $script:Quiet = $true; $script:Fancy = $false
    $script:Pros = $null
    Set-Content $pj '{"version":1,"pros":[{"nick":"Pro1","dpi":1600,"prefs":{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.2}]}},{"nick":"Pro2","team":"T","active":false,"prefs":{"intSettings":[]}}]}' -Encoding UTF8
    $script:Pros = $null
    function Parse-Arr($j) { ,@(ConvertFrom-Json $j | ForEach-Object { $_ }) }
    $names = { param($o) (($o.PSObject.Properties.Name | Sort-Object) -join ' ') }
    $lp = Get-ListJson 'pros'
    $pl = (Parse-Arr $lp)
    Check 'list pros: одна строка, поля nick team label hint needsDpi' ($lp -notmatch "[\r\n]" -and $pl.Count -eq 2 -and $pl[1].nick -eq 'Pro2' -and $pl[1].label -eq 'Pro2 · T · не играет' -and (& $names $pl[0]) -eq 'hint label needsDpi nick team') $lp
    Check 'list pros: подсказка с DPI и eDPI, нужен DPI мыши' ($pl[0].hint -like '*1600 DPI*eDPI 320*' -and $pl[0].needsDpi -and $pl[0].label -eq 'Pro1') $lp
    Set-AccountState 'mainmainmain' @{ name = 'Главный#EU'; seen = '2026-10-01T10:00:00'; main = $true; state = 'diff'; diff = 3; checked = (Get-Stamp) }
    Set-AccountState $tp @{ name = 'Тест#EU'; seen = '2026-10-02T10:00:00'; own = $false }
    $la = Get-ListJson 'accounts'; $al = (Parse-Arr $la)
    Check 'list accounts: поля и порядок (основной первым)' ($al.Count -ge 2 -and (& $names $al[0]) -eq 'actions checked current main name own puuid state status' -and $al[0].puuid -eq 'mainmainmain' -and $al[0].main) $la
    $a1 = $al | Where-Object puuid -eq $tp
    Check 'list accounts: действия основного и обычного' ((@($al[0].actions.id) -join ',') -eq 'forget' -and (@($a1.actions.id) -join ',') -eq 'main,own,forget' -and $a1.current -and $a1.state -eq '' -and $al[0].state -eq 'diff' -and $a1.actions[0].label -eq 'Сделать основным') $la
    $bk1 = New-Backup $script:sess $cloud0
    $lb = Get-ListJson 'backups'; $bl = (Parse-Arr $lb)
    $b1 = $bl | Where-Object id -eq ([IO.Path]::GetFileNameWithoutExtension($bk1))
    Check 'list backups: id, account, when, why' ($b1 -and (& $names $b1) -eq 'account id mine when why' -and $b1.mine -and $b1.account -eq 'Тест#EU') $lb
    New-HistoryPoint 'тест-точка'
    $lh = Get-ListJson 'history'; $hl = (Parse-Arr $lh)
    $hp = $hl | Where-Object why -eq 'тест-точка'
    Check 'list history: id, when, why, current' ($hp -and (& $names $hp) -eq 'current id when why' -and $hp.current -eq $true) $lh
    $ld = Get-ListJson 'diff'; $dl = (Parse-Arr $ld)
    Check 'list diff: what/old/new' ($dl.Count -ge 1 -and (& $names $dl[0]) -eq 'new old what') $ld
    $script:sess = $null
    Check 'list diff: нет входа — пустой массив' ((Get-ListJson 'diff') -eq '[]')
    $script:sess = [pscustomobject]@{ Puuid = $tp; Token = 't'; Entitlement = 'e'; ClientPid = '1'; Port = '1'; Auth = '' }
    Check 'list: неизвестный список — ошибка' ($(try { $null = Get-ListJson 'zzz'; $false } catch { $true }))

    # про: DPI -> примерить -> отмена; игра запущена -> очередь
    $cloudP = $script:cloud = '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.9}]}'
    $r = Invoke-Do 'pro:Pro1'
    Check 'do pro без DPI мыши — понятная ошибка, облако цело' (-not $r.ok -and $r.message -like '*DPI*' -and $script:cloud -ceq $cloudP) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'set:dpi=800'
    Check 'do set:dpi' ($r.ok -and (Get-Config).dpi -eq 800)
    Check 'list pros: после DPI needsDpi=false' (-not ((Parse-Arr (Get-ListJson 'pros'))[0].needsDpi))
    $r = Invoke-Do 'pro:Pro1'
    Check 'do pro: чувствительность пересчитана, на время, отмена доступна' ($r.ok -and $r.undo -and $script:cloud -like '*"value":0.4*' -and (Test-Temp $tp) -and $r.message -like '*Pro1*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после pro: облако и исходные как были' ($r.ok -and $script:cloud -ceq $cloudP -and -not (Test-Temp $tp) -and -not (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'pro:Нетакого'
    Check 'do pro: нет в списке — ошибка' (-not $r.ok)
    $GameProc = 'powershell'
    $r = Invoke-Do 'pro:Pro1'
    Check 'do pro при запущенной игре: в очереди, облако не тронуто' ($r.ok -and $r.queued -and -not $r.undo -and $script:cloud -ceq $cloudP -and ((Get-Content $CloudQueue -Encoding UTF8) -match 'pro:Pro1')) ($r | ConvertTo-Json -Compress)
    Remove-Item $CloudQueue -ErrorAction SilentlyContinue
    $r = Invoke-Do "restore:$([IO.Path]::GetFileNameWithoutExtension($bk1))"
    Check 'do restore при запущенной игре — отказ' (-not $r.ok -and $r.message -like 'Игра запущена*' -and $script:cloud -ceq $cloudP) ($r | ConvertTo-Json -Compress)
    $GameProc = 'valset-test-no-such-process'

    # код для друга: упаковка, чтение, предпросмотр, запись и отмена — облако подставное
    $bad = @(foreach ($n in 1..9) { $b = [byte[]](@(250, 0, 77, 255, 1, 128, 64, 3, 200)[0..($n - 1)]); if (((ConvertFrom-Cjk (ConvertTo-Cjk $b)) -join ',') -ne ($b -join ',')) { $n } })
    Check 'код: 14 бит в символ туда и обратно (длины 1–9)' (-not $bad.Count) "$bad"
    $profS = Get-Content $ProfilePath -Raw -Encoding UTF8
    $pf = $profS | ConvertFrom-Json
    $pf | Add-Member -NotePropertyName stringSettings -NotePropertyValue @(@($pf.stringSettings) + [pscustomobject]@{ settingEnum = 'EAresStringSettingName::LastSeenSeasonalPopup'; value = 'x' }) -Force
    $pf | Add-Member -NotePropertyName boolSettings -NotePropertyValue @(@($pf.boolSettings) + [pscustomobject]@{ settingEnum = 'EAresBoolSettingName::HasSeenSettingsTutorial'; value = $true }) -Force
    $xs = Get-Content "$fx\crosshair-profiles.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-CrosshairValue $pf (ConvertTo-CrosshairJson $xs)
    $pf | Add-Member -NotePropertyName floatSettings -NotePropertyValue @(@($pf.floatSettings | Where-Object { $_.settingEnum -ne $SensEnum }) + [pscustomobject]@{ settingEnum = $SensEnum; value = 0.31 }) -Force
    Save-Profile $pf
    $code = New-ShareCode; $codeB = New-ShareCode -BindsOnly
    $plain = Expand-Bytes (ConvertFrom-Cjk $code.Substring(8))
    Check 'код: VALSET2, без служебных отметок и без PUUID' ($code.StartsWith('VALSET2:') -and $plain -notmatch 'LastSeen|HasSeen' -and $plain -notmatch $tp -and $plain -notmatch 'mainmainmain') $plain.Substring(0, [Math]::Min(200, $plain.Length))
    Check 'код: бинды короче полного' ($codeB.Length -lt $code.Length -and $codeB.Length -gt 8) "$($codeB.Length) / $($code.Length)"
    $rc = Read-ShareCode ("держи: " + $code.Substring(0, 20) + " `r`n " + $code.Substring(20) + " — вставь в VALSET")
    $xa = @($xs.profiles)[[int]$xs.currentProfile]; $xb = @((Get-Crosshairs $rc.Prefs).profiles)
    Check 'код: читается с подписью и переносами; прицел — один, активный, без потерь' ($rc.Kind -eq 'full' -and $xb.Count -eq 1 -and (Get-XhKey $xb[0]) -eq (Get-XhKey $xa) -and $xb[0].profileName -eq $xa.profileName)
    Check 'код: из ссылки без префикса, с %-кодировкой' ((Read-ShareCode ([Uri]::EscapeDataString($codeB.Substring(8)))).Kind -eq 'binds')
    $old = 'VALSET2:' + (ConvertTo-Cjk (Compress-Bytes (ConvertTo-Json -InputObject ([ordered]@{ v = 2; kind = 'full'; name = 'набор'; profile = $pf; gfxIniT = 'a'; gfxRiotT = 'b' }) -Depth 32 -Compress)))
    $ro = Read-ShareCode $old
    Check 'код 1.0.0 (full с графикой): читается, графика не берётся, прицел один' ($ro.Gfx -and @((Get-Crosshairs $ro.Prefs).profiles).Count -eq 1 -and (ConvertTo-Json -InputObject $ro.Prefs -Depth 32 -Compress) -notmatch 'LastSeen')
    Check 'код: обрезанный — понятная ошибка' ($(try { $null = Read-ShareCode $code.Substring(0, 30); $false } catch { $_.Exception.Message -like '*повреждён*' -or $_.Exception.Message -like '*другой версии*' }))
    Check 'код: текст без кода — ошибка' ($(try { $null = Read-ShareCode 'привет'; $false } catch { $_.Exception.Message -like '*VALSET*' }))
    $cloudC = $script:cloud = '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.9}],"boolSettings":[{"settingEnum":"EAresBoolSettingName::HasSeenSettingsTutorial","value":false}]}'
    $lc = Parse-Arr (Get-ListJson "code:$code")
    Check 'list code: аккаунт, что в коде, отличия; облако не тронуто' ($lc[0].info -like 'В коде:*' -and $lc[0].account -eq 'Тест#EU' -and $lc[0].same -eq $false -and @($lc | Where-Object { $_.what -eq 'Чувствительность' -and $_.new -eq '0.31' }).Count -eq 1 -and $script:cloud -ceq $cloudC) (Get-ListJson "code:$code")
    Check 'list code: битый код — элемент error' ([bool](Parse-Arr (Get-ListJson 'code:VALSET2:abc'))[0].error)
    $baseKeep = Get-SessionBase $tp; $bkT = [DateTime]::Now.AddSeconds(-1)
    $r = Invoke-Do "code:$code"
    $cc = $script:cloud | ConvertFrom-Json
    Check 'do code: записано, бэкап, отмена; отметки аккаунта не тронуты' ($r.ok -and $r.undo -and $script:cloud -like '*0.31*' -and @(Get-BackupFiles | Where-Object { $_.LastWriteTime -gt $bkT }).Count -ge 1 -and @($cc.boolSettings | Where-Object { $_.settingEnum -like '*HasSeenSettingsTutorial' -and $_.value -eq $false }).Count -eq 1 -and @((Get-Crosshairs $cc).profiles).Count -eq 1) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'share'
    Check 'do share: код в ответе, прошлая отмена не стёрта' ($r.ok -and $r.code -like 'VALSET2:*' -and $r.undo -and (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do "code:$code"
    Check 'do code повторно: уже как в коде, без записи' ($r.ok -and $r.message -like 'Настройки уже*')
    Remove-LastAction
    $script:cloud = $cloudC
    $null = Invoke-Do "code:$code"; $r = Invoke-Do 'undo'
    Check 'do undo после code: облако как было' ($r.ok -and $script:cloud -ceq $cloudC) ($r | ConvertTo-Json -Compress)
    $GameProc = 'powershell'
    $r = Invoke-Do "code:$code"
    Check 'do code при запущенной игре — отказ, облако цело' (-not $r.ok -and $script:cloud -ceq $cloudC)
    $GameProc = 'valset-test-no-such-process'
    $lp2 = Parse-Arr (Get-ListJson 'pro:Pro1')
    Check 'list pro: предпросмотр примерки без записи' ($lp2[0].info -like 'Pro1*' -and @($lp2 | Where-Object { $_.what -eq 'Чувствительность' }).Count -eq 1 -and $script:cloud -ceq $cloudC) (Get-ListJson 'pro:Pro1')
    Check 'list pro: нет такого — error' ([bool](Parse-Arr (Get-ListJson 'pro:Нетакого'))[0].error)
    Write-FileSafe $ProfilePath $profS; $script:cloud = $cloudP; Remove-LastAction
    if ($baseKeep) { Set-SessionBase $tp $baseKeep.json $baseKeep.scope } else { Clear-SessionBase $tp }

    . "$PSScriptRoot\test-sets.ps1"   # наборы косметики
    . "$PSScriptRoot\test-skins.ps1"  # «Все скины»
    . "$PSScriptRoot\test-collections.ps1"  # «Коллекции»
    . "$PSScriptRoot\test-report.ps1"  # «Сообщить об ошибке»
    # откат аккаунта из бэкапа
    $bk2 = New-Backup $script:sess '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.31}]}'
    $id2 = [IO.Path]::GetFileNameWithoutExtension($bk2)
    $r = Invoke-Do "restore:$id2"
    Check 'do restore: облако = бэкап, отмена доступна' ($r.ok -and $r.undo -and $script:cloud -like '*0.31*' -and $r.message -like 'Аккаунт возвращён*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после restore: облако как было' ($r.ok -and $script:cloud -ceq $cloudP) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do "restore:$id2"; $r = Invoke-Do "restore:$id2"
    Check 'do restore повторно: уже в этом состоянии, без новой точки' ($r.ok -and -not $r.undo -and $r.message -like '*уже*') ($r | ConvertTo-Json -Compress)
    $script:cloud = $cloudP
    $r = Invoke-Do 'restore:cccccccc_20200101-000000'
    Check 'do restore: нет такого бэкапа — ошибка' (-not $r.ok)
    $r = Invoke-Do 'restore:..\x'
    Check 'do restore: путь в идентификаторе отвергнут' (-not $r.ok)
    Set-Content (Join-Path $BackupDir 'zzzzzzzz_20200101-000000.json') $cloud0 -Encoding UTF8
    $r = Invoke-Do 'restore:zzzzzzzz_20200101-000000'
    Check 'do restore: бэкап чужого аккаунта — отказ' (-not $r.ok -and $r.message -like 'Это бэкап аккаунта*' -and $script:cloud -ceq $cloudP)

    # история моих настроек
    $o = Get-Content $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $o.floatSettings[0].value = 0.777
    $alt = ConvertTo-Json -InputObject $o -Depth 32 -Compress
    Write-FileSafe $ProfilePath $alt
    $r = Invoke-Do "history:$($hp.id)"
    Check 'do history: эталон вернулся к версии, отмена доступна' ($r.ok -and $r.undo -and (Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $prof0 -and $r.message -like 'Твои настройки возвращены*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после history: прежний эталон' ($r.ok -and (Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $alt -and -not (Test-Path $LastActionPath)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'history:nope'
    Check 'do history: нет такой версии — ошибка' (-not $r.ok)
    Write-FileSafe $ProfilePath $prof0

    # графика
    $r = Invoke-Do 'gfxsave'
    Check 'do gfxsave без снимка графики — ошибка в JSON' (-not $r.ok -and $r.message -like 'Графику не нашёл*') ($r | ConvertTo-Json -Compress)
    function Save-Graphics { $true }
    $r = Invoke-Do 'gfxsave'
    Check 'do gfxsave: ok, отмена доступна' ($r.ok -and $r.undo -and $r.message -like 'Графика сохранена*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после gfxsave: эталон на месте' ($r.ok -and (Get-Content $ProfilePath -Raw -Encoding UTF8) -ceq $prof0) ($r | ConvertTo-Json -Compress)
    function Save-Graphics { $false }

    # переключатели
    $cfg0 = Get-Content $ConfigPath -Raw -Encoding UTF8
    $r = Invoke-Do 'set:notify=on'
    Check 'do set notify=on: config и отмена' ($r.ok -and $r.undo -and (Get-Config).notify -and $r.message -like 'Уведомления: вкл*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после set: config как был' ($r.ok -and -not (Get-Config).notify -and (Get-Content $ConfigPath -Raw -Encoding UTF8) -ceq $cfg0) ($r | ConvertTo-Json -Compress)
    $okAll = $true
    foreach ($k in 'notify', 'autoApply', 'badge', 'app', 'tempAuto', 'gfxAll') {
        $r1 = Invoke-Do "set:$k=on"; $c1 = (Get-Config).$k; $r2 = Invoke-Do "set:$k=off"; $c2 = (Get-Config).$k
        if (-not ($r1.ok -and $r2.ok -and $c1 -eq $true -and $c2 -eq $false)) { $okAll = $false; Write-Host "    $k : $($r1.message) / $($r2.message)" }
    }
    Check 'do set: все шесть переключателей on/off' $okAll
    $r = Invoke-Do 'set:notify=off'
    Check 'do set: то же значение — без изменений, без точки отмены' ($r.ok -and -not $r.undo -and $r.message -like '*без изменений*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'set:lang=en'
    Check 'do set:lang=en: язык и ответ на новом языке' ($r.ok -and (Get-Config).lang -eq 'en' -and $r.message -eq 'Language: English') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после lang: русский' ($r.ok -and $script:Lang -eq 'ru' -and $r.message -eq 'Отменено') ($r | ConvertTo-Json -Compress)
    $r1 = Invoke-Do 'set:notify=maybe'; $r2 = Invoke-Do 'set:bogus=on'; $r3 = Invoke-Do 'set:lang=de'
    Check 'do set: мусор отвергается' (-not $r1.ok -and -not $r2.ok -and -not $r3.ok)
    Set-Content $ConfigPath '{}' -Encoding UTF8; Remove-LastAction

    # действия с аккаунтами
    $acc0 = Get-Content $AccountsPath -Raw -Encoding UTF8
    $r = Invoke-Do "account:${tp}:main"
    Check 'do account main: основной сменился, отмена доступна' ($r.ok -and $r.undo -and (Get-MainPuuid) -eq $tp -and $r.message -like 'Основной аккаунт*') ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после main: accounts.json как был' ($r.ok -and (Get-MainPuuid) -eq 'mainmainmain' -and (Get-Content $AccountsPath -Raw -Encoding UTF8) -ceq $acc0) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do "account:${tp}:own"
    Check 'do account own' ($r.ok -and (Read-Accounts)[$tp].own -eq $true) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do "account:${tp}:notown"
    Check 'do account notown' ($r.ok -and (Read-Accounts)[$tp].own -eq $false) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do "account:${tp}:forget"
    Check 'do account forget: убран из списка' ($r.ok -and -not (Read-Accounts).ContainsKey($tp)) ($r | ConvertTo-Json -Compress)
    $r = Invoke-Do 'undo'
    Check 'do undo после forget: аккаунт вернулся' ($r.ok -and (Read-Accounts).ContainsKey($tp)) ($r | ConvertTo-Json -Compress)
    $r1 = Invoke-Do 'account:mainmainmain:own'; $r2 = Invoke-Do "account:${tp}:dance"; $r3 = Invoke-Do 'account:nobody:main'
    Check 'do account: основной «мой», неизвестное действие и аккаунт — ошибки' (-not $r1.ok -and -not $r2.ok -and -not $r3.ok)
    Remove-LastAction
    $cap = @(& { Write-DoJson 'set:badge=off'; $null = Invoke-Do 'undo' } *>&1)
    Check 'do set: в stdout ровно одна строка JSON' ($cap.Count -eq 1 -and $cap[0] -is [string] -and (($cap[0] | ConvertFrom-Json).ok)) ($cap -join ' | ')
    $capL = @(& { Write-ListJson 'pros' } *>&1)
    Check 'list: в stdout ровно одна строка' ($capL.Count -eq 1 -and $capL[0] -is [string] -and $capL[0].StartsWith('[')) ($capL -join ' | ')
    Set-Content $ConfigPath '{}' -Encoding UTF8
    $script:Quiet = $false

    # сборка приложения из вшитых исходников (WPF + WinForms + System.Net.Http должны находиться)
    $AppSources = @{ 'T.cs' = 'using System; class P { [STAThread] static void Main() { var w = new System.Windows.Window(); var n = new System.Windows.Forms.NotifyIcon(); } }' }
    $AppExe = Join-Path $tmp 'app-test.exe'; $AppSrcDir = Join-Path $tmp 'app-src-test'; $AppHashPath = Join-Path $AppSrcDir 'hash.txt'
    try { Build-App; $okb = (Test-Path $AppExe) -and (Test-Path "$AppSrcDir\T.cs") -and (Test-Path $AppHashPath) } catch { $okb = $false; $eb = $_.Exception.Message }
    Check 'Build-App: исходники → exe со ссылками на WPF/WinForms' $okb "$eb"

    Write-Host 'режим lib: Invoke-Core и кэши'
    $profKeep = Get-Content $ProfilePath -Raw -Encoding UTF8; $srcKeep = Get-Content $SourcePath -Raw -Encoding UTF8
    & {
        . "$proj\src\valset.ps1" lib
        Check 'lib: функции загружены, switch не выполнялся (нет exit, Lib=true, Fancy=false)' ((Get-Command Invoke-Core -ErrorAction SilentlyContinue) -and $script:Lib -and -not $script:Fancy)
        $GameProc = 'valset-test-no-such-process'
        function Update-Agent {}; function Save-Graphics { $false }; function Sync-Graphics {}; function Invoke-ApplyGraphics { 0 }
        function Get-Session { $script:sess }; function Get-RiotId($s) { $script:idCalls++; 'Тест#EU' }
        $script:reads = 0; $script:idCalls = 0
        function Read-CloudSettings($s) { $script:reads++; $script:cloud }
        function Invoke-RestMethod { throw 'сеть в тестах не нужна' }
        Clear-SettingsCache
        $a = Get-Settings $script:sess; $b = Get-Settings $script:sess
        Check 'Get-Settings: второй вызов в пределах 60 с из кэша (облако читано 1 раз)' ($script:reads -eq 1 -and $a -ceq $b) "reads=$($script:reads)"
        $null = Get-Settings $script:sess -Fresh
        Check 'Get-Settings -Fresh / Assert-Written читают облако, не кэш' ($script:reads -eq 2)
        $script:cloud = '{"floatSettings":[{"settingEnum":"EAresFloatSettingName::MouseSensitivity","value":0.5}]}'
        Assert-Written $script:sess $script:cloud 'тест'
        Check 'Assert-Written видит новое значение облака (кэш обойдён)' ($script:reads -eq 3)
        $thrown = $false; try { Assert-Written $script:sess $cloud0 'тест' } catch { $thrown = $true }
        Check 'Assert-Written: расхождение с облаком — ошибка' $thrown
        $script:cloud = $cloud0; Clear-SettingsCache; $script:reads = 0
        $null = Get-Settings $script:sess
        function Set-CloudRaw { }   # Set-Settings должен сбросить кэш (сеть заглушена выше — запись упадёт, кэш всё равно сброшен)
        try { Set-Settings $script:sess '{}' } catch {}
        $null = Get-Settings $script:sess
        Check 'Set-Settings сбрасывает кэш (следующее чтение — из облака)' ($script:reads -eq 2) "reads=$($script:reads)"
        # игра запущена → кэш не используется
        $GameProc = 'powershell'; Clear-SettingsCache; $script:reads = 0
        $null = Get-Settings $script:sess; $null = Get-Settings $script:sess
        Check 'игра запущена: каждое чтение из облака' ($script:reads -eq 2) "reads=$($script:reads)"
        $GameProc = 'valset-test-no-such-process'
        # Invoke-Core
        Clear-SettingsCache; $script:reads = 0
        $js = Invoke-Core 'state'; $o = $js | ConvertFrom-Json
        Check 'Invoke-Core state: одна строка JSON с account' ($js -is [string] -and $js.StartsWith('{') -and $o.account -eq 'Тест#EU' -and $o.puuid -eq $tp) $js
        $js2 = Invoke-Core 'state'
        Check 'Invoke-Core state: второй вызов без чтения облака и сети за именем' ($script:reads -eq 1 -and $js2 -ceq $js) "reads=$($script:reads)"
        $d = (Invoke-Core 'do' 'save') | ConvertFrom-Json
        Check 'Invoke-Core do save: JSON ok:true' ($d.ok -eq $true) ($d | ConvertTo-Json -Compress)
        Check 'do читает облако заново (кэш сброшен перед записью)' ($script:reads -ge 2) "reads=$($script:reads)"
        $d2 = (Invoke-Core 'do' 'нет-такого') | ConvertFrom-Json
        Check 'Invoke-Core do: ошибка — JSON ok:false, без исключения' ($d2.ok -eq $false -and $d2.message)
        $l = Invoke-Core 'list' 'accounts'
        Check 'Invoke-Core list accounts: JSON-массив' ($l.StartsWith('[')) $l
        $e = (Invoke-Core 'list' 'нет') | ConvertFrom-Json
        Check 'Invoke-Core list: неизвестный вид — JSON с error' ($e.ok -eq $false -and $e.error)
        $env:VALSET_GAME_TOKEN = $null
        Check 'Invoke-Core watch: возвращает {} и убирает токен игры' ((Invoke-Core 'watch' '' '{"x":1}') -eq '{}' -and -not $env:VALSET_GAME_TOKEN)
    }
    $script:Lib = $false; $script:Fancy = $false
    Write-FileSafe $ProfilePath $profKeep; Write-FileSafe $SourcePath $srcKeep

    Write-Host 'сборка'
    $b = powershell -NoProfile -ExecutionPolicy Bypass -File "$proj\build.ps1" 2>&1
    Check 'build.ps1 без ошибок' ($LASTEXITCODE -eq 0) "$b"
    $out = cmd /c "`"$proj\dist\valset.cmd`" status" 2>&1 | Out-String
    Check 'dist\valset.cmd запускается' ($out -match 'Аккаунт') ($out.Substring(0, [Math]::Min(300, $out.Length)))
    $env:VALSET_LANG = 'en'
    $outEn = cmd /c "`"$proj\dist\valset.cmd`" status" 2>&1 | Out-String
    $env:VALSET_LANG = 'ru'
    Check 'английский интерфейс: status' ($outEn -match 'Account' -and $outEn -notmatch 'Аккаунт') ($outEn.Substring(0, [Math]::Min(300, $outEn.Length)))
    Check 'собранный файл без BOM' (((Get-Content "$proj\dist\valset.cmd" -Encoding Byte -TotalCount 3) -join ',') -ne '239,187,191')
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:VALSET_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:VALSET_LANG -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("итого: {0} ок, {1} ошибок" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail
