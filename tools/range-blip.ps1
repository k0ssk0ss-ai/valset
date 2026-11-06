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
$name = 'VALSET-range-blip'
Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$t0 = Get-Date -Format 'HH:mm:ss.fff'
try {
    New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Program $exe.Path | Out-Null
    Write-Host "[$t0] сеть игре закрыта на $Seconds с"
    Start-Sleep -Seconds $Seconds
} finally {
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] сеть игре открыта (правило удалено)"
}
