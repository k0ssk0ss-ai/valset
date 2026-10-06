# accounts.ps1 — аккаунты по Riot ID: запоминаем каждый вход, основной аккаунт, последний статус настроек.
# accounts.json: { "<puuid>": { name: "Name#TAG", seen, checked, applied: "yyyy-MM-ddTHH:mm:ss", state: same|diff, diff: N, main: true } }

$AccountsPath = Join-Path $Root 'accounts.json'

function Get-Stamp { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }

function Read-Accounts {
    $h = @{}
    if (Test-Path $AccountsPath) {
        try {
            $o = Get-Content $AccountsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
        } catch {}
    }
    $h
}

function Save-Accounts([hashtable]$h) {
    New-Item -ItemType Directory -Force $Root | Out-Null
    $o = [ordered]@{}; foreach ($k in $h.Keys) { $o[$k] = $h[$k] }
    Set-Content $AccountsPath (ConvertTo-Json -InputObject ([pscustomobject]$o) -Depth 5) -Encoding UTF8
}

function Set-AccountState([string]$puuid, [hashtable]$fields) {
    if (-not $puuid) { return }
    $h = Read-Accounts
    $e = if ($h[$puuid]) { $h[$puuid] } else { [pscustomobject]@{} }
    foreach ($k in $fields.Keys) { $e | Add-Member -NotePropertyName $k -NotePropertyValue $fields[$k] -Force }
    $h[$puuid] = $e
    Save-Accounts $h
}

# Riot ID из локального клиента (без сети). $null — клиент не ответил.
function Get-RiotId($s) {
    try {
        $r = Invoke-RestMethod "https://127.0.0.1:$($s.Port)/player-account/aliases/v1/active" -Headers @{ Authorization = $s.Auth } -TimeoutSec 3
        if ($r.game_name) { return "$($r.game_name)#$($r.tag_line)" }
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
            Write-Screen (L 'АККАУНТЫ' 'ACCOUNTS')
            Write-Note (L 'пока пусто: аккаунт появится здесь, когда войдёшь в него при открытом VALSET или с автопереносом' 'empty so far: an account shows up here once you log into it with VALSET open or with auto-apply on')
            Wait-AnyKey; return
        }
        $items = @(foreach ($k in $keys) {
            $tags = @(); if ($k -eq $main) { $tags += (L 'основной' 'main') }; if ($k -ne $main -and $h[$k].own) { $tags += (L 'мой' 'mine') }; if ($s -and $s.Puuid -eq $k) { $tags += (L 'сейчас' 'current') }
            $label = "$(Get-AccountLabel $k)$(if ($tags) { " · $($tags -join ', ')" })"
            New-MenuEntry $label (Format-AccountState $h[$k]) $k
        })
        $gall = (Get-Config).gfxAll
        $items += New-MenuSep (L 'ГРАФИКА НА ЭТОМ ПК' 'GRAPHICS ON THIS PC')
        $gopt = New-MenuEntry (L 'Писать графику' 'Write graphics') '' '' @(
            New-MenuOpt $(if ($gall -eq $true) { '• ' + (L 'во все' 'to all') } else { L 'во все' 'to all' }) 'gfx-all' (L 'во все аккаунты этого ПК' 'to all accounts on this PC')
            New-MenuOpt $(if ($gall -eq $false) { '• ' + (L 'в текущий' 'current') } else { L 'в текущий' 'current' }) 'gfx-one' (L 'только в аккаунт, где ты сейчас' 'only the account you are on'))
        if ($gall -eq $false) { $gopt.Opt = 1 }
        $items += $gopt
        $i = Select-Item (L 'АККАУНТЫ' 'ACCOUNTS') $items $sel -Header {
            Write-Host (L '    перенос — только на аккаунт, в который вошёл в клиенте Riot' '    applying works only on the account you are logged into in the Riot Client') -ForegroundColor DarkGray
            Write-Host (L '    основной автоперенос не трогает: с него ты «Запоминаешь» свои настройки' '    auto-apply never touches the main account: that is where you “Save as mine”') -ForegroundColor DarkGray
        }
        if ($i -lt 0) { return }
        $sel = $i
        $gid = Get-EntryId $items[$i]
        if ($gid -in 'gfx-all', 'gfx-one') { Set-Config 'gfxAll' ($gid -eq 'gfx-all'); continue }
        $k = $items[$i].Id
        $acts = @(
            if ($k -ne $main) { New-MenuEntry (L 'Сделать основным' 'Make main') (L 'автоперенос перестанет его трогать' 'auto-apply will stop touching it') 'main' }
            if ($k -ne $main) {
                if ($h[$k].own) { New-MenuEntry (L 'Не мой аккаунт' 'Not my account') (L 'переносить на время, исходные возвращать' 'apply for now, restore the originals') 'notown' }
                else { New-MenuEntry (L 'Мой аккаунт' 'My account') (L 'переносить насовсем, без возврата исходных' 'apply permanently, no restore') 'own' }
            }
            New-MenuEntry (L 'Забыть' 'Forget') (L 'убрать из списка (появится снова при входе)' 'remove from the list (comes back on next login)') 'forget'
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
