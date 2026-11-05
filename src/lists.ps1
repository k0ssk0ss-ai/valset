# lists.ps1 — `valset list <pros|accounts|backups|history|diff|code:КОД|pro:НИК|loadouts|agents|loadout:ID|skins|skin:СПЕЦ>`: данные экранов консоли для панели приложения.
# Одна строка JSON-массив (UTF-8, без оформления); подписи уже на языке интерфейса и готовы к показу.

function ConvertTo-DiffItems($list) {
    @($list | Where-Object { $_ } | ForEach-Object { [ordered]@{ what = "$($_.What)"; old = "$($_.Old)"; new = "$($_.New)" } })
}

function Format-Num($v) { try { ([double]@($v)[0]).ToString('0.####', [Globalization.CultureInfo]::InvariantCulture) } catch { "$v" } }

# Нужен ли DPI мыши, чтобы пересчитать чувствительность про (в do: спросить нельзя — приложение задаёт set:dpi=N).
function Test-ProNeedsDpi($pro) {
    [bool]($pro.dpi -and (@($pro.prefs.floatSettings) | Where-Object { $_.settingEnum -eq $SensEnum }) -and (Get-Config).dpi -lt 100)
}

function Get-ListPros {
    $all = Get-Pros
    @($all | ForEach-Object {
        $sens = @($_.prefs.floatSettings) | Where-Object { $_.settingEnum -eq $SensEnum } | Select-Object -First 1
        $hint = @(
            if ($sens) { "$(L 'чувств.' 'sens') $(Format-Num $sens.value)" }
            if ($_.dpi) { "$($_.dpi) DPI" }
            if ($sens -and $_.dpi) { "eDPI $(Format-Num ($(try { [double]@($sens.value)[0] * [double]@($_.dpi)[0] } catch { 0 })))" }
            if ($_.crosshair) { L 'прицел' 'crosshair' }
        ) -join ' · '
        $retired = $_.PSObject.Properties['active'] -and -not $_.active
        [ordered]@{ nick = "$($_.nick)"; team = "$($_.team)"; label = (@($_.nick, $_.team, $(if ($retired) { L 'не играет' 'retired' })) | Where-Object { $_ }) -join ' · '; hint = $hint; needsDpi = (Test-ProNeedsDpi $_) }
    })
}

function Get-AccountActions([string]$k, $e, [string]$main) {
    @(
        if ($k -ne $main) { [ordered]@{ id = 'main'; label = (L 'Сделать основным' 'Make main') } }
        if ($k -ne $main -and $e.own) { [ordered]@{ id = 'notown'; label = (L 'Не мой аккаунт' 'Not my account') } }
        if ($k -ne $main -and -not $e.own) { [ordered]@{ id = 'own'; label = (L 'Мой аккаунт' 'My account') } }
        [ordered]@{ id = 'forget'; label = (L 'Забыть' 'Forget') }
    )
}

function Get-ListAccounts {
    $h = Read-Accounts; $main = Get-MainPuuid; $s = Get-Session
    $keys = @($h.Keys | Sort-Object @{ Expression = { if ($_ -eq $main) { 0 } else { 1 } } }, @{ Expression = { "$($h[$_].seen)" }; Descending = $true })
    @(foreach ($k in $keys) {
        $e = $h[$k]
        [ordered]@{ puuid = $k; name = (Get-AccountLabel $k); main = [bool]($k -eq $main); own = [bool]($k -ne $main -and $e.own)
                    current = [bool]($s -and $s.Puuid -eq $k); state = $(if ("$($e.state)" -in 'same', 'diff') { "$($e.state)" } else { '' })
                    checked = $(if ($e.checked) { Format-When $e.checked } else { '' }); status = (Format-AccountState $e)
                    actions = @(Get-AccountActions $k $e $main) }
    })
}

function Get-BackupFiles { @(Get-ChildItem $BackupDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15) }

function Get-ListBackups {
    $s = Get-Session; $me = if ($s) { Short $s.Puuid } else { '' }
    $files = Get-BackupFiles
    @(@($files | Where-Object { $_.BaseName.Split('_')[0] -eq $me }) + @($files | Where-Object { $_.BaseName.Split('_')[0] -ne $me }) | ForEach-Object {
        $acc = $_.BaseName.Split('_')[0]
        [ordered]@{ id = $_.BaseName; account = (Get-LabelByShort $acc); when = (Format-When $_.LastWriteTime); why = (L 'до переноса' 'before apply'); mine = [bool]($acc -eq $me) }
    })
}

function Get-ListHistory {
    $cur = if (Test-Path $ProfilePath) { Read-Profile } else { $null }
    @(Get-HistoryPoints | ForEach-Object {
        $same = $false
        if ($cur) { try { $same = Test-PrefsEqual $cur (Get-Content (Join-Path $_.Dir 'profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
        [ordered]@{ id = (Split-Path $_.Dir -Leaf); when = (Format-When $_.When); why = $_.Why; current = [bool]$same }
    })
}

function Get-ListDiff { ConvertTo-DiffItems (Get-MenuState 6>$null).DiffList }

function Get-ListJson([string]$kind) {
    # предпросмотр: code:<код> — вставка кода для друга (share.ps1), pro:<ник> — примерка про (pros.ps1)
    $items = if ($kind -match '^code:(.+)$') { Get-ListCode $Matches[1] } elseif ($kind -match '^pro:(.+)$') { Get-ListProPreview $Matches[1] } elseif ($kind -match '^loadout:(.+)$') { Get-ListLoadoutPreview $Matches[1] } elseif ($kind -match '^skin:(.+)$') { Get-ListSkinPreview $Matches[1] } elseif ($kind -match '^collection:(.+)$') { Get-ListCollection $Matches[1] } elseif ($kind -match '^coll:(.+)$') { Get-ListCollPreview $Matches[1] } else { switch ($kind) {
        'pros' { Get-ListPros } 'accounts' { Get-ListAccounts } 'backups' { Get-ListBackups }
        'history' { Get-ListHistory } 'diff' { Get-ListDiff } 'loadouts' { Get-ListLoadouts } 'agents' { Get-ListAgents } 'skins' { Get-ListSkins } 'collections' { Get-ListCollections }
        default { throw (L "неизвестный список: $kind" "unknown list: $kind") }
    } }
    ConvertTo-Json -InputObject @($items) -Depth 5 -Compress
}

function Write-ListJson([string]$kind) {
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
    Write-Output (Get-ListJson $kind)
}
