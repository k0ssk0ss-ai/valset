# app.ps1 — трей-приложение VALSET (исходник — src\app\*.cs) вместо сторожа из agent.ps1.
# Собирается на ПК пользователя (как сторож): без подписи и без скачанного exe. Исходники берутся из src\app\ при запуске
# из исходников, а в dist\valset.cmd вшиты build.ps1 строками в $AppSources (имя → текст). Перед сборкой пишутся в app-src\.
# Запуск: Run\VALSET → `valset-app-1.exe "<valset.cmd>"`; протокол valset: (кнопки в уведомлениях) → то же + аргумент `valset:<действие>`.
# Один экземпляр — мьютекс Local\valset-app; остановка — событие Local\valset-app-stop.

$AppExe      = Join-Path $Root 'valset-app-1.exe'
$AppSrcDir   = Join-Path $Root 'app-src'
$AppHashPath = Join-Path $Root 'app-src\hash.txt'   # отпечаток исходников, из которых собран exe: изменились — пересобрать
$AppMutex    = 'Local\valset-app'
$AppStopName = 'Local\valset-app-stop'
$ProtoKey    = 'HKCU:\Software\Classes\valset'
$AppSources  = @{}
# @@APP-SOURCES@@ — build.ps1 заменяет эту строку на `$AppSources['имя.cs'] = @'…'@` для каждого src\app\*.cs

function Get-AppSources {
    if ($AppSources.Count) { return $AppSources }
    $h = @{}
    $d = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'app' }
    if ($d -and (Test-Path $d)) { foreach ($f in Get-ChildItem $d -Filter '*.cs') { $h[$f.Name] = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) } }
    $h
}

function Get-AppHash($src) {
    $text = (@($src.Keys | Sort-Object) | ForEach-Object { "$_`n$($src[$_])" }) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '')
}

# Пути к сборкам .NET 4.8 из Windows (WPF, WinForms для значка в трее, HTTP и т. п.).
function Get-AppReferences {
    foreach ($n in 'PresentationFramework', 'PresentationCore', 'WindowsBase', 'System.Xaml', 'System.Windows.Forms', 'System.Drawing', 'System.Xml', 'System.Core', 'System.Web.Extensions') {
        try { Add-Type -AssemblyName $n } catch { continue }
        $a = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $n } | Select-Object -First 1
        if ($a) { $a.Location }
    }
    [psobject].Assembly.Location   # System.Management.Automation: ядро в runspace приложения (InProc.cs)
}

function Build-App($src) {
    if (-not $src) { $src = Get-AppSources }
    if (-not $src.Count) { throw (L 'В этой сборке нет исходников приложения (src\app).' 'This build has no app sources (src\app).') }
    if (Test-Path $AppSrcDir) { Remove-Item -LiteralPath $AppSrcDir -Recurse -Force }
    New-Item -ItemType Directory -Force $AppSrcDir | Out-Null
    $files = foreach ($k in ($src.Keys | Sort-Object)) {
        $p = Join-Path $AppSrcDir $k
        [IO.File]::WriteAllText($p, $src[$k], (New-Object Text.UTF8Encoding $true))   # BOM — компилятор иначе читает кириллицу как ANSI
        $p
    }
    $tmp = [IO.Path]::ChangeExtension($AppExe, '.new.exe')   # расширение не .exe — компилятор соберёт библиотеку
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
    Add-Type -Path $files -OutputAssembly $tmp -OutputType WindowsApplication -ReferencedAssemblies @(Get-AppReferences)
    if (Test-Path $AppExe) { Remove-Item -LiteralPath $AppExe -Force }
    Move-Item -LiteralPath $tmp -Destination $AppExe
    [IO.File]::WriteAllText($AppHashPath, (Get-AppHash $src))
    Log "приложение собрано: $(Split-Path $AppExe -Leaf) ($($files.Count) файл.)"
}

function Set-RegValue([string]$path, [string]$name, [string]$value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    if ((Get-ItemProperty $path -Name $name -ErrorAction SilentlyContinue).$name -ne $value) { Set-ItemProperty $path -Name $name -Value $value }
}

function Test-AppRunning { Test-NamedMutex $AppMutex }

# Остановить приложение: сигнал, а если не вышло (версии 2.0.0 до исправления не завершались) — завершить процесс по пути exe.
function Stop-App {
    Send-Stop $AppStopName { Test-AppRunning }
    $full = [IO.Path]::GetFullPath($AppExe)
    foreach ($p in Get-Process ([IO.Path]::GetFileNameWithoutExtension($AppExe)) -ErrorAction SilentlyContinue) {
        if ($p.Path -eq $full) { try { $p.Kill(); [void]$p.WaitForExit(3000) } catch { } }
    }
}

function Enable-App {
    if (-not (Test-Path $InstalledCmd)) { throw (L 'Сначала установи VALSET: valset.cmd install' 'Install VALSET first: valset.cmd install') }
    $src = Get-AppSources
    $fresh = (Test-Path $AppExe) -and (Test-Path $AppHashPath) -and (([IO.File]::ReadAllText($AppHashPath)).Trim() -eq (Get-AppHash $src))
    if (-not $fresh) {
        if (Test-AppRunning) { Stop-App }   # старый exe занят — остановить и пересобрать
        Build-App $src
    }
    # старый сторож: приложение его заменяет
    if (Test-OldAgentRunning) { Send-Stop $AgentStopName { Test-OldAgentRunning } }
    foreach ($old in Get-ChildItem $Root -Filter 'valset-agent-*.exe' -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $old.FullName -ErrorAction SilentlyContinue }
    Set-RegValue $RunKey 'VALSET' "`"$AppExe`" `"$InstalledCmd`""
    # протокол valset: — кнопки в уведомлениях открывают приложение с аргументом valset:<действие>
    Set-RegValue $ProtoKey '(default)' 'URL:VALSET'
    Set-RegValue $ProtoKey 'URL Protocol' ''
    Set-RegValue "$ProtoKey\shell\open\command" '(default)' "`"$AppExe`" `"$InstalledCmd`" `"%1`""
    if (-not (Test-AppRunning)) { Start-Process $AppExe -ArgumentList "`"$InstalledCmd`"" }
}

# Приложение выключено (config.app = false): убрать автозапуск и остановить.
function Disable-App {
    Remove-ItemProperty $RunKey -Name 'VALSET' -ErrorAction SilentlyContinue
    if (Test-AppRunning) { Stop-App }
}

# Удаление: автозапуск, протокол, exe и исходники.
function Remove-App {
    Disable-App
    if (Test-Path $ProtoKey) { Remove-Item $ProtoKey -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($p in $AppExe, [IO.Path]::ChangeExtension($AppExe, '.new.exe')) { if (Test-Path $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
    if (Test-Path $AppSrcDir) { Remove-Item -LiteralPath $AppSrcDir -Recurse -Force -ErrorAction SilentlyContinue }
}
