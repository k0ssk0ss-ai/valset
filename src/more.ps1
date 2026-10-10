# more.ps1 — экран «Ещё»: всё, что не нужно каждый день. После действия — назад на главный экран
# (он заново проверит аккаунт). Действия общие с главным экраном — Invoke-MenuAction (menu.ps1).

function Get-MoreItems($st) {
    $c = $st.Cfg
    $h = Read-Accounts
    $acc = @($h.Keys | ForEach-Object { "$(Get-AccountLabel $_) $(switch ("$($h[$_].state)") { 'same' { '√' } 'diff' { '‼' } default { '·' } })" }) -join '  '
    $on  = { param($v, $t) if ($v) { '• ' + $t } else { $t } }
    @(
        New-MenuSep (L 'ВРУЧНУЮ' 'MANUAL')
        if ($st.Have) { New-ApplyEntry $st }
        New-SaveEntry
        if ($st.Session -and (Test-Temp $st.Session.Puuid)) { New-MenuEntry (L 'Вернуть исходные' 'Restore originals') (L 'настройки аккаунта до твоего переноса' 'the account''s settings before your apply') 'untemp' }
        if ($st.Session -and (Get-Pros).Count) { New-MenuEntry (L 'Настройки про' 'Pro settings') (L 'примерить на время' 'try on for now') 'pros' }
        New-MenuSep (L 'VALSET' 'VALSET')
        New-MenuEntry (L 'Аккаунты' 'Accounts') $(if ($acc) { $acc } else { L 'пока пусто' 'empty so far' }) 'accounts'
        New-MenuEntry (L 'Уведомления' 'Notifications') '' '' @(
            New-MenuOpt (& $on $c.notify (L 'вкл' 'on')) 'notify-on' (L 'подскажет, если настройки разошлись' 'tells you when settings differ')
            New-MenuOpt (& $on (-not $c.notify) (L 'выкл' 'off')) 'notify-off' (L 'без уведомлений' 'no notifications'))
        New-MenuEntry (L 'Автоперенос' 'Auto-apply') '' '' @(
            New-MenuOpt (& $on $c.autoApply (L 'вкл' 'on')) 'auto-on' (L 'сам при входе, кроме основного' 'on login, except the main account')
            New-MenuOpt (& $on (-not $c.autoApply) (L 'выкл' 'off')) 'auto-off' (L 'переносить вручную' 'apply manually'))
        New-MenuEntry (L 'Бэкапы' 'Backups') '' '' @(
            New-MenuOpt (L 'аккаунта' 'account') 'restore' (L 'вернуть аккаунт как был до переноса' 'restore the account as it was before an apply')
            New-MenuOpt (L 'моих настроек' 'my settings') 'history' (L 'вернуть свои настройки к прошлой версии' 'restore your settings to an earlier version'))
        New-MenuEntry (L 'Справка' 'Help') (L 'как это работает · язык · папка' 'how it works · language · folder') 'help'
        New-MenuEntry (L 'Назад' 'Back') '' 'back'
    )
}

# Возвращает $true, если после действия ждать клавишу (как Invoke-MenuAction).
function Show-More($st) {
    $items = Get-MoreItems $st
    $i = Select-Item (L 'ЕЩЁ' 'MORE') $items -Header { Write-State $st }
    if ($i -lt 0) { return $false }
    $id = Get-EntryId $items[$i]
    if ($id -eq 'back') { return $false }
    $r = @(Invoke-MenuAction $id $st)
    [bool]$r[-1]
}
