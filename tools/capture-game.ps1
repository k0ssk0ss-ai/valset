# capture-game.ps1 — ВРЕМЕННО: пишет в dist\capture-game.txt всё, что игра пишет в ShooterGame.log (новые строки)
# и каждые 2 с — GET-состояние pregame/coregame (только чтение; пишется только при изменении).
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-game.ps1 ; остановка: Ctrl+C или закрыть окно.
$ErrorActionPreference = 'Continue'
$here = Split-Path $PSScriptRoot -Parent
$out = Join-Path $here 'dist\capture-game.txt'
. (Join-Path $here 'src\valset.ps1') lib
function W([string]$tag, [string]$t) { Add-Content -Path $out -Value ("{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss.fff'), $tag, $t) -Encoding UTF8 }
W 'start' 'capture started'
$log = $GameLog
$fs = $null; $sr = $null; $pos = 0; $s = $null; $rt = $null; $last = @{}
$tick = 0
while ($true) {
    try {
        if (Test-Path $log) {
            if (-not $fs -or $fs.Length -lt $pos) {
                if ($sr) { $sr.Close() }
                $fs = New-Object IO.FileStream($log, 'Open', 'Read', 'ReadWrite,Delete')
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                if (-not $pos) { $null = $fs.Seek(0, 'End') } ; $pos = $fs.Position
                W 'log' "open pos=$pos"
            }
            while ($null -ne ($ln = $sr.ReadLine())) { W 'log' $ln }
            $pos = $fs.Position
        }
    } catch { W 'err' "log: $($_.Exception.Message)" }
    if ($tick++ % 4 -eq 0) {   # раз в 2 с
        try {
            if (-not $s) { $s = Connect-Session; $rt = Get-RiotRoute $s; W 'state' 'session ok' }
            $h = Get-GameHeaders $s $rt
            foreach ($e in @(@('pregame', "$($rt.Glz)/pregame/v1/players/$($s.Puuid)"), @('coregame', "$($rt.Glz)/core-game/v1/players/$($s.Puuid)"))) {
                $v = try { (Invoke-RestMethod $e[1] -Headers $h -TimeoutSec 4 | ConvertTo-Json -Compress) } catch { "HTTP $(Get-HttpCode $_)" }
                if ($last[$e[0]] -ne $v) { $last[$e[0]] = $v; W $e[0] $v }
            }
        } catch { $s = $null; if ($last.err -ne $_.Exception.Message) { $last.err = $_.Exception.Message; W 'err' "state: $($last.err)" } }
    }
    Start-Sleep -Milliseconds 500
}
