# build.ps1 — склеивает src\ в один файл dist\valset.cmd: bat-обёртка + весь PowerShell-код.
# Один файл удобно передавать: запускается двойным щелчком, не упирается в ExecutionPolicy,
# кодировку выставляет сборка (UTF-8 без BOM — BOM сломал бы bat-часть; PowerShell читает файл явно как UTF-8).
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
$out = Join-Path $PSScriptRoot 'dist\valset.cmd'

$body = foreach ($line in [IO.File]::ReadAllLines((Join-Path $src 'valset.ps1'), [Text.Encoding]::UTF8)) {
    if ($line -match "^\. \(Join-Path \`$PSScriptRoot '(.+\.ps1)'\)$") {
        "# ── модуль $($Matches[1]) ──"
        [IO.File]::ReadAllLines((Join-Path $src $Matches[1]), [Text.Encoding]::UTF8)
    } else {
        $line
    }
}

# Для cmd это строки до exit /b; для PowerShell — блочный комментарий <# ... #>.
$header = @(
    '<# :'
    '@echo off'
    'set "VALSET_FILE=%~f0"'
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:VALSET_FILE, [Text.Encoding]::UTF8))) %*"'
    'exit /b %errorlevel%'
    '#>'
)
$text = (@($header) + @($body)) -join "`r`n"

$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
if ($errors) { throw "Ошибка синтаксиса в сборке: $($errors[0].Message) (строка $($errors[0].Extent.StartLineNumber))" }
if ($text -match "(?m)^\. \(Join-Path") { throw 'В сборке остались подключения модулей.' }

New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
[IO.File]::WriteAllText($out, $text + "`r`n", (New-Object Text.UTF8Encoding $false))
'собрано: {0} ({1} строк, {2} КБ)' -f $out, ($text -split "`n").Count, [Math]::Round((Get-Item $out).Length / 1KB)

# Архив релиза: valset.cmd + короткая памятка + лицензия; рядом — SHA-256 для проверки скачанного.
# Имена файлов в архиве — латиницей: встроенный распаковщик Windows может исказить кириллицу.
$ver = ([regex]::Match($text, "(?m)^\`$Version = '(.+)'")).Groups[1].Value
if (-not $ver) { throw 'Не нашёл $Version в src\valset.ps1.' }
$stage = Join-Path $PSScriptRoot 'dist\release'
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $out, (Join-Path $PSScriptRoot 'LICENSE') $stage
$howto = @"
VALSET $ver — твои настройки VALORANT на всех твоих аккаунтах

1. Запусти valset.cmd двойным щелчком.
   Если Windows предупредит «Система Windows защитила ваш компьютер» —
   «Подробнее» → «Выполнить в любом случае» (файл скачан и не подписан;
   это обычный текстовый скрипт — можно открыть в Блокноте и прочитать).
2. VALSET предложит установиться — нажми Y. Дальше меню: Ctrl+Alt+V.
3. Войди в основной аккаунт → «Запомнить как мои».
   В другом аккаунте → «Перенести мои» (до запуска игры).

Справка внутри программы — клавиша ?. Неофициальная программа, Riot Games её не проверяла.

----------------------------------------------------------------------
VALSET $ver — your VALORANT settings on all your accounts

1. Run valset.cmd (double-click).
   If Windows says "Windows protected your PC" — "More info" → "Run anyway"
   (downloaded, unsigned file; it is a plain-text script you can read in Notepad).
2. VALSET offers to install — press Y. Then the menu is Ctrl+Alt+V.
3. Log into your main account → "Save as mine".
   On another account of yours → "Apply mine" (before launching the game).

Help inside the app — key ?. Unofficial tool, not reviewed by Riot Games.
"@
[IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $howto.Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding $true))
$zip = Join-Path $PSScriptRoot "dist\VALSET-$ver.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force
$sums = foreach ($f in $zip, $out) { '{0}  {1}' -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path $f -Leaf) }
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'dist\SHA256SUMS.txt'), [string[]]$sums)
'релиз: {0} ({1} КБ), SHA256SUMS.txt' -f $zip, [Math]::Round((Get-Item $zip).Length / 1KB)
