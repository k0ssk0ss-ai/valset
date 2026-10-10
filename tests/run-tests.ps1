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

    Write-Host 'редактор: чтение'
    $vals = @{}
    foreach ($d in $SettingDefs) { $vals[$d.Label] = Format-Setting $d }
    Check 'все настройки читаются' ($vals.Count -eq $SettingDefs.Count)
    Check 'чувствительность 0.35'      ($vals['Чувствительность'] -eq '0.35') $vals['Чувствительность']
    Check 'снайперский — удержание'    ($vals['Снайперский прицел'] -eq 'удержание')
    Check 'статистика FPS — текст и график' ($vals['FPS'] -eq 'текст и график')
    Check 'разрешение 1920×1080'      ($vals['Разрешение'] -eq '1920×1080')
    Check 'лимит FPS 240'              ($vals['Лимит FPS'] -eq '240')
    Check 'нет ключа → стандарт игры'      ($vals['Качество текстур'] -eq 'стандарт игры (сейчас = высокое)')

    Write-Host 'редактор: запись и обратное чтение'
    $def = { param($l) $SettingDefs | Where-Object Label -eq $l }
    $cases = @(
        @('Чувствительность', 0.314, '0.314'), @('Снайперский прицел', $false, 'переключение'),
        @('Громкость музыки', (ConvertFrom-FreeInput (& $def 'Громкость музыки') '40'), '40%'),
        @('Разрешение', (ConvertFrom-FreeInput (& $def 'Разрешение') '1728 х 1080'), '1728×1080'),
        @('Лимит FPS', '144', '144'), @('Лимит FPS', 'off', 'без лимита'),
        @('NVIDIA Reflex', $null, 'стандарт'), @('Режим экрана', '1', 'оконный без рамки'), @('Кровь', $true, 'показывать'),
        @('Качество материалов', '2', 'среднее'), @('Качество материалов', $null, 'стандарт игры (сейчас = высокое)')
    )
    foreach ($c in $cases) {
        $d = & $def $c[0]
        Set-SettingValue $d $c[1]
        $got = Format-Setting $d
        Check "$($c[0]) → $($c[2])" ($got -eq $c[2]) "получено: $got"
    }
    $p = Read-Profile
    Check 'дублей настроек нет' (@($p.boolSettings | Where-Object settingEnum -like '*HoldInputForSniperScopes').Count -eq 1)
    $hp = @(Get-HistoryPoints)
    Check 'перед правкой — одна версия в истории' ($hp.Count -eq 1 -and $hp[0].Why -like '*«Изменить»*') "версий: $($hp.Count)"

    Write-Host 'бинды'
    Set-Bind $p 'Ping' 1 'G'
    $p = Read-Profile
    Check 'доп. клавиша пинга = G' ((Format-Key (Get-Binding $p 'Ping' 1)) -eq 'G')
    Check 'основная не тронута'    ((Format-Key (Get-Binding $p 'Ping' 0)) -eq 'Mouse5')
    Set-Bind $p 'Ping' 1 $null
    Check 'стандарт убирает запись' ($null -eq (Get-Binding (Read-Profile) 'Ping' 1))
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
    Check 'графика эталона записана'           (($after -match 'MaxFramerateAlways=144').Count -eq 1)
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
    Set-Bind $b 'Ping' 1 'G'
    $b = Read-Profile
    $sens = $b.floatSettings | Where-Object settingEnum -like '*MouseSensitivity' | Select-Object -First 1
    $sens.value = 0.5
    $d = Compare-Prefs $a $b
    $many = Compare-Prefs ([pscustomobject]@{ floatSettings = @(1..60 | ForEach-Object { @{ settingEnum = "EAresFloatSettingName::T$_"; value = 1 } }) }) ([pscustomobject]@{})
    Check 'отличия — массив: @() не падает (PowerShell 5.1 и List[object])' ($many -is [array] -and @($many).Count -ge 0)
    Check 'видно 2 отличия' ($d.Count -eq 2) "получено $($d.Count): $(($d | ForEach-Object What) -join '; ')"
    Check 'бинд подписан по-человечески' (@($d | Where-Object { $_.What -like 'Пинг*доп.*' -and $_.New -eq 'G' }).Count -eq 1)
    Check 'чувствительность 0.314 → 0.5' (@($d | Where-Object { $_.What -eq 'Чувствительность' -and $_.Old -eq '0.314' -and $_.New -eq '0.5' }).Count -eq 1)
    Check 'только бинды — 1 отличие' ((Compare-Prefs $a $b -BindsOnly).Count -eq 1)
    Set-Bind $b 'Ping' 1 $null

    Write-Host 'код для обмена'
    $code = New-ExportCode
    $imp = Read-ImportCode $code
    Check 'весь эталон: код читается обратно' ((ConvertTo-Json $imp.profile -Depth 32 -Compress) -eq (ConvertTo-Json (Read-Profile) -Depth 32 -Compress))
    Check 'графика в коде без изменений' ([IO.File]::ReadAllText($GfxIni) -eq $imp.gfxIniT)
    $ok = $true
    foreach ($n in 0..40) { $bytes = [byte[]](1..$n | ForEach-Object { Get-Random -Maximum 256 }); if ($n -eq 0) { $bytes = [byte[]]@() }
        if ([Convert]::ToBase64String((ConvertFrom-Cjk (ConvertTo-Cjk $bytes))) -ne [Convert]::ToBase64String($bytes)) { $ok = $false } }
    Check '14 бит в символ: туда и обратно, длины 0–40' $ok
    Check 'старый код VALSET1 читается' ((Read-ImportCode ('VALSET1:' + (Compress-Pref '{"v":1,"kind":"binds","profile":{"actionMappings":[]}}'))).kind -eq 'binds')
    Check 'пробелы и переносы в коде не мешают' ((Read-ImportCode ($code.Insert(20, " `r`n "))).kind -eq 'full')
    $bc = New-ExportCode -BindsOnly
    Check 'код биндов короче' ($bc.Length -lt $code.Length) "$($bc.Length) / $($code.Length)"
    Check 'код биндов — только бинды' (@((Read-ImportCode $bc).profile.PSObject.Properties.Name | Where-Object { $_ -notin $BindKeys }).Count -eq 0)
    $bad = $false; try { $null = Read-ImportCode ($code.Substring(0, 60)) } catch { $bad = $true }
    Check 'обрезанный код — понятная ошибка' $bad

    Write-Host 'несколько эталонов'
    Save-ProfileAs 'A'; Save-ProfileAs 'B'
    Check 'активный — B' ((Get-ActiveName) -eq 'B')
    Set-Bind (Read-Profile) 'Ping' 1 'K'
    Use-Profile 'A'
    Check 'переключение на A' ((Get-ActiveName) -eq 'A' -and $null -eq (Get-Binding (Read-Profile) 'Ping' 1))
    Check 'правка B сохранилась в его копии' ((Format-Key (Get-Binding (Get-Content "$env:VALSET_ROOT\profiles\B\profile.json" -Raw -Encoding UTF8 | ConvertFrom-Json) 'Ping' 1)) -eq 'K')
    Use-Profile 'B'
    Check 'обратно на B — с правкой' ((Format-Key (Get-Binding (Read-Profile) 'Ping' 1)) -eq 'K')
    Check 'графика ездит вместе с эталоном' (Test-Path "$env:VALSET_ROOT\profiles\A\graphics\GameUserSettings.ini")

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
    $one = & $mk @('A', 'B', 'C') 1
    Select-ActiveCrosshair $one
    $o = Get-Crosshairs $one
    Check 'один прицел: остался активный B' (@($o.profiles).Count -eq 1 -and $o.profiles[0].profileName -eq 'B' -and $o.currentProfile -eq 0)
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
    $script:ProfileBackedUp = $true; Set-SettingValue ($SettingDefs | Where-Object Label -eq 'Чувствительность') 0.777
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

    Write-Host 'шкала качества'
    Check 'знакомые значения — без предупреждения' (-not (Get-QualityOddities))
    Set-GfxRiot 'EAresIntSettingName::TextureQuality' '2'
    Check 'незнакомое значение замечено' ((Get-QualityOddities) -contains 'TextureQuality=2')
    Set-GfxRiot 'EAresIntSettingName::TextureQuality' $null

    Write-Host 'сборка'
    $b = powershell -NoProfile -ExecutionPolicy Bypass -File "$proj\build.ps1" 2>&1
    Check 'build.ps1 без ошибок' ($LASTEXITCODE -eq 0) "$b"
    $out = cmd /c "`"$proj\dist\valset.cmd`" status" 2>&1 | Out-String
    Check 'dist\valset.cmd запускается' ($out -match 'Автоперенос') ($out.Substring(0, [Math]::Min(300, $out.Length)))
    $env:VALSET_LANG = 'en'
    $outEn = cmd /c "`"$proj\dist\valset.cmd`" status" 2>&1 | Out-String
    $env:VALSET_LANG = 'ru'
    Check 'английский интерфейс: status' ($outEn -match 'Helper' -and $outEn -notmatch 'Помощник') ($outEn.Substring(0, [Math]::Min(300, $outEn.Length)))
    Check 'собранный файл без BOM' (((Get-Content "$proj\dist\valset.cmd" -Encoding Byte -TotalCount 3) -join ',') -ne '239,187,191')
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:VALSET_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:VALSET_LANG -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("итого: {0} ок, {1} ошибок" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail
