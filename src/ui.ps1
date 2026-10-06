# ui.ps1 — оформление консоли: баннер, экраны, список со стрелками, шаги с полосой, главное меню.
# Подключается из valset.ps1 (dot-source), использует его функции и переменные.

function Write-Banner {
    $val = @(
        '██╗   ██╗ █████╗ ██╗     '
        '██║   ██║██╔══██╗██║     '
        '██║   ██║███████║██║     '
        '╚██╗ ██╔╝██╔══██║██║     '
        ' ╚████╔╝ ██║  ██║███████╗'
        '  ╚═══╝  ╚═╝  ╚═╝╚══════╝'
    )
    $set = @(
        '███████╗███████╗████████╗'
        '██╔════╝██╔════╝╚══██╔══╝'
        '███████╗█████╗     ██║   '
        '╚════██║██╔══╝     ██║   '
        '███████║███████╗   ██║   '
        '╚══════╝╚══════╝   ╚═╝   '
    )
    $h = 40; try { $h = [Console]::WindowHeight } catch {}
    if ($h -lt 34) {   # низкое окно — однострочная шапка, чтобы меню влезло целиком
        Write-Host ''
        Write-Host -NoNewline '  VAL' -ForegroundColor Red; Write-Host -NoNewline 'SET' -ForegroundColor White
        Write-Host "  ♦ $(L 'твои настройки VALORANT на любом аккаунте' 'your VALORANT settings on any account') · v$Version" -ForegroundColor DarkGray
        return
    }
    Write-Host ''
    for ($r = 0; $r -lt $val.Count; $r++) {
        Write-Host -NoNewline '  '
        Write-Host -NoNewline $val[$r] -ForegroundColor Red
        Write-Host $set[$r] -ForegroundColor White
    }
    Write-Host "  ♦ $(L 'твои настройки VALORANT на любом аккаунте' 'your VALORANT settings on any account') · v$Version" -ForegroundColor DarkGray
}

function Write-Section([string]$title) {
    Write-Host ''
    Write-Host -NoNewline '  ♦ ' -ForegroundColor Red
    Write-Host -NoNewline "$title " -ForegroundColor White
    Write-Host ('─' * [Math]::Max(4, 56 - $title.Length)) -ForegroundColor DarkGray
}

# Отдельный экран действия: в меню стирает терминал и рисует компактную шапку.
function Write-Screen([string]$title) {
    if ($script:InMenu) { Clear-Host }
    Write-Host ''
    Write-Host -NoNewline '  VAL' -ForegroundColor Red
    Write-Host -NoNewline 'SET ' -ForegroundColor White
    Write-Host -NoNewline '♦ ' -ForegroundColor Red
    Write-Host -NoNewline "$title " -ForegroundColor White
    Write-Host ('─' * [Math]::Max(4, 50 - $title.Length)) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Field([string]$label, [string]$value, [string]$color = 'Gray') {
    Write-Host -NoNewline '    • ' -ForegroundColor $color
    Write-Host -NoNewline $label.PadRight(13) -ForegroundColor DarkGray
    Write-Host $value -ForegroundColor $color
}

function Write-Ok([string]$msg)   { Write-Host ''; Write-Host "    √ $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host ''; Write-Host "    × $msg" -ForegroundColor Red }
function Write-Note([string]$msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }

function Wait-AnyKey([string]$text = (L 'любая клавиша — назад' 'any key — back')) {
    Write-Host ''
    Write-Host "    $text" -ForegroundColor DarkGray
    [void](Read-KeyOrQuit)
}

# Ждёт клавишу; если открыли новое окно меню (оно подаёт сигнал), это окно тихо закрывается.
function Read-KeyOrQuit {
    while ($true) {
        try { if ([Console]::KeyAvailable) { break } } catch { break }   # ввод не с консоли — читаем как есть
        if ($script:QuitEvent -and $script:QuitEvent.WaitOne(50)) {
            try { $script:MenuMutex.ReleaseMutex() } catch {}
            [Environment]::Exit(0)
        }
        if (-not $script:QuitEvent) { Start-Sleep -Milliseconds 50 }
    }
    [Console]::ReadKey($true)
}

function Confirm-Key([string]$question) {
    Write-Host -NoNewline "    ? $question " -ForegroundColor Yellow
    Write-Host -NoNewline '[y/n] ' -ForegroundColor DarkGray
    $k = "$((Read-KeyOrQuit).KeyChar)"
    Write-Host $k
    $k -in 'y', 'Y', 'н', 'Н'   # н — та же клавиша на русской раскладке
}

# ── Список со стрелками ───────────────────────────────────────────────────────

# Пункт с вариантами (Opts): варианты в той же строке, ←→ переключают, Id берётся у выбранного варианта.
function New-MenuEntry([string]$label, [string]$hint = '', [string]$id = '', [object[]]$Opts = $null) {
    [pscustomobject]@{ Label = $label; Hint = $hint; Id = $id; Sep = $false; Opts = $Opts; Opt = 0 }
}
function New-MenuOpt([string]$label, [string]$id, [string]$hint) { [pscustomobject]@{ L = $label; Id = $id; Hint = $hint } }
function Get-EntryId($it) { if ($it.Opts) { $it.Opts[$it.Opt].Id } else { $it.Id } }
function New-MenuSep([string]$label) { [pscustomobject]@{ Label = $label; Hint = ''; Id = ''; Sep = $true } }

$script:RowWidth = 78
function Write-ItemRow($it, [bool]$on, [string]$num = '') {
    if ($it.Sep) {
        $t = "  ── $($it.Label) "
        Write-Host ($t + ('─' * [Math]::Max(2, 40 - $t.Length))).PadRight($script:RowWidth) -ForegroundColor DarkGray
        return
    }
    $num = $num.PadLeft(2)
    if ($on) { Write-Host -NoNewline "$num ► " -ForegroundColor Red } else { Write-Host -NoNewline "$num   " -ForegroundColor DarkGray }
    $used = 5
    if ($it.Opts) {
        $label = " $($it.Label) ".PadRight([Math]::Max(13, [int]$script:OptLabelW))
        if ($on) { Write-Host -NoNewline $label -ForegroundColor White -BackgroundColor DarkRed } else { Write-Host -NoNewline $label -ForegroundColor Gray }
        $used += $label.Length
        for ($j = 0; $j -lt $it.Opts.Count; $j++) {
            $t = " $($it.Opts[$j].L) "
            if ($j -eq $it.Opt) {
                if ($on) { Write-Host -NoNewline $t -ForegroundColor Black -BackgroundColor Gray }
                else     { Write-Host -NoNewline $t -ForegroundColor Gray -BackgroundColor DarkGray }
            } else { Write-Host -NoNewline $t -ForegroundColor DarkGray }
            $used += $t.Length
        }
        $hint = "$($it.Opts[$it.Opt].Hint)"
    } else {
        $label = " $($it.Label) ".PadRight(30)
        if ($on) { Write-Host -NoNewline $label -ForegroundColor White -BackgroundColor DarkRed } else { Write-Host -NoNewline $label -ForegroundColor Gray }
        $used += $label.Length
        $hint = "$($it.Hint)"
    }
    $room = $script:RowWidth - $used - 2
    if ($hint.Length -gt $room) { $hint = if ($room -gt 1) { $hint.Substring(0, $room - 1) + '…' } else { '' } }
    Write-Host -NoNewline " $hint" -ForegroundColor $(if ($on) { 'Gray' } else { 'DarkGray' })
    Write-Host (' ' * [Math]::Max(0, $script:RowWidth - $used - 1 - $hint.Length))
}

# Рисует экран со списком и ждёт выбора. Возвращает индекс пункта или -1 (Esc / ←).
# Стрелки двигают выделение, цифры 1–9 выбирают пункт сразу.
# При перемещении перерисовываются только две строки — без мерцания.
function Select-Item {
    param([string]$Title, [object[]]$Items, [int]$Start = 0, [scriptblock]$Header,
          [string]$Footer = (L '↑↓ выбор · Enter — открыть · цифра — сразу · Esc — назад' '↑↓ select · Enter — open · digit — jump · Esc — back'))
    $idx = @(for ($n = 0; $n -lt $Items.Count; $n++) { if (-not $Items[$n].Sep) { $n } })
    # строки с вариантами — общая ширина названия по самому длинному (языки разной длины)
    $script:OptLabelW = 2 + [int](@($Items | Where-Object { $_.Opts } | ForEach-Object { $_.Label.Length }) + 0 | Measure-Object -Maximum).Maximum
    if (-not $idx) { return -1 }
    $cur = if ($idx -contains $Start) { $Start } else { $idx[0] }
    $num = @{}
    for ($n = 0; $n -lt $idx.Count -and $n -lt 9; $n++) { $num[$idx[$n]] = "$($n + 1)" }

    if ($Title) { Write-Screen $Title } elseif ($script:InMenu) { Clear-Host }
    if ($Header) { & $Header }
    Write-Host ''
    for ($n = 0; $n -lt $Items.Count; $n++) { Write-ItemRow $Items[$n] ($n -eq $cur) "$($num[$n])" }
    Write-Host ''
    Write-Host "    $Footer" -ForegroundColor DarkGray
    if (@($Items | Where-Object { $_.Opts })) {
        Write-Host (L '    ←→ вариант в строке · две цифры сразу: 12 = пункт 1, вариант 2' '    ←→ option in the row · two digits: 12 = item 1, option 2') -ForegroundColor DarkGray
    }
    # Позиции считаем от конца: если список не влез и терминал прокрутился, верх уехал, а низ — нет.
    $end = [Console]::CursorTop
    $top = [Math]::Max(0, $end - $Items.Count - 2 - $(if (@($Items | Where-Object { $_.Opts })) { 1 } else { 0 }))
    $await = -1   # после цифры пункта с вариантами вторая цифра выбирает вариант
    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            $k = Read-KeyOrQuit
            $c = "$($k.KeyChar)"
            if ($await -ge 0) {
                $a = $await; $await = -1
                if ($c -match '^[1-9]$' -and [int]$c -le $Items[$a].Opts.Count) { $Items[$a].Opt = [int]$c - 1; return $a }
            }
            $p = [Array]::IndexOf($idx, $cur)
            $next = $cur
            $it = $Items[$cur]
            switch ("$($k.Key)") {
                'UpArrow'    { $next = $idx[($p - 1 + $idx.Count) % $idx.Count] }
                'DownArrow'  { $next = $idx[($p + 1) % $idx.Count] }
                'Home'       { $next = $idx[0] }
                'End'        { $next = $idx[-1] }
                'Enter'      { return $cur }
                'Escape'     { return -1 }
                'Backspace'  { return -1 }
                'RightArrow' {
                    if (-not $it.Opts) { return $cur }
                    if ($it.Opt -lt $it.Opts.Count - 1) { $it.Opt++; [Console]::SetCursorPosition(0, $top + $cur); Write-ItemRow $it $true "$($num[$cur])"; [Console]::SetCursorPosition(0, $end) }
                }
                'LeftArrow'  {
                    if (-not $it.Opts) { return -1 }
                    if ($it.Opt -gt 0) { $it.Opt--; [Console]::SetCursorPosition(0, $top + $cur); Write-ItemRow $it $true "$($num[$cur])"; [Console]::SetCursorPosition(0, $end) }
                }
                default {
                    if ($c -eq '?' -or $c -eq ',') { for ($n = 0; $n -lt $Items.Count; $n++) { if ($Items[$n].Id -eq 'help') { return $n } } }
                    if ($c -match '^[1-9]$' -and [int]$c -le $idx.Count) {
                        $t = $idx[[int]$c - 1]
                        if (-not $Items[$t].Opts) { return $t }
                        $next = $t; $await = $t   # ждём цифру варианта; Enter — выбранный сейчас
                    }
                }
            }
            if ($next -ne $cur) {
                [Console]::SetCursorPosition(0, $top + $cur);  Write-ItemRow $Items[$cur] $false "$($num[$cur])"
                [Console]::SetCursorPosition(0, $top + $next); Write-ItemRow $Items[$next] $true "$($num[$next])"
                $cur = $next
                [Console]::SetCursorPosition(0, $end)
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

# ── Шаги с полосой ───────────────────────────────────────────────────────────

# Анимация полосы крутится в отдельном потоке ровно пока идёт настоящая работа — без искусственных пауз.
$script:BarWidth = 18
$script:AnimRunspace = $null
$AnimScript = {
    param($sync, $title, $w)
    $i = 0
    while ($sync.Run) {
        $fill = [Math]::Min($w - 1, $i + 1)   # ~40 мс на деление, у края ждёт окончания
        [Console]::Write("`r    ")
        [Console]::ForegroundColor = 'Cyan';     [Console]::Write(('█' * $fill))
        [Console]::ForegroundColor = 'DarkGray'; [Console]::Write(('░' * ($w - $fill)))
        [Console]::ForegroundColor = 'Gray';     [Console]::Write("  $title")
        [Console]::ResetColor()
        Start-Sleep -Milliseconds 40
        $i++
    }
}

# Шаг: живая полоса во время действия, затем √ или ×.
# Локальные переменные с префиксом __, чтобы не перекрыть переменные вызывающего.
function Invoke-Step([string]$__title, [scriptblock]$__action) {
    if (-not $script:Fancy) { return (& $__action) }
    $__w = $script:BarWidth
    if (-not $script:AnimRunspace) {
        $script:AnimRunspace = [RunspaceFactory]::CreateRunspace()
        $script:AnimRunspace.Open()
    }
    $__sync = [hashtable]::Synchronized(@{ Run = $true })
    $__ps = [PowerShell]::Create()
    $__ps.Runspace = $script:AnimRunspace
    [void]$__ps.AddScript($AnimScript).AddArgument($__sync).AddArgument($__title).AddArgument($__w)
    try { [Console]::CursorVisible = $false } catch {}
    $__h = $__ps.BeginInvoke()
    try {
        try { $__result = & $__action }
        finally { $__sync.Run = $false; [void]$__ps.EndInvoke($__h); $__ps.Dispose() }
        Write-Host -NoNewline "`r    "
        Write-Host -NoNewline ('█' * $__w) -ForegroundColor Green
        Write-Host -NoNewline "  $__title " -ForegroundColor Gray
        Write-Host '√' -ForegroundColor Green
        return $__result
    } catch {
        Write-Host -NoNewline "`r    "
        Write-Host -NoNewline ('█' * $__w) -ForegroundColor Red
        Write-Host -NoNewline "  $__title " -ForegroundColor Gray
        Write-Host '×' -ForegroundColor Red
        throw
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}
