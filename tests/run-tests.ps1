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
    1..12 | ForEach-Object { New-HistoryPoint "лишняя $_" }
    Check 'хранится не больше 10 версий' (@(Get-HistoryPoints).Count -eq 10)

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
    Check 'pros.json в репозитории разбирается' ($null -ne (Get-Content "$proj\pros.json" -Raw | ConvertFrom-Json).pros)

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
