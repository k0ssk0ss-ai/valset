# install.ps1 — установка: папка, команда valset в PATH, ярлык в «Пуске» с Ctrl+Alt+V.
# Ярлыков на рабочем столе нет: Valorant запускается как обычно, переносом занимается автоперенос (agent.ps1).
#
# Ctrl+Alt+V запускает не меню, а крошечную программу без окна (valset-open-1.exe): если на переднем плане игра —
# она ничего не делает (любое окно отобрало бы фокус и свернуло полноэкранную игру), иначе открывает меню.

$OpenExe = Join-Path $Root 'valset-open-1.exe'
$OpenSrc = @"
using System; using System.Diagnostics; using System.Runtime.InteropServices;
static class ValsetOpen {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    static void Main(string[] args) {
        if (args.Length < 1) return;
        uint fg; GetWindowThreadProcessId(GetForegroundWindow(), out fg);
        foreach (var p in Process.GetProcessesByName("VALORANT-Win64-Shipping")) {
            bool active = p.Id == fg; p.Dispose();
            if (active) return;   // идёт игра — не мешаем
        }
        var si = new ProcessStartInfo(args[0]);
        si.UseShellExecute = true; si.WorkingDirectory = System.IO.Path.GetDirectoryName(args[0]);
        try { Process.Start(si); } catch { }
    }
}
"@

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

    # Ярлык меню в «Пуске» с горячей клавишей (Windows ловит хоткеи только у ярлыков Пуска/рабочего стола).
    $ws = New-Object -ComObject WScript.Shell
    $guard = $true
    try { if (-not (Test-Path $OpenExe)) { Add-Type -TypeDefinition $OpenSrc -OutputAssembly $OpenExe -OutputType WindowsApplication } }
    catch { $guard = $false; Log "защита Ctrl+Alt+V в игре недоступна: $($_.Exception.Message)" }
    $sc = $ws.CreateShortcut($MenuLnk)
    if ($guard) { $sc.TargetPath = $OpenExe; $sc.Arguments = "`"$InstalledCmd`"" }
    else        { $sc.TargetPath = $InstalledCmd }
    $sc.WorkingDirectory = $Root
    $sc.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
    $sc.Hotkey = 'Ctrl+Alt+V'
    $sc.Save()

    # Помощник в фоне — только если человек сам включил его раньше (config.json); по умолчанию выключен.
    $helper = $true
    try { Update-Agent } catch { $helper = $false; Log "помощник не запущен: $($_.Exception.Message)" }

    Log "установлено в $($Root): меню по Ctrl+Alt+V"
    Write-Ok "$(L 'Установлено в' 'Installed to') $Root"
    Write-Note (L 'Меню: Ctrl+Alt+V. Не срабатывает — ярлык «VALSET» в меню Пуск (сочетание иногда' 'Menu: Ctrl+Alt+V. Not working? Use the “VALSET” shortcut in the Start menu (the hotkey')
    Write-Note (L '      заработает только после перезахода в Windows) или команда valset в новом терминале.' '      sometimes needs a Windows sign-out) or run valset in a new terminal.')
    $c = Get-Config
    if ($helper -and ($c.notify -or $c.autoApply)) { Write-Note (L 'Помощник в фоне включён, как ты выбрал раньше (отключается в меню).' 'Background helper is on, as you chose before (turn off in the menu).') }
    else { Write-Note (L 'Помощник в фоне выключен. По желанию в меню: уведомления и автоперенос.' 'Background helper is off. Optional in the menu: notifications and auto-apply.') }
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
        Write-Host (L '    Установка: папка %USERPROFILE%\valset, команда valset, меню по Ctrl+Alt+V.' '    Installs to %USERPROFILE%\valset, adds the valset command and the Ctrl+Alt+V menu.') -ForegroundColor Gray
        Write-Host (L '    Ничего не запускается в фоне без твоего выбора.' '    Nothing runs in the background unless you choose so.') -ForegroundColor Gray
        $q = L 'Установить VALSET?' 'Install VALSET?'
    }
    Write-Host ''
    if (Confirm-Key $q) { Invoke-Install; Wait-AnyKey (L 'любая клавиша — открыть меню' 'any key — open the menu') }
}

function Invoke-Uninstall {
    Disable-Agent
    foreach ($p in $MenuLnk, $LaunchLnk, $LaunchVbs, $OpenExe) { if (Test-Path $p) { Remove-Item -LiteralPath $p } }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (($userPath -split ';' | Where-Object { $_ -and $_ -ne $Root }) -join ';'), 'User')
    Log 'программа удалена (мои настройки и бэкапы оставлены)'
    Write-Ok (L "Ярлык, команда и автоперенос убраны. Твои настройки и бэкапы остались в $Root" "Shortcut, command and helper removed. Your settings and backups remain in $Root")
    if ($Self -eq $InstalledCmd) { Write-Note (L 'сам valset.cmd удали вручную, если он больше не нужен' 'delete valset.cmd itself manually if you no longer need it') }
    elseif (Test-Path $InstalledCmd) { Remove-Item -LiteralPath $InstalledCmd }
}
