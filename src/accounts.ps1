# accounts.ps1 — аккаунты по Riot ID: запоминаем каждый вход, основной аккаунт, последний статус настроек.
# accounts.json: { "<puuid>": { name: "Name#TAG", seen, checked, applied: "yyyy-MM-ddTHH:mm:ss", state: same|diff, diff: N, main: true } }

$AccountsPath = Join-Path $Root 'accounts.json'

function Get-Stamp { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }

function Read-Accounts {
    $h = @{}
    if (Test-Path $AccountsPath) {
        try {
            $o = Get-Content $AccountsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) {
                if ($p.Value.name) { $p.Value.name = Repair-Utf8 $p.Value.name }
                $h[$p.Name] = $p.Value
            }
        } catch {}
    }
    $h
}

function Save-Accounts([hashtable]$h) {
    New-Item -ItemType Directory -Force $Root | Out-Null
    $o = [ordered]@{}; foreach ($k in $h.Keys) { $o[$k] = $h[$k] }
    Write-FileSafe $AccountsPath (ConvertTo-Json -InputObject ([pscustomobject]$o) -Depth 5)
}

function Set-AccountState([string]$puuid, [hashtable]$fields) {
    if (-not $puuid) { return }
    $h = Read-Accounts
    $e = if ($h[$puuid]) { $h[$puuid] } else { [pscustomobject]@{} }
    foreach ($k in $fields.Keys) { $e | Add-Member -NotePropertyName $k -NotePropertyValue $fields[$k] -Force }
    $h[$puuid] = $e
    Save-Accounts $h
}

# Имена, сохранённые до 1.3.0, PowerShell 5.1 прочитал как Latin-1 («Ð Ð°Ð´Ð¸» вместо «Ради»): байты целы — переводим обратно.
function Repair-Utf8([string]$t) {
    if ($t -notmatch '[Â-ô][\u0080-¿]') { return $t }
    $fixed = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes($t))
    if ($fixed.Contains([char]0xFFFD)) { $t } else { $fixed }
}

# Riot ID из локального клиента (без сети). $null — клиент не ответил.
# Ответ без charset: Invoke-RestMethod в PowerShell 5.1 читал его как Latin-1 и портил кириллицу — декодируем UTF-8 сами.
function Get-RiotId($s) {
    # в lib: имя не меняется, пока тот же puuid (сеть 0,2 с)
    if ($script:Lib -and $script:RiotIdCache -and $script:RiotIdCache.Puuid -eq $s.Puuid) { return $script:RiotIdCache.Name }
    try {
        $w = Invoke-WebRequest "https://127.0.0.1:$($s.Port)/player-account/aliases/v1/active" -Headers @{ Authorization = $s.Auth } -TimeoutSec 3 -UseBasicParsing
        $r = [Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
        if ($r.game_name) { $n = "$($r.game_name)#$($r.tag_line)"; if ($script:Lib) { $script:RiotIdCache = @{ Puuid = $s.Puuid; Name = $n } }; return $n }
    } catch {}
    $null
}

# Запоминает вход; возвращает подпись аккаунта.
function Register-Account($s) {
    $name = Get-RiotId $s
    $f = @{ seen = (Get-Stamp) }
    if ($name) { $f.name = $name }
    Set-AccountState $s.Puuid $f
    if ($name) { $name } else { Get-AccountLabel $s.Puuid }
}

function Get-AccountLabel([string]$puuid) {
    if (-not $puuid) { return '—' }
    $e = (Read-Accounts)[$puuid]
    if ($e -and $e.name) { $e.name } else { Short $puuid }
}

# Подпись по первым 8 символам PUUID (так названы бэкапы).
function Get-LabelByShort([string]$short) {
    $h = Read-Accounts
    foreach ($k in $h.Keys) { if ($k.StartsWith($short) -and $h[$k].name) { return $h[$k].name } }
    $short
}

# Основной — отмеченный явно, иначе тот, с которого запомнены мои настройки.
function Get-MainPuuid {
    $h = Read-Accounts
    foreach ($k in $h.Keys) { if ($h[$k].main) { return $k } }
    Get-Source
}

function Set-MainAccount([string]$puuid) {
    $h = Read-Accounts
    foreach ($k in @($h.Keys)) { $h[$k] | Add-Member -NotePropertyName main -NotePropertyValue ($k -eq $puuid) -Force }
    Save-Accounts $h
    Log "основной аккаунт: $(Get-AccountLabel $puuid)"
}

function ConvertFrom-Stamp([string]$s) {
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact("$s", 'yyyy-MM-ddTHH:mm:ss', $null, 'None', [ref]$d)) { $d } else { $null }
}

