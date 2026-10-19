# install.ps1 — установка: папка, команда valset в PATH, ярлык «VALSET» в «Пуске» (консольное меню) и трей-приложение (app.ps1).
# Ярлыков на рабочем столе нет: Valorant запускается как обычно. Ctrl+Alt+V и valset-open-1.exe убраны в 2.0.0 —
# вместо них значок у часов; старый exe при установке и удалении удаляется.

$OpenExe = Join-Path $Root 'valset-open-1.exe'   # только для чистки: 1.x ставили сюда защиту хоткея

function Invoke-Install {
    if ($Self -notlike '*.cmd') { throw (L 'Устанавливается собранный файл: запусти build.ps1, затем dist\valset.cmd install.' 'Install the built file: run build.ps1, then dist\valset.cmd install.') }
    New-Item -ItemType Directory -Force $Root | Out-Null
    if ($Self -ne $InstalledCmd) { Copy-Item $Self $InstalledCmd -Force }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $Root) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';'), $Root) -join ';').TrimStart(';'), 'User')
    }

    # Старые версии ставили ярлык «VALORANT (VALSET)» на рабочий стол — он больше не нужен.
    foreach ($p in $LaunchLnk, $LaunchVbs) { if (Test-Path $p) { Remove-Item -LiteralPath $p } }

    # Ярлык консольного меню в «Пуске» — запасной путь; горячей клавиши у него больше нет (старую снимаем).
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($MenuLnk)
    $sc.TargetPath = $InstalledCmd
    $sc.Arguments = ''
    $sc.WorkingDirectory = $Root
    $sc.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $sc.Hotkey = ''
    $sc.Save()
    if (Test-Path $OpenExe) { Remove-Item -LiteralPath $OpenExe -ErrorAction SilentlyContinue }

    # Трей-приложение: собирается из исходника на этом ПК, запускается с Windows (выключается в настройках: config.app).
    $appErr = $null
    try { Update-Agent } catch { $appErr = $_.Exception.Message; Log "приложение не запущено: $appErr" }

    Log "установлено в $($Root): значок в трее, консоль — ярлык и команда valset"
    Write-Ok "$(L 'Установлено в' 'Installed to') $Root"
    if ($appErr) { Write-Note "$(L 'Значок в трее не запустился' 'The tray icon did not start'): $appErr" }
    else { Write-Note (L 'Значок VALSET — у часов (трей), запускается с Windows. Выключить: в настройках его окна.' 'The VALSET icon is near the clock (tray) and starts with Windows. Turn it off: in its window settings.') }
    Write-Note (L 'Консоль: ярлык «VALSET» в меню Пуск или команда valset в новом терминале.' 'Console: the “VALSET” shortcut in the Start menu, or run valset in a new terminal.')
    # Дальше всё в панели у часов (там же один раз спросит про автоперенос) — открыть её; консоль больше не нужна.
    $script:PanelOpened = $false
    if (-not $appErr -and (Test-AppRunning)) {
        try { Start-Process $AppExe -ArgumentList "`"$InstalledCmd`" valset:open"; $script:PanelOpened = $true } catch { Log "панель не открылась: $($_.Exception.Message)" }
    }
}

# Версия установленного valset.cmd (строка $Version = '...'), $null — не установлен.
function Get-InstalledVersion {
    if (-not (Test-Path $InstalledCmd)) { return $null }
    $m = Select-String -Path $InstalledCmd -Pattern "^\`$Version = '(.+)'" -Encoding UTF8 | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
}

# Запущен скачанный файл (не из папки установки) — предложить установку или обновление.
function Invoke-InstallOffer {
    if ($Self -notlike '*.cmd' -or $Self -eq $InstalledCmd) { return }
    $have = Get-InstalledVersion
    if ($have -eq $Version) { return }
    Clear-Host; Write-Banner; Write-Host ''
    if ($have) {
        Write-Host (L "    Установлена версия $have, это — $Version." "    Installed: version $have, this file: $Version.") -ForegroundColor Gray
        $q = L 'Обновить? Твои настройки и бэкапы останутся' 'Update? Your settings and backups stay'
    } else {
        Write-Host (L '    Установка: папка %USERPROFILE%\valset, команда valset, ярлык в Пуске, значок у часов.' '    Installs to %USERPROFILE%\valset, adds the valset command, a Start-menu shortcut and a tray icon.') -ForegroundColor Gray
        Write-Host (L '    Значок запускается с Windows (собирается на этом ПК из исходника); выключается в его окне.' '    The icon starts with Windows (built on this PC from source); turn it off in its window.') -ForegroundColor Gray
        $q = L 'Установить VALSET?' 'Install VALSET?'
    }
    Write-Host ''
    if (-not (Confirm-Key $q)) { return $false }
    Invoke-Install | Out-Null
    if ($script:PanelOpened) {
        Write-Note (L 'Панель VALSET открыта у часов. Это окно закроется само.' 'The VALSET panel is open near the clock. This window will close by itself.')
        Start-Sleep -Seconds 4; return $true
    }
    Wait-AnyKey (L 'любая клавиша — открыть меню' 'any key — open the menu'); $false
}

function Invoke-Uninstall {
    Disable-Agent
    Remove-App
    foreach ($p in $MenuLnk, $LaunchLnk, $LaunchVbs, $OpenExe) { if (Test-Path $p) { Remove-Item -LiteralPath $p } }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (($userPath -split ';' | Where-Object { $_ -and $_ -ne $Root }) -join ';'), 'User')
    Log 'программа удалена (мои настройки и бэкапы оставлены)'
    Write-Ok (L "Ярлык, команда и значок в трее убраны. Твои настройки и бэкапы остались в $Root" "Shortcut, command and tray icon removed. Your settings and backups remain in $Root")
    if ($Self -eq $InstalledCmd) { Write-Note (L 'сам valset.cmd удали вручную, если он больше не нужен' 'delete valset.cmd itself manually if you no longer need it') }
    elseif (Test-Path $InstalledCmd) { Remove-Item -LiteralPath $InstalledCmd }
}
