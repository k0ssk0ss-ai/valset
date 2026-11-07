# range-blip.ps1 — ЭКСПЕРИМЕНТ: на N секунд (по умолчанию 4) закрыть VALORANT выход в сеть, чтобы проверить,
# перечитает ли игра скины (CoreGame_FetchMatchLoadouts) при переподключении в стрельбище.
# Запускай САМ, от администратора (меняется правило брандмауэра на время работы; в finally оно удаляется).
# Работает только в стрельбище (последняя карта в ShooterGame.log — RangeV2) — в матче отказывается.
# Запуск (PowerShell от администратора):  powershell -ExecutionPolicy Bypass -File tools\range-blip.ps1 [-Seconds 4]
param([int]$Seconds = 4)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host 'Нужен PowerShell от администратора.'; exit 1 }
$log = Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Logs\ShooterGame.log'
$map = Select-String -Path $log -Pattern 'Map Name: (\w+)' | Select-Object -Last 1
if (-not $map -or $map.Matches[0].Groups[1].Value -ne 'RangeV2') { Write-Host 'Последняя карта не RangeV2 — отказ (только стрельбище).'; exit 1 }
$exe = Get-Process -Name 'VALORANT-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Write-Host 'Игра не запущена.'; exit 1 }
$prog = $exe.Path
if (-not $prog) {   # Ð¿ÑƒÑ‚ÑŒ Ð¿Ñ€Ð¾Ñ†ÐµÑÑÐ° Ð¿Ð¾Ð´ Ð·Ð°Ñ‰Ð¸Ñ‚Ð¾Ð¹ Vanguard Ð½Ðµ Ñ‡Ð¸Ñ‚Ð°ÐµÑ‚ÑÑ â€” Ð±ÐµÑ€Ñ‘Ð¼ Ð¸Ð· ÑƒÑÑ‚Ð°Ð½Ð¾Ð²ÐºÐ¸
    $y = Get-Content (Join-Path $env:ProgramData 'Riot Games\Metadata\valorant.live\valorant.live.product_settings.yaml') -ErrorAction SilentlyContinue | Select-String 'product_install_full_path:\s*"?([^"]+)"?' | Select-Object -First 1
    if ($y) { $prog = (Join-Path ($y.Matches[0].Groups[1].Value.Trim() -replace '/', '\') 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe') }
}
if (-not $prog -or -not (Test-Path $prog)) { Write-Host "ÐÐµ Ð½Ð°ÑˆÑ‘Ð» exe Ð¸Ð³Ñ€Ñ‹ ($prog)."; exit 1 }
$name = 'VALSET-range-blip'
Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$t0 = Get-Date -Format 'HH:mm:ss.fff'
try {
    New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Program $prog | Out-Null
    Write-Host "[$t0] сеть игре закрыта на $Seconds с"
    Start-Sleep -Seconds $Seconds
} finally {
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] сеть игре открыта (правило удалено)"
}
