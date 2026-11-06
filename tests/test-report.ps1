# test-report.ps1 — «Сообщить об ошибке» (report.ps1): маскирование личного в диагностике и `do report`.
# Подключается из run-tests.ps1 (dot-source): там Check и загруженные функции ядра.

$fakePuuid = '0a1b2c3d-1111-2222-3333-444455556666'
$fakeLog = @(
    "2026-11-07 10:00:00 вошёл: Тестовый Ник#RU1 ($fakePuuid)"
    "2026-11-07 10:00:01 перенос на SomePlayer#EUW (0a1b2c3d)"
    "2026-11-07 10:00:02 файл $env:USERPROFILE\valset\profile.json"
    "2026-11-07 10:00:03 запрос: Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl"
    "2026-11-07 10:00:04 entitlement=eyJraWQiOiJzMSJ9.e30.sig token: abcdefSECRET123"
    "2026-11-07 10:00:05 путь C:\Users\SomeoneElse\AppData\Local"
) -join "`n"
$masked = Hide-Private $fakeLog @('Тестовый Ник#RU1') @($fakePuuid)
$leaks = @('Тестовый Ник', 'RU1', 'SomePlayer#EUW', $fakePuuid, '0a1b2c3d', $env:USERPROFILE, 'eyJ', 'abcdefSECRET123', 'SomeoneElse') |
    Where-Object { $masked.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
Check 'report: Riot ID, PUUID, путь профиля, токены не утекают' (-not $leaks) "утекло: $($leaks -join ', ') :: $masked"
Check 'report: метки на месте, время и текст журнала сохранены' ($masked -like '*<riot-id>*' -and $masked -like '*<puuid>*' -and $masked -like '*%USERPROFILE%\valset*' -and $masked -like '*Bearer <token>*' -and $masked -like '*2026-11-07 10:00:05 путь*') $masked

$logKeep = if (Test-Path $LogPath) { Get-Content $LogPath -Raw -Encoding UTF8 } else { $null }
Add-Content $LogPath "2026-11-07 10:00:06 вход $fakePuuid Bearer eyJabc.def.ghi" -Encoding UTF8
$hadUndo = Test-Path $LastActionPath
$r = Invoke-Do 'report'
Check 'do report: текст с версией, Windows, журналом; токенов и puuid нет; отмена не стёрта' ($r.ok -and $r.text -like "VALSET $Version*" -and $r.text -like '*Windows:*' -and $r.text -like '*valset.log*' -and $r.text -notlike '*eyJ*' -and $r.text -notlike "*$fakePuuid*" -and (Test-Path $LastActionPath) -eq $hadUndo) ($r | ConvertTo-Json -Compress)
if ($null -ne $logKeep) { Write-FileSafe $LogPath $logKeep } else { Remove-Item -LiteralPath $LogPath -ErrorAction SilentlyContinue }