# «сегодня 23:12», «вчера 23:12», «05.10 23:12».
function Format-When($d) {
    if ($d -is [string]) { $d = ConvertFrom-Stamp $d }
    if (-not $d) { return '—' }
    $days = ((Get-Date).Date - $d.Date).Days
    $day = switch ($days) { 0 { L 'сегодня' 'today' } 1 { L 'вчера' 'yesterday' } default { $d.ToString('dd.MM') } }
    "$day $($d.ToString('HH:mm'))"
}

function Format-AccountState($e) {
    switch ("$($e.state)") {
        'same'  { "√ $(L 'совпадают' 'match') · $(Format-When $e.checked)" }
        'diff'  { "‼ $(L 'отличий' 'differences'): $($e.diff) · $(Format-When $e.checked)" }
        default { L 'ещё не проверялся' 'not checked yet' }
    }
}

# Экран «Аккаунты»: все, на которые входил при VALSET. Переносить можно только на тот, в который вошёл сейчас.
function Show-Accounts {
    $sel = 0
    while ($true) {
        $h = Read-Accounts
        $main = Get-MainPuuid
        $s = Get-Session
        $keys = @($h.Keys | Sort-Object @{ Expression = { if ($_ -eq $main) { 0 } else { 1 } } }, @{ Expression = { "$($h[$_].seen)" }; Descending = $true })
        if (-not $keys) {
            Write-Screen (L 'Аккаунты' 'Accounts')
            Write-Note (L 'Пока пусто. Аккаунт появится здесь, когда ты войдёшь в него при открытом VALSET или с автопереносом' 'Empty so far. An account shows up here once you log into it with VALSET open or with auto-apply on')
            Wait-AnyKey; return
        }
        $items = @(foreach ($k in $keys) {
            $tags = @(); if ($k -eq $main) { $tags += (L 'основной' 'main') }; if ($k -ne $main -and $h[$k].own) { $tags += (L 'мой' 'mine') }; if ($s -and $s.Puuid -eq $k) { $tags += (L 'сейчас' 'current') }
            $label = "$(Get-AccountLabel $k)$(if ($tags) { " · $($tags -join ', ')" })"
            New-MenuEntry $label (Format-AccountState $h[$k]) $k
        })
        $gall = (Get-Config).gfxAll
        $items += New-MenuSep (L 'Графика на этом ПК' 'Graphics on this PC')
        $gopt = New-MenuEntry (L 'Писать графику' 'Write graphics') '' '' @(
            New-MenuOpt $(if ($gall -eq $true) { '• ' + (L 'во все' 'to all') } else { L 'во все' 'to all' }) 'gfx-all' (L 'во все аккаунты этого ПК' 'to all accounts on this PC')
            New-MenuOpt $(if ($gall -eq $false) { '• ' + (L 'в текущий' 'current') } else { L 'в текущий' 'current' }) 'gfx-one' (L 'только в аккаунт, где ты сейчас' 'only the account you are on'))
        if ($gall -eq $false) { $gopt.Opt = 1 }
        $items += $gopt
        $i = Select-Item (L 'Аккаунты' 'Accounts') $items $sel -Header {
            Write-Host (L '    Переносить можно только на аккаунт, в который ты вошёл' '    You can apply only to the account you are logged into') -ForegroundColor DarkGray
            Write-Host (L '    Основной аккаунт автоперенос не меняет. С него ты сохраняешь свои настройки' '    Auto-apply never changes the main account. That is where you save yours') -ForegroundColor DarkGray
        }
        if ($i -lt 0) { return }
        $sel = $i
        $gid = Get-EntryId $items[$i]
        if ($gid -in 'gfx-all', 'gfx-one') { Set-Config 'gfxAll' ($gid -eq 'gfx-all'); continue }
        $k = $items[$i].Id
        $acts = @(
            if ($k -ne $main) { New-MenuEntry (L 'Сделать основным' 'Make main') (L 'автоперенос перестанет его менять' 'auto-apply will stop changing it') 'main' }
            if ($k -ne $main) {
                if ($h[$k].own) { New-MenuEntry (L 'Не мой аккаунт' 'Not my account') (L 'переносить на время, исходные вернутся' 'apply for now, the originals come back') 'notown' }
                else { New-MenuEntry (L 'Мой аккаунт' 'My account') (L 'переносить насовсем' 'apply permanently') 'own' }
            }
            New-MenuEntry (L 'Забыть' 'Forget') (L 'убрать из списка (вернётся при входе)' 'remove from the list (comes back on next login)') 'forget'
        )
        $j = Select-Item (Get-AccountLabel $k).ToUpper() $acts
        if ($j -lt 0) { continue }
        switch ($acts[$j].Id) {
            'main'   { Set-MainAccount $k }
            'own'    { Set-AccountState $k @{ own = $true } }
            'notown' { Set-AccountState $k @{ own = $false } }
            'forget' { $h.Remove($k); Save-Accounts $h; Log "аккаунт забыт: $(Short $k)" }
        }
    }
}
